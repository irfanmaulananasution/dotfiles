# Darwin/Nix state-management plan

Declarative state management for this Mac. The goal is a laptop whose state is
**reproducible from a manifest**, where an intentional change is "declare it →
commit it", and an accidental change is "reset → gone". Reset must **never**
mean factory-resetting macOS — it is a *soft reconcile* over the layers we own.

> Status: **plan / in-progress**. The repo already has the *declare* + *apply*
> half (Brewfile, `.symlink` templates, defaults, topic installers). What is
> missing is the *reconcile* (reset) half, the *capture* workflow, and the
> browser-extension story. The `nix-darwin` end-state is described but not yet
> implemented.

---

## 1. The mental model: three layers

Only layer 1 is ever in git. Layers 2 and 3 are never committed.

| Layer | Name | Meaning | Where it lives |
|---|---|---|---|
| 1 | **Declared** (intent) | The source of truth — what you *want* | `~/.dotfiles` (git) |
| 2 | **Derived** (regenerable) | Produced by applying layer 1 — installed apps, symlinked configs, generated env files | not in git; rebuilt by `install.sh` / `bootstrap` |
| 3 | **Transient** (junk) | Caches, logs, saved state, derived data | not in git; safe to wipe |

Rules:

- `git` tracks only layer 1. Never `~`, never `~/Library` as a whole.
- Layer 2 is *reproduced* from layer 1 (idempotent `install.sh`).
- Layer 3 is *cleaned* or ignored, never tracked.
- **Reset** = reconcile layer 2 against layer 1 + wipe layer 3. It is not a
  factory reset and does not touch macOS itself, `~/Code`, `~/Documents`, or
  iCloud.

---

## 2. The workflow loop

```
                 +---------------------------------------------+
                 |                                             |
                 v                                             |
   expected state (manifest in git)                            |
                 |                                             |
   +-------------+--------------+                              |
   |                            |                              |
   | "intend a change"          | "reset / reconcile"          |
   |  install app / add ext     |  remove drift + re-apply     |
   |                            |                              |
   v                            v                              |
   capture -> commit            dot reset                      |
   (update manifest)            (declared state restored)      |
                 |                                             |
                 +--------------------> next reset keeps it ----+
```

Two directions, both driven by the manifest:

- **Capture** (`dot capture`) — install something intentionally, then persist it
  into the manifest and commit. Next reset keeps it.
- **Reset** (`dot reset`) — remove anything *not* in the manifest and re-apply
  everything declared.

---

## 3. Current state (what is already declared)

| Concern | Manifest | Applied by |
|---|---|---|
| Homebrew formulae + casks | `Brewfile` | `install.sh` → `brew bundle` |
| App Store apps | `Brewfile` (`mas "…", id: …`) | `install.sh` |
| macOS defaults | `mac/defaults.symlink` | `mac/install.sh` |
| dotfiles / configs | `*.symlink`, `.zshrc` | `script/bootstrap` |
| git identity + SSH | `git/install.sh` (from `.env.local`) | `git/install.sh` |
| VS Code extensions | `vscode/install.sh` | `vscode/install.sh` |
| secrets | `.env.example` → `.local/.env.local` | `script/bootstrap` |
| browser extensions | ❌ **missing** | see §6 |

Missing pieces (the point of this plan): reconcile/reset, capture, browser
extensions, cache cleanup, drift detection.

---

## 4. Target command surface (`bin/dot`)

Extend `bin/dot` so the whole workflow is one place:

```
dot bootstrap   re-symlink dotfiles                    (exists)
dot install     full install after clone               (exists)
dot update      brew update && upgrade && cleanup      (exists)
dot macos       re-apply macOS defaults                (exists)

dot capture     persist current intended state → manifest  (new)
dot reset       reconcile: remove drift + re-apply          (new)
dot cleanup     wipe known cache/junk dirs                  (new)
dot drift       report undeclared files/apps (dry-run)      (new)
```

### `dot reset` (the reconcile)

Ordered, idempotent, and non-destructive to OS/data:

1. `brew bundle cleanup --force` — remove formulae + casks not in `Brewfile`.
   (Always run `--dry-run` first to preview; `--zap` for casks to remove their
   support files too.)
2. `./install.sh` — re-apply configs, defaults, extensions, symlinks.
3. `script/cleanup` — wipe layer-3 cache dirs (§7).
4. Re-apply browser policies (§6).
5. Report anything still undeclared (`dot drift`) so you can decide keep vs drop.

