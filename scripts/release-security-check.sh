#!/bin/bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

for forbidden_path in \
  "firebase/functions/.env" \
  "firebase/backups" \
  "DerivedData" \
  "build"
do
  if git ls-files --error-unmatch "$forbidden_path" >/dev/null 2>&1 ||
     git ls-files "$forbidden_path/**" | grep -q .; then
    printf 'Tracked release-secret or build path: %s\n' "$forbidden_path" >&2
    exit 1
  fi
done

secret_patterns=(
  'sk-proj-[A-Za-z0-9_-]{20,}'
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
  '"private_key"[[:space:]]*:[[:space:]]*"-----BEGIN'
  'OPENAI_API_KEY[[:space:]]*=[[:space:]]*[A-Za-z0-9_-]{20,}'
)

for pattern in "${secret_patterns[@]}"; do
  if git grep -nI -E -e "$pattern" -- \
    ':!scripts/release-security-check.sh' \
    ':!firebase/functions/.env.example'
  then
    printf 'Potential credential detected. Remove it before release.\n' >&2
    exit 1
  fi
done

if git ls-files | grep -E '(^|/)(backup|export).*\.(json|ndjson)$' >/dev/null; then
  printf 'Potential Firebase backup/export data is tracked.\n' >&2
  exit 1
fi

npm --prefix firebase/functions audit --audit-level=high

printf 'Release security checks passed.\n'
