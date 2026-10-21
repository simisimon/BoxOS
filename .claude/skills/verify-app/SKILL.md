---
name: verify-app
description: Check a BoxOS Flutter change — runs flutter analyze and the full flutter test suite, compares failures with the known-red baseline, restores the golden failure images and fixes .dart_tool after the frontend container. Use after any change under app/ before calling it done.
---

Run from anywhere in the repo:

```bash
bash .claude/skills/verify-app/verify.sh
```

It exits 0 when there are no new analyzer errors/warnings and no new failing
tests. Report the result plainly: new failures with their names, or "no new
failures". Do not expect a green suite — `baseline.txt` lists the tests that are
already red (12 outdated widget tests, 2 Windows-only goldens).

If the script lists tests under "Now passing", a fix landed: update
`baseline.txt` by removing those lines, and mention it.

Never regenerate goldens (`--update-goldens`) on macOS.
