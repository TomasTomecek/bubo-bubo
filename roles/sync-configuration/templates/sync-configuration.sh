#!/bin/bash
# Runs the daily configuration sync:
#   1. skip the whole sync if the local git repo is dirty
#   2. git pull --ff-only origin master
#   3. git submodule sync + update
#   4. make sync (dotfiles, user-level, no root)
# Records the result to ~/.local/state/sync-configuration/last-run as
# "<epoch> <status>" where status is success|skipped|failure.
#
# Installed by the sync-configuration ansible role (do not edit by hand).
# Run by sync-configuration.service (user unit): at user login and daily
# via sync-configuration.timer.
set -u

WORKDIR="{{ sync_configuration_workdir | expanduser }}"
STATE_DIR="$HOME/.local/state/sync-configuration"
STATE_FILE="$STATE_DIR/last-run"

mkdir -p "$STATE_DIR"
cd "$WORKDIR" || { echo "$(date +%s) failure" > "$STATE_FILE"; exit 1; }

record() {
  echo "$(date +%s) $1" > "$STATE_FILE"
}

# Skip the whole sync if the working tree is dirty (tracked files modified).
# Ignore submodules (a stale submodule shouldn't block) and untracked files
# (WIP shouldn't block).
if [ -n "$(git status --porcelain --ignore-submodules=all --untracked-files=no)" ]; then
  record skipped
  exit 0
fi

# Pull the latest from origin (github, public repo, no auth needed).
if ! git pull --ff-only origin master; then
  record failure
  exit 1
fi

# Sync submodule URLs from .gitmodules, then update.
if ! git submodule sync --recursive; then
  record failure
  exit 1
fi
if ! git submodule update --init --recursive; then
  record failure
  exit 1
fi

# Run the user-level sync playbook (dotfiles).
if make sync; then
  record success
  exit 0
else
  record failure
  exit 1
fi
