# Python Package Registry Release

Use this when publishing Python wheel/sdist artifacts to a private PyPI-compatible registry, or when proving that a consumer can resolve the published package without local source mappings.

The Python stack skill owns package internals: version bump, `pyproject.toml`, lock/source mapping, package `__version__`, import behavior, and tests. This release skill owns the registry publication path and the consumer-view proof after the tag/build is ready.

## Required Release Path

1. Build from the committed release commit or tag.
   - Verify the tag points to the intended commit before building.
   - Build wheel and sdist using the repo's declared tool, for example `uv build`.
   - Before upload, record hashes for the exact artifact bytes produced by this build and keep the manifest with the release evidence. Tie the manifest to the release commit/tag build (commit it, capture it as a CI build artifact, or otherwise pin it to the release SHA) so verification cannot later be satisfied by a manifest regenerated from a different upload. Do not regenerate this manifest during verification from rebuilt artifacts; Python wheels/sdists are not guaranteed byte-reproducible unless the project has explicitly proven reproducible builds.
     ```bash
     python3 - <<'PY' > dist/SHA256SUMS
     import hashlib
     import pathlib

     for path in sorted(pathlib.Path("dist").glob("*")):
         if path.is_file():
             print(hashlib.sha256(path.read_bytes()).hexdigest(), path.name)
     PY
     ```
   - Inspect artifact metadata before upload:
     ```bash
     unzip -p dist/<distribution>-<version>-py3-none-any.whl '<distribution>-<version>.dist-info/METADATA' \
       | rg '^(Name|Version|Requires-Python|Requires-Dist):'
     ```

2. Publish with a Python package publisher, not a low-level package-file API.
   - Prefer `uv publish` or `twine upload` against the registry upload endpoint.
   - For GitLab-compatible registries, the upload endpoint shape is:
     ```text
     https://<gitlab-host>/api/v4/projects/<project-id>/packages/pypi
     ```
   - Use environment variables or keyring/netrc for credentials. For install/download verification, prefer keyring, netrc, or pip config so command logs do not contain token-bearing URLs. Do not echo tokens, commit index URLs containing tokens, or leave token-bearing commands in durable docs.
   - `uv publish` example:
     ```bash
     export UV_PUBLISH_USERNAME=<user>
     read -rs UV_PUBLISH_PASSWORD
     export UV_PUBLISH_PASSWORD
     uv publish \
       --publish-url "https://<gitlab-host>/api/v4/projects/<project-id>/packages/pypi" \
       dist/<distribution>-<version>-py3-none-any.whl \
       dist/<distribution>-<version>.tar.gz
     unset UV_PUBLISH_PASSWORD
     ```
   - If the installed `uv publish --help` does not list `--dry-run`, do not use `uv publish` as a no-write duplicate probe. Query the registry package listing or simple index manually; run `uv publish --check-url ...` only when you are ready for missing files to upload.
   - Do not use `--check-url` for metadata repair after a bad raw upload. `uv publish --check-url` skips an already-present *identical* file when the index exposes a supported hash (exact behavior varies by index); it does not overwrite or repair broken simple-index metadata for a file that already exists. Publish a new patch or post-release version; do not reuse the same version after any upload has reached a consumer-visible registry surface.

3. Use `--check-url` before republishing or after an interrupted publish.
   - Check URL shape:
     ```text
     https://<gitlab-host>/api/v4/projects/<project-id>/packages/pypi/simple/
     ```
   - Dry-run duplicate check, only when `uv publish --help` lists `--dry-run`:
     ```bash
     export UV_PUBLISH_USERNAME=<user>
     read -rs UV_PUBLISH_PASSWORD
     export UV_PUBLISH_PASSWORD
     uv publish --dry-run \
       --publish-url "https://<gitlab-host>/api/v4/projects/<project-id>/packages/pypi" \
       --check-url "https://<gitlab-host>/api/v4/projects/<project-id>/packages/pypi/simple/" \
       dist/<distribution>-<version>-py3-none-any.whl \
       dist/<distribution>-<version>.tar.gz
     unset UV_PUBLISH_PASSWORD
     ```

## Recovery Rules

