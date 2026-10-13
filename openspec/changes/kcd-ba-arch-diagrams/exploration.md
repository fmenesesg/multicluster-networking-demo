## Exploration: kcd-ba-arch-diagrams

Two ChatGPT image-generation prompts for KCD Buenos Aires 2026 talk slides: (1) production-shaped AKS + WKS architecture with official-looking cloud/product logos; (2) the laptop demo topology with stack-piece logos. Grounded in repo architecture. **No code or stack changes.**

### Current State

The demo is a 30-minute laptop stack: **Envoy Gateway + Kuadrant (N-S)**, **Linkerd (E-W)**, **Skupper VAN (inter-site)**, **Kuadrant CoreDNS (DNS HA)**, three sites **`kind-west`**, **`kind-east`**, **`podman-edge`**. Live path: RateLimit **429**, meshed emojivoto, Kind↔Podman Skupper, CoreDNS failover. Optional UIs (`make ui` A→B→C) are off the critical path.

**Local topology (source of truth: `README.md`, `demo/VERSIONS.md`, specs):**

```
Client → EG (west) → web (meshed) → voting → emoji
              │            │            │
         RateLimit      Linkerd      Skupper
              │                         ├─ voting (east)
         CoreDNS west→east              └─ legacy-emoji (podman-edge)
```

| Site | Role | Runs |
|------|------|------|
| `kind-west` | Hub | EG, Kuadrant, Linkerd, full emojivoto (web/voting/emoji), Skupper hub (`linkAccess`), CoreDNS DNSPolicy **primary** |
| `kind-east` | Secondary / failover peer | EG, Kuadrant, Linkerd, **voting replica**, Skupper spoke, CoreDNS **secondary** |
| `podman-edge` | Outside Kubernetes | Skupper Podman site + tiny `legacy-emoji` HTTP JSON (host `:18080`) — **not** a third Kind cluster |
| `kind-cluster` | Unrelated | **Never** show as a demo site |

Planes (do not collapse in diagrams):

- **N-S:** client → Envoy Gateway; Kuadrant RateLimitPolicy (Limitador); hostname `emojivoto.demo.local`.
- **E-W:** Linkerd on **Kind sites only**; skip-inject on EG/Kuadrant/Skupper namespaces; inject `emojivoto`.
- **VAN:** Skupper 2.2.1 three-site; selected exposure only (`voting` west↔east; `legacy-emoji` from Podman).
- **HA:** CoreDNS west primary / east secondary; failover hurts west EG dataplane + deletes west DNSPolicy (not `weight: 0`).
- **Local LB:** `cloud-provider-kind` (not MetalLB); west `:8080`, east `:8081`.

Talk packaging already has **English** Gemini image prompts in `openspec/changes/archive/2026-09-28-kcd-ba-talk-deck/gemini-prompts.md`. Those prompts **explicitly forbid commercial vendor logos** (community / CNCF-adjacent generic marks only). Slide 5 is the existing topology diagram (west / east / podman-edge, no vendor hero branding).

**WKS assumption (repo does not name WKS, AKS, or EKS as sites).** The only AWS mention in archived explore is optional Route53 as a *rejected* laptop DNS path. Treat **WKS as Amazon EKS (AWS Kubernetes)** for the real-world diagram unless the speakers later name another second cloud. Record that mapping in every real-world prompt and on-slide caption.

**Edge is not a cloud cluster.** Production edge = a **service/site outside Azure and AWS** (on-prem / factory / legacy VM), matching `podman-edge` + `legacy-emoji`. Do not draw a third AKS/EKS/GKE box.

### Affected Areas

