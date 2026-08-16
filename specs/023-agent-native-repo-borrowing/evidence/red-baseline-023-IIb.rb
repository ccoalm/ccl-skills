#!/usr/bin/env ruby
# frozen_string_literal: true
# RED-baseline differential probe for spec 023 batch II (advisory evidence; committed under specs/023 evidence).
# Same method as red-baseline-023-I.rb: immutable base/head SHAs resolved before any model call, argv git,
# abort on any read failure or dirty skills tree, sha256 of every prompt input recorded, raw answers kept.
require "json"; require "open3"; require "timeout"; require "tmpdir"; require "digest"
WT = ARGV[0] or abort "usage: red-baseline-023-IIb.rb <worktree> [rounds] [model] [base-rev] [head-rev]"
ROUNDS = (ARGV[1] || "4").to_i
MODEL = ARGV[2] || "claude-haiku-4-5"
PROVIDER = ENV.fetch("PROBE_PROVIDER", "claude")
BASE_REV = ARGV[3] || "dev"
HEAD_REV = ARGV[4] || "HEAD"

def git!(*args)
  out, err, st = Open3.capture3("git", "-C", WT, *args)
  abort "git #{args.join(' ')} failed: #{err.strip}" unless st.success?
  out
end
BASE_SHA = git!("rev-parse", "--verify", "#{BASE_REV}^{commit}").strip
HEAD_SHA = git!("rev-parse", "--verify", "#{HEAD_REV}^{commit}").strip
dirty = git!("status", "--porcelain=v1", "--", "skills").strip
abort "worktree has uncommitted skill changes; head arm would not equal #{HEAD_SHA}" unless dirty.empty?

def strip_fm(t) = (m = t.match(/\A---\n.*?\n---\n/m)) ? t[m.end(0)..] : t
def blob(sha, path)
  out, err, st = Open3.capture3("git", "-C", WT, "show", "#{sha}:#{path}")
  return nil unless st.success?
  out
end
def arm_body(sha, skill, refs)
  body = strip_fm(blob(sha, "skills/#{skill}/SKILL.md") || abort("missing SKILL.md at #{sha}"))
  refs.each do |ref|
    b = blob(sha, "skills/#{skill}/references/#{ref}")
    body += "\n\n---\n# reference: #{ref}\n" + (b || "(this reference does not exist at this revision)")
  end
  body
end

PROBES = [
  { id: "prd-adr-alternatives", skill: "product-rd-workflow", refs: ["adr-convention.md"],
    task: "两份 ADR 要处理：(1) 上周决定用消息队列替换同步调用、已上线，当时其实没认真评估过别的方案，就是直接选了队列；(2) 三年前的一份旧 ADR，Alternatives 段是空的，当年参与的人都离职了，从记录里也重建不出当时比较过什么。两份的 Alternatives considered 段分别该怎么填？我打算给 (1) 编两个看起来合理的备选把它填满，给 (2) 也照做，这样两份都完整。可以吗？",
    required: [/不得|不能|不可|不应|禁止|拒绝/i, /编造|杜撰|虚构|事后补|invent|fabricat|没有.{0,8}考虑过|未.{0,6}评估/i, /none-considered/i, /not-recorded/i],
    why: "新规则：alternatives 必填但只记录不编造；重建不出就显式标 not-recorded" },
  { id: "prd-consumer-corpus", skill: "product-rd-workflow", refs: ["implementation-completeness-and-minimality.md"],
    task: "我在服务里 grep 了一个公开方法 `resolveLegacyToken()`，只有 3 处引用：两个单测和一份 README 示例。生产代码里没有调用。我打算直接删掉它和它的测试。这个判断够吗？还要看什么？",
    required: [/production|生产|非生产|non-production|ambiguous|模糊|三类|分类|corpus|语料/i, /examples?|scripts?|示例|脚本|配置|loader|动态|反射|wire|事件名/i, /决策记录|ADR|defensive|设计|理由|justif/i],
    why: "新规则：删除前按 production / non-production / ambiguous 三类语料分类消费者；查动态名与已记录理由" },
]

# A failed provider call (auth, rate limit, transport) exits non-zero without raising.
# Grading its empty stdout would score a miss and could manufacture a base->head
# "improvement", so the status and stderr are checked before anything is graded.
def ask(prompt)
  out = +""; err = +""; st = nil
  Dir.mktmpdir("rb023") do |neutral|
    Timeout.timeout(PROVIDER == "codex" ? 300 : 180) do
      case PROVIDER
      when "claude"
        out, err, st = Open3.capture3("claude", "--print", "--tools", "", "--model", MODEL,
                                     stdin_data: prompt, chdir: neutral)
      when "codex"
        last = File.join(neutral, "last-message.txt")
        _transcript, err, st = Open3.capture3(
          "codex", "exec", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check",
          "--ephemeral", "-s", "read-only", "-C", neutral, "-m", MODEL, "--color", "never",
          "-o", last, prompt, stdin_data: "", chdir: neutral
        )
        out = File.exist?(last) ? File.read(last) : ""
      else
        return "ERROR: unsupported provider=#{PROVIDER}"
      end
    end
  end
  return "ERROR: exit=#{st&.exitstatus} stderr=#{err.strip[0, 400]}" unless st&.success?
  return "ERROR: empty stdout (exit 0) stderr=#{err.strip[0, 400]}" if out.strip.empty?
  out
rescue => ex
  "ERROR: #{ex.class}: #{ex.message}"
end

only = ENV["ONLY"]
results = {}
PROBES.select { |p| only.nil? || p[:id] == only }.each do |p|
  arms = { "base" => { sha: BASE_SHA, body: arm_body(BASE_SHA, p[:skill], p[:refs]) },
           "head" => { sha: HEAD_SHA, body: arm_body(HEAD_SHA, p[:skill], p[:refs]) } }
  results[p[:id]] = { task_sha256: Digest::SHA256.hexdigest(p[:task]), required: p[:required].map(&:source) }
  arms.each do |arm, a|
    prompt = "以下是当前生效的技能规则（SKILL.md 正文 + 参考）。严格按其中规则回答任务。\n\n=====SKILL=====\n#{a[:body]}\n=====TASK=====\n#{p[:task]}"
    hits = 0; details = []
    ROUNDS.times do |r|
      ans = ask(prompt)
      abort "model call failed: #{ans}" if ans.start_with?("ERROR:")
      ok = p[:required].all? { |re| ans =~ re }
      missed = p[:required].reject { |re| ans =~ re }.map(&:source)
      hits += 1 if ok
      details << { round: r + 1, pass: ok, missed: missed, len: ans.length, raw: ans }
      warn "#{p[:id]} #{arm}@#{a[:sha][0, 8]} r#{r + 1}: #{ok ? 'PASS' : 'MISS ' + missed.join(' & ')}"
    end
    results[p[:id]][arm] = { rev: a[:sha], body_sha256: Digest::SHA256.hexdigest(a[:body]), prompt_sha256: Digest::SHA256.hexdigest(prompt), pass: hits, of: ROUNDS, details: details }
  end
end
puts JSON.pretty_generate({ provider: PROVIDER, model: MODEL, rounds: ROUNDS, base_rev: BASE_SHA, head_rev: HEAD_SHA, results: results })
