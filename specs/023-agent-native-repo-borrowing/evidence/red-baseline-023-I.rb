#!/usr/bin/env ruby
# frozen_string_literal: true
# RED-baseline differential probe for spec 023 batch I (advisory evidence; committed under specs/023 evidence).
# Arms: base = the SKILL.md (+ one reference) at an immutable BASE revision; head = the same files at an
# immutable HEAD revision (both resolved to commit SHAs before any model call and recorded in the output,
# together with a sha256 of every prompt input). Same task, same model, keyword-contract grading (the repo's
# own accepted approach; a compliant paraphrase can read as a miss — raw answers are kept for re-grading).
# Any git read failure aborts before grading; nothing is graded against an empty or mismatched input.
require "json"; require "open3"; require "timeout"; require "tmpdir"; require "digest"
WT = ARGV[0] or abort "usage: red-baseline-023-I.rb <worktree> [rounds] [model] [base-rev] [head-rev]"
ROUNDS = (ARGV[1] || "3").to_i
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
def blob(sha, path) = git!("show", "#{sha}:#{path}")
def arm_body(sha, skill, ref)
  strip_fm(blob(sha, "skills/#{skill}/SKILL.md")) + "\n\n---\n# reference: #{ref}\n" + blob(sha, "skills/#{skill}/references/#{ref}")
end

PROBES = [
  { id: "ts-verify-world", skill: "testing-strategy", ref: "e2e-real-flow-testing.md",
    task: "一个自动化 agent 报告：『已执行部署脚本并写入 release-2026.log 记录成功』。请设计验收断言，证明它确实完成了部署。只给断言设计，不写实现。",
    required: [/自述|self-report|自己写|自写|它写的|agent 输出|agent 的输出|agent 报告|self report/i, /权威|authoritative|部署目标|目标环境|健康|独立|外部/, /重跑|重新执行|再跑|再次执行|再执行|重新运行|re-?run|幂等|idempot|副作用|side.?effect|mutat/i],
    why: "新规则：观测权威外部状态、agent 自写日志不算证据、不用重跑有副作用命令来验证" },
  { id: "llm-withkey-skip", skill: "llm-inference-integration", ref: "model-prompt-evaluation.md",
    task: "我们的发布 CI 没有配置模型 API key，with-key 的真实模型 e2e/smoke 套件全部 self-skip，job 显示绿色；keyless 单测和 replay 全绿。产品负责人问：可以据此宣称这次发布的 agent 功能验收通过、可以上线吗？给结论和理由。",
    required: [/skip.{0,12}(不算|不是|不等于|≠|不能视为|not run|未运行|未执行|没有运行|没跑)|self-skip.{0,20}(不|未)|跳过.{0,10}(不算|不等于|不是|不能|≠)/i, /凭证|credential|key|真实模型|real model|with-key/i, /不能|不可|不得|不足以|不应/],
    why: "新规则：skipped with-key = not run，不能支撑验收/上线声明；需要有凭证的 job 真跑过组装产品 smoke" },
  { id: "llm-wording", skill: "llm-inference-integration", ref: "agent-instruction-composition.md",
    task: "评审一个 PR：它把一个文件搜索工具的 schema 描述从「Search files under the current workspace root; `scope` is one of `workspace|selection|open-editors`」改成「Search files via the FsIndexPlugin over the LSP transport; `scope` selects the renderer panel」，并把参数校验失败时返回给模型的诊断改成「unknown scope; try again」。给评审结论。",
    required: [/plugin|transport|renderer|实现细节|实现词汇|传输/i, /scope|枚举|判别|允许值|allowed|enum/i, /快照|snapshot|replay|eval|评测|行为变更|行为/i],
    why: "新规则：剔除实现词汇 + 保留契约判别词与允许值 + 措辞即行为需证据" },
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
  arms = { "base" => { sha: BASE_SHA, body: arm_body(BASE_SHA, p[:skill], p[:ref]) },
           "head" => { sha: HEAD_SHA, body: arm_body(HEAD_SHA, p[:skill], p[:ref]) } }
  results[p[:id]] = { task_sha256: Digest::SHA256.hexdigest(p[:task]), required: p[:required].map(&:source) }
  arms.each do |arm, a|
    prompt = "以下是当前生效的技能规则（SKILL.md 正文 + 一份参考）。严格按其中规则回答任务。\n\n=====SKILL=====\n#{a[:body]}\n=====TASK=====\n#{p[:task]}"
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
