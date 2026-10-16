#!/bin/bash
# Exports the last sync-configuration run status to a Prometheus textfile
# for node_exporter's textfile collector.
#
# Installed by the sync-configuration ansible role (do not edit by hand).
# Run by sync-configuration-export.service (system unit, root), triggered
# by sync-configuration-export.path when last-run changes and by
# sync-configuration-export.timer as a fallback.
#
# Reads from {{ ansible_facts['user_dir'] }}/.local/state/sync-configuration/
# (written by the user-level sync-configuration.service):
#   last-run       "<epoch> <status>", status = success|skipped|failure
#   last-run.env   key=value: duration, step, commit, recap_*
#   last-success   epoch of the last successful run
#   counts         key=value: success, skipped, failure
# SECURITY: this script runs as root but those files are owned by an
# unprivileged user. They are never sourced or evaluated; they are parsed
# line by line, only whitelisted keys are accepted and every value is
# validated against a strict pattern. Anything else is ignored. Missing
# files (old single-line state) are fine.
#
# Metrics:
#   sync_configuration_last_run_success            1 if the last run succeeded
#   sync_configuration_last_run_skipped            1 if the last run was skipped (dirty repo)
#   sync_configuration_last_run_failure            1 if the last run failed
#   sync_configuration_last_run_timestamp_seconds  unix time of the last run
#   sync_configuration_last_success_timestamp_seconds  unix time of the last successful run
#   sync_configuration_last_run_duration_seconds   wall time of the last run
#   sync_configuration_last_run_tasks{result}      ansible recap task counts of the last make sync
#   sync_configuration_runs_total{status}          run counts by status
#   sync_configuration_last_run_info{step,commit}  1; failing step and HEAD commit
set -euo pipefail

STATE_DIR="${SYNC_CONFIGURATION_STATE_DIR:-{{ ansible_facts['user_dir'] }}/.local/state/sync-configuration}"
OUT_DIR="${SYNC_CONFIGURATION_OUT_DIR:-/var/lib/node_exporter/textfile_collector}"
OUT="$OUT_DIR/sync-configuration.prom"
TMP="$OUT.tmp.$$"
trap 'rm -f "$TMP"' EXIT

# read_kv FILE KEY...: parse key=value lines of FILE into the global
# associative array KV. Only the listed keys with strictly valid values
# are kept: integers ^[0-9]+$ (max 15 digits), step from a fixed set,
# commit ^[0-9a-f]{0,40}$. Never evaluates the content.
declare -A KV=()
read_kv() {
  local file="$1" line key val
  KV=()
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    key=${line%%=*}
    val=${line#*=}
    [ "$key" != "$line" ] || continue
    case "$key" in
      duration|recap_ok|recap_changed|recap_unreachable|recap_failed|\
recap_skipped|recap_rescued|recap_ignored|success|skipped|failure)
        [[ "$val" =~ ^[0-9]{1,15}$ ]] && KV[$key]=$val ;;
      step)
        case "$val" in
          done|dirty|chdir|pull|submodule-sync|submodule-update|make) KV[$key]=$val ;;
        esac ;;
      commit)
        [[ "$val" =~ ^[0-9a-f]{0,40}$ ]] && KV[$key]=$val ;;
    esac
  done < <(head -c 65536 "$file" 2>/dev/null || true)
}

ts=0
status=""
if [ -f "$STATE_DIR/last-run" ]; then
  read -r ts status < <(head -c 256 "$STATE_DIR/last-run") || true
fi
case "$ts" in
  ''|*[!0-9]*) ts=0 ;;
esac
[[ "$ts" =~ ^[0-9]{1,15}$ ]] || ts=0

success=0
skipped=0
failure=0
case "$status" in
  success) success=1 ;;
  skipped) skipped=1 ;;
  failure) failure=1 ;;
esac

last_success=0
if [ -f "$STATE_DIR/last-success" ]; then
  read -r last_success < <(head -c 64 "$STATE_DIR/last-success") || true
  [[ "$last_success" =~ ^[0-9]{1,15}$ ]] || last_success=0
fi

read_kv "$STATE_DIR/counts"
runs_success=${KV[success]:-0}
runs_skipped=${KV[skipped]:-0}
runs_failure=${KV[failure]:-0}

read_kv "$STATE_DIR/last-run.env"
duration=${KV[duration]:-0}
commit=${KV[commit]:-}
step=${KV[step]:-}
if [ -z "$step" ]; then
  # Old single-line state: derive what we can.
  case "$status" in
    success) step="done" ;;
    skipped) step=dirty ;;
    *) step=unknown ;;
  esac
fi
# Recap counts are meaningless for a skipped run.
[ "$skipped" -eq 1 ] && for k in "${!KV[@]}"; do
  case "$k" in recap_*) unset "KV[$k]" ;; esac
done

{
  echo "# HELP sync_configuration_last_run_success 1 if the last sync-configuration run succeeded"
  echo "# TYPE sync_configuration_last_run_success gauge"
  echo "sync_configuration_last_run_success $success"
  echo "# HELP sync_configuration_last_run_skipped 1 if the last sync-configuration run was skipped (dirty repo)"
  echo "# TYPE sync_configuration_last_run_skipped gauge"
  echo "sync_configuration_last_run_skipped $skipped"
  echo "# HELP sync_configuration_last_run_failure 1 if the last sync-configuration run failed"
  echo "# TYPE sync_configuration_last_run_failure gauge"
  echo "sync_configuration_last_run_failure $failure"
  echo "# HELP sync_configuration_last_run_timestamp_seconds Unix timestamp of the last sync-configuration run"
  echo "# TYPE sync_configuration_last_run_timestamp_seconds gauge"
  echo "sync_configuration_last_run_timestamp_seconds $ts"
  echo "# HELP sync_configuration_last_success_timestamp_seconds Unix timestamp of the last successful sync-configuration run (0 if never)"
  echo "# TYPE sync_configuration_last_success_timestamp_seconds gauge"
  echo "sync_configuration_last_success_timestamp_seconds $last_success"
  echo "# HELP sync_configuration_last_run_duration_seconds Wall time of the last sync-configuration run in seconds"
  echo "# TYPE sync_configuration_last_run_duration_seconds gauge"
  echo "sync_configuration_last_run_duration_seconds $duration"
  if [ -n "${KV[recap_ok]:-}" ]; then
    echo "# HELP sync_configuration_last_run_tasks Ansible PLAY RECAP task counts of the last make sync, by result"
    echo "# TYPE sync_configuration_last_run_tasks gauge"
    for r in ok changed unreachable failed skipped rescued ignored; do
      [ -n "${KV[recap_$r]:-}" ] && echo "sync_configuration_last_run_tasks{result=\"$r\"} ${KV[recap_$r]}"
    done
  fi
  echo "# HELP sync_configuration_runs_total Number of sync-configuration runs by status"
  echo "# TYPE sync_configuration_runs_total counter"
  echo "sync_configuration_runs_total{status=\"success\"} $runs_success"
  echo "sync_configuration_runs_total{status=\"skipped\"} $runs_skipped"
  echo "sync_configuration_runs_total{status=\"failure\"} $runs_failure"
  echo "# HELP sync_configuration_last_run_info Last sync-configuration run: step reached (done, dirty or the failing step) and HEAD commit"
  echo "# TYPE sync_configuration_last_run_info gauge"
  echo "sync_configuration_last_run_info{step=\"$step\",commit=\"$commit\"} 1"
} > "$TMP"
mv "$TMP" "$OUT"
