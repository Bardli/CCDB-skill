# Storage on Alliance Canada

## Three-tier filesystem (every cluster)

| Variable | Path pattern | Quota | Use for | Backup | Persistence |
|---|---|---|---|---|---|
| `$HOME` | `/home/$USER/` | small fixed (varies, often ~50 GB) | configs, dotfiles ONLY | yes | persistent |
| `$SCRATCH` | `/scratch/$USER/` (Lustre / GPFS) | large fixed (TB) | active/temporary work, venvs, caches, training | NO | **purged** if inactive |
| `$PROJECT` | `/project/<group>/` | RAC-allocated (TB–PB) | shared lab data, long-term archive | yes | persistent |

`$HOME`, `$SCRATCH`, `$PROJECT` are set on every Alliance node — use them in
scripts instead of hard-coded paths so the same script works across clusters.

## Cluster-specific quotas (selected)

| Cluster | $HOME | $SCRATCH | $PROJECT | Filesystem |
|---|---|---|---|---|
| Cedar | 526 TB shared | 5.4 PB | 23 PB | Lustre (DDN ES14K) |
| Graham | 133 TB shared | 3.2 PB | 16 PB | Lustre |
| Béluga | 105 TB shared | 2.6 PB | 25 PB | Lustre |
| Narval | 40 TB shared | 5.5 PB | 19 PB | Lustre |
| Niagara | 200 TB shared | 12.5 PB + 232 TB burst-buffer | 3.5 PB | IBM Spectrum Scale (GPFS) |
| Fir | 51 PB total (2 PB NVMe + 49 PB SAS) | (same pool) | (same pool) | Single-pool (verify partitioning) |
| Killarney | 1.7 PB total (all NVMe VastData) | (same pool) | (same pool) | VastData |
| Trillium | VERIFY | VERIFY | VERIFY | VERIFY |
| Rorqual | several PB (details TBD per mirror) | VERIFY | VERIFY | VERIFY |

Per-user quotas are not the same as total volume — run `diskusage_report` on
the cluster to see your actual quota and current usage.

## Keep everything in `$SCRATCH`

`$HOME` is small and on slower NFS (Lustre on some clusters). It fills fast
and running jobs from it can fail on write errors. Standard pattern:

1. **Symlink caches into scratch** (Alliance often pre-symlinks `~/.cache` and
   `~/.local` to scratch — check with `readlink ~/.cache`).
2. **Export cache env vars in `~/.bashrc`** so any tool that bypasses XDG
   still lands in scratch:
   ```bash
   export PIP_CACHE_DIR=$SCRATCH/.cache/pip
   export UV_CACHE_DIR=$SCRATCH/.cache/uv
   export HF_HOME=$SCRATCH/.cache/huggingface
   export TORCH_HOME=$SCRATCH/.cache/torch
   export XDG_CACHE_HOME=$SCRATCH/.cache
   export TMPDIR=$SCRATCH/tmp
   ```
3. **Verify in a fresh login shell:**
   ```bash
   env | grep -E "(CACHE|TMPDIR|HF_HOME)="
   # All values must begin with $SCRATCH/
   ```

## Job-local fast disk: `$SLURM_TMPDIR`

Every Alliance compute node provides a per-job temporary directory at
`$SLURM_TMPDIR` (typically a fast local SSD/NVMe). On most clusters it's
machine-local, so:

- **Best practice:** copy input data to `$SLURM_TMPDIR` at job start, do all
  fast I/O there, copy results back to `$SCRATCH` at job end. This avoids
  hammering the parallel filesystem when many small files are involved.
- The directory and its contents **disappear when the job ends** — copy
  anything you need to keep before the job exits.
- Some clusters let you size it: `--tmp=2400G` on Béluga gets you 2.4 TB
  (range typically 350–2490 GB). On Fir / Cedar / Graham the size is
  determined by node hardware.

Pattern inside a job script:

```bash
cp -r $SCRATCH/dataset $SLURM_TMPDIR/
python train.py --data $SLURM_TMPDIR/dataset
cp -r $SLURM_TMPDIR/results $SCRATCH/results_${SLURM_JOB_ID}/
```

## Purge policies

- **`$SCRATCH` is purged** when files are inactive (typically 60 days). Move
  anything you want to keep long-term to `$PROJECT`.
- **`$PROJECT` is allocated**: small default for unallocated groups (~1 TB),
  much larger after RAC. Apply via the CCDB portal.
- **Burst buffer** (Niagara only): also purged, like scratch, but much faster.
  Use for I/O-bound parallel jobs.

## Common gotchas

- **Submitting jobs from `/home`** is forbidden on Cedar and several other
  clusters: "Submitting jobs from directories residing in /home is not
  permitted". Always `cd $SCRATCH/<project>` first.
- **`/scratch` filesystem performance varies** — Lustre (Cedar/Graham/etc.) is
  optimized for parallel large-file I/O; many small files hit metadata
  latency. Use `$SLURM_TMPDIR` for many-small-file workloads.
- **`/project` is NOT for active jobs**: it's not designed for parallel I/O.
  Read or write `$SCRATCH` during a job, sync to `$PROJECT` afterward.
