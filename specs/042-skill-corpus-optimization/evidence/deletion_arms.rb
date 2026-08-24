#!/usr/bin/env ruby
# frozen_string_literal: true
# 042 批 2：删除候选的三臂探针。
#
# 为什么不能复用 conflict_arms.rb：那套的效力闸是为**阳性**设计的（要求旧臂
# 有失败空间）。测删除时「带该规则的臂」本来就该接近满分，会被天花板闸误判无效。
# 证「删了不掉」是零结果主张，需要**阳性对照臂**证明本探针测得出损失。
#
# 三臂：
#   full            完整分组
#   minus_candidate 去掉待删候选
#   minus_control   去掉一条已知承重、且由**另一个 marker** 承接的内容
# 判定：
#   control 未掉    -> INVALID_APPARATUS（探针根本测不出删除，零结果无意义）
#   candidate 掉了  -> LOAD_BEARING（不可删）
#   control 掉、candidate 不掉 -> REMOVABLE_ON_PROBED_POINTS（仅限所测决策点，不外推）
# 零结果同样要功率与复现：--runs >= 10、--replicate >= 2。
require "json"; require "open3"; require "timeout"; require "tmpdir"
def arg(f, d=nil) = (i = ARGV.index(f)) ? ARGV[i+1] : d
RUNS = (arg("--runs","10")).to_i
REPLICATE = (arg("--replicate","2")).to_i
MODEL = arg("--model","claude-haiku-4-5")
TIMEOUT = (arg("--timeout","150")).to_i
REPO = File.expand_path("../../..", __dir__)
SK = "skills/skill-extraction-workflow/SKILL.md"

LINES = File.read(File.join(REPO, SK)).split("\n", -1)
GROUP = (101..122)                     # Owner-generalization / target-output / impact-chain 组
# 一次测多个候选：臂 = full + 每个候选各一 + 对照，共用同一批调用。
CONTROL = 107                                   # 对照（已实证：拿掉它 marker 从 9/10 归零）
CANDIDATES = {
  120 => /install-drift/i,                          # 924B；marker 是它**要求**的产出（L116 亦承载=冗余假设）
  113 => /immediate neighbors|相邻|邻居/i,                  # 597B，结构筛 0 独有
}
M_CTRL = /route-to-shared/i

def body(drop)
  GROUP.reject { |i| i == drop }.map { |i| LINES[i - 1] }.join("\n")
end
ARMS = { "full" => body(nil), "minus_control" => body(CONTROL) }
CANDIDATES.each_key { |ln| ARMS["minus_L#{ln}"] = body(ln) }
abort("臂文本有重复，行号可能已漂移") if ARMS.values.uniq.length != ARMS.length

TASK = "我刚在 Go 服务技能里改了一条上游契约规则（它同时是别的技能要执行的决策面），过程中还发现自己漏掉了一个 owner 维度。按上面的规则，closeout 我必须产出什么？逐项列全。"

# 前置自检，两条要求不同——这是本量具最容易用错的一处：
#   对照臂：marker 必须在组内**唯一承载**。否则删掉对照行也删不掉概念，
#           探针测不出损失，候选的零结果毫无意义。
#   候选臂：marker 只需**出现在候选行里**（确保测的是它），**允许别处也有承载**。
#           别处有承载恰恰是「这条与那条冗余」的证据本身，不是伪影；
#           拿对照的规矩去卡候选，等于把要测的现象当噪声筛掉。
ctrl_owners = GROUP.select { |i| LINES[i - 1].match?(M_CTRL) }
abort("对照 marker 命中 #{ctrl_owners.inspect}，非唯一承载于 L#{CONTROL}；重选") unless ctrl_owners == [CONTROL]
CANDIDATES.each do |line, re|
  abort("候选 marker 未出现在 L#{line} 本行，测的不是它") unless LINES[line - 1].match?(re)
  others = GROUP.select { |i| i != line && LINES[i - 1].match?(re) }
  puts "  note: L#{line} 的 marker 在组内另有承载 #{others.inspect}（冗余假设的直接候选）" unless others.empty?
end

