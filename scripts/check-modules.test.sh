#!/usr/bin/env bash
# This test requires GNU awk, GNU coreutils, GNU findutils, GNU grep and GNU sed (readlink -f, sed -i).

set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  prologue_only=0
elif [[ "$#" -eq 1 && "$1" == --prologue-only ]]; then
  prologue_only=1
else
  printf 'FAIL: setup: expected no arguments or --prologue-only\n' >&2
  exit 1
fi

script_path=$(readlink -f "${BASH_SOURCE[0]}") || { printf 'FAIL: setup: cannot resolve the test path\n' >&2; exit 1; }
repo_root=$(dirname "$(dirname "${script_path}")")
cd "${repo_root}" || { printf 'FAIL: setup: cannot change to the repository root\n' >&2; exit 1; }

test_root=''
cleanup() {
  local status=$?
  if [[ -n "${test_root}" ]] && ! rm -rf -- "${test_root}"; then
    printf 'check-modules.test.sh: could not remove temporary directory: %s\n' "${test_root}" >&2
    [[ "${status}" -eq 0 ]] && exit 1
  fi
  exit "${status}"
}
trap cleanup EXIT
test_root=$(mktemp -d) || { printf 'FAIL: setup: cannot create temporary directory\n' >&2; exit 1; }

base_fixture="${test_root}/base"
logs_dir="${test_root}/logs"
shim_dir="${test_root}/shim"
real_path=${PATH}
tofu_bin=$(readlink -f -- "$(command -v tofu)") || { printf 'FAIL: setup: cannot resolve tofu\n' >&2; exit 1; }
cacheprobe_dir="${test_root}/cacheprobe"
cacheprobe_log="${test_root}/relative-cache-probe"
mkdir -p "${base_fixture}/scripts" "${base_fixture}/modules/cf-kv/tests" "${logs_dir}" "${shim_dir}" "${cacheprobe_dir}"

check_modules_script=${CHECK_MODULES_SCRIPT:-scripts/check-modules.sh}
cp -- "${check_modules_script}" "${base_fixture}/scripts/check-modules.sh"
for fixture_file in README.md main.tf variables.tf outputs.tf versions.tf; do
  cp -- "modules/cf-kv/${fixture_file}" "${base_fixture}/modules/cf-kv/${fixture_file}"
done
printf '%s\n' \
  'mock_provider "cloudflare" {}' \
  '' \
  'run "plans" {' \
  '  command = plan' \
  '' \
  '  variables {' \
  '    account_id = "0123456789abcdef0123456789abcdef"' \
  '    title      = "example-namespace"' \
  '  }' \
  '}' > "${base_fixture}/modules/cf-kv/tests/smoke.tftest.hcl"
chmod +x "${base_fixture}/scripts/check-modules.sh"
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_CEILING_DIRECTORIES GIT_ATTR_SOURCE
git -C "${base_fixture}" init -q
git -C "${base_fixture}" config user.name check-modules-test
git -C "${base_fixture}" config user.email check-modules-test@example.invalid
git -C "${base_fixture}" add -A
git -C "${base_fixture}" commit -q -m fixture

[[ "${prologue_only}" -eq 0 ]] || exit 0

envshim_dir="${test_root}/envshim"
mkdir -p "${envshim_dir}"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" >> "${TF_PLUGIN_CACHE_DIR:?}/shim.log"' 'exit 97' > "${shim_dir}/tofu"
chmod +x "${shim_dir}/tofu"
printf '%s\n' '#!/usr/bin/env bash' "env | grep -Ev '^(PWD|SHLVL|_)=' > \"\${TF_PLUGIN_CACHE_DIR:?}/shim.log\"" 'if [[ -f modules/cf-kv/main.tf ]]; then grep -c $'\''\r'\'' modules/cf-kv/main.tf || true; else printf "0\\n"; fi | sed "s/^/cr-count=/" > "${TF_PLUGIN_CACHE_DIR:?}/cr-count"' 'exit 97' > "${envshim_dir}/tofu"
chmod +x "${envshim_dir}/tofu"
printf '%s\n' '#!/usr/bin/env bash' "printf '%s\\n' \"\${TF_PLUGIN_CACHE_DIR:?}\" > '${cacheprobe_log}'" "exec '${tofu_bin}' \"\$@\"" > "${cacheprobe_dir}/tofu"
chmod +x "${cacheprobe_dir}/tofu"

shim_log() {
  printf '%s/cache/%s/shim.log' "${test_root}" "$1"
}

fail_case() {
  printf 'FAIL: %s: %s\n' "$1" "$2" >&2
  if [[ -s "${logs_dir}/$1.log" ]]; then
    printf -- '--- %s.log ---\n' "$1" >&2
    cat -- "${logs_dir}/$1.log" >&2
  fi
  if [[ -s "$(shim_log "$1")" ]]; then
    printf -- '--- %s.shim.log ---\n' "$1" >&2
    cat -- "$(shim_log "$1")" >&2
  fi
  exit 1
}

new_case() {
  case_dir="${test_root}/cases/$1"
  mkdir -p "${test_root}/cases"
  cp -a "${base_fixture}/." "${case_dir}"
}