- `openspec/changes/kcd-ba-arch-diagrams/exploration.md` — this artifact (prompts + mapping).
- `openspec/changes/archive/2026-09-28-kcd-ba-talk-deck/gemini-prompts.md` — **tension**: prior policy avoided vendor logos; this request wants logos (proposal must choose: extra slides vs replace slide 5).
- `openspec/changes/archive/2026-09-28-kcd-ba-talk-deck/{scripts.md,design.md}` — slide 5 topology (~2 min, speaker B); 12-slide budget.
- `openspec/changes/kcd-ba-demo-backup/{talk-conductor.md,stage-commands.md}` — conductor still points slide 5 at “diagrama topo”; new art is visual-only.
- `README.md`, `demo/VERSIONS.md`, specs `north-south-kuadrant`, `east-west-linkerd`, `skupper-van`, `failover-demo`, `kind-podman-lifecycle` — **read-only** grounding; do not change stack.
- Out-of-git PPTX/Keynote (same as talk-deck: **do not commit** generated PNGs/PPTX).

This change does **not** affect `demo/` manifests, Make targets, or cluster allowlist.

### Approaches

1. **Pair of English ChatGPT image prompts (recommended)** — Two separate 16:9 image-gen prompts: “Real-world solution” then “Solution in a nutshell”. Shared style block; no mixing of Kind names into the production diagram.
   - Pros: Matches the user request (two diagrams); ChatGPT/DALL·E handles logos better than Mermaid; English matches existing Gemini prompt language; lower prompt confusion than one mega-prompt; speaker can regenerate one slide without the other.
   - Cons: Image models hallucinate topology; logos are **lookalikes**, not licensed assets; trademark/KCD-community tension vs archived Gemini policy; two generations to iterate.
   - Effort: Low (prompts only)

2. **One combined prompt producing a two-panel slide** — Single image: left production, right laptop, with a mapping legend.
   - Pros: One generation; mapping is visible on one slide (good for 2-minute topology).
   - Cons: High visual density; logos unreadable at 16:9; models merge AKS into Kind boxes; worse iteration (cannot fix one panel).
   - Effort: Low — rejected for quality

3. **Mermaid / draw.io / Excalidraw in-repo** — Structured diagrams; logos as attached SVG files the speaker supplies.
   - Pros: Accurate topology; editable; no trademarked pixels in git if using generic icons; reproducible.
   - Cons: Does **not** satisfy “official-looking logos” unless speakers drop licensed SVGs; extra tooling; not ChatGPT as requested.
   - Effort: Medium — keep as fallback if image-gen topology is wrong

4. **Reuse / extend archived Gemini prompts (logo-free)** — Stay on community iconography from `gemini-prompts.md` slide 5.
   - Pros: Already aligned with KCD community aesthetic and “no proprietary packaging”.
   - Cons: Directly contradicts this user request for logos.
   - Effort: Low — reject for this change; keep as legal-safe alternate

#### Prompt-channel comparison

| Channel | Logos | Topology fidelity | Talk fit |
|---------|-------|-------------------|----------|
| ChatGPT Images (pair, English) | Strong lookalike | Medium (must constrain labels) | Best for requested look |
| One two-panel prompt | Weak (muddy) | Low | Poor |
| Mermaid / draw.io | Only if user supplies marks | High | Fallback / speaker rebuild |
| Archived Gemini (no logos) | Forbidden by those prompts | High if labels are text | Safer for community deck |

### Recommendation

**Use Approach 1: two English ChatGPT image-generation prompts**, 16:9, with a shared style + hard “do not invent extra clouds/clusters” constraints.

Why: the user asked for ChatGPT and two distinct diagrams (production vs laptop). A pair keeps density readable and matches talk-deck prompt language (English for image gen; Spanish titles can be added on the slide later). Do **not** bake Kind names into the real-world picture; use the mapping table as a caption or speaker note.

**WKS → EKS:** label the second cloud **Amazon EKS** on the diagram, with a footnote “WKS shown as EKS (AWS Kubernetes) — not named in this repo.” If WKS later means another product, only the real-world prompt’s cloud box changes.

