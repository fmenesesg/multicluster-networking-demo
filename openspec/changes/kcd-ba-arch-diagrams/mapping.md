# Mapping: demo sites ↔ real-world diagram

Caption / speaker notes for the two extra architecture pages.  
Prompts: [`chatgpt-prompts.md`](./chatgpt-prompts.md).  
Primary timed topology remains archived slide 5 (community, logo-light) — these extras are **aparte**.

## Sites

| Demo site | Real-world site | Notes |
|-----------|-----------------|-------|
| `kind-west` | **Azure AKS** (primary / hub) | EG + Kuadrant N-S, Linkerd E-W, full app, Skupper hub, DNS **primary** |
| `kind-east` | **Amazon EKS** (secondary) — WKS shown as EKS | Same N-S/E-W pattern, voting replica, Skupper spoke, DNS **secondary** |
| `podman-edge` | **Edge / legacy outside both clouds** | Not AKS, not EKS; Skupper-connected legacy HTTP (like `legacy-emoji`) |
| `kind-cluster` | *(none)* | Never map; unrelated local Kind |

## Planes

| Demo plane | Real-world equivalent |
|------------|----------------------|
| Envoy Gateway + Kuadrant RateLimit | North-south API gateway + policy (rate limit → **HTTP 429**) at cloud ingress |
| Linkerd | In-cluster east-west mesh (mTLS) **inside** AKS and **inside** EKS — not across clouds |
| Skupper VAN | Application network linking AKS ↔ EKS ↔ edge without a third cloud cluster |
| CoreDNS + DNSPolicy west→east | DNS HA: primary AKS ingress, failover to EKS (laptop truth is CoreDNS, not Route53/Azure DNS) |
| emojivoto | Multi-service app (web / voting / emoji) |
| `legacy-emoji` | Legacy / edge HTTP backend |
| `cloud-provider-kind` | **Demo-only** LB stand-in — show on nutshell (`:8080` / `:8081`); **omit** from real-world picture |

## Post-generation checklist

**Prompt 1 (real-world)** — reject if any fail:

- [ ] Exactly two public clouds: Azure AKS + Amazon EKS
- [ ] Edge site drawn **outside** both cloud boxes
- [ ] Skupper spans three sites; Linkerd only in-cluster
- [ ] No Kind, Podman, cloud-provider-kind, MetalLB, GKE, `kind-cluster`

**Prompt 2 (nutshell)** — reject if any fail:

- [ ] Sites labeled exactly `kind-west`, `kind-east`, `podman-edge`
- [ ] No Azure, AWS, AKS, EKS, GKE, `kind-cluster`
- [ ] Stack marks include Kind, Podman, EG, Kuadrant, Linkerd, Skupper, CoreDNS, emojivoto/legacy-emoji, cloud-provider-kind

## Binary policy

Generated PNG/PPTX stay **outside git**. Lookalike logos = rehearsal only.
