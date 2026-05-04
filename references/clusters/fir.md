# Fir Cluster

> Sourced from live Fir session (2026-05) + Alliance wiki mirror oldid=164899 (June 2025).
> Status: **Operational.** `$CC_CLUSTER=fir`, `$CC_RESTRICTED=true`.

## At a glance

| Item | Value |
|---|---|
| Location | Simon Fraser University (Burnaby, BC) |
| Login host | Set by Alliance (check with `echo $HOSTNAME` from a login session) |
| Globus endpoint | (verify) |
| OS | AlmaLinux 9.6 |
| Special | `$CC_RESTRICTED=true` — export-control rules apply |
| Best for | **Long jobs (≥1 day)** on H100 |

## Hardware

| Nodes | Cores | Memory | CPU | GPU |
|---|---|---|---|---|
| 860 | 192 | 768 GB DDR5 | 2× AMD EPYC 9655 (Zen 5) @ 2.7 GHz, 384 MB L3 | — |
| 160 | 48 | 1 TB DDR5 | 1× AMD EPYC 9454 (Zen 4) @ 2.4 GHz, 256 MB L3 | 4× NVIDIA H100 SXM5 (80 GB) |

H100s on the GPU nodes support **MIG slicing**, so a single 80 GB GPU can be
partitioned into smaller virtual GPUs.

## GPU sizing — MIG slice names

| Slice | VRAM | `--gpus-per-node=` value | Break-even CPUs | Break-even Mem |
|---|---|---|---|---|
| 1g.10gb | 10 GB | `h100_1g.10gb:1` | 1 | ~41 GB |
| 2g.20gb | 20 GB | `h100_2g.20gb:1` | 3 | ~82 GB |
| 3g.40gb | 40 GB | `h100_3g.40gb:1` | 5 | ~123 GB |
| Full H100 | 80 GB | `h100:1` (or `h100:4` for whole node) | 12 | ~288 GB |

**Default to 20 GB or 40 GB** — full 80 GB is for genuine VRAM hogs or 1-day jobs.

## Storage

| Mount | Variable | Volume | Purge |
|---|---|---|---|
| `/home/$USER` | `$HOME` | small fixed (~48 GB) | persistent |
| `/scratch/$USER` | `$SCRATCH` | large fixed | inactive purge (60 days) |
| `/project/<group>` | `$PROJECT` | RAC | persistent |
| `/cvmfs/soft.computecanada.ca/...` | — | shared software stack | read-only |

Total cluster storage: 51 PB (2 PB NVMe + 49 PB SAS).

## Fir-specific quirks

- **Compute-node internet IS available** — `pip install`, `wandb online`, and
  `huggingface_hub` calls work inside `sbatch`. (Most Alliance clusters block
  this; Fir does not.)
- **`$CC_RESTRICTED=true`** — some software (CUDA toolkit, certain ML
  libraries) is gated; ITAR/EAR-style export-control rules. If a `module
  load` returns "permission denied", that's why; ask CCDB support.
- **Templates path** — example job templates live in `$SCRATCH/job_*.sh`
  (per-user; not shipped with this skill).
- **MASTER_PORT** — see `references/templates.md` for the torchrun pitfall;
  a documented case occurred on Fir.

## Partitions and wall-time

Fir uses banded partitions where SLURM picks the first that fits your
`--time` request:

| Partition | Wall-time |
|---|---|
| `gpubase_bygpu_b1` | 3 h |
| `gpubase_bygpu_b2` | 6 h |
| `gpubase_bygpu_b3` | 12 h |
| `gpubase_bygpu_b4` | 1 day |
| `gpubase_bygpu_b5` | 3 days |
| `gpubase_bygpu_b6` | 7 days |

You normally don't pick the partition; SLURM picks it from your `--time`.

## TRES weights (observed 2026-04, partition `gpubase_bygpu_b1`)

| Resource | Weight per unit |
|---|---|
| 1 CPU core | 1,016.67 |
| 1 GB RAM | 42.36 |
| 1× MIG 1g.10gb | 1,742.86 |
| 1× MIG 2g.20gb | 3,485.71 |
| 1× MIG 3g.40gb | 5,228.57 |
| 1× full H100 | 12,200 |

Re-verify with `scontrol show partition gpubase_bygpu_b1 | grep -i tresbill`.

## Daily cost (12h, requested vs used)

| GPU | Daily cost |
|---|---|
| 1g.10gb | ~75M / day |
| 2g.20gb | ~150M / day |
| 3g.40gb | ~226M / day |
| Full H100 | ~527M / day |

(Numbers are billing units, not currency; useful for relative comparison.)

## Common pitfalls on Fir

- **Idle full-H100 reservation while AFK** — bills the same as 100%-utilized.
  Cancel with `scancel` when you step away.
- **PyTorch < 2.2** — H100 is sm_90, needs PyTorch ≥ 2.2.
- **Hard-coded `os.environ['MASTER_PORT']` in `main.py`** — overwrites
  torchrun's port and hangs `dist.init_process_group` for 1800 s. See
  `templates.md`.
- **Submitting from `/home`** — fails with "Submitting jobs from
  directories residing in /home is not permitted". `cd $SCRATCH/<project>` first.