**Logo policy for proposal:** generate for rehearsal; **do not commit** binary slides; speakers must decide whether logo-heavy art stays in a KCD community deck (see Risks). Fallback: text-labeled boxes if legal/community review objects.

Paste the prompts below into ChatGPT (Images / DALL·E). Generate **one image per prompt**. After generation, check labels against the mapping table; regenerate the failing prompt only.

---

### Site mapping (demo ↔ real-world)

| Demo site | Real-world site | Notes |
|-----------|-----------------|-------|
| `kind-west` | **Azure AKS** (primary / hub) | EG + Kuadrant N-S, Linkerd E-W, full app, Skupper hub, DNS **primary** |
| `kind-east` | **Amazon EKS** (secondary) — **WKS treated as EKS** | Same N-S/E-W pattern, voting replica, Skupper spoke, DNS **secondary** |
| `podman-edge` | **Edge / legacy site outside both clouds** | Not AKS, not EKS; Skupper-connected service (legacy HTTP), like `legacy-emoji` |
| `kind-cluster` | *(none)* | Never map; unrelated local Kind |

| Demo plane | Real-world equivalent |
|------------|----------------------|
| Envoy Gateway + Kuadrant RateLimit | North-south API gateway + policy (rate limit → 429) at each cloud ingress |
| Linkerd | In-cluster east-west mesh (mTLS) **inside** AKS and **inside** EKS, not across clouds |
| Skupper VAN | Application network linking AKS ↔ EKS ↔ edge **without** requiring a third cloud cluster |
| CoreDNS + DNSPolicy west→east | DNS HA: primary AKS ingress, failover to EKS (laptop uses CoreDNS, not Route53/Azure DNS) |
| emojivoto | Multi-service app (web / voting / emoji) |
| `legacy-emoji` | Legacy/edge HTTP backend |
| `cloud-provider-kind` | **Demo-only** LoadBalancer stand-in; omit from real-world diagram (use cloud LB / ingress) |

---

### Ready-to-paste ChatGPT prompts (English)

**Shared style (prepend mentally, or paste once in the chat before Prompt 1):**

Widescreen 16:9 architecture diagram for a Kubernetes community conference (KCD Argentina). Clean infographic, high-contrast labels, deep teal + warm sand + charcoal, generous margins, readable 10+ word labels, no photorealistic people, no unreadably tiny text, no extra mystery clouds or extra Kubernetes clusters, no sci-fi cityscapes.

#### Prompt 1 — Real-world solution

Create a widescreen 16:9 professional architecture diagram titled **“Real-world solution”**.

Show TWO cloud regions as Kubernetes clusters with official-looking product logos:

LEFT: **Microsoft Azure** logo and **Azure Kubernetes Service (AKS)** cluster box labeled “Primary / hub”. Inside AKS, clearly labeled components with recognizable logos or official-looking marks: **Envoy Gateway** (north-south ingress), **Kuadrant** (RateLimit / Gateway API policy), **Linkerd** (east-west mesh inside this cluster only), **CoreDNS** (DNS primary for hostname emojivoto.demo.local as a caption, not a public SaaS DNS), application services **web**, **voting**, **emoji**.

RIGHT: **Amazon Web Services** logo and **Amazon EKS** cluster box labeled “Secondary / failover (WKS shown as EKS)”. Inside EKS: **Envoy Gateway**, **Kuadrant**, **Linkerd** (in-cluster only), **voting** replica, **CoreDNS** secondary. Do **not** invent a third public cloud. **WKS means Amazon EKS / AWS Kubernetes** in this picture.

BOTTOM-CENTER, **outside both cloud boxes**, not inside Azure or AWS: an **edge / legacy site** — a factory or on-prem server icon (not a Kubernetes control plane in a cloud). Label it **“Edge service (outside both clouds)”** with a small HTTP/legacy app mark. This is **not** a cluster in Azure or AWS.

