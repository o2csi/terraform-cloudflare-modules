#!/usr/bin/env bash
# This check accepts a fixed shape: module and run headers and their closing lines begin at column 0 (other blocks
# are not parsed); the token sequences << and /* are refused anywhere in variables.tf and outputs.tf, and outside
# double-quoted strings in a README example and a test file; a tracked module or run block ends at the next line that
# is exactly } at column 0; the scanner does not attribute braces, so a block whose own closing brace is indented and
# that is followed by another top-level block is not detected; README
# fences begin at column 0; each module README has one hcl fence and one module block; a line starting with module
# in an example, or run in a test file, is exactly module "<name>" { / run "<name>" {, does not arrive while a block
# is open, and every block closes before end of file; a run block carries command = plan; JSON test files are refused;
# a test file is one tofu test discovers (the module directory and tests/); a test-suffixed file elsewhere under a
# module is refused; dot-prefixed files are ignored; and a same-directory .tftest/.tofutest stem collision is refused;
# the example's ?ref= is a literal ref token that git check-ref-format accepts. These scans
# are lexical: they recognize the canonical spellings and refuse what they can see; they are not an HCL parser. They
# require GNU awk, GNU coreutils, GNU findutils, GNU grep and GNU sed.
# The check judges an export of the Git index written to ${tmp_dir}/index, with .gitattributes taken from the index
# tree (git --attr-source), and with GIT_DIR, GIT_INDEX_FILE and the other repository-selection variables cleared.
# git add what you want checked: untracked, ignored, and unstaged content is not read, while indexed but uncommitted
# content is. Git configuration (core.autocrlf, filters, info/attributes) still applies as you configured it.
# Every tofu invocation runs through run_tofu, with an environment of exactly PATH (yours), HOME (an empty directory
# under the temporary directory), TMPDIR (the temporary directory) and TF_PLUGIN_CACHE_DIR (yours, or a default under
# the temporary directory); no other variable is inherited, so none of your credentials, CLI configuration, mirrors
# or proxies is available, and no TF_* variable other than TF_PLUGIN_CACHE_DIR reaches tofu. An honest mistake (a run that applies, a filter in TF_CLI_ARGS_test) cannot
# use them. This is not a sandbox: staged content — this script included — runs at your privilege and can read
# your files and processes. Run the check only on a branch you would run a script from.
# Without a lock file, tofu init selects the newest registry release satisfying ~> 5.0 — a freshness sentinel, not a
# reproducible build — and runs it at your privilege; a mirror configured in your CLI configuration is not used.
# Interface declarations: variable and output headers are accepted only in variables.tf and outputs.tf, at column 0 as variable "<name>" { / output "<name>" { with an ASCII identifier (this repository's profile; HCL itself allows Unicode letters); a .tofu, .tf.json or .tofu.json file in a module root is refused, because tofu would load it (and .tofu shadows .tf) outside the description scan; /* outside a double-quoted string is refused in every module-root .tf, while variables.tf and outputs.tf refuse it even inside strings.
# tofu test executes what tofu discovers in the module root and tests/; scripts/check-modules.test.sh exercises the
# refusals and the environment.
set -euo pipefail

script_path=$(readlink -f "${BASH_SOURCE[0]}") || { printf 'check-modules.sh: cannot resolve the script path\n' >&2; exit 1; }
repo_root=$(dirname "$(dirname "${script_path}")")

fail() {
  printf 'check-modules.sh: %s\n' "$*" >&2
  exit 1
}

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