run_check() {
  local case_name=$1 mode=$2 status cache_dir
  cache_dir="${test_root}/cache/${case_name}"
  mkdir -p "${cache_dir}"
  if [[ "${mode}" == shim ]]; then
    if PATH="${shim_dir}:${real_path}" TF_PLUGIN_CACHE_DIR="${cache_dir}" "${case_dir}/scripts/check-modules.sh" > "${logs_dir}/${case_name}.log" 2>&1; then status=0; else status=$?; fi
  elif [[ "${mode}" == envshim ]]; then
    if PATH="${envshim_dir}:${real_path}" TF_PLUGIN_CACHE_DIR="${cache_dir}" "${case_dir}/scripts/check-modules.sh" > "${logs_dir}/${case_name}.log" 2>&1; then status=0; else status=$?; fi
  elif [[ "${mode}" == relative ]]; then
    if PATH=".:${shim_dir}:${real_path}" TF_PLUGIN_CACHE_DIR="${cache_dir}" "${case_dir}/scripts/check-modules.sh" > "${logs_dir}/${case_name}.log" 2>&1; then status=0; else status=$?; fi
  elif [[ "${mode}" == relative-cache ]]; then
    if (cd -- "${case_dir}" && PATH="${cacheprobe_dir}:${real_path}" TF_PLUGIN_CACHE_DIR=relative-cache "${case_dir}/scripts/check-modules.sh") > "${logs_dir}/${case_name}.log" 2>&1; then status=0; else status=$?; fi
  else
    mkdir -p "${test_root}/plugin-cache"
    if PATH="${real_path}" TF_PLUGIN_CACHE_DIR="${test_root}/plugin-cache" "${case_dir}/scripts/check-modules.sh" > "${logs_dir}/${case_name}.log" 2>&1; then status=0; else status=$?; fi
  fi
  printf '%s' "${status}"
}

assert_status() {
  [[ "$2" -eq "$3" ]] || fail_case "$1" "expected rc $3, got $2"
}

log_probe() {
  local case_name=$1 status
  shift
  if grep "$@" "${logs_dir}/${case_name}.log"; then
    return 0
  else
    status=$?
  fi
  [[ "${status}" -eq 1 ]] && return 1
  fail_case "${case_name}" "could not read ${logs_dir}/${case_name}.log (grep exit ${status})"
}

assert_log_has() {
  log_probe "$1" -Fq -- "$2" || fail_case "$1" "missing log substring: $2"
}

assert_log_lacks() {
  if log_probe "$1" -Fq -- "$2"; then
    fail_case "$1" "unexpected log substring: $2"
  fi
}

assert_log_matches() {
  log_probe "$1" -Eq -- "$2" || fail_case "$1" "missing log pattern: $2"
}

assert_no_shim() {
  [[ ! -e "$(shim_log "$1")" ]] || fail_case "$1" "tofu shim was reached"
}

assert_shim() {
  [[ -e "$(shim_log "$1")" ]] || fail_case "$1" "tofu shim was not reached"
}

case_baseline() {
  local status
  new_case baseline
  status=$(run_check baseline real)
  assert_status baseline "${status}" 0
  assert_log_lacks baseline 'check-modules.sh:'
  printf 'ok baseline\n'
}

case_slash_comment() {
  local status
  new_case slash-comment
  sed -i '/source =/a\  // comment' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check slash-comment real)
  assert_status slash-comment "${status}" 0
  assert_log_lacks slash-comment 'check-modules.sh:'
  printf 'ok slash-comment\n'
}

case_block_comment() {
  local status
  new_case block-comment
  sed -i '/source =/a\  /* x */' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check block-comment shim)
  assert_status block-comment "${status}" 1
  assert_log_has block-comment 'contains /*'
  assert_no_shim block-comment
  printf 'ok block-comment\n'
}

case_token_in_string() {
  local status
  new_case token-in-string
  sed -i 's/title      = "example-namespace"/title      = "x\/*y<<z"/' "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check token-in-string shim)
  assert_status token-in-string "${status}" 1
  assert_log_lacks token-in-string 'profile refusal'
  assert_shim token-in-string
  printf 'ok token-in-string\n'
}

case_second_fence() {
  local status
  new_case second-fence
  printf '%s\n' '' '```' 'ignored' '```' >> "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check second-fence shim)
  assert_status second-fence "${status}" 1
  assert_log_has second-fence 'exactly one complete hcl fence'
  assert_no_shim second-fence
  printf 'ok second-fence\n'
}

case_indented_fence() {
  local status
  new_case indented-fence
  printf '%s\n' '' ' ```hcl' ' ```' >> "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check indented-fence shim)
  assert_status indented-fence "${status}" 1
  assert_log_matches indented-fence 'line [0-9]+'
  assert_log_has indented-fence 'indented fence'
  assert_no_shim indented-fence
  printf 'ok indented-fence\n'
}

case_source_outside_module() {
  local status
  new_case source-outside-module
  sed -i 's|source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-kv?ref=v0.3.0"|source = "./x"|' "${case_dir}/modules/cf-kv/README.md"
  sed -i '/^```$/i\
locals {\
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-kv?ref=v0.3.0"\
}' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check source-outside-module shim)
  assert_status source-outside-module "${status}" 1
  assert_log_has source-outside-module 'source must be inside the single module block'
  assert_no_shim source-outside-module
  printf 'ok source-outside-module\n'
}