- Do not use a raw / low-level package-file upload API as the normal publish path. Non-PyPI upload paths may bypass the registry's PyPI metadata generation and create files while omitting simple-index metadata such as `data-requires-python`, which later changes resolver behavior (observed risk — verify the simple-index metadata after any non-standard upload rather than assuming it is present). If this already happened, publish a new patch or post-release version through `uv publish` or `twine upload`; do not delete and republish different bytes under the same version after any consumer-visible upload.
- A duplicate-file response is not a successful metadata repair. If the bad package already exists, a publisher will normally skip or reject it rather than overwrite registry metadata.
- If `pip install` returns `401` while the platform CLI can query the registry, verify credential form before blaming the package:
  - the token belongs to the same registry host being installed from;
  - the Basic auth username matches the token type expected by that registry;
  - tokens embedded in an index URL are URL-encoded;
  - shell variables are assigned before the command that expands them, for example `TOKEN_ENC=$(...); pip install ... "${TOKEN_ENC}"`, not `TOKEN_ENC=$(...) pip install ... "${TOKEN_ENC}"`.

## Published-Package Verification

**Precondition — defeat registry forwarding.** A GitLab-compatible registry forwards a not-found request to public PyPI **by default, even when `--index-url` points at the private simple index** (GitLab: "package request forwarding"). So a bare `--index-url <private-simple>` resolve is NOT proof of private-registry origin: a package that never landed in the private registry but exists on public PyPI (same name+version) resolves anyway. The byte-hash check below still fails on *different* bytes, but identical forwarded bytes would pass. Before trusting the registry-only proof: turn off package forwarding for the target group/instance (the authoritative control), and additionally assert that every simple-index anchor and the downloaded artifact resolve to the private registry host, not `pypi.org` (the script below enforces the host assertion on the simple index).

Before closing the release, collect all four evidence rows:

1. Artifact metadata: wheel `METADATA` shows expected `Name`, `Version`, `Requires-Python`, and dependency requirements.
2. Registry listing: the registry API or UI shows the package name and version in the expected project/namespace.
3. Simple index: the simple-index page contains the wheel/sdist filenames for the exact distribution/version. When artifact metadata declares `Requires-Python`, a present `data-requires-python` anchor value must be parseable and semantically equivalent; missing `data-requires-python` on registry classes that do not reliably emit it is informational evidence, not a hard pass/fail signal.
4. Fresh install: a new environment proves the target artifact came from the intended private registry, then installs that downloaded artifact with the dependency indexes required by the package. Do not use an editable install, local path source, or workspace override. If the package exposes a module `__version__`, import that module and compare it to the distribution version; otherwise record an explicit no-module-version declaration.

A fresh install check should verify both artifact origin and runtime version when the package exposes a module version:

