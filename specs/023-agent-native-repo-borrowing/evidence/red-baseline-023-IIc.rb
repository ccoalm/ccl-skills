#!/usr/bin/env ruby
# frozen_string_literal: true
# RED-baseline differential probe for spec 023 batch II (advisory evidence; committed under specs/023 evidence).
# Same method as red-baseline-023-I.rb: immutable base/head SHAs resolved before any model call, argv git,
# abort on any read failure or dirty skills tree, sha256 of every prompt input recorded, raw answers kept.
require "json"; require "open3"; require "timeout"; require "tmpdir"; require "digest"
WT = ARGV[0] or abort "usage: red-baseline-023-IIc.rb <worktree> [rounds] [model] [base-rev] [head-rev]"
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
  { id: "wt-lease-order", skill: "worktree-isolation", refs: [],
    task: "我要 rebase 一个已经推送、挂着 MR、有两条 review 评论的分支，然后 force-push。我的计划：先 `git rev-list --left-right --count mybr...origin/mybr` 确认远端没有独有提交，再 `git rebase origin/main`，最后 `git push --force-with-lease`。够安全吗？还缺什么？",
    required: [/observed|记下|观察到|亲眼|显式.{0,8}OID|:<.{0,12}oid|=.{0,12}:.{0,20}oid/i, /fetch/i, /重审|重新.{0,4}审|失效|不再是|作废|重新 fetch|approval|评论锚点|线程/i],
    why: "新规则：固定次序 fetch→记 OID→对同一引用做拓扑检查→rebase→lease 钉 OID；重写后重审评审状态" },
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