case_no_modules_in_index() {
  local status
  new_case no-modules-in-index
  git -C "${case_dir}" rm -r -q --cached modules
  status=$(run_check no-modules-in-index shim)
  assert_status no-modules-in-index "${status}" 1
  assert_log_has no-modules-in-index 'modules/ is absent from the index'
  assert_no_shim no-modules-in-index
  printf 'ok no-modules-in-index\n'
}

case_untracked_then_staged() {
  local status
  new_case untracked-then-staged
  printf '%s\n' 'resource "x" {' > "${case_dir}/modules/cf-kv/broken.tf"
  status=$(run_check untracked-then-staged real)
  assert_status untracked-then-staged "${status}" 0
  assert_log_lacks untracked-then-staged 'check-modules.sh:'
  git -C "${case_dir}" add modules/cf-kv/broken.tf
  status=$(run_check untracked-then-staged real)
  assert_status untracked-then-staged "${status}" 1
  assert_log_has untracked-then-staged 'assertion 1:'
  printf 'ok untracked-then-staged\n'
}

case_unstaged_edit() {
  local status
  new_case unstaged-edit
  printf '%s\n' 'this is invalid hcl =' >> "${case_dir}/modules/cf-kv/variables.tf"
  status=$(run_check unstaged-edit real)
  assert_status unstaged-edit "${status}" 0
  assert_log_lacks unstaged-edit 'check-modules.sh:'
  printf 'ok unstaged-edit\n'
}

case_run_without_plan() {
  local status
  new_case run-without-plan
  printf '%s\n' '' 'run "applies" {' '}' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check run-without-plan shim)
  assert_status run-without-plan "${status}" 1
  assert_log_has run-without-plan 'has no command = plan'
  assert_no_shim run-without-plan
  printf 'ok run-without-plan\n'
}

case_tf_data_dir() {
  local status status_out
  new_case tf-data-dir
  export TF_DATA_DIR="${case_dir}/.tfdata"
  status=$(run_check tf-data-dir real)
  unset TF_DATA_DIR
  assert_status tf-data-dir "${status}" 0
  assert_log_lacks tf-data-dir 'check-modules.sh:'
  [[ ! -e "${case_dir}/.tfdata" ]] || fail_case tf-data-dir 'TF_DATA_DIR was used'
  if ! status_out=$(git -C "${case_dir}" status --porcelain --ignored); then
    fail_case tf-data-dir 'git status failed'
  fi
  [[ -z "${status_out}" ]] || fail_case tf-data-dir 'fixture work tree changed'
  printf 'ok tf-data-dir\n'
}

case_commented_module_header() {
  local status
  new_case commented-module-header
  sed -i '/^```$/i\
module "extra" { # comment\
  source = "./x"\
}' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check commented-module-header shim)
  assert_status commented-module-header "${status}" 1
  assert_log_has commented-module-header 'non-canonical module header'
  assert_no_shim commented-module-header
  printf 'ok commented-module-header\n'
}

case_indented_module_header() {
  local status
  new_case indented-module-header
  sed -i '/^```$/i\
  module "extra" {\
    source = "./x"\
  }' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check indented-module-header shim)
  assert_status indented-module-header "${status}" 1
  assert_log_has indented-module-header 'non-canonical module header'
  assert_no_shim indented-module-header
  printf 'ok indented-module-header\n'
}

case_zero_space_module_header() {
  local status
  new_case zero-space-module-header
  sed -i '/^```$/i\
module"extra"{\
  source = "./x"\
}' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check zero-space-module-header shim)
  assert_status zero-space-module-header "${status}" 1
  assert_log_has zero-space-module-header 'non-canonical module header'
  assert_no_shim zero-space-module-header
  printf 'ok zero-space-module-header\n'
}

case_commented_run_header() {
  local status
  new_case commented-run-header
  printf '%s\n' '' 'run "applies" { # comment' '}' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check commented-run-header shim)
  assert_status commented-run-header "${status}" 1
  assert_log_has commented-run-header 'non-canonical run header'
  assert_no_shim commented-run-header
  printf 'ok commented-run-header\n'
}

case_indented_run_header() {
  local status
  new_case indented-run-header
  printf '%s\n' '' '  run "applies" {' '  }' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check indented-run-header shim)
  assert_status indented-run-header "${status}" 1
  assert_log_has indented-run-header 'non-canonical run header'
  assert_no_shim indented-run-header
  printf 'ok indented-run-header\n'
}

case_zero_space_run_header() {
  local status
  new_case zero-space-run-header
  printf '%s\n' '' 'run"applies"{' '}' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check zero-space-run-header shim)
  assert_status zero-space-run-header "${status}" 1
  assert_log_has zero-space-run-header 'non-canonical run header'
  assert_no_shim zero-space-run-header
  printf 'ok zero-space-run-header\n'
}

