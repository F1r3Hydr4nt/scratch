# Plan: Security-informed WSL upgrade/update script

## Context

The user shared Canonical's "MicroK8s Strict Confinement" whitepaper (Oct 2022) and asked for a script that upgrades and updates their WSL installation(s), informed by the security principles in the paper.

Current environment (verified):
- WSL version: **2.6.3.0**, kernel **6.6.87.2-1**, WSLg 1.0.71
- Distros installed:
  - `Ubuntu` — default, WSL 2, stopped
  - `docker-desktop` — WSL 2, stopped (managed by Docker Desktop itself; **do not apt-upgrade**)
- Scratch dir `C:\Users\honoh\scratch` is nearly empty (no prior script to edit).

## Security principles digested from the whitepaper

The paper is about MicroK8s on Ubuntu Core for IoT edge, but several principles port cleanly to a personal WSL update workflow:

1. **Transactional updates with rollback.** MicroK8s OTA updates "are fully transactional and roll back on failure" (p.4). → Export each distro to a tarball *before* upgrading so a broken upgrade can be restored with `wsl --import`.
2. **Minimise the unpatched window.** A device that is off for weeks "may be operating without the latest security fixes" when turned back on (p.3). → Make the script trivially re-runnable and optionally schedule it.
3. **Trusted update channels only.** Snaps come from a signed store; strict confinement blocks untrusted interactions (p.5). → Use only `apt` and `snap` with their default signed sources. No `curl | bash`, no ad-hoc PPAs.
4. **Least privilege.** Strict confinement grants "the absolutely necessary permissions" and nothing more (p.5). → The PowerShell driver runs as the normal user; elevation happens *inside* each distro via `sudo` for the package commands only.
5. **Self-healing / observability.** Ubuntu Core has self-healing OTA with logs (p.4). → Every run writes a timestamped log; the script exits non-zero on any per-distro failure and prints a summary table.
6. **Scoped to what the tool owns.** Strict confinement means a snap only touches resources it declares (p.5). → Per-distro upgrade commands are gated on what the distro actually supports (only call `apt` if `apt-get` exists; only call `snap refresh` if `snap` exists). No distro is excluded by name — see "No skipping" note below.

### "No skipping" (user instruction, 2026-04-23)

The script processes **every** distro returned by `wsl --list --quiet`, including `docker-desktop`. There are no `-Skip*` flags. Every step in the upgrade sequence runs for every distro, with the safety net that a missing tool inside a distro (e.g. no `snap`) is treated as "step not applicable", not a failure. Backups are always taken — not opt-in.

## Approach

One PowerShell script: `C:\Users\honoh\scratch\Update-WSL.ps1`.

Steps the script performs, in order, with **no skip flags**:

1. **Update WSL itself** — `wsl --update` on the Windows side. Always runs.
2. **Enumerate distros** via `wsl --list --quiet`. Every distro is processed, including `docker-desktop`.
3. **Backup (always on)** — `wsl --export <distro> <path>` each distro to `C:\Users\honoh\scratch\wsl-backups\<distro>-<yyyyMMdd-HHmmss>.tar` before upgrading. The script warns about disk usage and prunes backups older than 14 days at the end of the run (configurable retention via `-RetentionDays`).
4. **Per-distro upgrade** — for each distro, attempt every step. If a tool is missing inside the distro, the step is recorded as `n/a` (not a failure). Steps:
   - If `apt-get` exists:
     - `sudo apt-get update`
     - `sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confold" dist-upgrade`
     - `sudo apt-get -y autoremove --purge`
     - `sudo apt-get -y autoclean`
   - If `snap` exists: `sudo snap refresh`
   - `docker-desktop` is a BusyBox-based distro and will exercise the "tool missing" branches naturally — no special-casing in code.
5. **Log** everything to `C:\Users\honoh\scratch\wsl-update-logs\wsl-update-<yyyyMMdd-HHmmss>.log` (stdout + stderr, tee'd to console).
6. **Summary table**: distro | wsl-update | backup | apt | snap | duration | log path. Exit code = count of failures (steps recorded as `n/a` do not count as failures).

Flags (intentionally minimal):
- `-Distro <name>`        — restrict to a single distro (for targeted re-runs after a failure).
- `-RetentionDays <int>`  — prune backups older than N days (default 14).

Non-goals (explicit):
- No automatic PPA additions, no `do-release-upgrade` (major Ubuntu version jumps stay manual — too risky to automate blind).
- No Scheduled Task registration by default (see open question below).

## Files to create

- `C:\Users\honoh\scratch\Update-WSL.ps1`

## Verification

1. `pwsh -File .\Update-WSL.ps1 -Distro Ubuntu` — single-distro run; inspect the log file and confirm a tarball appears under `wsl-backups\`.
2. Re-run the same command immediately — second run should find nothing to upgrade for `apt`/`snap` steps (idempotent), but will produce a fresh backup.
3. Full run: `pwsh -File .\Update-WSL.ps1` — verify `docker-desktop` is processed; expect its `apt`/`snap` steps to show as `n/a` (BusyBox has neither) and its overall status to be `OK`, not `FAIL`.
4. Sanity-check a backup is restorable: `wsl --import test-restore C:\temp\test-restore <tarball>` then `wsl --unregister test-restore`. Do this once, not every run.

## Decisions confirmed with user

- **No skipping** — every distro is processed (including `docker-desktop`), no `-Skip*` flags, backups always on.
- **KISS, manual run only** — no Scheduled Task registration. The script does one thing: upgrade WSL and the distros when invoked.