def ask(prompt)
  out = +""
  Dir.mktmpdir do |neutral|
    Open3.popen3("claude","--print","--tools","","--model",MODEL, chdir: neutral) do |i,o,e,t|
      err = +""; r = Thread.new { out << o.read rescue nil }; er = Thread.new { err << e.read rescue nil }
      begin
        st = nil
        Timeout.timeout(TIMEOUT) do
          begin
            i.write(prompt)
          rescue Errno::EPIPE, IOError
            nil
          end
          i.close rescue nil; r.join; er.join; st = t.value
        end
        return [nil, "grader_exit_#{st&.exitstatus}"] unless st&.success?
      rescue Timeout::Error
        Process.kill("KILL", t.pid) rescue nil; return [nil, "grader_timeout"]
      ensure er.kill end
    end
  end
  [out, nil]
end

def measure
  tally = {}
  ARMS.each do |name, text|
    t = Hash.new(0)
    RUNS.times do
      prompt = "这是一个隔离的角色扮演评测，与你所在的任何代码仓库无关。你按下面的规则工作。\n\n=== RULES ===\n#{text}\n=== END ===\n\n用户请求：#{TASK}\n\n你没有文件读取工具。直接列出必须产出的东西。"
      out, err = ask(prompt)
      if err then t[:err] += 1
      else
        CANDIDATES.each { |ln, re| t[ln] += 1 if out.match?(re) }
        t[:ctrl] += 1 if out.match?(M_CTRL)
      end
    end
    tally[name] = t
    puts "  #{name.ljust(16)} " + CANDIDATES.keys.map { |ln| "L#{ln}=#{t[ln]}/#{RUNS}" }.join(" ") + " ctrl=#{t[:ctrl]}/#{RUNS} err=#{t[:err]}"
  end
  tally
end

reps = []
REPLICATE.times do |k|
  puts "\n-- 复现轮 #{k+1}/#{REPLICATE} --"
  reps << measure
end

def verdict(t, runs)
  return { _apparatus: "INCONCLUSIVE(grader errors)" } if t.values.sum { |x| x[:err] } > 0
  need = (runs * 0.3).ceil
  ctrl_drop = t["full"][:ctrl] - t["minus_control"][:ctrl]
  return { _apparatus: "INVALID_APPARATUS (对照臂只掉 #{ctrl_drop}/#{runs})" } if ctrl_drop < need
  out = { _apparatus: "ok (对照掉 #{ctrl_drop}/#{runs})" }
  CANDIDATES.each_key do |ln|
    drop = t["full"][ln] - t["minus_L#{ln}"][ln]
    out[ln] = drop >= need ? "LOAD_BEARING (掉 #{drop}/#{runs})" : "REMOVABLE_ON_PROBED_POINTS (掉 #{drop}/#{runs})"
  end
  out
end

puts "\n== 跨 #{REPLICATE} 次复现 =="
vs = reps.map { |t| verdict(t, RUNS) }
vs.each_with_index { |v, i| puts "  轮#{i+1}: apparatus=#{v[:_apparatus]}" }
final = {}
if vs.any? { |v| !v[:_apparatus].start_with?("ok") }
  final[:all] = "APPARATUS_FAILED"
elsif RUNS < 10 then final[:all] = "UNDERPOWERED (零结果需 --runs >= 10)"
elsif REPLICATE < 2 then final[:all] = "UNREPLICATED"
else
  CANDIDATES.each_key do |ln|
    kinds = vs.map { |v| v[ln].split(" ").first }.uniq
    final[ln] = kinds.length > 1 ? "NOT_REPLICATED (#{kinds.join(',')})" : kinds.first
    puts "  L#{ln}: #{final[ln]}   " + vs.map { |v| v[ln] }.join(" | ")
  end
end
puts "final: #{final.inspect}"
if (p = arg("--json"))
  File.write(p, JSON.pretty_generate({model: MODEL, runs: RUNS, replicate: REPLICATE,
    candidates: CANDIDATES.keys, control_line: CONTROL, per_replicate: reps, verdicts: vs, final: final}))
  puts "raw -> #{p}"
end
exit(final.values.any? { |v| v.to_s.start_with?("REMOVABLE") } ? 0 : 1)
