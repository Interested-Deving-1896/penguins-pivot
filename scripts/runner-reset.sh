#!/usr/bin/env bash
# scripts/ci/runner-reset.sh — re-register the Incus KVM self-hosted runner
#
# Called monthly by runner-reset.yml to re-register the runner after the
# GitHub shared runner quota resets. Does NOT re-provision Incus — only
# handles runner de-registration and re-registration.
#
# Required env:
#   GH_TOKEN          — PAT with manage_runners:org or repo scope
#   SSH_KEY           — SSH private key for the runner host (PEM format)
#   RUNNER_HOST       — hostname or IP of the runner host
#   GH_REPO           — e.g. Interested-Deving-1896/linux-pivot
#
# Optional env:
#   RUNNER_HOST_USER  — SSH user on the runner host (default: runner)
#   RUNNER_DIR        — runner install directory (default: /opt/actions-runner)
#   DRY_RUN           — if "true", print commands without executing (default: false)

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${SSH_KEY:?SSH_KEY is required}"
: "${RUNNER_HOST:?RUNNER_HOST is required}"
: "${GH_REPO:?GH_REPO is required}"

RUNNER_HOST_USER="${RUNNER_HOST_USER:-runner}"
RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"
DRY_RUN="${DRY_RUN:-false}"

info() { echo "[runner-reset] $*"; }
die()  { echo "[runner-reset][error] $*" >&2; exit 1; }

# ── SSH setup ─────────────────────────────────────────────────────────────────
info "Setting up SSH key..."
SSH_KEY_FILE=$(mktemp)
chmod 600 "$SSH_KEY_FILE"
echo "$SSH_KEY" > "$SSH_KEY_FILE"
trap 'rm -f "$SSH_KEY_FILE"' EXIT

SSH_OPTS="-i ${SSH_KEY_FILE} -o StrictHostKeyChecking=no -o ConnectTimeout=15"

ssh_run() {
  local cmd="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[DRY RUN] ssh ${RUNNER_HOST_USER}@${RUNNER_HOST}: $cmd"
    return 0
  fi
  # shellcheck disable=SC2086
  ssh $SSH_OPTS "${RUNNER_HOST_USER}@${RUNNER_HOST}" "$cmd"
}

# ── Verify connectivity ───────────────────────────────────────────────────────
info "Verifying SSH connectivity to ${RUNNER_HOST}..."
ssh_run "echo 'SSH OK'"

# ── Get fresh registration token ─────────────────────────────────────────────
info "Requesting fresh runner registration token from GitHub API..."
if [[ "$DRY_RUN" == "true" ]]; then
  info "[DRY RUN] would POST /repos/${GH_REPO}/actions/runners/registration-token"
  NEW_TOKEN="DRY_RUN_TOKEN"
else
  response=$(curl -fsSL \
    -X POST \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${GH_REPO}/actions/runners/registration-token")
  NEW_TOKEN=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null) \
    || die "Failed to parse registration token from API response: ${response:0:200}"
  info "Registration token obtained (expires in 1 hour)"
fi

# ── Stop the runner service ───────────────────────────────────────────────────
info "Stopping runner service..."
ssh_run "sudo ${RUNNER_DIR}/svc.sh stop 2>/dev/null || true"

# ── Remove existing registration ─────────────────────────────────────────────
info "Removing existing runner registration..."
ssh_run "cd ${RUNNER_DIR} && sudo -u ${RUNNER_HOST_USER} ./config.sh remove --unattended --token '${NEW_TOKEN}' 2>/dev/null || true"

# ── Re-register with same labels ─────────────────────────────────────────────
info "Re-registering runner..."
ssh_run "cd ${RUNNER_DIR} && sudo -u ${RUNNER_HOST_USER} ./config.sh \
  --url 'https://github.com/${GH_REPO}' \
  --token '${NEW_TOKEN}' \
  --name 'incus-kvm-\$(hostname)' \
  --labels 'self-hosted,linux,kvm,incus' \
  --work '_work' \
  --unattended \
  --replace"

# ── Restart the runner service ────────────────────────────────────────────────
info "Starting runner service..."
ssh_run "sudo ${RUNNER_DIR}/svc.sh start"

# ── Verify runner is online ───────────────────────────────────────────────────
info "Verifying runner is online..."
sleep 5
if [[ "$DRY_RUN" != "true" ]]; then
  runner_status=$(curl -fsSL \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GH_REPO}/actions/runners" \
    | python3 -c "
import sys, json
runners = json.load(sys.stdin).get('runners', [])
online = [r for r in runners if r.get('status') == 'online' and 'incus' in [l['name'] for l in r.get('labels', [])]]
print(f'{len(online)} incus runner(s) online')
for r in online:
    print(f'  {r[\"name\"]} — {r[\"status\"]}')
" 2>/dev/null) || runner_status="(could not verify)"
  info "$runner_status"
fi

info "Runner reset complete."
