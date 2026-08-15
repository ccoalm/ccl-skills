#!/usr/bin/env ruby
# frozen_string_literal: true
# RED-baseline differential probe for spec 023 batch II (advisory evidence; committed under specs/023 evidence).
# Same method as red-baseline-023-I.rb: immutable base/head SHAs resolved before any model call, argv git,
# abort on any read failure or dirty skills tree, sha256 of every prompt input recorded, raw answers kept.
require "json"; require "open3"; require "timeout"; require "tmpdir"; require "digest"
WT = ARGV[0] or abort "usage: red-baseline-023-III.rb <worktree> [rounds] [model] [base-rev] [head-rev]"
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
  { id: "sew-review-mining", skill: "skill-extraction-workflow", refs: ["review-feedback-mining.md"],
    task: "我想从上个月已合并的 PR 里挖人类评审意见，用来更新我们的评审技能。我的做法：把所有 review 评论拉下来，凡是线程被 resolved、或作者回复了「已修」的，就算这条意见被采纳，然后据此往技能里加规则。另外我打算把模型起草的新 SKILL.md 直接提交。这个流程有问题吗？",
    required: [/resolved|线程|已修|fixed|回复/i, /diff|补丁|patch|落地|landed|对比|反馈时刻|feedback-time|前后/i, /不得|不能|不可|逐字|verbatim|人工|操作者|裁决|审阅/i],
    why: "新规则：线程状态/已修回复不是采纳证明，采纳=反馈时刻补丁 vs 落地补丁；模型草稿不得逐字提交" },
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
