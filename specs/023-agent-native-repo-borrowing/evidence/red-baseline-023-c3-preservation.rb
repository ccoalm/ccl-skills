#!/usr/bin/env ruby
# frozen_string_literal: true

# Round-scoped preservation probe for the C3 repair. Advisory only: it compares
# immutable base/head skill bodies and an applied guard-removal mutant, retaining
# raw answers and deterministic grader misses for independent inspection.
require "digest"
require "json"
require "open3"
require "timeout"
require "tmpdir"

REFRESH_OPT_IN = "CCL_C3_ALLOW_MODEL_REFRESH"
abort "model-dependent C3 evidence refresh disabled; rerun with #{REFRESH_OPT_IN}=1 after explicit provider authorization" unless ENV[REFRESH_OPT_IN] == "1"

WT = ARGV[0] or abort "usage: red-baseline-023-c3-preservation.rb <worktree> [rounds] [model] [base-rev] [head-rev]"
ROUNDS = (ARGV[1] || "2").to_i
MODEL = ARGV[2] || "claude-haiku-4-5"
BASE_REV = ARGV[3] || "dev"
HEAD_REV = ARGV[4] || "HEAD"

def git!(*args)
  out, err, status = Open3.capture3("git", "-C", WT, *args)
  abort "git #{args.join(' ')} failed: #{err.strip}" unless status.success?
  out
end

BASE_SHA = git!("rev-parse", "--verify", "#{BASE_REV}^{commit}").strip
HEAD_SHA = git!("rev-parse", "--verify", "#{HEAD_REV}^{commit}").strip
abort "worktree has uncommitted skill changes" unless git!("status", "--porcelain=v1", "--", "skills").strip.empty?

def blob(sha, path)
  out, err, status = Open3.capture3("git", "-C", WT, "show", "#{sha}:#{path}")
  abort "git show #{sha}:#{path} failed: #{err.strip}" unless status.success?
  out
end

def strip_frontmatter(text)
  match = text.match(/\A---\n.*?\n---\n/m)
  match ? text[match.end(0)..] : text
end

def body(sha, skill, reference, reference_expected: true)
  skill_body = strip_frontmatter(blob(sha, "skills/#{skill}/SKILL.md"))
  return skill_body unless reference

  reference_path = "skills/#{skill}/references/#{reference}"
  unless reference_expected
    present = git!("ls-tree", "--name-only", sha, "--", reference_path).strip
    abort "expected #{sha}:#{reference_path} to be absent" unless present.empty?
    return skill_body
  end

  "#{skill_body}\n\n---\n# reference: #{reference}\n#{blob(sha, reference_path)}"
end

def ask(prompt)
  output = error = +""
  status = nil
  Dir.mktmpdir("c3-preservation") do |dir|
    Timeout.timeout(300) do
      output, error, status = Open3.capture3(
        "claude", "--print", "--safe-mode", "--tools", "", "--model", MODEL,
        stdin_data: prompt, chdir: dir
      )
    end
  end
  abort "model call failed: exit=#{status&.exitstatus} #{error.strip[0, 400]}" unless status&.success?
  abort "model call returned empty output" if output.strip.empty?
  output
end

def tighten_grade(answer)
  required = {
    "dead-session" => /死.{0,8}(?:会话|设计)/im,
    "pr-stack" => /(?:stack.{0,8}PR|PR.{0,8}(?:stack|视角|堆叠))/im,
    "change-and-unanchored" => /变更叙事.{0,120}(?:指示|时间戳|无锚点)|(?:指示|时间戳|无锚点).{0,120}变更叙事/im,
    "review-choreography" => /评审编排/im,
    "defense" => /辩护/im,
    "derivation-ledger" => /推导(?:流水账|过程|叙述)/im,
    "hedge" => /hedge/im,
    "working-language" => /工作语言/im,
    "stable-version" => /apiVersion: v2/im,
    "issue" => /issue #42/im,
    "measurement" => /p95=120ms/im
  }
  misses = required.filter_map { |name, pattern| name unless answer.match?(pattern) }
  misses << "keep-markers" unless answer.match?(/保留|keep/i)
  misses
end

