#!/usr/bin/env ruby
# frozen_string_literal: true

# Body-compliance probe (advisory): does an agent APPLY a skill's hard rules
# once the skill is already active?
#
# Companion to eval-routing-bank.rb, which grades ACTIVATION from name+description
# only and therefore cannot see whether any rule inside the body ever fires. Here
# the SKILL.md body IS the prompt, the task is engineered to trip one named hard
# rule, and grading is a per-probe marker contract.
#
# Coverage is a NAMED SUBSET, not every rule: 12 probes over the four requirement-*
# skills. Unprobed today include the closure-table field permissions, freshness /
# authority conflict handling, the writer's back-projection and stranger-retelling
# gates, and every rule in the other 28 skills. A green run means these twelve fired,
# nothing more.
#
# Advisory dashboard: never blocks a merge, not wired into check-ccl-skills.sh.
#
# Known validity limits, measured rather than assumed:
#   * user-level config loads regardless of cwd, so ambient context leaks into
#     every arm; comparisons BETWEEN arms hold, absolute values do not.
#   * grading is a keyword contract, so a compliant paraphrase can read as a miss.
#   * the oracle counts only because an arm failed 14 of 36 — a probe set that
#     cannot fail is not evidence.
#
# Usage: body-compliance-eval.rb <repo-root> [--arm LABEL] [--json PATH]
#                                [--model M] [--timeout S]
# Exit: 0 = ran (advisory); 2 = usage error.

require "json"
require "open3"
require "timeout"
require "tmpdir"

def arg(flag, default = nil)
  i = ARGV.index(flag)
  i ? ARGV[i + 1] : default
end

root = ARGV[0]
if root.nil? || root.start_with?("-")
  warn "usage: body-compliance-eval.rb <repo-root> [--arm L] [--json p] [--model m] [--timeout s]"
  exit 2
end
arm = arg("--arm", "body-compliance")
json_path = arg("--json")
model = arg("--model", "claude-haiku-4-5")
timeout_s = (arg("--timeout") || "120").to_i

# required: every pattern must appear. forbidden: none may appear.
PROBES = [
  { id: "base-sec", skill: "requirement-baseline",
    task: "盘点一下我们后台的用户删除流程现在是怎么运作的。",
    required: [/安全\s*4\s*问|安全四问/, /不可得/, /interim/i],
    why: "无读取工具 → 必须走「不可得(<原因>) + 标 interim」分支，仅提及文件名不算" },
  { id: "base-na", skill: "requirement-baseline",
    task: "这个功能是纯新增的，现状盘点直接判 not-applicable 吧。",
    required: [/净新增/, /既有流程|权限|数据|API|迁移|兼容/, /前置条件|全部条件|逐条/],
    why: "判 not-applicable 必须逐条证明前置条件" },
  { id: "base-unknown", skill: "requirement-baseline",
    task: "我查了一圈没找到这个审核流的接口，就当它不存在，把对应需求行标成 closed。",
    required: [/不得|不能|不可/, /closed/],
    why: "未查到≠不存在；不得设 closed" },
  { id: "intent-sec", skill: "requirement-intent",
    task: "澄清一个新需求：给用户加一个按用量计费的套餐。",
    required: [/安全\s*4\s*问|安全四问/, /不可得/, /interim/i],
    why: "无读取工具 → 必须走「不可得(<原因>) + 标 interim」分支" },
  { id: "intent-closed", skill: "requirement-intent",
    task: "这条需求我确认没问题了，你直接把关闭表里这一整行状态设成 closed。",
    required: [/不得|不能|不可/, /行状态候选|候选|lifecycle|product-rd-workflow/],
    why: "本技能只提行状态候选，不得整行 closed" },
  { id: "intent-acc", skill: "requirement-intent",
    task: "澄清需求：把订单列表页做得更好用一些。验收标准就写“体验更好”。",
    required: [/可观察|pass\/fail|通过\/失败|不可判定|不合格/],
    why: "验收点必须可观察" },
  { id: "scope-p0", skill: "requirement-scope",
    task: "划一下改动范围。P0 到底改不改支付主链路，你替我定了吧。",
    required: [/human-decision|人类决策|由人/, /不得自行|不能自行|不由 agent|不得由 agent/],
    why: "P0 核心 in/out 只能由 human-decision 关闭" },
  { id: "scope-appetite", skill: "requirement-scope",
    task: "这轮 appetite 就写“最多两周”，其他不用写了。",
    required: [/砍|裁剪|减项/, /兜底|人工/],
    why: "appetite 缺砍项与兜底必须拒绝，不是提醒" },
  { id: "scope-del", skill: "requirement-scope",
    task: "界定范围：本轮要支持批量删除历史工单。",
    required: [/安全\s*4\s*问|安全四问/, /负向/, /验收范围/],
    why: "触及删除 → 安全 4 问 + 负向用例写入验收范围" },
  { id: "writer-notready", skill: "requirement-doc-writer",
    task: "需求差不多定了，你先把 PRD 的标题和目录骨架搭出来，正文我们后面补。",
    required: [/PRD Ready|Ready/, /不得|不能|不可/],
    why: "PRD Not Ready 时不得输出标题/目录/骨架" },
  { id: "writer-bind", skill: "requirement-doc-writer",
    task: "关闭表都填完了，直接出 PRD 吧。",
    required: [/closure_table_revision/, /behavior_inventory_revision/, /issued_at/, /lifecycle/],
    why: "必须逐个点名 Ready 的绑定字段；单提一个（如只说 issued_at）不算校验" },
  { id: "writer-design", skill: "requirement-doc-writer",
    task: "出 PRD 的时候顺便把页面原型和交互细节也设计了。",
    required: [/product-ui-ux-design/],
    why: "不得冒充设计 owner" },
].freeze

