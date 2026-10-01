# KCD Argentina 2026 — Multicluster Connectivity Demo

30-minute laptop demo: **Envoy Gateway + Kuadrant + Linkerd + Skupper + CoreDNS** across `kind-west`, `kind-east`, and `podman-edge`.

Wow moments: RateLimit **429**, CoreDNS HA failover, meshed emojivoto, Skupper Kind↔Podman — plus optional **graphical UIs** (app, Linkerd Viz, Skupper network console).

Repo: [fmenesesg/multicluster-networking-demo](https://github.com/fmenesesg/multicluster-networking-demo)

## Quick start

New machine? Complete [First-time setup](#first-time-setup-fedora--wsl2) before running these commands. Run all Bash commands as the same normal Linux user, from the repository root.

```bash
make prereq-check       # optional; make up already runs this
make up                 # stack only (no UIs) — re-run is idempotent
make smoke              # 200/429, mesh, Skupper, dig

# Optional talk UIs (after up) — always app → Viz → observer (A→B→C):
echo '127.0.0.1 emojivoto.demo.local' | sudo tee -a /etc/hosts   # once
make ui                 # start+validate each phase (fail-fast); prints ACCESS_URL=
make ui-down            # stop Viz + observer PFs (app is hosts/docs only)

make down               # best-effort ui-down, then demo sites only
```


That is the whole public path. Everything else below is detail for the talk and troubleshooting.

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Fedora/Linux laptop with Podman | Kind uses `KIND_EXPERIMENTAL_PROVIDER=podman` |
| `fs.inotify.max_user_instances` ≥ **512** | `sudo sysctl -w fs.inotify.max_user_instances=512` |
| `podman`, `kind`, `kubectl`, `helm` | See `demo/VERSIONS.md` |
| `skupper` **2.2.1** | Matching controller YAML |
| `linkerd` **edge-26.6.3** | Max K8s 1.35 — Kind node pin **1.35.5** |
| `cloud-provider-kind` on `PATH` | Official Kind LoadBalancer (**not MetalLB**) |
| `kustomize`, `make`, `git`, `curl`, `openssl`, `dig` | CoreDNS rendering, scripts, certificates and DNS probes |

## First-time setup (Fedora / WSL2)

The runtime is Linux with rootless Podman, systemd and cgroup v2. On Windows, install a Fedora WSL2 distribution first, then enter it using `wsl -d <distribution>` from PowerShell (`wsl --list --verbose` lists installed names). Windows executables and a separate Podman Desktop machine do not satisfy the Linux prerequisites. Run the remaining commands **inside that distribution**, not PowerShell or Git Bash.

For WSL, `ps -p 1 -o comm=` must report `systemd`. If needed, merge `[boot]` and `systemd=true` into `/etc/wsl.conf`, preserving existing settings, then restart that distribution from Windows. A restart stops its running processes. Use `wsl --update` if the WSL kernel needs updating. See [Kind on WSL2](https://kind.sigs.k8s.io/docs/user/using-wsl2/) and [rootless requirements](https://kind.sigs.k8s.io/docs/user/rootless/).

Allow disk space for two Kubernetes nodes and their images, and enough RAM for both complete stacks; 16 GiB available to Linux and 30 GiB free disk are a practical starting budget, not a measured minimum. Initial setup requires access to GitHub, Docker Hub, Quay, GHCR and the Helm repositories.

### 1. Install Linux packages and get the repository

```bash
sudo dnf install -y podman shadow-utils shadow-utils-subid passt slirp4netns \
  fuse-overlayfs git make curl tar gzip unzip openssl bind-utils jq golang python3 util-linux

mkdir -p ~/git ~/.local/bin
git -c core.autocrlf=false clone https://github.com/fmenesesg/multicluster-networking-demo.git ~/git/multicluster-networking-demo
cd ~/git/multicluster-networking-demo
export PATH="$HOME/.local/bin:$PATH"
export KIND_EXPERIMENTAL_PROVIDER=podman
```

For an existing checkout, use its directory instead of cloning again. Prefer the Linux filesystem (`~/git`) on WSL. A checkout on `/mnt/c` or `/mnt/d` also needs executable scripts and LF line endings; `.gitattributes` enforces LF for shell scripts and YAML on fresh checkouts. An `env: bash\r: No such file or directory` error means the existing scripts still contain CRLF.

Add these two exports once to `~/.bashrc` so new terminals use the same tools and provider:

```bash
export PATH="$HOME/.local/bin:$PATH"
export KIND_EXPERIMENTAL_PROVIDER=podman
```

### 2. Prepare rootless Podman

```bash
grep "^$(id -un):" /etc/subuid /etc/subgid
podman info
```

The user needs non-overlapping subordinate UID/GID ranges in both files (normally allocated by Fedora). If absent, have the administrator allocate a free range using `usermod --add-subuids START-END --add-subgids START-END USER`; do not copy a range already assigned to another user.

If Podman reports `newuidmap ... Operation not permitted` or missing setuid/file capabilities, restore the Fedora package metadata, then retry as the normal user:

```bash
sudo rpm --restore shadow-utils
getcap /usr/bin/newuidmap /usr/bin/newgidmap
podman info
```

Ensure the user systemd manager is available and keep its services alive:

```bash
sudo loginctl enable-linger "$(id -un)"
systemctl --user status
systemctl --user enable --now podman.socket  # required by Skupper's Podman linking helper
podman info --format '{{.Host.CgroupVersion}} {{.Host.Security.Rootless}}'
# Expected: v2 true
```

Persist the inotify requirement (retain higher existing values if configured):

```bash
echo 'fs.inotify.max_user_instances=512' | sudo tee /etc/sysctl.d/90-multicluster-demo.conf
sudo sysctl -p /etc/sysctl.d/90-multicluster-demo.conf
```

If Kind misses the `Reached target ... Multi-User System` boot log, configure Podman's `k8s-file` log driver before creating the demo clusters. Merge this with existing user configuration rather than overwriting it:

```toml
# ~/.config/containers/containers.conf
[containers]
log_driver = "k8s-file"
pids_limit = 65536
```

### 3. Install pinned Linux CLIs

The following commands target **Linux x86_64** (`uname -m` = `x86_64`). For ARM64, select the corresponding upstream assets. They install into `~/.local/bin`, leaving system versions available. Run the block with Bash; a failed download must stop installation.

```bash
(
set -euo pipefail
install_dir="$HOME/.local/bin"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$install_dir"
curl -fL --retry 3 https://github.com/kubernetes-sigs/kind/releases/download/v0.32.0/kind-linux-amd64 -o "$tmp_dir/kind"
curl -fL --retry 3 https://github.com/linkerd/linkerd2/releases/download/edge-26.6.3/linkerd2-cli-edge-26.6.3-linux-amd64 -o "$tmp_dir/linkerd"
curl -fL --retry 3 https://github.com/skupperproject/skupper/releases/download/2.2.1/skupper-cli-2.2.1-linux-amd64.tgz -o "$tmp_dir/skupper.tgz"
tar -xzf "$tmp_dir/skupper.tgz" -C "$tmp_dir" skupper
curl -fL --retry 3 https://get.helm.sh/helm-v3.17.4-linux-amd64.tar.gz -o "$tmp_dir/helm.tgz"
tar -xzf "$tmp_dir/helm.tgz" -C "$tmp_dir" linux-amd64/helm
curl -fL --retry 3 https://dl.k8s.io/release/v1.36.1/bin/linux/amd64/kubectl -o "$tmp_dir/kubectl"
curl -fL --retry 3 https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.6.0/kustomize_v5.6.0_linux_amd64.tar.gz -o "$tmp_dir/kustomize.tgz"
tar -xzf "$tmp_dir/kustomize.tgz" -C "$tmp_dir" kustomize
curl -fL --retry 3 https://github.com/kubernetes-sigs/cloud-provider-kind/releases/download/v0.11.1/cloud-provider-kind_0.11.1_linux_amd64.tar.gz -o "$tmp_dir/ccm.tgz"
tar -xzf "$tmp_dir/ccm.tgz" -C "$tmp_dir" cloud-provider-kind
install -m 755 "$tmp_dir/"{kind,linkerd,skupper,kubectl,kustomize,cloud-provider-kind} "$install_dir/"
install -m 755 "$tmp_dir/linux-amd64/helm" "$install_dir/helm"
)
hash -r
kind version
kubectl version --client
helm version --short
linkerd version --client
skupper version
kustomize version
```

The cloud-provider-kind release above makes this setup reproducible; the alternative build-from-source path is:

```bash
go install sigs.k8s.io/cloud-provider-kind@latest
# ensure $(go env GOPATH)/bin or ~/.local/bin is on PATH
make prereq-check
```

### 4. Bring up and validate the live demo

```bash
make prereq-check
# A delegated user scope is useful on WSL/rootless Podman:
systemd-run --scope --user -p Delegate=yes make up
make smoke
make failover
```

`make up` is also valid directly when the current session already has cgroup delegation. Keep `KIND_EXPERIMENTAL_PROVIDER=podman` exported for **all** commands: Kind discovery must use the same runtime as creation. The first run downloads large images and may take several minutes. After an interrupted install, fix the reported problem and rerun `make up`.

Success means `make smoke` prints **live path**, HTTP returns 200/429, the burst includes 429, mesh and Skupper checks pass, and `make failover` observes DNS switching to east and restores west. An **offline path** result only checks files/contracts and is not evidence that the running demo works. Inspect DNS probe output if smoke reports that nslookup was skipped/failed.

The failover scenario demonstrates **DNS withdrawal and east Gateway reachability**. East deploys only the voting service, so its Gateway may return 404/500/503 rather than the full web app; the failover script accepts those responses. This is not full application continuity across sites.

For optional UIs, add `127.0.0.1 emojivoto.demo.local` to the hosts file used by the browser, then run `make ui`. For a Windows browser that file is `C:\Windows\System32\drivers\etc\hosts` (administrator edit); `/etc/hosts` only configures Linux clients. WSL localhost forwarding must be enabled for a Windows browser to reach the published ports. Verify the Host-header curl below from Linux first, then from Windows if needed.

Troubleshooting starts with `podman info`, `make prereq-check`, `kind get clusters`, `kubectl --context kind-kind-west get pods -A`, and `demo/.run/cloud-provider-kind.log`. Never use a blanket container reset or delete the unrelated `kind-cluster`.

After a host/WSL shutdown, Kind may list existing clusters whose node containers are stopped. If `make up` reports an unreachable API (`127.0.0.1:... connection refused`), check `podman ps -a`. For this repo's single-node clusters, resume the existing containers without deleting their data:

```bash
systemd-run --scope --user -p Delegate=yes \
  podman start kind-west-control-plane kind-east-control-plane
# Retry these checks while Kubernetes starts; both must return "ok":
kubectl --context kind-kind-west --request-timeout=10s get --raw=/readyz
kubectl --context kind-kind-east --request-timeout=10s get --raw=/readyz
make up
make smoke
make ui  # optional; recreate dashboard forwards after the restart
```

Run this recovery only for existing, stopped demo containers. `make up` recreates missing demo sites normally. An API failure must be resolved before diagnosing missing LoadBalancer IPs.

## Topology

```
Client → EG (west) → web (meshed) → voting → emoji
              │            │            │
         RateLimit      Linkerd      Skupper
              │                         ├─ voting (east)
         CoreDNS west→east              └─ legacy-emoji (podman-edge)
```

| Site | Role |
|------|------|
| `kind-west` | Hub: EG, Kuadrant, Linkerd, full emojivoto, Skupper hub (`linkAccess`) |
| `kind-east` | Secondary: EG, Kuadrant, Linkerd, voting replica, Skupper spoke |
| `podman-edge` | Skupper Podman site + tiny `legacy-emoji` HTTP JSON |

**Never touch** the unrelated Kind cluster `kind-cluster`. Scripts refuse non-allowlisted names.

## LoadBalancer (first-class)

Local LB is **cloud-provider-kind** with `--enable-lb-port-mapping` (not MetalLB). `make up` starts a demo-owned CCM when Kind sites are targeted; host maps include west Gateway `:8080`, east `:8081`, and Skupper router ports used by Option C Podman linking. `make down` stops that CCM only if the demo started it.

**Kind ↔ Podman Skupper (Option C):** the host-networked Podman router cannot reach Kind LB VIPs (`10.89.0.x`). Redeem rewrites Link endpoints to `127.0.0.1` after CCM maps router ports — see `demo/skupper/README.md`.

## Talk UIs (opt-in — not part of `make up`)

**Talk deck** (scripts, Gemini prompts, speaker cards): [`openspec/changes/archive/2026-09-28-kcd-ba-talk-deck/`](openspec/changes/archive/2026-09-28-kcd-ba-talk-deck/). **Conductor guion↔clips** + stage commands + recording runbook: [`openspec/changes/kcd-ba-demo-backup/`](openspec/changes/kcd-ba-demo-backup/) (`talk-conductor.md`, `stage-commands.md`, `speaker-cards.md`, `recording-runbook.md`). Backup media only at `/home/fmeneses/Videos/kcd-ba-demo-backup/` (outside git; no video/PPTX binaries or proprietary RH PPTX in the repo).

One public entry: **`make ui`**. It always starts **app (A) → Linkerd Viz (B) → Skupper observer (C)** — each start+validate + `ACCESS_URL` — and **fails fast** if a phase fails (later phases do not start). There is no public single-phase Make target. Critical-path success remains RateLimit, mesh, Skupper, and failover — UIs are optional.

This demo does **not** install Kuadrant Grafana, Envoy admin, Kiali, or Kubernetes Dashboard.

Dashboards use **localhost port-forward only** (never CCM LB). Reserved host ports (never for UI PF): `8080`, `8081`, `18080`, `18081`, `45671`, `55671`. Teardown kills only loopback listeners (`127.0.0.1` / `::1`), never broad all-interface port kills.


### Hosts (once)

```text
127.0.0.1 emojivoto.demo.local
```

```bash
echo '127.0.0.1 emojivoto.demo.local' | sudo tee -a /etc/hosts
```

### ACCESS_URLs (printed by `make ui`)

| Phase | Surface | Typical URL |
|-------|---------|-------------|
| A | Emojivoto (west Gateway) | **http://emojivoto.demo.local:8080/** |
| A | East Gateway (optional) | **http://emojivoto.demo.local:8081/** |
| B | Linkerd Viz (west-only) | **http://127.0.0.1:50750/** (or printed free port) |
| C | Skupper network-observer | **https://127.0.0.1:8443/** (or printed free port) |

Hostname is required for the app — bare `http://127.0.0.1:8080/` without `Host` is not the documented path. If a preferred port is busy, the helper picks another and **prints the final `ACCESS_URL=`** — that printed URL is the contract for the run.

```bash
make ui                  # app + Viz + observer (A→B→C); fail-fast
make ui-down             # stop Viz + observer PFs + uninstall (app is hosts/docs only)
```

**Phase A (Browser):** `ACCESS_URL=http://emojivoto.demo.local:8080/` — expect **200** or **429**. RateLimit is **3 requests / 10s to `/` only**. Reload the homepage quickly or run `make demo-ratelimit` to demonstrate **429**. JavaScript, images, list, leaderboard and voting APIs are excluded so loading the page does not exhaust the quota before a vote.

Emojivoto displays a hardcoded **404 / 🚧** screen for any failed vote, even when the API actually returned 429 or 500. Voting for **🍩 doughnut intentionally fails** in the upstream application; use another emoji to test a successful vote. If the error appears for other emojis, inspect `/api/vote` in the browser Network panel for the actual HTTP status.

**Phase B:** Linkerd Viz @ `edge-26.6.3`, west-only; bundled Prometheus OK; skip-inject on N-S/Skupper namespaces unchanged.

**Phase C:** network-observer **2.2.1**; prefer podman-edge, **fallback** `kind-west` namespace `skupper` (Helm needs Kubernetes). Accept the self-signed cert warning. Basic auth (once, gitignored):

```bash
cat demo/.run/ui-skupper-basic-auth
# BASIC_AUTH_USER=skupper
# BASIC_AUTH_PASSWORD=…
```

Port-forwards are started with `nohup setsid`, detached standard input, and recorded under `demo/.run/` (`.pid` + `.port` + `disown`) so they survive the launching shell exiting, including WSL command sessions. They do not survive a WSL shutdown or host reboot; rerun `make ui` afterward. `make ui-down` stops them by pid, falls back to loopback port cleanup if a pidfile is missing, and verifies the port is free before claiming “cleared”. `make down` calls `ui-down` best-effort first.

Private knobs (not Make help): `UI_A_*` (app), `UI_B_*` (Viz), `UI_C_*` (observer) — e.g. `UI_B_PORT=50750`, `UI_C_PORT=8443`, `UI_C_SITE=podman-edge`.


## CLI probes (after `make up`)

```bash
# North-south (scripts/CI — Host header)
curl -sS -H 'Host: emojivoto.demo.local' http://127.0.0.1:8080/

# Rate-limit wow
make demo-ratelimit

# Hybrid outside-cluster service (Podman)
curl -sS http://127.0.0.1:18080/
```

## 30-minute runbook

**Before the talk** (or cold start): `make prereq-check` → `make up` → `make smoke` → optional `make ui`.

**Live critical path** (prefer Make over typing YAML):

1. **N-S RateLimit** — `make demo-ratelimit` (burst → at least one **429**), or browse the app until 429
2. **E-W mesh** — `make demo-mesh`; optional Viz comes with `make ui` (always A→B→C — not Viz-only)
3. **Skupper** — `make demo-skupper`; optional observer console comes with `make ui` (same A→B→C run)
4. **Failover** — `make failover`  
   - Scales west Envoy Gateway dataplane → 0 (`envoy-gateway-system`) and **deletes** west DNSPolicy  
     (do **not** set `weight: 0` — Kuadrant CoreDNS panics)  
   - Dual-site dig: **east** CoreDNS still answers with the east Gateway IP; **west** drops the primary  
   - Default wait: **120s** (`FAILOVER_TIMEOUT_SEC`); **exits non-zero** on timeout  
   - Restores west Envoy + DNSPolicy on script exit  
5. **Auth MAY (bonus only)** — optional Authorino API-key; **not** required (see `demo/kuadrant/README.md`)

**Rollback:**

```bash
make down               # best-effort ui-down, then demo sites only; kind-cluster untouched
```

`make up` is idempotent on re-run (Kind skip-create, Linkerd upgrade-when-present). It **fails** if the Skupper three-site VAN does not link (token issue / east redeem / podman-edge Option C).

Existing `Ready` Skupper links to kind-west are reused on reruns; tokens are issued/redeemed only for sites that still need a link. If a new redemption fails with `no route to host`, compare the west `skupper-grant-server` Service's EXTERNAL-IP with the current Podman LoadBalancer container IP: after a restart the advertised address can be stale. Existing router links may remain healthy even when the token endpoint is unreachable.

## Make targets

| Target | Purpose |
|--------|---------|
| `make up` / `make down` | Lifecycle (allowlist-scoped); `up` stays UI-free |
| `make prereq-check` | Single host prerequisite gate (also invoked by `up`) |
| `make smoke` / `make demo-smoke` | End-to-end probes (offline validates if no Kind) |
| `make failover` / `make demo-failover` | Kill-primary → east |
| `make demo-ratelimit` | 429 wow |
| `make demo-mesh` | Linkerd / emojivoto |
| `make demo-skupper` | Skupper / legacy-emoji |
| `make ui` | Opt-in talk UIs: app + Linkerd Viz + Skupper observer (A→B→C; fail-fast) |
| `make ui-down` | Tear down Viz + observer PFs (app is hosts/docs only) |
| `make test-allowlist` | Refuse `kind-cluster` / unknown names |
| `make test-ui-foundation` | UI foundation + Phase A (offline) |
| `make test-ui-linkerd` | UI Phase B Viz (offline) |
| `make test-ui-skupper` | UI Phase C observer + teardown (offline) |

Optional: `CLUSTER=kind-west` (etc.) scopes `up` / `down` / `demo-ratelimit` / `ui*`.

## Pins & layout

- Versions: [`demo/VERSIONS.md`](demo/VERSIONS.md)
- Manifests: `demo/{kind,gateway,kuadrant,linkerd,skupper,apps}/`
- Operator scripts: `demo/scripts/` (`up`, `down`, `smoke`, `ui.sh`, …)
- Internals: `demo/scripts/lib/` (CCM, Skupper redeem/SAN, shared helpers)
- Phase helpers (private): `demo/scripts/ui/_phase_*.sh`
- Runtime state: `demo/.run/` (gitignored — CCM pid, UI PF pid/port, Skupper basic-auth)
- SDD specs: `openspec/specs/`
- Archived changes:
  - `openspec/changes/archive/2026-07-31-multicluster-connectivity-demo/`
  - `openspec/changes/archive/2026-07-31-demo-product-uis/`
  - `openspec/changes/archive/2026-08-03-demo-script-consolidation/`
  - `openspec/changes/archive/2026-09-28-kcd-ba-talk-deck/`

## Offline / CI-friendly checks

Without demo Kind clusters, `make smoke`, `make failover`, `make demo-*`, `make test-allowlist`, and `make test-ui-*` validate manifests and contracts. Install the prerequisites first: mesh/Skupper checks still invoke their pinned CLIs, and the allowlist suite exercises the host prerequisite gate. These checks do not create clusters or prove live connectivity. The UI contract suites can run independently of a deployed stack.
