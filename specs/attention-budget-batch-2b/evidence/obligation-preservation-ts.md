# Obligation-Preservation Table (`testing-strategy`)

Aliases: `MPR_SKILL`=`skills/multi-perspective-research/SKILL.md`, `MPR_PDA`=`.../references/public-data-acquisition.md`, `MPR_ECPM`=`.../references/evidence-controls-and-program-mode.md`, `MPR_PDC`=`.../references/public-disclosure-channels.md`; `SEW_SKILL`=`skills/skill-extraction-workflow/SKILL.md`, `SEW_SRC`=`.../references/source-to-skill-extraction.md`, `SEW_BDR`=`.../references/backend-data-and-redis-extraction.md`, `SEW_DLE`=`.../references/design-and-ledger-extraction.md`, `SEW_VAL`=`.../references/validation-and-landing.md`, `SEW_UIUX`=`.../references/uiux-judgment-extraction.md`; `TAM_BIT`=`skills/test-artifact-management/references/bitable-setup.md`, `TAM_UPD`=`.../references/update-lifecycle.md`; `TS_SKILL`=`skills/testing-strategy/SKILL.md`, `TS_CI`=`.../references/ci-fixtures-and-flake-control.md`, `TS_CRT`=`.../references/client-runtime-test-matrices.md`, `TS_ORAC`=`.../references/design-closed-contract-oracles.md`, `TS_E2E`=`.../references/e2e-real-flow-testing.md`, `TS_ICT`=`.../references/integration-contract-testing.md`, `TS_SCEN`=`.../references/scenario-testing.md`, `TS_STC`=`.../references/structured-tc-input-translation.md`, `TS_AUTH`=`.../references/test-code-authoring-patterns.md`, `TS_TOPO`=`.../references/test-topology-and-commands.md`, `TS_VEND`=`.../references/vendored-contract-drift-checklist.md`, `TS_ENF`=`.../references/verify-enforcement-mechanisms.md`, `TS_FIT`=`.../references/fitness-functions.md`.

