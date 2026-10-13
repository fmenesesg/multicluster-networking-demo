# kcd-talk-deck Specification

## Purpose

30-min dual-speaker KCD Argentina 2026 packaging for the laptop demo on `main`. MUST NOT redesign or weaken demo-stack specs.

## Requirements

### Requirement: Twelve-slide dual-speaker plan

Packaging MUST define exactly 12 primary slides with Spanish titles, owner (A/B/A+B), and timing. Speaker A MUST be Francisco Meneses (framing, N-S EG+Kuadrant, CoreDNS failover, close). Speaker B MUST be Sergio Canales (topology, Skupper, Linkerd E-W, Viz/observer). Swap MAY if documented. Sites MUST be `kind-west`/`kind-east`/`podman-edge`; MUST NOT operate `kind-cluster`. Option-C backup MAY sit outside the 12; MUST cut first on overrun.

#### Scenario: Locked 12-slide ownership

- GIVEN packaged talk artifacts
- WHEN reviewing the primary deck plan
- THEN 12 slides list ES titles, A=Francisco / B=Sergio (or documented swap), and timing

#### Scenario: kind-cluster excluded

- GIVEN agenda or live cues
- WHEN speakers reference demo sites
- THEN only west/east/podman-edge appear; `kind-cluster` MUST NOT be operated

### Requirement: Hybrid Spanish body and English tech terms

Titles and speaking body MUST be Spanish. RateLimit, failover, mesh, Gateway, N-S, E-W, ACCESS_URL, LoadBalancer, port-forward MUST stay English. Gemini prompts MUST be English. Scripts MUST prefer Make over ad-hoc YAML on stage.

#### Scenario: Hybrid wording check

- GIVEN titles and talking points
- WHEN inspecting language mix
- THEN body/titles are Spanish and listed tech terms stay English

#### Scenario: Gemini prompts English

- GIVEN prompts for slides 1–12
- WHEN reviewed
- THEN each is English and 16:9 community-oriented

### Requirement: Live demo cues and optional UI A→B→C

Live blocks MUST cue `demo-skupper` (B), `demo-mesh` (B), `demo-ratelimit`→HTTP 429 (A), `failover` (A). Pre-talk SHOULD warm `prereq-check`→`up`→`smoke`→optional `ui`. On-stage UI MUST follow `make ui` A→B→C (app → Viz `:50750` → observer `:8443`) without changing `talk-ui-surface`. On stall/lateness SHOULD skip UI; MUST NOT fight >~2 minutes.

#### Scenario: Critical-path Make cues present

- GIVEN slides 7–10 packaging
- WHEN live cues are listed
- THEN cues map to named Make targets and owners for Skupper, mesh, ratelimit→429, failover

#### Scenario: UI skip on overrun

- GIVEN clock pressure or UI stall
- WHEN continuing
- THEN UI MAY be skipped; Make critical path remains valid

### Requirement: Live cues with per-cue offline video backup

Critical-path cues (`demo-skupper`, `demo-mesh`, `demo-ratelimit`→429, `failover`) MUST be live-first. Backup media MUST cover those wow moments (and MAY cover optional UI A/B/C), MUST stay outside git (host path such as `/home/fmeneses/Videos/kcd-ba-demo-backup/`), and SHOULD be agent-recorded (CLI asciinema/`script` and/or Playwright `recordVideo`, silent). After ~2m failure/timeout speakers MUST stop, acknowledge prior smoke, play the matching clip when available, and advance (takeaways if needed).

#### Scenario: Live-first failover

- GIVEN slide 10 and warm stack
- WHEN failover is demonstrated
- THEN primary path is live `make failover`

#### Scenario: Per-cue video contingency outside git

- GIVEN a live critical-path cue flakes
- WHEN falling back within ~2 minutes
- THEN the matching outside-git clip for that cue is used; no video binary is committed

#### Scenario: Agent-recorded silent media

- GIVEN rehearsal recording of backup clips
- WHEN media is produced
- THEN capture is CLI and/or Playwright video without microphone, written outside the git worktree

### Requirement: Source and binary policy

