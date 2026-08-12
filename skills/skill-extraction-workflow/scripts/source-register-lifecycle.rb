#!/usr/bin/env ruby
# frozen_string_literal: true

# Emits the source-register lifecycle advisory. This helper never chooses the
# checker exit code; its caller deliberately treats the report as advisory.

require "date"

register = ARGV.fetch(0)
today = Date.today
supersedes = 0
revalidate_when = 0
revalidate_by = 0
overdue = 0
skipped = false

begin
  File.foreach(register) do |line|
    next unless line.match?(/^\s*\|/)
    next if line.match?(/^\s*\|\s*:?-{3,}:?\s*\|/)

    supersedes += line.scan(/supersedes:/).length
    revalidate_when += line.scan(/revalidate-when:/).length
    line.scan(/revalidate-by:\s*(\d{4}-\d{2}-\d{2})(?![\dT:-])/) do |match|
      date = begin
        Date.strptime(match[0], "%Y-%m-%d")
      rescue StandardError
        nil
      end
      next unless date

      revalidate_by += 1
      next unless date < today

      warn "revalidate_overdue: source-register has revalidate-by #{match[0]} (before #{today}) — re-check that externally-anchored rule (advisory, not blocking)"
      overdue += 1
    end
  end
rescue StandardError => e
  skipped = true
  warn "revalidate_check_skipped: #{e.class}: #{e.message}"
end

unless skipped
  puts "source_register_lifecycle_advisory: supersedes=#{supersedes} revalidate_when=#{revalidate_when} revalidate_by=#{revalidate_by} overdue=#{overdue}"
  if overdue.zero?
    puts "revalidate_check_ok"
  else
    puts "revalidate_check_advisory: #{overdue} overdue marker(s) above (advisory — not blocking)"
  end
end
