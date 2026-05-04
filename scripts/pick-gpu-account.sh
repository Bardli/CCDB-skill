#!/bin/bash
# Print the GPU account with the highest LevelFS from `sshare -U -l`.
# Works on any Alliance Canada cluster — uses generic SLURM commands only.
#
# Usage:
#   ./pick-gpu-account.sh
#   sbatch --account=$(./pick-gpu-account.sh) /path/to/job.sh
#
# Exits non-zero with an empty line if sshare fails or no *_gpu account matches.

set -euo pipefail

sshare -U -l --noheader --parsable2 \
  | awk -F'|' '$1 ~ /_gpu$/ { print $9, $1 }' \
  | sort -rn \
  | head -1 \
  | awk '{ print $2 }'