Artifacts MUST be original outlines, Spanish scripts, English Gemini prompts, timing, ownership, repo-tied cues. MUST NOT include proprietary workshop PPTX/marketing/paths/catalog IDs. MUST NOT commit PPTX/video binaries or secrets (incl. `demo/.run/`). QR/bios MUST NOT be committed unless later requested.

#### Scenario: No proprietary or binary creep

- GIVEN a proposed talk-packaging commit
- WHEN reviewing staged files
- THEN no PPTX/video binaries, `demo/.run/` secrets, or proprietary workshop text/paths

#### Scenario: Original narrative only

- GIVEN scripts and prompts
- WHEN checking provenance
- THEN content derives from this repo’s README/`demo/` story

### Requirement: Timing budget and packaging success criteria

Packaging MUST target 30 min: 0–5 open (A→B); 5–9 topo (B); 9–16 Skupper+mesh+UI B/C (B); 16–25 429+failover+UI A (A); 25–30 close (A+B). Success MUST cover requirements above, rehearsal of 429+mesh+Skupper and failover live or video on time, and CTA `up`→`smoke`→optional `ui`→`down`. Demo-stack specs MUST remain unmodified.

#### Scenario: Timing blocks documented

- GIVEN talk packaging
- WHEN checking the 30-min plan
- THEN the five timing blocks and owners match

#### Scenario: CTA and non-interference

- GIVEN takeaways and existing demo specs
- WHEN this change is applied
- THEN CTA lists `up`→`smoke`→optional `ui`→`down`; demo-stack specs stay unchanged

### Requirement: Extra architecture-diagram pages outside the primary twelve

Talk packaging MUST keep exactly 12 primary slides. Packaging MUST add two extra architecture-diagram pages as appendix or speaker-owned deck pages, separate from primary slides 1–12. Those extra pages MUST NOT replace archived community topology slide 5. Those extra pages MUST NOT expand the 12-slide primary budget, change primary-slide owners, or steal slide 5’s slot in the 5–9 topology block. Primary slide 5 MUST remain the community, logo-light west / east / podman-edge topology visual. Extra pages MAY use official-looking product logos; primary slide 5 MUST NOT be rewritten to that logo-heavy style.

#### Scenario: Extra pages leave the primary twelve intact

- GIVEN packaged talk artifacts that include architecture-diagram extras
- WHEN reviewing the primary deck plan
- THEN exactly 12 primary slides remain listed with Spanish titles, owners, and timing
- AND two extra architecture-diagram pages exist outside that list

#### Scenario: Extra pages do not replace community slide 5

- GIVEN archived talk-deck slide 5 (community topology, Gemini, west / east / podman-edge)
- WHEN extra architecture-diagram pages are added
- THEN slide 5 still occupies the primary topology slot
- AND the extra pages are appendix, overflow, or speaker-owned pages rather than a substitute for slide 5

#### Scenario: Logo-heavy extras coexist with logo-light slide 5

- GIVEN extra pages that use official-looking product logos and primary slide 5 that uses community / generic marks
- WHEN comparing the two visual styles
- THEN extra logo-heavy art MUST NOT be used as the required primary slide 5
- AND speakers MAY keep extras as rehearsal or speaker-owned art while slide 5 stays community-oriented

### Requirement: Real-world extra diagram maps AKS, Amazon EKS, and external edge

The first extra architecture diagram MUST depict a production-shaped solution titled as a real-world picture. It MUST show exactly two public clouds: Microsoft Azure / AKS as primary hub, and AWS / Amazon EKS as secondary failover (WKS shown as EKS). It MUST show an edge / legacy site outside both cloud boxes. Skupper MUST span AKS, EKS, and the edge site. Linkerd MUST appear only as in-cluster east-west mesh inside AKS and inside EKS, not across clouds. Client traffic MUST hit AKS Envoy Gateway with a RateLimit HTTP 429 callout. DNS HA / failover MUST prefer EKS ingress when AKS ingress is unhealthy, and MUST NOT present Route53 (or equivalent public DNS SaaS) as the laptop demo’s source of truth. The diagram MUST NOT include Kind, Podman, cloud-provider-kind, MetalLB, GKE, a third public cloud, or `kind-cluster`.

#### Scenario: Happy-path real-world topology

