#!/usr/bin/env ruby
# Offline regrade of stored ans_full with the current graders in probe-064-patterns.rb.
# No model calls. NON-DESTRUCTIVE: source files are never modified; each regrade
# writes ONE immutable output (O_EXCL via link(2), unique regrade id, grader-source
# sha embedded) so serial/concurrent regrades with different grader revisions can
# never last-writer-wins each other (convergence-round P1).
# Inputs: default = the frozen round-064 files probe-064-{base,head}.json (flat
# task map); or pass explicit run-file paths (round-4+ envelope {run,tasks}) as ARGV.
# (History note: two regrades before the non-destructive fix rewrote the round-064
# source files in place; the overwritten online details are unrecoverable, the score
# chain is recorded in AGENTS.md.)
# Valid only for rounds that stored ans_full; truncated/absent entries keep the
# original online verdict.
require "json"; require "digest"; require "securerandom"
ENV["REGRADE"] = "1"
code = File.read(File.join(__dir__, "probe-064-patterns.rb"))
graders_src = code[/def grade_t1.*?^end\n\ndef grade_t2.*?^end\n\ndef grade_t3.*?^end/m] or abort "graders not found"
eval(graders_src)
GRADER_SHA = Digest::SHA256.hexdigest(graders_src)
G = { "T1-smells" => method(:grade_t1), "T2-fixture" => method(:grade_t2), "T3-param" => method(:grade_t3) }

inputs = ARGV.empty? ? %w[base head].map { |a| File.join(__dir__, "probe-064-#{a}.json") } : ARGV
inputs.each do |p|
  abort "input not found: #{p}" unless File.exist?(p)
  doc = JSON.parse(File.read(p))
  envelope = doc.key?("tasks") && doc.key?("run")
  tasks = envelope ? doc["tasks"] : doc
  tasks.each do |k, v|
    grader = G[k] or next
    old = v["pass"]; hits = 0; skipped = 0
    v["details"].each do |d|
      next if d["error"]
      full = d["ans_full"]
      if full.nil? || full.empty? || d["ans_truncated"] || full.length >= 8000
        # No full text, or truncated: offline evidence is incomplete — keep the
        # original online verdict rather than overwrite it.
        skipped += 1; hits += 1 if d["pass"]
        next
      end
      g = grader.call(full)
      d["original_pass"] = d["pass"]; d["original_detail"] = d["detail"]
      d["pass"] = g[:pass]; d["detail"] = g[:detail]
      hits += 1 if g[:pass]
    end
    v["pass"] = hits
    puts "#{File.basename(p)} #{k}: #{old} -> #{hits} (#{skipped} rounds kept original verdict, no ans_full)"
  end
  regrade_id = "#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}"
  outdoc = { regrade: { input: File.basename(p), input_sha256: Digest::SHA256.hexdigest(File.read(p)),
                        grader_sha256: GRADER_SHA, regrade_id: regrade_id },
             result: doc }
  out = File.join(__dir__, "#{File.basename(p, '.json')}-regraded-#{regrade_id}.json")
  tmp = File.join(__dir__, ".#{File.basename(out)}.tmp")
  File.write(tmp, JSON.pretty_generate(outdoc))
  File.link(tmp, out)   # atomic no-replace publish; EEXIST rather than overwrite
  File.unlink(tmp)
  puts "wrote #{out}"
end
