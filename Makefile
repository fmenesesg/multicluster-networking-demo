# Multicluster connectivity demo — lifecycle + N-S + E-W + Skupper + failover (PR1–PR5).
# Allowlist: kind-west, kind-east, podman-edge. Never kind-cluster.
# LoadBalancer: cloud-provider-kind (NOT MetalLB) — see demo/VERSIONS.md.
# Talk UI (opt-in): make ui (A→B→C) — NEVER a dependency of up.

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS := $(ROOT)/demo/scripts

.PHONY: help install up down test-allowlist test-ui-foundation test-ui-linkerd test-ui-skupper prereq-check \
	smoke failover \
	demo-ratelimit demo-mesh demo-skupper demo-smoke demo-failover \
	ui ui-down

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  make install        Install host CLIs/pins (VERSIONS.md) into ~/.local/bin; then prereq-check' \
	  '  make up             Bring up demo sites + EG/Kuadrant + Linkerd + Skupper + apps' \
	  '  make down           Tear down demo sites only (never kind-cluster); stop demo-owned CCM' \
	  '  make prereq-check   Fail-fast host prerequisite gate (incl. cloud-provider-kind)' \
	  '  make test-allowlist Allowlist refusal suite' \
	  '  make test-ui-foundation  UI foundation + Phase A contract suite (offline)' \
	  '  make test-ui-linkerd     UI Phase B Viz contract suite (offline)' \
	  '  make test-ui-skupper     UI Phase C observer + teardown suite (offline)' \
	  '  make smoke          End-to-end smoke (200/429, mesh, Skupper, dig) — offline if no Kind' \
	  '  make failover       Hurt west primary; wait CoreDNS→east; timeout≠0' \
	  '  make demo-ratelimit Burst Gateway traffic; expect HTTP 429 (N-S wow)' \
	  '  make demo-mesh      Linkerd/emojivoto check (live or offline manifests)' \
	  '  make demo-skupper   Skupper/legacy-emoji check (live or offline manifests)' \
	  '  make demo-smoke     Alias of make smoke' \
	  '  make demo-failover  Alias of make failover' \
	  '  make ui             Opt-in talk UIs: app + Linkerd Viz + Skupper observer (A→B→C; fail-fast)' \
	  '  make ui-down        Tear down Viz + observer PFs (app is hosts/docs only)' \
	  'Optional: CLUSTER=<allowlisted-name> scopes up/down/demo-ratelimit/ui*'

install:
	@$(SCRIPTS)/install-prereqs.sh

up:
	@$(SCRIPTS)/up.sh

down:
	@$(SCRIPTS)/down.sh

prereq-check:
	@$(SCRIPTS)/prereq-check.sh

test-allowlist:
	@$(SCRIPTS)/test-allowlist.sh

test-ui-foundation:
	@$(SCRIPTS)/test-ui-foundation.sh

test-ui-linkerd:
	@$(SCRIPTS)/test-ui-linkerd.sh

test-ui-skupper:
	@$(SCRIPTS)/test-ui-skupper.sh

smoke demo-smoke:
	@$(SCRIPTS)/smoke.sh

failover demo-failover:
	@$(SCRIPTS)/failover.sh

demo-ratelimit:
	@$(SCRIPTS)/demo-ratelimit.sh

demo-mesh:
	@$(SCRIPTS)/check-east-west.sh

demo-skupper:
	@$(SCRIPTS)/check-skupper.sh

# --- Opt-in talk UI (never deps of up) ---
ui:
	@$(SCRIPTS)/ui.sh

ui-down:
	@$(SCRIPTS)/ui-down.sh