```bash
set -euo pipefail
DIST_NAME=<distribution>
MODULE_VERSION_MODULE=<module-with-__version__>
PACKAGE_HAS_NO_MODULE_VERSION=0  # set to 1 only when the package intentionally exposes no module __version__
NO_MODULE_VERSION_IMPORT_MODULE=<module-to-import-when-no-__version__>
PACKAGE_HAS_NO_REQUIRES_PYTHON=0  # set to 1 only when the release intentionally has no Requires-Python metadata
ALLOW_MISSING_DATA_REQUIRES_PYTHON=0  # set to 1 only with recorded registry-class override
ALLOW_DIVERGENT_DATA_REQUIRES_PYTHON=0  # set to 1 only with recorded registry-class override
EXPECTED_VERSION=<version>
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python)}"
UPLOADED_ARTIFACT=dist/<distribution>-<version>-py3-none-any.whl  # exact file uploaded in the publish step; do not replace with a rebuild
ARTIFACT_SHA256_MANIFEST=dist/SHA256SUMS  # generated immediately after the release commit/tag build, before upload
FILENAME_VERSION="${FILENAME_VERSION:-$(
  "${PYTHON_BIN}" - "${DIST_NAME}" "${UPLOADED_ARTIFACT}" <<'PY'
import pathlib
import re
import sys

dist = re.sub(r"[-_.]+", "-", sys.argv[1]).lower()
name = pathlib.Path(sys.argv[2]).name
lowered = name.lower().replace("_", "-")
if name.endswith(".whl"):
    parts = name[:-4].split("-")
    if len(parts) < 2:
        raise SystemExit(f"cannot parse wheel filename version: {name}")
    print(parts[1])
elif lowered.endswith(".tar.gz") or lowered.endswith(".zip"):
    stem = lowered.removesuffix(".tar.gz").removesuffix(".zip")
    prefix = dist + "-"
    if not stem.startswith(prefix):
        raise SystemExit(f"artifact filename does not start with expected distribution prefix {prefix!r}: {name}")
    print(stem[len(prefix):])
else:
    raise SystemExit(f"unsupported artifact filename for version parsing: {name}")
PY
)}"
EXPECTED_ARTIFACT_BASENAME=$(basename "${UPLOADED_ARTIFACT}")
PRIVATE_REGISTRY_HOST=<gitlab-host>
PRIVATE_SIMPLE_INDEX="https://${PRIVATE_REGISTRY_HOST}/api/v4/projects/<project-id>/packages/pypi/simple"
# INSTALL_INDEX_URL=https://<internal-index-or-proxy-serving-private-and-approved-public-deps>/simple
: "${INSTALL_INDEX_URL:?set INSTALL_INDEX_URL; PRIVATE_SIMPLE_INDEX is valid only when it also serves every dependency}"
# Fail closed on credentials embedded in an index URL: they leak into pip argv, shell history, and logs.
# GitLab documents inline-auth install URLs, but this proof forbids them — keep auth in netrc/keyring only.
for _url_var in PRIVATE_SIMPLE_INDEX INSTALL_INDEX_URL; do
  "${PYTHON_BIN}" -c 'import sys,urllib.parse as u; p=u.urlparse(sys.argv[1]); sys.exit(1 if (p.username or p.password) else 0)' "${!_url_var}" || {
    echo "${_url_var} must not embed credentials (user:token@host); use netrc/keyring instead" >&2; exit 1
  }
done
PIP_KEYRING_PROVIDER="${PIP_KEYRING_PROVIDER:-disabled}"  # set to import only when keyring auth is installed in the tooling venv
export PIP_NO_CACHE_DIR=1
VENV_DIR=$(mktemp -d)      # clean consumer venv: nothing installed except the released artifact + its declared deps
TOOL_VENV=$(mktemp -d)     # separate verifier-tooling venv (packaging) so it cannot mask a missing runtime dep of the release
ARTIFACT_DIR=$(mktemp -d)
SIMPLE_PAGE=$(mktemp)
# Downloaded private artifacts + simple-index HTML can contain private package names/versions/URLs; clean up on exit.
trap 'rm -rf "${VENV_DIR}" "${TOOL_VENV}" "${ARTIFACT_DIR}" "${SIMPLE_PAGE}"' EXIT
EXPECTED_ARTIFACT_SHA256=$(
  "${PYTHON_BIN}" -c 'import pathlib, sys; target=pathlib.Path(sys.argv[1]).name; manifest=pathlib.Path(sys.argv[2]); rows=[line.split() for line in manifest.read_text().splitlines() if line.split()]; matches=[row[0] for row in rows if len(row) >= 2 and row[1] == target]; assert len(matches) == 1, f"manifest must contain exactly one hash for {target}"; print(matches[0])' \
    "${UPLOADED_ARTIFACT}" "${ARTIFACT_SHA256_MANIFEST}"
)
ACTUAL_UPLOADED_ARTIFACT_SHA256=$("${PYTHON_BIN}" -c 'import hashlib, pathlib, sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' "${UPLOADED_ARTIFACT}")
test "${ACTUAL_UPLOADED_ARTIFACT_SHA256}" = "${EXPECTED_ARTIFACT_SHA256}"
export DIST_NAME MODULE_VERSION_MODULE PACKAGE_HAS_NO_MODULE_VERSION NO_MODULE_VERSION_IMPORT_MODULE PACKAGE_HAS_NO_REQUIRES_PYTHON ALLOW_MISSING_DATA_REQUIRES_PYTHON ALLOW_DIVERGENT_DATA_REQUIRES_PYTHON EXPECTED_VERSION EXPECTED_ARTIFACT_SHA256 UPLOADED_ARTIFACT EXPECTED_ARTIFACT_BASENAME FILENAME_VERSION PRIVATE_REGISTRY_HOST PRIVATE_SIMPLE_INDEX INSTALL_INDEX_URL SIMPLE_PAGE
python -m venv "${VENV_DIR}"
python -m venv "${TOOL_VENV}"
"${TOOL_VENV}/bin/python" -m pip install --index-url "${INSTALL_INDEX_URL}" packaging
# The isolated target-artifact download runs from TOOL_VENV, so keyring — when requested — is installed
# HERE, never in the pristine consumer venv (VENV_DIR), which must receive only the released artifact.
if [[ "${PIP_KEYRING_PROVIDER}" != "disabled" ]]; then
  "${TOOL_VENV}/bin/python" -m pip install --index-url "${INSTALL_INDEX_URL}" keyring
fi
EXPECT_REQUIRES_PYTHON_SPEC=$("${TOOL_VENV}/bin/python" - <<'PY'
import os
import pathlib
import re
import tarfile
import zipfile

dist = re.sub(r"[-_.]+", "-", os.environ["DIST_NAME"]).lower()
filename_version = os.environ["FILENAME_VERSION"].lower()

def matches_distribution_version(filename):
    filename = filename.lower().replace("_", "-")
    marker = f"-{filename_version}"
    idx = filename.find(marker)
    if idx < 0:
        return False
    name_part = filename[:idx]
    rest = filename[idx + len(marker):]
    normalized_name = re.sub(r"[-_.]+", "-", name_part).lower()
    return normalized_name == dist and (rest.startswith("-") or rest in (".tar.gz", ".zip"))

def metadata_from_artifact(path):
    artifact = str(path)
    if artifact.endswith(".whl") or artifact.endswith(".zip"):
        with zipfile.ZipFile(artifact) as zf:
            metadata_name = next(
                name for name in zf.namelist()
                if name.endswith(".dist-info/METADATA") or name.endswith("PKG-INFO")
            )
            return zf.read(metadata_name).decode()
    if artifact.endswith((".tar.gz", ".tgz")):
        with tarfile.open(artifact) as tf:
            metadata_member = next(
                member for member in tf.getmembers()
                if member.isfile() and member.name.endswith("PKG-INFO")
            )
            extracted = tf.extractfile(metadata_member)
            assert extracted is not None
            return extracted.read().decode()
    raise SystemExit(f"unsupported artifact type for metadata extraction: {artifact}")

dist_dir = pathlib.Path(os.environ["UPLOADED_ARTIFACT"]).parent
matching_artifacts = [
    path for path in sorted(dist_dir.iterdir())
    if path.is_file() and matches_distribution_version(path.name)
]
matching_wheels = [path for path in matching_artifacts if path.name.endswith(".whl")]
metadata_sources = matching_wheels or matching_artifacts
if not metadata_sources:
    raise SystemExit(f"no local built artifacts found for {dist} {filename_version}")
requires_python_specs = set()
for path in metadata_sources:
    metadata = metadata_from_artifact(path)
    for line in metadata.splitlines():
        if line.startswith("Requires-Python:"):
            requires_python_specs.add(line.split(":", 1)[1].strip())
if len(requires_python_specs) > 1:
    raise SystemExit(f"inconsistent Requires-Python metadata across artifacts: {sorted(requires_python_specs)}")
print(next(iter(requires_python_specs), ""))
PY
)
if [[ -z "${EXPECT_REQUIRES_PYTHON_SPEC}" && "${PACKAGE_HAS_NO_REQUIRES_PYTHON}" != "1" ]]; then
  echo "Requires-Python metadata is missing; set PACKAGE_HAS_NO_REQUIRES_PYTHON=1 only when this is intentional" >&2
  exit 1
fi
if [[ "${PACKAGE_HAS_NO_REQUIRES_PYTHON}" == "1" ]] && [[ -f pyproject.toml ]] && grep -Eq 'requires-python[[:space:]]*=' pyproject.toml; then
  echo "PACKAGE_HAS_NO_REQUIRES_PYTHON=1 contradicts pyproject.toml requires-python" >&2
  exit 1
fi
export EXPECT_REQUIRES_PYTHON_SPEC
if [[ -n "${SIMPLE_INDEX_FETCH_CMD:-}" ]]; then
  # SIMPLE_INDEX_FETCH_CMD must read credentials from netrc/keyring/env/fd — never embed a token in
  # the command string (e.g. `curl -H "PRIVATE-TOKEN: <tok>"` or `-u user:<tok>`): that leaks the
  # secret into process args, shell history, CI logs, and any durable copy of this evidence.
  "${SHELL:-/bin/sh}" -c "${SIMPLE_INDEX_FETCH_CMD}" > "${SIMPLE_PAGE}"
else
  "${TOOL_VENV}/bin/python" - <<'PY' > "${SIMPLE_PAGE}"
import base64
import netrc
import os
import re
import sys
import urllib.request

dist = re.sub(r"[-_.]+", "-", os.environ["DIST_NAME"]).lower()
url = os.environ["PRIVATE_SIMPLE_INDEX"].rstrip("/") + "/" + dist + "/"

def fetch_with_netrc():
    req = urllib.request.Request(url)
    try:
        auth = netrc.netrc().authenticators(os.environ["PRIVATE_REGISTRY_HOST"])
    except (FileNotFoundError, netrc.NetrcParseError):
        auth = None
    if not auth:
        return None
    login, _, password = auth
    token = base64.b64encode(f"{login}:{password}".encode()).decode()
    req.add_header("Authorization", f"Basic {token}")
    with urllib.request.urlopen(req) as resp:
        return resp.read()

content = fetch_with_netrc()
if content is None:
    raise SystemExit("netrc credentials required, or set SIMPLE_INDEX_FETCH_CMD to a supported authenticated fetch command")
sys.stdout.buffer.write(content)
PY
fi
test -s "${SIMPLE_PAGE}"
"${TOOL_VENV}/bin/python" - <<'PY'
from html.parser import HTMLParser
import os
import pathlib
import re
from urllib.parse import urljoin, urlparse

dist = re.sub(r"[-_.]+", "-", os.environ["DIST_NAME"]).lower()
expected = os.environ["EXPECTED_VERSION"]
expected_artifact_basename = os.environ["EXPECTED_ARTIFACT_BASENAME"]
filename_version = os.environ["FILENAME_VERSION"].lower()
expected_requires_python = os.environ["EXPECT_REQUIRES_PYTHON_SPEC"]
allow_missing_requires_python = os.environ["ALLOW_MISSING_DATA_REQUIRES_PYTHON"] == "1"
allow_divergent_requires_python = os.environ["ALLOW_DIVERGENT_DATA_REQUIRES_PYTHON"] == "1"
simple_base = os.environ["PRIVATE_SIMPLE_INDEX"].rstrip("/") + "/" + dist + "/"
page = pathlib.Path(os.environ["SIMPLE_PAGE"]).read_text()

def normalize_specifier(value):
    from packaging.specifiers import SpecifierSet

    return str(SpecifierSet(value))

class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self._attrs = None
        self._text = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self._attrs = dict(attrs)
            self._text = []

    def handle_data(self, data):
        if self._attrs is not None:
            self._text.append(data)

    def handle_endtag(self, tag):
        if tag == "a" and self._attrs is not None:
            self.links.append((self._attrs, "".join(self._text)))
            self._attrs = None

parser = LinkParser()
parser.feed(page)

def matches_distribution_version(filename):
    filename = filename.lower().replace("_", "-")
    marker = f"-{filename_version}"
    idx = filename.find(marker)
    if idx < 0:
        return False
    name_part = filename[:idx]
    rest = filename[idx + len(marker):]
    normalized_name = re.sub(r"[-_.]+", "-", name_part).lower()
    return normalized_name == dist and (rest.startswith("-") or rest in (".tar.gz", ".zip"))

anchors = [
    (attrs, text)
    for attrs, text in parser.links
    if matches_distribution_version(text)
]
assert anchors, f"no simple-index files found for exact version {expected}"
def normalize_filename(filename):
    return filename.lower().replace("_", "-")

expected_artifact_anchors = [
    (attrs, text) for attrs, text in anchors
    if normalize_filename(text) == normalize_filename(expected_artifact_basename)
]
assert expected_artifact_anchors, f"expected artifact {expected_artifact_basename} not present in private simple index"
# Defeat registry forwarding AND wrong-registry resolution: EVERY release-version file's download href
# (wheel and sdist, not just the one expected basename) must resolve to the configured private
# registry endpoint — same host+port, a GitLab package-registry file path, and (for a project index)
# the same project prefix. Relative hrefs resolve same-origin. A forwarded pypi.org origin, a
# different host/port, or a different project on the same host all fail here.
iu = urlparse(os.environ["PRIVATE_SIMPLE_INDEX"])
expected_hostport = (iu.hostname, iu.port)
pkg_marker = "/packages/pypi/"
index_path = (iu.path or "").rstrip("/")
# Project index -> pin the project prefix (kills wrong-project-same-host). Group index aggregates
# project-scoped file URLs, so only host+registry-marker is enforced there.
project_prefix = None
if "/projects/" in index_path and pkg_marker in index_path + "/":
    project_prefix = index_path[: index_path.index(pkg_marker) + len(pkg_marker)]
bad = []
for attrs, text in anchors:
    href = attrs.get("href", "")
    u = urlparse(urljoin(simple_base, href))
    path = u.path or ""
    if (u.hostname, u.port) != expected_hostport:
        bad.append((text, href, f"host/port {(u.hostname, u.port)} != {expected_hostport}"))
    elif pkg_marker not in path:
        bad.append((text, href, f"path {path!r} is not a package-registry file URL"))
    elif project_prefix is not None and not path.startswith(project_prefix):
        bad.append((text, href, f"path {path!r} outside configured project prefix {project_prefix!r}"))
assert not bad, (
    f"simple-index anchors do not all resolve to the configured private registry: {bad}. "
    "Disable package forwarding for the target group/instance and set PRIVATE_SIMPLE_INDEX to the exact "
    "intended project/group endpoint (a forwarded pypi.org origin, a different host/port, or a different "
    "project on the same host would trigger this), then re-run."
)
if expected_requires_python:
    expected_requires_python = normalize_specifier(expected_requires_python)
    missing = [
        text for attrs, text in anchors
        if text.endswith((".whl", ".tar.gz", ".zip")) and not attrs.get("data-requires-python")
    ]
    if missing and allow_missing_requires_python:
        print(f"simple_index_requires_python_missing_info: registry did not emit data-requires-python for {missing}")
    elif missing:
        raise AssertionError(f"missing data-requires-python for {missing}; set ALLOW_MISSING_DATA_REQUIRES_PYTHON=1 only with recorded registry-class override")
    wrong = [
        (text, attrs.get("data-requires-python"))
        for attrs, text in anchors
        if text.endswith((".whl", ".tar.gz", ".zip"))
        and attrs.get("data-requires-python")
        and normalize_specifier(attrs.get("data-requires-python", "")) != expected_requires_python
    ]
    if wrong and allow_divergent_requires_python:
        print(f"simple_index_requires_python_divergent_info: registry emitted divergent data-requires-python {wrong}; expected {expected_requires_python!r}")
    else:
        assert not wrong, f"wrong data-requires-python for {wrong}; expected {expected_requires_python!r}"
PY
# Clear every resolution-affecting pip/uv input so artifact AND dependency provenance come only from
# the URLs passed explicitly below; auth still flows through netrc/keyring, which these do not touch.
PIP_ISOLATION_ENV=(env
  -u PIP_INDEX_URL -u PIP_EXTRA_INDEX_URL -u PIP_NO_INDEX
  -u PIP_FIND_LINKS -u PIP_CONSTRAINT -u PIP_REQUIREMENT
  -u UV_INDEX_URL -u UV_EXTRA_INDEX_URL
  PIP_CONFIG_FILE=/dev/null)
# Detect --keyring-provider support; fail closed if the help command itself fails, rather than
# collapsing "pip help failed" and "flag absent" into the same empty-args branch.
# The download runs from TOOL_VENV (which holds keyring when requested) so the consumer venv stays pristine.
if ! DOWNLOAD_HELP=$("${PIP_ISOLATION_ENV[@]}" "${TOOL_VENV}/bin/pip" download --help); then
  echo "pip download --help failed in ${TOOL_VENV}; cannot verify keyring support" >&2
  exit 1
fi
if grep -q -- '--keyring-provider' <<<"${DOWNLOAD_HELP}"; then
  PIP_DOWNLOAD_KEYRING_ARGS=(--keyring-provider "${PIP_KEYRING_PROVIDER}")
else
  PIP_DOWNLOAD_KEYRING_ARGS=()
fi
if [[ "${PIP_KEYRING_PROVIDER}" != "disabled" && "${#PIP_DOWNLOAD_KEYRING_ARGS[@]}" -eq 0 ]]; then
  echo "pip in ${TOOL_VENV} does not support --keyring-provider; upgrade pip or use netrc for this isolated target-artifact download" >&2
  exit 1
fi
"${PIP_ISOLATION_ENV[@]}" \
  "${TOOL_VENV}/bin/pip" download "${PIP_DOWNLOAD_KEYRING_ARGS[@]}" --no-cache-dir --no-deps --dest "${ARTIFACT_DIR}" --index-url "${PRIVATE_SIMPLE_INDEX}" "${DIST_NAME}==${EXPECTED_VERSION}"
test "$(find "${ARTIFACT_DIR}" -maxdepth 1 -type f | wc -l)" -eq 1
TARGET_ARTIFACT=$(find "${ARTIFACT_DIR}" -maxdepth 1 -type f | sed -n '1p')
export TARGET_ARTIFACT
NORMALIZED_TARGET_BASENAME=$(basename "${TARGET_ARTIFACT}" | tr '[:upper:]_' '[:lower:]-')
NORMALIZED_EXPECTED_BASENAME=$(printf '%s' "${EXPECTED_ARTIFACT_BASENAME}" | tr '[:upper:]_' '[:lower:]-')
test "${NORMALIZED_TARGET_BASENAME}" = "${NORMALIZED_EXPECTED_BASENAME}" || {
  echo "downloaded $(basename "${TARGET_ARTIFACT}") but expected ${EXPECTED_ARTIFACT_BASENAME}; expected artifact is missing from the private registry" >&2
  exit 1
}
"${VENV_DIR}/bin/python" -I -c 'import hashlib, os, pathlib; actual=hashlib.sha256(pathlib.Path(os.environ["TARGET_ARTIFACT"]).read_bytes()).hexdigest(); assert actual == os.environ["EXPECTED_ARTIFACT_SHA256"]'
# Consumer install: dependency auth for INSTALL_INDEX_URL must come from netrc, NOT keyring — installing
# keyring into the consumer venv would defeat the pristine-venv guarantee and could mask an undeclared dep.
"${PIP_ISOLATION_ENV[@]}" \
  "${VENV_DIR}/bin/pip" install --no-cache-dir --index-url "${INSTALL_INDEX_URL}" "${TARGET_ARTIFACT}"
# -I (isolated): ignore PYTHONPATH/PYTHONHOME and user site so the import/version proof resolves ONLY from
# the installed downloaded artifact, never from a local checkout on PYTHONPATH (which would be a false green).
"${VENV_DIR}/bin/python" -I - <<'PY'
import os
from importlib import import_module
from importlib.metadata import version

dist = os.environ["DIST_NAME"]
expected = os.environ["EXPECTED_VERSION"]
module_name = os.environ.get("MODULE_VERSION_MODULE", "")
no_module_version_import = os.environ.get("NO_MODULE_VERSION_IMPORT_MODULE", "")
no_module_version = os.environ.get("PACKAGE_HAS_NO_MODULE_VERSION") == "1"

assert version(dist) == expected
if module_name:
    module = import_module(module_name)
    assert getattr(module, "__version__", None) == expected
elif no_module_version:
    if not no_module_version_import:
        raise SystemExit("NO_MODULE_VERSION_IMPORT_MODULE required when PACKAGE_HAS_NO_MODULE_VERSION=1")
    module = import_module(no_module_version_import)
    assert not hasattr(module, "__version__")
    print(f"module_version_check_skipped: {no_module_version_import} declares no module __version__")
else:
    raise SystemExit("MODULE_VERSION_MODULE required unless PACKAGE_HAS_NO_MODULE_VERSION=1")
PY
```

