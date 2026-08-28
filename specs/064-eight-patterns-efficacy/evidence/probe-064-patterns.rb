#!/usr/bin/env ruby
# 064 eight-patterns efficacy probe — body-as-prompt differential, 023-style.
#
# What this number is NOT: it is not a merge gate (eval/AGENTS.md advisory
# contract), not a claim that the graded keyword contract equals semantic
# quality, and not a cross-provider claim (single provider/model per run).
# The head arm SIMULATES a followed pointer: it embeds the updated workflow
# slice PLUS the decision table + closeout checklist that the pointer would
# lead a real agent to read; the base arm embeds the current workflow slice
# only. So the measured delta is "the surface reachable at the firing point
# changed", not "agents follow pointers" (the latter needs a live-repo probe).
#
# Usage: ruby probe-064-patterns.rb <arm-label> <skill-slice-file> [rounds] [model]
#   ruby probe-064-patterns.rb base slice-base.md 10
#   ruby probe-064-patterns.rb --selftest   # grader oracle check (must red on bad, green on good)
require "open3"; require "json"; require "digest"; require "timeout"; require "fileutils"; require "tmpdir"; require "securerandom"

MODEL  = ARGV[3] || "claude-haiku-4-5"
ROUNDS = begin
  r = Integer(ARGV[2] || "10", 10)
  abort "rounds must be a positive integer" unless r > 0
  r
rescue ArgumentError
  abort "rounds must be a positive integer"
end

TASKS = [
  { id: "T1-smells",
    task: "评审这个测试（图书借阅系统）：\n```python\ndef test_loan():\n    lib = Library()\n    data = json.load(open('fixtures/books.json'))\n    for b in data:\n        lib.add(b)\n    if lib.count() > 3:\n        loan = lib.borrow('u1', data[0]['id'])\n        assert loan is not None\n        assert lib.count() == len(data) - 1\n        assert lib.history('u1')[0].book_id == data[0]['id']\n        late = lib.borrow('u1', data[1]['id'])\n        assert late.due_days == 14\n```\n这个测试有什么问题，怎么改？给出改后的测试代码。" },
  { id: "T2-fixture",
    task: "给天气缓存模块补 4 个测试：命中未过期、过期后 serve-then-refresh、TTL 边界、来源降级。模块定义（信息已完整，不要追问，直接输出测试代码）：\n```python\n@dataclass\nclass CacheEntry:\n    key: str; temp_c: float; fetched_at: datetime; ttl_minutes: int; source: str; stale_policy: str\n\nclass WeatherCache:\n    def put(self, entry: CacheEntry) -> None: ...\n    def get(self, key: str) -> Reading:  # 未过期返回缓存值；过期且 stale_policy='serve-then-refresh' 先返回旧值并触发后台刷新；来源不可用时降级到 source='fallback'\n```\n现有测试每个都这样逐字段构造：\n```python\nentry = CacheEntry(key='beijing', temp_c=21, fetched_at=now()-timedelta(minutes=4), ttl_minutes=5, source='api-v2', stale_policy='serve-then-refresh')\n```" },
  { id: "T3-param",
    task: "运费计算函数 shipping_fee(weight_kg, zone) 规则：≤1kg 起步价 8 元；1–5kg 每 kg 加 3 元；>5kg 每 kg 加 2 元且封顶 45 元；zone='remote' 全程 ×1.5。请为它写测试，至少覆盖 0.5kg/3kg/8kg/remote 8kg 四种输入。直接给出测试代码。" },
]

# --- keyword-contract graders (mechanical; validated by --selftest) ---
def grade_t1(out)
  # Synonym classes calibrated against real haiku phrasing (base run 1, discarded):
  # semantic target = names >=2 problem classes (any wording) + structural fix.
  classes = 0
  classes += 1 if out =~ /条件逻辑|条件跳过|条件判断|条件执行|条件性测试|conditional/im
  classes += 1 if out =~ /mystery\s*guest|外部文件|隐[式性]依赖|不可靠的?依赖|books\.json|obscure\s*test/im
  classes += 1 if out =~ /eager\s*test|assertion\s*roulette|(一个|单个)测试.{0,20}(多个?场景|太多|塞)|多个关注点|关注点混|职责混|混合多个|混淆多个|单点失败.{0,12}定位|拆分?(成|为).{0,8}(多个|独立|单一).{0,6}测试/im
  fix = out =~ /拆分|参数化|parametrize|工厂|builder|factory|移除.{0,8}(if|条件)|去掉.{0,8}(if|条件)|显式.{0,10}(fixture|构造|数据)|inline|内联/im
  { pass: classes >= 2 && !!fix, detail: { classes: classes, fix: !!fix } }
