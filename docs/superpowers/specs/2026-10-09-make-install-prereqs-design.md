# Design: `make install` host prerequisites

Approved 2026-10-09. Installs demo host CLIs so `make prereq-check` passes.

## Contract

- `make install` → `demo/scripts/install-prereqs.sh`
- Pins from `demo/VERSIONS.md` (script constants kept in sync)
- CLIs → `~/.local/bin`; podman + inotify via sudo when needed
- Host tools for `prereq-check` (`python3`, `dig`/`bind-utils`, `setsid`/`util-linux`) via dnf when missing
- Force-overwrite pins with **warn** when replacing another version
- Does **not** edit shell rc files; prints `export PATH=…` + optional idempotent zsh snippet
- Ends by running `prereq-check` with `PATH` prepended
- Default CCM pin **v0.11.1** (stable host ports on Podman; override with `CLOUD_PROVIDER_KIND_VERSION`)

## Out of scope

`make up`, clusters, `make uninstall`, non-linux (fail clearly; arm64 release assets supported).
