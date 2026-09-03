#!/usr/bin/env bash

set -euo pipefail

script_path=$(readlink -f "${BASH_SOURCE[0]}") || { printf 'FAIL: setup: cannot resolve the test path\n' >&2; exit 1; }
repo_root=$(dirname "$(dirname "${script_path}")")
cd "${repo_root}" || { printf 'FAIL: setup: cannot change to the repository root\n' >&2; exit 1; }

test_root=$(mktemp -d) || { printf 'FAIL: setup: cannot create temporary directory\n' >&2; exit 1; }
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

base_fixture="${test_root}/base"
logs_dir="${test_root}/logs"
shim_dir="${test_root}/shim"
real_path=${PATH}
mkdir -p "${base_fixture}/scripts" "${base_fixture}/modules/cf-kv/tests" "${logs_dir}" "${shim_dir}"

cp -- scripts/check-modules.sh "${base_fixture}/scripts/check-modules.sh"
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

printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" >> "${CHECK_MODULES_TEST_ROOT:?}/logs/${CHECK_MODULES_TEST_CASE:?}.shim.log"' 'exit 97' > "${shim_dir}/tofu"
chmod +x "${shim_dir}/tofu"

fail_case() {
  printf 'FAIL: %s: %s\n' "$1" "$2" >&2
  exit 1
}

new_case() {
  case_dir="${test_root}/cases/$1"
  mkdir -p "${test_root}/cases"
  cp -a "${base_fixture}/." "${case_dir}"
}

run_check() {
  local case_name=$1 mode=$2 status
  if [[ "${mode}" == shim ]]; then
    if CHECK_MODULES_TEST_ROOT="${test_root}" CHECK_MODULES_TEST_CASE="${case_name}" PATH="${shim_dir}:${real_path}" "${case_dir}/scripts/check-modules.sh" > "${logs_dir}/${case_name}.log" 2>&1; then status=0; else status=$?; fi
  else
    if CHECK_MODULES_TEST_ROOT="${test_root}" CHECK_MODULES_TEST_CASE="${case_name}" PATH="${real_path}" TF_PLUGIN_CACHE_DIR="${test_root}/plugin-cache" "${case_dir}/scripts/check-modules.sh" > "${logs_dir}/${case_name}.log" 2>&1; then status=0; else status=$?; fi
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

assert_no_shim() {
  [[ ! -e "${logs_dir}/$1.shim.log" ]] || fail_case "$1" "tofu shim was reached"
}

case_baseline() {
  local status
  new_case baseline
  status=$(run_check baseline real)
  assert_status baseline "${status}" 0
  assert_log_lacks baseline 'check-modules.sh:'
}

case_slash_comment() {
  local status
  new_case slash-comment
  sed -i '/source =/a\  // comment' "${case_dir}/modules/cf-kv/README.md"
  git -C "${case_dir}" add -A
  status=$(run_check slash-comment real)
  assert_status slash-comment "${status}" 0
  assert_log_lacks slash-comment 'check-modules.sh:'
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
}

case_no_modules_in_index() {
  local status
  new_case no-modules-in-index
  git -C "${case_dir}" rm -r -q --cached modules
  status=$(run_check no-modules-in-index shim)
  assert_status no-modules-in-index "${status}" 1
  assert_log_has no-modules-in-index 'modules/ is absent from the index'
  assert_no_shim no-modules-in-index
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
}

case_unstaged_edit() {
  local status
  new_case unstaged-edit
  printf '%s\n' 'this is invalid hcl =' >> "${case_dir}/modules/cf-kv/variables.tf"
  status=$(run_check unstaged-edit real)
  assert_status unstaged-edit "${status}" 0
  assert_log_lacks unstaged-edit 'check-modules.sh:'
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
case_tf_data_dir
printf 'check-modules tests: PASS\n'
