# Stage commands — KCD BA demo backup

**Talk:** KCD Argentina 2026 — conectividad multicluster (30 min)  
**A** = Francisco Meneses · **B** = Sergio Canales (swap OK if documented)  
**Sites allowlist:** `kind-west` / `kind-east` / `podman-edge`  
**Never** operate or record against `kind-cluster`  
**Binary / offline policy:** no proprietary RH PPTX; no video/PPTX binaries in git; backup media lives only under `/home/fmeneses/Videos/kcd-ba-demo-backup/` (filenames below; never commit the files)

Prefer Make over ad-hoc YAML on stage. Live first; if a cue stalls **≤ ~2 minutes**, abandon → play the matching clip → advance.

**Hilo conductor (guion ↔ grabación por slide):** [`talk-conductor.md`](./talk-conductor.md) · Cards: [`speaker-cards.md`](./speaker-cards.md) · Runbook: [`recording-runbook.md`](./recording-runbook.md) · helpers: `demo/scripts/record-talk-backup/`  
**Extra architecture diagrams (aparte from primary slide 5):** [`../archive/2026-10-13-kcd-ba-arch-diagrams/`](../archive/2026-10-13-kcd-ba-arch-diagrams/) — visual-only ChatGPT prompts; no Make cue; skip on overrun at or before Option-C.

### Slide ↔ clip (resumen)

| Slide | Live | Backup file |
|------:|------|-------------|
| 7 | `make demo-skupper` | `kcd-ba-01-skupper.cast` (+ opc. `07-ui-c.webm`) |
| 8 | `make demo-mesh` | `kcd-ba-02-mesh.cast` (+ opc. `06-ui-b.webm`) |
| 9 | `make demo-ratelimit` | `kcd-ba-03-ratelimit-429.cast` (+ opc. `05-ui-a.webm`) |
| 10 | `make failover` | `kcd-ba-04-failover.cast` |

---

## Pre-warm (off-clock — before the 30 min)

| Step | Command | Expected signal |
|------|---------|-----------------|
| 1 | `make prereq-check` | Host CLIs / versions OK |
| 2 | `make up` | Sites + stack ready |
| 3 | `make smoke` | 200/429, mesh, Skupper, dig OK |
| 4 | Hosts | `127.0.0.1 emojivoto.demo.local` in `/etc/hosts` if needed |
| 5 | Optional | `make ui` — save printed `ACCESS_URL=` values (A→B→C) |

Confirm **no** use of `kind-cluster`. Teardown after rehearsal/talk: `make ui-down` (if UI was up) then `make down`.

---

## Live ordered block (critical path)

| Clock | Owner | Cue ID | Make command | Expected signal | Backup clip ID |
|-------|-------|--------|--------------|-----------------|----------------|
| ~9–12 | B | Skupper | `make demo-skupper` | Kind↔Podman / legacy-emoji OK (optional curl `http://127.0.0.1:18080/`) | `01-skupper` |
| ~12–16 | B | Mesh | `make demo-mesh` | Linkerd / emojivoto E-W OK | `02-mesh` |
| ~16–20 | A | RateLimit | `make demo-ratelimit` | ≥1 HTTP **429** | `03-ratelimit-429` |
| ~20–25 | A | Failover | `make failover` | East keeps serving after west hurt (≤~120s) | `04-failover` |

Optional curl companion for Skupper (not a substitute for Make):

```bash
curl -sS http://127.0.0.1:18080/
```

---

## Optional UI on stage (A→B→C)

Only if clock allows and `make ui` already printed ACCESS_URLs. **Skip UI first** on overrun or stall.

| Order | Owner | Surface | Typical ACCESS_URL | Backup clip ID |
|-------|-------|---------|--------------------|----------------|
| A | A | Emojivoto app | `http://emojivoto.demo.local:8080/` | `05-ui-a` |
| B | B | Linkerd Viz | `http://127.0.0.1:50750/` | `06-ui-b` |
| C | B | Skupper observer | `https://127.0.0.1:8443/` | `07-ui-c` |

Hygiene on camera: never open `demo/.run/`; never show basic-auth credentials; accept self-signed cert for observer without pasting secrets.

---

## Cut / abandon rules

1. **Skip-first:** cut live UI before cutting critical-path Make cues.
2. **≤2m abandon:** if a live cue fails or hangs ~2 minutes → stop fighting → play matching clip from the media root → continue (takeaways if needed).
3. **Overrun order:** (1) UI live, (2) Option-C deep diagram backup (outside the 12 slides), (3) shorten takeaways — do not fight a demo >~2 min.
4. Failover: do not set CoreDNS `weight: 0`; trust `make failover`’s safe path.

---

## Teardown

```bash
make ui-down   # if UI was started
make down      # demo sites only — never kind-cluster
```

---

## Clip index (outside git — filenames only)

Media root: `/home/fmeneses/Videos/kcd-ba-demo-backup/`

| Clip ID | Capture | Priority | Suggested basename |
|---------|---------|----------|--------------------|
| `01-skupper` | CLI | High | `kcd-ba-01-skupper.*` |
| `02-mesh` | CLI | High | `kcd-ba-02-mesh.*` |
| `03-ratelimit-429` | CLI (+ optional browser) | Must | `kcd-ba-03-ratelimit-429.*` |
| `04-failover` | CLI | Must | `kcd-ba-04-failover.*` |
| `05-ui-a` | Playwright | Optional | `kcd-ba-05-ui-a.*` |
| `06-ui-b` | Playwright | Optional | `kcd-ba-06-ui-b.*` |
| `07-ui-c` | Playwright | Optional | `kcd-ba-07-ui-c.*` |

Extensions are typically `.cast` / `.mp4` / `.webm` / `.gif` after export — **never commit them**.
