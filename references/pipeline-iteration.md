# Pipeline Iteration Protocol — Smoke Test Before Full Run

This is the canonical "two-phase" pattern for any new ML training experiment
on Alliance: a tiny interactive smoke test that exercises the full pipeline
end-to-end, then a one-day full-dataset job once the smoke clears all gates.

The full version with experiment-folder structure (PLAN.md / SUMMARY.md,
versioned `results_vN_<tag>/` directories, mandatory wandb metric tables,
watchdogs) lives in a separate skill / repo:

> <https://github.com/Bardli/ml-experiment-workflow>

This page is the cluster-mechanics summary so you have the gist without
loading the full experiment-workflow skill.

## Phase 1 — Interactive smoke test

1. Request a **20–40 GB MIG / partial GPU** interactive allocation
   (`salloc --gpus-per-node=h100_2g.20gb:1` on Fir, equivalent on other
   clusters). Not a full GPU.
2. Copy or symlink **5–10 training samples** into your project's `data/`. The
   point is fast iteration — keep it tiny.
3. Build the full training + eval pipeline end-to-end: data loader → model →
   loss → optimizer step → wandb log. **Wire wandb on the very first run** —
   not "later".
4. Run for enough steps that loss visibly decreases. Estimate per-epoch
   wall-clock for the full dataset; that estimate is your phase-2 sizing input.

## Phase 1 — Live resource verification (REQUIRED, second terminal)

Wandb dashboards lag ~30 s and don't show CPU/RAM. While the smoke run is
going, ssh into the compute node and check directly:

```bash
sq                              # find the node your job is on
ssh <node>                      # ssh straight into it (Alliance allows this for your own jobs)
nvidia-smi                      # GPU memory + utilization
htop                            # CPU
free -h                         # RAM
```

The bar to clear, **all three**:

- **GPU memory ≥ ~95%** of allocated VRAM. If only 30% used → over-allocated;
  drop to a smaller MIG slice / partial GPU.
- **GPU utilization ≥ ~90%** sustained. If 30–60% → dataloader / I/O
  bottleneck. Increase `num_workers`, prefetch, or move data to
  `$SLURM_TMPDIR`. **Do not scale to the full job until this is fixed** — the
  bottleneck multiplies on a bigger GPU.
- **CPU saturation** matches the break-even count for the GPU slice (see
  `billing.md`).

## Phase 1 — Train-set sanity inference (proves no train/infer skew)

Run the same eval/inference script you'll use in phase 2, but on the
**5–10 training samples**. Expected metrics: **~100% DSC / accuracy / IoU.**
Anything materially lower means a train/inference flag mismatch — cheaper to
catch in phase 1 than after a 24-hour full job.

## Phase 2 — One-day full-dataset job (only after phase 1 clears all three bars)

- Submit a SLURM batch job on a **full GPU** with `--time=1-00:00:00` (1-day
  jobs go on full GPUs, per the cluster-sizing rule in `SKILL.md`).
- Save **latest** and **best** checkpoints every epoch. Both, every time —
  `latest` for resume, `best` for eval.
- Implement **patience-based early stopping**: halt if best validation metric
  hasn't improved for ~10 epochs/steps. Don't burn shared LevelFS on a flat
  curve.
- Watch wandb validation curves trend upward. If they don't within the first
  ~10–20% of total steps, kill the job and diagnose.

> **The non-negotiable phase-1 exit gate:** wandb shows decreasing training
> loss + GPU memory & utilization both ~100% (verified by `nvidia-smi`
> on-node, not just wandb) + train-set inference metrics ~100%. **All three.**
> Until then you are not ready for the full dataset.

## Common failure modes (drawn from the experiment-workflow skill)

- **Skipping phase 1 sanity inference and discovering a train/infer flag mismatch only on full-dataset eval.** Cheapest catch in phase 1.
- **Submitting the full-dataset job before GPU utilization is verified ~100% on-node.** Wandb shows allocated memory, not actual utilization.
- **Skipping early-stopping and letting a flat-curve job run 24 h.** Patience early-stop is shared-LevelFS hygiene, not just a convenience.
- **"I'll just submit the full-dataset job — interactive smoke is wasted time."** It's not. The whole point is to spend 30 minutes catching a bug that would otherwise burn 24 h.