case_relative_plugin_cache() {
  local status cache_path expected_cache_path
  new_case relative-plugin-cache
  status=$(run_check relative-plugin-cache relative-cache)
  assert_status relative-plugin-cache "${status}" 0
  assert_log_lacks relative-plugin-cache 'check-modules.sh:'
  [[ -d "${case_dir}/relative-cache" ]] || fail_case relative-plugin-cache 'relative plugin cache was not created in the fixture directory'
  [[ -f "${cacheprobe_log}" ]] || fail_case relative-plugin-cache 'tofu did not receive a plugin cache path'
  if cache_path=$(<"${cacheprobe_log}"); then
    :
  else
    status=$?
    fail_case relative-plugin-cache "could not read ${cacheprobe_log} (read exit ${status})"
  fi
  expected_cache_path=$(readlink -f -- "${case_dir}/relative-cache") || fail_case relative-plugin-cache 'could not canonicalize the fixture plugin cache path'
  [[ "${cache_path}" == "${expected_cache_path}" ]] || fail_case relative-plugin-cache "tofu received a non-absolute or wrong plugin cache path: ${cache_path}"
  printf 'ok relative-plugin-cache\n'
}

case_json_test_file() {
  local status
  new_case json-test-file
  printf '%s\n' '{}' > "${case_dir}/modules/cf-kv/tests/extra.tftest.json"
  git -C "${case_dir}" add -A
  status=$(run_check json-test-file shim)
  assert_status json-test-file "${status}" 1
  assert_log_has json-test-file 'is a JSON test file'
  assert_no_shim json-test-file
  printf 'ok json-test-file\n'
}

case_tf_cli_args() {
  local status
  new_case tf-cli-args
  export TF_CLI_ARGS_test=-filter=modules/cf-kv/tests/nonexistent.tftest.hcl
  status=$(run_check tf-cli-args real)
  unset TF_CLI_ARGS_test
  assert_status tf-cli-args "${status}" 0
  assert_log_matches tf-cli-args 'run "plans"\.\.\. pass'
  printf 'ok tf-cli-args\n'
}

case_env_allowlist() {
  local status names home_value evidence_file
  new_case env-allowlist
  export CLOUDFLARE_API_TOKEN=leak TF_CLI_CONFIG_FILE=/nonexistent TF_DATA_DIR="${case_dir}/.tfdata" HTTPS_PROXY=http://127.0.0.1:9
  status=$(run_check env-allowlist envshim)
  unset CLOUDFLARE_API_TOKEN TF_CLI_CONFIG_FILE TF_DATA_DIR HTTPS_PROXY
  assert_status env-allowlist "${status}" 1
  evidence_file=$(shim_log env-allowlist)
  if names=$(cut -d= -f1 "${evidence_file}" | sort -u | tr '\n' ' '); then
    :
  else
    status=$?
    fail_case env-allowlist "could not read ${evidence_file} (cut/sort exit ${status})"
  fi
  [[ "${names}" == 'HOME PATH TF_PLUGIN_CACHE_DIR TMPDIR ' ]] || fail_case env-allowlist "unexpected tofu environment names: ${names}"
  if home_value=$(grep '^HOME=' "${evidence_file}"); then
    :
  else
    status=$?
    [[ "${status}" -eq 1 ]] || fail_case env-allowlist "could not read ${evidence_file} (grep exit ${status})"
    home_value=''
  fi
  [[ "${home_value}" != "HOME=${HOME}" && "${home_value}" == */home ]] || fail_case env-allowlist "unexpected tofu HOME: ${home_value}"
  printf 'ok env-allowlist\n'
}

case_untracked_gitattributes() {
  local status evidence_file cr_count
  new_case untracked-gitattributes
  printf '%s\n' '*.tf eol=crlf' > "${case_dir}/.gitattributes"
  status=$(run_check untracked-gitattributes envshim)
  assert_status untracked-gitattributes "${status}" 1
  assert_shim untracked-gitattributes
  evidence_file="${test_root}/cache/untracked-gitattributes/cr-count"
  if grep -qx 'cr-count=0' "${evidence_file}"; then
    :
  else
    status=$?
    [[ "${status}" -eq 1 ]] || fail_case untracked-gitattributes "could not read ${evidence_file} (grep exit ${status})"
    if cr_count=$(grep '^cr-count=' "${evidence_file}"); then
      fail_case untracked-gitattributes "export carries carriage returns: ${cr_count}"
    else
      status=$?
      [[ "${status}" -eq 1 ]] || fail_case untracked-gitattributes "could not read ${evidence_file} (grep exit ${status})"
      fail_case untracked-gitattributes 'export carries carriage returns'
    fi
  fi
  printf 'ok untracked-gitattributes\n'
}

case_git_index_file() {
  local status
  new_case git-index-file
  export GIT_INDEX_FILE="${case_dir}/.git/no-such-index"
  status=$(run_check git-index-file shim)
  unset GIT_INDEX_FILE
  assert_status git-index-file "${status}" 1
  assert_log_lacks git-index-file 'modules/ is absent from the index'
  assert_shim git-index-file
  printf 'ok git-index-file\n'
}

case_tofu_file_in_module() {
  local status
  new_case tofu-file-in-module
  printf '%s\n' 'output "b" {' '  description = "documented output"' '  value       = 1' '}' > "${case_dir}/modules/cf-kv/outputs.tofu"
  git -C "${case_dir}" add -A
  status=$(run_check tofu-file-in-module shim)
  assert_status tofu-file-in-module "${status}" 1
  assert_log_has tofu-file-in-module 'profile refusal: modules/cf-kv/outputs.tofu is a .tofu or JSON configuration file; the check reads .tf files only'
  assert_no_shim tofu-file-in-module
  printf 'ok tofu-file-in-module\n'
}

