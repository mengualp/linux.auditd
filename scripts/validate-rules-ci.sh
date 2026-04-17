#!/usr/bin/env bash

set -euo pipefail

rules_file="${1:-audit.rules}"
work_dir="$(mktemp -d)"
portable_rules="${work_dir}/99-ci-portable.rules"
strict_rules="${work_dir}/99-ci-strict.rules"
backup_dir="${work_dir}/backup"
backup_rules_dir="${backup_dir}/rules.d"
backup_audit_rules="${backup_dir}/audit.rules"
had_rules_dir=0
had_audit_rules=0

cleanup() {
  if [[ "$had_rules_dir" == "1" || "$had_audit_rules" == "1" ]]; then
    sudo rm -f /etc/audit/audit.rules
    sudo rm -rf /etc/audit/rules.d

    if [[ "$had_rules_dir" == "1" ]]; then
      sudo cp -a "$backup_rules_dir" /etc/audit/rules.d
    fi

    if [[ "$had_audit_rules" == "1" ]]; then
      sudo cp -a "$backup_audit_rules" /etc/audit/audit.rules
    fi
  fi

  sudo rm -rf "$work_dir"
}

trap cleanup EXIT

if [[ ! -f "$rules_file" ]]; then
  printf 'Rules file not found: %s\n' "$rules_file" >&2
  exit 1
fi

if [[ "${GITHUB_ACTIONS:-}" != "true" && "${AUDITD_CI_ALLOW_LOCAL:-0}" != "1" ]]; then
  printf 'Refusing to modify /etc/audit outside CI. Set AUDITD_CI_ALLOW_LOCAL=1 to override.\n' >&2
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

backup_existing_rules() {
  sudo mkdir -p "$backup_dir"

  if sudo test -d /etc/audit/rules.d; then
    sudo cp -a /etc/audit/rules.d "$backup_rules_dir"
    had_rules_dir=1
  fi

  if sudo test -f /etc/audit/audit.rules; then
    sudo cp -a /etc/audit/audit.rules "$backup_audit_rules"
    had_audit_rules=1
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

identity_exists() {
  local field="$1"
  local value="$2"

  case "$field" in
    gid|egid|sgid|fsgid|obj_gid)
      getent group "$value" >/dev/null 2>&1
      ;;
    *)
      getent passwd "$value" >/dev/null 2>&1
      ;;
  esac
}

should_skip_identity_line() {
  local line="$1"
  local regex='-F[[:space:]]+(auid|uid|euid|suid|fsuid|obj_uid|gid|egid|sgid|fsgid|obj_gid)(!?=)([^[:space:]]+)'

  while [[ "$line" =~ $regex ]]; do
    local field="${BASH_REMATCH[1]}"
    local value="${BASH_REMATCH[3]}"

    line="${line#*"${BASH_REMATCH[0]}"}"

    case "$value" in
      unset|-1|4294967295)
        continue
        ;;
    esac

    if [[ "$value" =~ ^-?[0-9]+$ ]]; then
      continue
    fi

    if ! identity_exists "$field" "$value"; then
      return 0
    fi
  done

  return 1
}

build_ci_copy() {
  local source_rules="$1"
  local output_rules="$2"
  local drop_ignore_errors="${3:-0}"

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
        if [[ "$drop_ignore_errors" == "1" ]]; then
          continue
        fi
        printf '%s\n' "$line" >> "$output_rules"
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
    elif [[ "$trimmed" =~ -F[[:space:]]+exe=([^[:space:]]+) ]]; then
      target="${BASH_REMATCH[1]}"
    fi

    if [[ -n "$target" && "$target" == /* && ! -e "$target" ]]; then
      printf '# CI skipped missing path: %s\n' "$line" >> "$output_rules"
      continue
    fi

    if should_skip_identity_line "$trimmed"; then
      printf '# CI skipped missing identity: %s\n' "$line" >> "$output_rules"
      continue
    fi

    printf '%s\n' "$line" >> "$output_rules"
  done < "$source_rules"
}

start_auditd
backup_existing_rules

build_ci_copy "$rules_file" "$portable_rules" 0
load_rules_copy "$portable_rules"
if ! sudo auditctl -l | grep -q 'process_creation'; then exit 1; fi

build_ci_copy "$rules_file" "$strict_rules" 1
load_rules_copy "$strict_rules"
if ! sudo auditctl -l | grep -q 'process_creation'; then exit 1; fi
