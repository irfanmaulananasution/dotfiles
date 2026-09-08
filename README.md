# dotfiles

Personal dotfiles — topical organization for macOS + zsh + Oh My Zsh.

Inspired by [holman/dotfiles](https://github.com/holman/dotfiles), [driesvints/dotfiles](https://github.com/driesvints/dotfiles), and [ryanb/dotfiles](https://github.com/ryanb/dotfiles).

## Requirements

- macOS (Sequoia or later recommended)
- Internet connection
- Apple ID (for Mac App Store apps)

## Quick Start

### 1. Clone and set up

```bash
git clone https://github.com/irfanmaulananasution/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
mkdir -p .local && cp .env.example .local/.env.local
```

Then edit `.local/.env.local` and fill in both API keys, your database password,
and git identity:

```ini
PERSONAL_OPENCODE_API_KEY="sk-your-key-here"
PERSONAL_DEEPSEEK_API_KEY="sk-your-deepseek-key-here"
PHOENIX_DB_PASSWORD="use-a-unique-password"
GIT_AUTHOR_NAME="Your Name"
GIT_AUTHOR_EMAIL="your@email.com"
```

### 2. Run the install script

```bash
./install.sh
```

Start Docker Desktop or Rancher Desktop and wait for the Docker daemon before
running the installer. The script handles the macOS setup end-to-end:
- Xcode Command Line Tools, Homebrew, Oh My Zsh
- Apps and CLI tools from Brewfile
- Symlinks all config files
- VS Code settings and extensions
- SDKMAN and Java 21; Gradle is intentionally not installed globally
- opencode config
- SSH key generation plus optional GitHub CLI auth/upload; interactive steps may be required
- macOS defaults

## What install.sh does

| Step | What | Idempotent? |
|------|------|-------------|
| 1 | Installs Xcode Command Line Tools | Skips if already installed |
| 2 | Installs Homebrew | Skips if already installed |
| 3 | Installs Oh My Zsh | Skips if already installed |
| 4 | Symlinks `~/.zshrc` → dotfiles | Only updates if different |
| 5 | Runs `brew bundle` (Brewfile) | Brew handles idempotency |
| 6 | Symlinks all `.symlink` files via `bootstrap` | Skips if already linked |
| 7 | Runs all discovered topic installers | Individual prerequisites are validated |
| 8 | Points iTerm2 preferences to dotfiles | Skips if already set |
| 9 | Applies macOS defaults | Re-applies every run |

### Installed software

| Category | Items |
|----------|-------|
| **Homebrew CLI** | git, bash, gh, node, opencode, caddy, uv, wget, mas |
| **Apps (casks)** | Visual Studio Code, iTerm2, DBeaver, Rancher, Firefox, Obsidian, Anki, The Unarchiver |
| **Mac App Store** | Xcode |
| **SDKMAN** | Java 21 LTS (Temurin) by default — bumpable via `JAVA_VERSION` env var. No global Gradle (per-project wrapper is the modern convention) |
| **VS Code extensions** | Python, Java, GitLens, Copilot + Copilot Chat, Prettier, ESLint, EditorConfig, Pylance, Auto Rename Tag, Material Icons, Markdown Preview, Remote SSH |
| **Shell** | Oh My Zsh + aliases for git, node, docker, tmux, general |

## Structure

```
~/.dotfiles/
├── install.sh                   # One-command installer
├── .zshrc                       # Main zsh config (→ .local/.zshrc → ~/.zshrc)
├── .env.example                 # Template for secrets (→ .local/.env.local)
├── AGENTS.md                    # Repo conventions for AI agents
├── TODO.md                      # Personal setup backlog
├── Brewfile                     # Homebrew dependencies (declarative)
├── .gitignore                   # Repo-level ignores
├── .pre-commit-config.yaml      # gitleaks hook to block secrets on commit
├── .local/                      # Generated machine files (gitignored)
├── bin/
│   └── dot                      # Utility: dot bootstrap|install|update|macos
├── script/
│   └── bootstrap                # Copy templates to .local/, symlink to $HOME
├── topics-ai/
│   ├── hermes/
│   │   ├── install.sh           # Idempotent Hermes Agent installer (core + model + MCP + plugins + skills)
│   │   ├── MANIFEST.md          # Runtime record of everything installed
│   │   └── scripts/
│   │       └── hermes-evolve-skill  # PATH launcher for the self-evolution tool
│   ├── opencode/
│   │   ├── opencode.jsonc       # Providers point to LiteLLM; keys via {env:…}
│   │   ├── scripts/
│   │   │   └── opencode-web.sh  # Headless `opencode serve` wrapper (launchd)
│   │   └── install.sh           # Symlink config + web auto-start
│   └── litellm/
│       ├── config.yaml          # Model routes (per-provider sections)
│       ├── docker-compose.yml   # postgres + phoenix + litellm + enrich + eval-accuracy
│       ├── Dockerfile           # LiteLLM proxy image (also used by sidecars)
│       ├── Dockerfile.phoenix   # Arize Phoenix image
│       ├── docker-entrypoint.sh # Applies OTEL_ENDPOINT and monkey patch at startup
│       ├── monkey_patch.py      # DeepSeek cache fields + CostSpanProcessor
│       ├── otel_utils.py        # Shared pricing/parse helpers (MODEL_PRICING)
│       ├── db/
│       │   ├── init.sql         # Create litellm DB on first postgres startup
│       │   ├── pricing.sql      # Phoenix generative_models + token_prices seeds
│       │   └── evaluators.sql   # Phoenix task_accuracy evaluator seeds
│       ├── scripts/
│       │   ├── enrich_spans.py  # Sidecar: token promotion + sessions
│       │   └── evaluate_accuracy.py  # Sidecar: LLM-as-judge accuracy annotations
│       ├── install.sh           # Generate env in .local/, bring up the stack, seed Phoenix
│       └── README.md            # Full architecture/operations guide for the stack
├── k8s/
│   ├── namespace.yaml           # llm-stack namespace
│   ├── postgres.yaml            # Postgres StatefulSet + Service
│   ├── phoenix.yaml             # Phoenix Deployment + Service
│   ├── litellm.yaml             # LiteLLM Deployment + Service
│   ├── kustomization.yaml       # Ties manifests + secretGenerator
│   ├── .env.example             # Template for kustomize's secret env file
│   └── setup.sh                 # Generate .local/k8s.env.local, apply, delete temp .env
├── caddy/
│   ├── Caddyfile                # https://*.localhost → local services
│   └── install.sh               # Symlink config, clean up old hosts entries, start Caddy
├── git/
│   ├── aliases.zsh              # Git aliases (gs, gc, gl, gp, …)
│   ├── gitconfig.symlink        # → .local/gitconfig → ~/.gitconfig
│   ├── gitignore_global.symlink # → .local/gitignore_global → ~/.gitignore_global
│   └── install.sh               # Reads ~/.env for identity + SSH key setup
├── mac/
│   ├── defaults.symlink         # macOS system defaults (declarative)
│   ├── startup.symlink          # → .local/startup → ~/.startup (launchd on login)
│   └── install.sh               # Apply defaults + register startup LaunchAgent
├── firefox/
│   └── install.sh               # Vertical tabs, extensions, bookmarks via user.js
├── rancher/
│   ├── settings.json            # Rancher Desktop settings
│   └── install.sh               # Apply Rancher Desktop settings
├── zsh/
│   ├── aliases.zsh              # Shell aliases
│   ├── path.zsh                 # PATH setup
│   └── config.zsh               # Shell options
├── vscode/
│   ├── settings.json            # Editor settings
│   └── install.sh               # Symlink settings + install extensions
├── iterm2/
│   ├── com.googlecode.iterm2.plist.template
│   └── restore.sh               # Point iTerm2 at the dotfiles prefs
├── node/
│   └── aliases.zsh              # npm/yarn aliases
├── java/
│   ├── path.zsh                 # SDKMAN setup
│   └── install.sh               # Install SDKMAN, Java 21 LTS (Temurin)
├── docker/
│   └── aliases.zsh              # Docker aliases
├── tmux/
│   ├── aliases.zsh              # tmux aliases
│   └── tmux.conf.symlink        # → .local/tmux.conf → ~/.tmux.conf
└── vim/
    └── vimrc.symlink            # → .local/vimrc → ~/.vimrc
```

### How it works

- **`.zsh` files** in topic dirs are auto-loaded by Oh My Zsh (via `ZSH_CUSTOM=$DOTFILES`)
- **`.symlink` files** (plus `.zshrc`) are copied to `.local/` then symlinked to `$HOME` by `script/bootstrap`
- **`install.sh`** in topic dirs run automatically during setup
- **`bin/dot`** is a convenience utility for maintenance

### Template vs local pattern

Templates (`.zshrc`, `.symlink` files) stay in the repo as the source of truth. When `bootstrap` runs, it copies them to `.local/` and symlinks from `$HOME` to the copy:

```
repo/.zshrc              →  .local/.zshrc       →  ~/.zshrc
repo/git/gitconfig.symlink   →  .local/gitconfig     →  ~/.gitconfig
repo/vim/vimrc.symlink       →  .local/vimrc         →  ~/.vimrc
repo/mac/defaults.symlink    →  .local/defaults      →  (sourced by topic installer)
```

This means if a tool modifies `~/.zshrc` or you run `git config --global`, it only touches the copy in `.local/` — never the template. Edits to the template only take effect after running `dot bootstrap`. `.local/` is gitignored, so machine-specific changes stay local.

### Per-machine exclusion

To skip a topic on a specific machine, rename the directory (e.g., `mv docker docker.skip`). Excluded topics won't be sourced by OMZ and their installers won't run.

## Secrets & API Keys

The dotfiles **never** store secrets in tracked files. Secrets live in `.local/.env.local` (gitignored and restricted to mode `0600`). The opencode config uses `{env:PERSONAL_OPENCODE_API_KEY}` to read from the environment at runtime.

The observability stack captures full prompt and response message content in
Phoenix/Postgres. The optional accuracy evaluator sends sampled content to the
configured DeepSeek judge API. Do not enable these services for sensitive data
unless that external processing is acceptable.

### Setup

```bash
# Create your env file from the template (first time only)
mkdir -p .local && cp .env.example .local/.env.local

# Fill in your values, then the installer will symlink ~/.env → .local/.env.local
```

`.zshrc` loads it automatically:
```zsh
if [[ -f "$HOME/.env" ]]; then
  set -a
  source "$HOME/.env"
  set +a
fi
```

### Adding more secrets

Add any environment variables to `.local/.env.local`:
```ini
PERSONAL_OPENCODE_API_KEY="sk-..."
GITHUB_TOKEN="ghp_..."
```

## Manual Steps (Firefox)

These can't be automated:

1. **Sign in to Firefox Sync** to restore bookmarks and history
2. **Install extensions:**
   - [uBlock Origin](https://addons.mozilla.org/firefox/addon/ublock-origin/)
   - [Video DownloadHelper](https://addons.mozilla.org/firefox/addon/video-downloadhelper/)

## Maintenance

```bash
dot bootstrap   # Re-symlink all config files
dot update      # brew update && brew upgrade && brew cleanup
dot macos       # Re-apply macOS defaults (runs mac/install.sh)
```

## Moving to a new Mac

1. Clone this repo to `~/.dotfiles`
2. Run `mkdir -p .local && cp .env.example .local/.env.local` and fill in your secrets
3. Start Docker Desktop or Rancher Desktop
4. Run `./install.sh`
5. Sign in to Firefox Sync
6. Done

## Design Decisions

This section records the non-obvious security and architecture decisions made
through the project's evolution, including the ones that were reversed. Sourced
from the security audit cycle (`SECURITY-AUDIT.md` → `...-V2.md` →
`...-V3.md`). Each entry lists *why* the decision was made and *why the
alternatives were rejected*.

### Secrets live in `.local/.env.local`, never in tracked files
- **Decision:** `.env.example` ships a redacted template (`sk-`). Real keys go
  in `.local/.env.local`, which is gitignored by `.gitignore:2` (`.local/`).
  `script/bootstrap` symlinks `~/.env` → `.local/.env.local`, and `.zshrc`
  sources `~/.env` at shell startup.
- **Rejected:** committing a `.env` with real keys (leaks to anyone with repo
  access); committing a `.env` with placeholder keys and no symlink path
  (forces per-machine duplication of the whole file).
- **Audit history:** flagged CRITICAL in V1 after keys surfaced in a review
  session. Mitigation is rotation (manual, at the provider) plus the gitleaks
  pre-commit hook (`.pre-commit-config.yaml`) as a staging-boundary guard.

### opencode config reads keys via `{env:…}`, not inline strings
- **Decision:** `topics-ai/opencode/opencode.jsonc:6` uses
  `"apiKey": "{env:PERSONAL_OPENCODE_API_KEY}"` so the secret is resolved
  from the environment at runtime and never written to the tracked config.
- **Rejected:** pasting the key into `opencode.jsonc` (would be committed).

### `.zshrc` uses `set -a; source "$HOME/.env"; set +a` to load secrets
- **Decision:** load the env file with `source` while `set -a` (allexport) is
  on, then turn it off. This is the original pattern; it was briefly replaced
  by a `while IFS= read` loop and then reverted.
- **Why `source` and not a hand-rolled loop:** `source` parses each line as
  *shell code*, so `KEY="value"` yields `value` (quotes stripped) and
  `ALIAS=$KEY` yields the *value of KEY* (reference expanded). A
  `while IFS= read` loop cannot do this without `eval`, and the two naive
  forms the audit tried both broke:
  - `IFS='=' read -r k v; export "$k=$v"` — leaves literal `"` chars in the
    value (opencode gets `"sk-…"` and auth fails) and does not expand `$KEY`
    references (`PERSONAL_API_KEY` becomes the 26-char string
    `$PERSONAL_OPENCODE_API_KEY`).
  - `export "${line}"` — *also* leaves quotes intact; `export` does not
    perform shell quote-removal. Verified empirically in the V3 audit.
- **Why not `eval` the loop:** `eval "$line"` does work but offers no
  advantage over `source` for a 0600 owner-owned file, while adding an
  injection surface if the env file is ever world-writable or sourced by
  accident from an untrusted path.
- **Accepted trade-off:** `set -a` briefly exports *every* var defined
  while it's on, so keys are visible via `env` to any spawned subprocess.
  This is inherent to the env-var approach opencode expects; the audit rated
  it LOW. Scoping exports to named vars was considered and rejected as
  not worth the complexity versus the `source` primitive that provably
  works.

### iTerm2 preferences: template-in-repo, instance-in-`.local/`
- **Decision:** `iterm2/com.googlecode.iterm2.plist.template` is a curated,
  minimal plist tracked in git. `iterm2/restore.sh` copies it into
  `.local/iterm2/com.googlecode.iterm2.plist` on first run and points iTerm2
  at that folder via `PrefsCustomFolder`.
- **Rejected:** the original `iterm2/install.sh` blindly `cp`'d the *full*
  machine plist into `iterm2/` (tracked dir). iTerm2 plists routinely
  contain profile commands, SSH host aliases, and pasted secrets, and
  `.gitignore` did not exclude them — a fork-and-`git add -A` would commit
  the user's private prefs.
- **Why a subfolder:** `.local/iterm2/` keeps the plist out of the same
  directory as `.env.local` and `.zshrc` (defense-in-depth; iTerm2 only
  reads its own named file from there, so there is no actual leak).
- **Audit history:** HIGH in V1, applied in the V1→V2 round, V3 confirmed
  the V2 minor bug (`Working Directory` = `/Users/$USER`, which iTerm2 does
  not expand) was also fixed to an empty string.

### `curl | bash` installers are pinned to immutable commit SHAs, not `HEAD`
- **Decision:** `install.sh:30` and `install.sh:46` download the Homebrew and
  Oh My Zsh installers from `raw.githubusercontent.com` at a hardcoded
  40-char commit SHA (`BREW_COMMIT`, `OMZ_COMMIT`), execute from `/tmp`,
  then delete. SDKMAN (`java/install.sh:9`) remains `curl … | bash` because
  `get.sdkman.io` is a stable redirect with no version tag to pin against.
- **Rejected:** the original `.../HEAD/install.sh` and `.../master/install.sh`
  — both are moving refs that track the latest branch commit, so a
  compromised branch or DNS hijack becomes RCE in the shell that
  subsequently loads API keys and SSH keys.
- **Why not `shasum -c` on top:** would require hardcoding a SHA-256 of the
  installer. A hash fetched on the same network path as the file is only
  marginal defense over TLS + Git's content-addressing (a pinned commit SHA
  returns 404 from GitHub if the underlying blob is mutated). Not worth the
  stale-hash maintenance burden.

### Homebrew casks require SHA-256 verification
- **Decision:** `Brewfile:2` is `cask_args require_sha: true`.
- **Rejected:** the original `require_sha: false` — a global downgrade of
  integrity checks for every GUI app, so a tampered/mirror-compromised
  download installs without warning. If a specific cask legitimately lacks
  a checksum, it should be handled individually, not by disabling
  verification globally.

### SSH keys are generated without a passphrase
- **Decision:** `git/install.sh:45` runs `ssh-keygen -t ed25519 -C "$email"
  -f "$SSH_KEY" -N ""`, so the key is created without a passphrase.
  This avoids prompting during automated installs and CI-like provisioning.
- **Trade-off:** no passphrase means the private key on disk (`0600`) is the
  only barrier. A process running as the user or a backup of `~/.ssh` would
  yield immediate GitHub access. Acceptable because the dotfiles are for a
  single-user personal machine, not a shared environment.

### Global gitignore covers all `.env.*` variants
- **Decision:** `git/gitignore_global.symlink:13-16` is
  `.env` / `.env.*` / `!.env.example` / `.localrc`.
- **Rejected:** the original only ignored `.env` and `.localrc`, which
  missed `.env.local` (the de-facto Next.js/Vite local-secrets filename) and
  `.env.production`, `.env.staging`, etc. Those could be `git add`-ed into a
  project's history by accident. The `!.env.example` negation keeps
  templates trackable.

### A pre-commit gitleaks hook guards the staging boundary
- **Decision:** `.pre-commit-config.yaml` runs `gitleaks` (rev `v8.21.2`)
  on every commit, blocking anything matching a known secret pattern from
  entering history. Install once after cloning:
  `brew install pre-commit && pre-commit install`.
- **Why:** `.gitignore` is voluntary; a stray `git add -f .local/.env.local`
  would still commit keys. The hook is the enforcement layer, added in
  response to the V1 audit's CRITICAL finding that plaintext keys had
  surfaced in a review session. Defense-in-depth, not a replacement for
  careful `.gitignore` hygiene.

### `BREW_COMMIT` / `OMZ_COMMIT` must be refreshed manually
- **Decision (and its cost):** the pinned commit SHAs in `install.sh` go
  stale by design. They should be refreshed quarterly (or when an upstream
  security fix lands). Bumping is a one-line edit per ref. The trade-off is
  deliberate: immutability now, manual maintenance later, versus a moving
  ref that silently tracks whatever the upstream branch points at.

## Design Decisions — V4 configuration refactor

A refactor pass over vim / tmux / macOS / Java / git / vscode / zsh. Each scope
was rewritten by pulling in best practices from a canonical external
reference, then pruning anything subjective or risky. References cited inline.

### Java defaults to Java 21 LTS, no global Gradle
- **Decision:** `java/install.sh` installs SDKMAN and a single Java LTS
  (`21.0.5-tem` by default), overridable via the `JAVA_VERSION` env var.
  Global Gradle is intentionally **not** installed.
- **Why no Gradle:** since Gradle 4.x, the per-project Gradle Wrapper
  (`./gradlew`, committed to the repo) is the canonical way to run Gradle.
  A global `gradle` on `$PATH` silently overrides the wrapper's pinned
  version and is a leading cause of "works on my machine" drift. The
  previous behavior pinned `Gradle 7.6.4` globally, which would shadow every
  project's wrapper. To install a specific Gradle for a one-off, the script
  prints the exact `sdk install gradle <version>` command to run manually.
- **Why Java 21 specifically:** the current LTS in widest production use
  (released Sept 2023, supported through Sept 2028 per Oracle's roadmap).
  Java 25 LTS (Sept 2025) is also out; bump the `JAVA_VERSION` variable
  one line if you prefer it.
- **References:** SDKMAN install docs
  (<https://sdkman.io/install>, 2026 — confirms `curl -s "https://get.sdkman.io" | bash` remains the official install path); Gradle Wrapper docs
  (<https://docs.gradle.org/current/userguide/gradle_wrapper.html>).

### `vim/vimrc.symlink` — thoughtbot-inspired defaults, no plugin manager
- **Decision:** expanded the 20-line vimrc to ~50 lines, adding settings
  thoughtbot/dotfiles ships by default (`vimrc`, master branch): `encoding=utf-8`,
  `backspace=indent,eol,start`, `ruler`, `showcmd`, `laststatus=2`,
  `autowrite`, `filetype plugin indent on`, `nojoinspaces`, `shiftround`,
  `splitbelow splitright`, plus a security hardening (`modelines=0`,
  `nomodeline` — modeline parsing has been a recurring vim vulnerability
  surface, e.g. CVE-2019-12735).
- **Rejected:** thoughtbot's full `vimrc` pulls in ALE, FZF, vim-fugitive,
  Catppuccin — those need a plugin manager (`vimrc.bundles`), which the user
  explicitly opted out of ("balanced, no plugin manager"). Sticking to
  built-in `:set` options only.
- **Reference:** <https://github.com/thoughtbot/dotfiles/blob/master/vimrc>.

### `tmux/tmux.conf.symlink` — gpakosz essentials, default prefix
- **Decision:** added the universally-recommended settings from
  gpakosz/.tmux (master): `escape-time 10` (removes vim-keys lag inside
  tmux), `focus-events on` (so vim/nvim inside tmux sees focus changes),
  `default-terminal "screen-256color"`, `automatic-rename on`,
  `renumber-windows on` (close gaps), `set-titles on`, `monitor-activity
  on`, and `-r` (repeatable) prefix on the vim-style pane bindings.
- **Rejected:** gpakosz's full ~500-line config (theme code, battery
  integration, copy-to-X11/Wayland clipboard, the elaborate
  `_apply_configuration` shell-embedded function) — far too opinionated
  for "balanced" and most of it is cosmetic statusline theming.
- **Rejected:** remapping the prefix to `C-a` (gpakosz's `prefix2`) — too
  opinionated, conflicts with readline's `C-a` (beginning-of-line).
- **Reference:** <https://github.com/gpakosz/.tmux/blob/master/.tmux.conf>.

### macOS defaults — mathiasbynens-style, scoped to safe + coder-friendly
- **Decision:** rewrote `mac/defaults.symlink` to selectively include
  mathiasbynens/`.macos` items. Kept the existing ones and added: keyboard
  repeat acceleration, full keyboard access (`AppleKeyboardUIMode=3`),
  save-to-disk-not-iCloud, plain-text UTF-8 TextEdit, disable caps/period
  substitution, `FXEnableExtensionChangeWarning=false`,
  `DSDontWriteUSBStores=true`, Activity Monitor CPU-usage Dock icon,
  hot-corner top-right = Mission Control, screen-saver immediate password
  requirement, hidden `~/Library` and `/Volumes` unhide.
- **Rejected (security):** `LSQuarantine=false` (disables macOS's
  "downloaded from internet" warning — a security gate), disk-image
  verification skips (`skip-verify*`), Secure Keyboard Entry off.
- **Rejected (intrusive):** `sudo nvram SystemAudioVolume=" "` (T2/Secure
  Boot macs can refuse it), Spotlight rebuild via `sudo mdutil -E /`
  (triggers a full reindex on every install), `sudo systemsetup` timezone
  change (hardware/locale-specific), `sudo rm /private/var/vm/sleepimage`
  (filesystem surgery for marginal space win), Notification Center
  unload, Time Machine disable. All of these are either risky or step on
  per-user preference.
- **Kept:** the `sudo -v` upfront + keep-alive loop (the existing
  pattern). Used only for `sudo chflags nohidden /Volumes` and
  `chflags nohidden ~/Library`. Everything else is user-defaults (no
  sudo).
- **Reference:** <https://github.com/mathiasbynens/dotfiles/blob/master/.macos>.

### `git/gitconfig.symlink` — thoughtbot essentials, no workflow imposition
- **Decision:** added thoughtbot's universal wins: `core.autocrlf=input`
  (cross-platform line-ending safety), `core.quotepath=false` (literal
  non-ASCII filenames), `fetch.prune=true` (auto-prune deleted remote
  branches), `rebase.autosquash=true` (reorder `fixup!`/`squash!` commits
  automatically), `diff.colorMoved=zebra` (visualize code moves).
- **Rejected:** thoughtbot's `merge.ff=only` (forces fast-forward-only
  merges, blocking legitimate merge commits like vendored subtree
  merges) — that's a workflow decision for rebase-only teams, not a safe
  default. Removed before commit.
- **Rejected:** `commit.template = ~/.gitmessage` (thoughtbot ships one,
  but we don't ship a template file) and `include.path = ~/.gitconfig.local`
  (we already inject identity via `.local/gitconfig` from
  `git/install.sh`, an include would be redundant).
- **Reference:** <https://github.com/thoughtbot/dotfiles/blob/master/gitconfig>.

### `git/aliases.zsh` — dropped `gnuke` duplicate
- **Decision:** removed `gnuke="git clean -df && git reset --hard"`.
- **Why:** it's an exact duplicate of `gclean`. The alias did not add
  behavior, only an alternate destructive name. Kept `gclean` (more
  descriptive) and `gforce` (uses `--force-with-lease`, which is the
  safer-than-`-f` form).

### `zsh/config.zsh` — history hygiene
- **Decision:** kept the existing options and added `HIST_IGNORE_SPACE`
  (commands prefixed with a space are not recorded — typing ` <secret>`
  keeps secrets out of history on disk), `HIST_FIND_NO_DUPS` (skip
  duplicates when navigating), `HIST_VERIFY` (show the expanded history
  line before running, so `!1234`-style recalls get a chance to be
  edited or aborted), `HIST_REDUCE_BLIPS` (drop superfluous entries).
- **Inherent in the choice:** `SHARE_HISTORY` (already present) writes
  every command to disk immediately and shares it across sessions; this
  is a feature for multi-window workflows but means anything in history
  is on disk fast — `HIST_IGNORE_SPACE` is the safety valve for that.

### `vscode/settings.json` — universal defaults, telemetry stays off
- **Decision:** added `files.insertFinalNewline`,
  `files.trimFinalNewlines`, `files.trimTrailingWhitespace` (POSIX
  compliance — files end with one newline and no trailing whitespace),
  `editor.rulers: [100]`, `search.exclude` (node_modules / dist / build
  / .git), `workbench.editor.enablePreview: false` (preview tabs are
  a frequent source of "where did my file go" confusion for new users).
- **Kept:** `telemetry.telemetryLevel: "off"` (already present) —
  non-negotiable for a config that ships in a dotfiles repo.
- **Rejected:** opinionated defaults like a specific formatter
  (`editor.defaultFormatter`), specific linters, per-language
  `formatOnSave` beyond json/jsonc, or theme overrides — all are
  project-specific and don't belong in shared user settings.

## Design Decisions — V5 cruft pass (de-dup this-laptop leftovers)

After the V4 refactor landed best practices, a further pass removed
laptop-specific cruft: dead aliases, redundant extensions installed twice,
legacy software flags, and project-specific tools masquerading as defaults.

### VS Code extensions: 9 dropped, 13 kept
- **Decision:** the previous `vscode/install.sh:21-45` list installed 22
  extensions. Trimmed to 13 by removing 9 in three categories.
- **Redundant (installed by the `vscjava.vscode-java-pack` meta-extension
  anyway):** `redhat.java`, `vscjava.vscode-java-debug`,
  `vscjava.vscode-java-maven`, `vscjava.vscode-gradle`. The Java pack
  bundles these — listing them separately caused `code --install-extension`
  to write a "already installed" error on every run. (Also aligns with the
  "no global Gradle" decision from V4.) Dropped 4.
- **Duplicate icon themes:** both `PKief.material-icon-theme` and
  `vscode-icons-team.vscode-icons` were installed — only one can be
  active at a time. Kept Material Icons (more modern, broader file-type
  coverage). Dropped 1.
- **Project-specific (should be per-project):**
  - `bradlc.vscode-tailwindcss` — only relevant to Tailwind projects.
  - `golang.go` — only relevant to Go projects.
  - `ms-toolsai.jupyter` — notebook workflow; auto-pulls Python deps.
  - `ritwickdey.LiveServer` — HTML static dev server; only relevant to
    HTML/CSS projects.
  These belong in a project's `.vscode/extensions.json` recommendations,
  masquerading as universal defaults in a dotfiles repo. Dropped 4.
- **Kept (universal or already-paid-for):** EditorConfig, GitLens,
  Prettier, ESLint, Copilot + Copilot-Chat (user has subscription),
  Markdown Preview GitHub Styles, auto-rename-tag, Material Icons,
  Python + Pylance, remote-ssh, the Java Pack (one bundle, not five),
  vim bindings.

### `zsh/aliases.zsh` — `alias ~="cd ~"` removed
- **Decision:** dropped the `~` alias.
- **Why:** `~` is expanded by zsh's filename-expansion phase *before*
  alias resolution fires, so the alias never actually triggered. More
  importantly, `zsh/config.zsh` already sets `setopt AUTO_CD`, which makes
  typing `~` + Enter cd into `$HOME` directly with no alias needed. The
  line was dead and redundant.

### `node/aliases.zsh` — yarn aliases removed
- **Decision:** dropped 6 yarn aliases (`y`, `ya`, `yad`, `yr`, `yb`,
  `yd`). Kept all 9 npm aliases.
- **Why:** yarn is not in the Brewfile, so the dotfiles don't install it.
  Yarn 1.x is in maintenance mode only; modern projects either stay on npm
  or move to pnpm. Keeping yarn-only aliases in a fresh-Mac install
  creates aliases for a binary that isn't there. Re-add by hand if you
  actually install yarn.

### `iterm2/com.googlecode.iterm2.plist.template` — `BM Growl` key removed
- **Decision:** dropped the `BM Growl` (Boolean true) entry from the
  iTerm2 plist template.
- **Why:** Growl was a third-party macOS notification system popular from
  ~2008-2014; it was deprecated in 2014 and removed from the Mac App
  Store in 2017. Modern macOS uses the native Notification Center, which
  iTerm2 supports without the `BM Growl` toggle. The flag was inert
  cruft from an earlier iTerm2 generation.

### `mac/defaults.symlink` — already clean
- Verified the V4 rewrite contains no this-laptop specifics: no hardcoded
  timezone, no custom hostname, no `sudo nvram`, no Spotlight rebuild,
  no `LSQuarantine=false`, no disk-image-verification bypass, no
  sleepimage surgery. Everything is user-defaults only. Nothing to clean
  up here.

### `Brewfile` — intentionally not edited
- The cask list (`obsidian`, `anki`, `the-unarchiver`, `dbeaver-community`,
  `rancher`) is personal preference, not redundancy. None of these are
  dead software or installed-twice. Removing any of them would be
  imposing a different opinion about apps the user actually uses, not
  "cleaning cruft." Left untouched; revisit per-app if you want to slim
  the fresh-Mac install.

## Resources

- [Getting Started with Dotfiles](https://driesvints.com/blog/getting-started-with-dotfiles/)
- [Dotfiles Are Meant to Be Forked](https://zachholman.com/2010/08/dotfiles-are-meant-to-be-forked/)
- [Mathias Bynens' .macos](https://github.com/mathiasbynens/dotfiles/blob/master/.macos)
