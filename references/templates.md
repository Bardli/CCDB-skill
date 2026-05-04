# SLURM Job Templates

Templates below use generic placeholders (`<your-gpu-account>`, `$SCRATCH`) so
they work on any Alliance cluster. Cluster-specific GPU types and partition
names live in `clusters/<cluster>.md`.

## Boilerplate header

Every Alliance job script should start with:

```bash
#!/bin/bash
#SBATCH --account=<your-gpu-account>          # use pick-gpu-account.sh
#SBATCH --time=12:00:00                        # 12h here; pick the smallest fitting
#SBATCH --job-name=<job_name>
#SBATCH --output=<scratch>/slurm_logs/%x_%j.out
#SBATCH --error=<scratch>/slurm_logs/%x_%j.err

module load python/3.11.5                      # or the version you need
source <scratch>/<project>/.venv/bin/activate
```

Replace `<scratch>` with `$SCRATCH` (or the literal path) and `<project>` with
your project dir.

## Single-GPU MIG (Fir-style — H100 with MIG slices)

```bash
#!/bin/bash
#SBATCH --account=<your-gpu-account>
#SBATCH --gpus-per-node=h100_3g.40gb:1         # 40 GB MIG slice
#SBATCH --cpus-per-task=5                       # break-even for 3g on Fir
#SBATCH --mem=120G
#SBATCH --time=12:00:00
#SBATCH --output=<scratch>/slurm_logs/%x_%j.out

module load python/3.11.5
source <scratch>/<project>/.venv/bin/activate
python train.py [args...]
```

Available MIG slice names on Fir: `h100_1g.10gb`, `h100_2g.20gb`,
`h100_3g.40gb`. Use the smallest that fits your model — see `billing.md`
for break-even CPU counts.

## Single full GPU (Cedar V100 / Graham V100 / Narval A100 / Fir H100)

```bash
#!/bin/bash
#SBATCH --account=<your-gpu-account>
#SBATCH --gpus-per-node=1                       # any GPU on this cluster
#SBATCH --cpus-per-task=12                      # break-even for full H100; check cluster
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=<scratch>/slurm_logs/%x_%j.out

module load python/3.11.5 cuda/12.6
source <scratch>/<project>/.venv/bin/activate
python train.py [args...]
```

To target a specific GPU type (only one cluster has multiple types per node):
- Cedar: `--gres=gpu:p100:1` or `--gres=gpu:v100:1`
- Graham: `--gres=gpu:v100:1`, `--gres=gpu:t4:1`, `--gres=gpu:a100:1`, `--gres=gpu:a5000:1`
- Béluga / Narval: only one type, `--gpus-per-node=1` is enough
- Fir: `--gpus-per-node=h100:1` or use a MIG slice name

## Multi-GPU DDP (whole-node H100 / A100 / V100)

```bash
#!/bin/bash
#SBATCH --account=<your-gpu-account>
#SBATCH --gpus-per-node=h100:4                  # MUST specify type for whole GPUs
#SBATCH --ntasks-per-node=4                     # match GPU count for DDP
#SBATCH --cpus-per-task=12                      # break-even per H100
#SBATCH --mem=0                                  # all node memory
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --job-name=<job_name>
#SBATCH --output=<scratch>/slurm_logs/%x_%j.out
#SBATCH --error=<scratch>/slurm_logs/%x_%j.err

module load python/3.11.5 cuda/12.6
source <scratch>/<project>/.venv/bin/activate

export MASTER_ADDR=localhost
export MASTER_PORT=29500
export NCCL_DEBUG=INFO

torchrun --nproc_per_node=4 --master_port=$MASTER_PORT main.py \
    --distributed [args...]
```

**Key rules:**
- `--gpus-per-node=h100:4` (or `v100:8`, `a100:4` per cluster) — always specify the GPU type for whole-GPU jobs.
- `--mem=0` allocates all node memory; recommended for whole-node GPU jobs.
- `--ntasks-per-node` must match `--nproc_per_node` in torchrun.
- Use different `--master_port` values when submitting multiple jobs simultaneously.

### Pitfall: hardcoded MASTER_PORT in the model code

Many training scripts hardcode `os.environ['MASTER_PORT']` at the top of
`main.py`. When launched with `torchrun`, this **overwrites** the port torchrun
is actually listening on, causing `dist.init_process_group` to hang for 1800s
then timeout with:
```
[E socket.cpp:922] The client socket has timed out after 1800s while trying to connect to (127.0.0.1, <wrong_port>)
```

**Fix:** before submitting, check `main.py` for hardcoded `os.environ`
assignments and guard them:
```python
# WRONG — breaks torchrun
os.environ['MASTER_ADDR'] = 'localhost'
os.environ['MASTER_PORT'] = '28890'

# RIGHT — respect torchrun's env vars
if 'MASTER_ADDR' not in os.environ:
    os.environ['MASTER_ADDR'] = 'localhost'
if 'MASTER_PORT' not in os.environ:
    os.environ['MASTER_PORT'] = '28890'
```

### Pitfall: `mp.spawn` + `torchrun` double-spawn

If the script uses `--distributed` with `mp.spawn` internally, but you also
use `torchrun --nproc_per_node=4`, processes are spawned twice. Detect with
`LOCAL_RANK` env var:
```python
if "LOCAL_RANK" in os.environ:
    # torchrun path — use env-based init
    dist.init_process_group(backend="nccl")
elif args.distributed:
    # mp.spawn path — legacy TCP rendezvous
    mp.spawn(main_worker, ...)
```

## Interactive job (smoke test, debug, dev)

```bash
salloc --account=<your-gpu-account> \
       --gpus-per-node=h100_2g.20gb:1 \
       --cpus-per-task=3 --mem=40G --time=2:00:00
# you land in a shell on the compute node
```

Or via `srun` for a one-shot:
```bash
srun --account=<your-gpu-account> --gpus-per-node=h100_2g.20gb:1 \
     --cpus-per-task=3 --mem=40G --time=1:00:00 --pty bash
```

**Cancel when stepping away** — idle interactive billing tanks LevelFS for the whole lab.

## CPU-only long job (data prep, archiving, conversion)

```bash
#!/bin/bash
#SBATCH --account=<your-cpu-account>
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=18:00:00
#SBATCH --output=<scratch>/slurm_logs/%x_%j.out

module load python/3.11.5
source <scratch>/<project>/.venv/bin/activate
python convert_dataset.py [args...]
```

## PyTorch version requirement for H100 / L40s / A100

H100 is SM 9.0 (sm_90), L40s is SM 8.9 (sm_89), A100 is SM 8.0 (sm_80) —
all require PyTorch ≥ 2.2. PyTorch 2.1.x and earlier fail with "CUDA kernel
image not found" or similar. Affects Fir / Rorqual / Killarney H100 jobs and
Killarney L40s jobs and Narval / Graham A100 jobs.
