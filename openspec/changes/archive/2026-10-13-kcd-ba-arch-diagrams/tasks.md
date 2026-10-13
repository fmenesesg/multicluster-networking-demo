# Tasks: KCD BA Architecture Diagrams

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~120–220 (docs only: prompts + mapping + optional conductor pointers; explore/proposal/spec/design already present) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single docs PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: Low

User locked: second cloud = **Amazon EKS**; diagrams **aparte** from primary slide 5 / 12-slide budget. **No push without explicit approval.** Speakers may later decide logo-heavy extras for public deck vs rehearsal-only (not blocking apply).

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Materialize prompts + mapping + optional conductor pointers; verify extras stay outside primary 12 | Single docs PR (or local-only) | `test -f openspec/changes/kcd-ba-arch-diagrams/chatgpt-prompts.md && test -f openspec/changes/kcd-ba-arch-diagrams/mapping.md && rg -n 'kind-west\|Amazon EKS\|aparte\|slide 5' openspec/changes/kcd-ba-arch-diagrams/` | N/A — ChatGPT image gen is speaker-local; no Make/demo harness | Revert change-folder docs; discard generated PNG/PPTX outside git |

## Phase 1: Materialize prompt and mapping artifacts

- [x] 1.1 Create `openspec/changes/kcd-ba-arch-diagrams/chatgpt-prompts.md` with English shared style block plus Prompt 1 (real-world AKS + Amazon EKS + edge outside both clouds) and Prompt 2 (nutshell `kind-west` / `kind-east` / `podman-edge`) copied from `exploration.md` ready-to-paste section; do not replace archived Gemini slide 5 prompts
- [x] 1.2 Create `openspec/changes/kcd-ba-arch-diagrams/mapping.md` with demo↔real-world site table (`kind-west`→AKS, `kind-east`→EKS, `podman-edge`→edge outside clouds, never `kind-cluster`) and plane notes (Linkerd in-cluster; Skupper spans sites; DNS HA caption; omit cloud-provider-kind from real-world picture)
- [x] 1.3 In both new files, state binary policy: generate for rehearsal; **MUST NOT** commit PNG/PPTX/Keynote; lookalike logos are rehearsal marks; text-label fallback if branding objects

## Phase 2: Optional conductor / stage pointers

- [x] 2.1 Optional: add a short pointer in `openspec/changes/kcd-ba-demo-backup/talk-conductor.md` that extra architecture diagrams live under `kcd-ba-arch-diagrams/` as appendix/speaker-owned art; slide 5 remains community topology; no new Make cue
- [x] 2.2 Optional: add a matching one-liner in `openspec/changes/kcd-ba-demo-backup/stage-commands.md` (visual-only extras; skip on overrun at or before Option-C)

## Phase 3: Offline verify + delivery gate

- [x] 3.1 Offline check vs `specs/kcd-talk-deck/spec.md` ADDED scenarios: extras outside primary 12; Prompt 1 has AKS+EKS+external edge and forbids Kind/Podman/`kind-cluster`/third cloud; Prompt 2 has only demo site names and forbids Azure/AWS/AKS/EKS; no `demo/**` or Make target changes
  - Result: PASS — see verification notes below
- [x] 3.2 Confirm `git status` shows no image binaries under the worktree; generated art (if any) stays outside git
  - Result: PASS — text-only under `openspec/changes/`; no PNG/PPTX staged
- [x] 3.3 Package as one docs work unit on a feature branch for a **single PR** (size-exception) **or keep local-only**; **do not `git push` or open a remote PR without explicit user approval**
  - Branch `docs/kcd-ba-arch-diagrams`; user approved commit + push + PR

## Verification notes (apply)

```text
PASS: chatgpt-prompts.md + mapping.md present
PASS: Prompt 1 contains Azure AKS, Amazon EKS, edge outside, HTTP 429; forbids Kind/Podman/kind-cluster/GKE
PASS: Prompt 2 contains kind-west/kind-east/podman-edge; forbids Azure/AWS/AKS/EKS
PASS: extras documented as aparte from slide 5; no Make cue in conductor/stage pointers
PASS: git status — no image binaries; demo/** and Makefile untouched
```