|Before (`governing-chain-diff.py`)|Old|After|Status|Proof (Checks 1–4)|
|---|---|---|---|---|
|they add no coverag…|`TS_SKILL#001`(`rw`)|`TS_SKILL:39` `§Core Rules`|`merged`|`c=1`(`they add no coverage …`),`q:`no`=91`;pointer folded inline|
|Reviewers convert t…|`TS_SKILL#002`(`rw`)|`TS_AUTH:368` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`Reviewers convert the…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|Keep a literal only…|`TS_SKILL#003`(`rw`)|`TS_AUTH:368` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`Keep a literal only w…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|otherwise, after co…|`TS_SKILL#004`(`rw`)|`TS_AUTH:368` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`otherwise, after conf…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|Heuristic, exceptio…|`TS_SKILL#005`(`rw`)|`TS_SKILL:39` `§Core Rules`|`merged`|`c=1`(`Do not write change-d…`),`q:`Do not`=6`;pointer folded inline|
|`references/test-co…|`TS_SKILL#006`(`rw`)|`TS_SKILL:39` `§Core Rules`|`merged`|`c=1`(`(`references/test-cod…`),`q:v`;pointer extended inline|
|**Reuse before gene…|`TS_SKILL#007`(`rw`)|`TS_SKILL:41` `§Core Rules`|`merged`|`c=1`(`**Reuse before genera…`),`q:`Before`=5`;tightened inline|
|If coverage exists,…|`TS_SKILL#008`(`rw`)|`TS_AUTH:369` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`If coverage exists, e…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|Duplicate test stru…|`TS_SKILL#009`(`rw`)|`TS_AUTH:369` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`Duplicate test struct…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|**When the change C…|`TS_SKILL#010`(`rw`)|`TS_AUTH:370` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`**When the change COR…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|find the assertions…|`TS_SKILL#011`(`rw`)|`TS_AUTH:370` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`find the assertions t…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|Rewrite each pinned…|`TS_SKILL#012`(`rw`)|`TS_AUTH:370` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`Rewrite each pinned a…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|the corrected form …|`TS_SKILL#013`(`rw`)|`TS_AUTH:370` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`the corrected form is…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|Why the old behavio…|`TS_SKILL#014`(`rw`)|`TS_SKILL:41` `§Core Rules`|`merged`|`c=1`(`on behavior-correctin…`),`q:`every`=8`;tightened inline|
|`references/test-co…|`TS_SKILL#015`(`rw`)|`TS_SKILL:41` `§Core Rules`|`merged`|`c=1`(`(`references/test-cod…`),`q:v`;pointer extended inline|
|**module-level** (t…|`TS_SKILL#016`(`rw`)|`TS_SKILL:48` `§Core Rules`|`merged`|`c=1`(`**module-level** (the…`),`q:v`;tightened inline|
|A change to one sub…|`TS_SKILL#017`(`rw`)|`TS_SCEN:91` `§Composite Pipeline Acceptance Scope`|`rehosted`|`c=1`(`A change to one sub-m…`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|require an end-to-e…|`TS_SKILL#018`(`rw`)|`TS_SCEN:91` `§Composite Pipeline Acceptance Scope`|`rehosted`|`c=1`(`require an end-to-end…`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|Scope and the uncha…|`TS_SKILL#019`(`rw`)|`TS_SCEN:91` `§Composite Pipeline Acceptance Scope`|`subsumed`|`c=1`(`a pure internal refac…`),`q:v`;dedup onto existing TS_SCEN carrier|
|`references/scenari…|`TS_SKILL#020`(`ch`)|`TS_SKILL:48` `§Core Rules`|`merged`|`c=1`(`and **product-level**…`),`q:v`;pointer folded inline|
|(For AI/inference p…|`TS_SKILL#021`(`rw`)|`TS_SCEN:91` `§Composite Pipeline Acceptance Scope`|`rehosted`|`c=1`(`(For AI/inference pip…`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|this rule is the st…|`TS_SKILL#022`(`rw`)|`TS_SCEN:91` `§Composite Pipeline Acceptance Scope`|`rehosted`|`c=1`(`this rule is the stac…`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|Maintain a frozen r…|`TS_SKILL#023`(`rw`)|`TS_SKILL:49` `§Core Rules`|`merged`|`c=1`(`Maintain a frozen reg…`),`q:`every`=8,`not`=54`;tightened inline|
|Tier it so the gate…|`TS_SKILL#024`(`rw`)|`TS_CI:121` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`Tier it so the gate s…`),`q:v`;moved to TS_CI|
|`references/ci-fixt…|`TS_SKILL#025`(`ch`)|`TS_SKILL:49` `§Core Rules`|`merged`|`c=1`(`run it on **every rel…`),`q:`every`=8,`not`=54`;pointer folded inline|
|For AI features, th…|`TS_SKILL#026`(`rw`)|`TS_CI:121` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`For AI features, the …`),`q:v`;-TS_SKILL->+TS_CI(v)|
|the release-blockin…|`TS_SKILL#027`(`rw`)|`TS_CI:121` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`the release-blocking …`),`q:v`;-TS_SKILL->+TS_CI(v)|
|When the same contr…|`TS_SKILL#028`(`rw`)|`TS_SKILL:62` `§Core Rules`|`merged`|`c=1`(`When the same contrac…`),`q:v`;split standalone bullet inline + detail in TS_ICT|
|any exemption/known…|`TS_SKILL#029`(`rw`)|`TS_SKILL:62` `§Core Rules`|`merged`|`c=1`(`any exemption or know…`),`q:`any`=7,`must`=16`;mandatory size-cap clause inline + detail in TS_ICT|
|prove the observed …|`TS_SKILL#030`(`rw`)|`TS_SKILL:63` `§Core Rules`|`merged`|`c=1`(`prove the observed su…`),`q:`not`=54`;tightened inline|
|A denylist of forbi…|`TS_SKILL#031`(`rw`)|`TS_ORAC:13` `§Why A Denylist Cannot Prove A Closed Boundary`|`subsumed`|`c=1`(`A denylist of forbidd…`),`q:v`;dedup onto existing TS_ORAC carrier|
|Mirror the **docume…|`TS_SKILL#032`(`rw`)|`TS_ORAC:5` `§Design Closed-Contract Oracles`|`rehosted`|`c=1`(`Mirror the **document…`),`q:v`;-TS_SKILL->+TS_ORAC(v)|
|don't snapshot a ge…|`TS_SKILL#033`(`rw`)|`TS_ORAC:5` `§Design Closed-Contract Oracles`|`rehosted`|`c=1`(`don't snapshot a gene…`),`q:v`;-TS_SKILL->+TS_ORAC(v)|
|Negative/adversaria…|`TS_SKILL#034`(`rw`)|`TS_ORAC:5` `§Design Closed-Contract Oracles`|`rehosted`|`c=1`(`Negative/adversarial …`),`q:v`;-TS_SKILL->+TS_ORAC(v)|
|when an adversarial…|`TS_SKILL#035`(`rw`)|`TS_ORAC:5` `§Design Closed-Contract Oracles`|`rehosted`|`c=1`(`when an adversarial r…`),`q:v`;-TS_SKILL->+TS_ORAC(v)|
|The denylist failur…|`TS_SKILL#036`(`rw`)|`TS_SKILL:63` `§Core Rules`|`merged`|`c=1`(`report oracle dimensi…`),`q:v`;tightened inline|
|**A clean oracle is…|`TS_SKILL#037`(`rw`)|`TS_ORAC:6` `§Design Closed-Contract Oracles`|`rehosted`|`c=1`(`**A clean oracle is c…`),`q:v`;-TS_SKILL->+TS_ORAC(v)|
|the **shape** of a …|`TS_SKILL#038`(`rw`)|`TS_ORAC:6` `§Design Closed-Contract Oracles`|`rehosted`|`c=1`(`the **shape** of a va…`),`q:v`;-TS_SKILL->+TS_ORAC(v)|
|and **ordering** wh…|`TS_SKILL#039`(`rw`)|`TS_ORAC:6` `§Design Closed-Contract Oracles`|`rehosted`|`c=1`(`and **ordering** wher…`),`q:v`;-TS_SKILL->+TS_ORAC(v)|
|The per-dimension e…|`TS_SKILL#040`(`rw`)|`TS_ORAC:29` `§Per-Dimension Explanations`|`subsumed`|`c=1`(`Failure shape: four c…`),`q:v`;dedup onto existing TS_ORAC carrier|
|**A guard's cases m…|`TS_SKILL#041`(`rw`)|`TS_ORAC:7` `§Design Closed-Contract Oracles`|`rehosted`|`c=1`(`**A guard's cases mus…`),`q:v`;-TS_SKILL->+TS_ORAC(v)|
|The dual-track swee…|`TS_SKILL#042`(`rw`)|`TS_ORAC:33` `§Precision Near-Miss Rows`|`subsumed`|`c=1`(`Relationship to `skil…`),`q:v`;dedup onto existing TS_ORAC carrier|
|The load-bearing in…|`TS_SKILL#043`(`rw`)|`TS_VEND:3` `§Vendored Contract Drift Checklist`|`rehosted`|`c=1`(`The load-bearing inva…`),`q:v`;-TS_SKILL->+TS_VEND(v)|
|This is the test me…|`TS_SKILL#044`(`rw`)|`TS_VEND:3` `§Vendored Contract Drift Checklist`|`rehosted`|`c=1`(`This is the test mech…`),`q:v`;-TS_SKILL->+TS_VEND(v)|
|fixtures hand-built…|`TS_SKILL#045`(`rw`)|`TS_SKILL:67` `§Core Rules`|`merged`|`c=1`(`fixtures hand-built f…`),`q:`only`=27`;pointer added inline|
|With none obtainabl…|`TS_SKILL#046`(`rw`)|`TS_ICT:136` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`With none obtainable,…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|unavailable` and sc…|`TS_SKILL#047`(`rw`)|`TS_ICT:136` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`unavailable` and scop…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|A real sample is un…|`TS_SKILL#048`(`rw`)|`TS_ICT:136` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`A real sample is untr…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|Method, per-cell co…|`TS_SKILL#049`(`rw`)|`TS_ICT:38` `§Agreement — Conformance, Compatibility, Interop — With An External Contract Needs Real Samples`|`subsumed`|`c=1`(`Enumerate the cells t…`),`q:v`;dedup onto existing TS_ICT carrier|
|`references/integra…|`TS_SKILL#050`(`ch`)|`TS_SKILL:168` `§Reference Loading`|`merged`|`c=1`(``references/integrati…`),`q:v`;host:TS_SKILL;v|
|For UI that calls A…|`TS_SKILL#051`(`rw`)|`TS_SKILL:69` `§Core Rules`|`merged`|`c=1`(`For UI that calls API…`),`q:`not`=54`;merged inline|
|Cover the page at t…|`TS_SKILL#052`(`rw`)|`TS_ICT:137` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`Cover the page at thr…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|component/unit test…|`TS_SKILL#053`(`rw`)|`TS_ICT:137` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`component/unit tests …`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|Mocked component te…|`TS_SKILL#054`(`rw`)|`TS_SKILL:69` `§Core Rules`|`merged`|`c=1`(`mocked component test…`),`q:`must not`=4`;merged inline|
|If all mocks return…|`TS_SKILL#055`(`rw`)|`TS_ICT:137` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`If all mocks return i…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|When the pinned inp…|`TS_SKILL#056`(`rw`)|`TS_AUTH:371` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`When the pinned input…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|use the real comman…|`TS_SKILL#057`(`rw`)|`TS_AUTH:371` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`use the real command/…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|For a helper that r…|`TS_SKILL#058`(`rw`)|`TS_AUTH:371` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`For a helper that ret…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|A green test over o…|`TS_SKILL#059`(`rw`)|`TS_AUTH:371` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`A green test over onl…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|(Tests that intenti…|`TS_SKILL#060`(`rw`)|`TS_AUTH:371` `§11. 默认未设路径、有状态辅助函数与字面量复核细则`|`rehosted`|`c=1`(`(Tests that intention…`),`q:v`;-TS_SKILL->+TS_AUTH(v)|
|prove the gate stil…|`TS_SKILL#061`(`rw`)|`TS_SKILL:71` `§Core Rules`|`merged`|`c=1`(`prove the gate still …`),`q:`not`=54`;pointer added inline|
|Put the negative te…|`TS_SKILL#062`(`rw`)|`TS_ICT:138` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`Put the negative test…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|if existing chain-l…|`TS_SKILL#063`(`rw`)|`TS_ICT:138` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`if existing chain-lev…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|Pure DI, rename, im…|`TS_SKILL#064`(`rw`)|`TS_ICT:138` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`Pure DI, rename, impo…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|the job that select…|`TS_SKILL#065`(`rw`)|`TS_SKILL:72` `§Core Rules`|`merged`|`c=1`(`the job that selects …`),`q:v`;pointer added inline|
|When a suite mixes …|`TS_SKILL#066`(`rw`)|`TS_CI:113` `§Conditional-Skip × Job-Selection Executed-Count Guards`|`rehosted`|`c=1`(`When a suite mixes co…`),`q:`must`=10`;moved to TS_CI|
|Any change to job-l…|`TS_SKILL#067`(`rw`)|`TS_CI:113` `§Conditional-Skip × Job-Selection Executed-Count Guards`|`rehosted`|`c=1`(`Any change to job-lev…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|"The tests exist an…|`TS_SKILL#068`(`rw`)|`TS_CI:113` `§Conditional-Skip × Job-Selection Executed-Count Guards`|`rehosted`|`c=1`(`"The tests exist and …`),`q:v`;-TS_SKILL->+TS_CI(v)|
|A new, ported, or m…|`TS_SKILL#069`(`rw`)|`TS_SKILL:73` `§Core Rules`|`merged`|`c=1`(`A new, ported, or mir…`),`q:`not`=54`;pointer folded inline|
|Require a behaviora…|`TS_SKILL#070`(`rw`)|`TS_ENF:5` `§Verify Enforcement Mechanisms`|`rehosted`|`c=1`(`Require a behavioral …`),`q:`Require`=1,`before`=1`;moved to TS_ENF|
|the matrix cells, t…|`TS_SKILL#071`(`rw`)|`TS_ENF:14` `§Behavioral Matrix Cells`|`subsumed`|`c=1`(`A case that cannot be…`),`q:`not`=7`;dedup onto existing TS_ENF carrier|
|Run the matrix only…|`TS_SKILL#072`(`rw`)|`TS_ENF:5` `§Verify Enforcement Mechanisms`|`rehosted`|`c=1`(`Run the matrix only a…`),`q:v`;-TS_SKILL->+TS_ENF(v)|
|Parity claimed from…|`TS_SKILL#073`(`rw`)|`TS_ENF:5` `§Verify Enforcement Mechanisms`|`rehosted`|`c=1`(`Parity claimed from c…`),`q:v`;-TS_SKILL->+TS_ENF(v)|
|When a test is **po…|`TS_SKILL#074`(`rw`)|`TS_ENF:20` `§Port/Mirror Parity`|`subsumed`|`c=1`(`For the sibling oblig…`),`q:v`;dedup onto existing TS_ENF carrier|
|移植对抗输入本身).|`TS_SKILL#075`(`rw`)|`TS_AUTH:342` `§9. 跨栈移植测试：移植对抗输入本身`|`subsumed`|`c=1`(`把一个 stack 的测试移植/镜像到兄弟…`),`q:v`;dedup onto existing TS_AUTH §9|
|A "skip CI" / "no r…|`TS_SKILL#076`(`rw`)|`TS_SKILL:74` `§Core Rules`|`merged`|`c=1`(`A "skip CI" / "no run…`),`q:`not`=54,`only`=27`;pointer added inline|
|When the blocking C…|`TS_SKILL#077`(`rw`)|`TS_CI:122` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`When the blocking CI …`),`q:v`;-TS_SKILL->+TS_CI(v)|
|for a change that c…|`TS_SKILL#078`(`rw`)|`TS_CI:122` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`for a change that can…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|Note where a local …|`TS_SKILL#079`(`rw`)|`TS_CI:122` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`Note where a local ru…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|Separately, a proje…|`TS_SKILL#080`(`rw`)|`TS_CI:122` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`Separately, a project…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|require green statu…|`TS_SKILL#081`(`rw`)|`TS_CI:122` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`require green status,…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|Browser/E2E smoke m…|`TS_SKILL#082`(`rw`)|`TS_SKILL:75` `§Core Rules`|`merged`|`c=1`(`Browser/E2E smoke mus…`),`q:`must`=16,`not`=54`;merged inline|
|For frontend API pa…|`TS_SKILL#083`(`rw`)|`TS_E2E:24` `§Browser E2E Rules`|`rehosted`|`c=1`(`For frontend API page…`),`q:v`;-TS_SKILL->+TS_E2E(v)|
|Capture console err…|`TS_SKILL#084`(`rw`)|`TS_E2E:24` `§Browser E2E Rules`|`subsumed`|`c=1`(`Capture console error…`),`q:`when`=15`;preserved tool-support condition in TS_E2E|
|UI tests and screen…|`TS_SKILL#085`(`rw`)|`TS_SKILL:75` `§Core Rules`|`merged`|`c=1`(`UI tests and screensh…`),`q:`must`=16,`not`=54`;merged inline|
|Assert or visually …|`TS_SKILL#086`(`rw`)|`TS_E2E:24` `§Browser E2E Rules`|`rehosted`|`c=1`(`Assert or visually in…`),`q:v`;-TS_SKILL->+TS_E2E(v)|
|Authentication and …|`TS_SKILL#087`(`rw`)|`TS_SKILL:77` `§Core Rules`|`merged`|`c=1`(`Authentication and ac…`),`q:`before`=18`;pointer added inline|
|Cover identity-inpu…|`TS_SKILL#088`(`rw`)|`TS_SCEN:87` `§Authentication And Account Scenario Matrix`|`rehosted`|`c=1`(`Cover identity-input …`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|If a capability suc…|`TS_SKILL#089`(`rw`)|`TS_SCEN:87` `§Authentication And Account Scenario Matrix`|`rehosted`|`c=1`(`If a capability such …`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|For report-only QA,…|`TS_SKILL#090`(`rw`)|`TS_SKILL:80` `§Core Rules`|`merged`|`c=1`(`For report-only QA, b…`),`q:`no`=91`;pointer added inline|
|This exception appl…|`TS_SKILL#091`(`rw`)|`TS_CI:124` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`This exception applie…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|an agent or automat…|`TS_SKILL#092`(`rw`)|`TS_CI:124` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`an agent or automated…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|Do not weaken the t…|`TS_SKILL#093`(`rw`)|`TS_CI:125` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`Do not weaken the tes…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|For disputed or hig…|`TS_SKILL#094`(`rw`)|`TS_CI:126` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`For disputed or high-…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|a test-only verific…|`TS_SKILL#095`(`rw`)|`TS_CI:126` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`a test-only verificat…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|Its failing regress…|`TS_SKILL#096`(`rw`)|`TS_CI:126` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`Its failing regressio…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|the skip carries th…|`TS_SKILL#097`(`rw`)|`TS_CI:126` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`the skip carries the …`),`q:v`;-TS_SKILL->+TS_CI(v)|
|The QA report is no…|`TS_SKILL#098`(`rw`)|`TS_CI:127` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`The QA report is not …`),`q:v`;-TS_SKILL->+TS_CI(v)|
|red-light evidence …|`TS_SKILL#099`(`rw`)|`TS_CI:127` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`red-light evidence an…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|Live or production …|`TS_SKILL#100`(`rw`)|`TS_CI:128` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`Live or production be…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|when live behavior …|`TS_SKILL#101`(`rw`)|`TS_CI:128` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`when live behavior co…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|do not resolve it b…|`TS_SKILL#102`(`rw`)|`TS_CI:128` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`do not resolve it by …`),`q:v`;-TS_SKILL->+TS_CI(v)|
|A QA report with an…|`TS_SKILL#103`(`rw`)|`TS_CI:129` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`A QA report with an o…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|Verification warnin…|`TS_SKILL#104`(`rw`)|`TS_SKILL:82` `§Core Rules`|`merged`|`c=1`(`Verification warnings…`),`q:`not`=54`;merged inline|
|classify build/bund…|`TS_SKILL#105`(`rw`)|`TS_CI:130` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`Classify build/bundle…`),`q:`before`=11`;moved to TS_CI|
|defer only with rea…|`TS_SKILL#106`(`rw`)|`TS_CI:130` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`defer only with reaso…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|Do not open, merge,…|`TS_SKILL#107`(`rw`)|`TS_SKILL:82` `§Core Rules`|`merged`|`c=1`(`do not open, merge, o…`),`q:`do not`=4,`until`=1`;merged inline|
|The matrix must inc…|`TS_SKILL#108`(`rw`)|`TS_CI:131` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`The matrix must inclu…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|missing layers are …|`TS_SKILL#109`(`rw`)|`TS_CI:131` `§Skip-CI Instructions, Report-Only QA, And Gate Closeout Rules`|`rehosted`|`c=1`(`missing layers are re…`),`q:v`;-TS_SKILL->+TS_CI(v)|
|Do not mark a brows…|`TS_SKILL#110`(`rw`)|`TS_SKILL:84` `§Core Rules`|`merged`|`c=1`(`Do not mark a browser…`),`q:`Do not`=6`;pointer added inline|
|First run the norma…|`TS_SKILL#111`(`rw`)|`TS_E2E:25` `§Browser E2E Rules`|`rehosted`|`c=1`(`First run the normal …`),`q:v`;-TS_SKILL->+TS_E2E(v)|
|launch the emulator…|`TS_SKILL#112`(`rw`)|`TS_E2E:25` `§Browser E2E Rules`|`rehosted`|`c=1`(`launch the emulator/b…`),`q:v`;-TS_SKILL->+TS_E2E(v)|
|Only after that fai…|`TS_SKILL#113`(`rw`)|`TS_E2E:25` `§Browser E2E Rules`|`rehosted`|`c=1`(`Only after that fails…`),`q:v`;-TS_SKILL->+TS_E2E(v)|
|the reviewer confir…|`TS_SKILL#114`(`rw`)|`TS_SKILL:93` `§Step A — Resolve acceptance and TC sources`|`merged`|`c=1`(`cover it as existing-…`),`q:v`;repointed from step 4 to structured-tc-input-translation.md|
|**User provided TC …|`TS_SKILL#115`(`rw`)|`TS_STC:9` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`**User provided TC UR…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|**`.report-config.j…|`TS_SKILL#116`(`rw`)|`TS_STC:10` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`**`.report-config.jso…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|fetch active TCs fr…|`TS_SKILL#117`(`rw`)|`TS_STC:10` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`fetch active TCs from…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|filter out `废弃` rec…|`TS_SKILL#118`(`rw`)|`TS_STC:10` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`filter out `废弃` recor…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|Do not ask the user…|`TS_SKILL#119`(`rw`)|`TS_STC:10` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`Do not ask the user —…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|**No TC source foun…|`TS_SKILL#120`(`rw`)|`TS_STC:11` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`**No TC source found*…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|For product deliver…|`TS_SKILL#121`(`rw`)|`TS_STC:11` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`For product delivery,…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|test code coverage …|`TS_SKILL#122`(`rw`)|`TS_STC:12` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`test code coverage — …`),`q:v`;-TS_SKILL->+TS_STC(v)|
|user journeys, acce…|`TS_SKILL#123`(`rw`)|`TS_STC:12` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`user journeys, accept…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|Test code covers a …|`TS_SKILL#124`(`rw`)|`TS_STC:12` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`Test code covers a br…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|unit-level logic, i…|`TS_SKILL#125`(`rw`)|`TS_STC:12` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`unit-level logic, int…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|These two scopes do…|`TS_SKILL#126`(`rw`)|`TS_STC:12` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`These two scopes do n…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|Test code without a…|`TS_SKILL#127`(`rw`)|`TS_STC:13` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`Test code without a T…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|It runs as part of …|`TS_SKILL#128`(`rw`)|`TS_STC:13` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`It runs as part of co…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|Do not force-add TC…|`TS_SKILL#129`(`rw`)|`TS_STC:13` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`Do not force-add TC I…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|When the underlying…|`TS_SKILL#130`(`rw`)|`TS_STC:13` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`When the underlying c…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|A TC entry without …|`TS_SKILL#131`(`rw`)|`TS_STC:14` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`A TC entry without au…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|manual test, deferr…|`TS_SKILL#132`(`rw`)|`TS_STC:14` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`manual test, deferred…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|The automated repor…|`TS_SKILL#133`(`rw`)|`TS_STC:15` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`The automated report …`),`q:v`;-TS_SKILL->+TS_STC(v)|
|Broader code covera…|`TS_SKILL#134`(`rw`)|`TS_STC:15` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`Broader code coverage…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|coverage reports, C…|`TS_SKILL#135`(`rw`)|`TS_STC:15` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`coverage reports, CI …`),`q:v`;-TS_SKILL->+TS_STC(v)|
|run the full scenar…|`TS_SKILL#136`(`rw`)|`TS_STC:17` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`run the full scenario…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|consult TC list for…|`TS_SKILL#137`(`rw`)|`TS_STC:17` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`consult TC list for a…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|narrow TC list to T…|`TS_SKILL#138`(`rw`)|`TS_STC:18` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`narrow TC list to TCs…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|run scenario matrix…|`TS_SKILL#139`(`rw`)|`TS_STC:18` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`run scenario matrix f…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|**函数 / 接口**:|`TS_SKILL#140`(`rw`)|`TS_STC:19` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`**函数 / 接口**:`),`q:v`;-TS_SKILL->+TS_STC(v)|
|narrow to TCs direc…|`TS_SKILL#141`(`rw`)|`TS_STC:19` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`narrow to TCs directl…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|add negative-path a…|`TS_SKILL#142`(`rw`)|`TS_STC:19` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`add negative-path and…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|After resolving TC …|`TS_SKILL#143`(`rw`)|`TS_SKILL:109` `§Step B — Determine scope (if not already bounded)`|`merged`|`c=1`(`After confirming scop…`),`q:`After`=1`;tightened inline|
|When the input is a…|`TS_SKILL#144`(`rw`)|`TS_SKILL:115` `§When Input Is a Structured TC List`|`merged`|`c=1`(`When the input is a s…`),`q:v`;tightened inline|
|The mapping is dire…|`TS_SKILL#145`(`rw`)|`TS_STC:5` `§Structured TC Input Translation`|`subsumed`|`c=1`(`The mapping is direct…`),`q:v`;dedup onto existing carrier|
|Keep these entrypoi…|`TS_SKILL#146`(`rw`)|`TS_STC:20` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`Keep these entrypoint…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|normalize TC status…|`TS_SKILL#147`(`rw`)|`TS_STC:20` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`normalize TC status b…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|treat `失败` as a reg…|`TS_SKILL#148`(`rw`)|`TS_STC:20` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`treat `失败` as a regre…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|treat `阻塞` as block…|`TS_SKILL#149`(`rw`)|`TS_STC:20` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`treat `阻塞` as blocked…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|exclude `跳过` / `废弃`…|`TS_SKILL#150`(`rw`)|`TS_STC:20` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`exclude `跳过` / `废弃` f…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|treat P0/P1/P2 as b…|`TS_SKILL#151`(`rw`)|`TS_STC:20` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`treat P0/P1/P2 as bus…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|keep TC IDs in side…|`TS_SKILL#152`(`rw`)|`TS_STC:20` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`keep TC IDs in sideca…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|let this skill choo…|`TS_SKILL#153`(`rw`)|`TS_STC:20` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`let this skill choose…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|After pre-check and…|`TS_SKILL#154`(`rw`)|`TS_STC:20` `§Source Resolution, Coverage Gap, And Scope Narrowing`|`rehosted`|`c=1`(`After pre-check and f…`),`q:v`;-TS_SKILL->+TS_STC(v)|
|Discover the reposi…|`TS_SKILL#155`(`rw`)|`TS_SKILL:121` `§Workflow`|`merged`|`c=1`(`Discover the reposito…`),`q:v`;tightened inline|
|Read local guidance…|`TS_SKILL#156`(`rw`)|`TS_TOPO:16` `§Discovery Order`|`rehosted`|`c=1`(`Read local guidance f…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|`AGENTS.md`, `CLAUD…|`TS_SKILL#157`(`rw`)|`TS_TOPO:16` `§Discovery Order`|`rehosted`|`c=1`(``AGENTS.md`, `CLAUDE.…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|Identify default fa…|`TS_SKILL#158`(`rw`)|`TS_TOPO:17` `§Discovery Order`|`rehosted`|`c=1`(`Identify default fast…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|Exclude dependency …|`TS_SKILL#159`(`rw`)|`TS_TOPO:18` `§Discovery Order`|`rehosted`|`c=1`(`Exclude dependency an…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|`node_modules`, vir…|`TS_SKILL#160`(`rw`)|`TS_TOPO:18` `§Discovery Order`|`rehosted`|`c=1`(``node_modules`, virtu…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|Prefer documented w…|`TS_SKILL#161`(`rw`)|`TS_TOPO:19` `§Discovery Order`|`rehosted`|`c=1`(`Prefer documented wra…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|If a frontend or ap…|`TS_SKILL#162`(`rw`)|`TS_TOPO:20` `§Discovery Order`|`rehosted`|`c=1`(`If a frontend or app …`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|Use build/typecheck…|`TS_SKILL#163`(`rw`)|`TS_TOPO:20` `§Discovery Order`|`rehosted`|`c=1`(`Use build/typecheck a…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|If CI mainly builds…|`TS_SKILL#164`(`rw`)|`TS_TOPO:21` `§Discovery Order`|`rehosted`|`c=1`(`If CI mainly builds i…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|It does not prove p…|`TS_SKILL#165`(`rw`)|`TS_TOPO:21` `§Discovery Order`|`rehosted`|`c=1`(`It does not prove pro…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|When adding a new c…|`TS_SKILL#166`(`rw`)|`TS_TOPO:22` `§Discovery Order`|`rehosted`|`c=1`(`When adding a new cli…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|Keep a sample only …|`TS_SKILL#167`(`rw`)|`TS_TOPO:22` `§Discovery Order`|`rehosted`|`c=1`(`Keep a sample only if…`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|otherwise replace i…|`TS_SKILL#168`(`rw`)|`TS_TOPO:22` `§Discovery Order`|`rehosted`|`c=1`(`otherwise replace it …`),`q:v`;-TS_SKILL->+TS_TOPO(v)|
|For API contract ch…|`TS_SKILL#169`(`rw`)|`TS_ICT:132` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`For API contract chan…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|request shape, resp…|`TS_SKILL#170`(`rw`)|`TS_ICT:132` `§Platform Contract / Protobuf / RPC Test Obligations`|`subsumed`|`c=1`(`request shape, respon…`),`q:v`;dedup onto existing carrier|
|If this is missing,…|`TS_SKILL#171`(`rw`)|`TS_ICT:132` `§Platform Contract / Protobuf / RPC Test Obligations`|`subsumed`|`c=1`(`If this is missing, s…`),`q:v`;dedup onto existing carrier|
|For protobuf-backed…|`TS_SKILL#172`(`rw`)|`TS_ICT:133` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`For protobuf-backed H…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|`protobuf-http-cont…|`TS_SKILL#173`(`rw`)|`TS_ICT:133` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(``protobuf-http-contra…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|This skill owns ass…|`TS_SKILL#174`(`rw`)|`TS_ICT:133` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`This skill owns asser…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|platform-service-co…|`TS_SKILL#175`(`rw`)|`TS_ICT:133` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`platform-service-conn…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|For external/gatewa…|`TS_SKILL#176`(`rw`)|`TS_ICT:134` `§Platform Contract / Protobuf / RPC Test Obligations`|`rehosted`|`c=1`(`For external/gateway/…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|Detailed platform c…|`TS_SKILL#177`(`rw`)|`TS_SKILL:128` `§Workflow`|`merged`|`c=1`(`For API, protobuf-bac…`),`q:`not`=54`;tightened inline|
|**A property about …|`TS_SKILL#178`(`rw`)|`TS_ICT:107` `§API And Contract Tests`|`rehosted`|`c=1`(`When the contract say…`),`q:`must`=21,`not`=118`;moved to TS_ICT|
|`references/integra…|`TS_SKILL#179`(`rw`)|`TS_SKILL:137` `§Workflow`|`merged`|`c=1`(`**A property about wh…`),`q:`NOT`=1,`only`=27`;pointer folded inline|
|State the split exp…|`TS_SKILL#180`(`rw`)|`TS_ICT:107` `§API And Contract Tests`|`rehosted`|`c=1`(`State the split expli…`),`q:v`;-TS_SKILL->+TS_ICT(v)|
|for each triggered …|`TS_SKILL#181`(`rw`)|`TS_SKILL:138` `§Workflow`|`merged`|`c=1`(`High-risk resilience …`),`q:v`;pointer added inline|
|idempotency unit/co…|`TS_SKILL#182`(`rw`)|`TS_SCEN:83` `§High-Risk Failure Classes`|`rehosted`|`c=1`(`idempotency unit/cont…`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|auth timeout unit p…|`TS_SKILL#183`(`rw`)|`TS_SCEN:83` `§High-Risk Failure Classes`|`rehosted`|`c=1`(`auth timeout unit plu…`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|AI fallback eval/re…|`TS_SKILL#184`(`rw`)|`TS_SCEN:83` `§High-Risk Failure Classes`|`rehosted`|`c=1`(`AI fallback eval/repl…`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|client double-submi…|`TS_SKILL#185`(`rw`)|`TS_SCEN:83` `§High-Risk Failure Classes`|`rehosted`|`c=1`(`client double-submit …`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|High-risk backend t…|`TS_SKILL#186`(`rw`)|`TS_SCEN:83` `§High-Risk Failure Classes`|`rehosted`|`c=1`(`High-risk backend tes…`),`q:v`;-TS_SKILL->+TS_SCEN(v)|
|For client API-back…|`TS_SKILL#187`(`ch`)|`TS_SKILL:140` `§Workflow`|`merged`|`c=1`(`For client API-backed…`),`q:v`;host:TS_SKILL;v|
|Non-negotiable anch…|`TS_SKILL#188`(`rw`)|`TS_CRT:8` `§Client And Runtime Test Matrices`|`rehosted`|`c=1`(`Non-negotiable anchor…`),`q:v`;-TS_SKILL->+TS_CRT(v)|
|the default three-b…|`TS_SKILL#189`(`rw`)|`TS_CRT:8` `§Client And Runtime Test Matrices`|`rehosted`|`c=1`(`the default three-bou…`),`q:v`;-TS_SKILL->+TS_CRT(v)|
|runtime-dependent s…|`TS_SKILL#190`(`rw`)|`TS_CRT:8` `§Client And Runtime Test Matrices`|`rehosted`|`c=1`(`runtime-dependent smo…`),`q:v`;-TS_SKILL->+TS_CRT(v)|
|developer-tool comp…|`TS_SKILL#191`(`rw`)|`TS_CRT:8` `§Client And Runtime Test Matrices`|`rehosted`|`c=1`(`developer-tool compil…`),`q:v`;-TS_SKILL->+TS_CRT(v)|
|dangerous or irreve…|`TS_SKILL#192`(`rw`)|`TS_CRT:8` `§Client And Runtime Test Matrices`|`rehosted`|`c=1`(`dangerous or irrevers…`),`q:v`;-TS_SKILL->+TS_CRT(v)|
|Build scenario matr…|`TS_SKILL#193`(`rw`)|`TS_CRT:8` `§Client And Runtime Test Matrices`|`rehosted`|`c=1`(`Build scenario matric…`),`q:v`;-TS_SKILL->+TS_CRT(v)|
|do not paste produc…|`TS_SKILL#194`(`rw`)|`TS_CRT:8` `§Client And Runtime Test Matrices`|`rehosted`|`c=1`(`do not paste product-…`),`q:v`;-TS_SKILL->+TS_CRT(v)|
|For E2E, collect co…|`TS_SKILL#195`(`rw`)|`TS_SKILL:153` `§Workflow`|`merged`|`c=1`(`For E2E, capture cons…`),`q:`when`=17,`do not`=4`;preserved tool-support condition + pointer|
|Give smoke/e2e harn…|`TS_SKILL#196`(`rw`)|`TS_E2E:24` `§Browser E2E Rules`|`rehosted`|`c=1`(`Give smoke/e2e harnes…`),`q:v`;-TS_SKILL->+TS_E2E(v)|
|tolerate benign add…|`TS_SKILL#197`(`rw`)|`TS_E2E:24` `§Browser E2E Rules`|`rehosted`|`c=1`(`tolerate benign addre…`),`q:v`;-TS_SKILL->+TS_E2E(v)|
|For source provenan…|`TS_SKILL#198`(`rw`)|`TS_SKILL:163` `§Reference Loading`|`merged`|`c=1`(`Provenance & extracti…`),`q:v`;tightened Reference Loading|
|For discovering rep…|`TS_SKILL#199`(`rw`)|`TS_SKILL:164` `§Reference Loading`|`merged`|`c=1`(`Topology, wrappers, h…`),`q:v`;tightened Reference Loading|
|For scenario matric…|`TS_SKILL#200`(`rw`)|`TS_SKILL:165` `§Reference Loading`|`merged`|`c=1`(`Scenario matrices, pi…`),`q:v`;tightened Reference Loading|
|For unit tests, fak…|`TS_SKILL#201`(`rw`)|`TS_SKILL:166` `§Reference Loading`|`merged`|`c=1`(`Unit tests, fakes, an…`),`q:v`;tightened Reference Loading|
|For test data, fact…|`TS_SKILL#202`(`rw`)|`TS_SKILL:167` `§Reference Loading`|`merged`|`c=1`(`Fixtures, builders, f…`),`q:v`;tightened Reference Loading|
|For API, contract, …|`TS_SKILL#203`(`rw`)|`TS_SKILL:168` `§Reference Loading`|`merged`|`c=1`(`API, contract, protob…`),`q:v`;tightened Reference Loading|
|For client API-back…|`TS_SKILL#204`(`rw`)|`TS_SKILL:169` `§Reference Loading`|`merged`|`c=1`(`Client API surfaces, …`),`q:v`;tightened Reference Loading|
|native-bridge and a…|`TS_SKILL#205`(`rw`)|`TS_SKILL:169` `§Reference Loading`|`merged`|`c=1`(`and async finality: `…`),`q:v`;tightened Reference Loading|
|For batch jobs, ETL…|`TS_SKILL#206`(`rw`)|`TS_SKILL:170` `§Reference Loading`|`merged`|`c=1`(`Batch jobs, streams, …`),`q:v`;tightened Reference Loading|
|For browser, API wo…|`TS_SKILL#207`(`rw`)|`TS_SKILL:171` `§Reference Loading`|`merged`|`c=1`(`Browser, real-flow, p…`),`q:v`;tightened Reference Loading|
|For CI gates, test …|`TS_SKILL#208`(`rw`)|`TS_SKILL:172` `§Reference Loading`|`merged`|`c=1`(`CI gates, external-as…`),`q:v`;tightened Reference Loading|
|For translating str…|`TS_SKILL#209`(`rw`)|`TS_SKILL:173` `§Reference Loading`|`merged`|`c=1`(`Structured TC transla…`),`q:v`;tightened Reference Loading|
|For **how to write …|`TS_SKILL#210`(`rw`)|`TS_SKILL:174` `§Reference Loading`|`merged`|`c=1`(`Test-code authoring p…`),`q:v`;tightened Reference Loading|
|For **architecture …|`TS_SKILL#211`(`rw`)|`TS_SKILL:175` `§Reference Loading`|`merged`|`c=1`(`Architecture fitness …`),`q:v`;tightened Reference Loading|
|2017) — automated t…|`TS_SKILL#212`(`rw`)|`TS_SKILL:175` `§Reference Loading`|`merged`|`c=1`(`2017): `references/fi…`),`q:v`;tightened Reference Loading|
|Different from prod…|`TS_SKILL#213`(`rw`)|`TS_FIT:5` `§Architecture Fitness Functions`|`subsumed`|`c=1`(`不替代普通单测 / e2e；这是**结构性…`),`q:v`;dedup onto existing TS_FIT intro|
|protects structural…|`TS_SKILL#214`(`rw`)|`TS_SKILL:175` `§Reference Loading`|`subsumed`|`c=1`(`Architecture fitness …`),`q:v`;gloss folded; TS_FIT §1 holds ADR rule|
|For the killing-mut…|`TS_SKILL#215`(`rw`)|`TS_SKILL:176` `§Reference Loading`|`merged`|`c=1`(`Killing-mutation walk…`),`q:v`;tightened Reference Loading|
|For closed-contract…|`TS_SKILL#216`(`rw`)|`TS_SKILL:177` `§Reference Loading`|`merged`|`c=1`(`Closed-contract oracl…`),`q:v`;tightened Reference Loading|
|For enforcement-mec…|`TS_SKILL#217`(`rw`)|`TS_SKILL:178` `§Reference Loading`|`merged`|`c=1`(`Enforcement-mechanism…`),`q:v`;tightened Reference Loading|
|Mechanics for the e…|`TS_ORAC#001`(`rw`)|`TS_ORAC:3` `§Design Closed-Contract Oracles`|`merged`|`c=1`(`Mechanics and full ru…`),`q:v`;updated TS_ORAC intro|
|The obligations the…|`TS_ORAC#002`(`rw`)|`TS_ORAC:3` `§Design Closed-Contract Oracles`|`merged`|`c=1`(`and its oracle-dimens…`),`q:v`;updated TS_ORAC intro|
|this file owns the …|`TS_ORAC#003`(`rw`)|`TS_ORAC:3` `§Design Closed-Contract Oracles`|`subsumed`|`c=1`(`Mechanics and full ru…`),`q:v`;scope note folded into TS_ORAC intro|
|Capture console err…|`TS_E2E#001`(`rw`)|`TS_E2E:24` `§Browser E2E Rules`|`merged`|`c=1`(`Capture console error…`),`q:`when`=15`;restored tool-support condition|
|Restated from the e…|`TS_ICT#001`(`rw`)|`TS_ICT:130` `§Platform Contract / Protobuf / RPC Test Obligations`|`subsumed`|`c=1`(`The detailed obligati…`),`q:v`;prefix retired as rule moved here|
|for API contract ch…|`TS_ICT#002`(`rw`)|`TS_ICT:132` `§Platform Contract / Protobuf / RPC Test Obligations`|`merged`|`c=1`(`For API contract chan…`),`q:`first`=13`;capitalized inline|
|request shape, resp…|`TS_ICT#003`(`ch`)|`TS_ICT:132` `§Platform Contract / Protobuf / RPC Test Obligations`|`merged`|`c=1`(`request shape, respon…`),`q:v`;host:TS_ICT;v|
|If this is missing,…|`TS_ICT#004`(`ch`)|`TS_ICT:132` `§Platform Contract / Protobuf / RPC Test Obligations`|`merged`|`c=1`(`If this is missing, s…`),`q:v`;host:TS_ICT;v|
|Mechanics for the e…|`TS_ENF#001`(`rw`)|`TS_ENF:3` `§Verify Enforcement Mechanisms`|`merged`|`c=1`(`Mechanics and full ru…`),`q:v`;updated TS_ENF intro|
|the behavioral matr…|`TS_ENF#002`(`rw`)|`TS_ENF:3` `§Verify Enforcement Mechanisms`|`merged`|`c=1`(`verification obligati…`),`q:v`;updated TS_ENF intro|
|The obligations the…|`TS_ENF#003`(`rw`)|`TS_ENF:5` `§Verify Enforcement Mechanisms`|`merged`|`c=1`(`Run the matrix only a…`),`q:`only`=2,`never`=2`;relocated scratch-only boundary here|
|this file owns what…|`TS_ENF#004`(`rw`)|`TS_ENF:3` `§Verify Enforcement Mechanisms`|`subsumed`|`c=1`(`Mechanics and full ru…`),`q:v`;scope note folded into TS_ENF intro|
