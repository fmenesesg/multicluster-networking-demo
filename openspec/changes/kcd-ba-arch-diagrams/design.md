# Design: KCD BA Architecture Diagrams

## Technical Approach

Add **two extra** ChatGPT image-generation architecture diagrams as talk packaging under `openspec/changes/kcd-ba-arch-diagrams/`, without redesigning the demo stack or rewriting the locked 12-slide plan. Capability delta: `kcd-talk-deck` (ADDED-only requirements in `specs/kcd-talk-deck/spec.md`).

Locked decisions: second cloud is **Amazon EKS** (WKS = EKS); diagrams are **aparte** from primary slide 5; PNG/PPTX stay outside git.

## Architecture — Talk Packaging

```text
IN GIT (openspec/changes/kcd-ba-arch-diagrams/)
  exploration.md          ← Approach 1 + ready-to-paste prompts + mapping
  proposal.md, design.md, tasks.md (tasks next)
  specs/kcd-talk-deck/spec.md   ← ADDED extras (primary 12 unchanged)
  chatgpt-prompts.md      ← EN 16:9 prompts (copy from explore; apply)
  mapping.md (thin)       ← demo ↔ AKS/EKS/edge caption notes
  OPTIONAL pointer in talk-conductor / stage-commands (visual-only)

OUTSIDE GIT
  Generated PNG/WebP from ChatGPT; speaker-owned PPTX/Keynote pages;
  licensed brand SVGs if speakers later replace lookalikes

NEVER
  Replace archived gemini-prompts.md slide 5
  Expand primary 12-slide budget or steal 5–9 topology clock
  Commit binaries; mutate demo/** Make/clusters
```

Primary topology for the timed talk remains archived community slide 5 (logo-light Gemini). Extras are appendix / overflow / speaker-owned.

## Site Mapping (demo ↔ real-world)

| Demo | Real-world | Planes |
|------|------------|--------|
| `kind-west` | Azure **AKS** hub | EG+Kuadrant N-S, Linkerd E-W in-cluster, Skupper hub, DNS primary |
| `kind-east` | Amazon **EKS** secondary | Same N-S/E-W pattern, voting replica, DNS secondary |
| `podman-edge` | Edge/legacy **outside** both clouds | Skupper-connected HTTP (legacy), not a cloud K8s cluster |
| `kind-cluster` | *(none)* | Never map or draw |

Linkerd stays **inside** each cluster. Skupper spans AKS ↔ EKS ↔ edge. Laptop CoreDNS HA is labeled as DNS HA/failover on the real-world slide (not Route53 as laptop truth).

## Generation and Acceptance Flow

```mermaid
sequenceDiagram
  participant Sp as Speaker
  participant CG as ChatGPT Images
  participant Map as Mapping table
  participant Deck as Speaker deck (out of git)

  Sp->>CG: Shared style + Prompt 1 (real-world)
  CG-->>Sp: Image A
  Sp->>Map: Post-check labels (AKS/EKS/edge outside)
  alt Drift
    Sp->>CG: Regenerate Prompt 1 only
  else OK
    Sp->>Deck: Extra page Real-world (appendix)
  end
  Sp->>CG: Prompt 2 (nutshell)
  CG-->>Sp: Image B
  Sp->>Map: Post-check kind-west/east/podman-edge only
  alt Drift
    Sp->>CG: Regenerate Prompt 2 only
  else OK
    Sp->>Deck: Extra page Nutshell (appendix)
  end
  Note over Sp,Deck: Primary slide 5 unchanged; skip extras on overrun before Option-C
```

## Architecture Decisions

