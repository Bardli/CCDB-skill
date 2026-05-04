# CCDB-skill — Alliance Canada Clusters Skill for Claude Code

A Claude Code skill that loads cluster-specific guidance for **Alliance Canada**
(formerly Compute Canada / DRAC) HPC clusters. Auto-detects the active cluster
via `$CC_CLUSTER` and routes to the right reference file.

Covers (as of 2026-05): **Fir, Trillium, Rorqual, Cedar, Graham, Béluga,
Narval, Niagara, Killarney**. Each cluster's per-node hardware, GPU types,
login host, file-system layout, and known quirks live under
`references/clusters/<name>.md`. Generic SLURM / module / billing / Python
content lives under `references/`.

## What this skill enforces

- Always submit heavy work via `sbatch`; the login node is for `ls` and `module load`.
- Default GPU sizing prefers MIG slices (20–40 GB) over whole 80 GB cards unless the model needs it.
- Never `pip install --index-url …` for PyTorch — use the CCDB wheelhouse on `/cvmfs`.
- Run `seff <jobID>` after every job: LevelFS is shared with your lab group.
- Cluster choice: short jobs on Trillium, long jobs on Fir/Rorqual, AI on Killarney, large CPU-parallel on Niagara.

See `SKILL.md` for the full critical-rules table.

## Install (Claude Code)

Clone this repo into a stable location, then symlink it into your skills
directory so the harness picks it up:

```bash
git clone https://github.com/Bardli/CCDB-skill.git "$SCRATCH/CCDB-skill"

mkdir -p ~/.claude/skills
ln -s "$SCRATCH/CCDB-skill" ~/.claude/skills/ccdb-clusters
```

The skill name (`ccdb-clusters`) is set in the frontmatter of `SKILL.md`.

## Personal config (NOT in this repo)

This repo is generic — it does **not** contain your account names, venv paths,
or group memberships. Keep those in your local Claude memory at:

```
~/.claude/projects/<project>/memory/personal_cc_config.md
```

The skill references this path so future Claude sessions know to consult it.

## Updating

Most cluster facts come from <https://docs.alliancecan.ca/wiki/>. The wiki is
behind a JavaScript anti-bot challenge that can't be scraped programmatically;
we use the parsed-Markdown mirror at
<https://github.com/ermingpei/docs-alliancecan> as a snapshot, and timestamp
each per-cluster reference with the MediaWiki `oldid=` it was sourced from.
When you re-pull from the wiki for a specific cluster, bump the timestamp.

## Status of cluster pages (2026-05-04)

| Cluster | Status | Source for facts |
|---|---|---|
| Fir | Operational, this user is on it | Live skill content + mirror stub (oldid 164899) |
| Trillium | Operational, NOT in mirror | Drafted from training-data + onboarding bullets — **VERIFY** |
| Rorqual | Likely operational (mirror said "deploy winter-spring 2025") | Mirror stub (oldid 176376) — **VERIFY** |
| Cedar | Operational | Mirror (oldid 153230) |
| Graham | Reduced capacity, retiring; replaced by Nibi | Mirror (oldid 175647) |
| Béluga | Operational | Mirror |
| Narval | Operational | Mirror (oldid 164850) |
| Niagara | Operational, CPU-only | Mirror |
| Killarney | Vector/SciNet AI cluster, status was TBA in mirror | Mirror (oldid 174874) — **VERIFY** |

## License

The Alliance docs content adapted into per-cluster references is from the
Alliance MediaWiki, licensed under [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
This skill's structure and prose are MIT.
