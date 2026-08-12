#!/usr/bin/env bash
set -euo pipefail

target="${1:-.}"

if [[ ! -e "$target" ]]; then
  echo "target_not_found: $target" >&2
  exit 2
fi

for required_cmd in ruby rg; do
  if ! command -v "$required_cmd" >/dev/null 2>&1; then
    echo "missing_required_command: $required_cmd" >&2
    exit 2
  fi
done

if [[ -f "$target/SKILL.md" ]]; then
  roots=("$target")
else
  roots=()
  while IFS= read -r skill_file; do
    roots+=("$(dirname "$skill_file")")
  done < <({ find "$target" -mindepth 2 -maxdepth 2 -name SKILL.md -type f
             # Repo-root runs over a skills/<name>/SKILL.md layout: pick up depth-3
             # roots ONLY under a literal skills/ directory (never nested fixtures).
             [ -d "$target/skills" ] && find "$target/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f
           } | sort -u)
fi

if [[ "${#roots[@]}" -eq 0 ]]; then
  echo "no_skill_roots_found: $target" >&2
  exit 2
fi

echo "validating ${#roots[@]} skill root(s)"

ruby -ryaml -e '
ARGV.each do |root|
  data = YAML.load_file(File.join(root, "SKILL.md"))
  %w[name description].each do |key|
    if data[key].to_s.strip.empty?
      warn "missing_frontmatter_#{key}: #{File.join(root, "SKILL.md")}"
      exit 1
    end
  end
  Dir[File.join(root, "agents", "*.yaml")].each { |f| YAML.load_file(f) }
end
puts "yaml_ok"
' "${roots[@]}"