- GIVEN the real-world extra diagram
- WHEN inspecting labeled sites
- THEN Azure AKS is the primary hub, Amazon EKS is the secondary cloud, and the edge site sits outside both clouds
- AND Skupper links the three sites with selected exposure (voting AKS↔EKS; legacy HTTP from edge)

#### Scenario: Mesh stays in-cluster and no third cloud

- GIVEN the real-world extra diagram
- WHEN inspecting connectivity planes
- THEN Linkerd is drawn only inside each Kubernetes cluster
- AND no GKE, extra mystery cloud, or extra Kubernetes cluster appears

#### Scenario: Laptop-only marks omitted from the real-world picture

- GIVEN the real-world extra diagram
- WHEN checking for demo-host artifacts
- THEN Kind, Podman, cloud-provider-kind, MetalLB, and `kind-cluster` MUST NOT appear

### Requirement: Laptop nutshell extra diagram uses demo site names only

The second extra architecture diagram MUST depict the laptop demo titled as a solution-in-a-nutshell picture. Sites MUST be labeled exactly `kind-west`, `kind-east`, and `podman-edge`. It MUST include official-looking marks for Kind, Podman, Envoy Gateway, Kuadrant, Linkerd, Skupper, CoreDNS, emojivoto / legacy-emoji, and cloud-provider-kind with west `:8080` and east `:8081`. It MUST NOT show Azure, AWS, AKS, EKS, GKE, or `kind-cluster`. It MUST NOT add Istio, MetalLB, Grafana, Kiali, or Kubernetes Dashboard as part of the story.

#### Scenario: Happy-path nutshell sites

- GIVEN the laptop nutshell extra diagram
- WHEN inspecting site labels
- THEN only `kind-west`, `kind-east`, and `podman-edge` appear as sites
- AND stack marks include Kind, Podman, Envoy Gateway, Kuadrant, Linkerd, Skupper, CoreDNS, emojivoto / legacy-emoji, and cloud-provider-kind (`:8080` / `:8081`)

#### Scenario: Cloud names and kind-cluster omitted from the nutshell

- GIVEN the laptop nutshell extra diagram
- WHEN checking forbidden labels
- THEN Azure, AWS, AKS, EKS, GKE, and `kind-cluster` MUST NOT appear

### Requirement: English ChatGPT prompts and post-generation topology check

Packaging MUST include two English 16:9 ChatGPT / DALL·E (or equivalent) image-generation prompts, one per extra diagram, sharing style constraints that forbid extra clouds and extra clusters. Gemini prompts for primary slides 1–12 MUST remain English and community-oriented; extra-diagram ChatGPT prompts MUST NOT replace those Gemini prompts. After generation, speakers MUST check labels against the demo-to-real-world mapping. If a generated image drifts, speakers MUST reject that image as talk truth and SHOULD regenerate only the failing prompt. Speakers MAY fall back to text-labeled boxes or a topology-fidelity drawing if generated art remains unusable. Lookalike logos MUST be treated as rehearsal marks, not licensed brand assets.

#### Scenario: Two English 16:9 extra-diagram prompts

- GIVEN talk-packaging prompts for the extra architecture pages
- WHEN reviewing language and aspect
- THEN each extra-diagram prompt is English and 16:9
- AND primary-slide Gemini prompts for slides 1–12 remain present and unmodified in role

#### Scenario: Image-generation topology drift is rejected

- GIVEN a generated extra diagram that invents a third cloud, places the edge inside Azure or AWS, draws Linkerd across clouds, or shows `kind-cluster`
- WHEN speakers validate the image against the mapping
- THEN that image MUST NOT be used as the talk’s topology truth
- AND speakers regenerate the failing prompt or use the text-labeled / topology-fidelity fallback

#### Scenario: Community branding fallback

- GIVEN KCD / CNCF community-deck constraints that object to vendor-hero logos
- WHEN preparing a published community deck
- THEN speakers MAY replace lookalike logos with generic or text-labeled boxes on the extra pages
- AND they MUST NOT treat lookalikes as licensed printed sponsor art

### Requirement: Demo-to-real-world mapping captions without kind-cluster