case_json_config_in_module() {
  local status
  new_case json-config-in-module
  printf '%s\n' '{}' > "${case_dir}/modules/cf-kv/.extra.tf.json"
  git -C "${case_dir}" add -A
  status=$(run_check json-config-in-module shim)
  assert_status json-config-in-module "${status}" 1
  assert_log_has json-config-in-module 'profile refusal: modules/cf-kv/.extra.tf.json is a .tofu or JSON configuration file; the check reads .tf files only'
  assert_no_shim json-config-in-module
  printf 'ok json-config-in-module\n'
}

case_output_in_extra_tf() {
  local status
  new_case output-in-extra-tf
  printf '%s\n' 'output "c" {' '  value = 1' '}' > "${case_dir}/modules/cf-kv/extra.tf"
  git -C "${case_dir}" add -A
  status=$(run_check output-in-extra-tf shim)
  assert_status output-in-extra-tf "${status}" 1
  assert_log_has output-in-extra-tf 'assertion 3: modules/cf-kv/extra.tf line 1 declares a variable or output outside variables.tf and outputs.tf'
  assert_no_shim output-in-extra-tf
  printf 'ok output-in-extra-tf\n'
}

case_indented_variable_header() {
  local status
  new_case indented-variable-header
  printf '%s\n' '  variable "x" {' '  description = "documented variable"' '}' > "${case_dir}/modules/cf-kv/variables.tf"
  git -C "${case_dir}" add -A
  status=$(run_check indented-variable-header shim)
  assert_status indented-variable-header "${status}" 1
  assert_log_has indented-variable-header 'profile refusal: modules/cf-kv/variables.tf line 1: an interface header is exactly variable "<name>" { or output "<name>" { with an ASCII identifier'
  assert_no_shim indented-variable-header
  printf 'ok indented-variable-header\n'
}

case_unicode_variable_name() {
  local status
  new_case unicode-variable-name
  printf '%s\n' 'variable "é" {' '  description = "documented variable"' '}' > "${case_dir}/modules/cf-kv/variables.tf"
  git -C "${case_dir}" add -A
  status=$(run_check unicode-variable-name shim)
  assert_status unicode-variable-name "${status}" 1
  assert_log_has unicode-variable-name 'profile refusal: modules/cf-kv/variables.tf line 1: an interface header is exactly variable "<name>" { or output "<name>" { with an ASCII identifier'
  assert_no_shim unicode-variable-name
  printf 'ok unicode-variable-name\n'
}

case_harness_clears_git_selectors() {
  local status
  new_case harness-clears-git-selectors
  if (cd "${repo_root}" && GIT_INDEX_FILE="${case_dir}/ext-index" bash "${script_path}" --prologue-only) > "${logs_dir}/harness-clears-git-selectors.log" 2>&1; then
    status=0
  else
    status=$?
  fi
  assert_status harness-clears-git-selectors "${status}" 0
  [[ ! -e "${case_dir}/ext-index" ]] || fail_case harness-clears-git-selectors 'prologue wrote GIT_INDEX_FILE'
  printf 'ok harness-clears-git-selectors\n'
}

case_block_comment_before_declaration() {
  local status
  new_case block-comment-before-declaration
  printf '%s\n' '/* c */ output "hidden" {' '  description = "x"' '  value = 1' '}' > "${case_dir}/modules/cf-kv/extra.tf"
  git -C "${case_dir}" add -A
  status=$(run_check block-comment-before-declaration shim)
  assert_status block-comment-before-declaration "${status}" 1
  assert_log_has block-comment-before-declaration 'modules/cf-kv/extra.tf contains /* outside a string'
  assert_no_shim block-comment-before-declaration
  printf 'ok block-comment-before-declaration\n'
}

case_unicode_variable_name_locale() {
  local status
  new_case unicode-variable-name-locale
  printf '%s\n' 'variable "é" {' '  description = "documented variable"' '}' > "${case_dir}/modules/cf-kv/variables.tf"
  git -C "${case_dir}" add -A
  # If en_US.UTF-8 is unavailable, Bash warns and falls back; the refusal still passes.
  export LC_ALL=en_US.UTF-8
  status=$(run_check unicode-variable-name-locale shim)
  unset LC_ALL
  assert_status unicode-variable-name-locale "${status}" 1
  assert_log_has unicode-variable-name-locale 'profile refusal: modules/cf-kv/variables.tf line 1: an interface header is exactly variable "<name>" { or output "<name>" { with an ASCII identifier'
  assert_no_shim unicode-variable-name-locale
  printf 'ok unicode-variable-name-locale\n'
}

case_relative_path() {
  local status
  new_case relative-path
  printf '%s\n' '#!/usr/bin/env bash' "printf 'hijacked\\n' >> '${case_dir}/hijack.log'" 'exit 98' > "${case_dir}/tofu"
  chmod +x "${case_dir}/tofu"
  git -C "${case_dir}" add -A
  status=$(run_check relative-path relative)
  assert_status relative-path "${status}" 1
  [[ ! -e "${case_dir}/hijack.log" ]] || fail_case relative-path 'staged tofu was reached'
  assert_shim relative-path
  printf 'ok relative-path\n'
}