Connect the three sites with a **Skupper** virtual application network ribbon (official-looking Skupper mark): AKS hub ↔ EKS spoke ↔ edge service. Label selected exposure only: **voting** AKS↔EKS; **legacy HTTP** from the edge.

Show a **Client** browser at top-left hitting AKS Envoy Gateway (RateLimit callout “HTTP 429”). Show a **failover** dashed arrow: if AKS ingress is unhealthy, DNS/HA prefers EKS gateway (label “DNS HA / failover”, not Route53 as the laptop truth).

Must include: Azure, AKS, AWS, EKS, Envoy Gateway, Kuadrant, Linkerd, Skupper, CoreDNS logos/marks as hero identifiers. Must **not** include: Kind, Podman, cloud-provider-kind, MetalLB, GKE, a third cloud, `kind-cluster`, VPN-as-the-story, full mesh spanning clouds (Linkerd stays inside each cluster; Skupper spans sites).

#### Prompt 2 — Solution in a nutshell (this laptop demo)

Create a widescreen 16:9 architecture diagram titled **“Solution in a nutshell — local demo”**.

Three sites only, labeled exactly:

1. Top-left Kubernetes hex **kind-west** (hub) with **Kind** logo.
2. Top-right Kubernetes hex **kind-east** (secondary) with **Kind** logo.
3. Bottom **podman-edge** as a **Podman** container/site (not Kind), tiny service **legacy-emoji**.

Inside both Kind sites: **Envoy Gateway**, **Kuadrant**, **Linkerd**, **CoreDNS**. kind-west also has full **emojivoto** (web, voting, emoji). kind-east has **voting** replica. Skip-inject story: mesh on emojivoto, not on gateway/Skupper control planes (optional small “skip-inject” note, do not clutter).

**Skupper** curves link all three sites (VAN). **cloud-provider-kind** as a small host LoadBalancer mark feeding west **:8080** and east **:8081** (not MetalLB). Client → west Gateway → meshed web → voting → emoji; Skupper to east voting and to podman-edge legacy-emoji. CoreDNS arrow west primary → east secondary.

Use official-looking logos for: **Kind**, **Podman**, **Envoy Gateway**, **Kuadrant**, **Linkerd**, **Skupper**, **CoreDNS**, **emojivoto** / **legacy-emoji**, **cloud-provider-kind**. Do **not** show Azure, AWS, AKS, EKS, GKE, or `kind-cluster`. Do not add Istio, MetalLB, Grafana, Kiali, or Kubernetes Dashboard.

---

### Risks

- **Trademark / community-deck tension:** archived `gemini-prompts.md` forbade commercial vendor logos; this request **wants** them. KCD slides can look like vendor marketing. Mitigate: keep binaries out of git; optional “lookalike OK for rehearsal, replace with generic marks for published deck”; speakers confirm CNCF/KCD branding rules.
- **WKS ambiguity:** repo never defines WKS; **EKS is an assumption**. Wrong second cloud if WKS is not AWS.
- **Image-gen topology drift:** models add GKE, put edge *inside* Azure, mesh across clouds, or rename sites. Mitigate: pair of prompts + post-check against mapping table.
- **Lookalike logos ≠ official brand assets:** not suitable for printed sponsor materials without license.
- **Slide-5 time:** two logo-heavy diagrams may overflow the ~2 min topology slot; recommend real-world first, nutshell second, or one live + one appendix.
- **No stack change:** diagrams must not imply Istio, MetalLB, cloud DNS, or a third Kind cluster.

### Ready for Proposal

**Yes.** Orchestrator should tell the user: prompts and the demo↔AKS/EKS/edge mapping live in `openspec/changes/kcd-ba-arch-diagrams/exploration.md`; **WKS is documented as EKS**; logo request **conflicts** with prior Gemini no-logo policy. Next: **sdd-propose** to decide whether these replace slide 5, become two extra slides, and whether generated images stay outside git. No demo code work.