Extra-diagram packaging MUST include a caption or speaker notes mapping `kind-west` to Azure AKS hub, `kind-east` to Amazon EKS, and `podman-edge` to an edge / legacy site outside both clouds. Mapping MUST NOT assign `kind-cluster` to any real-world or demo site. Real-world captions MUST NOT present Kind site names as production cluster names. Nutshell captions MUST NOT present AKS or EKS as laptop site names.

#### Scenario: Mapping notes present

- GIVEN extra architecture-diagram pages
- WHEN reading caption or speaker notes
- THEN `kind-west` maps to AKS, `kind-east` maps to Amazon EKS, and `podman-edge` maps to edge outside both clouds

#### Scenario: kind-cluster is never mapped or shown as a demo site

- GIVEN agenda, extra diagrams, or live cues
- WHEN speakers reference sites
- THEN only west / east / podman-edge appear as demo sites
- AND `kind-cluster` MUST NOT be mapped, labeled, or operated

### Requirement: Extra diagrams are visual-only and MUST NOT change the live Make path

Extra architecture diagrams MUST be visual-only. Packaging MUST NOT add Make targets, cluster operations, CLI steps, or live-demo cues for those pages. Conductor and scripts MAY note that extra art is optional visuals. Live critical-path cues (`demo-skupper`, `demo-mesh`, `demo-ratelimit`→HTTP 429, `failover`) MUST stay unchanged. Demo-stack specs MUST remain unmodified. Speakers MUST NOT operate or mutate `kind-west`, `kind-east`, `podman-edge`, or `kind-cluster` as part of showing the extra diagrams.

#### Scenario: No new live Make cues

- GIVEN extra architecture-diagram pages and existing live blocks
- WHEN listing stage cues
- THEN extra pages have no new Make or CLI cue
- AND Skupper, mesh, ratelimit→429, and failover cues remain the existing named targets and owners

#### Scenario: Demo stack and clusters unchanged

- GIVEN this talk-art change
- WHEN checking demo manifests, Make, CLIs, and cluster allowlist
- THEN no demo-stack behavior change is required
- AND no extra-diagram step operates `kind-cluster`

### Requirement: Overrun skips extra diagrams before the primary twelve

When both extra diagrams are shown, speakers SHOULD show the real-world diagram first and the laptop nutshell second. Extra architecture diagrams MUST be omitted before cutting any of the 12 primary slides and before delaying live Make cues. Extra architecture diagrams SHOULD be skipped at least as early as Option-C backup (they MAY be skipped before Option-C). Extra diagrams MUST NOT consume the ~2 minute primary topology slot in place of community slide 5. On clock pressure, speakers MUST keep slide 5 as the topology visual and MAY keep at most one extra diagram as backup art.

#### Scenario: Optional order when time allows

- GIVEN sufficient time and both extra diagrams available
- WHEN speakers choose to show extras
- THEN the real-world diagram is shown first and the nutshell second if both are used
- AND community slide 5 remains in the primary 5–9 topology block

#### Scenario: Overrun skips extras before primary-slide cuts

- GIVEN clock pressure during the talk
- WHEN deciding what to drop
- THEN extra architecture diagrams are skipped before any of the 12 primary slides are cut
- AND live Make critical-path cues remain valid

#### Scenario: Extras skip no later than Option-C

- GIVEN overrun handling that already cuts Option-C first among live-path backups
- WHEN extra architecture diagrams are also present
- THEN extras are skipped at or before the Option-C cut
- AND extras MUST NOT delay skipping Option-C or the UI skip path

### Requirement: Extra-diagram binaries stay outside git

Generated extra-diagram PNG, PPTX, Keynote, and equivalent binaries MUST NOT be committed. This extends the existing talk-packaging binary policy to architecture-diagram image files. Prompt text and mapping notes MAY live in repository talk-art artifacts. Licensed brand SVG dumps MUST NOT be committed.

#### Scenario: No generated image binaries in a packaging commit

- GIVEN a proposed talk-packaging commit that includes extra-diagram work
- WHEN reviewing staged files
- THEN no PNG, PPTX, Keynote, or video binaries are present
- AND no `demo/.run/` secrets are added

#### Scenario: Prompt text is the in-repo deliverable

- GIVEN English ChatGPT prompts and mapping notes
- WHEN checking provenance
- THEN in-repo content is original prompt and mapping text grounded in this repo’s demo story
- AND generated pixels remain speaker-local

