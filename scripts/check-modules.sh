#!/usr/bin/env bash
# This check accepts a fixed shape: top-level blocks begin at column 0 (enforced by tofu fmt -check);
# no heredoc; no block comment in variables.tf or outputs.tf; no line-leading block comment in a README
# example. Each module README has exactly one fenced block, and that block is hcl.
# Assertions 5 and 6 run tofu init and tofu validate, which download and start the providers the
# checkout names (seven modules constrained >= 5.0 resolve the newest release); run this on a checkout you would run tofu on.
set -euo pipefail

script_path=$(readlink -f "${BASH_SOURCE[0]}") || { printf 'check-modules.sh: cannot resolve the script path\n' >&2; exit 1; }
repo_root=$(dirname "$(dirname "${script_path}")")
cd "${repo_root}" || { printf 'check-modules.sh: cannot change to the repository root\n' >&2; exit 1; }

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

[[ -d modules ]] || fail "modules/ is absent from the repository root"
tmp_dir=$(mktemp -d) || fail "could not create a temporary directory"
cleanup() {
  local status=$?
  if ! rm -rf -- "${tmp_dir}"; then
    printf 'check-modules.sh: could not remove temporary directory: %s\n' "${tmp_dir}" >&2
    [[ "${status}" -eq 0 ]] && exit 1
  fi
  exit "${status}"
}
trap cleanup EXIT

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

if ! tofu fmt -no-color -check -recursive; then
  fail "assertion 1: tofu fmt -check -recursive failed"
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

# Reject every non-hcl fence before extracting the sole permitted README block.
for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  readme="${module_dir}/README.md"
  if ! invalid_fence=$(awk '
    /^(~~~|```)/ && $0 != "```hcl" && $0 != "```" {
      print
      exit
    }
  ' "${readme}"); then
    fail "could not inspect README fences in ${readme}"
  fi
  [[ -z "${invalid_fence}" ]] || fail "profile refusal: ${readme} contains ${invalid_fence}; the check keeps a fixed shape"
done

for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  readme="${module_dir}/README.md"
  example_dir="${tmp_dir}/examples/${module}"
  mkdir -p "${example_dir}"
  if ! awk '
    /^```hcl$/ {
      if (in_block || seen) exit 1
      in_block = 1
      seen = 1
      next
    }
    in_block && /^```$/ {
      in_block = 0
      closed = 1
      next
    }
    in_block { print }
    END { if (!seen || in_block || !closed) exit 1 }
  ' "${readme}" > "${example_dir}/main.tf"; then
    fail "assertion 6: ${module} README must contain exactly one complete hcl fence"
  fi
  if grep_answer "${example_dir}/main.tf" -nF '<<'; then
    fail "profile refusal: ${readme} extracted example contains <<; the check keeps a fixed shape"
  fi
  if grep_answer "${example_dir}/main.tf" -nE '^[[:space:]]*/\\*'; then
    fail "profile refusal: ${readme} extracted example contains line-leading /*; the check keeps a fixed shape"
  fi
done

export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${tmp_dir}/plugin-cache}"
mkdir -p "${TF_PLUGIN_CACHE_DIR}"
for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  staged_module="${tmp_dir}/modules/${module}"
  mkdir -p "${staged_module}"
  if ! find "${module_dir}" -type f -print0 | while IFS= read -r -d '' module_file; do
    relative_file=${module_file#"${module_dir}"/}
    mkdir -p "${staged_module}/$(dirname "${relative_file}")"
    cp -- "${module_file}" "${staged_module}/${relative_file}"
  done; then
    fail "assertion 5: ${module} staging copy failed"
  fi
  if ! tofu -chdir="${staged_module}" init -no-color -backend=false -input=false; then
    fail "assertion 5: ${module} init failed"
  fi
  if ! tofu -chdir="${staged_module}" validate -no-color; then
    fail "assertion 5: ${module} validate failed"
  fi
done

for module_dir in "${module_dirs[@]}"; do
  module=${module_dir##*/}
  example_dir="${tmp_dir}/examples/${module}"
  source_pattern='^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::https://github.com/o2csi/terraform-cloudflare-modules\.git//modules/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$'
  source_count_file="${example_dir}/source-count"
  source_line_file="${example_dir}/source-line"
  if grep_answer "${example_dir}/main.tf" -Ec "${source_pattern}" > "${source_count_file}"; then
    IFS= read -r source_matches < "${source_count_file}" || fail "could not read source count for ${example_dir}/main.tf"
  else
    source_matches=0
  fi
  [[ "${source_matches}" -eq 1 ]] || fail "assertion 6: ${module} README has no module source ending in //modules/${module}?ref=<something>\""
  if grep_answer "${example_dir}/main.tf" -E "${source_pattern}" > "${source_line_file}"; then
    IFS= read -r source_line < "${source_line_file}" || fail "could not read source line for ${example_dir}/main.tf"
  else
    source_line=''
  fi
  source_value=${source_line#*\"}
  source_value=${source_value%%\"*}
  source_name_and_ref=${source_value#git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/}
  source_module=${source_name_and_ref%%\?ref=*}
  source_ref=${source_name_and_ref#*\?ref=}
  [[ "${source_module}" == "${module}" && -n "${source_ref}" ]] || fail "assertion 6: ${module} README has no module source ending in //modules/${module}?ref=<something>\""

  staged_source="../../modules/${module}"
  awk -v replacement="${staged_source}" '
    /^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$/ {
      prefix = $0
      sub(/"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$/, "", prefix)
      suffix = $0
      sub(/^[^"]*"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"/, "", suffix)
      print prefix "\"" replacement "\"" suffix
      next
    }
    { print }
  ' "${example_dir}/main.tf" > "${example_dir}/main.tf.rewritten"
  mv "${example_dir}/main.tf.rewritten" "${example_dir}/main.tf"
  if ! tofu -chdir="${example_dir}" init -no-color -backend=false -input=false; then
    fail "assertion 6: ${module} README example init failed"
  fi
  if ! tofu -chdir="${example_dir}" validate -no-color; then
    fail "assertion 6: ${module} README example validate failed"
  fi
done
