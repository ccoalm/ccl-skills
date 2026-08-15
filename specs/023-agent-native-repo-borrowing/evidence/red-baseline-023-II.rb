#!/usr/bin/env ruby
# frozen_string_literal: true
# RED-baseline differential probe for spec 023 batch II (advisory evidence; committed under specs/023 evidence).
# Same method as red-baseline-023-I.rb: immutable base/head SHAs resolved before any model call, argv git,
# abort on any read failure or dirty skills tree, sha256 of every prompt input recorded, raw answers kept.
require "json"; require "open3"; require "timeout"; require "tmpdir"; require "digest"
WT = ARGV[0] or abort "usage: red-baseline-023-II.rb <worktree> [rounds] [model] [base-rev] [head-rev]"
ROUNDS = (ARGV[1] || "4").to_i
MODEL = ARGV[2] || "claude-haiku-4-5"
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
  { id: "td-session-vantage", skill: "tighten-doc", refs: ["session-vantage-leakage.md"],
    task: "请审阅并优化下面这段将要写进模块 README 的文字（给出改后文本 + 每处修改的理由）：\n\n「This module used to parse config through the legacy loader (see design §4.7 and decision 7); after PR #212 it no longer does. The cast below is safe — it simply narrows the type, as the reviewer confirmed in round 3. Probably fine for now.」",
    required: [/decision 7|§4\.7|设计会话|会话|design ledger|PR #212|reviewer|评审|round 3|轮/i, /现在|当前|现状|present|改写|重述|HEAD/i, /TODO|界限|hedge|probably|以后|标记/i],
    why: "新规则：识别死引用/PR 视角/评审编排/辩护注释/hedge，改写为现状陈述而非只删" },
  { id: "prd-enforcement-review", skill: "product-rd-workflow", refs: ["code-review-checklist.md"],
    task: "评审一个 agent 工具 PR：新增 `delete_branch(name)` 工具；作者在系统提示里写了「绝不对 main 调用」，并把 schema 描述里的 main 选项删掉了；工具执行器本身没有任何检查。同时工具描述里加了一句「通过 GitOpsPlugin 的 gRPC transport 执行」。给评审结论。",
    required: [/执行器|executor|执行层|执行时|运行时检查|绕过|bypass|直接调用/i, /prompt|提示|schema/i, /transport|plugin|gRPC|实现细节|实现词汇|模型.{0,6}(不需要|无关)/i],
    why: "新规则：拒绝路径要在执行器测（prompt/schema 不是权限边界）；模型视角评审剔除实现词汇" },
  { id: "dd-postmortem-criteria", skill: "defect-diagnosis", refs: [],
    task: "背景：CI 单测全绿，但产品一启动它的自动化 server 就崩；根因是一个插件用了 default export，加载器因此丢掉了它声明的依赖注入。已修好。问：这个 bug 值不值得写一份正式 postmortem？依据什么判？如果写，开头必须有什么、结尾必须链接什么？",
    required: [/subtle|systemic|costly|微妙|非显然|系统性|重新发现|再发现|代价|工具.{0,4}缺口|测试.{0,4}缺口/i, /执行摘要|executive|30 秒|三十秒|开头|一段话/i, /guardrail|护栏|回链|链接|测试|规则|决策记录/i],
    why: "新规则：subtle+systemic+costly 三判据；30 秒执行摘要；回链催生的 guardrail" },
]

def ask(prompt)
  out = +""
  Dir.mktmpdir("rb023") do |neutral|
    Timeout.timeout(180) do
      Open3.popen3("claude", "--print", "--tools", "", "--model", MODEL, chdir: neutral) do |i, o, e, t|
        i.write(prompt); i.close; out << o.read; e.read; t.value
      end
    end
  end
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
puts JSON.pretty_generate({ model: MODEL, rounds: ROUNDS, base_rev: BASE_SHA, head_rev: HEAD_SHA, results: results })
