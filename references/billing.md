# Billing, Fairshare, and Account Selection on Alliance Canada

## How Slurm bills jobs (MAX_TRES)

Alliance uses **MAX_TRES** billing on every cluster: each second, a job's cost
equals the *maximum* of its TRES components — not the sum. You pay for whichever
dimension (CPU, Mem, or GPU) is most expensive; other dimensions are effectively
free up to that break-even point.

### Reading TRES weights for the current partition

Weights vary per cluster and per partition. Always look them up:

```bash
scontrol show partition <partition> | grep -i tresbill
```

Example (Fir, `gpubase_bygpu_b1`, observed 2026-04):

| Resource | Weight per unit |
|---|---|
| 1 CPU core | 1,016.67 |
| 1 GB RAM | 42.36 |
| 1× MIG 1g.10gb | 1,742.86 |
| 1× MIG 2g.20gb | 3,485.71 |
| 1× MIG 3g.40gb | 5,228.57 |
| 1× full H100 | 12,200 |

CPU-only partitions: `CPU=1000, Mem≈250/GB` (no GPU term).

The GPU weights are calibrated so the hardware-natural ratio (e.g. 48 CPU :
4 H100 per node → 12 CPU per H100 on Fir) matches the billing break-even
exactly. Your cluster's reference page has the break-even table for that
specific cluster.

## Break-even CPU/Mem per GPU (general principle)

Pick the CPU count that balances the GPU TRES weight. On Fir's H100 nodes:

| GPU | "Free" CPUs | "Free" Memory |
|---|---|---|
| 1g.10gb | **1** | ~41 GB |
| 2g.20gb | **3** | ~82 GB |
| 3g.40gb | **5** | ~123 GB |
| Full H100 | **12** | ~288 GB |

**Rule:** request the break-even CPU count with your GPU. Past break-even, CPU
(not GPU) becomes the billing driver. The same pattern applies on every
cluster — check the per-cluster reference for that cluster's exact numbers.

## What's billed: requested × wall-clock, NOT actual usage

- `seff` efficiency is diagnostic only — low CPU% or idle GPU does **not** reduce your bill.
- TIMEOUT bills full wall-clock, not just useful runtime.
- Jobs that finish early are billed for actual elapsed (over-requesting `--time` is fine for billing, but hurts backfill priority).
- Idle reservations (an interactive job sitting empty) cost the SAME as a 100%-utilized training job.
- Memory over-request is billed if it tips past GPU-dominance.

## Fairshare / LevelFS

Check yours with `sshare -U -l`. Priority formula (simplified):
```
LevelFS = NormShares / EffectvUsage
```
- `LevelFS > 1` → under-used → high priority
- `LevelFS < 1` → over-used → queued longer
- `EffectvUsage` decays with a **1-week half-life** — idle 1 week ≈ LevelFS doubles
- Slurm can't tell idle from productive; both burn LevelFS equally

**Nothing you do in-job increases LevelFS.** Only time (via decay) recovers it.

### Lab-shared LevelFS — `seff` is a team-priority duty

LevelFS in `def-<pi>_*` and `rrg-<pi>_*` is **shared across the entire lab
group**, not per-user. When one member runs an idle reservation, an
under-utilized GPU job, or a TIMEOUT-billed run, the whole lab queues longer
for ~1 week (the half-life of LevelFS decay). Slurm cannot distinguish
productive use from idle use — both burn fairshare equally.

This is why `seff <jobID>` after every job is **mandatory**, not optional. It
is a duty to teammates, not just self-diagnosis. Bars to clear:

- CPU efficiency ≥ 80% (low CPU usually means dataloader bottleneck)
- GPU utilization ≥ 90% sustained
- Memory used vs requested ≥ 80% (over-requesting Mem flips you past the
  GPU-dominance break-even — see TRES weights above)

If a job comes back with `CPU Efficiency: 12%` or "GPU idle 3 hours", **fix
it before submitting more**. Alliance staff will lower your group's priority
if the pattern continues, and your PI will get the notification.

## Account selection — MANDATORY pre-submit step

Most users have multiple Alliance accounts. LevelFS drifts daily as the
group consumes quota, so the "right" account changes. **Always check
LevelFS before submitting and rewrite `--account=` to the winner.**

Account naming convention:

| Account suffix | Scope | Notes |
|---|---|---|
| `def-<pi>_gpu` | Default GPU jobs | Default share, one per group |
| `def-<pi>_cpu` | Default CPU jobs | CPU-dedicated share |
| `rrg-<pi>_gpu` | RAC-allocated GPU | Larger share but heavily consumed |
| `rrg-<pi>_cpu` | RAC-allocated CPU | Same |
| `rpp-<pi>` | Priority-access (some clusters) | Special, scope varies |

Your specific account names go into your local Claude memory at
`~/.claude/projects/<proj>/memory/personal_cc_config.md` — **not** here, since
this skill is shared across users.

### Procedure (before every `sbatch`)

```bash
# 1. Check current LevelFS via helper script:
~/.claude/skills/ccdb-clusters/scripts/show-fairshare.sh

# 2. Pick winner for your job type:
#    - GPU job → max LevelFS among *_gpu accounts
#    - CPU job → max LevelFS among *_cpu accounts (rarely beaten)

# 3. Submit with that account:
sbatch --account=$(~/.claude/skills/ccdb-clusters/scripts/pick-gpu-account.sh) \
       /path/to/job.sh
```

If both your GPU accounts are <1, you're queued either way — submit on the
higher one and accept the wait, or delay for ~1 week of decay.

## Group-wide efficiency visibility (limits)

- `seff <jobID>` — your jobs only; teammates' jobs return "no data"
- `sacct -a` — restricted on Alliance, shows only your own jobs even with `-a`
- `sreport cluster AccountUtilizationByUser Accounts=<acct>` — works for group totals (CPU-hours per user)
- `sshare -A <acct>` — group LevelFS; no per-user breakdown
- `~/.claude/skills/ccdb-clusters/scripts/group-seff.sh` — loop `seff` over your recent jobs

For group-wide `seff` aggregates you must ask each member to run `seff`
themselves, or request a report from Alliance technical support.

## Useful commands

```bash
seff <jobID>                                    # post-hoc efficiency (your own)
sshare -U -l                                    # your fairshare state
sshare -A def-<pi>_gpu                          # whole group's LevelFS
sreport cluster AccountUtilizationByUser \
  Accounts=def-<pi>_gpu Start=2026-04-01 -t Hours    # per-user CPU-hours
scontrol show partition <partition> | grep TRESBillingWeights   # verify weights
```
