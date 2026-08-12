#!/usr/bin/env python3
"""Contract tests for the deterministic evaluator bridge.

The bridge is the only cross-repository surface, so every test here drives it as
a real process: one JSON request on stdin, one JSON response on stdout, typed
exit codes.  Importing the module would prove none of that.
"""

import hashlib
import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


EVAL_DIR = Path(__file__).resolve().parent
TRIAL_DIR = EVAL_DIR / "skill-effectiveness"
BRIDGE_PATH = TRIAL_DIR / "bridge.py"
TRIAL_PATH = TRIAL_DIR / "trial.py"
PROTOCOL_DIR = TRIAL_DIR / "protocol"
REQUEST_SCHEMA_PATH = PROTOCOL_DIR / "request-v1.schema.json"
RESPONSE_SCHEMA_PATH = PROTOCOL_DIR / "response-v1.schema.json"
REQUEST_SCHEMA = "skill-effectiveness.bridge.request.v1"
RESPONSE_SCHEMA = "skill-effectiveness.bridge.response.v1"
ANSI = re.compile(r"\x1b\[")


def load_trial_module():
    spec = importlib.util.spec_from_file_location(
        "skill_effectiveness_trial_for_bridge", TRIAL_PATH
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def request_envelope(action, payload, request_id="req-1", artifact_root=None):
    return {
        "schema": REQUEST_SCHEMA,
        "request_id": request_id,
        "action": action,
        "artifact_root": artifact_root,
        "payload": payload,
    }


def invoke(request, *, raw=None, environment=None):
    text = raw if raw is not None else json.dumps(request)
    completed = subprocess.run(
        [sys.executable, str(BRIDGE_PATH)],
        input=text,
        text=True,
        capture_output=True,
        check=False,
        env=environment,
    )
    return completed


def parse(completed):
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise AssertionError(f"bridge must emit one stdout line, got {len(lines)}")
    return json.loads(lines[0])


# 本校验器**真正求值**的关键字。
_EVALUATED_KEYWORDS = frozenset(
    {
        "const",
        "enum",
        "oneOf",
        "type",
        "properties",
        "required",
        "additionalProperties",
        "items",
    }
)

# 明确记录在案的**收窄型**缺口：它们只在已定型的值内部再收紧，忽略是有文档的已知
# 取舍，不会让节点恒真；连同纯元数据一并放行。组合/引用关键字不在此列。
_NARROWING_IGNORED_KEYWORDS = frozenset(
    {
        "pattern",
        "format",
        "minLength",
        "maxLength",
        "minimum",
        "maximum",
        "exclusiveMinimum",
        "exclusiveMaximum",
        "multipleOf",
        "minItems",
        "maxItems",
        "uniqueItems",
        "description",
        "title",
        "$schema",
        "$id",
        "$defs",
        "$comment",
        "examples",
        "default",
    }
)


def schema_evaluability_errors(schema, path="$"):
    """**文档无关**地遍历 schema 结构，报出本校验器无法求值的节点。

    只拿一份样本文档去验证「schema 仍可完整求值」是空转的：藏在未出现的可选属性、
    未选中的 oneOf 分支或 $defs 下的 unsupported 节点根本不会被访问到。独立评审命中该点。
    """

    if not isinstance(schema, dict):
        return [f"{path}: expected a schema object, got {type(schema).__name__}"]
    errors = []
    unsupported = sorted(set(schema) - _EVALUATED_KEYWORDS - _NARROWING_IGNORED_KEYWORDS)
    if unsupported:
        errors.append(f"{path}: unsupported schema keyword(s) {unsupported}")
    items = schema.get("items")
    if isinstance(items, list):
        errors.append(f"{path}: unsupported tuple-form 'items'")
    elif isinstance(items, dict):
        errors.extend(schema_evaluability_errors(items, f"{path}.items"))
    for group in ("properties", "$defs"):
        for key, child in (schema.get(group) or {}).items():
            errors.extend(schema_evaluability_errors(child, f"{path}.{group}.{key}"))
    for index, branch in enumerate(schema.get("oneOf") or []):
        errors.extend(schema_evaluability_errors(branch, f"{path}.oneOf[{index}]"))
    return errors


def _json_equal(left, right):
    """JSON 语义的相等。Python 的 ``True == 1`` 在 JSON 里为假，故必须先比布尔身份，
    否则 ``{"type": "integer", "const": 1}`` 会接受 ``true``——而 runtime_manifest 的
    ``schema_version`` 正是 ``{"const": 1}``，这条路径真实可达。"""

    if isinstance(left, bool) != isinstance(right, bool):
        return False
    return left == right


def schema_conformance_errors(document, schema, path="$"):
    """闭集一致性检查（**不是**完整的 JSON Schema 校验器）。

    只覆盖本协议实际使用、且历史上真正漂移过的那一类约束：
    ``additionalProperties: false`` 的对象不得出现未声明的键、``required`` 必须齐全、
    ``const``/``enum`` 必须命中、``oneOf`` 至少命中一支、数组逐项递归。
    pattern/format/数值边界不在此实现，由各自的专项断言覆盖。

    存在的理由：既有的 test_protocol_schemas_match_the_implemented_contract 只逐条比对
    schema 的片段（const、enum、顶层 additionalProperties），从不拿一份**真实响应**去校验
    整份 schema。interpreter.user_site_disabled 正是从这个缺口漂进去的——桥发出了自己
    发布的 schema 不允许的字段，任何忠于 schema 的消费者都会拒掉每一次真实响应。
    """

    errors = []
    # 未实现的**组合/引用**关键字会让该节点变成恒真，于是本门静默放行一个合规
    # 消费者会拒绝的文档——与 oneOf 同一失败类，由第一性自审发现。故先 fail-closed：
    # 不认识的约束性关键字一律报错，逼后来者扩展本校验器而不是无声通过。
    unsupported = sorted(set(schema) - _EVALUATED_KEYWORDS - _NARROWING_IGNORED_KEYWORDS)
    if unsupported:
        return [
            f"{path}: unsupported schema keyword(s) {unsupported} — this checker cannot "
            f"evaluate this node and refuses to pass it silently"
        ]
    if isinstance(schema.get("items"), list):
        return [
            f"{path}: unsupported tuple-form 'items' — this checker cannot evaluate it "
            f"and refuses to pass it silently"
        ]

    # const/enum/oneOf 不再提前返回：同级关键字（type、additionalProperties 等）必须
    # 一并求值，否则本门会放行一个合规消费者会拒绝的文档。独立评审命中该缺陷。
    if "const" in schema and not _json_equal(document, schema["const"]):
        errors.append(f"{path}: expected const {schema['const']!r}, got {document!r}")
    if "enum" in schema and not any(
        _json_equal(document, allowed) for allowed in schema["enum"]
    ):
        errors.append(f"{path}: {document!r} is outside the closed set {schema['enum']}")
    if "oneOf" in schema:
        # oneOf 是「恰好命中一支」，不是 anyOf。用 any() 会让同时命中两支的文档
        # 通过本门，而一个真正合规的消费者会拒绝它——对一个准备被依赖的共享门来说，
        # 这是静默放行。独立评审命中该语义错误。
        matched = sum(
            1
            for branch in schema["oneOf"]
            if not schema_conformance_errors(document, branch, path)
        )
        if matched != 1:
            errors.append(
                f"{path}: {document!r} matches {matched} oneOf branches, expected exactly 1"
            )

    declared = schema.get("type")
    if declared == "object":
        if not isinstance(document, dict):
            errors.append(f"{path}: expected an object, got {type(document).__name__}")
            return errors
        properties = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in document:
                errors.append(f"{path}.{key}: required property is missing")
        if schema.get("additionalProperties") is False:
            for key in document:
                if key not in properties:
                    errors.append(
                        f"{path}.{key}: undeclared property under additionalProperties=false"
                    )
        for key, value in document.items():
            if key in properties:
                errors.extend(
                    schema_conformance_errors(value, properties[key], f"{path}.{key}")
                )
        return errors
    if declared == "array":
        if not isinstance(document, list):
            errors.append(f"{path}: expected an array, got {type(document).__name__}")
            return errors
        item_schema = schema.get("items")
        if item_schema:
            for index, item in enumerate(document):
                errors.extend(
                    schema_conformance_errors(item, item_schema, f"{path}[{index}]")
                )
        return errors
    if declared == "null" and document is not None:
        errors.append(f"{path}: expected null")
    if declared == "string" and not isinstance(document, str):
        errors.append(f"{path}: expected a string")
    if declared == "boolean" and not isinstance(document, bool):
        errors.append(f"{path}: expected a boolean")
    if declared == "integer" and (
        not isinstance(document, int) or isinstance(document, bool)
    ):
        errors.append(f"{path}: expected an integer")
    return errors


class BridgeContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.trial = load_trial_module()
        cls.manifest = cls.probe_manifest()

    @classmethod
    def probe_manifest(cls):
        completed = invoke(request_envelope("probe", {"phase": "manifest"}))
        if completed.returncode != 0:
            raise AssertionError(f"manifest probe failed: {completed.stderr}")
        return parse(completed)["result"]["runtime_manifest"]

    def assertResponseShape(self, completed, response, status, exit_code):
        self.assertEqual(exit_code, completed.returncode, completed.stderr)
        self.assertEqual(RESPONSE_SCHEMA, response["schema"])
        self.assertEqual(
            {
                "schema",
                "request_id",
                "status",
                "reason_code",
                "runtime_binding",
                "result",
            },
            set(response),
        )
        self.assertEqual(status, response["status"])
        self.assertIsNone(ANSI.search(completed.stdout))
        completed.stdout.encode("utf-8")

    def test_the_conformance_checker_enforces_exactly_one_oneof_branch(self):
        # 校验器本身是共享门，其 oneOf 语义必须是「恰好一支」。分支重叠的文档
        # 必须被拒，否则本门会放行一个合规消费者会拒绝的响应。
        overlapping = {"oneOf": [{"type": "string"}, {"enum": ["x"]}]}
        self.assertNotEqual([], schema_conformance_errors("x", overlapping))
        self.assertEqual([], schema_conformance_errors("y", overlapping))
        self.assertNotEqual([], schema_conformance_errors(7, overlapping))

        disjoint = {"oneOf": [{"type": "null"}, {"type": "string"}]}
        self.assertEqual([], schema_conformance_errors(None, disjoint))
        self.assertEqual([], schema_conformance_errors("v", disjoint))
        self.assertNotEqual([], schema_conformance_errors(7, disjoint))

    def test_the_conformance_checker_fails_closed_on_keywords_it_cannot_evaluate(self):
        # 第一性自审发现：未实现的**组合/引用**关键字会让该节点变成恒真，于是本门
        # 静默放行一个合规消费者会拒绝的文档——与外部 challenge 抓到的 oneOf 同一
        # 失败类。$ref 在请求 schema 里真的在用（pinned_manifest）。
        for keyword, schema, document in [
            ("$ref", {"$ref": "#/$defs/runtime_manifest"}, "anything at all"),
            ("allOf", {"allOf": [{"type": "string"}]}, 12345),
            ("anyOf", {"anyOf": [{"type": "string"}]}, 12345),
            ("not", {"not": {"type": "string"}}, "a string"),
            ("if", {"if": {"type": "string"}, "then": {"const": "x"}}, 1),
            ("tuple items", {"type": "array", "items": [{"type": "string"}]}, [1]),
        ]:
            errors = schema_conformance_errors(document, schema)
            self.assertNotEqual([], errors, f"{keyword} 必须 fail-closed 而不是静默放行")
            self.assertIn("unsupported", " ".join(errors), keyword)

        # 明确记录在案的**收窄型**缺口不 fail-closed：它们只在已定型的值内部再收紧，
        # 忽略是有文档的已知取舍，不会让节点恒真。
        for narrowing in [
            {"type": "string", "pattern": "^sha256:"},
            {"type": "string", "minLength": 4},
            {"type": "integer", "minimum": 0},
            {"type": "array", "items": {"type": "string"}, "minItems": 1},
        ]:
            self.assertEqual([], schema_conformance_errors(
                "sha256:x" if narrowing.get("type") == "string" else (
                    1 if narrowing.get("type") == "integer" else ["a"]
                ), narrowing))

        # 真实响应 schema 必须**文档无关地**完整可求值：只验一份样本文档会漏掉藏在
        # 未出现的可选属性/未选中分支/$defs 下的节点（独立评审命中该空转点）。
        response_schema = json.loads(RESPONSE_SCHEMA_PATH.read_text(encoding="utf-8"))
        self.assertEqual([], schema_evaluability_errors(response_schema))
        probe = parse(invoke(request_envelope("probe", {"phase": "manifest"})))
        self.assertEqual([], schema_conformance_errors(probe, response_schema))

        # 遍历必须真的文档无关：藏在从不出现的可选属性下的 unsupported 节点也要报出。
        hidden = {
            "type": "object",
            "properties": {"never_present": {"allOf": [{"type": "string"}]}},
        }
        self.assertNotEqual([], schema_evaluability_errors(hidden))
        self.assertEqual([], schema_conformance_errors({}, hidden))

        # 请求 schema 的不可求值节点必须是**已知且被钉住**的那一个，而不是未知状态：
        # pinned_manifest 用了 $ref。新增任何一个都会让这条断言 RED。
        request_schema = json.loads(REQUEST_SCHEMA_PATH.read_text(encoding="utf-8"))
        request_gaps = schema_evaluability_errors(request_schema)
        self.assertEqual(1, len(request_gaps), request_gaps)
        self.assertIn("pinned_manifest", request_gaps[0])
        self.assertIn("$ref", request_gaps[0])

    def test_the_conformance_checker_is_json_typed_and_evaluates_sibling_keywords(self):
        # Python 的 True == 1，但 JSON 里 true 不是 1。runtime_manifest.schema_version
        # 就是 {"const": 1}，所以这条路径真实可达。
        self.assertNotEqual(
            [], schema_conformance_errors(True, {"type": "integer", "const": 1})
        )
        self.assertEqual([], schema_conformance_errors(1, {"type": "integer", "const": 1}))
        self.assertNotEqual([], schema_conformance_errors(True, {"enum": [1, 0]}))
        self.assertEqual([], schema_conformance_errors(True, {"enum": [True, False]}))

        # const/enum/oneOf 不得提前返回而吞掉同级关键字。
        self.assertNotEqual(
            [], schema_conformance_errors(7, {"type": "string", "enum": [7]})
        )
        both = {
            "oneOf": [{"type": "null"}, {"type": "object"}],
            "type": "object",
            "additionalProperties": False,
            "properties": {},
        }
        self.assertNotEqual([], schema_conformance_errors({"extra": 1}, both))
        self.assertEqual([], schema_conformance_errors({}, both))

    def test_the_bridge_really_emits_the_required_user_site_evidence(self):
        # 兼容性证据必须在包内可核验，而不是只写在说明里：本仓是该 v1 响应的唯一
        # 生产者，这条断言证明它确实无条件发出该必填字段；停发即 RED。
        probe = parse(invoke(request_envelope("probe", {"phase": "manifest"})))
        interpreter = probe["runtime_binding"]["interpreter"]
        self.assertIn("user_site_disabled", interpreter)
        self.assertIsInstance(interpreter["user_site_disabled"], bool)
        source = BRIDGE_PATH.read_text(encoding="utf-8")
        self.assertIn("\"user_site_disabled\": bool(sys.flags.no_user_site)", source)

    def test_every_real_response_validates_against_the_published_response_schema(self):
        # 片段比对不等于一致性：必须拿真实响应整份过 schema，否则桥可以合法地
        # 发出自己 schema 不允许的字段，而所有忠于 schema 的消费者都会拒收。
        response_schema = json.loads(RESPONSE_SCHEMA_PATH.read_text(encoding="utf-8"))
        cases = [
            ("manifest probe", request_envelope("probe", {"phase": "manifest"}), None, 0),
            (
                "full probe",
                request_envelope(
                    "probe", {"phase": "full", "pinned_manifest": self.manifest}
                ),
                None,
                0,
            ),
            ("unparseable request", None, "not json at all", 2),
            (
                "unsupported action",
                {**request_envelope("probe", {"phase": "manifest"}), "action": "nope"},
                None,
                2,
            ),
        ]
        for label, request, raw, exit_code in cases:
            with self.subTest(label):
                completed = invoke(request, raw=raw)
                self.assertEqual(exit_code, completed.returncode, completed.stderr)
                errors = schema_conformance_errors(parse(completed), response_schema)
                self.assertEqual([], errors, f"{label}: {errors}")

    def test_protocol_schemas_match_the_implemented_contract(self):
        request_schema = json.loads(REQUEST_SCHEMA_PATH.read_text(encoding="utf-8"))
        response_schema = json.loads(RESPONSE_SCHEMA_PATH.read_text(encoding="utf-8"))
        self.assertEqual(REQUEST_SCHEMA, request_schema["properties"]["schema"]["const"])
        self.assertEqual(
            RESPONSE_SCHEMA, response_schema["properties"]["schema"]["const"]
        )
        self.assertFalse(request_schema["additionalProperties"])
        self.assertFalse(response_schema["additionalProperties"])
        probe = parse(
            invoke(
                request_envelope(
                    "probe", {"phase": "full", "pinned_manifest": self.manifest}
                )
            )
        )
        self.assertEqual(
            sorted(request_schema["properties"]["action"]["enum"]),
            sorted(probe["result"]["supported_actions"]),
        )
        self.assertEqual(
            ["blocked", "error", "ok"],
            sorted(response_schema["properties"]["status"]["enum"]),
        )
        self.assertEqual(
            sorted(probe["result"]["reason_codes"]),
            sorted(response_schema["properties"]["reason_code"]["oneOf"][0]["enum"]),
        )
        checkpoint_payload = {
            "trial_path": "task/sample-1",
            "status": "completed",
            "access_audit_complete": False,
            "access_roots_enforced": False,
        }
        self.assertEqual(
            [],
            schema_conformance_errors(
                checkpoint_payload,
                request_schema["$defs"]["checkpoint_payload"],
            ),
        )
        for missing_field in ("access_audit_complete", "access_roots_enforced"):
            incomplete_payload = dict(checkpoint_payload)
            incomplete_payload.pop(missing_field)
            self.assertNotEqual(
                [],
                schema_conformance_errors(
                    incomplete_payload,
                    request_schema["$defs"]["checkpoint_payload"],
                ),
                missing_field,
            )
        self.assertEqual(
            [],
            schema_conformance_errors(
                {"trial_path": "task/sample-1", "status": "running"},
                request_schema["$defs"]["checkpoint_payload"],
            ),
        )

    def test_manifest_probe_enumerates_code_and_configuration_without_import(self):
        completed = invoke(request_envelope("probe", {"phase": "manifest"}))
        response = parse(completed)
        self.assertResponseShape(completed, response, "ok", 0)
        result = response["result"]
        self.assertEqual("manifest", result["phase"])
        entries = {entry["path"]: entry for entry in result["runtime_manifest"]["entries"]}
        for expected in (
            "bridge.py",
            "trial.py",
            "active_control.py",
            "pilot-gates.json",
            "protocol/request-v1.schema.json",
            "protocol/response-v1.schema.json",
        ):
            self.assertIn(expected, entries)
        for path, entry in entries.items():
            digest = hashlib.sha256((TRIAL_DIR / path).read_bytes()).hexdigest()
            self.assertEqual(f"sha256:{digest}", entry["sha256"])
            self.assertEqual((TRIAL_DIR / path).stat().st_size, entry["size"])
        self.assertNotIn("configuration", result)
        binding = response["runtime_binding"]
        self.assertEqual(
            result["runtime_manifest"]["manifest_hash"], binding["manifest_hash"]
        )
        self.assertEqual(
            entries["bridge.py"]["sha256"], binding["bridge_hash"]
        )
        self.assertFalse(Path(binding["interpreter"]["resolved_executable"]).is_symlink())

    def test_full_probe_binds_the_pinned_manifest_and_fails_closed_on_drift(self):
        completed = invoke(
            request_envelope(
                "probe", {"phase": "full", "pinned_manifest": self.manifest}
            )
        )
        response = parse(completed)
        self.assertResponseShape(completed, response, "ok", 0)
        result = response["result"]
        self.assertEqual("full", result["phase"])
        self.assertEqual(
            ["checkpoint", "evaluate", "prepare", "probe"],
            sorted(result["supported_actions"]),
        )
        configuration = result["configuration"]
        self.assertEqual(
            sorted(self.trial.EVIDENCE_TIERS), sorted(configuration["evidence_tiers"])
        )
        self.assertEqual(
            sorted(self.trial.ADVISORY_WAIVABLE_ITEMS),
            sorted(configuration["advisory_waivable_items"]),
        )
        self.assertEqual(
            {
                "paired-profile": {
                    "schema_version": 1,
                    "requested_tier": "advisory-paired",
                    "waived_items": sorted(self.trial.ADVISORY_WAIVABLE_ITEMS),
                },
                "skill-content": {
                    "schema_version": 1,
                    "requested_tier": "causal",
                    "waived_items": [],
                },
            },
            configuration["checkpoint_evidence_tiers"],
        )
        self.assertEqual(
            self.trial.canonical_hash(
                json.loads((TRIAL_DIR / "pilot-gates.json").read_text(encoding="utf-8"))
            ),
            configuration["pilot_gates_hash"],
        )
        self.assertIn("profile_arm_templates", configuration)

        tampered = json.loads(json.dumps(self.manifest))
        tampered["entries"][0]["sha256"] = "sha256:" + "0" * 64
        drifted = invoke(
            request_envelope("probe", {"phase": "full", "pinned_manifest": tampered})
        )
        drifted_response = parse(drifted)
        self.assertResponseShape(drifted, drifted_response, "blocked", 3)
        self.assertEqual("unsupported_evaluator", drifted_response["reason_code"])

        shortened = json.loads(json.dumps(self.manifest))
        shortened["entries"] = shortened["entries"][:-1]
        missing_entry = invoke(
            request_envelope("probe", {"phase": "full", "pinned_manifest": shortened})
        )
        self.assertEqual(3, missing_entry.returncode)
        self.assertEqual(
            "unsupported_evaluator", parse(missing_entry)["reason_code"]
        )

        unknown_entry = json.loads(json.dumps(self.manifest))
        unknown_entry["entries"].append(
            {"path": "run.py", "sha256": "sha256:" + "1" * 64, "size": 1}
        )
        extra = invoke(
            request_envelope(
                "probe", {"phase": "full", "pinned_manifest": unknown_entry}
            )
        )
        self.assertEqual(3, extra.returncode)
        self.assertEqual("unsupported_evaluator", parse(extra)["reason_code"])

    def test_invalid_requests_fail_closed_without_echoing_the_payload(self):
        secret = "private-analysis-text-do-not-echo"
        cases = [
            (dict(request_envelope("probe", {"phase": "manifest"}), schema="other"), 2),
            (dict(request_envelope("probe", {"phase": "manifest"}), action="rollback"), 2),
            (
                {**request_envelope("probe", {"phase": "manifest"}), "extra": secret},
                2,
            ),
            (request_envelope("probe", {"phase": secret}), 2),
            (request_envelope("probe", {"phase": "manifest"}, request_id="../escape"), 2),
        ]
        for request, exit_code in cases:
            with self.subTest(request=request.get("action")):
                completed = invoke(request)
                response = parse(completed)
                self.assertResponseShape(completed, response, "error", exit_code)
                self.assertEqual("protocol_mismatch", response["reason_code"])
                self.assertNotIn(secret, completed.stdout)
                self.assertNotIn(secret, completed.stderr)
                self.assertEqual({}, response["result"])

        not_json = invoke(None, raw="{not json")
        self.assertEqual(2, not_json.returncode)
        self.assertEqual("protocol_mismatch", parse(not_json)["reason_code"])

        oversized = invoke(
            None,
            raw=json.dumps(
                request_envelope("probe", {"phase": "manifest", "pad": "x" * 2_000_000})
            ),
        )
        self.assertEqual(2, oversized.returncode)
        self.assertEqual("protocol_mismatch", parse(oversized)["reason_code"])

        empty = invoke(None, raw="")
        self.assertEqual(2, empty.returncode)

    def test_artifact_root_must_be_an_absolute_private_path_outside_the_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            outside = Path(directory) / "store"
            outside.mkdir(mode=0o700)
            for artifact_root, reason in (
                (None, "evidence_invalid"),
                ("relative/path", "evidence_invalid"),
                (str(TRIAL_DIR / "inside"), "evidence_invalid"),
            ):
                completed = invoke(
                    request_envelope(
                        "checkpoint",
                        {"trial_path": "t/a/sample-001", "status": "running"},
                        artifact_root=artifact_root,
                    )
                )
                response = parse(completed)
                self.assertIn(completed.returncode, (2, 3))
                self.assertEqual(reason, response["reason_code"])
            probe_with_root = invoke(
                request_envelope(
                    "probe", {"phase": "manifest"}, artifact_root=str(outside)
                )
            )
            self.assertEqual(2, probe_with_root.returncode)
            self.assertEqual(
                "protocol_mismatch", parse(probe_with_root)["reason_code"]
            )

    def prepare_payload(self, arm_id="profile-full", registry_schema="paired-profile"):
        trial = self.trial
        if registry_schema == "paired-profile":
            manifest = trial.freeze_profile_arm_manifest(
                {
                    "schema_version": 1,
                    "registry_schema": "paired-profile",
                    "arm_id": arm_id,
                    "scope": "main",
                    "treatment": "full",
                    "allowlisted_diff": ["profile_payload"],
                    "runnable": True,
                },
                {
                    "task_builder_template": b"task-builder-revision-1",
                    "task": b"synthetic-analysis-task",
                    "driver": b"fixture-driver",
                    "model": b"deterministic-no-model-call",
                    "prompt_template": b"prompt-template-v1",
                    "permission_profile": b"analysis-read-only",
                    "profile_payload": b"candidate-profile-text",
                },
            )
        else:
            manifest = trial.freeze_arm_manifest(
                {
                    "schema_version": 1,
                    "arm_id": arm_id,
                    "scope": "main",
                    "treatment": "full",
                    "allowlisted_diff": ["ccl_layer"],
                    "runnable": True,
                    "active_control_selection": {"status": "not-applicable"},
                },
                {
                    "system_prompt": b"synthetic-system",
                    "bootstrap": b"",
                    "skill_inventory": b"",
                    "tool_schema": b"synthetic-tools",
                    "hook_command_config": b"",
                    "repo_instructions": b"synthetic-repo-contract",
                    "ccl_layer": b"bundle",
                },
            )
        task = {
            "task_id": "t1",
            "task_family": "review",
            "cohort": "known-regression",
            "prompt_ref": "fixture://t1",
            "expected_owners": ["ccl-skills:testing-strategy"],
            "frozen_at_sha": "a" * 40,
            "corpus_version": "test-v1",
        }
        runtime = {
            "provider": "fixture",
            "model": "deterministic",
            "session_id": "fresh-t1-full-1",
            "isolation_config_hash": "sha256:" + "c" * 64,
            "runner_hash": "sha256:" + "d" * 64,
            "experiment_plan_hash": "sha256:" + "e" * 64,
        }
        return {
            "registry_schema": registry_schema,
            "task": task,
            "manifest": manifest,
            "runtime": runtime,
            "budget": {
                "tokens": None,
                "wall_time_seconds": None,
                "tool_calls": None,
                "cost_units": None,
            },
            "sample_index": 1,
        }

    def test_prepare_and_checkpoint_reuse_the_trial_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "store"
            root.mkdir(mode=0o700)
            payload = self.prepare_payload()
            completed = invoke(
                request_envelope("prepare", payload, artifact_root=str(root))
            )
            response = parse(completed)
            self.assertResponseShape(completed, response, "ok", 0)
            trial_path = response["result"]["trial_path"]
            self.assertEqual("t1/profile-full/sample-001", trial_path)
            self.assertTrue((root / "trials" / trial_path / "trial.json").exists())
            self.assertEqual("created", response["result"]["mode"])
            self.assertEqual(0, response["result"]["state_version"])
            # No absolute private-store path may cross the process boundary.
            self.assertNotIn(str(root), completed.stdout)
            checkpoint = invoke(
                request_envelope(
                    "checkpoint",
                    {
                        "trial_path": trial_path,
                        "status": "running",
                        "resume_cursor": {
                            "next_run_order": 1,
                            "consumed_budget": {
                                "tokens": 0,
                                "wall_time_seconds": 0,
                                "tool_calls": 0,
                                "cost_units": 0,
                            },
                        },
                    },
                    request_id="req-2",
                    artifact_root=str(root),
                )
            )
            checkpoint_response = parse(checkpoint)
            self.assertResponseShape(checkpoint, checkpoint_response, "ok", 0)
            self.assertEqual(1, checkpoint_response["result"]["state_version"])
            self.assertEqual(
                {
                    "schema_version": 1,
                    "requested_tier": "advisory-paired",
                    "waived_items": sorted(self.trial.ADVISORY_WAIVABLE_ITEMS),
                },
                checkpoint_response["result"]["evidence_tier"],
            )
            # A non-completion evaluated no isolation, which must not read as an
            # empty set of waivers.
            self.assertIsNone(
                checkpoint_response["result"]["coverage_limitations"]
            )
            trial_dir = root / "trials" / trial_path
            checkout = root / "agent-checkout"
            checkout.mkdir(mode=0o700)
            self.trial.write_jsonl_atomic(
                trial_dir / "events.jsonl",
                [
                    {
                        "event_contract": "trial-lifecycle-v1",
                        "type": "runner-complete",
                        "skills_invoked": [],
                    }
                ],
            )
            self.trial.write_jsonl_atomic(trial_dir / "access-audit.jsonl", [])
            self.trial.write_json_atomic(
                trial_dir / "outcome" / "result.json", {"passed": True}
            )
            completion = invoke(
                request_envelope(
                    "checkpoint",
                    {
                        "trial_path": trial_path,
                        "status": "completed",
                        "isolation_evidence": {
                            "fresh_session": None,
                            "forked_from_existing": None,
                            "auto_memory_enabled": None,
                            "vector_retrieval_enabled": None,
                            "session_recall_enabled": None,
                            "cross_session_cache_enabled": None,
                            "provider_persistence": "unverified",
                            "canary_leak_detected": None,
                        },
                        "read_allow_roots": [str(checkout)],
                        "write_allow_roots": [str(trial_dir / "outcome")],
                        "access_audit_complete": False,
                        "access_roots_enforced": False,
                        "expected_state_version": 1,
                    },
                    request_id="req-3",
                    artifact_root=str(root),
                )
            )
            completion_response = parse(completion)
            self.assertResponseShape(completion, completion_response, "ok", 0)
            self.assertEqual(2, completion_response["result"]["state_version"])
            self.assertEqual(
                [
                    "access_root_enforcement",
                    "complete_access_audit",
                    "memory_isolation_proof",
                    "provider_side_persistence_proof",
                ],
                completion_response["result"]["coverage_limitations"],
            )
            completed_artifact = self.trial.load_private_json(
                trial_dir / "trial.json"
            )
            self.assertEqual(
                completed_artifact["completion_isolation"]["coverage_limitations"],
                completion_response["result"]["coverage_limitations"],
            )

    def test_completed_checkpoint_requires_explicit_audit_declarations(self):
        for omitted_field in (
            "access_audit_complete",
            "access_roots_enforced",
        ):
            with self.subTest(omitted_field), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / "store"
                root.mkdir(mode=0o700)
                prepared = invoke(
                    request_envelope(
                        "prepare",
                        self.prepare_payload(),
                        artifact_root=str(root),
                    )
                )
                prepared_response = parse(prepared)
                self.assertResponseShape(prepared, prepared_response, "ok", 0)
                trial_path = prepared_response["result"]["trial_path"]
                trial_dir = root / "trials" / trial_path
                checkout = root / "agent-checkout"
                checkout.mkdir(mode=0o700)
                self.trial.write_jsonl_atomic(
                    trial_dir / "events.jsonl",
                    [
                        {
                            "event_contract": "trial-lifecycle-v1",
                            "type": "runner-complete",
                            "skills_invoked": [],
                        }
                    ],
                )
                self.trial.write_jsonl_atomic(
                    trial_dir / "access-audit.jsonl",
                    [
                        {
                            "actor": "tested-agent",
                            "operation": "read",
                            "path": str(checkout / "task.json"),
                        },
                        {
                            "actor": "tested-agent",
                            "operation": "write",
                            "path": str(trial_dir / "outcome" / "result.json"),
                        },
                    ],
                )
                self.trial.write_json_atomic(
                    trial_dir / "outcome" / "result.json", {"passed": True}
                )
                checkpoint_payload = {
                    "trial_path": trial_path,
                    "status": "completed",
                    "isolation_evidence": {
                        "fresh_session": True,
                        "forked_from_existing": False,
                        "auto_memory_enabled": False,
                        "vector_retrieval_enabled": False,
                        "session_recall_enabled": False,
                        "cross_session_cache_enabled": False,
                        "provider_persistence": "disabled",
                        "canary_leak_detected": False,
                    },
                    "read_allow_roots": [str(checkout)],
                    "write_allow_roots": [str(trial_dir / "outcome")],
                    "access_audit_complete": True,
                    "access_roots_enforced": True,
                    "expected_state_version": 0,
                }
                checkpoint_payload.pop(omitted_field)
                completed = invoke(
                    request_envelope(
                        "checkpoint",
                        checkpoint_payload,
                        request_id=f"missing-{omitted_field}",
                        artifact_root=str(root),
                    )
                )
                response = parse(completed)
                self.assertResponseShape(completed, response, "error", 2)
                self.assertEqual("protocol_mismatch", response["reason_code"])

    def test_checkpoint_defers_missing_registry_schema_to_completion(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "store"
            root.mkdir(mode=0o700)
            completed = invoke(
                request_envelope(
                    "prepare",
                    self.prepare_payload(
                        arm_id="S2",
                        registry_schema="skill-content",
                    ),
                    artifact_root=str(root),
                )
            )
            response = parse(completed)
            self.assertResponseShape(completed, response, "ok", 0)
            trial_path = response["result"]["trial_path"]
            trial_file = root / "trials" / trial_path / "trial.json"
            unversioned_artifact = self.trial.load_private_json(trial_file)
            unversioned_artifact.pop("registry_schema")
            self.trial.write_json_atomic(trial_file, unversioned_artifact)

            checkpoint = invoke(
                request_envelope(
                    "checkpoint",
                    {
                        "trial_path": trial_path,
                        "status": "running",
                        "resume_cursor": {
                            "next_run_order": 1,
                            "consumed_budget": {
                                "tokens": 0,
                                "wall_time_seconds": 0,
                                "tool_calls": 0,
                                "cost_units": 0,
                            },
                        },
                    },
                    request_id="missing-registry-checkpoint",
                    artifact_root=str(root),
                )
            )
            checkpoint_response = parse(checkpoint)
            self.assertResponseShape(checkpoint, checkpoint_response, "ok", 0)
            self.assertIsNone(checkpoint_response["result"]["evidence_tier"])

            trial_dir = root / "trials" / trial_path
            checkout = root / "agent-checkout"
            checkout.mkdir(mode=0o700)
            self.trial.write_jsonl_atomic(
                trial_dir / "events.jsonl",
                [
                    {
                        "event_contract": "trial-lifecycle-v1",
                        "type": "runner-complete",
                        "skills_invoked": [],
                    }
                ],
            )
            self.trial.write_jsonl_atomic(
                trial_dir / "access-audit.jsonl",
                [
                    {
                        "actor": "tested-agent",
                        "operation": "read",
                        "path": str(checkout / "task.json"),
                    },
                ],
            )
            self.trial.write_json_atomic(
                trial_dir / "outcome" / "result.json", {"passed": True}
            )
            completion = invoke(
                request_envelope(
                    "checkpoint",
                    {
                        "trial_path": trial_path,
                        "status": "completed",
                        "isolation_evidence": {
                            "fresh_session": True,
                            "forked_from_existing": False,
                            "auto_memory_enabled": False,
                            "vector_retrieval_enabled": False,
                            "session_recall_enabled": False,
                            "cross_session_cache_enabled": False,
                            "provider_persistence": "disabled",
                            "canary_leak_detected": False,
                        },
                        "read_allow_roots": [str(checkout)],
                        "write_allow_roots": [str(trial_dir / "outcome")],
                        "access_audit_complete": True,
                        "access_roots_enforced": True,
                    },
                    request_id="missing-registry-completion",
                    artifact_root=str(root),
                )
            )
            completion_response = parse(completion)
            self.assertResponseShape(completion, completion_response, "blocked", 3)
            self.assertEqual("evidence_invalid", completion_response["reason_code"])

    def test_checkpoint_reports_unknown_registry_schema_as_invalid_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "store"
            root.mkdir(mode=0o700)
            completed = invoke(
                request_envelope(
                    "prepare",
                    self.prepare_payload(
                        arm_id="S2",
                        registry_schema="skill-content",
                    ),
                    artifact_root=str(root),
                )
            )
            response = parse(completed)
            self.assertResponseShape(completed, response, "ok", 0)
            trial_path = response["result"]["trial_path"]
            trial_file = root / "trials" / trial_path / "trial.json"
            artifact = self.trial.load_private_json(trial_file)
            artifact["registry_schema"] = "unknown-registry"
            self.trial.write_json_atomic(trial_file, artifact)

            checkpoint = invoke(
                request_envelope(
                    "checkpoint",
                    {
                        "trial_path": trial_path,
                        "status": "running",
                        "resume_cursor": {
                            "next_run_order": 1,
                            "consumed_budget": {
                                "tokens": 0,
                                "wall_time_seconds": 0,
                                "tool_calls": 0,
                                "cost_units": 0,
                            },
                        },
                    },
                    request_id="unknown-registry-checkpoint",
                    artifact_root=str(root),
                )
            )
            checkpoint_response = parse(checkpoint)
            self.assertResponseShape(checkpoint, checkpoint_response, "blocked", 3)
            self.assertEqual("evidence_invalid", checkpoint_response["reason_code"])

    def test_checkpoint_reports_missing_trial_artifact_as_invalid_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "store"
            root.mkdir(mode=0o700)
            completed = invoke(
                request_envelope(
                    "prepare",
                    self.prepare_payload(
                        arm_id="S2",
                        registry_schema="skill-content",
                    ),
                    artifact_root=str(root),
                )
            )
            response = parse(completed)
            self.assertResponseShape(completed, response, "ok", 0)
            trial_path = response["result"]["trial_path"]
            (root / "trials" / trial_path / "trial.json").unlink()

            checkpoint = invoke(
                request_envelope(
                    "checkpoint",
                    {
                        "trial_path": trial_path,
                        "status": "running",
                    },
                    request_id="missing-trial-checkpoint",
                    artifact_root=str(root),
                )
            )
            checkpoint_response = parse(checkpoint)
            self.assertResponseShape(checkpoint, checkpoint_response, "blocked", 3)
            self.assertEqual("evidence_invalid", checkpoint_response["reason_code"])

    def test_evaluate_rejects_unverified_reviewer_calibration_publishers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "store"
            root.mkdir(mode=0o700)
            prompt_call = invoke(
                request_envelope(
                    "evaluate",
                    {"evaluation_kind": "reviewer_calibration_prompt"},
                    request_id="calibration-prompt",
                    artifact_root=str(root),
                )
            )
            prompt_response = parse(prompt_call)
            self.assertResponseShape(prompt_call, prompt_response, "error", 2)
            self.assertEqual("protocol_mismatch", prompt_response["reason_code"])

            judgments = [
                {"case_id": "k1", "verdict": "A win"},
                {"case_id": "k2", "verdict": "B win"},
                {"case_id": "k3", "verdict": "tie"},
                {"case_id": "k4", "verdict": "A win"},
                {"case_id": "k5", "verdict": "B win"},
            ]
            config = json.loads(
                (TRIAL_DIR / "pilot-gates.json").read_text(encoding="utf-8")
            )
            finalize_payload = {
                "evaluation_kind": "reviewer_calibration_finalize",
                "evidence_path": "calibration/trial-candidate",
                "config": config,
                "reviewer_family": "codex",
                "runs": [judgments, judgments],
                "runtime": {
                    "provider": "codex",
                    "model": "fixture-model",
                    "version": "fixture-version",
                    "runtime_binding": "sha256:" + "a" * 64,
                },
            }
            requests = [
                request_envelope(
                    "evaluate",
                    finalize_payload,
                    request_id=f"calibration-finalize-{index}",
                    artifact_root=str(root),
                )
                for index in range(2)
            ]
            with ThreadPoolExecutor(max_workers=2) as pool:
                finalized_calls = list(pool.map(invoke, requests))
            for finalized in finalized_calls:
                finalized_response = parse(finalized)
                self.assertResponseShape(finalized, finalized_response, "error", 2)
                self.assertEqual(
                    "protocol_mismatch", finalized_response["reason_code"]
                )
            calibration_root = root / "calibration" / "trial-candidate"
            self.assertFalse(calibration_root.exists())

            request_schema = json.loads(
                REQUEST_SCHEMA_PATH.read_text(encoding="utf-8")
            )
            evaluate_schema = request_schema["$defs"]["evaluate_payload"]
            self.assertNotEqual(
                [],
                schema_conformance_errors(
                    {"evaluation_kind": "reviewer_calibration_prompt"},
                    evaluate_schema,
                ),
            )
            self.assertNotEqual(
                [],
                schema_conformance_errors(finalize_payload, evaluate_schema),
            )

    def test_repeated_request_id_replays_the_receipt_and_rejects_divergence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "store"
            root.mkdir(mode=0o700)
            payload = self.prepare_payload()
            request = request_envelope("prepare", payload, artifact_root=str(root))
            first = invoke(request)
            replay = invoke(request)
            self.assertEqual(0, first.returncode)
            self.assertEqual(0, replay.returncode)
            first_response = parse(first)
            replay_response = parse(replay)
            self.assertFalse(first_response["result"].pop("replayed_receipt"))
            self.assertTrue(replay_response["result"].pop("replayed_receipt"))
            self.assertEqual(first_response, replay_response)
            diverged = request_envelope(
                "prepare",
                self.prepare_payload(arm_id="profile-off"),
                artifact_root=str(root),
            )
            conflict = invoke(diverged)
            conflict_response = parse(conflict)
            self.assertResponseShape(conflict, conflict_response, "blocked", 3)
            self.assertEqual("stale_state", conflict_response["reason_code"])

    def test_permanent_completion_contract_errors_are_not_stale_state(self):
        for label, declarations in (
            ("non-boolean-audit-declaration", {"access_audit_complete": "yes"}),
            ("non-boolean-roots-declaration", {"access_roots_enforced": 1}),
        ):
            with self.subTest(label), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / "store"
                root.mkdir(mode=0o700)
                prepared = invoke(
                    request_envelope(
                        "prepare",
                        self.prepare_payload(),
                        artifact_root=str(root),
                    )
                )
                prepared_response = parse(prepared)
                self.assertResponseShape(prepared, prepared_response, "ok", 0)
                trial_path = prepared_response["result"]["trial_path"]
                trial_dir = root / "trials" / trial_path
                checkout = root / "agent-checkout"
                checkout.mkdir(mode=0o700)
                self.trial.write_jsonl_atomic(
                    trial_dir / "events.jsonl",
                    [
                        {
                            "event_contract": "trial-lifecycle-v1",
                            "type": "runner-complete",
                            "skills_invoked": [],
                        }
                    ],
                )
                self.trial.write_jsonl_atomic(
                    trial_dir / "access-audit.jsonl",
                    [
                        {
                            "actor": "tested-agent",
                            "operation": "read",
                            "path": str(checkout / "task.json"),
                        },
                        {
                            "actor": "tested-agent",
                            "operation": "write",
                            "path": str(trial_dir / "outcome" / "result.json"),
                        },
                    ],
                )
                self.trial.write_json_atomic(
                    trial_dir / "outcome" / "result.json", {"passed": True}
                )
                checkpoint_payload = {
                    "trial_path": trial_path,
                    "status": "completed",
                    "isolation_evidence": {
                        "fresh_session": True,
                        "forked_from_existing": False,
                        "auto_memory_enabled": False,
                        "vector_retrieval_enabled": False,
                        "session_recall_enabled": False,
                        "cross_session_cache_enabled": False,
                        "provider_persistence": "disabled",
                        "canary_leak_detected": False,
                    },
                    "read_allow_roots": [str(checkout)],
                    "write_allow_roots": [str(trial_dir / "outcome")],
                    "access_audit_complete": True,
                    "access_roots_enforced": True,
                    "expected_state_version": 0,
                }
                checkpoint_payload.update(declarations)
                completed = invoke(
                    request_envelope(
                        "checkpoint",
                        checkpoint_payload,
                        request_id=f"contract-{label}",
                        artifact_root=str(root),
                    )
                )
                response = parse(completed)
                self.assertResponseShape(completed, response, "blocked", 3)
                self.assertEqual("evidence_invalid", response["reason_code"])

    def test_waived_memory_coverage_is_encoded_as_unverified(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "store"
            root.mkdir(mode=0o700)
            prepared = invoke(
                request_envelope(
                    "prepare",
                    self.prepare_payload(),
                    artifact_root=str(root),
                )
            )
            prepared_response = parse(prepared)
            self.assertResponseShape(prepared, prepared_response, "ok", 0)
            trial_path = prepared_response["result"]["trial_path"]
            trial_dir = root / "trials" / trial_path
            checkout = root / "agent-checkout"
            checkout.mkdir(mode=0o700)
            self.trial.write_jsonl_atomic(
                trial_dir / "events.jsonl",
                [
                    {
                        "event_contract": "trial-lifecycle-v1",
                        "type": "runner-complete",
                        "skills_invoked": [],
                    }
                ],
            )
            self.trial.write_jsonl_atomic(
                trial_dir / "access-audit.jsonl",
                [
                    {
                        "actor": "tested-agent",
                        "operation": "read",
                        "path": str(checkout / "task.json"),
                    },
                    {
                        "actor": "tested-agent",
                        "operation": "write",
                        "path": str(trial_dir / "outcome" / "result.json"),
                    },
                ],
            )
            self.trial.write_json_atomic(
                trial_dir / "outcome" / "result.json", {"passed": True}
            )
            completion = invoke(
                request_envelope(
                    "checkpoint",
                    {
                        "trial_path": trial_path,
                        "status": "completed",
                        # provider persistence is proven disabled, so only the
                        # memory_isolation_proof item is waived.
                        "isolation_evidence": {
                            "fresh_session": None,
                            "forked_from_existing": False,
                            "auto_memory_enabled": False,
                            "vector_retrieval_enabled": False,
                            "session_recall_enabled": False,
                            "cross_session_cache_enabled": False,
                            "provider_persistence": "disabled",
                            "canary_leak_detected": False,
                        },
                        "read_allow_roots": [str(checkout)],
                        "write_allow_roots": [str(trial_dir / "outcome")],
                        "access_audit_complete": True,
                        "access_roots_enforced": True,
                    },
                    request_id="waived-memory-only",
                    artifact_root=str(root),
                )
            )
            completion_response = parse(completion)
            self.assertResponseShape(completion, completion_response, "ok", 0)
            self.assertEqual(
                ["memory_isolation_proof"],
                completion_response["result"]["coverage_limitations"],
            )
            isolation = self.trial.load_private_json(trial_dir / "trial.json")[
                "completion_isolation"
            ]
            self.assertEqual("unverified", isolation["memory_isolation_status"])

    def test_waived_access_root_coverage_is_encoded_as_unverified(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "store"
            root.mkdir(mode=0o700)
            prepared = invoke(
                request_envelope(
                    "prepare",
                    self.prepare_payload(),
                    artifact_root=str(root),
                )
            )
            prepared_response = parse(prepared)
            self.assertResponseShape(prepared, prepared_response, "ok", 0)
            trial_path = prepared_response["result"]["trial_path"]
            trial_dir = root / "trials" / trial_path
            checkout = root / "agent-checkout"
            checkout.mkdir(mode=0o700)
            self.trial.write_jsonl_atomic(
                trial_dir / "events.jsonl",
                [
                    {
                        "event_contract": "trial-lifecycle-v1",
                        "type": "runner-complete",
                        "skills_invoked": [],
                    }
                ],
            )
            self.trial.write_jsonl_atomic(
                trial_dir / "access-audit.jsonl",
                [
                    {
                        "actor": "tested-agent",
                        "operation": "read",
                        "path": str(checkout / "task.json"),
                    },
                    {
                        "actor": "tested-agent",
                        "operation": "write",
                        "path": str(trial_dir / "outcome" / "result.json"),
                    },
                ],
            )
            self.trial.write_json_atomic(
                trial_dir / "outcome" / "result.json", {"passed": True}
            )
            completion = invoke(
                request_envelope(
                    "checkpoint",
                    {
                        "trial_path": trial_path,
                        "status": "completed",
                        # Isolation evidence is complete; only the runtime
                        # enforcement of the allow-roots is unproven.
                        "isolation_evidence": {
                            "fresh_session": True,
                            "forked_from_existing": False,
                            "auto_memory_enabled": False,
                            "vector_retrieval_enabled": False,
                            "session_recall_enabled": False,
                            "cross_session_cache_enabled": False,
                            "provider_persistence": "disabled",
                            "canary_leak_detected": False,
                        },
                        "read_allow_roots": [str(checkout)],
                        "write_allow_roots": [str(trial_dir / "outcome")],
                        "access_audit_complete": True,
                        "access_roots_enforced": False,
                    },
                    request_id="waived-access-roots-only",
                    artifact_root=str(root),
                )
            )
            completion_response = parse(completion)
            self.assertResponseShape(completion, completion_response, "ok", 0)
            self.assertEqual(
                ["access_root_enforcement"],
                completion_response["result"]["coverage_limitations"],
            )
            isolation = self.trial.load_private_json(trial_dir / "trial.json")[
                "completion_isolation"
            ]
            self.assertEqual("unverified", isolation["file_access_status"])

    def test_bridge_rejects_a_plan_that_mixes_registry_contracts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "store"
            root.mkdir(mode=0o700)
            payload = self.prepare_payload(registry_schema="paired-profile")
            payload["manifest"] = self.prepare_payload(
                arm_id="S2", registry_schema="skill-content"
            )["manifest"]
            completed = invoke(
                request_envelope("prepare", payload, artifact_root=str(root))
            )
            response = parse(completed)
            self.assertResponseShape(completed, response, "blocked", 3)
            self.assertEqual("evidence_invalid", response["reason_code"])

    def test_bridge_never_spawns_a_process_or_opens_a_socket(self):
        source = BRIDGE_PATH.read_text(encoding="utf-8")
        for forbidden in (
            "import subprocess",
            "import socket",
            "os.system",
            "os.popen",
            "os.exec",
            "eval(",
            "exec(",
            "urllib",
            "http.client",
        ):
            self.assertNotIn(forbidden, source)
        self.assertEqual(0o644, BRIDGE_PATH.stat().st_mode & 0o777)
        self.assertFalse(bool(BRIDGE_PATH.stat().st_mode & stat.S_IWGRP))
        self.assertFalse(bool(BRIDGE_PATH.stat().st_mode & stat.S_IWOTH))

    def test_bridge_does_not_import_unpinned_checkout_modules(self):
        completed = invoke(
            request_envelope(
                "probe", {"phase": "full", "pinned_manifest": self.manifest}
            )
        )
        loaded = parse(completed)["result"]["loaded_checkout_modules"]
        pinned = {
            entry["path"]
            for entry in self.manifest["entries"]
            if entry["path"].endswith(".py")
        }
        self.assertTrue(set(loaded).issubset(pinned), loaded)

    def test_environment_cannot_replace_the_pinned_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            shadow = Path(directory) / "shadow"
            shadow.mkdir(mode=0o700)
            (shadow / "trial.py").write_text(
                "raise SystemExit('shadow module executed')\n", encoding="utf-8"
            )
            environment = dict(os.environ)
            environment["PYTHONPATH"] = str(shadow)
            completed = invoke(
                request_envelope(
                    "probe", {"phase": "full", "pinned_manifest": self.manifest}
                ),
                environment=environment,
            )
            response = parse(completed)
            self.assertResponseShape(completed, response, "ok", 0)
            self.assertEqual(
                self.manifest["manifest_hash"],
                response["runtime_binding"]["manifest_hash"],
            )


if __name__ == "__main__":
    unittest.main()