case_block_commented_module() {
  local status
  new_case block-commented-module
  sed -i '/^```$/i\
locals {\
  hidden = 1 /*\
module "fake" {\
  source = "git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/cf-kv?ref=v0.3.0"\
}\
  */\
}' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check block-commented-module shim)
  assert_status block-commented-module "${status}" 1
  assert_log_has block-commented-module 'contains /*'
  assert_no_shim block-commented-module
  printf 'ok block-commented-module\n'
}

case_heredoc_in_example() {
  local status
  new_case heredoc-in-example
  sed -i '/^```$/i\
locals { t = <<EOT\
example\
EOT\
}' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check heredoc-in-example shim)
  assert_status heredoc-in-example "${status}" 1
  assert_log_has heredoc-in-example 'contains <<'
  assert_no_shim heredoc-in-example
  printf 'ok heredoc-in-example\n'
}

case_trailing_brace_in_example() {
  local status
  new_case trailing-brace-in-example
  sed -i 's/^}$/} # comment/' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check trailing-brace-in-example shim)
  assert_status trailing-brace-in-example "${status}" 1
  assert_log_has trailing-brace-in-example 'closing line followed by text'
  assert_no_shim trailing-brace-in-example
  printf 'ok trailing-brace-in-example\n'
}

case_unterminated_module() {
  local status
  new_case unterminated-module
  sed -i '/^}$/d' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check unterminated-module shim)
  assert_status unterminated-module "${status}" 1
  assert_log_has unterminated-module 'unclosed module block'
  assert_no_shim unterminated-module
  printf 'ok unterminated-module\n'
}

case_module_header_while_open() {
  local status
  new_case module-header-while-open
  sed -i '/^}$/i\
module "extra" {\
  source = "./x"' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check module-header-while-open shim)
  assert_status module-header-while-open "${status}" 1
  assert_log_has module-header-while-open 'module header while the previous block is open'
  assert_no_shim module-header-while-open
  printf 'ok module-header-while-open\n'
}

case_noncanonical_module_while_open() {
  local status
  new_case noncanonical-module-while-open
  sed -i '/^}$/i\
module "extra" { # c' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check noncanonical-module-while-open shim)
  assert_status noncanonical-module-while-open "${status}" 1
  assert_log_has noncanonical-module-while-open 'module header while the previous block is open'
  assert_no_shim noncanonical-module-while-open
  printf 'ok noncanonical-module-while-open\n'
}

case_interpolated_ref() {
  local status
  new_case interpolated-ref
  sed -i 's/?ref=v0.3.0/?ref=${var.ref}/' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check interpolated-ref shim)
  assert_status interpolated-ref "${status}" 1
  assert_log_has interpolated-ref 'not a literal Git reference'
  assert_log_lacks interpolated-ref 'var.ref'
  assert_no_shim interpolated-ref
  printf 'ok interpolated-ref\n'
}

case_block_commented_plan() {
  local status
  new_case block-commented-plan
  printf '%s\n' '' 'run "applies" {' '  /*' '  command = plan' '  */' '}' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check block-commented-plan shim)
  assert_status block-commented-plan "${status}" 1
  assert_log_has block-commented-plan 'contains /*'
  assert_no_shim block-commented-plan
  printf 'ok block-commented-plan\n'
}

case_heredoc_in_test() {
  local status
  new_case heredoc-in-test
  printf '%s\n' '' 'run "x" {' '  command = plan' '  variables { title = <<EOT' 'example' 'EOT' '  }' '}' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check heredoc-in-test shim)
  assert_status heredoc-in-test "${status}" 1
  assert_log_has heredoc-in-test 'contains <<'
  assert_no_shim heredoc-in-test
  printf 'ok heredoc-in-test\n'
}

case_trailing_brace_in_test() {
  local status
  new_case trailing-brace-in-test
  printf '%s\n' '' 'run "applies" {' '} # comment' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check trailing-brace-in-test shim)
  assert_status trailing-brace-in-test "${status}" 1
  assert_log_has trailing-brace-in-test 'closing line followed by text'
  assert_no_shim trailing-brace-in-test
  printf 'ok trailing-brace-in-test\n'
}

case_unterminated_run() {
  local status
  new_case unterminated-run
  printf '%s\n' '' 'run "applies" {' '  command = plan' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check unterminated-run shim)
  assert_status unterminated-run "${status}" 1
  assert_log_has unterminated-run 'unclosed at end of file'
  assert_no_shim unterminated-run
  printf 'ok unterminated-run\n'
}

case_run_header_while_open() {
  local status
  new_case run-header-while-open
  printf '%s\n' '' 'run "a" {' '  command = plan' 'run "b" {' '  command = plan' '}' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check run-header-while-open shim)
  assert_status run-header-while-open "${status}" 1
  assert_log_has run-header-while-open 'still open when the next run begins'
  assert_no_shim run-header-while-open
  printf 'ok run-header-while-open\n'
}

case_noncanonical_run_while_open() {
  local status
  new_case noncanonical-run-while-open
  printf '%s\n' '' 'run "a" {' '  command = plan' 'run "b" { # c' '}' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check noncanonical-run-while-open shim)
  assert_status noncanonical-run-while-open "${status}" 1
  assert_log_has noncanonical-run-while-open 'still open when the next run begins'
  assert_no_shim noncanonical-run-while-open
  printf 'ok noncanonical-run-while-open\n'
}