end

def grade_t2(out)
  # Tightened per codex review P1 (keyword-only mention must not pass):
  # pass = a helper/factory/builder is DEFINED, REUSED >=2 times, the full
  # field-by-field constructor is not still copy-pasted, and tests are behavior-named.
  m = out.match(/def\s+((?:a_?|an_?|make_|build_)[a-z_]*entry[a-z_]*|[a-z_]*entry_factory|fresh_entry|expired_entry)\s*\(/i)
  helper_def = m && m[1]
  reuse = helper_def ? out.scan(/#{Regexp.escape(helper_def)}\s*\(/i).size - 1 : 0
  if !helper_def && out =~ /class\s+\w*Builder\b/i
    helper_def = "builder-class"
    reuse = out.scan(/\.build\s*\(/).size
  end
  if !helper_def && (fm = out.match(/@pytest\.fixture[\s\S]{0,80}?def\s+(\w+)\s*\(/))
    helper_def = "pytest-fixture:#{fm[1]}"
    reuse = out.scan(/\b#{Regexp.escape(fm[1])}\b/).size - 2
  end
  full_ctors = out.scan(/CacheEntry\s*\(/).size
  copy_paste = full_ctors >= 3
  name = out =~ /def\s+test_[a-z0-9_]*(expired|stale|refresh|boundary|edge|ttl|fallback|serve|hit|fresh|degrad)/i
  { pass: !!helper_def && reuse >= 2 && !copy_paste && !!name,
    detail: { helper_def: !!helper_def, reuse: reuse, full_ctors: full_ctors, behavior_name: !!name } }
end

def grade_t3(out)
  # Tightened per codex review P2: parametrization must be CONSUMED (decorator on a
  # def, or a cases loop whose body asserts), and the 1kg/5kg boundary rows present.
  consumed = out =~ /parametrize[\s\S]{0,2400}?\)\s*\n\s*(@[^\n]*\n\s*)*def\s+test_/i ||
             out =~ /for\s+[a-z_, ]+\s+in\s+[a-z_]*(cases|table|rows|data)\b[\s\S]{0,400}?assert/i
  funcs = out.scan(/def\s+test_/).size
  b1 = out =~ /[\(\[,]\s*1(\.0)?\s*,/
  b5 = out =~ /[\(\[,]\s*5(\.0)?\s*,/
  { pass: !!consumed && funcs <= 2 && !!b1 && !!b5,
    detail: { consumed: !!consumed, test_funcs: funcs, boundary_1kg: !!b1, boundary_5kg: !!b5 } }
end

GRADERS = { "T1-smells" => method(:grade_t1), "T2-fixture" => method(:grade_t2), "T3-param" => method(:grade_t3) }

if ARGV[0] == "--selftest"
  good = {
    "T1-smells" => [
      "这个测试有三个问题：1) 测试体内的条件逻辑——if lib.count()>3 包住了全部断言，数据不足时静默跳过（Conditional Test Logic）；2) Mystery Guest——依赖外部文件 fixtures/books.json，内容不可见；3) 一个测试塞多个场景，应拆分成多个测试并把构造显式 inline。",
      # paraphrase pin: real haiku phrasing from discarded base run 1 (grader must accept synonyms)
      "问题：**条件跳过** (if lib.count() > 3) 导致断言可能不执行；**硬依赖外部文件**，格式错误难以诊断；**混合多个关注点**，单点失败时难以定位。改法：拆分测试并用工厂构造数据。",
    ],
    "T2-fixture" => [
      # builder-class pin (real head-arm false red before this form was accepted)
      "class CacheEntryBuilder:\n    def __init__(self): self.age_min = 0\n    def with_age(self, m):\n        self.age_min = m\n        return self\n    def build(self): return CacheEntry(key='x', temp_c=20, fetched_at=now()-timedelta(minutes=self.age_min), ttl_minutes=5, source='api-v2', stale_policy='serve-then-refresh')\n\ndef test_expired_entry_serves_stale_then_refreshes():\n    e = CacheEntryBuilder().with_age(9).build()\ndef test_fresh_entry_hit_returns_cached():\n    e = CacheEntryBuilder().build()\ndef test_ttl_boundary_still_fresh():\n    e = CacheEntryBuilder().with_age(5).build()\ndef test_source_fallback_degrades():\n    e = CacheEntryBuilder().build()\n",
      "用集中工厂：\ndef a_fresh_entry(**kw):\n    fields = dict(key='x', temp_c=20, fetched_at=now(), ttl_minutes=5, source='api-v2', stale_policy='serve-then-refresh')\n    fields.update(kw)\n    return CacheEntry(**fields)\n\ndef test_fresh_entry_hit_returns_cached():\n    cache.put(a_fresh_entry())\n    assert cache.get('x').temp_c == 20\n\ndef test_expired_entry_serves_stale_then_refreshes():\n    cache.put(a_fresh_entry(fetched_at=now()-timedelta(minutes=9)))\n    assert cache.get('x') is not None\n",
    ],
    "T3-param"   => [
      "@pytest.mark.parametrize('w,zone,fee', [(0.5,'city',8),(1,'city',8),(3,'city',14),(5,'city',20),(8,'city',26),(8,'remote',39)])\ndef test_shipping_fee(w, zone, fee):\n    assert shipping_fee(w, zone) == fee",
    ],
  }
  bad = {
    "T1-smells" => [
      "建议给断言加上失败信息，并把测试改名为 test_loan_flow，这样报错更清楚。",
    ],
    "T2-fixture" => [
      "def test_1():\n    entry = CacheEntry(key='beijing', temp_c=21, fetched_at=now()-timedelta(minutes=4), ttl_minutes=5, source='api-v2', stale_policy='serve-then-refresh')\n    assert cache.get('beijing')\ndef test_2():\n    entry = CacheEntry(key='beijing', temp_c=21, fetched_at=now()-timedelta(minutes=9), ttl_minutes=5, source='api-v2', stale_policy='serve-then-refresh')\n    assert cache.get('beijing')",
      # ask-for-context pin: refusing to write code must stay RED
      "我需要先看到现有的测试文件和 CacheEntry 类定义。能否分享一下测试文件位置和完整代码样本？",
      # codex-review adversarial pin: keyword-only factory mention + copy-pasted full ctors must stay RED
      "建议用工厂模式（builder）。\ndef test_hit_not_expired():\n    entry = CacheEntry(key='beijing', temp_c=21, fetched_at=now(), ttl_minutes=5, source='api-v2', stale_policy='serve-then-refresh')\ndef test_expired_serves_stale():\n    entry = CacheEntry(key='beijing', temp_c=21, fetched_at=now()-timedelta(minutes=9), ttl_minutes=5, source='api-v2', stale_policy='serve-then-refresh')\ndef test_ttl_boundary_exact():\n    entry = CacheEntry(key='beijing', temp_c=21, fetched_at=now()-timedelta(minutes=5), ttl_minutes=5, source='api-v2', stale_policy='serve-then-refresh')\n",
    ],
    "T3-param"   => [
      "def test_a():\n    assert shipping_fee(0.5,'city')==8\ndef test_b():\n    assert shipping_fee(3,'city')==14\ndef test_c():\n    assert shipping_fee(8,'city')==31\ndef test_d():\n    assert shipping_fee(8,'remote')==46.5",
      # codex-review adversarial pin: cases list defined but never consumed must stay RED
      "cases = [(0.5,'city',8),(1,'city',8),(5,'city',20),(8,'remote',39)]\ndef test_a():\n    assert shipping_fee(0.5,'city')==8\ndef test_b():\n    assert shipping_fee(3,'city')==14\ndef test_c():\n    assert shipping_fee(8,'city')==26\ndef test_d():\n    assert shipping_fee(8,'remote')==39",
      # boundary-missing parametrize must stay RED
      "@pytest.mark.parametrize('w,zone,fee', [(0.5,'city',8),(3,'city',14),(8,'city',26),(8,'remote',39)])\ndef test_shipping_fee(w, zone, fee):\n    assert shipping_fee(w, zone) == fee",
    ],
  }
  ok = true
  GRADERS.each do |id, g|
    good[id].each_with_index do |s, i|
      gp = g.call(s)[:pass]
      puts "#{id} good[#{i}]: #{gp ? 'GREEN' : 'RED(!)'}"; ok &&= gp
    end
    bad[id].each_with_index do |s, i|
      bp = g.call(s)[:pass]
      puts "#{id} bad[#{i}]: #{bp ? 'GREEN(!)' : 'RED'}"; ok &&= !bp
    end
  end
  puts ok ? "selftest_ok: oracle can green on good and red on bad" : "selftest_FAILED"
  exit(ok ? 0 : 1)
end

ARM   = ARGV[0] or abort "usage: probe-064-patterns.rb <arm> <slice-file> [rounds] [model] | --selftest"
SLICE = File.read(ARGV[1])
# Fresh unpredictable cwd per invocation (challenge P2: a predictable shared dir
# could carry a stale/poisoned CLAUDE.md into claude's project-instruction discovery).
neutral = Dir.mktmpdir("probe064-")
at_exit { FileUtils.remove_entry(neutral) if File.directory?(neutral) }

def ask(prompt, neutral)
  # Own process group + TERM->KILL reap on timeout: Timeout alone interrupts the
  # Ruby wait but leaves a hung claude child alive (challenge P2).
  r_out, w_out = IO.pipe; r_err, w_err = IO.pipe; r_in, w_in = IO.pipe
  pid = Process.spawn("claude", "--print", "--tools", "", "--model", MODEL,
                      in: r_in, out: w_out, err: w_err, chdir: neutral, pgroup: true)
  [r_in, w_out, w_err].each(&:close)
  out = +""; err = +""
  reaped = false
  err_reader = Thread.new { err = r_err.read rescue "" }
  begin
    # stdin write lives INSIDE the timed region (a child that stops reading
    # stdin would otherwise block us forever outside the timeout).
    Timeout.timeout(180) do
      w_in.write(prompt); w_in.close
      out = r_out.read
      err_reader.join
      Process.wait(pid)
      reaped = true
    end
  rescue Timeout::Error
    raise "claude timeout after 180s (process group reaped)"
  ensure
    # Reap on EVERY exceptional exit (timeout, EPIPE, anything), not only Timeout.
    unless reaped
      begin Process.kill("-TERM", pid); rescue Errno::ESRCH; end
      sleep 2
      begin Process.kill("-KILL", pid); rescue Errno::ESRCH; end
      begin Process.wait(pid); rescue Errno::ECHILD; end
    end
    [w_in, r_out, r_err].each { |io| io.close unless io.closed? }
  end
  raise "claude rc=#{$?.exitstatus} err=#{err.lines.first}" unless $?.success?
  raise "empty output" if out.strip.empty?
  out
end

results = {}
tasks = ENV["ONLY"] ? TASKS.select { |t| ENV["ONLY"].split(",").include?(t[:id]) } : TASKS
tasks.each do |t|
  prompt = "以下是当前生效的测试技能规则片段。严格按其中规则完成任务。\n\n=====SKILL=====\n#{SLICE}\n=====TASK=====\n#{t[:task]}"
  hits = 0; det = []
  ROUNDS.times do |i|
    begin
      ans = ask(prompt, neutral)
      g = GRADERS[t[:id]].call(ans)
      hits += 1 if g[:pass]
      det << { round: i, pass: g[:pass], detail: g[:detail], ans_sha256: Digest::SHA256.hexdigest(ans), ans_head: ans[0, 400], ans_full: ans[0, 8000], ans_truncated: ans.length > 8000 }
    rescue => e
      det << { round: i, error: e.message[0, 200] }   # error round counts as fail, recorded
    end
    $stderr.puts "#{t[:id]} round #{i}: #{det.last[:error] ? 'ERROR' : det.last[:pass]}"
  end
  results[t[:id]] = { arm: ARM, model: MODEL, pass: hits, of: ROUNDS,
                      slice_sha256: Digest::SHA256.hexdigest(SLICE),
                      prompt_sha256: Digest::SHA256.hexdigest(prompt), details: det }
end
# Writer decision, 3rd same-class challenge finding → REPLACE (convergence by
# deletion): the mutable canonical arm file + in-place merge was the root of
# every clobber/mix finding across three rounds (partial-merge clobber; flock'd
# last-writer-wins; cross-experiment merge without contract checks). Every run
# now writes ONE immutable run file (refused if it somehow exists), embedding
# the run contract (arm/model/rounds/slice sha) in name and payload. Nothing is
# merged implicitly; aggregation is a human/regrade decision over named files.
# The canonical probe-064-<arm>.json files from this round remain as frozen
# historical evidence and are never written by this script again.
run_id = "#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{Process.pid}-#{SecureRandom.hex(4)}"
out_path = File.join(__dir__, "probe-064-#{ARM}-run-#{run_id}.json")
payload = { run: { arm: ARM, model: MODEL, rounds: ROUNDS, run_id: run_id,
                   slice_sha256: Digest::SHA256.hexdigest(SLICE),
                   only: ENV["ONLY"] }, tasks: results }
# Durable-then-publish: write a temp file first, then hard-link it into place —
# link(2) fails with EEXIST if the target exists (no-replace) and is atomic, so
# a crash mid-write can never leave a truncated file wearing the final name.
tmp = File.join(__dir__, ".probe-064-#{ARM}-run-#{run_id}.tmp")
File.write(tmp, JSON.pretty_generate(payload))
File.link(tmp, out_path)
File.unlink(tmp)
puts "wrote #{out_path}"
results.each { |id, r| puts "#{id}: #{r[:pass]}/#{r[:of]}" }