### `dot capture` (persist intent)

```bash
brew bundle dump --force          # Brewfile <- currently installed
brew leaves                       # review: minimal "manual installs" list
mas list                          # review: App Store apps
# then hand-edit Brewfile to keep ONLY what was intentional, and commit
```

Prefer **edit-then-apply** (add `brew "x"` by hand, run `dot install`) over
dump-then-commit, because dump captures *dependencies and experiments* too.
`brew leaves` is the cleaner source: it lists only packages nothing else
depends on.

### `dot drift` (report, don't delete)

Snapshot-diff the meaningful-but-unmanaged areas and report what appeared since
the last committed baseline:

```bash
find ~/Library/Application\ Support ~/Library/LaunchAgents \
     ~/Library/Preferences -type f | sort > "$TMP/now"
diff <(git show HEAD:snapshot/baseline.txt) "$TMP/now"
# → "these files exist now but are not in the baseline"
```

This surfaces *surprises* (a LaunchAgent an app snuck in, a rogue preference
domain) without pretending to know your intent.

---

## 5. Manifest layout (target)

```
~/.dotfiles/
├── Brewfile                     # formulae + casks + mas apps (source of truth)
├── snapshot/
│   └── baseline.txt             # committed file-list baseline for dot drift
├── script/
│   ├── bootstrap                # (exists)
│   ├── cleanup                  # NEW: wipe layer-3 cache dirs
│   ├── reconcile                # NEW: dot reset body
│   └── drift                    # NEW: dot drift body
├── firefox/
│   └── policies.json            # NEW: declarative extension installs
├── mac/defaults.symlink         # (exists)
├── *.symlink / topic installers # (exist)
└── DARWIN-NIX-PLAN.md           # this file
```

---

## 6. Browser extensions (declarative)

Replace "download `.xpi` into profile" (current `firefox/install.sh`, unpinned)
with **policy-enforced install by add-on ID**.

**Firefox** — `distribution/policies.json` with `ExtensionSettings`:

```json
{
  "policies": {
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      }
    }
  }
}
```

Placed at `/Library/Application Support/Firefox/distribution/policies.json`
(system-wide) or inside `Firefox.app/Contents/Resources/distribution/`. Then:
"intended extension" = one block; "remove" = delete the block; `dot reset`
re-installs whatever is declared. Extensions can no longer be silently added or
removed by the app itself.

**Chrome** — the same idea via managed `policies.json` +
`ExtensionInstallForcelist` (ID + update URL).

---

## 7. Cache / junk cleanup (`script/cleanup`)

Only wipe *known* regenerable locations. Never touch user data.

```
~/Library/Caches/*
~/Library/Logs/*
~/Library/Saved Application State/*
~/Library/Application Support/*/Cache
~/Library/Application Support/*/Service Worker/CacheStorage
~/Library/Developer/Xcode/DerivedData
~/Library/Developer/CoreSimulator/Caches
~/.npm/_cacache
~/Library/Caches/pip
~/.cargo/registry/cache
```

Plus package-manager-level cleanups: `brew cleanup`, `pip cache purge`,
`npm cache clean --force`, `xcrun simctl` caches.

---

## 8. Honest limits

1. **`brew bundle cleanup` only sees Homebrew.** `.pkg` installers and
   drag-to-Applications apps are invisible to it — migrate them to casks or
   accept them as manual.
2. **`brew bundle dump` captures dependencies too.** Use `brew leaves` as the
   minimal manual-install list and curate the Brewfile by hand.
3. **Arbitrary `~/Library` drift can't be enumerated without a baseline.** The
   snapshot diff (§`dot drift`) only *reports*; you still decide keep vs drop.
4. **Data is never reset.** Config and apps are reconciled; `~/Code`,
   `~/Documents`, iCloud are never touched by `dot reset`.
5. **Secrets stay out of the manifest.** `.env.local` remains gitignored;
   installers derive per-service env files from it.

---

## 9. The nix-darwin end-state

What you are describing — whole-system declarative state, atomic rollback, and
*garbage-collection of anything not declared* — is exactly what
**nix-darwin + home-manager** provide, and it is the intended end-state of this
plan (hence the filename).

Why it wins over the Homebrew reconcile:

