# record-talk-backup

Thin helpers for **silent** talk backup clips. Media MUST land only under:

`/home/fmeneses/Videos/kcd-ba-demo-backup/`

Docs (local-only, not in git): `/home/fmeneses/demos/kcd-argentina2026-openspec-local/changes/kcd-ba-demo-backup/stage-commands.md` and `recording-runbook.md`.

## CLI

```bash
./demo/scripts/record-talk-backup/record-cli.sh 01-skupper -- make demo-skupper
EXPORT=1 ./demo/scripts/record-talk-backup/record-cli.sh 03-ratelimit-429 -- make demo-ratelimit
```

Uses `asciinema` when present; otherwise `script(1)`. Never commits output.

## UI (Playwright)

```bash
ACCESS_URL='http://emojivoto.demo.local:8080/' \
  OUT_FILE='/home/fmeneses/Videos/kcd-ba-demo-backup/kcd-ba-05-ui-a.webm' \
  node demo/scripts/record-talk-backup/record-ui.mjs
```

No microphone. Orchestrator/`make up` (+ optional `make ui`) must already be up.
