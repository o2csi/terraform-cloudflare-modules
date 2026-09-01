#!/usr/bin/env bash
# Assertions 5 and 6 may download the Cloudflare provider on a clean run; the
# seven modules constrained >= 5.0 resolve whichever release is newest.
set -euo pipefail

fail() {
  printf 'check-modules.sh: %s\n' "$*" >&2
  exit 1
}

repo_root=$(pwd)
[[ -d modules ]] || fail "run this script from the repository root"

if ! tofu fmt -no-color -check -recursive; then
  fail "assertion 1: tofu fmt -check -recursive failed"
fi

for module_dir in modules/*; do
  module=$(basename "$module_dir")
  for required_file in README.md main.tf variables.tf outputs.tf versions.tf; do
    [[ -f "$module_dir/$required_file" ]] || fail "assertion 2: $module is missing $required_file"
  done
done

for module_dir in modules/*; do
  module=$(basename "$module_dir")
  if grep -nE '^(variable|output) "' "$module_dir/main.tf"; then
    fail "assertion 3: $module/main.tf declares a variable or output"
  fi
done

for module_dir in modules/*; do
  for interface_file in "$module_dir/variables.tf" "$module_dir/outputs.tf"; do
    if grep -nE '<<' "$interface_file"; then
      fail "assertion 4: $interface_file contains a heredoc"
    fi
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
    ' "$interface_file"; then
      fail "assertion 4: $interface_file has a block without description"
    fi
  done
done

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$tmp_dir/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

for module_dir in modules/*; do
  module=$(basename "$module_dir")
  if ! tofu -chdir="$module_dir" init -no-color -backend=false -input=false; then
    fail "assertion 5: $module init failed"
  fi
  if ! tofu -chdir="$module_dir" validate -no-color; then
    fail "assertion 5: $module validate failed"
  fi
done

for module_dir in modules/*; do
  module=$(basename "$module_dir")
  readme="$module_dir/README.md"
  hcl_fences=$(grep -Ec '^```hcl[[:space:]]*$' "$readme" || true)
  [[ "$hcl_fences" -eq 1 ]] || fail "assertion 6: $module README must contain exactly one hcl fence"

  example_dir="$tmp_dir/$module"
  mkdir -p "$example_dir"
  awk '
    /^```hcl[[:space:]]*$/ { in_block = 1; next }
    in_block && /^```[[:space:]]*$/ { exit }
    in_block { print }
  ' "$readme" > "$example_dir/main.tf"

  source_pattern="^[[:space:]]*source[[:space:]]*=[[:space:]]*\"git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/$module\\?ref=[^\"]+\"[[:space:]]*$"
  if ! grep -Eq "$source_pattern" "$example_dir/main.tf"; then
    fail "assertion 6: $module README has no module source ending in //modules/$module?ref=<something>\""
  fi

  sed -E "s|^([[:space:]]*source[[:space:]]*=[[:space:]]*)\"git::https://github.com/o2csi/terraform-cloudflare-modules\.git//modules/$module\\?ref=[^\"]+\"([[:space:]]*)$|\\1\"$repo_root/modules/$module\"\\2|" "$example_dir/main.tf" > "$example_dir/main.tf.rewritten"
  mv "$example_dir/main.tf.rewritten" "$example_dir/main.tf"
  cp "$module_dir/versions.tf" "$example_dir/versions.tf"

  if ! tofu -chdir="$example_dir" init -no-color -backend=false -input=false; then
    fail "assertion 6: $module README example init failed"
  fi
  if ! tofu -chdir="$example_dir" validate -no-color; then
    fail "assertion 6: $module README example validate failed"
  fi
done
