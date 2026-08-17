#!/usr/bin/env bash
#
# Install SDKMAN and a current Java LTS.
#
# Why no Gradle: since Gradle 4.x the recommended way to use Gradle on a
# project is the Gradle Wrapper (`./gradlew`), checked into each repo. A global
# `gradle` on $PATH silently overrides per-project wrapper versions and is a
# source of "works on my machine" drift. If you genuinely need a global one,
# run `sdk install gradle <version>` manually.
#
# Why curl|bash for SDKMAN: it's the only install path the project ships
# (https://sdkman.io/install, 2026). The endpoint redirects to a hosted blob
# with no version tag to pin against — if you want immutability, mirror the
# installer in your own artifact store and replace the URL below.

set -euo pipefail

# Default Java LTS to install. Bump this when a new LTS lands (Java 25 in
# Sept 2025, Java 29 in Sept 2029). Verify identifiers with `sdk list java`.
JAVA_VERSION="${JAVA_VERSION:-21.0.5-tem}"

# ---------- SDKMAN ----------
if [ ! -f "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
  echo "==> Installing SDKMAN..."
  curl -s "https://get.sdkman.io" | bash
fi

# SDKMAN's scripts reference unset vars/positional params under `set -u`
# (init reads ZSH_VERSION; sdkman-install.sh:24 reads unbound $3). Relax -u
# for the entire SDKMAN section.
set +u
. "$HOME/.sdkman/bin/sdkman-init.sh"

export SDKMAN_OFFLINE_MODE="${SDKMAN_OFFLINE_MODE:-false}"

# ---------- Java ----------
if ! sdk list java 2>/dev/null | grep -q "$JAVA_VERSION"; then
  echo "==> Installing Java $JAVA_VERSION..."
  sdk install java "$JAVA_VERSION"
fi
sdk default java "$JAVA_VERSION" 2>/dev/null || true
set -u

# ---------- Gradle: intentionally not installed globally ----------
# Per-project `./gradlew` is the standard since Gradle 4.x. A global gradle
# causes version drift and "works on my machine" bugs. Run
#   sdk install gradle <version>
# yourself only if you have a specific reason.

echo "  [ OK ] Java $JAVA_VERSION installed via SDKMAN (Gradle via per-project wrapper)"
echo "  [ TIP ] JAVA_VERSION env var overrides the default; bump the default in java/install.sh when a new LTS lands."