#!/usr/bin/env bash
set -euo pipefail
# Ruby takes its encoding from the locale; under a POSIX/unset locale it reads the UTF-8 skill text as US-ASCII and crashes. Pin UTF-8, as CI runs.
case " ${RUBYOPT:-} " in *" -Ku "*) ;; *) export RUBYOPT="-Ku${RUBYOPT:+ $RUBYOPT}" ;; esac

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
    if [[ "$skill_file" == */* ]]; then
      roots+=("${skill_file%/*}")
    else
      roots+=(".")
    fi
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
roots = ARGV
skill_texts = {}
roots.each do |root|
  skill_path = File.join(root, "SKILL.md")
  text = File.read(skill_path)
  skill_texts[skill_path] = text
  data = YAML.load(text) || {}
  %w[name description].each do |key|
    if !data.is_a?(Hash) || data[key].to_s.strip.empty?
      warn "missing_frontmatter_#{key}: #{skill_path}"
      exit 1
    end
  end
  Dir[File.join(root, "agents", "*.yaml")].each { |f| YAML.load_file(f) }
end
puts "yaml_ok"
$stdout.flush

missing = []
roots.each do |root|
  files = [File.join(root, "SKILL.md")] + Dir[File.join(root, "references", "*.md")]
  files.each do |path|
    next unless File.file?(path)
    text = skill_texts[path] || File.read(path)
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
      candidates =
        if ref.start_with?("../")
          # Relative Markdown references navigate from the document that
          # contains them. SKILL.md still resolves from root because it lives
          # there; references/*.md resolves from references/. Preserve the
          # legacy skill-root lookup as a compatibility fallback for older
          # prose locators until those documents are migrated.
          [File.expand_path(ref, File.dirname(path)), File.expand_path(ref, root)].uniq
        else
          [File.join(root, ref)]
        end
      missing << [File.basename(root), path.sub(root + "/", ""), ref] unless candidates.any? { |candidate| File.exist?(candidate) }
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
abs_roots=()
orig_by_abs=()
for root in "${roots[@]}"; do
  # Verify every skill root is reachable and readable up front so a vanished or
  # chmod-000 root still fails closed with credential_path_scan_error. Resolving
  # physical paths and invoking a single `rg` from `/` keeps `--glob` exclusions
  # independent of the caller's cwd while replacing N per-root `rg` spawns with 1.
  if ! abs_root="$(cd "$root" 2>/dev/null && [ -r . ] && pwd -P)"; then
    echo "credential_path_scan_error: scan exited 3 for $root" >&2
    exit 1
  fi
  abs_roots+=("$abs_root")
  orig_by_abs+=("$abs_root"$'\t'"${root%/}")
done
if leak_output="$(cd / && rg -n --hidden --with-filename --color never \
  --glob '!**/scripts/validate-skill.sh' \
  --glob '!**/scripts/generic-r0-leak-scan.sh' \
  --glob '!**/scripts/test_generic_r0_leak_scan.sh' \
  --glob '!**/scripts/test_validate_skill_credential_cwd.sh' \
  'glpat-|PRIVATE-TOKEN: ?[a-zA-Z0-9]|oauth2:[^[:space:]@]+@|/Users/[^/[:space:]]+|\bsk-[A-Za-z0-9_-]{20,}' \
  "${abs_roots[@]}")"; then
  # Re-attach the caller's root spelling with pure bash (no sed) so characters
  # like `&` or `#` in a root path cannot corrupt the reported offender line.
  while IFS= read -r line; do
    mapped="$line"
    for pair in "${orig_by_abs[@]}"; do
      abs_p="${pair%%$'\t'*}"
      orig_p="${pair#*$'\t'}"
      if [[ "$line" == "$abs_p/"* ]]; then
        mapped="$orig_p/${line#"$abs_p/"}"
        break
      fi
    done
    printf '%s\n' "$mapped"
  done <<<"$leak_output"
  leak_status=1
else
  rg_status=$?
  if [[ "$rg_status" -ne 1 ]]; then
    echo "credential_path_scan_error: scan exited $rg_status for ${roots[*]}" >&2
    exit 1
  fi
fi
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
  if ! skill_names_out="$(ruby -ryaml -e '
    ARGV.each do |r|
      d = YAML.load(File.read(File.join(r, "SKILL.md"))) || {}
      name = d.is_a?(Hash) ? d["name"].to_s.strip : ""
      abort "missing_frontmatter_name: #{r}/SKILL.md" if name.empty?
      puts name
    end
  ' "${roots[@]}")"; then
    echo "install_visibility_scan_error" >&2
    exit 2
  fi
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
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
  done <<<"$skill_names_out"
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
