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
git clone <url> ~/.dotfiles
cd ~/.dotfiles
mkdir -p .local && cp .env.example .local/.env.local
```

Then edit `.local/.env.local` and fill in your API key and git identity:

```ini
PERSONAL_OPENCODE_API_KEY="sk-your-key-here"
GIT_AUTHOR_NAME="Your Name"
GIT_AUTHOR_EMAIL="your@email.com"
```

### 2. Run the install script

```bash
./install.sh
```

That's it. The script handles everything end-to-end:
- Xcode Command Line Tools, Homebrew, Oh My Zsh
- Apps and CLI tools from Brewfile
- Symlinks all config files
- VS Code settings and extensions
- SDKMAN, Java, Gradle
- opencode config
- SSH key generation + GitHub CLI auth + upload
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
| 7 | Runs topic installers (VS Code, SDKMAN, opencode, git) | Checks before installing |
| 8 | Points iTerm2 preferences to dotfiles | Skips if already set |
| 9 | Applies macOS defaults | Re-applies every run |

### Installed software

| Category | Items |
|----------|-------|
| **Homebrew CLI** | git, gh, node, opencode, wget, mas |
| **Apps (casks)** | Visual Studio Code, iTerm2, DBeaver, Rancher, Firefox, Obsidian, Anki, The Unarchiver |
| **Mac App Store** | Xcode |
| **SDKMAN** | Java 11 (Temurin), Gradle 7.6.4 |
| **VS Code extensions** | Python, Java, Go, GitLens, Copilot, Vim bindings, Material Icons, Prettier, ESLint, Tailwind, Live Server, and more |
| **Shell** | Oh My Zsh + aliases for git, node, docker, tmux, general |

## Structure

```
~/.dotfiles/
├── install.sh              # One-command installer
├── .zshrc                  # Main zsh config (→ .local/.zshrc → ~/.zshrc)
├── .env.example            # Template for secrets (→ .local/.env.local)
├── Brewfile                # Homebrew dependencies (declarative)
├── .gitignore               # Repo-level ignores
├── .local/                 # Generated machine files (gitignored)
├── bin/
│   └── dot                 # Utility: dot bootstrap|update
├── script/
│   └── bootstrap           # Copy templates to .local/, symlink to $HOME
├── opencode/
│   ├── opencode.jsonc      # Config (API key via {env:…})
│   └── install.sh          # Symlinks to ~/.config/opencode/
├── git/
│   ├── aliases.zsh         # Git aliases (gs, gc, gl, gp, …)
│   ├── gitconfig.symlink   # → .local/gitconfig → ~/.gitconfig
│   ├── gitignore_global.symlink  # → .local/gitignore_global → ~/.gitignore_global
│   └── install.sh          # Reads ~/.env for identity + SSH key setup
├── mac/
│   ├── defaults.symlink    # macOS system defaults (declarative)
│   └── install.sh          # Applies macOS defaults
├── zsh/
│   ├── aliases.zsh         # Shell aliases
│   ├── path.zsh            # PATH setup
│   └── config.zsh          # Shell options
├── vscode/
│   ├── settings.json       # Editor settings
│   └── install.sh          # Symlinks settings + installs extensions
├── iterm2/
│   └── restore.sh          # Point iTerm2 to dotfiles prefs
├── node/
│   └── aliases.zsh         # npm/yarn aliases
├── java/
│   ├── path.zsh            # SDKMAN setup
│   └── install.sh          # Installs SDKMAN, Java 11, Gradle
├── docker/
│   └── aliases.zsh         # Docker aliases
├── tmux/
│   ├── aliases.zsh         # tmux aliases
│   └── tmux.conf.symlink   # → .local/tmux.conf → ~/.tmux.conf
└── vim/
    └── vimrc.symlink       # → .local/vimrc → ~/.vimrc
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

The dotfiles **never** store secrets in tracked files. Secrets live in `.local/.env.local` (gitignored). The opencode config uses `{env:PERSONAL_OPENCODE_API_KEY}` to read from the environment at runtime.

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
3. Run `./install.sh`
4. Sign in to Firefox Sync
5. Done

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
- **Decision:** `opencode/opencode.jsonc:6` uses
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

### SSH keys are generated with a passphrase, stored in the macOS keychain
- **Decision:** `git/install.sh:45` runs `ssh-keygen -t ed25519 -C "$email"
  -f "$SSH_KEY"` (no `-N ""`), so the user is prompted once for a
  passphrase. The same script then calls
  `ssh-add --apple-use-keychain "$SSH_KEY"` so the passphrase is only
  needed once on first use.
- **Rejected:** the original `-N ""` generated an unencrypted private key
  with `0600` as the only barrier. Any process running as the user (or a
  `tar` of `~/.ssh`) would yield instant GitHub access via the key this
  script then auto-uploads. The passphrase adds a second factor at rest.

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

## Resources

- [Getting Started with Dotfiles](https://driesvints.com/blog/getting-started-with-dotfiles/)
- [Dotfiles Are Meant to Be Forked](https://zachholman.com/2010/08/dotfiles-are-meant-to-be-forked/)
- [Mathias Bynens' .macos](https://github.com/mathiasbynens/dotfiles/blob/master/.macos)