For dependency stacks that span multiple private registries or public PyPI, keep the target-artifact proof separate: the simple-index metadata check and isolated `pip download --no-cache-dir --no-deps --index-url "${PRIVATE_SIMPLE_INDEX}"` must use only the registry that should contain the released distribution. The target-artifact download deliberately clears pip index environment variables and sets `PIP_CONFIG_FILE=/dev/null`, so credentials for that one fetch must come from a non-index-confusing path: netrc by default, or keyring only when `PIP_KEYRING_PROVIDER=import` is set — in which case keyring is installed into the separate tooling venv, never the consumer venv, and the download itself runs from the tooling venv. The final consumer install authenticates to `INSTALL_INDEX_URL` via netrc only, so the consumer venv keeps only the released artifact plus its declared dependencies. Set `UPLOADED_ARTIFACT` to the exact file that was uploaded from the release commit/tag build, and read `EXPECTED_ARTIFACT_SHA256` only from the manifest generated before upload. This snippet proves one `UPLOADED_ARTIFACT`; when both wheel and sdist are release artifacts, repeat the target-artifact block for each artifact or use an equivalent per-artifact direct-download loop before closing the release. A rebuilt artifact is not a valid hash source unless the project has separately proven reproducible builds. Set `INSTALL_INDEX_URL` explicitly to the private index or, for packages with external dependencies, to an internal proxy/mirror that serves both private and approved public packages; the raw private simple index is valid only when it also serves every dependency needed by the fresh install. Do not rely on pip's implicit public index or copy in direct public `--extra-index-url` unless every private dependency in scope is also provenance-checked. Set `MODULE_VERSION_MODULE` when the imported module exposes `__version__`; when it is set, a missing or stale module `__version__` is a release failure. If the package intentionally has no module version, set `PACKAGE_HAS_NO_MODULE_VERSION=1` plus `NO_MODULE_VERSION_IMPORT_MODULE` and record that declaration with the evidence; if it intentionally has no Python-version bound, set `PACKAGE_HAS_NO_REQUIRES_PYTHON=1` and keep it consistent with `pyproject.toml`. Missing or divergent simple-index `data-requires-python` is a failure by default; set `ALLOW_MISSING_DATA_REQUIRES_PYTHON=1` or `ALLOW_DIVERGENT_DATA_REQUIRES_PYTHON=1` only with a recorded registry-class override. The concrete snippet installs `packaging` as verification tooling into a **separate** tooling venv (never the consumer venv, so a verifier dependency cannot mask a runtime dependency the released package failed to declare) from `INSTALL_INDEX_URL` before comparing specifiers, fetches the simple-index page with netrc by default, and supports keyring or platform-CLI auth through `SIMPLE_INDEX_FETCH_CMD` — which must read secrets from netrc/keyring/env/fd and never carry a token in its command string. Never repair a venv auth failure by embedding a token in `--index-url`; the script fails closed before any pip call if `PRIVATE_SIMPLE_INDEX` or `INSTALL_INDEX_URL` carries `user:token@` userinfo. The final import/version check runs the consumer interpreter with `-I` (isolated), so it resolves only from the installed downloaded artifact and a stray `PYTHONPATH` pointing at a local checkout cannot produce a false green. The isolated download and the final consumer install both clear resolution-affecting pip/uv inputs (`PIP_INDEX_URL`/`PIP_EXTRA_INDEX_URL`/`PIP_NO_INDEX`/`PIP_FIND_LINKS`/`PIP_CONSTRAINT`/`PIP_REQUIREMENT`/`UV_INDEX_URL`/`UV_EXTRA_INDEX_URL`) and set `PIP_CONFIG_FILE=/dev/null`, so both artifact and dependency provenance come only from the URLs passed explicitly. Because a GitLab-compatible registry forwards not-found requests to public PyPI by default even under `--index-url`, disable package forwarding for the target group/instance; the simple-index check additionally asserts that **every** release-version anchor (wheel and sdist) resolves to the configured registry's host+port, a `/packages/pypi/` file path, and — for a project index — the same project prefix, so a forwarded pypi.org origin, a different host/port, or a different project on the same host all fail. Residual: the check binds the artifacts to the endpoint you configured in `PRIVATE_SIMPLE_INDEX`, so set it to the exact intended project/group endpoint and confirm the project/group id. The proof must still avoid local `[tool.uv.sources]`, editable path installs, and local wheel directories other than the just-downloaded target artifact unless the release explicitly ships through those mechanisms.
