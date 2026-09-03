#!/usr/bin/env bash
# This check accepts a fixed shape: the module/run boundary scanners track only module and run boundaries; variable
# and output headers are read by a separate lexical description scan (a column-0 header, a `  description =` line and
# a column-0 `}`), which does not attribute braces; the token sequences << and /* are refused anywhere in variables.tf
# and outputs.tf, and outside
# double-quoted strings in a README example and a test file; a tracked module or run block ends at the next line that
# is exactly } at column 0; the scanner does not attribute braces, so a block whose own closing brace is indented and
# that is followed by another top-level block is not detected; README
# fences begin at column 0; each module README has one hcl fence and one module block; a line starting with module
# in an example, or run in a test file, is exactly module "<name>" { / run "<name>" {, does not arrive while a block
# is open, and every block closes before end of file; the canonical header grammar is this repository's ASCII profile:
# ^module "[A-Za-z_][A-Za-z0-9_-]*" \{$ and ^run "[A-Za-z_][A-Za-z0-9_-]*" \{$. HCL identifiers are Unicode-aware
# (ID_Start (ID_Continue | '-')*), so a label with a Unicode letter is legal HCL and this check refuses it as
# non-canonical; a run block carries command = plan; JSON test files are refused;
# a test file is one tofu test discovers (the module directory and tests/); a test-suffixed file elsewhere under a
# module is refused; dot-prefixed files are ignored; and a same-directory .tftest/.tofutest stem collision is refused;
# the example's ?ref= is a literal ref token that git check-ref-format accepts. These scans
# are lexical: they recognize the canonical spellings and refuse what they can see; they are not an HCL parser. They
# require GNU awk and GNU coreutils.
# The check judges an export of the Git index written to ${tmp_dir}/index, with .gitattributes taken from the index
# tree (git --attr-source), and with GIT_DIR, GIT_INDEX_FILE and the other repository-selection variables cleared.
# git add what you want checked: untracked, ignored and unstaged worktree paths are not exported, while indexed but
# uncommitted content is. Git configuration, .git/info/attributes and filter programs are read as you configured them
# and can transform the exported bytes.
# Every tofu invocation runs through run_tofu, with an environment of exactly PATH (yours), HOME (an empty directory
# under the temporary directory), TMPDIR (the temporary directory) and TF_PLUGIN_CACHE_DIR (yours, or a default under
# the temporary directory); credential-bearing variables, CLI configuration, mirrors and proxies carried by your
# environment are not inherited, and no TF_* variable other than TF_PLUGIN_CACHE_DIR reaches tofu. An honest mistake
# (a run that applies, a filter in TF_CLI_ARGS_test) cannot use them. This is not a sandbox: staged content — this
# script included — runs at your privilege and can read your files, including credential files, and processes. Run the
# check only on a branch you would run a script from.
# Without a lock file, tofu init selects the newest registry release satisfying ~> 5.0 — a freshness sentinel, not a
# reproducible build — and runs it at your privilege; a mirror configured in your CLI configuration is not used.
# tofu test executes what tofu discovers in the module root and tests/; scripts/check-modules.test.sh exercises the
# refusals and the environment. Each fail diagnostic is one record under 4096 bytes; only the record-terminating
# newline is below 0x20.
render_failure() {
  local message
  message=$(LC_ALL=C printf '%s' "$*" | LC_ALL=C tr -d '\000-\037\177' | head -c 4076 || :)
  printf 'check-modules.sh: %s\n' "${message}" >&2
}

fail() {
  render_failure "$@"
  exit 1
}

set -euo pipefail

script_path=$(readlink -f "${BASH_SOURCE[0]}") || fail 'cannot resolve the script path'
repo_root=$(dirname "$(dirname "${script_path}")")

grep_answer() {
  local file=$1 status
  shift
  if grep "$@" "${file}" > /dev/null; then
    return 0
  else
    status=$?
  fi
  [[ "${status}" -eq 1 ]] && return 1
  fail "grep failed for ${file} (status ${status})"
}