| Property | Homebrew reconcile | nix-darwin |
|---|---|---|
| Declares packages | ✅ Brewfile | ✅ `home.packages` / `homebrew.brews` |
| Declares macOS defaults | ⚠️ `defaults` (imperative) | ✅ `system.defaults` (declarative) |
| Declares dotfiles | ⚠️ symlink templates | ✅ home-manager |
| Remove undeclared | ⚠️ `brew bundle cleanup` (brew-only) | ✅ `nix-collect-garbage` (everything managed) |
| Rollback | ❌ | ✅ generations / `--rollback` |
| Atomic switch | ❌ | ✅ `darwin-rebuild switch` |

### Homebrew vs home-manager (the "why not just Homebrew?" question)

A natural concern is: if Homebrew already installs packages, why add
home-manager at all — and can't you keep Homebrew for packages and use
nix-darwin only for the configuration files?

They aren't the same thing:

- **Homebrew is imperative.** `brew install x` mutates state toward whatever
  the *latest* version is at install time. There is no record of exactly what
  was installed at which version, and no atomic "undo".
- **home-manager is declarative.** It *generates* dotfiles and a package
  environment from an expression, backed by a lockfile that pins every version,
  so applying a config is reproducible and can be rolled back atomically.

And yes — the hybrid you proposed works exceptionally well, and it's the
recommended bridge. `nix-darwin` ships a built-in `homebrew` module, so you can
keep Homebrew as the package backend while *declaring* the exact casks/brews in
Nix:

- `homebrew.brews` / `homebrew.casks` — declare which Homebrew formulae and
  casks must exist.
- `homebrew.onActivation.cleanup` — remove Homebrew packages that are *not*
  declared (the nix-native equivalent of `brew bundle cleanup`).
- `homebrew.onActivation.upgrade` — declare the upgrade policy.

This keeps Homebrew's catalog and your existing muscle memory, but wraps it in a
declarative manifest with rollback — a much smaller migration than moving every
package into the nix store, and a natural middle step on the way to full
home-manager ownership.

### Migration sketch (later phase — not started)

1. Install `nix` + `nix-darwin` + `home-manager` behind a unified `flake.nix`
   (nix-darwin for system defaults/daemons, home-manager for user dotfiles and
   packages).
2. Port `Brewfile` → `homebrew.brews` / `homebrew.casks` (nix-darwin's
   `homebrew` module keeps Homebrew as the backend, now declared in Nix). Move a
   few tools into `home.packages` (the nix store) only where you want strict
   pinning.
3. Port `mac/defaults.symlink` → `system.defaults`.
4. Port `*.symlink` → `home-manager` file sources (dotfiles become *generated*
   output rather than symlinks).
5. Port `script/cleanup` → `nix-collect-garbage -d` +
   `homebrew.onActivation.cleanup`.
6. Keep `git` as the manifest store (the flake), keep `.local/.env.local` for
   secrets (never into the store).

The Homebrew reconcile stays as the *working* system until the nix port is
complete; the two can coexist (`homebrew.*` options in nix-darwin).

---

## 10. Phased rollout

- [ ] **Phase 1 — reconcile + cleanup**: add `script/reconcile`, `script/cleanup`,
      wire `dot reset` / `dot cleanup`. Verify `brew bundle cleanup --dry-run`.
- [ ] **Phase 2 — capture**: add `dot capture` (`brew bundle dump` + `brew leaves`
      + `mas list`), document edit-then-apply vs dump-then-commit.
- [ ] **Phase 3 — drift**: add `snapshot/baseline.txt` + `dot drift` snapshot-diff.
- [ ] **Phase 4 — browser**: `firefox/policies.json` + rework `firefox/install.sh`
      to force-install by ID; Chrome `policies.json` if used.
- [ ] **Phase 5 — nix-darwin**: install nix, port Brewfile/defaults/dotfiles,
      replace reconcile with `darwin-rebuild switch` + `nix-collect-garbage`.

## 11. Open questions

- Edit-then-apply vs dump-then-commit as the *primary* capture flow? (Leaning
  edit-then-apply for correctness, `dump` as a convenience.)
- Keep `~/Library/Preferences` in `dot drift`, or only
  `Application Support` + `LaunchAgents` (Preferences are noisy)?
- Firefox vs Chrome (or both) as the policied browser?
- Nix migration timeline: after Phases 1–4 stabilize, or in parallel?
