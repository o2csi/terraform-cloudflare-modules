#!/usr/bin/env bash
# Assertions 5 and 6 may download the Cloudflare provider on a clean run; the
# seven modules constrained >= 5.0 resolve whichever release is newest.
# Assertions 5 and 6 run tofu init and tofu validate, which download and start
# the providers the checkout names; run this on a checkout you would run tofu on.
set -euo pipefail

fail() {
  printf 'check-modules.sh: %s\n' "$*" >&2
  exit 1
}

[[ -d modules ]] || fail "run this script from the repository root"

for module_dir in modules/*; do
  module=${module_dir##*/}
  [[ "$module" =~ ^[a-z0-9-]+$ ]] || fail "module directory name is invalid: $module"
done

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
      fail "<< is not accepted in variables.tf or outputs.tf: a heredoc would end the block scan early, so the token is refused wherever it appears"
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
  module=${module_dir##*/}
  staged_module="$tmp_dir/modules/$module"
  mkdir -p "$staged_module"
  while IFS= read -r -d '' module_file; do
    relative_file=${module_file#"$module_dir"/}
    mkdir -p "$staged_module/$(dirname "$relative_file")"
    cp -- "$module_file" "$staged_module/$relative_file"
  done < <(find "$module_dir" -name '.terraform*' -prune -o -type f -print0)

  if ! tofu -chdir="$staged_module" init -no-color -backend=false -input=false; then
    fail "assertion 5: $module init failed"
  fi
  if ! tofu -chdir="$staged_module" validate -no-color; then
    fail "assertion 5: $module validate failed"
  fi
done

for module_dir in modules/*; do
  module=${module_dir##*/}
  readme="$module_dir/README.md"

  example_dir="$tmp_dir/examples/$module"
  mkdir -p "$example_dir"
  if ! awk '
    /^```hcl[[:space:]]*$/ {
      if (in_block || seen) {
        exit 1
      }
      in_block = 1
      seen = 1
      next
    }
    in_block && /^```[[:space:]]*$/ {
      in_block = 0
      closed = 1
      next
    }
    in_block { print }
    END {
      if (!seen || in_block || !closed) {
        exit 1
      }
    }
  ' "$readme" > "$example_dir/main.tf"; then
    fail "assertion 6: $module README must contain exactly one complete hcl fence"
  fi

  source_pattern='^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::https://github.com/o2csi/terraform-cloudflare-modules\.git//modules/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$'
  source_matches=$(grep -Ec "$source_pattern" "$example_dir/main.tf" || true)
  if [[ "$source_matches" -ne 1 ]]; then
    fail "assertion 6: $module README has no module source ending in //modules/$module?ref=<something>\""
  fi

  source_line=$(grep -E "$source_pattern" "$example_dir/main.tf")
  source_value=${source_line#*\"}
  source_value=${source_value%%\"*}
  source_name_and_ref=${source_value#git::https://github.com/o2csi/terraform-cloudflare-modules.git//modules/}
  source_module=${source_name_and_ref%%\?ref=*}
  source_ref=${source_name_and_ref#*\?ref=}
  if [[ "$source_module" != "$module" || -z "$source_ref" ]]; then
    fail "assertion 6: $module README has no module source ending in //modules/$module?ref=<something>\""
  fi

  staged_source="../../modules/$module"
  awk -v replacement="$staged_source" '
    /^[[:space:]]*source[[:space:]]*=[[:space:]]*"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$/ {
      prefix = $0
      sub(/"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"[[:space:]]*$/, "", prefix)
      suffix = $0
      sub(/^[^"]*"git::https:\/\/github.com\/o2csi\/terraform-cloudflare-modules\.git\/\/modules\/[a-z0-9-]+\?ref=[^"]+"/, "", suffix)
      print prefix "\"" replacement "\"" suffix
      next
    }
    { print }
  ' "$example_dir/main.tf" > "$example_dir/main.tf.rewritten"
  mv "$example_dir/main.tf.rewritten" "$example_dir/main.tf"

  if ! tofu -chdir="$example_dir" init -no-color -backend=false -input=false; then
    fail "assertion 6: $module README example init failed"
  fi
  if ! tofu -chdir="$example_dir" validate -no-color; then
    fail "assertion 6: $module README example validate failed"
  fi
done
