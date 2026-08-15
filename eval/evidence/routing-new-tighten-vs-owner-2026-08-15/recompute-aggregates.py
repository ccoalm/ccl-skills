#!/usr/bin/env python3
"""Deterministic aggregate recomputation for the routing-new-tighten-vs-owner round.

Enumerates every raw round file in this directory's four measurement arms,
records per-file sha256 and per-round verdicts, and recomputes every aggregate
cited in MANIFEST.json and the plan-doc round record from those raw files.
Rerun and diff against the committed aggregates-recomputed.json to verify.
"""
import hashlib
import json
import os
import statistics
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# Expected-input pinning (chain r2 review P1): enumeration alone accepts a
# directory with removed rounds or a consistently-bound DIFFERENT bank/surface.
# Every constant below is declared up front; missing, extra, or substituted
# inputs fail the recomputation instead of shrinking it.
BASE_HEAD = "c0561c74e0f7249b8041f7c5800a8d6deadf496f"
FIX_HEAD = "411367a18a40c896e4afcfc3985aa288612cf645"
BANK_SINGLE_SHA = "0b63dd24591f950e4fa40faafdb8c4af9ac1e85573e0aa0a9d542f2d83d7c081"
BANK_NEIGHBORS_SHA = "800a67e57c2be6a70e8cdf7f8ca0e2a6ecfa3ff91d6912397cafbbb0d81e6160"
RUNNER_SHA = "510f5ab2f42e68fe1de8c97cad23892a6da5a8b40f6244853c79a2073970baa6"
TARGET_IDS = {"new-tighten-vs-owner"}
NEIGHBOR_IDS = {
    "ab-c2", "ab-c4", "ab-c6", "ab-n1", "ctrl-feature", "ctrl-tighten",
    "mem-llm-gateway-doc", "p3-spec-then-tc", "p3-transition-impl",
    "route-doc-polish-fixed-substance", "route-tech-plan-effort-doc",
}
# Per-skill raw description-line hashes (the runner's construction: the raw
# line bytes including the trailing newline), binding each arm's reports to
# the exact wording at that arm's HEAD.
DESC_LINE = {
    BASE_HEAD: {
        "product-rd-workflow": "39f2dc7a58f9353d8e78bce7957f7fcf9ec5b06637242f1ca715d33bb4de4ec7",
        "requirement-intent": "a8ea50f4756b74a90ef0ed2a8d9f0e199e4f77a1a08e039cbcb1065326b9da45",
    },
    FIX_HEAD: {
        "product-rd-workflow": "cfaafc2faa6e46b9cf92ce99b7821457b5b8e014c75daf1ed703f0a02b64dda7",
        "requirement-intent": "ae198d015f0b971b554c23288cbadfc397b230890ced517456ef17384e6606c4",
    },
}
ARMS = {
    "baseline-rounds": {
        "description": "pre-change surface (dev c0561c7), bank-single.jsonl, 10 rounds",
        "rounds": 10, "head": BASE_HEAD, "bank_sha": BANK_SINGLE_SHA, "case_ids": TARGET_IDS,
    },
    "target-after-rounds": {
        "description": "post-change surface (final candidate 411367a), bank-single.jsonl, 10 rounds",
        "rounds": 10, "head": FIX_HEAD, "bank_sha": BANK_SINGLE_SHA, "case_ids": TARGET_IDS,
    },
    "neighbors-before": {
        "description": "pre-change surface (dev c0561c7), bank-neighbors.jsonl, 3 rounds",
        "rounds": 3, "head": BASE_HEAD, "bank_sha": BANK_NEIGHBORS_SHA, "case_ids": NEIGHBOR_IDS,
    },
    "neighbors-after": {
        "description": "post-change surface (final candidate 411367a), bank-neighbors.jsonl, 3 rounds",
        "rounds": 3, "head": FIX_HEAD, "bank_sha": BANK_NEIGHBORS_SHA, "case_ids": NEIGHBOR_IDS,
    },
}
TARGET_ID = "new-tighten-vs-owner"
MUST_NOT = "tighten-doc"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    out = {"arms": {}, "target_case": {}, "neighbor_cases": {}, "must_not": {}}
    target_rows = {}
    neighbor_tallies = {}
    must_not_hits = 0
    must_not_rounds = 0

    # Pin the committed bank files and runner to the declared hashes before
    # touching any round (substituted-input guard).
    for bank_name, expected in (("bank-single.jsonl", BANK_SINGLE_SHA), ("bank-neighbors.jsonl", BANK_NEIGHBORS_SHA)):
        actual = sha256(os.path.join(HERE, bank_name))
        if actual != expected:
            raise SystemExit(f"{bank_name} sha256 {actual} != pinned {expected}")
    runner_path = os.path.normpath(os.path.join(HERE, "..", "..", "..", "skills", "skill-extraction-workflow", "scripts", "eval-routing-bank.rb"))
    if sha256(runner_path) != RUNNER_SHA:
        raise SystemExit("in-tree runner sha256 does not match pinned RUNNER_SHA")

    # Ground-truth surface/catalog reconstruction per pinned HEAD (chain r3,
    # both lanes): sidecar-vs-report agreement alone is forgeable by editing
    # both sides consistently. Rebuild the FULL description surface and graded
    # catalog from the git objects at each arm's pinned HEAD and require every
    # report and sidecar hash to equal the reconstruction — fabrication now
    # requires rewriting git history, not editing two JSON files.
    repo = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
    def git_bytes(*args):
        return subprocess.run(["git", "-C", repo, *args], capture_output=True, check=True).stdout
    expected = {}
    for head, bank_name in ((BASE_HEAD, None), (FIX_HEAD, None)):
        paths = [
            p2 for p2 in git_bytes("ls-tree", "--name-only", head, "skills/").decode().splitlines()
        ]
        surface = b""
        for skill_dir in sorted(paths):
            name = skill_dir.split("/")[-1]
            try:
                content = git_bytes("show", f"{head}:{skill_dir}/SKILL.md")
            except subprocess.CalledProcessError:
                continue
            for raw_line in content.split(b"\n"):
                if raw_line.startswith(b"description:"):
                    surface += name.encode() + b"\t" + raw_line + b"\n"
                    break
        ruby = (
            'require "yaml"; require "digest"; require "tmpdir"; '
            'root = ARGV[0]; '
            'catalog = Dir[File.join(root, "skills", "*", "SKILL.md")].sort.map { |path| '
            'name = File.basename(File.dirname(path)); '
            'm = File.read(path).match(/\A---\s*\n(.*?)\n---\s*\n/m); next unless m; '
            'desc = (YAML.safe_load(m[1]) rescue {})["description"].to_s.strip; next if desc.empty?; '
            '"### #{name}\n#{desc}" }.compact.join("\n\n"); '
            'puts Digest::SHA256.hexdigest(catalog)'
        )
        import tempfile
        with tempfile.TemporaryDirectory() as td:
            archive = subprocess.run(["git", "-C", repo, "archive", head, "skills"], capture_output=True, check=True).stdout
            subprocess.run(["tar", "-x", "-C", td], input=archive, check=True)
            catalog_sha = subprocess.run(["ruby", "-e", ruby, td], capture_output=True, check=True).stdout.decode().strip()
        expected[head] = {"surface_prefix": surface, "catalog_sha256": catalog_sha}

    for arm in sorted(ARMS):
        spec = ARMS[arm]
        arm_dir = os.path.join(HERE, arm)
        rounds = sorted(
            (f for f in os.listdir(arm_dir) if f.endswith(".json") and not f.endswith(".binding.json")),
            key=lambda f: int(f.split("-")[1].split(".")[0]),
        )
        if len(rounds) != spec["rounds"]:
            raise SystemExit(f"arm {arm}: expected exactly {spec['rounds']} rounds, found {len(rounds)}")
        if [f"round-{i}.json" for i in range(1, spec["rounds"] + 1)] != rounds:
            raise SystemExit(f"arm {arm}: round numbering must be exactly 1..{spec['rounds']} with no gaps")
        arm_out = {"description": spec["description"], "rounds": []}
        for fname in rounds:
            path = os.path.join(arm_dir, fname)
            report = json.load(open(path, encoding="utf-8"))
            sidecar_path = path + ".binding.json"
            sidecar = json.load(open(sidecar_path, encoding="utf-8"))
            # Assert every binding leg independently rather than trusting the
            # wrapper-derived binding_valid boolean (chain r1a, both lanes): a
            # hand-edited sidecar could set the boolean while a leg is false.
            legs = {
                "binding_valid": sidecar["binding_valid"] is True,
                "embedded_matches_surface": sidecar["embedded_matches_surface"] is True,
                "embedded_matches_catalog": sidecar["embedded_matches_catalog"] is True,
                "results_match_bank": sidecar["results_match_bank"] is True,
                "surface_before==after": sidecar["routing_surface_sha256_before"] == sidecar["routing_surface_sha256_after"],
                "catalog_before==after": sidecar["graded_catalog_sha256_before"] == sidecar["graded_catalog_sha256_after"],
                "skills_tree_clean": sidecar["skills_tree_dirty_entries"] == 0,
                "runner_rc==0": sidecar["runner_rc"] == 0,
            }
            bad = [name for name, ok in legs.items() if not ok]
            if bad:
                raise SystemExit(f"binding legs failed {bad}: {sidecar_path}")
            if sidecar["round_file_sha256"] != sha256(path):
                raise SystemExit(f"sidecar round_file_sha256 does not match raw round file: {path}")
            # Bind this round to the arm's declared HEAD, bank, and runner, and
            # cross-check the REPORT's own embedded surface identity against the
            # sidecar's independent recomputation (chain r2 review P1).
            if sidecar["repo_head"] != spec["head"]:
                raise SystemExit(f"arm {arm}: sidecar head {sidecar['repo_head']} != pinned {spec['head']}: {sidecar_path}")
            if sidecar["bank_sha256"] != spec["bank_sha"]:
                raise SystemExit(f"arm {arm}: sidecar bank sha != pinned bank sha: {sidecar_path}")
            if sidecar["runner_script_sha256"] != RUNNER_SHA:
                raise SystemExit(f"arm {arm}: sidecar runner sha != pinned runner sha: {sidecar_path}")
            surface = report.get("routing_surface") or {}
            if surface.get("descriptions_sha256") != sidecar["routing_surface_sha256_before"]:
                raise SystemExit(f"report embedded surface != sidecar recomputation: {path}")
            # Ground-truth legs (chain r3): reconstruct from the pinned HEAD's
            # git objects + the pinned bank bytes; report AND sidecar must match.
            bank_file = "bank-single.jsonl" if spec["case_ids"] == TARGET_IDS else "bank-neighbors.jsonl"
            with open(os.path.join(HERE, bank_file), "rb") as bf:
                bank_bytes = bf.read()
            truth_surface = hashlib.sha256(expected[spec["head"]]["surface_prefix"] + bank_bytes).hexdigest()
            if surface.get("descriptions_sha256") != truth_surface:
                raise SystemExit(f"report surface hash != git-reconstructed ground truth for {spec['head'][:7]}: {path}")
            if sidecar["routing_surface_sha256_before"] != truth_surface:
                raise SystemExit(f"sidecar surface hash != git-reconstructed ground truth: {sidecar_path}")
            truth_catalog = expected[spec["head"]]["catalog_sha256"]
            if surface.get("catalog_sha256") != truth_catalog:
                raise SystemExit(f"report catalog hash != git-reconstructed ground truth: {path}")
            if sidecar["graded_catalog_sha256_before"] != truth_catalog or sidecar["embedded_catalog_sha256"] != truth_catalog:
                raise SystemExit(f"sidecar catalog hashes != git-reconstructed ground truth: {sidecar_path}")
            if surface.get("bank_sha256") != spec["bank_sha"]:
                raise SystemExit(f"report embedded bank sha != pinned bank sha: {path}")
            per_skill = surface.get("per_skill_description_line_sha256") or {}
            for skill_name, expected_line in DESC_LINE[spec["head"]].items():
                if per_skill.get(skill_name) != expected_line:
                    raise SystemExit(f"arm {arm}: {skill_name} description-line hash != pinned wording for {spec['head'][:7]}: {path}")
            if {r["id"] for r in report["results"]} != spec["case_ids"]:
                raise SystemExit(f"arm {arm}: result case ids != pinned case-id set: {path}")
            verdicts = []
            for r in report["results"]:
                verdicts.append({"id": r["id"], "status": r["status"], "selected": r["selected"], "confidence": r.get("confidence")})
                if r["id"] == TARGET_ID:
                    must_not_rounds += 1
                    if r["selected"] == MUST_NOT:
                        must_not_hits += 1
                    target_rows.setdefault(arm, []).append(r)
                if arm.startswith("neighbors"):
                    neighbor_tallies.setdefault(arm, {}).setdefault(r["id"], []).append(r["status"])
            arm_out["rounds"].append({
                "file": f"{arm}/{fname}",
                "sha256": sha256(path),
                "sidecar_sha256": sha256(sidecar_path),
                "repo_head": sidecar["repo_head"],
                "surface_sha256": sidecar["routing_surface_sha256_before"],
                "pass": report["pass"],
                "tasks": report["tasks"],
                "verdicts": verdicts,
            })
        heads = {r["repo_head"] for r in arm_out["rounds"]}
        surfaces = {r["surface_sha256"] for r in arm_out["rounds"]}
        arm_out["unique_heads"] = sorted(heads)
        arm_out["unique_surfaces"] = sorted(surfaces)
        if len(heads) != 1 or len(surfaces) != 1:
            raise SystemExit(f"arm {arm}: expected single HEAD and single surface, got {heads} / {surfaces}")
        out["arms"][arm] = arm_out

    for arm, rows in target_rows.items():
        passes = [r for r in rows if r["status"] == "PASS"]
        fails = [r for r in rows if r["status"] != "PASS"]
        out["target_case"][arm] = {
            "pass": f"{len(passes)}/{len(rows)}",
            "fail_selected": sorted({r["selected"] for r in fails}),
            "fail_confidences": sorted(r.get("confidence") for r in fails),
            "pass_confidences": sorted(r.get("confidence") for r in passes),
            "pass_confidence_median": statistics.median(r.get("confidence") for r in passes) if passes else None,
        }

    for arm, cases in neighbor_tallies.items():
        out["neighbor_cases"][arm] = {
            cid: f"{sum(1 for s in st if s == 'PASS')}/{len(st)}" for cid, st in sorted(cases.items())
        }

    out["must_not"] = {
        "constraint": f"{TARGET_ID} must never route to {MUST_NOT}",
        "target_rounds_enumerated": must_not_rounds,
        "hits": must_not_hits,
    }

    json.dump(out, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
