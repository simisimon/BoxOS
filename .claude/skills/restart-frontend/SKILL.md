---
name: restart-frontend
description: Restart the frontend-dev container so http://localhost:3001 serves the current app/ code, wait until it is up, and repair the local .dart_tool afterwards.
disable-model-invocation: true
---

`frontend-dev` runs `flutter run -d web-server` and never reloads on its own.

1. `docker compose restart frontend-dev`
2. Wait until `docker compose logs --since 2m frontend-dev` contains
   `is being served` (poll every 5 s, give up after 5 min and show the last
   40 log lines).
3. `cd app && flutter pub get` — the container rewrote
   `.dart_tool/package_config.json` to container paths, which breaks local
   `flutter test`.
4. Tell the user to hard-reload the browser (Cmd+Shift+R); the old build is
   cached otherwise. If the logs show compile errors, report them instead.
