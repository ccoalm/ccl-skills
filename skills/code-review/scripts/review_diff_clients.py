"""Reviewer clients for review_diff.py: one adapter per CLI.

Codex and Claude count as their own model family. OpenCode and Kimi can run
any model, so one read of the user's config decides their family and is the
config they launch with. Each run is one read-only review under a private home
built from an allowlisted part of the user's config and deleted afterwards.
An answer comes back only from a process that exited by itself; judging it is
the runner's job.
"""
# Loaded by path and never registered in sys.modules, so no string annotations
# (and no `from __future__ import annotations`) in dataclasses here.
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

CLIENT_ORDER = ("codex", "claude", "opencode", "kimi")
# Spellings of a model family used across this repository and its callers.
FAMILY_ALIASES = {"openai": "codex", "gpt": "codex", "chatgpt": "codex", "anthropic": "claude",
                  "moonshot": "kimi"}
# A word in a model id that names its family. OpenCode can run any provider, so
# its family comes from the model it is configured with; an id naming none of
# these is of unknown family and is not used as a reviewer.
MODEL_FAMILY_WORDS = (("claude", "claude"), ("anthropic", "claude"), ("gpt", "codex"),
                      ("openai", "codex"), ("codex", "codex"), ("kimi", "kimi"),
                      ("moonshot", "kimi"), ("deepseek", "deepseek"), ("gemini", "gemini"),
                      ("qwen", "qwen"), ("glm", "glm"))
# Families an implementer can be named as. A client name that can run any model
# (opencode) or "other" says nothing about independence, so it is refused.
KNOWN_FAMILIES = {family for _, family in MODEL_FAMILY_WORDS}
INTERRUPT_CODES = {130, 137, 143}
# Top-level config keys carried into a reviewer's private home, plus the tables
# that define the models they select. An allowlist on purpose: anything else
# (MCP servers, hooks, plugins, skills, tool settings) stays out.
CODEX_KEYS = ("model", "model_reasoning_effort", "model_provider", "model_verbosity")
KIMI_KEYS = ("default_model", "default_effort", "default_thinking", "model", "provider", "protocol",
             "base_url", "api_key", "max_context_size", "max_input_size", "max_output_size")
KIMI_TABLES = ("models", "providers", "thinking")
KIMI_LINKS = ("credentials", "oauth", "device_id", "region")  # links, so a token refresh persists
READ_TOOLS = ("Read", "Grep", "Glob")
# Moonshot's own API hosts. A `kimi`-type provider elsewhere is a gateway that
# can serve any model, so only these make an unnamed model id Kimi.
MOONSHOT_HOSTS = ("moonshot.cn", "moonshot.ai", "kimi.com")


class Interrupted(Exception):
    """The runner was told to stop; the reviewer in flight is killed."""


@dataclass
class Run:
    """One reviewer process. A timed-out or interrupted run carries no answer."""
    outcome: str  # ran, timeout, interrupted, or missing (it could not start)
    returncode: Optional[int] = None
    answer: str = ""
    stderr: str = ""


class Client:
    """One reviewer CLI.

    snapshot() returns (family, model, snapshot), family None when unknown.
    run() launches with that snapshot, records the model (and provider) in
    `meta` as soon as it knows them, and raises OSError or CalledProcessError
    when the private home cannot be built."""
    name = ""

    def snapshot(self):
        return self.name, None, None

    def run(self, snapshot, prompt: str, cwd: str, diff_dir: str, timeout: int, meta: dict) -> Run:
        raise NotImplementedError


@dataclass
class Reviewer:
    """An installed client of another family, with the config read that judged it."""
    client: Client
    family: str
    model: Optional[str]
    snapshot: object


def canonical_family(name: str) -> str:
    name = name.strip().lower()
    return FAMILY_ALIASES.get(name, name)


