#!/bin/bash
# Runs the daily configuration sync:
#   1. skip the whole sync if the local git repo is dirty
#   2. git pull --ff-only origin master
#   3. git submodule sync + update
#   4. make sync (dotfiles, user-level, no root)
# Records the result in ~/.local/state/sync-configuration/:
#   last-run        "<epoch> <status>", status = success|skipped|failure
#                   (format is stable; written LAST so a watcher sees
#                   complete data)
#   last-run.env    key=value: duration, step, commit, recap_* task counts
#   last-run.log    output of the last `make sync` (overwritten each run)
#   last-success    epoch of the last successful run
#   counts          key=value: success, skipped, failure run totals
# All files are written atomically (tmp + mv). They are read by the root
# exporter (sync-configuration-export.sh), which parses them strictly and
# never sources them.
#
# Installed by the sync-configuration ansible role (do not edit by hand).
# Run by sync-configuration.service (user unit): at user login and daily
# via sync-configuration.timer.
set -u

WORKDIR="{{ sync_configuration_workdir | expanduser }}"
STATE_DIR="$HOME/.local/state/sync-configuration"
STATE_FILE="$STATE_DIR/last-run"
ENV_FILE="$STATE_DIR/last-run.env"
LOG_FILE="$STATE_DIR/last-run.log"
SUCCESS_FILE="$STATE_DIR/last-success"
COUNTS_FILE="$STATE_DIR/counts"

START=$(date +%s)
mkdir -p "$STATE_DIR"

# write_atomic FILE: write stdin to FILE via tmp + mv.
write_atomic() {
  local tmp="$1.tmp.$$"
  cat > "$tmp" && mv "$tmp" "$1"
}

# recap_env: print recap_<result>=<n> lines summed over the ansible PLAY
# RECAP host lines in the make output; print nothing if there is no recap.
recap_env() {
  [ -f "$LOG_FILE" ] || return 0
  awk '
    / : +ok=[0-9]+ / && /failed=[0-9]+/ {
      found = 1
      for (i = 1; i <= NF; i++)
        if (split($i, kv, "=") == 2 && kv[2] ~ /^[0-9]+$/)
          sum[kv[1]] += kv[2]
    }
    END {
      if (!found) exit
      n = split("ok changed unreachable failed skipped rescued ignored", r, " ")
      for (i = 1; i <= n; i++) printf "recap_%s=%d\n", r[i], sum[r[i]]
    }
  ' "$LOG_FILE"
}

# record STATUS STEP: persist all state; last-run goes last.
record() {
  local status="$1" step="$2" now commit="" n success=0 skipped=0 failure=0 line
  now=$(date +%s)
  commit=$(git -C "$WORKDIR" rev-parse --short=12 HEAD 2>/dev/null) || commit=""

  if [ "$status" = success ]; then
    echo "$now" | write_atomic "$SUCCESS_FILE"
  fi

  if [ -f "$COUNTS_FILE" ]; then
    while IFS= read -r line; do
      n=${line#*=}
      case "$n" in ''|*[!0-9]*) continue ;; esac
      case "$line" in
        success=*) success=$n ;;
        skipped=*) skipped=$n ;;
        failure=*) failure=$n ;;
      esac
    done < "$COUNTS_FILE"
  fi
  case "$status" in
    success) success=$((success + 1)) ;;
    skipped) skipped=$((skipped + 1)) ;;
    failure) failure=$((failure + 1)) ;;
  esac
  printf 'success=%d\nskipped=%d\nfailure=%d\n' "$success" "$skipped" "$failure" \
    | write_atomic "$COUNTS_FILE"

  {
    echo "duration=$((now - START))"
    echo "step=$step"
    echo "commit=$commit"
    if [ "$status" = failure ] || [ "$status" = success ]; then
      recap_env
    fi
  } | write_atomic "$ENV_FILE"

  echo "$now $status" | write_atomic "$STATE_FILE"
}

# fail STEP: record a failure at STEP and exit.
fail() {
  record failure "$1"
  exit 1
}

# A skipped/early run must not leave a stale log that looks like a recap.
rm -f "$LOG_FILE"

cd "$WORKDIR" || fail chdir

# Skip the whole sync if the working tree is dirty (tracked files modified).
# Ignore submodules (a stale submodule shouldn't block) and untracked files
# (WIP shouldn't block).
if [ -n "$(git status --porcelain --ignore-submodules=all --untracked-files=no)" ]; then
  record skipped dirty
  exit 0
fi

# Pull the latest from origin (github, public repo, no auth needed).
git pull --ff-only origin master || fail pull

# Sync submodule URLs from .gitmodules, then update.
git submodule sync --recursive || fail submodule-sync
git submodule update --init --recursive || fail submodule-update

# Run the user-level sync playbook (dotfiles). Tee the output to the log
# (for the recap) while still printing it to the journal; the exit status
# is make's, not tee's.
make sync 2>&1 | tee "$LOG_FILE"
if [ "${PIPESTATUS[0]}" -eq 0 ]; then
  record success "done"
  exit 0
else
  fail make
fi
