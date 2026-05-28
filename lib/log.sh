#!/usr/bin/env bash
# lib/log.sh — logging helpers

PIVOT_LOG_FILE="${PIVOT_LOG_FILE:-/var/log/linux-pivot.log}"
PIVOT_VERBOSE="${PIVOT_VERBOSE:-0}"

_log() {
  local level="$1"; shift
  local ts; ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local msg="[pivot/${level}] $*"
  echo "$msg"
  mkdir -p "$(dirname "$PIVOT_LOG_FILE")" 2>/dev/null || true
  echo "${ts} ${msg}" >> "$PIVOT_LOG_FILE" 2>/dev/null || true
}

log_info()    { _log "info"  "$@"; }
log_warn()    { _log "warn"  "$@" >&2; }
log_error()   { _log "error" "$@" >&2; }
log_verbose() { [[ "$PIVOT_VERBOSE" == "1" ]] && _log "debug" "$@" || true; }
die()         { log_error "$@"; exit 1; }

log_step() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
