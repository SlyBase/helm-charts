# helm-charts

Collection of signed Helm charts for self-hosted apps. Each chart lives under `charts/<chart>/` with its own `Chart.yaml`, `values.yaml`, `values.schema.json`, `templates/`, and `samples/`.

Charts are distributed via OCI (`ghcr.io/slybase/charts`) and signed with Cosign — see [README-SIGNING.md](README-SIGNING.md).

## Chart structure

- `charts/<chart>/Chart.yaml` — version, appVersion, ArtifactHub annotations (`artifacthub.io/changes`)
- `charts/<chart>/values.yaml` + `values.schema.json` — changes to `values.yaml` must always be reflected in `values.schema.json` (new fields, type changes, removed fields)
- `charts/<chart>/templates/` — Deployment/StatefulSet, Service, Ingress, HPA, PVC, ServiceMonitor
- `charts/<chart>/samples/` — sample values used for installs and doc examples; update alongside template/value changes
- `charts/<chart>/CHANGELOG.md` — human-readable release history

## Release & versioning workflow

Releases are driven by **release-please** + **git tags**, not by hand-editing `version:` in `Chart.yaml`.

1. **Renovate** opens PRs with dependency bumps as conventional commits. The commit type encodes the chart bump (see `renovate.json` packageRules):
   - subchart (`helmv3`) major → `feat` (chart **minor**); subchart minor/patch/digest → `fix` (chart **patch**)
   - direct dep (`helm-values`/`custom.regex`) major → `feat!` breaking (chart **major**); minor → `feat`; patch/digest → `fix`
   - Renovate edits `appVersion` / `artifacthub.io/images` / subchart versions directly, but does **not** touch `version:`.
2. **release-please** (`.github/workflows/release-please.yml`, config `release-please-config.json` + `.release-please-manifest.json`) keeps one release PR per chart, bumping `Chart.yaml:version` (via `extra-files`) and generating `CHANGELOG.md`.
3. A bridge step runs `.github/scripts/sync-artifacthub-changes.py` on the release PR to derive the `artifacthub.io/changes` (+ `artifacthub.io/prerelease`) annotation from the new CHANGELOG entry — single source of truth.
4. Merging a release PR creates a per-chart tag (`<chart>-v<version>`, e.g. `wordpress-v4.5.0`) + GitHub Release, which triggers `oci-release.yaml` to package, push, Cosign-sign and upload ArtifactHub metadata.
5. **Auto-merge** (`.github/workflows/release-please-automerge.yml`): release PRs that are **patch or minor** bumps (i.e. not a breaking-major `feat!` and not a `-alpha/-beta/-rc` prerelease) are merged automatically once the ArtifactHub sync commit has landed and all PR checks (`pr-chart-validate.yml`, `chart-install-test.yml`) are green. **Major/breaking releases stay manual.** The merge uses the PAT (`SLYBASE_GHCR_TOKEN`) — a `GITHUB_TOKEN` merge would not re-trigger release-please, so step 4's tag/OCI chain would never fire. No PR approval is involved: `main` has no required-review protection.

Feature PRs use conventional commits (`feat:`/`fix:`/`feat!:`) the same way to drive their chart's bump. PR validation (lint/template) lives in `pr-chart-validate.yml`.

## WordPress chart

The most complex chart — uses init containers and ConfigMaps/Secrets for plugins, themes, MU-plugins, and custom init scripts. Integrates with MariaDB (subchart or external), Memcached, and Prometheus exporters. See [charts/wordpress/README.md](charts/wordpress/README.md) and [charts/wordpress/samples/](charts/wordpress/samples/).

**Workload controller (`controllerType`):** the chart renders either a Deployment or a StatefulSet:

- `controllerType: deployment` (default, backwards-compatible) — single shared PVC (`pvc.yaml`), suitable for `replicaCount: 1` or RWX storage.
- `controllerType: statefulset` — each replica gets its own ReadWriteOnce volume via `volumeClaimTemplates` (true HA without an RWX share-manager SPOF). Adds a headless Service and `statefulset.*` tunables (`podManagementPolicy`, `updateStrategy`, `persistentVolumeClaimRetentionPolicy`). `storage.existingClaim` is not supported here.

The Pod spec is shared between both controllers via the `wordpress.podTemplate` partial in [templates/_pod.tpl](charts/wordpress/templates/_pod.tpl) — **edit pod-level changes there, not in `deployment.yaml`/`statefulset.yaml`** (those only hold controller-level fields). After editing `_pod.tpl`, confirm the Deployment render is unchanged with a `helm template` before/after diff.

**After every change to the WordPress chart, run the verify script before committing:**

```bash
./charts/wordpress/samples/verify/verify.sh
```

This script installs the chart via `install.sh`, waits for all pods (WordPress, MariaDB, Valkey) to become Ready, checks init-container and main-container logs for errors, and runs HTTP + metrics smoke tests. Fix any reported failures before pushing. Clean up afterwards with:

```bash
./charts/wordpress/samples/verify/uninstall.sh
```

## WireGuard and wg-easy charts

Both charts require a namespace with `pod-security.kubernetes.io/enforce: privileged` (see each chart's `readme.md` "Prerequisites" section).

**After every change to the wireguard or wg-easy chart, run the matching verify script before committing:**

```bash
./charts/wireguard/samples/verify/verify.sh
./charts/wg-easy/samples/verify/verify.sh
```

Each script installs the chart via `install.sh` into a dedicated `*-verify` namespace, waits for the pod to become Ready, checks container logs for errors, verifies the `wg0` interface comes up (and for wireguard, that `wg show` reports the expected listening port and peer count), and smoke-tests the Service(s)/NodePort(s). Fix any reported failures before pushing. Clean up afterwards with:

```bash
./charts/wireguard/samples/verify/uninstall.sh
./charts/wg-easy/samples/verify/uninstall.sh
```

> **Note:** wg-easy's verify currently fails on nftables-only kernels (e.g. Talos) due to an upstream wg-easy v15 image issue — see [charts/wg-easy/readme.md](charts/wg-easy/readme.md#known-issues). This is expected and not a chart regression.

## Key files

| Purpose | Path |
|---|---|
| Detect changed charts in CI | `.github/actions/detect-changed-charts/action.yml` |
| Release automation (per-chart) | `.github/workflows/release-please.yml`, `release-please-config.json`, `.release-please-manifest.json` |
| Auto-merge patch/minor release PRs | `.github/workflows/release-please-automerge.yml` |
| OCI publish on release tag | `.github/workflows/oci-release.yaml` |
| CHANGELOG → ArtifactHub annotation bridge | `.github/scripts/sync-artifacthub-changes.py` |
| Script usage docs | `.github/scripts/README.md` |
| Signing docs | `README-SIGNING.md` |

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (60-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk go test             # Go test failures only (90%)
rtk jest                # Jest failures only (99.5%)
rtk vitest              # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk pytest              # Python test failures only (90%)
rtk rake test           # Ruby test failures only (90%)
rtk rspec               # RSpec test failures only (60%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%). Format flags (-c, -l, -L, -o, -Z) run raw.
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->