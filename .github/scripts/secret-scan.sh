#!/usr/bin/env bash
# Minimal secret scan over repository files: private keys and well-known token shapes.
# Fails closed: any git error is a failure, not a clean result.
set -uo pipefail
pattern='-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{32,}'

git grep --untracked -nIE -e "$pattern" -- . ':!.github/scripts/secret-scan.sh'
status=$?
if [ "$status" -eq 0 ]; then
  echo "possible secret found" >&2; exit 1
elif [ "$status" -ne 1 ]; then
  echo "secret scan failed to run (git grep exit $status)" >&2; exit 2
fi

bad="$(git ls-files --cached --others --exclude-standard | grep -E '\.(jks|keystore|p12|pem|apk)$|(^|/)MANIFEST\.txt$' || true)"
if [ -n "$bad" ]; then echo "sensitive or binary files present:" >&2; echo "$bad" >&2; exit 1; fi
echo "secret scan clean"
