#!/usr/bin/env bash
# Run every *_test.sh under tests/. Non-zero exit if any fails.
set -u
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
rc=0
for t in "$DIR"/*_test.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || rc=1
done
exit $rc
