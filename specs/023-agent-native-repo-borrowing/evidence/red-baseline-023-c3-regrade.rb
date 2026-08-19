#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministic re-grade for C3 preservation raw outputs. It never rewrites the
# source record; it binds the source and every answer by sha256 and emits scores.
require "digest"
require "json"

path = ARGV[0] or abort "usage: red-baseline-023-c3-regrade.rb <raw.json>"
raw_bytes = File.binread(path)
source = JSON.parse(raw_bytes)
canonical_arms = %w[base head mutant]
unless source["canonical"] == true && source["selected_arms"] == canonical_arms
  abort "refusing non-canonical partial replay"
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
  push_command = /\bgit push\b.*--force-with-lease=mybr:["']?\$remote_oid["']?/
  push_index = lines.index { |line| line.match?(push_command) } || lines.length
  target_fetch = /\Agit fetch(?:\s+-\S+)*\s+origin(?:\s+(?:refs\/heads\/)?main(?::refs\/remotes\/origin\/main)?)?\z/
  misses << "target-refresh" unless lines.any? { |line| line.match?(target_fetch) }
  branch_fetch = /git fetch(?:\s+-\S+)*\s+origin\s+(?:refs\/heads\/)?mybr(?:\s|$|:)/
  pre_push_branch_fetches = lines[0...push_index].count { |line| line.match?(branch_fetch) }
  misses << "one-branch-fetch-before-push" unless pre_push_branch_fetches == 1
  misses << "initial-branch-fetch" unless lines.any? { |line| line.match?(branch_fetch) }
  misses << "literal-fetch-head-oid" unless answer.match?(/remote_oid=\$?\(git rev-parse FETCH_HEAD\)/)
  topology = /git rev-list --left-right --count ["']?mybr["']?\.\.\.["']?\$remote_oid["']?(?:`|\s|$)/
  topology_index = lines.index { |line| line.match?(topology) } || lines.length
  misses << "exact-topology-command" unless topology_index < lines.length
  misses << "no-malformed-topology-command" if lines.any? { |line| line.include?("git rev-list --left-right") && !line.match?(topology) }
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

graded = {}
graders = {
  "tighten-eight-class-walk" => method(:tighten_grade),
  "worktree-one-fetch-order" => method(:worktree_grade)
}
source.fetch("results").each do |id, result|
  grader = graders[id] or abort "unknown task id #{id}"
  arms = {}
  %w[base head mutant].each do |arm|
    details = result.fetch(arm).fetch("details").map do |detail|
      answer = detail.fetch("raw")
      answer_sha256 = Digest::SHA256.hexdigest(answer)
      unless answer_sha256 == detail.fetch("answer_sha256")
        abort "answer sha256 mismatch for #{id}/#{arm}/round-#{detail.fetch('round')}"
      end
      misses = grader.call(answer)
      {
        round: detail.fetch("round"), pass: misses.empty?, missed: misses,
        answer_sha256: answer_sha256
      }
    end
    arm_result = {
      rev: result.fetch(arm).fetch("rev"),
      body_sha256: result.fetch(arm).fetch("body_sha256"),
      prompt_sha256: result.fetch(arm).fetch("prompt_sha256"),
      pass: details.count { |detail| detail[:pass] }, of: details.length,
      details: details
    }
    arm_result[:status] = result.fetch(arm).fetch("status") if result.fetch(arm).key?("status")
    arm_result[:reason] = result.fetch(arm).fetch("reason") if result.fetch(arm).key?("reason")
    arms[arm] = arm_result
  end
  graded_result = {
    task_sha256: result.fetch("task_sha256"), mutation: result.fetch("mutation"),
    runner_time_scores: %w[base head mutant].to_h do |arm|
      [arm, { pass: result.fetch(arm).fetch("pass"), of: result.fetch(arm).fetch("of") }]
    end,
    arms: arms
  }
  graded_result[:status] = result.fetch("status") if result.key?("status")
  graded_result[:reason] = result.fetch("reason") if result.key?("reason")
  graded[id] = graded_result
end

puts JSON.pretty_generate(
  source_sha256: Digest::SHA256.hexdigest(raw_bytes),
  grader_sha256: Digest::SHA256.file(__FILE__).hexdigest,
  provider_attestation: {
    status: "unavailable",
    reason: "Claude CLI did not expose a signed provider request/response attestation."
  },
  provider: source.fetch("provider"), model: source.fetch("model"),
  rounds: source.fetch("rounds"), base_rev: source.fetch("base_rev"),
  head_rev: source.fetch("head_rev"), results: graded
)
