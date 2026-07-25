#!/usr/bin/env bash
#
# Install SDKMAN, Java, and Gradle

set -euo pipefail

if [ ! -f "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
  echo "==> Installing SDKMAN..."
  curl -s "https://get.sdkman.io" | bash
fi

# SDKMAN init references ZSH_VERSION (unset under bash), disable -u temporarily
set +u
. "$HOME/.sdkman/bin/sdkman-init.sh"
set -u

export SDKMAN_OFFLINE_MODE="${SDKMAN_OFFLINE_MODE:-false}"

# Install Java 11 (Temurin)
if ! sdk list java 2>/dev/null | grep -q "11.0.22-tem"; then
  echo "==> Installing Java 11.0.22-tem..."
  sdk install java 11.0.22-tem
fi

sdk default java 11.0.22-tem 2>/dev/null || true

# Install Gradle
if ! sdk list gradle 2>/dev/null | grep -q "7.6.4"; then
  echo "==> Installing Gradle 7.6.4..."
  sdk install gradle 7.6.4
fi

sdk default gradle 7.6.4 2>/dev/null || true

echo "  [ OK ] Java and Gradle installed"