token_outside_strings() {
  local file=$1 token=$2 statuses
  if sed -E 's/"([^"\\]|\\.)*"//g' -- "${file}" | grep -nF -- "${token}" > /dev/null; then
    return 0
  else
    statuses=("${PIPESTATUS[@]}")
  fi
  [[ "${statuses[0]}" -eq 0 ]] || fail "sed failed for ${file} (status ${statuses[0]})"
  [[ "${statuses[1]}" -eq 1 ]] && return 1
  fail "grep failed for ${file} (status ${statuses[1]})"
}

run_scan() {
  local label=$1 err_file=$2 awk_program=$3 input=$4 stdout_file=${5:-} status
  : > "${err_file}" || fail "could not prepare ${label} scan diagnostics"
  if [[ -n "${stdout_file}" ]]; then
    if awk "${awk_program}" "${input}" > "${stdout_file}" 2> "${err_file}"; then
      return 0
    else
      status=$?
    fi
  else
    if awk "${awk_program}" "${input}" 2> "${err_file}"; then
      return 0
    else
      status=$?
    fi
  fi
  return "${status}"
}

profile_marker() {
  local err_file=$1 records status line
  profile_record=''
  profile_records=0
  if records=$(grep -E '^PROFILE:[a-z-]+(:.*)?$' "${err_file}"); then
    :
  else
    status=$?
    [[ "${status}" -eq 1 ]] || return "${status}"
    records=''
  fi
  if [[ -n "${records}" ]]; then
    while IFS= read -r line; do
      profile_records=$((profile_records + 1))
      [[ -n "${profile_record}" ]] || profile_record=${line}
    done <<< "${records}"
  fi
  [[ "${profile_records}" -le 1 ]] || return 2
}

run_tofu() {
  "${env_bin}" -i PATH="${PATH}" HOME="${tmp_dir}/home" TMPDIR="${tmp_dir}" TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR}" "${tofu_bin}" "$@"
}

command -v git >/dev/null || fail "git is required"
tofu_bin=$(readlink -f -- "$(command -v tofu)") || fail "tofu is required"
env_bin=$(readlink -f -- "$(command -v env)") || fail "env is required"
cd "${repo_root}" || fail "cannot change to the repository root"
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES GIT_ATTR_SOURCE
[[ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] || fail "not inside a Git work tree"

tmp_dir=''
cleanup() {
  local status=$?
  if [[ -n "${tmp_dir}" ]] && ! rm -rf -- "${tmp_dir}"; then
    trap - EXIT
    render_failure "could not remove temporary directory: ${tmp_dir}"
    [[ "${status}" -ne 0 ]] && exit "${status}"
    exit 1
  fi
  exit "${status}"
}
trap cleanup EXIT
tmp_dir=$(mktemp -d) || fail "could not create a temporary directory"
canonical_tmp_dir=$(readlink -f -- "${tmp_dir}") || fail "could not canonicalize the temporary directory"
tmp_dir=${canonical_tmp_dir}
TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${tmp_dir}/plugin-cache}"
mkdir -p -- "${TF_PLUGIN_CACHE_DIR}" || fail "could not create TF_PLUGIN_CACHE_DIR: ${TF_PLUGIN_CACHE_DIR}"
TF_PLUGIN_CACHE_DIR=$(readlink -f -- "${TF_PLUGIN_CACHE_DIR}") || fail "could not canonicalize TF_PLUGIN_CACHE_DIR"
export TF_PLUGIN_CACHE_DIR

# The export lives in ${tmp_dir}/index; generated examples and the cache are siblings, then the check cd's into it.
index_dir="${tmp_dir}/index"
mkdir -p "${index_dir}" || fail "could not create the index export directory"
index_tree=$(git write-tree) || fail "could not write the index tree (unmerged entries?)"
if ! git --attr-source="${index_tree}" checkout-index -a -f --prefix="${index_dir}/"; then
  fail "could not export the index (git 2.40 or newer is required)"
