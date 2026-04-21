#!/usr/bin/env bash

set -euo pipefail

rules_file="${1:-audit.rules}"

if [[ ! -f "$rules_file" ]]; then
  printf 'Rules file not found: %s\n' "$rules_file" >&2
  exit 1
fi

errors=0
line_no=0

while IFS= read -r line || [[ -n "$line" ]]; do
  line_no=$((line_no + 1))
  trimmed="${line#"${line%%[![:space:]]*}"}"

  case "$trimmed" in
    ""|\#*)
      continue
      ;;
  esac

  if [[ "$trimmed" == -w\ * ]] && [[ "$trimmed" != *" -p "* ]]; then
    printf 'Line %d: watch rule missing -p: %s\n' "$line_no" "$trimmed" >&2
    errors=1
  fi

  if [[ "$trimmed" == -a\ * || "$trimmed" == -A\ * ]]; then
    if [[ "$trimmed" == *" -p "* ]]; then
      printf 'Line %d: syscall rule uses bare -p; use -F perm=... instead: %s\n' "$line_no" "$trimmed" >&2
      errors=1
    fi

    if [[ "$trimmed" == *" -k -F "* ]]; then
      printf 'Line %d: malformed key expression: %s\n' "$line_no" "$trimmed" >&2
      errors=1
    fi

    if [[ "$trimmed" == *"-F obj="* ]]; then
      printf 'Line %d: unsupported obj= field in syscall rule: %s\n' "$line_no" "$trimmed" >&2
      errors=1
    fi

    if [[ "$trimmed" == *"-F dir=+"* ]]; then
      printf 'Line %d: invalid dir=+ filter in syscall rule: %s\n' "$line_no" "$trimmed" >&2
      errors=1
    fi
  fi
done < "$rules_file"

exit "$errors"