def model_family(model: Optional[str]) -> Optional[str]:
    """Family named by a model id. For `provider/model` only the model part
    counts: a provider name says nothing, since an OpenAI-compatible endpoint
    can serve any family."""
    part = (model or "").lower().rsplit("/", 1)[-1]
    hits = [(part.find(word), family) for word, family in MODEL_FAMILY_WORDS if word in part]
    return min(hits)[1] if hits else None


def select_reviewers(order: str, implementer: str):
    """Return (reviewers, skipped) for the clients named in `order`, in that order."""
    reviewers, skipped = [], []
    for name in (s.strip() for s in order.split(",")):
        client = CLIENTS.get(name)
        if client is None or implementer not in KNOWN_FAMILIES:
            continue
        if not shutil.which(name):
            skipped.append({"client": name, "reason": "not_installed"})
            continue
        try:
            family, model, snapshot = client.snapshot()
        except (OSError, ValueError):
            skipped.append({"client": name, "reason": "config_unreadable"})
            continue
        if family is None:
            skipped.append({"client": name, "reason": "reviewer_family_unknown", "model": model or ""})
        elif family == implementer:
            skipped.append({"client": name, "reason": "same_family", "model": model or ""})
        else:
            reviewers.append(Reviewer(client, family, model, snapshot))
    return reviewers, skipped


class Codex(Client):
    name = "codex"

    def run(self, snapshot, prompt, cwd, diff_dir, timeout, meta):
        source = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")
        home, model, provider = private_codex_home(source)
        meta.update(model=model or "", provider=provider or "openai")
        answer = os.path.join(home, "answer.txt")
        env = dict(os.environ, CODEX_HOME=home)
        cmd = ["codex", "exec", "-C", cwd, "-s", "read-only", "--ephemeral", "-o", answer, "-"]
        try:
            run = run_child(cmd, prompt, cwd, env, timeout)
            run.answer = ""  # the answer is the -o file, never stdout
            if run.outcome == "ran" and os.path.exists(answer):
                run.answer = Path(answer).read_text(encoding="utf-8", errors="replace")
        finally:
            shutil.rmtree(home, ignore_errors=True)
        return run


class Claude(Client):
    name = "claude"

    def run(self, snapshot, prompt, cwd, diff_dir, timeout, meta):
        # No shell at all: git itself can write files (`git diff --output=...`), so
        # Claude gets only read tools and reads the diff the runner saved for it.
        cmd = ["claude", "-p", "--tools", *READ_TOOLS, "--add-dir", diff_dir,
               "--permission-mode", "dontAsk", "--setting-sources", "", "--strict-mcp-config",
               "--no-session-persistence", "--output-format", "text"]
        return run_child(cmd, prompt, cwd, dict(os.environ), timeout)


class OpenCode(Client):
    name = "opencode"

    def snapshot(self):
        model, providers = opencode_config()
        return model_family(model), model, (model, providers)

    def run(self, snapshot, prompt, cwd, diff_dir, timeout, meta):
        model, providers = snapshot
        meta.update(model=model or "")
        root = private_opencode_root(model, providers, [cwd, diff_dir])
        project = os.path.join(root, "project")
        env = dict(os.environ)
        for name in ("OPENCODE_CONFIG", "OPENCODE_CONFIG_DIR", "OPENCODE_CONFIG_CONTENT", "OPENCODE_PERMISSION"):
            env.pop(name, None)
        env.update(XDG_CONFIG_HOME=os.path.join(root, "config"), XDG_DATA_HOME=os.path.join(root, "data"),
                   XDG_STATE_HOME=os.path.join(root, "state"), OPENCODE_DISABLE_PROJECT_CONFIG="1",
                   OPENCODE_DISABLE_DEFAULT_PLUGINS="1", OPENCODE_DISABLE_CLAUDE_CODE="1",
                   OPENCODE_DISABLE_AUTOUPDATE="1", OPENCODE_DISABLE_SHARE="1", OPENCODE_PURE="1")
        cmd = ["opencode", "run", "--dir", project, "--agent", "ccl-review", "-m", model, "--", prompt]
        try:
            return run_child(cmd, "", project, env, timeout)
        finally:
            shutil.rmtree(root, ignore_errors=True)