fi
cd "${index_dir}" || fail "could not change to the index export"

[[ -d modules ]] || fail "modules/ is absent from the index"

if ! find modules -mindepth 1 -maxdepth 1 -print0 > "${tmp_dir}/module-entries"; then
  fail "could not enumerate modules/"
fi
module_dirs=()
while IFS= read -r -d '' module_dir; do
  module=${module_dir##*/}
  [[ "${module}" =~ ^[a-z0-9-]+$ ]] || fail "module directory name is invalid: ${module}"
  module_dirs+=("${module_dir}")
done < "${tmp_dir}/module-entries"

if ! find modules -type l -print0 > "${tmp_dir}/symlinks"; then
  fail "could not inspect modules/ for symlinks"
fi
if IFS= read -r -d '' symlink < "${tmp_dir}/symlinks"; then
  fail "profile refusal: ${symlink} is a symlink; the check keeps a fixed shape"
fi

for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  for required_file in README.md main.tf variables.tf outputs.tf versions.tf; do
    [[ -f "${module_dir}/${required_file}" ]] || fail "assertion 2: ${module} is missing ${required_file}"
  done
done

# Refuse syntax outside the profile before the lexical description scans run.
for module_dir in "${module_dirs[@]}"; do
  for interface_file in "${module_dir}/variables.tf" "${module_dir}/outputs.tf"; do
    if grep_answer "${interface_file}" -nF '<<'; then
      fail "profile refusal: ${interface_file} contains <<; the check keeps a fixed shape"
    fi
    if grep_answer "${interface_file}" -nF '/*'; then
      fail "profile refusal: ${interface_file} contains /*; the check keeps a fixed shape"
    fi
  done
done

for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  main_file="${module_dir}/main.tf"
  if grep_answer "${main_file}" -nE '^(variable|output) "'; then
    fail "assertion 3: ${module}/main.tf declares a variable or output"
  fi
done

for module_dir in "${module_dirs[@]}"; do
  for interface_file in "${module_dir}/variables.tf" "${module_dir}/outputs.tf"; do
    scan_err="${tmp_dir}/description.err"
    if description_line=$(run_scan description "${scan_err}" '
      /^(variable|output) "/ {
        in_block = 1
        block_line = FNR
        has_description = 0
        next
      }
      in_block && /^  description[[:space:]]*=/ { has_description = 1 }
      in_block && /^}/ {
        if (!has_description) {
          outcome = block_line
          exit 1
        }
        in_block = 0
      }
      END {
        if (outcome == "" && in_block && !has_description) outcome = block_line
        if (outcome != "") {
          print outcome
          exit 1
        }
      }
    ' "${interface_file}"); then
      :
    else
      description_status=$?
      if [[ "${description_line}" =~ ^[0-9]+$ ]]; then
        fail "assertion 4: ${interface_file} line ${description_line}: block lacks a description"
      fi
      fail "could not scan ${interface_file} (description awk exit ${description_status})"
    fi
  done
done

