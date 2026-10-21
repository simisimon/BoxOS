#!/usr/bin/env bash
# Analyze + test the Flutter app and compare failures with the known baseline.
# Exits non-zero only when there are new analyzer issues or new failing tests.
set -uo pipefail

repo="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
here="$(cd "$(dirname "$0")" && pwd)"
cd "$repo/app"

# frontend-dev rewrites .dart_tool to container paths on every start.
flutter pub get >/dev/null 2>&1

status=0
issues="$(flutter analyze lib test 2>&1 | grep -E 'error •|warning •' | grep -v 'change_password_screen.dart' || true)"
if [ -n "$issues" ]; then
  echo "New analyzer errors/warnings:"
  echo "$issues"
  status=1
else
  echo "Analyzer: clean (known change_password warning ignored)."
fi

failing="$(mktemp)"
flutter test 2>&1 \
  | grep -E '\[E\]$' \
  | sed -E 's/^[0-9:]+ \+[0-9]+( ~[0-9]+)? -[0-9]+: //; s#^.*/app/test/#test/#' \
  | sort -u > "$failing"

# Golden runs rewrite these Windows-made images on every run.
git -C "$repo" checkout -- app/test/preview/failures/ 2>/dev/null

new="$(comm -23 "$failing" "$here/baseline.txt")"
fixed="$(comm -13 "$failing" "$here/baseline.txt")"
echo "Failing tests: $(wc -l < "$failing" | tr -d ' ') (baseline $(wc -l < "$here/baseline.txt" | tr -d ' '))"
if [ -n "$new" ]; then
  echo "NEW failures:"
  echo "$new"
  status=1
fi
if [ -n "$fixed" ]; then
  echo "Now passing (update baseline.txt):"
  echo "$fixed"
fi
[ -z "$new" ] && echo "No new test failures."
rm -f "$failing"
exit $status
