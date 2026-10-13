# ChatGPT prompts: KCD BA architecture diagrams

English **16:9** image-generation prompts for **two extra** talk pages (appendix / speaker-owned).  
They do **not** replace archived community topology slide 5 (`openspec/changes/archive/2026-09-28-kcd-ba-talk-deck/gemini-prompts.md`).

Grounding: `exploration.md`, `design.md`, delta `specs/kcd-talk-deck/spec.md`.  
Site mapping: [`mapping.md`](./mapping.md).

## Binary and logo policy

- Generate images for rehearsal on the speaker machine.
- **MUST NOT** commit PNG, WebP, PPTX, or Keynote binaries to this git repo.
- Lookalike product logos are **rehearsal marks**, not licensed brand assets.
- Fallback if branding objects: text-labeled boxes / Mermaid redraw.
- On overrun, skip these extras at or before Option-C; keep primary slide 5.

## How to use

1. Paste **Shared style** once in the ChatGPT (Images) chat.
2. Generate **one image per prompt** (Prompt 1, then Prompt 2).
3. Post-check labels against [`mapping.md`](./mapping.md); regenerate only the failing prompt.
4. Place accepted images on speaker-owned appendix pages outside git.

---

## Shared style

Widescreen 16:9 architecture diagram for a Kubernetes community conference (KCD Argentina). Clean infographic, high-contrast labels, deep teal + warm sand + charcoal, generous margins, readable 10+ word labels, no photorealistic people, no unreadably tiny text, no extra mystery clouds or extra Kubernetes clusters, no sci-fi cityscapes.

---

## Prompt 1 — Real-world solution

Create a widescreen 16:9 professional architecture diagram titled **“Real-world solution”**.

Show TWO cloud regions as Kubernetes clusters with official-looking product logos:

LEFT: **Microsoft Azure** logo and **Azure Kubernetes Service (AKS)** cluster box labeled “Primary / hub”. Inside AKS, clearly labeled components with recognizable logos or official-looking marks: **Envoy Gateway** (north-south ingress), **Kuadrant** (RateLimit / Gateway API policy), **Linkerd** (east-west mesh inside this cluster only), **CoreDNS** (DNS primary for hostname emojivoto.demo.local as a caption, not a public SaaS DNS), application services **web**, **voting**, **emoji**.

RIGHT: **Amazon Web Services** logo and **Amazon EKS** cluster box labeled “Secondary / failover (WKS shown as EKS)”. Inside EKS: **Envoy Gateway**, **Kuadrant**, **Linkerd** (in-cluster only), **voting** replica, **CoreDNS** secondary. Do **not** invent a third public cloud. **WKS means Amazon EKS / AWS Kubernetes** in this picture.

BOTTOM-CENTER, **outside both cloud boxes**, not inside Azure or AWS: an **edge / legacy site** — a factory or on-prem server icon (not a Kubernetes control plane in a cloud). Label it **“Edge service (outside both clouds)”** with a small HTTP/legacy app mark. This is **not** a cluster in Azure or AWS.

Connect the three sites with a **Skupper** virtual application network ribbon (official-looking Skupper mark): AKS hub ↔ EKS spoke ↔ edge service. Label selected exposure only: **voting** AKS↔EKS; **legacy HTTP** from the edge.

Show a **Client** browser at top-left hitting AKS Envoy Gateway (RateLimit callout “HTTP 429”). Show a **failover** dashed arrow: if AKS ingress is unhealthy, DNS/HA prefers EKS gateway (label “DNS HA / failover”, not Route53 as the laptop truth).

Must include: Azure, AKS, AWS, EKS, Envoy Gateway, Kuadrant, Linkerd, Skupper, CoreDNS logos/marks as hero identifiers. Must **not** include: Kind, Podman, cloud-provider-kind, MetalLB, GKE, a third cloud, `kind-cluster`, VPN-as-the-story, full mesh spanning clouds (Linkerd stays inside each cluster; Skupper spans sites).

---

## Prompt 2 — Solution in a nutshell (local demo)

Create a widescreen 16:9 architecture diagram titled **“Solution in a nutshell — local demo”**.

Three sites only, labeled exactly:

1. Top-left Kubernetes hex **kind-west** (hub) with **Kind** logo.
2. Top-right Kubernetes hex **kind-east** (secondary) with **Kind** logo.
3. Bottom **podman-edge** as a **Podman** container/site (not Kind), tiny service **legacy-emoji**.

Inside both Kind sites: **Envoy Gateway**, **Kuadrant**, **Linkerd**, **CoreDNS**. kind-west also has full **emojivoto** (web, voting, emoji). kind-east has **voting** replica. Skip-inject story: mesh on emojivoto, not on gateway/Skupper control planes (optional small “skip-inject” note, do not clutter).

**Skupper** curves link all three sites (VAN). **cloud-provider-kind** as a small host LoadBalancer mark feeding west **:8080** and east **:8081** (not MetalLB). Client → west Gateway → meshed web → voting → emoji; Skupper to east voting and to podman-edge legacy-emoji. CoreDNS arrow west primary → east secondary.

Use official-looking logos for: **Kind**, **Podman**, **Envoy Gateway**, **Kuadrant**, **Linkerd**, **Skupper**, **CoreDNS**, **emojivoto** / **legacy-emoji**, **cloud-provider-kind**. Do **not** show Azure, AWS, AKS, EKS, GKE, or `kind-cluster`. Do not add Istio, MetalLB, Grafana, Kiali, or Kubernetes Dashboard.