| Decision | Options | Tradeoff | Choice |
|----------|---------|----------|--------|
| Prompt channel | One two-panel vs pair | Density vs clarity | **Pair of English 16:9 ChatGPT prompts** |
| Second cloud | EKS vs other WKS | Repo unnamed | **Amazon EKS** (locked) |
| Placement | Replace slide 5 vs aparte | Clock vs story | **Aparte** (appendix / speaker-owned) |
| Logos | Gemini no-logo vs lookalikes | Community vs request | **Lookalikes on extras only**; slide 5 stays logo-light |
| Binaries | Commit vs local | Repro vs IP/bloat | **Outside git** |
| Topology fidelity | Image-gen only vs Mermaid | Look vs accuracy | **Image-gen primary**; Mermaid/text boxes fallback |
| Overrun | Cut extras vs cut Option-C | Spec | **Skip extras at or before Option-C** |
| Conductor | New Make cue vs visual-only | Stage risk | **Visual-only**; slide 5 still “diagrama topo” |

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `openspec/changes/kcd-ba-arch-diagrams/design.md` | Create | This design |
| `openspec/changes/kcd-ba-arch-diagrams/specs/kcd-talk-deck/spec.md` | Exists | ADDED delta (sdd-spec) |
| `openspec/changes/kcd-ba-arch-diagrams/chatgpt-prompts.md` | Create (apply) | EN prompts + shared style from explore |
| `openspec/changes/kcd-ba-arch-diagrams/mapping.md` | Create (apply) | Thin demo↔real-world + plane notes |
| `openspec/changes/kcd-ba-demo-backup/talk-conductor.md` | Optional pointer | Extra diagrams visual-only; slide 5 unchanged |
| `openspec/changes/kcd-ba-demo-backup/stage-commands.md` | Optional pointer | No new Make cues |
| `openspec/changes/archive/2026-09-28-kcd-ba-talk-deck/gemini-prompts.md` | Read-only | Primary slide 5 source of truth |
| `demo/**`, Make, CLIs | **None** | Cue-only talk art |

## Interfaces / Contracts

- **Prompts:** English, 16:9; shared style forbids extra clouds/clusters.
- **Prompt 1 must-have marks:** Azure, AKS, AWS, EKS, Envoy Gateway, Kuadrant, Linkerd, Skupper, CoreDNS; edge outside clouds; HTTP 429 callout; DNS HA → EKS.
- **Prompt 1 must-not:** Kind, Podman, cloud-provider-kind, MetalLB, GKE, `kind-cluster`, cross-cloud Linkerd.
- **Prompt 2 must-have sites:** `kind-west`, `kind-east`, `podman-edge` + stack logos incl. cloud-provider-kind `:8080`/`:8081`.
- **Prompt 2 must-not:** Azure/AWS/AKS/EKS/GKE/`kind-cluster`/Istio/MetalLB.
- **Make path:** unchanged (`up`/`smoke`/`demo-*`/`failover`/`ui`).

## Testing Strategy

| Layer | What | Approach |
|-------|------|----------|
| Offline | Completeness | Two prompts present; mapping table; extras outside primary 12; slide 5 untouched |
| Acceptance | Topology check | Human post-check against mapping; reject drift |
| Negative | Overrun / branding | Extras skippable; text-label fallback; no binaries in git |

## Threat Matrix

N/A for stack — talk art only. Branding/trademark residual risk documented; lookalikes are rehearsal marks, not licensed assets.

## Migration / Rollout

No data migration. Delivery **ask-on-risk**. Rollback = delete/revert this change folder (+ optional conductor pointer); stage fallback = community slide 5 only.

## Apply Implications (sdd-tasks)

1. Materialize `chatgpt-prompts.md` from exploration ready-to-paste block (shared style + Prompt 1 + Prompt 2).
2. Materialize thin `mapping.md` (site + plane tables).
3. Optional one-line pointers in `talk-conductor.md` / `stage-commands.md` (extras visual-only; no Make cues).
4. Do **not** edit archived Gemini slide 5 or demo scripts.
5. Forecast small docs PR (well under 400 authored lines); delivery ask-on-risk; single PR fine unless chained later.

## Open Questions

- [x] Second cloud = Amazon EKS (user locked).
- [x] Placement = aparte from slide 5 / primary 12 (user locked).
- [x] Spec ADDED-only on `kcd-talk-deck` (no MODIFIED twelve-slide block).
- [ ] Speakers confirm whether logo-heavy extras ship in the public community deck vs rehearsal-only (fallback: text labels) — not blocking design/tasks; decide before published deck.
