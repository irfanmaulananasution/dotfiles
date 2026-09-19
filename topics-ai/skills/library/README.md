# Shared skill library (cross-tool)

Skills in this directory are read by **every** AI tool on the machine, not just
Hermes. `topics-ai/skills/install.sh` symlinks `~/.agents/skills` here, and
`~/.agents/skills` is the cross-tool convention path that OpenCode scans natively
(OpenCode also scans `~/.config/opencode/skills/` and `~/.claude/skills/`).
Hermes reads it via `skills.external_dirs`, in addition to its own
`~/.hermes/skills/` — which stays primary and wins on a name collision.

## What belongs here

Only skills **you author** (source `local`). Upstream/hub skills — Hermes
builtins, official, clawhub, url — are **not** vendored into this repo; their
provenance is recorded in `../manifest` and Hermes installs them itself. See the
policy note at the top of that file.

## Adding a skill

```
library/
└── my-skill/
    ├── SKILL.md          # required
    ├── references/       # optional
    └── scripts/          # optional
```

1. Create `library/<skill-name>/SKILL.md`.
2. **The directory name MUST equal the frontmatter `name`.** Both OpenCode and
   the Agent Skills spec enforce this; a mismatch means the skill is silently
   ignored by OpenCode even though Hermes still loads it. Minimum frontmatter:

   ```yaml
   ---
   name: my-skill
   description: Use when <trigger>. <one-line behaviour>.
   ---
   ```

3. Add a row to `../manifest` with `tools=hermes,opencode` and identifier `-`.
4. Re-run `bash topics-ai/skills/install.sh` (or `./install.sh`), or validate
   directly: `python3 topics-ai/skills/scripts/validate-skills.py`.
