# Local Skill Hub — Plan

Status: research done, not yet implemented.

## Problem

Skills are currently set up per-tool:

| Tool | Skill location |
|---|---|
| Hermes | `~/.hermes/skills/` |
| OpenCode | `~/.config/opencode/skills/` |
| Claude Code | `~/.claude/skills/` |

Authoring a skill once and having every tool use it means copying it into each
location by hand.

## Finding: a cross-tool standard already exists

- The **Agent Skills** open standard (https://agentskills.io/specification) is a
  `SKILL.md` file: YAML frontmatter (`name`, `description`, optional `license`,
  `compatibility`, `allowed-tools`) + a Markdown body. Adopted by Claude Code,
  OpenCode, Hermes, and others.
- The de-facto shared location is **`~/.agents/skills/`** — the "cross-tool
  convention" directory.
- **OpenCode** discovers it natively (its "global compatibility" sources are
  `~/.agents/skills` and `~/.claude/skills`).
- **Claude Code** reads `~/.claude/skills/` (same Agent Skills standard).
- **Hermes** reads extra directories via `skills.external_dirs` in
  `~/.hermes/config.yaml`, and already recognizes `~/.agents/skills/` as the
  cross-tool convention (it even scans `/.agents/skills/` in a project root).

So the shared format and the shared directory already exist. The work is just
wiring each tool to one place.

## Approach (secara rapih)

One canonical, git-tracked directory in the dotfiles repo, symlinked to the
cross-tool path, and every tool pointed at it.

```
~/.dotfiles/skills/                 # canonical, tracked (source of truth)
    my-workflow/
        SKILL.md
        references/ ...
        scripts/ ...

~/.agents/skills -> ~/.dotfiles/skills   # symlink (cross-tool convention)
```

Per tool:

- **Hermes** — add to `~/.hermes/config.yaml`:
  ```yaml
  skills:
    external_dirs:
      - ~/.agents/skills
  ```
- **OpenCode** — nothing required; `~/.agents/skills` is auto-discovered.
  (Optional: an explicit `skills` array in `opencode.json` if you want more
  control.)
- **Claude Code** — symlink its dir to the same place:
  `ln -s ~/.dotfiles/skills ~/.claude/skills`
  (or `claude --add-dir ~/.dotfiles/skills`).

## Caveats / decisions to make

- Hermes keeps `~/.hermes/skills/` as its primary dir (bundled + hub-installed +
  self-improvement skills live there). The shared dir is **additive**. Hermes
  creates new skills in `~/.hermes/skills/`; existing shared skills can still be
  edited in place when writable.
- Name collisions: a local Hermes skill shadows a shared skill of the same name.
- Tool-specific skills are fine — each tool advertises only skills whose
  `description` matches the task.
- Alternative for Hermes: register the dotfiles repo as a `hermes skills tap`
  (custom GitHub source) so `hermes skills install` can also pull from it —
  useful if you want hub-style installs rather than a filesystem path.

## Open questions

1. Canonical home: `~/.dotfiles/skills/` (in this repo) vs a separate dedicated
   repo (cleaner if you want to share it across machines/repos independently)?
2. Should shared skills also be mirrored into `~/.hermes/skills/` so Hermes
   self-improvement treats them as first-class, or kept strictly external?

## Implementation steps (pending approval)

1. `mkdir -p ~/.dotfiles/skills` (tracked)
2. `ln -s ~/.dotfiles/skills ~/.agents/skills`
3. Add `skills.external_dirs: [~/.agents/skills]` to `~/.hermes/config.yaml`
4. (optional) `ln -s ~/.dotfiles/skills ~/.claude/skills`
5. Author one sample skill; verify all three tools list it.

## References

- Agent Skills spec: https://agentskills.io/specification
- OpenCode skills: https://opencode.ai/docs/skills/
- Claude Code skills: https://code.claude.com/docs/en/skills
- Hermes skills (external_dirs): https://hermes-agent.nousresearch.com/docs/user-guide/features/skills