ruby -e '
roots = ARGV
missing = []
roots.each do |root|
  files = [File.join(root, "SKILL.md")] + Dir[File.join(root, "references", "*.md")]
  files.each do |path|
    next unless File.file?(path)
    text = File.read(path)
    text.scan(/`([^`]+\.md)`/).flatten.each do |ref|
      next if ref.include?("*")
      # Cross-package reference: `<pkg>/references/...` resolves against the
      # skills/ parent (sibling skill package). Checked only when the sibling
      # package directory exists — a dangling FILE inside an existing package
      # is flagged; an absent package dir is out of recall (the path may point
      # outside the skills tree). Brace-glob refs (`{a,b}-dev.md`) are skipped
      # like `*` patterns: they name a set, not one file.
      cross = ref.match(/\A([a-z0-9][a-z0-9-]*)\/(references\/.+\.md)\z/)
      if cross && !ref.start_with?("references/") && !ref.include?("{")
        pkg_root = File.expand_path(cross[1], File.expand_path("..", root))
        if File.directory?(pkg_root) && !File.exist?(File.join(pkg_root, cross[2]))
          missing << [File.basename(root), path.sub(root + "/", ""), ref]
        end
        next
      end
      next unless ref.start_with?("references/") || ref.start_with?("../")
      candidate =
        if ref.start_with?("../")
          File.expand_path(ref, root)
        else
          File.join(root, ref)
        end
      missing << [File.basename(root), path.sub(root + "/", ""), ref] unless File.exist?(candidate)
    end
  end
end
if missing.empty?
  puts "markdown_references_ok"
else
  warn "missing_markdown_references:"
  missing.each { |skill, path, ref| warn "  #{skill}/#{path} -> #{ref}" }
  exit 1
end
' "${roots[@]}"

leak_status=0
# Leak-detector machinery is excluded because it MUST embed the very patterns it
# hunts (literal `/Users/`, `glpat-`, token prefixes) as detection rules — the
# same reason this scanner self-excludes validate-skill.sh. generic-r0-leak-scan.sh
# is the public R0 fallback detector and test_generic_r0_leak_scan.sh is its
# fixture test; test_validate_skill_credential_cwd.sh is this scanner's own
# cwd-independence regression test and likewise plants `/Users/` fixtures. All are
# independently regression-covered by the detector's `--self-test` and their
# integration tests, so excluding them here does not weaken real leak coverage of
# authored skill content. (Rationale recorded per the scripts/ AGENTS.md allowlist
# rule.)
for root in "${roots[@]}"; do
  # rg matches --glob patterns relative to its working directory, so running this
  # gate from a subdirectory (e.g. scripts/, as the tests and the mandated
  # worktree workflow do) would stop the self-exclusion globs from matching and
  # the detector scripts would flag their OWN embedded pattern literals (a
  # cwd-dependent false positive). cd into the root and search '.' so the globs
  # are always anchored to the search root. Roots are always skill dirs (each has
  # SKILL.md), never the repo root, so '.' never pulls in a top-level .git file.
  # `cd "$root" || exit 3` distinguishes a vanished/inaccessible root (exit 3 ->
  # fail closed below) from a genuine rg no-match (exit 1); scanning "." keeps the
  # globs anchored to the search root regardless of the caller's cwd.
  if leak_output="$(cd "$root" || exit 3; rg -n --hidden \
    --glob '!**/scripts/validate-skill.sh' \
    --glob '!**/scripts/generic-r0-leak-scan.sh' \
    --glob '!**/scripts/test_generic_r0_leak_scan.sh' \
    --glob '!**/scripts/test_validate_skill_credential_cwd.sh' \
    'glpat-|PRIVATE-TOKEN: ?[a-zA-Z0-9]|oauth2:[^[:space:]@]+@|/Users/[^/[:space:]]+|\bsk-[A-Za-z0-9_-]{20,}' \
    .)"; then
    # Re-attach the root so offenders stay locatable across multiple skill roots.
    # Pure bash (no sed) so a root path containing sed-special chars (& #) cannot
    # corrupt the reported offender path or abort the pipeline.
    while IFS= read -r line; do
      printf '%s\n' "${root%/}/${line#./}"
    done <<<"$leak_output"
    leak_status=1
  else
    rg_status=$?
    # 1 = rg clean (no matches). 2 = rg error, 3 = cd into root failed: both fail
    # closed so an unscannable root is never silently reported clean.
    if [[ "$rg_status" -ne 1 ]]; then
      echo "credential_path_scan_error: scan exited $rg_status for $root" >&2
      exit 1
    fi
  fi
done
if [[ "$leak_status" -eq 0 ]]; then
  echo "credential_path_scan_ok"
else
  echo "credential_or_personal_path_scan_failed" >&2
  exit 1
fi

ruby -e '
roots = ARGV
warnings = []
roots.each do |root|
  files = [File.join(root, "SKILL.md")] + Dir[File.join(root, "references", "*.md")]
  files.each do |path|
    next unless File.file?(path)
    lines = File.readlines(path, chomp: true)
    in_fence = false
    fence_start = nil
    fence_lines = 0
    blockquote_lines = 0
    timestamp_lines = 0
    placeholder_urls = []

    lines.each_with_index do |line, index|
      if line.start_with?("```")
        if in_fence
          if fence_lines > 80
            warnings << "#{path.sub(root + "/", "")}:#{fence_start}: long_fenced_block_lines=#{fence_lines}"
          end
          in_fence = false
          fence_start = nil
          fence_lines = 0
        else
          in_fence = true
          fence_start = index + 1
          fence_lines = 0
        end
        next
      end

      fence_lines += 1 if in_fence
      blockquote_lines += 1 if line.start_with?("> ")
      timestamp_lines += 1 if line.match?(/\b\d{1,2}:\d{2}:\d{2}\b/)
      line.scan(%r{https?://[^\s)>\]]+}).flatten.each do |url|
        placeholder_urls << "#{index + 1}:#{url}" if url.match?(%r{/(search|topics?|tags?|explore)([/?#]|$)}) || url.match?(%r{https?://[^/]+/?$})
      end
    end

    warnings << "#{path.sub(root + "/", "")}: blockquote_heavy_lines=#{blockquote_lines}" if blockquote_lines > 40
    warnings << "#{path.sub(root + "/", "")}: timestamp_like_lines=#{timestamp_lines}" if timestamp_lines > 20
    placeholder_urls.first(5).each { |item| warnings << "#{path.sub(root + "/", "")}:#{item}: placeholder_or_generic_url" }
  end
end

if warnings.empty?
  puts "source_dump_heuristics_ok"
else
  warn "source_dump_heuristics_warn:"
  warnings.each { |warning| warn "  #{warning}" }
end
' "${roots[@]}"

if [[ "${CHECK_INSTALL_VISIBILITY:-0}" = "1" ]]; then
  visible_count=0
  IFS=: read -r -a host_skill_dirs <<< "${HOST_SKILL_DIRS:-${CODEX_HOME:-$HOME/.codex}/skills:$HOME/.claude/skills}"
  for root in "${roots[@]}"; do
    name="$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0])["name"]' "$root/SKILL.md")"
    for skill_home in "${host_skill_dirs[@]}"; do
      if [[ -e "$skill_home/$name" ]]; then
        if [[ -e "$skill_home/$name/SKILL.md" ]]; then
          echo "install_visible: $skill_home/$name"
          visible_count=$((visible_count + 1))
        else
          echo "install_broken: $skill_home/$name" >&2
          exit 1
        fi
      fi
    done
  done
  if [[ "$visible_count" -eq 0 ]]; then
    echo "install_visibility_not_found"
  fi
else
  echo "install_visibility_skipped: set CHECK_INSTALL_VISIBILITY=1 to verify host skill symlinks"
fi

if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Scan git remotes for an embedded credential / leaked token. Per remote URL:
  #  - any glpat- / PRIVATE-TOKEN / oauth2: anywhere is always a failure;
  #  - a `://user:pass@` credential is a failure UNLESS the password is the live
  #    ephemeral CI job token (GitLab CI checks out via
  #    `gitlab-ci-token:<CI_JOB_TOKEN>@host`, which is not a committed secret).
  # The password is parsed from the authority and compared LITERALLY to CI_JOB_TOKEN
  # (no regex on the token — URL-safe is not regex-safe), and only the authority
  # (before the first `/`) is inspected, so a token echoed into a path/query can't
  # suppress scanning of the real credential. Outside CI, CI_JOB_TOKEN is unset, so
  # every `user:pass@` fails — the original strict behavior.
  remote_fail=0
  while read -r _ url _; do
    [[ -z "${url:-}" ]] && continue
    if printf '%s' "$url" | rg -q 'oauth2:|glpat-|PRIVATE-TOKEN'; then remote_fail=1; break; fi
    rest="${url#*://}"; [[ "$rest" == "$url" ]] && continue       # no scheme:// → no inline credential
    authority="${rest%%/*}"; [[ "$authority" != *@* ]] && continue
    userinfo="${authority%@*}"; [[ "$userinfo" != *:* ]] && continue
    pass="${userinfo#*:}"; [[ -z "$pass" ]] && continue
    [[ -n "${CI_JOB_TOKEN:-}" && "$pass" == "$CI_JOB_TOKEN" ]] && continue
    remote_fail=1; break
  done < <(git -C "$target" remote -v)
  if [[ "$remote_fail" -eq 1 ]]; then
    echo "remote_token_scan_failed" >&2
    exit 1
  fi
  git -C "$target" diff --check
  echo "git_checks_ok"
fi

echo "skill_validation_ok"
