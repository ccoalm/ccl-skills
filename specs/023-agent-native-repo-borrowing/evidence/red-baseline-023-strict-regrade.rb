#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministically re-grade two stored round-023 probes with stricter keyword
# contracts. This does not call a model or rewrite the original frozen evidence.
require "digest"
require "json"

CASES = [
  {
    id: "llm-wording",
    source: "red-baseline-023-I-final.json",
    required: [
      /plugin|transport|renderer|实现细节|实现词汇|传输/i,
      /scope|枚举|判别|允许值|allowed|enum/i,
      /快照|snapshot|replay|eval|评测|行为.{0,8}(证据|验证|测试|评估|复核)/i,
    ],
  },
  {
    id: "dd-postmortem-criteria",
    source: "red-baseline-023-II.json",
    required: [
      /subtle|微妙|非显然|隐蔽|不直观/i,
      /systemic|系统性|工具.{0,6}缺口|测试.{0,6}缺口|流程.{0,6}缺口/i,
      /costly|重新发现|再发现|复现.{0,4}代价|代价.{0,4}(高|大)|高成本/i,
      /执行摘要|executive|30 秒|三十秒|开头.{0,8}(摘要|一段话)/i,
      /guardrail|护栏|回链|链接.{0,8}(测试|规则|决策记录)/i,
    ],
  },
].freeze

def flags(regexp)
  [["i", Regexp::IGNORECASE], ["m", Regexp::MULTILINE], ["x", Regexp::EXTENDED]]
    .filter_map { |name, bit| name unless (regexp.options & bit).zero? }
    .join
end

results = {}
sources = {}

CASES.each do |spec|
  path = File.join(__dir__, spec.fetch(:source))
  bytes = File.binread(path)
  source = JSON.parse(bytes)
  original = source.fetch("results").fetch(spec.fetch(:id))
  sources[spec.fetch(:source)] = Digest::SHA256.hexdigest(bytes)

  result = {
    "source" => spec.fetch(:source),
    "task_sha256" => original.fetch("task_sha256"),
    "required" => spec.fetch(:required).map(&:source),
    "required_flags" => spec.fetch(:required).map { |regexp| flags(regexp) },
  }

  %w[base head].each do |arm|
    details = original.fetch(arm).fetch("details").map do |row|
      raw = row.fetch("raw")
      abort "stored len mismatch for #{spec.fetch(:id)} #{arm} r#{row.fetch('round')}" unless raw.length == row.fetch("len")

      missed = spec.fetch(:required).reject { |regexp| regexp.match?(raw) }.map(&:source)
      {
        "round" => row.fetch("round"),
        "pass" => missed.empty?,
        "missed" => missed,
        "len" => raw.length,
        "raw_sha256" => Digest::SHA256.hexdigest(raw),
      }
    end
    result[arm] = {
      "rev" => original.fetch(arm).fetch("rev"),
      "pass" => details.count { |row| row.fetch("pass") },
      "of" => details.length,
      "details" => details,
    }
  end
  results[spec.fetch(:id)] = result
end

puts JSON.pretty_generate(
  "schema" => "round-023-stored-raw-strict-regrade-v1",
  "method" => "No model calls. Re-grade raw answers from immutable source files; bind each source and raw answer by sha256.",
  "sources" => sources,
  "results" => results,
)