for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  readme="${module_dir}/README.md"
  example_dir="${tmp_dir}/examples/${module}"
  mkdir -p "${example_dir}" || fail "could not create ${example_dir}"
  scan_err="${example_dir}/fence.err"
  if run_scan fence "${scan_err}" '
    /^ (```|~~~)/ || /^  (```|~~~)/ || /^   (```|~~~)/ {
      outcome = "indented-fence"
      exit
    }
    !in_block && /^(```|~~~)/ {
      if ($0 == "```hcl" && !seen) {
        in_block = 1
        seen = 1
        next
      }
      outcome = "fence-structure"
      exit
    }
    in_block && /^```$/ {
      in_block = 0
      closed = 1
      next
    }
    in_block { print }
    END {
      if (outcome == "" && (!seen || in_block || !closed)) outcome = "fence-structure"
      if (outcome != "") {
        print "PROFILE:" outcome > "/dev/stderr"
        exit 1
      }
    }
  ' "${readme}" "${example_dir}/main.tf"; then
    :
  else
    fence_status=$?
    if ! profile_marker "${scan_err}" >/dev/null; then
      fail "could not scan ${readme}: ${profile_records} profile records"
    fi
    if [[ -z "${profile_record}" ]]; then
      fail "could not scan ${readme} (fence awk exit ${fence_status})"
    fi
    if [[ "${profile_record}" == 'PROFILE:indented-fence' ]]; then
      fail "profile refusal: ${readme} has an indented fence; the check keeps a fixed shape"
    fi
    fail "assertion 6: ${module} README must contain exactly one complete hcl fence and no other fence"
  fi
  if token_outside_strings "${example_dir}/main.tf" '<<'; then
    fail "profile refusal: ${readme} extracted example contains <<; the check keeps a fixed shape"
  fi
  if token_outside_strings "${example_dir}/main.tf" '/*'; then
    fail "profile refusal: ${readme} extracted example contains /*; the check keeps a fixed shape"
  fi
  if grep_answer "${example_dir}/main.tf" -nE '^\}.'; then
    fail "profile refusal: ${readme} extracted example has a closing line followed by text; the check keeps a fixed shape"
  fi
done

source_pattern='^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::https://github.com/o2csi/terraform-cloudflare-modules\.git//modules/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$'
for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  readme="${module_dir}/README.md"
  example_dir="${tmp_dir}/examples/${module}"
  scan_err="${example_dir}/module.err"
  if source_line=$(run_scan module "${scan_err}" '
    /^[[:space:]]*module[[:space:]]*"/ && in_module { outcome = "module-open:" FNR; exit }
    /^[[:space:]]*module[[:space:]]*"/ && !/^module "[A-Za-z_][A-Za-z0-9_-]*" \{$/ { outcome = "module-noncanonical:" FNR; exit }
    /^module "[A-Za-z_][A-Za-z0-9_-]*" \{$/ { module_count++; in_module = 1; module_line = FNR; next }
    in_module && /^\}$/ { in_module = 0; next }
    in_module && /^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$/ {
      source_count++
      source_line = $0
    }
    END {
      if (outcome == "" && in_module) outcome = "module-unclosed:" module_line
      if (outcome == "" && (module_count != 1 || source_count != 1)) outcome = "module-structure"
      if (outcome != "") {
        print "PROFILE:" outcome > "/dev/stderr"
        exit 1
      }
      print source_line
    }
  ' "${example_dir}/main.tf"); then
    :
  else
    module_status=$?
    if ! profile_marker "${scan_err}" >/dev/null; then
      fail "could not scan ${example_dir}/main.tf: ${profile_records} profile records"
    fi
    if [[ -z "${profile_record}" ]]; then
      fail "could not scan ${example_dir}/main.tf (module awk exit ${module_status})"
    fi
    case "${profile_record}" in
      PROFILE:module-noncanonical:*)
        fail "profile refusal: ${readme} example line ${profile_record#PROFILE:module-noncanonical:} has a non-canonical module header; canonical spelling is module \"[A-Za-z_][A-Za-z0-9_-]*\" {; the check keeps a fixed shape"
        ;;
      PROFILE:module-open:*)
        fail "profile refusal: ${readme} example line ${profile_record#PROFILE:module-open:} has a module header while the previous block is open; the check keeps a fixed shape"
        ;;
      PROFILE:module-unclosed:*)
        fail "profile refusal: ${readme} example line ${profile_record#PROFILE:module-unclosed:} has an unclosed module block; the check keeps a fixed shape"
        ;;
    esac
    if [[ "${profile_record}" != 'PROFILE:module-structure' ]]; then
      fail "could not scan ${example_dir}/main.tf (unknown profile outcome ${profile_record})"
    fi
    fail "assertion 6: ${module} README example: source must be inside the single module block"
  fi
  [[ "${source_line}" =~ ${source_pattern} ]] || fail "assertion 6: ${module} README has no module source ending in //modules/${module}?ref=<something>\""
  source_value=${source_line#*\"}
  source_value=${source_value%%\"*}
  source_name_and_ref=${source_value#git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/}
  source_module=${source_name_and_ref%%\?ref=*}
  source_ref=${source_name_and_ref#*\?ref=}
  [[ "${source_module}" == "${module}" && -n "${source_ref}" ]] || fail "assertion 6: ${module} README has no module source ending in //modules/${module}?ref=<something>\""
  if [[ ! "${source_ref}" =~ ^[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*$ ]]; then
    fail "assertion 6: ${module} README example ref is not a literal Git reference that git check-ref-format --allow-onelevel accepts"
  fi
  if git check-ref-format --allow-onelevel "${source_ref}" >/dev/null 2>&1; then
    :
  else
    ref_status=$?
    [[ "${ref_status}" -eq 1 ]] && fail "assertion 6: ${module} README example ref is not a literal Git reference that git check-ref-format --allow-onelevel accepts"
    fail "could not validate the example ref of ${module} (git check-ref-format exit ${ref_status})"
  fi
done

test_manifest="${tmp_dir}/test-files"
: > "${test_manifest}" || fail "could not prepare test manifest"
for module_dir in "${module_dirs[@]}"; do
  if ! find "${module_dir}" -type f ! -name '.*' \( -name '*.tftest.hcl' -o -name '*.tofutest.hcl' -o -name '*.tftest.json' -o -name '*.tofutest.json' \) -print0 > "${tmp_dir}/module-test-files"; then
    fail "could not enumerate test files"
  fi
  while IFS= read -r -d '' test_file; do
    test_dir=${test_file%/*}
    if [[ "${test_dir}" != "${module_dir}" && "${test_dir}" != "${module_dir}/tests" ]]; then
      fail "profile refusal: ${test_file} is a test file outside the module directory and tests/; tofu test never runs it; the check keeps a fixed shape"
    fi
  done < "${tmp_dir}/module-test-files"
  if ! cat -- "${tmp_dir}/module-test-files" >> "${test_manifest}"; then
    fail "could not prepare test manifest"
  fi
done
while IFS= read -r -d '' test_file; do
  case "${test_file}" in
    *.tftest.json|*.tofutest.json)
      fail "profile refusal: ${test_file} is a JSON test file; the check keeps a fixed shape"
      ;;
  esac
  test_dir=${test_file%/*}
  test_name=${test_file##*/}
  if [[ "${test_name}" =~ ^(.+)\.tftest\.(hcl|json)$ ]] && [[ -f "${test_dir}/${BASH_REMATCH[1]}.tofutest.${BASH_REMATCH[2]}" ]]; then
    fail "profile refusal: ${test_file} and ${test_dir}/${BASH_REMATCH[1]}.tofutest.${BASH_REMATCH[2]} share a test stem; tofu test runs only the tofutest file; the check keeps a fixed shape"
  fi
  if token_outside_strings "${test_file}" '<<'; then
    fail "profile refusal: ${test_file} contains <<; the check keeps a fixed shape"
  fi
  if token_outside_strings "${test_file}" '/*'; then
    fail "profile refusal: ${test_file} contains /*; the check keeps a fixed shape"
  fi
  if grep_answer "${test_file}" -nE '^\}.'; then
    fail "profile refusal: ${test_file} has a closing line followed by text; the check keeps a fixed shape"
  fi
  scan_err="${tmp_dir}/run.err"
  if run_scan run "${scan_err}" '
    /^[[:space:]]*run[[:space:]]*"/ && in_run { outcome = "run-open:" FNR; exit }
    /^[[:space:]]*run[[:space:]]*"/ && !/^run "[A-Za-z_][A-Za-z0-9_-]*" \{$/ { outcome = "run-noncanonical:" FNR; exit }
    /^run "[A-Za-z_][A-Za-z0-9_-]*" \{$/ {
      in_run = 1
      run_line = FNR
      has_plan = 0
      next
    }
    in_run && /^  command[[:space:]]*=[[:space:]]*plan$/ { has_plan = 1; next }
    in_run && /^\}$/ {
      if (!has_plan) {
        outcome = "run-noplan:" run_line
        exit
      }
      in_run = 0
    }
    END {
      if (outcome == "" && in_run) outcome = "run-unclosed:" run_line
      if (outcome != "") {
        print "PROFILE:" outcome > "/dev/stderr"
        exit 1
      }
    }
  ' "${test_file}"; then
    :
  else
    run_status=$?
    if ! profile_marker "${scan_err}" >/dev/null; then
      fail "could not scan ${test_file}: ${profile_records} profile records"
    fi
    if [[ -z "${profile_record}" ]]; then
      fail "could not scan ${test_file} (run awk exit ${run_status})"
    fi
    case "${profile_record}" in
      PROFILE:run-noncanonical:*)
        fail "profile refusal: ${test_file} line ${profile_record#PROFILE:run-noncanonical:} has a non-canonical run header; canonical spelling is run \"[A-Za-z_][A-Za-z0-9_-]*\" {; the check keeps a fixed shape"
        ;;
      PROFILE:run-open:*)
        fail "profile refusal: ${test_file} line ${profile_record#PROFILE:run-open:} has a run block still open when the next run begins; the check keeps a fixed shape"
        ;;
      PROFILE:run-unclosed:*)
        fail "profile refusal: ${test_file} line ${profile_record#PROFILE:run-unclosed:} has a run block unclosed at end of file; the check keeps a fixed shape"
        ;;
      PROFILE:run-noplan:*)
        fail "profile refusal: ${test_file} line ${profile_record#PROFILE:run-noplan:} has a run block that has no command = plan; the check keeps a fixed shape"
        ;;
      *)
        fail "could not scan ${test_file} (unknown profile outcome ${profile_record})"
        ;;
    esac
  fi
done < "${test_manifest}"

mkdir -p "${tmp_dir}/home" || fail "could not create temporary HOME: ${tmp_dir}/home"

if ! run_tofu fmt -no-color -check -recursive modules; then
  fail "assertion 1: tofu fmt -check -recursive failed"
fi

for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  staged_module="modules/${module}"
  if ! run_tofu -chdir="${staged_module}" init -no-color -backend=false -input=false; then
    fail "assertion 5: ${module} init failed"
  fi
  if ! run_tofu -chdir="${staged_module}" validate -no-color; then
    fail "assertion 5: ${module} validate failed"
  fi
  if ! run_tofu -chdir="${staged_module}" test -no-color; then
    fail "assertion 5: ${module} tests failed"
  fi
done

for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  example_dir="${tmp_dir}/examples/${module}"
  staged_source="../../index/modules/${module}"
  awk -v replacement="${staged_source}" '
    /^module "[^"]+" \{$/ { in_module = 1 }
    in_module && /^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$/ {
      prefix = $0
      sub(/"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$/, "", prefix)
      suffix = $0
      sub(/^[^"]*"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"/, "", suffix)
      print prefix "\"" replacement "\"" suffix
      next
    }
    in_module && /^\}$/ { in_module = 0 }
    { print }
  ' "${example_dir}/main.tf" > "${example_dir}/main.tf.rewritten"
  mv "${example_dir}/main.tf.rewritten" "${example_dir}/main.tf"
  if ! run_tofu -chdir="${example_dir}" init -no-color -backend=false -input=false; then
    fail "assertion 6: ${module} README example init failed"
  fi
  if ! run_tofu -chdir="${example_dir}" validate -no-color; then
    fail "assertion 6: ${module} README example validate failed"
  fi
done