class Kimi(Client):
    name = "kimi"

    def snapshot(self):
        family, alias, kept = kimi_snapshot(kimi_source())
        return family, alias, (alias, kept)

    def run(self, snapshot, prompt, cwd, diff_dir, timeout, meta):
        model, kept = snapshot
        home = private_kimi_home(kimi_source(), kept)
        meta.update(model=model or "")
        env = dict(os.environ)
        env.pop("KIMI_CODE_TRUST_WORKSPACE", None)  # an untrusted workspace loads no project MCP or config
        env.update(KIMI_CODE_HOME=home, KIMI_CODE_WATCH="0", KIMI_DISABLE_TELEMETRY="1",
                   KIMI_CODE_NO_AUTO_UPDATE="1", KIMI_CLI_NO_AUTO_UPDATE="1")
        cmd = ["kimi", "--skills-dir", os.path.join(home, "no-skills"), "--add-dir", diff_dir]
        cmd += ["-m", model] if model else []
        cmd += ["-p", prompt, "--output-format", "stream-json"]
        try:
            run = run_child(cmd, "", cwd, env, timeout)
        finally:
            shutil.rmtree(home, ignore_errors=True)
        run.answer = final_message(run.answer)
        return run


CLIENTS = {client.name: client for client in (Codex(), Claude(), OpenCode(), Kimi())}


# Process control.

def run_child(cmd: list, stdin: str, cwd: str, env: dict, timeout: int) -> Run:
    """Run one reviewer in its own process group and reap whatever it leaves."""
    try:
        proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, start_new_session=True)
    except OSError as exc:
        return Run("missing", stderr=str(exc))
    try:
        out, err = proc.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        if proc.poll() is None:
            _, err = reap(proc)
            return Run("timeout", stderr=err)  # a cut-off answer is never read
        # The reviewer exited but a descendant still holds its pipes.
        out, err = reap(proc)
    except Interrupted:
        reap(proc)
        raise
    else:
        reap(proc)  # descendants left in the reviewer's group
    if proc.returncode in INTERRUPT_CODES or proc.returncode < 0:
        return Run("interrupted", proc.returncode, stderr=err)
    return Run("ran", proc.returncode, out, err)


def reap(proc):
    """Kill the reviewer's process group and drain its pipes within a bound."""
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        out, err = proc.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        # A descendant in another session keeps the pipes open; stop reading.
        for pipe in (proc.stdin, proc.stdout, proc.stderr):
            if pipe:
                pipe.close()
        proc.wait()
        out, err = "", ""
    return out or "", err or ""


def final_message(stream: str) -> str:
    """The last assistant message of Kimi Code's stream-json output.

    Its text mode prints every assistant message, including the narration
    between tool calls, so only the last one is the answer. A line that is not
    JSON means the stream was cut, so there is no answer."""
    answer = ""
    for line in stream.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except ValueError:
            return ""
        if not isinstance(event, dict) or event.get("role") != "assistant":
            continue
        content = event.get("content")
        if isinstance(content, list):
            content = "".join(part.get("text", "") for part in content
                              if isinstance(part, dict) and part.get("type") == "text")
        answer = content if isinstance(content, str) else ""
    return answer


# Private homes and the config subsets carried into them.

def scratch_dir(prefix: str) -> str:
    # Not under the system temp dir: Codex refuses to create its sandbox helper
    # binaries there, and every shell command in the review then fails.
    parent = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "ccl-code-review"
    parent.mkdir(parents=True, exist_ok=True)
    path = tempfile.mkdtemp(prefix=prefix, dir=str(parent))
    os.chmod(path, 0o700)
    return path


def write_private(path: str, text: str) -> None:
    # Reviewer config can hold provider keys.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def link_if_present(source: Path, target: str) -> None:
    # A link, so a refreshed token lands in the user's own file.
    if source.exists():
        os.symlink(str(source), target)