# Sets profile_record/profile_records. Its stdout is the first protocol record, if any.
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
  [[ -z "${profile_record}" ]] || printf '%s\n' "${profile_record}"
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
    printf 'check-modules.sh: could not remove temporary directory: %s\n' "${tmp_dir}" >&2
    [[ "${status}" -eq 0 ]] && exit 1
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
  if ! find "${module_dir}" -maxdepth 1 -type f -print0 > "${tmp_dir}/module-files"; then
    fail "could not enumerate ${module_dir}"
  fi
  while IFS= read -r -d '' module_file; do
    file_name=${module_file##*/}
    case "${file_name}" in
      *.tofu|*.tf.json|*.tofu.json)
        fail "profile refusal: ${module_file} is a .tofu or JSON configuration file; the check reads .tf files only"
        ;;
    esac
    if [[ "${file_name}" == variables.tf || "${file_name}" == outputs.tf ]]; then
      if grep -nE '^[[:space:]]*(variable|output)[[:space:]]*"' "${module_file}" > "${tmp_dir}/interface-headers"; then
        while IFS= read -r interface_header; do
          line_number=${interface_header%%:*}
          header=${interface_header#*:}
          [[ "${header}" =~ ^(variable|output)\ \"[ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_][ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_0123456789-]*\"\ \{$ ]] || fail "profile refusal: ${module_file} line ${line_number}: an interface header is exactly variable \"<name>\" { or output \"<name>\" { with an ASCII identifier"
        done < "${tmp_dir}/interface-headers"
      else
        status=$?
        [[ "${status}" -eq 1 ]] || fail "grep failed for ${module_file} (status ${status})"
      fi
    elif [[ "${file_name}" == *.tf ]]; then
      if token_outside_strings "${module_file}" '/*'; then
        fail "profile refusal: ${module_file} contains /* outside a string; the check keeps a fixed shape"
      fi
      if declaration_headers=$(grep -m1 -nE '^[[:space:]]*(variable|output)[[:space:]]*"' "${module_file}"); then
        line_number=${declaration_headers%%:*}
        fail "assertion 3: ${module_file} line ${line_number} declares a variable or output outside variables.tf and outputs.tf"
      else
        status=$?
        [[ "${status}" -eq 1 ]] || fail "grep failed for ${module_file} (status ${status})"
      fi
    fi
  done < "${tmp_dir}/module-files"
done

for module_dir in "${module_dirs[@]}"; do
  for interface_file in "${module_dir}/variables.tf" "${module_dir}/outputs.tf"; do
    if ! awk '
      /^(variable|output) "/ {
        block = $2
        gsub(/"/, "", block)
        in_block = 1
        has_description = 0
        next
      }
      in_block && /^  description[[:space:]]*=/ { has_description = 1 }
      in_block && /^}/ {
        if (!has_description) {
          printf "%s: block %s lacks a description\n", FILENAME, block > "/dev/stderr"
          failed = 1
          exit 1
        }
        in_block = 0
      }
      END {
        if (in_block && !has_description && !failed) {
          printf "%s: block %s lacks a description\n", FILENAME, block > "/dev/stderr"
          exit 1
        }
      }
    ' "${interface_file}"; then
      fail "assertion 4: ${interface_file} has a block without description"
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
      cat -- "${scan_err}" >&2
      fail "could not scan ${readme} (awk exit ${fence_status})"
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
    /^[[:space:]]*module[[:space:]]*"/ && in_module { outcome = "module-open"; exit }
    /^[[:space:]]*module[[:space:]]*"/ && !/^module "[^"]+" \{$/ { outcome = "module-noncanonical:" substr($0, 1, 200) (length($0) > 200 ? "..." : ""); exit }
    /^module "[^"]+" \{$/ { module_count++; in_module = 1; next }
    in_module && /^\}$/ { in_module = 0; next }
    in_module && /^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$/ {
      source_count++
      source_line = $0
    }
    END {
      if (outcome == "" && in_module) outcome = "module-unclosed"
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
      cat -- "${scan_err}" >&2
      fail "could not scan ${example_dir}/main.tf (awk exit ${module_status})"
    fi
    case "${profile_record}" in
      PROFILE:module-noncanonical:*)
        fail "profile refusal: ${readme} example has a non-canonical module header: ${profile_record#PROFILE:module-noncanonical:}; the check keeps a fixed shape"
        ;;
      PROFILE:module-open)
        fail "profile refusal: ${readme} example has a module header while the previous block is open; the check keeps a fixed shape"
        ;;
      PROFILE:module-unclosed)
        fail "profile refusal: ${readme} example has an unclosed module block; the check keeps a fixed shape"
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
  if [[ ! "${source_ref}" =~ ^[A-Za-z0-9._/][A-Za-z0-9._/-]*$ ]]; then
    fail "assertion 6: ${module} README example ref is not a literal Git reference: ${source_ref:0:200}"
  fi
  if git check-ref-format --allow-onelevel "${source_ref}" >/dev/null 2>&1; then
    :
  else
    ref_status=$?
    [[ "${ref_status}" -eq 1 ]] && fail "assertion 6: ${module} README example ref is not a literal Git reference: ${source_ref:0:200}"
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
  if missing_run=$(run_scan run "${scan_err}" '
    /^[[:space:]]*run[[:space:]]*"/ && in_run { outcome = "run-open:" run_name; exit }
    /^[[:space:]]*run[[:space:]]*"/ && !/^run "[^"]+" \{$/ { outcome = "run-noncanonical:" substr($0, 1, 200) (length($0) > 200 ? "..." : ""); exit }
    /^run "[^"]+" \{$/ {
      in_run = 1
      run_name = $0
      sub(/^run "/, "", run_name)
      sub(/" \{$/, "", run_name)
      has_plan = 0
      next
    }
    in_run && /^  command[[:space:]]*=[[:space:]]*plan$/ { has_plan = 1; next }
    in_run && /^\}$/ {
      if (!has_plan) {
        outcome = "run-noplan:" run_name
        exit
      }
      in_run = 0
    }
    END {
      if (outcome == "" && in_run) outcome = "run-unclosed:" run_name
      if (outcome != "") {
        print "PROFILE:" outcome > "/dev/stderr"
        exit 1
      }
    }
  ' "${test_file}"); then
    :
  else
    run_status=$?
    if ! profile_marker "${scan_err}" >/dev/null; then
      fail "could not scan ${test_file}: ${profile_records} profile records"
    fi
    if [[ -z "${profile_record}" ]]; then
      cat -- "${scan_err}" >&2
      fail "could not scan ${test_file} (awk exit ${run_status})"
    fi
    case "${profile_record}" in
      PROFILE:run-noncanonical:*)
        fail "profile refusal: ${test_file} has a non-canonical run header: ${profile_record#PROFILE:run-noncanonical:}; the check keeps a fixed shape"
        ;;
      PROFILE:run-open:*)
        fail "profile refusal: ${test_file} has run \"${profile_record#PROFILE:run-open:}\" still open when the next run begins; the check keeps a fixed shape"
        ;;
      PROFILE:run-unclosed:*)
        fail "profile refusal: ${test_file} has run \"${profile_record#PROFILE:run-unclosed:}\" unclosed at end of file; the check keeps a fixed shape"
        ;;
      PROFILE:run-noplan:*)
        fail "profile refusal: ${test_file} run \"${profile_record#PROFILE:run-noplan:}\" has no command = plan; the check keeps a fixed shape"
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