case_test_outside_discovery() {
  local status
  new_case test-outside-discovery
  mkdir -p "${case_dir}/modules/cf-kv/fixtures"
  printf '%s\n' 'run "applies" {' '}' > "${case_dir}/modules/cf-kv/fixtures/extra.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check test-outside-discovery shim)
  assert_status test-outside-discovery "${status}" 1
  assert_log_has test-outside-discovery 'outside the module directory and tests/'
  assert_no_shim test-outside-discovery
  printf 'ok test-outside-discovery\n'
}

case_hidden_test_file() {
  local status
  new_case hidden-test-file
  printf '%s\n' 'run "applies" {' '}' > "${case_dir}/modules/cf-kv/tests/.backup.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check hidden-test-file shim)
  assert_status hidden-test-file "${status}" 1
  assert_log_lacks hidden-test-file 'profile refusal'
  assert_shim hidden-test-file
  printf 'ok hidden-test-file\n'
}

case_stem_collision() {
  local status
  new_case stem-collision
  cp -- "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl" "${case_dir}/modules/cf-kv/tests/smoke.tofutest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check stem-collision shim)
  assert_status stem-collision "${status}" 1
  assert_log_has stem-collision 'share a test stem'
  assert_no_shim stem-collision
  printf 'ok stem-collision\n'
}

assert_safe_log() {
  local case_name=$1 control_bytes diagnostic_lines log_bytes log_newlines status
  local log="${logs_dir}/${case_name}.log"
  [[ -s "${log}" ]] || fail_case "${case_name}" "${log} is empty"
  if control_bytes=$(LC_ALL=C tr -d '\012\040-\377' < "${log}" | wc -c); then
    :
  else
    status=$?
    fail_case "${case_name}" "could not inspect ${log} for control bytes (tr or wc exit ${status})"
  fi
  [[ "${control_bytes}" -eq 0 ]] || fail_case "${case_name}" "${log} contains ${control_bytes} control bytes"
  if log_newlines=$(LC_ALL=C tr -cd '\012' < "${log}" | wc -c); then
    :
  else
    status=$?
    fail_case "${case_name}" "could not inspect ${log} for newlines (tr or wc exit ${status})"
  fi
  [[ "${log_newlines}" -eq 1 ]] || fail_case "${case_name}" "${log} contains ${log_newlines} newlines, not one"
  if diagnostic_lines=$(grep -c '^check-modules.sh: ' "${log}"); then
    :
  else
    status=$?
    [[ "${status}" -eq 1 ]] || fail_case "${case_name}" "could not count diagnostic records in ${log} (grep exit ${status})"
    diagnostic_lines=0
  fi
  [[ "${diagnostic_lines}" -eq 1 ]] || fail_case "${case_name}" "${log} has ${diagnostic_lines} diagnostic records, not one"
  if log_bytes=$(wc -c < "${log}"); then
    :
  else
    status=$?
    fail_case "${case_name}" "could not inspect ${log} size (wc exit ${status})"
  fi
  [[ "${log_bytes}" -lt 4096 ]] || fail_case "${case_name}" "${log} is ${log_bytes} bytes, not smaller than 4096"
}

case_control_bytes_run_label() {
  local status run_label
  new_case control-bytes-run-label
  printf -v run_label 'a\033[31mforged\rok'
  printf '\nrun "%s" {\n}\n' "${run_label}" >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check control-bytes-run-label shim)
  assert_status control-bytes-run-label "${status}" 1
  assert_log_matches control-bytes-run-label 'line [0-9]+'
  assert_safe_log control-bytes-run-label
  assert_no_shim control-bytes-run-label
  printf 'ok control-bytes-run-label\n'
}

case_control_bytes_module_label() {
  local status readme_line replacement_readme
  new_case control-bytes-module-label
  replacement_readme="${case_dir}/modules/cf-kv/README.md.replacement"
  while IFS= read -r readme_line || [[ -n "${readme_line}" ]]; do
    if [[ "${readme_line}" == 'module "kv" {' ]]; then
      printf 'module "a\033[31mforged\rok" {\n'
    else
      printf '%s\n' "${readme_line}"
    fi
  done < "${case_dir}/modules/cf-kv/README.md" > "${replacement_readme}"
  mv -- "${replacement_readme}" "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check control-bytes-module-label shim)
  assert_status control-bytes-module-label "${status}" 1
  assert_log_matches control-bytes-module-label 'line [0-9]+'
  assert_safe_log control-bytes-module-label
  assert_no_shim control-bytes-module-label
  printf 'ok control-bytes-module-label\n'
}

case_control_bytes_test_filename() {
  local status test_name
  new_case control-bytes-test-filename
  printf -v test_name '\033[2Jx.tftest.json'
  printf '{}\n' > "${case_dir}/modules/cf-kv/tests/${test_name}"
  git -C "${case_dir}" add -A
  status=$(run_check control-bytes-test-filename shim)
  assert_status control-bytes-test-filename "${status}" 1
  assert_safe_log control-bytes-test-filename
  assert_log_has control-bytes-test-filename 'is a JSON test file'
  assert_no_shim control-bytes-test-filename
  printf 'ok control-bytes-test-filename\n'
}

