#!/usr/bin/env bash
# This check accepts a fixed shape: top-level blocks begin at column 0; no heredoc; no block comment in
# variables.tf or outputs.tf; no line-leading block comment in a README example; README fences begin at column 0;
# each README has one hcl fence and one top-level module block; a line starting with module in an extracted example,
# or run in a test file, must be exactly module "<name>" { / run "<name>" {; a run block must carry command = plan;
# and JSON test files are refused. These scans are lexical: they recognize the canonical spelling and refuse others
# they can see; they are not an HCL parser and do not prove what tofu will execute.
# The check judges an export of the Git index written to ${tmp_dir}/index, with .gitattributes taken from the index
# tree (git --attr-source), and with GIT_DIR, GIT_INDEX_FILE and the other repository-selection variables cleared.
# git add what you want checked: untracked, ignored, and unstaged content is not read, while indexed but uncommitted
# content is. Git configuration (core.autocrlf, filters, info/attributes) still applies as you configured it.
# Every tofu invocation runs through run_tofu, with an environment of exactly PATH, HOME (an empty directory under
# the temporary directory), TMPDIR and TF_PLUGIN_CACHE_DIR: none of your credentials, CLI configuration, mirrors,
# proxies or TF_* variables is inherited, so an honest mistake (a run that applies, a filter in TF_CLI_ARGS_test)
# cannot use them. This is not a sandbox: staged content — this script included — runs at your privilege and can read
# your files and processes. Run the check only on a branch you would run a script from.
# Without a lock file, tofu init selects the newest registry release satisfying ~> 5.0 — a freshness sentinel, not a
# reproducible build — and runs it at your privilege; a mirror configured in your CLI configuration is not used.
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
  if grep "$@" "${file}"; then
    return 0
  else
    status=$?
  fi
  [[ "${status}" -eq 1 ]] && return 1
  fail "grep failed for ${file} (status ${status})"
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
tmp_dir=$(readlink -f -- "${tmp_dir}") || fail "could not canonicalize the temporary directory"

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
  if awk '
    /^ (```|~~~)/ || /^  (```|~~~)/ || /^   (```|~~~)/ {
      indented = 1
      exit 2
    }
    !in_block && /^(```|~~~)/ {
      if ($0 == "```hcl" && !seen) {
        in_block = 1
        seen = 1
        next
      }
      failed = 1
      exit 1
    }
    in_block && /^```$/ {
      in_block = 0
      closed = 1
      next
    }
    in_block { print }
    END {
      if (indented) exit 2
      if (failed || !seen || in_block || !closed) exit 1
    }
  ' "${readme}" > "${example_dir}/main.tf"; then
    :
  else
    fence_status=$?
    if [[ "${fence_status}" -eq 2 ]]; then
      fail "profile refusal: ${readme} has an indented fence; the check keeps a fixed shape"
    fi
    fail "assertion 6: ${module} README must contain exactly one complete hcl fence and no other fence"
  fi
  if grep_answer "${example_dir}/main.tf" -nF '<<'; then
    fail "profile refusal: ${readme} extracted example contains <<; the check keeps a fixed shape"
  fi
  if grep_answer "${example_dir}/main.tf" -nE '^[[:space:]]*/\*'; then
    fail "profile refusal: ${readme} extracted example contains line-leading /*; the check keeps a fixed shape"
  fi
done

source_pattern='^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::https://github.com/o2csi/terraform-cloudflare-modules\.git//modules/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$'
for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  example_dir="${tmp_dir}/examples/${module}"
  if source_line=$(awk '
    /^module / && !/^module "[^"]+" \{$/ { print; noncanonical = 1; exit 3 }
    /^module "[^"]+" \{$/ { module_count++; in_module = 1; next }
    in_module && /^\}$/ { in_module = 0; next }
    in_module && /^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$/ {
      source_count++
      source_line = $0
    }
    END {
      if (noncanonical) exit 3
      if (module_count != 1 || source_count != 1) exit 1
      print source_line
    }
  ' "${example_dir}/main.tf"); then
    :
  else
    module_status=$?
    if [[ "${module_status}" -eq 3 ]]; then
      fail "profile refusal: ${readme} example has a non-canonical module header: ${source_line}; the check keeps a fixed shape"
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
done

if ! find modules -type f \( -name '*.tftest.hcl' -o -name '*.tofutest.hcl' -o -name '*.tftest.json' -o -name '*.tofutest.json' \) -print0 > "${tmp_dir}/test-files"; then
  fail "could not enumerate test files"
fi
while IFS= read -r -d '' test_file; do
  case "${test_file}" in
    *.tftest.json|*.tofutest.json)
      fail "profile refusal: ${test_file} is a JSON test file; the check keeps a fixed shape"
      ;;
  esac
  if missing_run=$(awk '
    /^run / && !/^run "[^"]+" \{$/ { print; noncanonical = 1; exit 3 }
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
        print run_name
        failed = 1
        exit 1
      }
      in_run = 0
    }
    END {
      if (noncanonical) exit 3
      if (!failed && in_run && !has_plan) {
        print run_name
        failed = 1
      }
      if (failed) exit 1
    }
  ' "${test_file}"); then
    :
  else
    run_status=$?
    if [[ "${run_status}" -eq 3 ]]; then
      fail "profile refusal: ${test_file} has a non-canonical run header: ${missing_run}; the check keeps a fixed shape"
    fi
    fail "profile refusal: ${test_file} run \"${missing_run}\" has no command = plan; the check keeps a fixed shape"
  fi
done < "${tmp_dir}/test-files"

export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${tmp_dir}/plugin-cache}"
mkdir -p "${TF_PLUGIN_CACHE_DIR}" || fail "could not create TF_PLUGIN_CACHE_DIR: ${TF_PLUGIN_CACHE_DIR}"
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
