#!/usr/bin/env python3
"""Exercise actual source installer entrypoints with disposable host fixtures."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent


class SourceInstallStatusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ccl-install-status-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "source"
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        for folder in (self.repo / "scripts", self.home, self.bin):
            folder.mkdir(parents=True)
        for name in ("install.sh", "install-opencode.sh"):
            shutil.copyfile(SCRIPTS / name, self.repo / "scripts" / name)
        assets = {
            "skills/sample/SKILL.md": "---\nname: sample\n---\nnew skill\n",
            "packages/opencode-plugin/ccl-skills.ts": "export default {}\n",
            "packages/opencode-plugin/commands/ccl-sample.md": "sample command\n",
            "agent-context/session-start.md": "session context\n",
            "agent-context/subagent-start.md": "subagent context\n",
            "hooks/hooks.json": "{}\n",
            "hooks/sample.sh": "exit 0\n",
            "scripts/owner-dispatch/owner-dispatch.sh": "exit 0\n",
        }
        for name, content in assets.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        for command in ("bash", "dirname", "basename", "date", "mkdir", "mv", "cp", "cat",
                        "find", "rm", "grep", "mktemp", "git", "tail", "readlink"):
            executable = shutil.which(command)
            self.assertIsNotNone(executable, command)
            (self.bin / command).symlink_to(executable)
        self.env = {"HOME": str(self.home), "PATH": str(self.bin), "TMPDIR": str(self.root),
                    "LANG": "C", "HOST_CALLS": str(self.root / "host-calls")}

    def fake_host(self, host, failing_operation=""):
        path = self.bin / host
        path.write_text("#!/bin/bash\n"
                        "printf '%s\\n' \"$*\" >> \"$HOST_CALLS\"\n"
                        "printf '%s\\n' 'host output first line' 'host output last line'\n"
                        f"case \"$*\" in {json.dumps(failing_operation)}*) echo 'synthetic host failure' >&2; exit 42;; esac\n"
                        "exit 0\n" if failing_operation else "#!/bin/bash\nexit 0\n")
        path.chmod(0o700)

    def fault_command(self, command, fragment=""):
        real = shutil.which(command)
        (self.bin / command).unlink()
        (self.bin / command).write_text(
            "#!/bin/bash\n"
            f"if [[ \"$*\" == *{json.dumps(fragment)}* ]]; then echo 'synthetic operation failure' >&2; exit 42; fi\n"
            f"exec {json.dumps(str(real))} \"$@\"\n")
        (self.bin / command).chmod(0o700)

    def run_install(self, name="install-opencode.sh", *args):
        return subprocess.run([str(self.bin / "bash"), str(self.repo / "scripts" / name), *args],
                              env=self.env, capture_output=True, text=True, timeout=20)

    def partial_copy_failure(self, fragment):
        real = shutil.which("cp")
        (self.bin / "cp").unlink()
        (self.bin / "cp").write_text(
            "#!/bin/bash\n"
            f"if [ \"$1\" = -R ] && [[ \"$2\" == *{json.dumps(fragment)}* ]]; then "
            "mkdir -p \"$3\"; printf partial > \"$3/PARTIAL\"; exit 42; fi\n"
            f"exec {json.dumps(str(real))} \"$@\"\n")
        (self.bin / "cp").chmod(0o700)

    def restore_command(self, command):
        (self.bin / command).unlink()
        (self.bin / command).symlink_to(shutil.which(command))

    def control_backup_clock(self):
        real = shutil.which("date")
        (self.bin / "date").unlink()
        (self.bin / "date").write_text(
            "#!/bin/bash\n"
            "if [ \"$*\" = '-u +%Y%m%dT%H%M%SZ' ]; then printf '%s\\n' \"$TEST_BACKUP_STAMP\"; "
            f"else exec {json.dumps(str(real))} \"$@\"; fi\n")
        (self.bin / "date").chmod(0o700)

    def destination(self, project=False):
        return self.repo / ".opencode" if project else self.home / ".config/opencode"

    def test_unified_skips_absent_opencode_without_creating_config(self):
        result = self.run_install("install.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.destination().exists())
        self.assertFalse((self.home / ".agents").exists())
        self.assertIn("未检测到 opencode CLI", result.stdout)

    def test_explicit_agent_skills_without_opencode_syncs_only_compat_path(self):
        shutil.rmtree(self.repo / "packages")
        result = self.run_install("install.sh", "--with-agent-skills")
        self.assertEqual(result.returncode, 0, result.stderr)
        skill = self.home / ".agents/skills/sample/SKILL.md"
        self.assertTrue(skill.is_file(), result.stdout)
        self.assertEqual(skill.read_text(), (self.repo / "skills/sample/SKILL.md").read_text())
        self.assertFalse(self.destination().exists())
        self.assertFalse(self.destination(True).exists())

    def test_agent_skills_failure_propagates_without_opencode_writes(self):
        old = self.home / ".agents/skills/sample/SKILL.md"
        old.parent.mkdir(parents=True)
        old.write_text("old skill\n")
        self.fault_command("cp", "/source/skills/sample")
        result = self.run_install("install.sh", "--with-agent-skills")
        self.assertEqual(result.returncode, 42, result.stdout)
        self.assertIn("synthetic operation failure", result.stderr)
        self.assertNotIn("完成。重启", result.stdout)
        self.assertFalse(self.destination().exists())
        backups = list((self.home / ".agents/.ccl-skills-backup").rglob("SKILL.md"))
        self.assertEqual([path.read_text() for path in backups], ["old skill\n"])

    def test_detected_opencode_with_agent_skills_syncs_both_paths(self):
        self.fake_host("opencode")
        result = self.run_install("install.sh", "--with-agent-skills")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / ".agents/skills/sample/SKILL.md").is_file())
        self.assertTrue((self.destination() / "skills/sample/SKILL.md").is_file())
        self.assertTrue((self.destination() / "ccl-skills/install-manifest.json").is_file())

    def test_only_agent_rejects_conflicting_modes_before_writing(self):
        for conflicting in ("--no-agent", "--project"):
            for args in (("--only-agent", conflicting), (conflicting, "--only-agent")):
                with self.subTest(args=args):
                    result = self.run_install("install-opencode.sh", *args)
                    self.assertEqual(result.returncode, 2, result.stdout)
                    self.assertFalse((self.home / ".agents").exists())
                    self.assertFalse(self.destination().exists())
                    self.assertFalse(self.destination(True).exists())

    def test_detected_opencode_installs_successfully(self):
        self.fake_host("opencode")
        result = self.run_install("install.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = self.destination() / "ccl-skills/install-manifest.json"
        self.assertEqual(json.loads(manifest.read_text())["install_mode"], "global")
        self.assertTrue((self.destination() / "skills/sample/SKILL.md").exists())
        self.assertFalse((self.home / ".agents").exists())

    def test_unified_propagates_each_host_plugin_failure(self):
        for host, operation in (("claude", "plugin marketplace add"), ("claude", "plugin install"),
                                ("codex", "plugin marketplace add"), ("codex", "plugin add")):
            with self.subTest(host=host, operation=operation):
                self.fake_host(host, operation)
                result = self.run_install("install.sh")
                self.assertIn("synthetic host failure", result.stdout)
                self.assertIn(operation, (self.root / "host-calls").read_text())
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("完成。重启", result.stdout)
                self.assertIn("host output last line", result.stdout)
                (self.bin / host).unlink()

    def test_copy_failure_propagates_and_does_not_refresh_receipt(self):
        fragments = ("/source/skills/sample", "/commands/ccl-sample.md", "/ccl-skills.ts",
                     "/bootstrap.md", "/source/hooks/hooks.json")
        for project in (False, True):
            for fragment in fragments:
                with self.subTest(project=project, copy=fragment):
                    destination = self.destination(project)
                    receipt = destination / "ccl-skills/install-manifest.json"
                    receipt.parent.mkdir(parents=True, exist_ok=True)
                    receipt.write_text("old receipt\n")
                    self.fault_command("cp", fragment)
                    result = self.run_install("install-opencode.sh", *( ["--project"] if project else ["--no-agent"] ))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(receipt.read_text(), "old receipt\n")
                    self.assertNotIn("install manifest 已写入", result.stdout)
                    (self.bin / "cp").unlink()
                    (self.bin / "cp").symlink_to(shutil.which("cp"))

    def test_unified_propagates_opencode_failure(self):
        self.fake_host("opencode")
        self.fault_command("cp", "/source/skills/sample")
        result = self.run_install("install.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("完成。重启", result.stdout)

    def test_manifest_write_failure_preserves_prior_receipt(self):
        receipt = self.destination() / "ccl-skills/install-manifest.json"
        receipt.parent.mkdir(parents=True)
        receipt.write_text("old receipt\n")
        self.fault_command("cat")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(receipt.read_text(), "old receipt\n")

    def test_manifest_publish_failure_preserves_prior_receipt(self):
        receipt = self.destination() / "ccl-skills/install-manifest.json"
        receipt.parent.mkdir(parents=True)
        receipt.write_text("old receipt\n")
        self.fault_command("mv", "/install-manifest.json")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(receipt.read_text(), "old receipt\n")

    def test_partial_host_failure_still_installs_other_detected_host(self):
        self.fake_host("claude", "plugin install")
        self.fake_host("opencode")
        result = self.run_install("install.sh")
        self.assertEqual(result.returncode, 42)
        self.assertTrue((self.destination() / "ccl-skills/install-manifest.json").is_file())
        self.assertIn("未回滚", result.stderr)

    def test_explicit_cron_failure_is_not_success(self):
        self.fake_host("codex")
        cron = self.bin / "crontab"
        cron.write_text("#!/bin/bash\nif [ \"$1\" = '-l' ]; then exit 1; fi\necho 'synthetic cron failure' >&2\nexit 42\n")
        cron.chmod(0o700)
        result = self.run_install("install.sh", "--codex-cron")
        self.assertEqual(result.returncode, 42)
        self.assertIn("synthetic cron failure", result.stderr)

    def test_empty_crontab_initial_write_succeeds(self):
        self.fake_host("codex")
        capture = self.root / "written-crontab"
        self.env["CRON_CAPTURE"] = str(capture)
        cron = self.bin / "crontab"
        cron.write_text("#!/bin/bash\nif [ \"$1\" = '-l' ]; then exit 1; fi\ncat > \"$CRON_CAPTURE\"\n")
        cron.chmod(0o700)
        result = self.run_install("install.sh", "--codex-cron")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("已装每日 9:00 cron", result.stdout)
        self.assertEqual(capture.read_text(),
                         "0 9 * * * codex plugin marketplace upgrade >/dev/null 2>&1; codex plugin add ccl-skills@ccl-skills >/dev/null 2>&1\n")

    def test_backup_move_failure_does_not_overwrite_original(self):
        old = self.destination() / "skills/sample/SKILL.md"
        old.parent.mkdir(parents=True)
        old.write_text("old skill\n")
        self.fault_command("mv", "/skills/sample")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(old.read_text(), "old skill\n")

    def test_failed_replacement_keeps_old_skill_in_backup(self):
        old = self.destination() / "skills/sample/SKILL.md"
        old.parent.mkdir(parents=True)
        old.write_text("old skill\n")
        self.fault_command("cp", "/source/skills/sample")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertNotEqual(result.returncode, 0)
        backups = list((self.destination() / ".ccl-skills-backup").rglob("SKILL.md"))
        self.assertEqual([path.read_text() for path in backups], ["old skill\n"])

    def test_skill_directory_creation_failure_stops_install(self):
        self.fault_command("mkdir", "/opencode/skills")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.destination() / "ccl-skills/install-manifest.json").exists())

    def test_failed_retry_preserves_last_recoverable_skill(self):
        self.control_backup_clock()
        old = self.destination() / "skills/sample/SKILL.md"
        old.parent.mkdir(parents=True)
        old.write_text("only recoverable old skill\n")
        self.fault_command("cp", "/source/skills/sample")
        for stamp in ("20260101T000001Z", "20260101T000002Z"):
            self.env["TEST_BACKUP_STAMP"] = stamp
            result = self.run_install("install-opencode.sh", "--no-agent")
            self.assertEqual(result.returncode, 42, result.stdout)
            self.assertFalse(old.exists())
            backups = list((self.destination() / ".ccl-skills-backup").rglob("SKILL.md"))
            self.assertEqual([path.read_text() for path in backups], ["only recoverable old skill\n"])
            self.assertFalse((self.destination() / "ccl-skills/install-manifest.json").exists())
        (self.bin / "cp").unlink()
        (self.bin / "cp").symlink_to(shutil.which("cp"))
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(old.read_text(), (self.repo / "skills/sample/SKILL.md").read_text())
        backups = list((self.destination() / ".ccl-skills-backup").rglob("SKILL.md"))
        self.assertEqual([path.read_text() for path in backups], ["only recoverable old skill\n"])

    def test_same_second_updates_keep_only_the_last_completed_backup(self):
        self.control_backup_clock()
        self.env["TEST_BACKUP_STAMP"] = "20260101T000000Z"
        source = self.repo / "skills/sample/SKILL.md"
        for version in range(4):
            source.write_text(f"skill version {version}\n")
            result = self.run_install("install-opencode.sh", "--no-agent")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((self.destination() / "skills/sample/SKILL.md").read_text(), source.read_text())
        backups = list((self.destination() / ".ccl-skills-backup/skills").glob("*/sample/SKILL.md"))
        self.assertEqual([path.read_text() for path in backups], ["skill version 2\n"])
        runtime_backups = list((self.destination() / "ccl-skills/.runtime-backup").iterdir())
        self.assertEqual(len(runtime_backups), 1)

    def test_partial_copy_retries_preserve_first_complete_backup(self):
        old = self.destination() / "skills/sample"
        old.mkdir(parents=True)
        (old / "SKILL.md").write_text("original skill\n")
        (old / "reference.md").write_text("original reference\n")
        self.partial_copy_failure("/source/skills/sample")
        for attempt in range(2):
            result = self.run_install("install-opencode.sh", "--no-agent")
            self.assertEqual(result.returncode, 42, result.stderr)
            self.assertEqual((old / "PARTIAL").read_text(), "partial")
            backups = list((self.destination() / ".ccl-skills-backup").rglob("SKILL.md"))
            self.assertEqual([path.read_text() for path in backups], ["original skill\n"], "pending_original")
            if attempt == 0:
                (old / "after-failure-edit.md").write_text("user edit after failure\n")
            else:
                edits = list((self.destination() / ".ccl-skills-backup").rglob("after-failure-edit.md"))
                self.assertEqual([path.read_text() for path in edits], ["user edit after failure\n"])
        self.restore_command("cp")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((old / "PARTIAL").exists())
        backups = list((self.destination() / ".ccl-skills-backup").rglob("SKILL.md"))
        self.assertEqual([path.read_text() for path in backups], ["original skill\n"])
        self.assertEqual((backups[0].parent / "reference.md").read_text(), "original reference\n")
        edits = list((self.destination() / ".ccl-skills-backup").rglob("after-failure-edit.md"))
        self.assertEqual([path.read_text() for path in edits], ["user edit after failure\n"])

    def test_retry_with_missing_component_retains_every_original(self):
        for name in ("sample", "z-last"):
            old = self.destination() / "skills" / name
            old.mkdir(parents=True)
            (old / "SKILL.md").write_text(f"old {name}\n")
        source = self.repo / "skills/z-last"
        source.mkdir()
        (source / "SKILL.md").write_text("new z-last\n")
        self.fault_command("cp", "/source/skills/sample")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertFalse((self.destination() / "skills/sample").exists())
        self.restore_command("cp")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 0, result.stderr)
        roots = list((self.destination() / ".ccl-skills-backup/skills").iterdir())
        self.assertEqual(len(roots), 1)
        for name in ("sample", "z-last"):
            self.assertEqual((roots[0] / name / "SKILL.md").read_text(), f"old {name}\n")

    def test_failed_runtime_retries_preserve_all_original_components(self):
        first = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.partial_copy_failure("/.runtime-stage.")
        for _ in range(2):
            result = self.run_install("install-opencode.sh", "--no-agent")
            self.assertEqual(result.returncode, 1, result.stderr)
        self.restore_command("cp")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 0, result.stderr)
        roots = list((self.destination() / "ccl-skills/.runtime-backup").iterdir())
        self.assertEqual(len(roots), 1)
        for component, name, expected in (("hooks", "hooks.json", "{}\n"),
                                           ("owner-dispatch", "owner-dispatch.sh", "exit 0\n"),
                                           ("agent-context", "session-start.md", "session context\n")):
            self.assertEqual((roots[0] / component / name).read_text(), expected)

    def test_repeated_legacy_migration_preserves_first_copy_without_nesting(self):
        legacy = self.home / ".agents/skills/claude-code-review"
        def create_legacy(text):
            (legacy / "scripts").mkdir(parents=True)
            (legacy / "SKILL.md").write_text("---\nname: claude-code-review\n---\n" + text)
            (legacy / "scripts/claude_review.sh").write_text("exit 0\n")
        create_legacy("original\n")
        self.fault_command("cp", "/ccl-skills.ts")
        failed = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(failed.returncode, 42, failed.stderr)
        create_legacy("recreated after failure\n")
        self.restore_command("cp")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = list((self.home / ".agents/.ccl-skills-backup").rglob("SKILL.md"))
        self.assertCountEqual([path.read_text() for path in backups], [
            "---\nname: claude-code-review\n---\noriginal\n",
            "---\nname: claude-code-review\n---\nrecreated after failure\n",
        ])

    def test_backup_rotation_preserves_names_that_are_not_installer_stamps(self):
        first = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(first.returncode, 0, first.stderr)
        root = self.destination() / ".ccl-skills-backup/skills"
        for name in ("20250101T000000Z", "personalTsafetyZ", "20250101T000000Z-1-notes"):
            folder = root / name
            folder.mkdir(parents=True)
            (folder / "note").write_text(name)
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((root / "20250101T000000Z").exists())
        for name in ("personalTsafetyZ", "20250101T000000Z-1-notes"):
            self.assertTrue((root / name / "note").is_file(), "stamp_predicate")
            self.assertEqual((root / name / "note").read_text(), name)

    def test_backup_commit_failure_retains_pending_and_prior_completed_copy(self):
        first = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(first.returncode, 0, first.stderr)
        root = self.destination() / ".ccl-skills-backup/skills"
        older = root / "20250101T000000Z"
        older.mkdir(parents=True)
        (older / "note").write_text("prior backup\n")
        original = (self.destination() / "skills/sample/SKILL.md").read_text()
        self.fault_command("mv", "/.pending ")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("安装内容已更新，备份整理失败", result.stderr)
        self.assertEqual((root / ".pending/sample/SKILL.md").read_text(), original)
        self.assertEqual((older / "note").read_text(), "prior backup\n")

    def test_backup_prune_failure_retains_new_completed_copy(self):
        first = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(first.returncode, 0, first.stderr)
        root = self.destination() / ".ccl-skills-backup/skills"
        older = root / "20250101T000000Z"
        older.mkdir(parents=True)
        (older / "note").write_text("prior backup\n")
        original = (self.destination() / "skills/sample/SKILL.md").read_text()
        self.fault_command("rm", str(older))
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("安装内容已更新，备份整理失败", result.stderr)
        self.assertFalse((root / ".pending").exists())
        completed = [path for path in root.iterdir() if path != older]
        self.assertEqual(len(completed), 1)
        self.assertEqual((completed[0] / "sample/SKILL.md").read_text(), original)
        self.assertEqual((older / "note").read_text(), "prior backup\n")

    def test_retry_backup_failure_keeps_original_pending_copy(self):
        old = self.destination() / "skills/sample"
        old.mkdir(parents=True)
        (old / "SKILL.md").write_text("original skill\n")
        self.partial_copy_failure("/source/skills/sample")
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 42, result.stderr)
        self.restore_command("cp")
        self.fault_command("mv", str(old))
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual((old / "PARTIAL").read_text(), "partial")
        pending = self.destination() / ".ccl-skills-backup/skills/.pending/sample/SKILL.md"
        self.assertEqual(pending.read_text(), "original skill\n")
        self.assertFalse((self.destination() / "ccl-skills/install-manifest.json").exists())

    def test_destructive_predicates_have_mutation_sensitive_controls(self):
        class ProbeResult(unittest.TestResult):
            def __init__(self):
                super().__init__()
                self.assertion_failures = []

            def addFailure(self, test, error):
                self.assertion_failures.append((test._testMethodName, str(error[1])))
                super().addFailure(test, error)

        mutations = (
            ("stamp_predicate", "test_backup_rotation_preserves_names_that_are_not_installer_stamps",
             '      [[ "${previous##*/}" =~ ^[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$ ]] || continue\n', ''),
            ("pending_original", "test_partial_copy_retries_preserve_first_complete_backup",
             '    if [ -e "$saved" ] || [ -L "$saved" ]; then\n'
             '      retry="$saved.retry.$BACKUP_STAMP"\n'
             '      [ ! -e "$retry" ] && [ ! -L "$retry" ] || return 1\n'
             '      mv "$dst" "$retry" || return "$?"\n'
             '    else\n'
             '      mv "$dst" "$saved" || return "$?"\n'
             '    fi\n',
             '    rm -rf -- "$saved" || return "$?"\n'
             '    mv "$dst" "$saved" || return "$?"\n'),
        )
        for predicate, method, anchor, replacement in mutations:
            for mutate in (False, True):
                with self.subTest(predicate=predicate, mutate=mutate):
                    child = type(self)(method)
                    child.longMessage = False
                    setup = child.setUp

                    def prepare(child=child, setup=setup, mutate=mutate,
                                anchor=anchor, replacement=replacement):
                        setup()
                        child.assertFalse(child.root.resolve().is_relative_to(SCRIPTS.parent.resolve()),
                                          "mutation_isolation")
                        script = child.repo / "scripts/install-opencode.sh"
                        original = script.read_text()
                        child.assertEqual(original.count(anchor), 1, "mutation_anchor")
                        if mutate:
                            changed = original.replace(anchor, replacement, 1)
                            child.assertNotEqual(changed, original, "mutation_not_applied")
                            script.write_text(changed)
                        syntax = subprocess.run([str(child.bin / "bash"), "-n", str(script)],
                                                env=child.env, capture_output=True, text=True,
                                                timeout=5)
                        child.assertEqual(syntax.returncode, 0, "mutation_syntax")

                    child.setUp = prepare
                    result = ProbeResult()
                    child.run(result)
                    self.assertEqual(result.testsRun, 1)
                    self.assertEqual(result.errors, [])
                    self.assertEqual(result.skipped, [])
                    expected = [(method, predicate)] if mutate else []
                    self.assertEqual(result.assertion_failures, expected)

    def test_command_sync_preserves_unowned_commands_and_updates_package_command(self):
        for project in (False, True):
            with self.subTest(project=project):
                commands = self.destination(project) / "commands"
                commands.mkdir(parents=True)
                (commands / "ccl-personal.md").write_text("personal command\n")
                (commands / "personal.md").write_text("another command\n")
                (commands / "ccl-sample.md").write_text("old package command\n")
                args = ["--project"] if project else ["--no-agent"]
                result = self.run_install("install-opencode.sh", *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((commands / "ccl-personal.md").read_text(), "personal command\n")
                self.assertEqual((commands / "personal.md").read_text(), "another command\n")
                self.assertEqual((commands / "ccl-sample.md").read_text(), "sample command\n")

    def test_missing_plugin_is_a_failed_install(self):
        (self.repo / "packages/opencode-plugin/ccl-skills.ts").unlink()
        result = self.run_install("install-opencode.sh", "--no-agent")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.destination() / "ccl-skills/install-manifest.json").exists())

    def test_explicit_project_success(self):
        result = self.run_install("install-opencode.sh", "--project")
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = self.destination(True) / "ccl-skills/install-manifest.json"
        self.assertEqual(json.loads(manifest.read_text())["install_mode"], "project")
        self.assertFalse(self.destination().exists())


if __name__ == "__main__":
    unittest.main()