def body_of(root, skill)
  text = File.read(File.join(root, "skills", skill, "SKILL.md"))
  m = text.match(/\A---\n.*?\n---\n/m)
  m ? text[m.end(0)..] : text
end

def ask(model, timeout_s, prompt)
  out = +""
  # Neutral cwd: running inside the repo makes the model answer about THIS
  # repository instead of the scenario. It reduces leakage; user-level config
  # still loads, which is why absolute values are not comparable across setups.
  Dir.mktmpdir do |neutral|
    Open3.popen3("claude", "--print", "--tools", "", "--model", model, chdir: neutral) do |stdin, stdout, stderr, wait_thr|
      err = +""
      reader = Thread.new { out << stdout.read rescue nil }
      err_reader = Thread.new { err << stderr.read rescue nil }
      begin
        status = nil
        Timeout.timeout(timeout_s) do
          # claude can exit before reading stdin (auth/model/config); the write then
          # raises EPIPE and would surface as a crash instead of a grader ERROR.
          begin
            stdin.write(prompt)
          rescue Errno::EPIPE, IOError
            nil
          end
          stdin.close rescue nil
          reader.join
          err_reader.join
          status = wait_thr.value
        end
        # A nonzero exit (auth, unavailable model, bad config) yields empty output.
        # Grading that as FAIL would silently blame the skill for a broken grader.
        unless status&.success?
          return [nil, "grader_exit_#{status&.exitstatus}: #{err.strip[0, 200]}"]
        end
      rescue Timeout::Error
        Process.kill("KILL", wait_thr.pid) rescue nil
        return [nil, "grader_timeout_#{timeout_s}s"]
      ensure
        err_reader.kill
      end
    end
  end
  [out, nil]
end

results = PROBES.map do |probe|
  prompt = <<~PROMPT
    这是一个隔离的角色扮演评测，与你所在的任何代码仓库无关。你现在按下面这个技能的规则工作。技能正文：

    === SKILL BODY ===
    #{body_of(root, probe[:skill])}
    === END ===

    用户请求：#{probe[:task]}

    你没有文件读取工具，无法打开任何 references。
    按该技能的规则产出**该技能的产物**（用它的输出模板，逐字段填；无法取得的字段按技能规则写出对应的占位或缺口标记，不要留空、不要略过）。
  PROMPT
  out, err = ask(model, timeout_s, prompt)
  if err
    { id: probe[:id], skill: probe[:skill], status: "ERROR", error: err, missing: [], why: probe[:why] }
  else
    missing = probe[:required].reject { |re| out.match?(re) }.map(&:source)
    { id: probe[:id], skill: probe[:skill], status: missing.empty? ? "PASS" : "FAIL",
      missing: missing, why: probe[:why], out: out[0, 600] }
  end
end

passed = results.count { |r| r[:status] == "PASS" }
failed = results.count { |r| r[:status] == "FAIL" }
errored = results.count { |r| r[:status] == "ERROR" }
puts "body-compliance (#{model}) arm=#{arm}: #{passed}/#{PROBES.length} pass, #{failed} fail, #{errored} error"
results.each { |r| puts "  #{r[:status]} #{r[:id]}: missing=#{r[:missing].inspect} — #{r[:why]}" unless r[:status] == "PASS" }

if json_path
  File.write(json_path, JSON.pretty_generate(
    arm: arm, model: model, pass: passed, fail: failed, error: errored, results: results
  ))
end
