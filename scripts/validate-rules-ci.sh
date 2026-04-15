#!/usr/bin/env bash

set -euo pipefail

rules_file="${1:-audit.rules}"
work_dir="$(mktemp -d)"
strict_rules="${work_dir}/99-ci-strict.rules"

cleanup() {
  rm -rf "$work_dir"
}

trap cleanup EXIT

if [[ ! -f "$rules_file" ]]; then
  printf 'Rules file not found: %s\n' "$rules_file" >&2
  exit 1
fi

start_auditd() {
  if sudo pgrep -x auditd >/dev/null 2>&1; then
    return
  fi

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl start auditd >/dev/null 2>&1 || true
  fi

  if ! sudo pgrep -x auditd >/dev/null 2>&1; then
    sudo auditd
  fi
}

reset_rules_dir() {
  sudo rm -f /etc/audit/audit.rules
  sudo rm -rf /etc/audit/rules.d
  sudo mkdir -p /etc/audit/rules.d
}

load_rules_copy() {
  local source_rules="$1"

  reset_rules_dir
  sudo cp "$source_rules" /etc/audit/rules.d/99-ci.rules
  sudo augenrules --load
}

build_strict_copy() {
  local source_rules="$1"
  local output_rules="$2"

  : > "$output_rules"

  while IFS= read -r line || [[ -n "$line" ]]; do
    local trimmed target

    trimmed="${line#"${line%%[![:space:]]*}"}"

    case "$trimmed" in
      ""|\#*)
        printf '%s\n' "$line" >> "$output_rules"
        continue
        ;;
      -i)
        continue
        ;;
    esac

    target=""

    if [[ "$trimmed" =~ ^-w[[:space:]]+([^[:space:]]+) ]]; then
      target="${BASH_REMATCH[1]}"
    elif [[ "$trimmed" =~ -F[[:space:]]+path=([^[:space:]]+) ]]; then
      target="${BASH_REMATCH[1]}"
    elif [[ "$trimmed" =~ -F[[:space:]]+dir=([^[:space:]]+) ]]; then
      target="${BASH_REMATCH[1]}"
    fi

    if [[ -n "$target" && "$target" == /* && ! -e "$target" ]]; then
      printf '# CI skipped missing path: %s\n' "$line" >> "$output_rules"
      continue
    fi

    printf '%s\n' "$line" >> "$output_rules"
  done < "$source_rules"
}

start_auditd

load_rules_copy "$rules_file"
sudo auditctl -l | grep -q 'process_creation'

build_strict_copy "$rules_file" "$strict_rules"
load_rules_copy "$strict_rules"
sudo auditctl -l | grep -q 'process_creation'