case_tab_in_test_filename() {
  local status test_name
  new_case tab-in-test-filename
  printf -v test_name 'a\tb.tftest.json'
  printf '{}\n' > "${case_dir}/modules/cf-kv/tests/${test_name}"
  git -C "${case_dir}" add -A
  status=$(run_check tab-in-test-filename shim)
  assert_status tab-in-test-filename "${status}" 1
  assert_safe_log tab-in-test-filename
  assert_log_has tab-in-test-filename 'is a JSON test file'
  assert_no_shim tab-in-test-filename
  printf 'ok tab-in-test-filename\n'
}

case_newline_in_test_filename() {
  local status test_name diagnostic_lines log_lines
  new_case newline-in-test-filename
  printf -v test_name 'a\nforged.tftest.json'
  printf '{}\n' > "${case_dir}/modules/cf-kv/tests/${test_name}"
  git -C "${case_dir}" add -A
  status=$(run_check newline-in-test-filename shim)
  assert_status newline-in-test-filename "${status}" 1
  if diagnostic_lines=$(grep -c '^check-modules.sh:' "${logs_dir}/newline-in-test-filename.log"); then
    :
  else
    status=$?
    [[ "${status}" -eq 1 ]] || fail_case newline-in-test-filename "could not count diagnostic records (grep exit ${status})"
    diagnostic_lines=0
  fi
  [[ "${diagnostic_lines}" -eq 1 ]] || fail_case newline-in-test-filename "expected one diagnostic record, got ${diagnostic_lines}"
  if log_lines=$(wc -l < "${logs_dir}/newline-in-test-filename.log"); then
    :
  else
    status=$?
    fail_case newline-in-test-filename "could not count log lines (wc exit ${status})"
  fi
  [[ "${log_lines}" -eq 1 ]] || fail_case newline-in-test-filename "expected one log line, got ${log_lines}"
  assert_safe_log newline-in-test-filename
  assert_log_has newline-in-test-filename 'is a JSON test file'
  assert_no_shim newline-in-test-filename
  printf 'ok newline-in-test-filename\n'
}

case_unicode_run_label() {
  local status
  new_case unicode-run-label
  printf '%s\n' '' 'run "é" {' '}' >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check unicode-run-label shim)
  assert_status unicode-run-label "${status}" 1
  assert_log_has unicode-run-label 'non-canonical run header'
  assert_log_matches unicode-run-label 'line [0-9]+'
  assert_no_shim unicode-run-label
  printf 'ok unicode-run-label\n'
}

case_long_run_label() {
  local status run_label
  new_case long-run-label
  printf -v run_label '%*s' 20000 ''
  run_label=${run_label// /a}
  printf '\nrun "%s" {\n}\n' "${run_label}" >> "${case_dir}/modules/cf-kv/tests/smoke.tftest.hcl"
  git -C "${case_dir}" add -A
  status=$(run_check long-run-label shim)
  assert_status long-run-label "${status}" 1
  assert_log_has long-run-label 'has no command = plan'
  assert_safe_log long-run-label
  assert_no_shim long-run-label
  printf 'ok long-run-label\n'
}

case_undocumented_block_name() {
  local status block_name
  new_case undocumented-block-name
  printf -v block_name '\033[31mx'
  printf 'variable "%s" {\n}\n' "${block_name}" >> "${case_dir}/modules/cf-kv/variables.tf"
  git -C "${case_dir}" add -A
  status=$(run_check undocumented-block-name shim)
  assert_status undocumented-block-name "${status}" 1
  assert_safe_log undocumented-block-name
  assert_log_matches undocumented-block-name 'line [0-9]+'
  assert_log_has undocumented-block-name 'an interface header is exactly variable "<name>" { or output "<name>" { with an ASCII identifier'
  assert_no_shim undocumented-block-name
  printf 'ok undocumented-block-name\n'
}

case_baseline
case_slash_comment
case_block_comment
case_token_in_string
case_second_fence
case_indented_fence
case_source_outside_module
case_no_modules_in_index
case_untracked_then_staged
case_unstaged_edit
case_run_without_plan
case_env_allowlist
case_tf_data_dir
case_commented_module_header
case_indented_module_header
case_zero_space_module_header
case_commented_run_header
case_indented_run_header
case_zero_space_run_header
case_relative_plugin_cache
case_json_test_file
case_tf_cli_args
case_untracked_gitattributes
case_git_index_file
case_tofu_file_in_module
case_json_config_in_module
case_output_in_extra_tf
case_indented_variable_header
case_unicode_variable_name
case_harness_clears_git_selectors
case_block_comment_before_declaration
case_unicode_variable_name_locale
case_relative_path
case_block_commented_module
case_heredoc_in_example
case_trailing_brace_in_example
case_unterminated_module
case_module_header_while_open
case_noncanonical_module_while_open
case_interpolated_ref
case_block_commented_plan
case_heredoc_in_test
case_trailing_brace_in_test
case_unterminated_run
case_run_header_while_open
case_noncanonical_run_while_open
case_test_outside_discovery
case_hidden_test_file
case_stem_collision
case_control_bytes_run_label
case_control_bytes_module_label
case_control_bytes_test_filename
case_tab_in_test_filename
case_newline_in_test_filename
case_unicode_run_label
case_long_run_label
case_undocumented_block_name
printf 'check-modules tests: PASS\n'