def read_config(config: Path) -> str:
    return config.read_text(encoding="utf-8", errors="replace") if config.is_file() else ""


def filter_toml(text: str, keys, keep_table):
    """Keep top-level `keys` and the tables keep_table(name, top) accepts.

    Returns (kept lines, {key: value}) for the kept top-level keys."""
    kept, top, table, keep = [], {}, None, False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            header = stripped.split("#", 1)[0].strip()  # a header may carry a comment
            table = header.strip("[]").replace('"', "").replace("'", "").strip()
            keep = keep_table(table, top)
            if keep:
                kept += ["", line]
            continue
        if table is None:
            key = stripped.split("=", 1)[0].strip()
            root = key.split(".", 1)[0].strip("\"'")
            if "=" in stripped and key not in keys and keep_table(root, top):
                kept.append(line)  # a dotted assignment into a kept table, `models.x = {...}`
            elif key in keys and "=" in stripped:
                kept.append(line)
                value = stripped.split("=", 1)[1].strip()
                quoted = re.match(r"""^(["'])(.*?)\1""", value)
                top[key] = quoted.group(2) if quoted else value.split("#", 1)[0].strip()
        elif keep:
            kept.append(line)
    return kept, top


def private_codex_home(source: Path):
    """Return (home, model, provider) for a Codex run that loads nothing else."""
    home = scratch_dir("codex-home-")
    link_if_present(source / "auth.json", os.path.join(home, "auth.json"))

    def selected_provider(table, top):
        provider = top.get("model_provider")
        return bool(provider) and (table == f"model_providers.{provider}"
                                   or table.startswith(f"model_providers.{provider}."))

    kept, top = filter_toml(read_config(source / "config.toml"), CODEX_KEYS, selected_provider)
    Path(home, "config.toml").write_text("\n".join(kept) + "\n", encoding="utf-8")
    return home, top.get("model"), top.get("model_provider")


def kimi_source() -> Path:
    return Path(os.environ.get("KIMI_CODE_HOME") or Path.home() / ".kimi-code")


def kimi_snapshot(source: Path):
    """Return (family, alias, config lines) from one read of Kimi Code's config.

    The family comes from the model id the default alias selects; a provider of
    type `kimi` (Moonshot's own API) makes an otherwise unnamed id Kimi. Any other
    unknown model has no family. Raises ValueError when the config cannot be
    parsed or the carried subset would not define the same models."""
    try:
        import tomllib
    except ImportError:  # Python < 3.11
        raise ValueError("reading the Kimi Code config needs Python 3.11 or later")
    text = read_config(source / "config.toml")
    data = tomllib.loads(text)
    kept, _ = filter_toml(text, KIMI_KEYS, lambda table, top: table.split(".", 1)[0] in KIMI_TABLES)
    expected = {k: v for k, v in data.items() if k in KIMI_KEYS or k in KIMI_TABLES}
    if tomllib.loads("\n".join(kept)) != expected:
        raise ValueError("the Kimi Code config uses a form the carried subset cannot keep")
    alias = data.get("default_model")
    if alias is None:
        return "kimi", None, kept  # Kimi Code's own default model
    if not isinstance(alias, str):
        raise ValueError("default_model is not a string")
    models, providers = data.get("models"), data.get("providers")
    entry = models.get(alias) if isinstance(models, dict) else None
    entry = entry if isinstance(entry, dict) else {}
    model = entry.get("model")
    family = model_family(model if isinstance(model, str) else alias)
    provider = providers.get(entry.get("provider")) if isinstance(providers, dict) else None
    if family is None and isinstance(provider, dict) and provider.get("type") == "kimi":
        host = urllib.parse.urlparse(str(provider.get("base_url") or "https://api.moonshot.cn")).hostname or ""
        if any(host == h or host.endswith("." + h) for h in MOONSHOT_HOSTS):
            family = "kimi"
    return family, alias, kept


