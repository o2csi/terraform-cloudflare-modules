#!/usr/bin/env bash
# This test requires GNU coreutils and sed (readlink -f, sed -i).

set -euo pipefail

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
mkdir -p "${base_fixture}/scripts" "${base_fixture}/modules/cf-kv/tests" "${logs_dir}" "${shim_dir}"

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
git -C "${base_fixture}" init -q
git -C "${base_fixture}" config user.name check-modules-test
git -C "${base_fixture}" config user.email check-modules-test@example.invalid
git -C "${base_fixture}" add -A
git -C "${base_fixture}" commit -q -m fixture

envshim_dir="${test_root}/envshim"
mkdir -p "${envshim_dir}"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" >> "${TF_PLUGIN_CACHE_DIR:?}/shim.log"' 'exit 97' > "${shim_dir}/tofu"
chmod +x "${shim_dir}/tofu"
printf '%s\n' '#!/usr/bin/env bash' "env | grep -Ev '^(PWD|SHLVL|_)=' > \"\${TF_PLUGIN_CACHE_DIR:?}/shim.log\"" 'if [[ -f modules/cf-kv/main.tf ]]; then grep -c $'\''\r'\'' modules/cf-kv/main.tf || true; else printf "0\\n"; fi | sed "s/^/cr-count=/" > "${TF_PLUGIN_CACHE_DIR:?}/cr-count"' 'exit 97' > "${envshim_dir}/tofu"
chmod +x "${envshim_dir}/tofu"

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
  else
    mkdir -p "${test_root}/plugin-cache"
    if PATH="${real_path}" TF_PLUGIN_CACHE_DIR="${test_root}/plugin-cache" "${case_dir}/scripts/check-modules.sh" > "${logs_dir}/${case_name}.log" 2>&1; then status=0; else status=$?; fi
  fi
  printf '%s' "${status}"
}

assert_status() {
  [[ "$2" -eq "$3" ]] || fail_case "$1" "expected rc $3, got $2"
}

assert_log_has() {
  grep -Fq -- "$2" "${logs_dir}/$1.log" || fail_case "$1" "missing log substring: $2"
}

assert_log_lacks() {
  ! grep -Fq -- "$2" "${logs_dir}/$1.log" || fail_case "$1" "unexpected log substring: $2"
}

assert_log_matches() {
  grep -Eq -- "$2" "${logs_dir}/$1.log" || fail_case "$1" "missing log pattern: $2"
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
  assert_log_has block-comment 'line-leading /*'
  assert_no_shim block-comment
  printf 'ok block-comment\n'
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
  local status
  new_case tf-data-dir
  export TF_DATA_DIR="${case_dir}/.tfdata"
  status=$(run_check tf-data-dir real)
  unset TF_DATA_DIR
  assert_status tf-data-dir "${status}" 0
  assert_log_lacks tf-data-dir 'check-modules.sh:'
  [[ ! -e "${case_dir}/.tfdata" ]] || fail_case tf-data-dir 'TF_DATA_DIR was used'
  [[ -z "$(git -C "${case_dir}" status --porcelain --ignored)" ]] || fail_case tf-data-dir 'fixture work tree changed'
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
  local status names home_value
  new_case env-allowlist
  export CLOUDFLARE_API_TOKEN=leak TF_CLI_CONFIG_FILE=/nonexistent TF_DATA_DIR="${case_dir}/.tfdata" HTTPS_PROXY=http://127.0.0.1:9
  status=$(run_check env-allowlist envshim)
  unset CLOUDFLARE_API_TOKEN TF_CLI_CONFIG_FILE TF_DATA_DIR HTTPS_PROXY
  assert_status env-allowlist "${status}" 1
  names=$(cut -d= -f1 "$(shim_log env-allowlist)" | sort -u | tr '\n' ' ')
  [[ "${names}" == 'HOME PATH TF_PLUGIN_CACHE_DIR TMPDIR ' ]] || fail_case env-allowlist "unexpected tofu environment names: ${names}"
  home_value=$(grep '^HOME=' "$(shim_log env-allowlist)")
  [[ "${home_value}" != "HOME=${HOME}" && "${home_value}" == */home ]] || fail_case env-allowlist "unexpected tofu HOME: ${home_value}"
  printf 'ok env-allowlist\n'
}

case_untracked_gitattributes() {
  local status
  new_case untracked-gitattributes
  printf '%s\n' '*.tf eol=crlf' > "${case_dir}/.gitattributes"
  status=$(run_check untracked-gitattributes envshim)
  assert_status untracked-gitattributes "${status}" 1
  assert_shim untracked-gitattributes
  grep -qx 'cr-count=0' "${test_root}/cache/untracked-gitattributes/cr-count" || fail_case untracked-gitattributes "export carries carriage returns: $(grep '^cr-count=' "${test_root}/cache/untracked-gitattributes/cr-count")"
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

case_baseline
case_slash_comment
case_block_comment
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
case_commented_run_header
case_json_test_file
case_tf_cli_args
case_untracked_gitattributes
case_git_index_file
case_relative_path
printf 'check-modules tests: PASS\n'
