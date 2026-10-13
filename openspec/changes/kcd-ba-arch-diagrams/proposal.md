# Proposal: KCD BA Architecture Diagrams

## Intent

Ship two ChatGPT image-generation architecture diagrams as **additional** KCD Buenos Aires 2026 talk art: a production-shaped **Azure AKS + Amazon EKS + external edge** picture with official-looking product logos, and a laptop **solution-in-a-nutshell** picture with stack logos. Speakers need a real-world mapping that the 12-slide community topology (slide 5) does not provide, without rewriting the demo or replacing that slide.

Grounding: `openspec/changes/kcd-ba-arch-diagrams/exploration.md` (Approach 1). Locked product decisions: second cloud is **Amazon EKS** (WKS = EKS); diagrams are **aparte** and do **not** replace archived talk-deck slide 5.

## Scope

### In Scope

- Two English ChatGPT / DALL·E 16:9 prompts (real-world, then laptop nutshell) plus shared style constraints from exploration
- Site mapping caption/speaker notes: `kind-west` → AKS hub; `kind-east` → Amazon EKS; `podman-edge` → edge/legacy **outside** both clouds; never map `kind-cluster`
- Talk-packaging delta: two **extra** slides (appendix / speaker-owned deck pages) that leave the locked 12-slide plan and slide 5 topology intact
- Optional conductor/script pointer that extra diagrams are visual-only (no new Make cues)
- Binary policy: generate for rehearsal; **do not commit** PNG/PPTX/Keynote

### Out of Scope

- Replacing or rewriting archived slide 5 Gemini prompt / topology slide
- Changing the 12 primary-slide budget, owners, timing blocks, or live Make path
- Demo stack, manifests, Make targets, cluster allowlist, CLIs, or demo-stack specs (`north-south-kuadrant`, `east-west-linkerd`, `skupper-van`, `failover-demo`, `kind-podman-lifecycle`, `talk-ui-surface`)
- Committing generated images, licensed brand SVGs, or a third public cloud (GKE)
- Resolving CNCF/KCD community branding for published decks beyond documenting the tension and fallback

## Capabilities

### New Capabilities

None

### Modified Capabilities

- `kcd-talk-deck`: Keep exactly 12 **primary** slides and slide 5 as the community topology (west / east / podman-edge, logo-light Gemini). **ADD** two extra architecture-diagram pages (real-world AKS+EKS+edge; laptop nutshell with stack logos) as appendix / speaker-owned art, with English ChatGPT image prompts, EKS as the second cloud, and the same no-PPTX/PNG-in-git policy. Demo Make path MUST stay unchanged.

## Approach

Follow exploration **Approach 1**: a pair of English 16:9 ChatGPT image prompts with a shared style block and hard “do not invent extra clouds/clusters” constraints.

1. **Prompt 1 — Real-world solution.** Two clouds only: Microsoft Azure / **AKS** (primary hub) and AWS / **Amazon EKS** (secondary / failover; caption “WKS shown as EKS”). Edge/legacy site **outside** both cloud boxes. Skupper VAN across AKS ↔ EKS ↔ edge (selected exposure: voting AKS↔EKS; legacy HTTP from edge). Linkerd **in-cluster only**. Client → AKS Envoy Gateway with RateLimit **HTTP 429**. DNS HA / failover to EKS ingress (not Route53 as laptop truth). Omit Kind, Podman, cloud-provider-kind, MetalLB, GKE, `kind-cluster`.
2. **Prompt 2 — Solution in a nutshell.** Sites labeled exactly `kind-west`, `kind-east`, `podman-edge`. Logos for Kind, Podman, Envoy Gateway, Kuadrant, Linkerd, Skupper, CoreDNS, emojivoto / legacy-emoji, cloud-provider-kind (`:8080` / `:8081`). No Azure/AWS/AKS/EKS/GKE/`kind-cluster`.
3. **Packaging.** Keep archived Gemini slide 5 as the ~2 min topology visual for the 12-slide clock. Extra diagrams MAY be shown as appendix, overflow, or speaker-owned pages (recommend real-world first, nutshell second if both are used). Do not expand the primary 12 or steal slide 5’s slot. Conductor still points slide 5 at “diagrama topo”; extra art is visual-only.
4. **Logo policy.** Lookalikes are for rehearsal. Speakers decide whether logo-heavy art ships in a community deck; fallback is text-labeled boxes. Generated binaries stay **outside git**, same as talk-deck PPTX/video.