def private_kimi_home(source: Path, kept: list):
    """Return the home for a Kimi Code run with read tools only and no hooks, MCP or skills."""
    home = scratch_dir("kimi-home-")
    for name in KIMI_LINKS:
        link_if_present(source / name, os.path.join(home, name))
    kept = list(kept)
    # A non-empty enabled list is Kimi Code's global tool allowlist.
    kept += ["", "[tools]", "enabled = " + json.dumps(list(READ_TOOLS))]
    write_private(os.path.join(home, "config.toml"), "\n".join(kept) + "\n")
    os.mkdir(os.path.join(home, "no-skills"))
    return home


def _outside_strings(text: str, step):
    """Rebuild JSON text, letting step(text, i) skip characters outside strings.

    step returns how many characters to drop at i, or 0 to keep text[i]."""
    out, i, in_string = [], 0, False
    while i < len(text):
        ch = text[i]
        if in_string:
            out.append(text[i:i + 2] if ch == "\\" else ch)
            i += 2 if ch == "\\" else 1
            in_string = ch != '"'
            continue
        skip = step(text, i)
        if skip:
            i += skip
            continue
        in_string = ch == '"'
        out.append(ch)
        i += 1
    return "".join(out)


def _comment(text: str, i: int) -> int:
    if text.startswith("//", i):
        end = text.find("\n", i)
        return (len(text) if end < 0 else end) - i
    if text.startswith("/*", i):
        end = text.find("*/", i + 2)
        return (len(text) if end < 0 else end + 2) - i
    return 0


CLOSER = re.compile(r"\s*[}\]]")


def _trailing_comma(text: str, i: int) -> int:
    return 1 if text[i] == "," and CLOSER.match(text, i + 1) else 0


def load_jsonc(path: Path):
    """Parse JSON with comments and trailing commas, as OpenCode config allows."""
    text = path.read_text(encoding="utf-8", errors="replace")
    return json.loads(_outside_strings(_outside_strings(text, _comment), _trailing_comma))


def opencode_config():
    """Return (model, provider tables) from the user's global OpenCode config."""
    base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "opencode"
    paths = [base / name for name in ("config.json", "opencode.json", "opencode.jsonc")]
    if os.environ.get("OPENCODE_CONFIG"):
        paths.append(Path(os.environ["OPENCODE_CONFIG"]))
    model, providers = None, {}
    for path in paths:
        try:
            data = load_jsonc(path) if path.is_file() else None
        except (OSError, ValueError):
            data = None
        if not isinstance(data, dict):
            continue
        if isinstance(data.get("model"), str):
            model = data["model"]
        if isinstance(data.get("provider"), dict):
            providers.update(data["provider"])
    return model, providers


def private_opencode_root(model: str, providers: dict, read_dirs: list) -> str:
    """Return the root of a private XDG layout and project for an OpenCode run with read tools only.

    OpenCode imports `.opencode/plugin` code from its project directory and each
    parent up to the git root, whatever its config says, so its project is an
    empty git repository here and the reviewed repository is an outside
    directory it may only read."""
    root = scratch_dir("opencode-")
    provider = model.split("/", 1)[0]
    outside = {"*": "deny"}
    outside.update({d + "/*": "allow" for d in read_dirs})
    permission = {"*": "deny", "read": "allow", "grep": "allow", "glob": "allow", "list": "allow",
                  "external_directory": outside}
    config = {"model": model, "small_model": model, "share": "disabled", "autoupdate": False,
              "permission": permission,
              "agent": {"ccl-review": {"mode": "primary", "description": "Read-only code review",
                                       "permission": permission}}}
    if provider in providers:
        config["provider"] = {provider: providers[provider]}
    for sub in ("config/opencode", "data/opencode", "state", "project"):
        os.makedirs(os.path.join(root, sub))
    subprocess.run(["git", "init", "-q", os.path.join(root, "project")], check=True, capture_output=True)
    write_private(os.path.join(root, "config", "opencode", "opencode.json"), json.dumps(config))
    data_home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
    link_if_present(data_home / "opencode" / "auth.json", os.path.join(root, "data", "opencode", "auth.json"))
    return root