def worktree_grade(answer)
  misses = []
  lines = answer.lines.map(&:strip)
  fetch_lines = lines.select { |line| line.match?(/\bgit fetch\b/) }
  push_command = /\bgit push\b.*--force-with-lease=mybr:["']?\$remote_oid["']?/
  push_index = lines.index { |line| line.match?(push_command) } || lines.length
  target_fetch = /\Agit fetch(?:\s+-\S+)*\s+origin(?:\s+(?:refs\/heads\/)?main(?::refs\/remotes\/origin\/main)?)?\z/
  misses << "target-refresh" unless lines.any? { |line| line.match?(target_fetch) }
  branch_fetch = /git fetch(?:\s+-\S+)*\s+origin\s+(?:refs\/heads\/)?mybr(?:\s|$|:)/
  pre_push_branch_fetches = lines[0...push_index].count { |line| line.match?(branch_fetch) }
  misses << "one-branch-fetch-before-push" unless pre_push_branch_fetches == 1
  misses << "initial-branch-fetch" unless fetch_lines.any? { |line| line.match?(branch_fetch) }
  misses << "literal-fetch-head-oid" unless answer.match?(/remote_oid=\$?\(git rev-parse FETCH_HEAD\)/)
  topology = /git rev-list --left-right --count ["']?mybr["']?\.\.\.["']?\$remote_oid["']?(?:`|\s|$)/
  topology_index = lines.index { |line| line.match?(topology) } || lines.length
  misses << "exact-topology-command" unless topology_index < lines.length
  malformed_topology = lines.any? do |line|
    line.include?("git rev-list --left-right") && !line.match?(topology)
  end
  misses << "no-malformed-topology-command" if malformed_topology
  right_zero_stop = /右侧.{0,20}(?:须|必须|要).{0,8}0|右侧.{0,20}(?:非\s*0|>\s*0).{0,30}(?:停|禁.*rebase|先.*(?:merge|并入))/im
  right_stop_index = lines.index { |line| line.match?(right_zero_stop) } || lines.length
  rebase_index = lines.index { |line| line.match?(/\Agit rebase origin\/main(?:\s|$)/) } || lines.length
  misses << "right-zero-stop" unless right_stop_index < lines.length
  misses << "rebase-after-check" unless rebase_index < lines.length && topology_index < rebase_index && right_stop_index < rebase_index
  misses << "explicit-oid-lease" unless answer.match?(/--force-with-lease=mybr:["']?\$remote_oid["']?/)
  post_push_lines = push_index < lines.length ? lines[(push_index + 1)..] : []
  misses << "post-push-fetch" unless post_push_lines.any? { |line| line.match?(branch_fetch) }
  revalidation_index = lines.each_index.find do |index|
    index > push_index && lines[index].match?(/失效证据|重新(?:检查|核验|评审)|重审|revalidat|refresh.{0,20}(?:review|CI)/i)
  end
  revalidation_block = revalidation_index ? lines[revalidation_index, 8].join("\n") : ""
  state_patterns = {
    "approval" => /\bapproval\b|批准|审批/i,
    "mergeable" => /\bmergeable\b|可合并/i,
    "CI" => /\bCI\b|持续集成/i,
    "commit" => /\bcommit(?:\s+hash)?\b|提交哈希/i,
    "thread" => /\bthread\b|评审线程/i,
    "line-anchor" => /行锚|行内评论.{0,12}锚|inline.{0,20}anchor/i
  }
  state_patterns.each do |token, pattern|
    misses << "review-state-#{token}" unless revalidation_block.match?(pattern)
  end
  misses
end

PROBES = [
  {
    id: "tighten-eight-class-walk",
    skill: "tighten-doc",
    reference: "session-vantage-leakage.md",
    task: <<~TASK,
      只输出两节，不写前言或总结。第一节是一张恰好 8 行的 Markdown 表格，逐类覆盖技能定义的 8 类会话视角泄漏，每类一行，不得合并；类别名可用入口短名或参考页全名。第二节标题为“保留”，逐项列出仍应保留的事实。审阅这段 README 草稿：
      「本轮按 design §4.7 的 decision 7，在 stacked PR #212 之后把旧 loader 改掉；today 这个 cut 已经够了。这个 cast 显然安全，reviewer 在 round 3 也确认过。推导过程是 A→B→C，probably fine，暂定先这样。当前契约是 apiVersion: v2；issue #42 记录兼容原因；实测 p95=120ms。」
      “保留”节必须原样写出 apiVersion: v2、issue #42、p95=120ms；先重述保留事实，再删除过程。
    TASK
    grader: method(:tighten_grade),
    mutate: lambda do |text|
      text.lines.reject { |line| line.start_with?("12. 会话视角泄漏：") }.join
    end,
    mutant_reference: nil,
    mutation: "remove DELETE #12, which removes the only load path to its canonical reference"
  },
  {
    id: "worktree-one-fetch-order",
    skill: "worktree-isolation",
    reference: "shared-branch-rebase.md",
    base_reference: false,
    task: <<~TASK,
      已推送分支 mybr 挂着 MR 和 review 评论，要 rebase 到 origin/main 后更新远端。只输出一个 bash 代码块，再输出一行“失效证据”列表。代码块必须按技能顺序逐行给出：刷新目标、只 fetch 一次 mybr（选择不更新 tracking ref 的形式）、立刻保存 $remote_oid、完整拓扑命令和右侧非 0 的停止注释、rebase、显式 OID lease push、push 后 fetch。命令必须使用 mybr、origin/main 和变量 $remote_oid，不得用占位符或替代拓扑命令；拓扑命令把技能模板的 `<branch>` 替换为 mybr，左侧不得写 origin/main；“失效证据”逐项复制技能列出的全部状态，不得省略、合并或改名。
    TASK
    grader: method(:worktree_grade),
    mutate: lambda do |text|
      text.lines.map do |line|
        if line.start_with?("- **已推送 / 挂着 MR / 别人可能在上面工作的分支**：")
          "- **已推送 / 挂着 MR / 别人可能在上面工作的分支**：rebase 后用 `--force-with-lease` 推送。\n"
        else
          line
        end
      end.join
    end,
    mutant_reference: nil,
    mutation: "replace the sole action/stop sequence and withhold its guard reference"
  }
]

selected = PROBES.select { |probe| ENV["ONLY"].nil? || ENV["ONLY"] == probe[:id] }
selected_arm_names = (ENV["ARMS"] || "base,head,mutant").split(",").map(&:strip).reject(&:empty?)
unknown_arms = selected_arm_names - %w[base head mutant]
abort "unknown ARMS: #{unknown_arms.join(',')}" unless unknown_arms.empty?
abort "ARMS selected no arms" if selected_arm_names.empty?
results = {}
selected.each do |probe|
  base_body = body(BASE_SHA, probe[:skill], probe[:reference], reference_expected: probe.fetch(:base_reference, true))
  head_body = body(HEAD_SHA, probe[:skill], probe[:reference])
  mutant_skill = probe[:mutate].call(strip_frontmatter(blob(HEAD_SHA, "skills/#{probe[:skill]}/SKILL.md")))
  mutant_body = if probe[:mutant_reference]
                  "#{mutant_skill}\n\n---\n# reference: #{probe[:mutant_reference]}\n#{blob(HEAD_SHA, "skills/#{probe[:skill]}/references/#{probe[:mutant_reference]}")}"
                else
                  mutant_skill
                end
  arms = { "base" => base_body, "head" => head_body, "mutant" => mutant_body }
  result = { task_sha256: Digest::SHA256.hexdigest(probe[:task]), mutation: probe[:mutation] }
  arms.each do |arm, skill_body|
    next unless selected_arm_names.include?(arm)

    prompt = "以下是当前生效的技能正文与已加载参考。严格按它回答任务。\n\n=====SKILL=====\n#{skill_body}\n=====TASK=====\n#{probe[:task]}"
    details = []
    ROUNDS.times do |round|
      answer = ask(prompt)
      misses = probe[:grader].call(answer)
      details << {
        round: round + 1, pass: misses.empty?, missed: misses,
        answer_sha256: Digest::SHA256.hexdigest(answer), len: answer.length, raw: answer
      }
      warn "#{probe[:id]} #{arm} r#{round + 1}: #{misses.empty? ? 'PASS' : 'MISS ' + misses.join(',')}"
    end
    result[arm] = {
      rev: arm == "base" ? BASE_SHA : HEAD_SHA,
      body_sha256: Digest::SHA256.hexdigest(skill_body),
      prompt_sha256: Digest::SHA256.hexdigest(prompt),
      pass: details.count { |detail| detail[:pass] }, of: ROUNDS, details: details
    }
  end
  results[probe[:id]] = result
end

puts JSON.pretty_generate(
  provider: "claude", model: MODEL, rounds: ROUNDS,
  base_rev: BASE_SHA, head_rev: HEAD_SHA,
  selected_arms: selected_arm_names,
  canonical: selected_arm_names.sort == %w[base head mutant].sort,
  results: results
)