Rejected here (already decided in explore): combined two-panel prompt; Mermaid as primary (keep as topology-fidelity fallback); logo-free Gemini reuse as the deliverable.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `openspec/changes/kcd-ba-arch-diagrams/` | New | Proposal, later spec delta / design / prompts copy |
| `openspec/specs/kcd-talk-deck/spec.md` | Modified (delta) | Extra slides MAY exist outside the 12; slide 5 mapping unchanged; ChatGPT prompts for extra art |
| `openspec/changes/archive/2026-09-28-kcd-ba-talk-deck/` | Read-only | Slide 5 Gemini + scripts remain source of the primary topology slide |
| `openspec/changes/kcd-ba-demo-backup/talk-conductor.md` | Optional pointer | Slide 5 still topo; extra diagrams not a Make cue |
| `README.md`, `demo/VERSIONS.md`, demo specs | None (read-only) | Grounding only |
| `demo/` manifests, Make, CLIs | **None** | No cluster, CLI, or demo-script changes |
| Kind sites `kind-west` / `kind-east` / `podman-edge` / `kind-cluster` | **None** | Diagrams only; do not operate or mutate clusters |
| Out-of-git PPTX/PNG | Speaker local | Do not commit |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Trademark / KCD community tension vs archived no-vendor-logo Gemini policy | Med | Extra slides only; binaries out of git; speakers confirm branding; fallback to generic marks |
| Image-gen topology drift (third cloud, edge inside Azure, mesh across clouds) | Med | Pair of constrained prompts; post-check mapping table; regenerate one prompt |
| Lookalike logos ≠ licensed assets | Med | Rehearsal only; do not use as printed sponsor art without license |
| Two extra diagrams overflow the ~2 min topo slot | Med | Do not replace slide 5; use as appendix or one live + one backup |
| WKS labeled EKS on-slide if a later talk renaming is needed | Low | Locked EKS for this change; only the real-world cloud box would change later |

## Rollback Plan

Talk-art only. Revert or delete `openspec/changes/kcd-ba-arch-diagrams/` artifacts (and the `kcd-talk-deck` delta if applied). Archived `2026-09-28-kcd-ba-talk-deck` stays the 12-slide source of truth, including slide 5. No cluster teardown, no CLI uninstall, no Make/demo rollback. Discard local PNG/PPTX; nothing in git to un-binary. Stage fallback: show only community slide 5.

## Dependencies

- Exploration prompts and mapping in `openspec/changes/kcd-ba-arch-diagrams/exploration.md`
- Existing `kcd-talk-deck` capability (12-slide plan, hybrid ES/EN, English image prompts, binary policy)
- ChatGPT Images / DALL·E (or equivalent) on the speaker machine — **not** in-repo
- Speakers A/B ownership from archived talk-deck (B owns topology; extra art is speaker-owned)

## Success Criteria

- [ ] Two extra diagram slides specified as **aparte** from primary slides 1–12; archived slide 5 topology unchanged
- [ ] Real-world diagram labels **Amazon EKS** as the second cloud and an edge site outside Azure and AWS
- [ ] Laptop nutshell uses `kind-west` / `kind-east` / `podman-edge` only (no `kind-cluster`, no AKS/EKS on that slide)
- [ ] English ChatGPT prompts grounded in exploration; no demo Make/cluster/CLI changes
- [ ] No PNG/PPTX committed; rollback is delete talk-art change artifacts
- [ ] `kcd-talk-deck` delta covers extra slides without weakening the 12-slide budget or live Make cues
