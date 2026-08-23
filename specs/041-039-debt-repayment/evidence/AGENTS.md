# evidence Agent Contract

041 轮的冻结测量工件：槽位 2/9 双删臂与归因臂的 runner、逐轮原始输出（含 `routing_surface` 自识别哈希）、单用例 bank，以及批 1 的两个只读谓词探针。提交进树是为了让 `dispositions.md` 的读数可被独立复核，而不是只能相信起草方的叙述。

规则：

- **落地后冻结。** 不得为让后来的结论更好看而编辑、重判、裁剪或重生成这些文件。要推翻某个读数，就在新一轮的 evidence 目录里放新的测量，并由引用它的台账行说明。
- **这些 runner 是证据工具，不是仓库闸。** `run_arms.sh` 调用活模型，非确定性，绝不接入 `make test` 或任何阻断检查。这里跑绿不证明仓库任何性质，它只记录某一次在钉住的表面上产生了什么。
- **引用数字前先读 runner。** `run_arms.sh` 的突变以逐字节跨度施加、施加后校验 `git diff` 非空（突变确已 applied）、每臂跑完 `git checkout` 复原并以 `git diff --quiet` 校验；每轮的 `--json` 报告内嵌 `descriptions_sha256` 与逐 skill description 行哈希，故「哪一版表面产生了这个数」可独立重算。
- **读数规则先于运行冻结。** 见 `../preregister-slot-2-9-round2.md`（sha256 记录在 `dispositions.md`），它在本目录任何一次运行之前已提交。跑完再换映射是本轮明令排除的形态。
- **`d2_strict.py` / `d2b_probe.py` 是只读探针**，不改任何文件，输出即 `dispositions.md` 批 1 引用的两个命中面数字（51/186 与 3/186）。
- **数字按实测报告。** 与设计预期相反的结果（批 1 的 D2 腿失败）留在记录里，不改判据去迁就它。
- **无凭据、无主机路径、无第三方内容。**

## 独立评审在本目录上找到的两处缺陷（已登记，脚本不追改）

`run_arms.sh` 有两处真实缺陷，由 041 的 review/challenge 两轮独立指出：

1. **不校验 runner 的退出码与报告有效性**，只 grep pass 行——超时或 grader-error 会被静默计成一次「路由失败」，而 `0/5` 正是承重结论所依赖的那个数。
2. **硬编码工作树路径 + 无条件 `git checkout --`**——在别的克隆里会读到无关状态，且会连带丢弃目标文件上无关的未提交改动，而 `git diff --quiet` 仍报干净。

**不修改这个脚本**，因为它是「实际跑出那批数的东西」；改了它，树里的记录就不再对应产生数据的过程。缺陷改为**事后补证**：`verify_arm_reports.py` 逐份校验 10 份报告（`grader_error_total=0`、每份 `tasks==1`、每份 `pass+fail+error==1`、两臂各跑在不同的 `descriptions_sha256`），输出在 `arm-report-verification.txt`。**缺陷成立，但没有咬到本次数据。**

下一次写这类一次性测量 runner 的人：先让它在失败路径上喊出来，再拿它的数去改任何终态。
