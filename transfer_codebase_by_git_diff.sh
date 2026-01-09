#!/usr/bin/env bash
#
# Creates a git diff patch from current workspace and deploys it to a remote server.
#
# ======================================================================================
# CONFIGURATION (Environment Variables)
# ======================================================================================

# Local Project Directory (本地项目路径)
# Default: $HOME/server/
LOCAL_PROJECT_DIR="${LOCAL_PROJECT_DIR:-$HOME/server/}"

# Remote Project Directory (远端项目路径)
# Default: $HOME/server/
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/data/nvme_data/rec_ws/server/}"

# Commit hash to compare against (对比的提交哈希)
# Default: HEAD (compares current workspace with last commit)
COMMIT_HASH="${COMMIT_HASH:-HEAD}"

# Local temporary directory root (本地临时目录)
# Default: $TMPDIR or /tmp/
LOCAL_TMP_DIR="${LOCAL_TMP_DIR:-${TMPDIR:-/tmp/}}"

# SSH Key Configuration (SSH密钥配置)
# Default: ~/.ssh/id_ed25519
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"

# ======================================================================================

set -euo pipefail

# ======================================================================================
# ANSI Color Codes
# ======================================================================================
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# ======================================================================================
# Logging Functions
# ======================================================================================

# Standard info log (blue)
log() {
  printf "${COLOR_BLUE}[%s]${COLOR_RESET} %s\n" "$(date '+%H:%M:%S')" "$*"
}

# Success log (green)
log_success() {
  printf "${COLOR_GREEN}[%s] ✓ %s${COLOR_RESET}\n" "$(date '+%H:%M:%S')" "$*"
}

# Error log (red)
log_error() {
  printf "${COLOR_RED}[%s] ✗ %s${COLOR_RESET}\n" "$(date '+%H:%M:%S')" "$*" >&2
}

# Warning log (yellow)
log_warning() {
  printf "${COLOR_YELLOW}[%s] ⚠ %s${COLOR_RESET}\n" "$(date '+%H:%M:%S')" "$*"
}

# ======================================================================================

if [ "$#" -lt 1 ]; then
  echo "Usage: $(basename "$0") <target-server> [commit-hash]"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") rec-server              # Deploy workspace diff vs HEAD"
  echo "  $(basename "$0") rec-server d21f153      # Deploy workspace diff vs specific commit"
  echo ""
  echo "Environment Variables:"
  echo "  LOCAL_PROJECT_DIR    Local project path (default: \$HOME/server/)"
  echo "  REMOTE_PROJECT_DIR   Remote project path (default: /data/nvme_data/rec_ws/server/)"
  echo "  COMMIT_HASH          Commit to compare against (default: HEAD)"
  echo "  LOCAL_TMP_DIR        Local temp directory (default: \$HOME/Public/)"
  echo "  SSH_KEY_PATH         SSH key path (default: ~/.ssh/id_ed25519)"
  exit 1
fi

TARGET_SERVER="$1"

# Allow overriding commit hash via second argument
if [ -n "${2:-}" ]; then
  COMMIT_HASH="$2"
fi

# Validate target server
case "$TARGET_SERVER" in
  rec-server)
    ;;
  wu)
    ;;
  ali)
    ;;
  *)
    echo "Error: Unsupported target server: $TARGET_SERVER" >&2
    echo "Supported servers: rec-server, wu, ali" >&2
    exit 1
    ;;
esac

# Check if local directory exists
if [ ! -d "$LOCAL_PROJECT_DIR" ]; then
  echo "Error: Local directory not found: $LOCAL_PROJECT_DIR" >&2
  exit 1
fi

# Check prerequisites (git, ssh, scp)
for cmd in git ssh scp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Command '$cmd' is required but not found in PATH." >&2
    exit 1
  fi
done

# Check if we're in a git repository
cd "$LOCAL_PROJECT_DIR"
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  log_error "Not a git repository: $LOCAL_PROJECT_DIR"
  exit 1
fi

# ======================================================================================
# Helper Functions
# ======================================================================================

# Retrieve remote server's HEAD commit hash
get_remote_head_hash() {
  local server="$1"
  local remote_dir="$2"
  local ssh_key="$3"

  log "Querying remote server's HEAD commit..." >&2

  local remote_head
  remote_head="$(ssh -i "$ssh_key" -o ConnectTimeout=10 -o BatchMode=yes "$server" \
    "cd '$remote_dir' 2>/dev/null && git rev-parse HEAD 2>/dev/null || echo 'UNAVAILABLE'")"

  if [ "$remote_head" = "UNAVAILABLE" ] || [ -z "$remote_head" ]; then
    log_warning "Could not retrieve remote HEAD from $server" >&2
    log_warning "Possible causes:" >&2
    log_warning "  - Remote server unreachable" >&2
    log_warning "  - Remote directory not a git repository" >&2
    log_warning "  - SSH authentication failed" >&2
    return 1
  fi

  log_success "Remote HEAD: $remote_head" >&2
  echo "$remote_head"
  return 0
}

# Check if a commit exists in local git history
commit_exists_in_local() {
  local commit_hash="$1"

  # Method 1: Check with git cat-file (most reliable)
  if git cat-file -e "${commit_hash}^{commit}" 2>/dev/null; then
    return 0
  fi

  # Method 2: Check with git rev-parse
  if git rev-parse --verify "${commit_hash}^{commit}" >/dev/null 2>&1; then
    return 0
  fi

  # Method 3: Check if commit exists in any branch history
  if git branch -a --contains "$commit_hash" 2>/dev/null | grep -q .; then
    return 0
  fi

  # Debug: show why check failed
  log "Debug: commit check failed for ${commit_hash:0:8}" >&2
  git rev-parse --verify "${commit_hash}^{commit}" 2>&1 | head -1 | sed 's/^/  /' >&2 || true

  return 1
}

# ======================================================================================

# Generate patch filename
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
PATCH_NAME="changes_${TARGET_SERVER}_${TIMESTAMP}.patch"
# Ensure LOCAL_TMP_DIR ends with slash
LOCAL_TMP_DIR="${LOCAL_TMP_DIR%/}/"
LOCAL_PATCH_PATH="${LOCAL_TMP_DIR}${PATCH_NAME}"
REMOTE_PATCH_PATH="$(dirname "${REMOTE_PROJECT_DIR%/}")/${PATCH_NAME}"

# ======================================================================================
# Determine Comparison Baseline
# ======================================================================================
log "Determining comparison baseline..."

# Variable to store remote HEAD for display
REMOTE_HEAD_BEFORE=""

# Priority 1: Explicitly provided COMMIT_HASH (env var or argument)
if [ "${COMMIT_HASH:-HEAD}" != "HEAD" ]; then
  BASELINE_COMMIT="$COMMIT_HASH"
  log "Using explicit commit: ${BASELINE_COMMIT}"

  # Verify it exists
  if ! git rev-parse --verify "${BASELINE_COMMIT}^{commit}" >/dev/null 2>&1; then
    log_error "Specified commit not found: ${BASELINE_COMMIT}"
    exit 1
  fi
  log_success "Baseline commit validated"

  # Try to get remote HEAD anyway for display
  REMOTE_HEAD_BEFORE="$(get_remote_head_hash "$TARGET_SERVER" "${REMOTE_PROJECT_DIR%/}" "$SSH_KEY_PATH" 2>/dev/null)" || true

# Priority 2: Try to retrieve remote HEAD automatically
else
  REMOTE_HEAD=""
  if REMOTE_HEAD="$(get_remote_head_hash "$TARGET_SERVER" "${REMOTE_PROJECT_DIR%/}" "$SSH_KEY_PATH")"; then
    REMOTE_HEAD_BEFORE="$REMOTE_HEAD"
    # Check if remote HEAD exists in local history
    if commit_exists_in_local "$REMOTE_HEAD"; then
      BASELINE_COMMIT="$REMOTE_HEAD"
      log_success "Using remote HEAD as baseline: ${BASELINE_COMMIT}"
    else
      log_warning "Remote HEAD ($REMOTE_HEAD) not found in local history"
      log_warning "This suggests local and remote repos have diverged"
      log_warning "Falling back to local HEAD"
      BASELINE_COMMIT="HEAD"
      log "Using local HEAD as baseline"
    fi
  else
    # Remote HEAD retrieval failed, use local HEAD with warning
    log_warning "Could not retrieve remote HEAD, using local HEAD"
    BASELINE_COMMIT="HEAD"
    log "Using local HEAD as baseline: ${BASELINE_COMMIT}"
  fi
fi

log ""
log "Configuration:"
log "  Local Path:        ${LOCAL_PROJECT_DIR}"
log "  Remote Path:       ${REMOTE_PROJECT_DIR}"
log "  Target Server:     ${TARGET_SERVER}"
log "  Baseline Commit:   ${BASELINE_COMMIT}"
if [ -n "$REMOTE_HEAD_BEFORE" ]; then
  log "  Remote HEAD Before: ${REMOTE_HEAD_BEFORE}"
fi
log "  Patch File:        ${PATCH_NAME}"
log "  SSH Key Path:      ${SSH_KEY_PATH}"
log ""

# ======================================================================================

# --- 1. Create Git Diff Patch ---
log "1. Creating git diff patch: ${LOCAL_PROJECT_DIR} vs ${BASELINE_COMMIT}..."

# Check if there are any changes
if git diff --quiet "${BASELINE_COMMIT}" 2>/dev/null; then
  log_error "No changes detected between workspace and commit ${BASELINE_COMMIT}"
  exit 1
fi

# Create the patch
git diff "${BASELINE_COMMIT}" > "$LOCAL_PATCH_PATH"

# Verify patch was created and is not empty
if [ ! -s "$LOCAL_PATCH_PATH" ]; then
  log_error "Failed to create patch or patch is empty"
  exit 1
fi

PATCH_SIZE="$(du -h "$LOCAL_PATCH_PATH" | cut -f1)"
log_success "Patch created successfully (${PATCH_SIZE}): ${LOCAL_PATCH_PATH}"

# Show summary of changes
log "Summary of changes:"
git diff --stat "${BASELINE_COMMIT}" | sed 's/^/      /'

# --- 2. Upload Patch to Remote Server ---
log "2. Uploading patch to ${TARGET_SERVER}:${REMOTE_PATCH_PATH}..."
scp -i "$SSH_KEY_PATH" "$LOCAL_PATCH_PATH" "${TARGET_SERVER}:${REMOTE_PATCH_PATH}"
log_success "Patch uploaded successfully"

# --- 3. Apply Patch on Remote Server ---
log "3. Applying patch on remote server..."
REMOTE_OUTPUT="$(ssh -i "$SSH_KEY_PATH" "$TARGET_SERVER" \
  "PATCH_FILE='${PATCH_NAME}' \
   REMOTE_PROJECT_DIR='${REMOTE_PROJECT_DIR}' \
   PATCH_PATH='${REMOTE_PATCH_PATH}' \
   COLOR_GREEN='\033[0;32m' \
   COLOR_RED='\033[0;31m' \
   COLOR_YELLOW='\033[0;33m' \
   COLOR_BLUE='\033[0;34m' \
   COLOR_RESET='\033[0m' \
   bash -s" <<'EOF'
set -uo pipefail

log() {
  printf "${COLOR_BLUE}[%s]${COLOR_RESET} %s\n" "$(date '+%H:%M:%S')" "$*"
}

log_success() {
  printf "${COLOR_GREEN}[%s] ✓ %s${COLOR_RESET}\n" "$(date '+%H:%M:%S')" "$*"
}

log_error() {
  printf "${COLOR_RED}[%s] ✗ %s${COLOR_RESET}\n" "$(date '+%H:%M:%S')" "$*"
}

log_warning() {
  printf "${COLOR_YELLOW}[%s] ⚠ %s${COLOR_RESET}\n" "$(date '+%H:%M:%S')" "$*"
}

# Navigate to remote project directory
cd "${REMOTE_PROJECT_DIR%/}" || {
  log_error "Failed to cd to: ${REMOTE_PROJECT_DIR}"
  exit 1
}

# Verify we're in a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  log_error "Remote directory is not a git repository: ${REMOTE_PROJECT_DIR}"
  exit 1
fi

# Check git status - if uncommitted changes exist, reset them (server should not be modified directly)
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  log_warning "Remote working directory has uncommitted changes"
  log "Resetting remote workspace (git reset --hard)..."
  git reset --hard HEAD
  log_success "Remote workspace reset to clean state"
fi

# Apply the patch
log "Applying patch with git apply..."
APPLY_OUTPUT="$(git apply --check "$PATCH_PATH" 2>&1)" || true
APPLY_EXIT=$?

if [ $APPLY_EXIT -eq 0 ]; then
  git apply "$PATCH_PATH"
  log_success "Patch applied successfully"

  # Show what changed
  log "Summary of applied changes:"
  git diff --stat | sed 's/^/    /'
else
  log_error "Patch does not apply cleanly to remote repository"
  log ""
  log "git apply --check output:"
  printf '%s\n' "$APPLY_OUTPUT" | sed 's/^/    /'
  exit 1
fi

# Remove the patch file after successful application
rm -f "$PATCH_PATH"
log_success "Patch file removed: ${PATCH_PATH}"

EOF
)" || true

if [ -n "$REMOTE_OUTPUT" ]; then
  printf '%s\n' "$REMOTE_OUTPUT"
fi

# Check if SSH command succeeded
if [ "${PIPESTATUS[0]}" -ne 0 ] 2>/dev/null || [ ! -s "$REMOTE_OUTPUT" ]; then
  # Check if remote patch file still exists (indicates failure)
  if ssh -i "$SSH_KEY_PATH" "$TARGET_SERVER" "test -f '$REMOTE_PATCH_PATH'" 2>/dev/null; then
    log_warning "Remote patch application may have failed"
    log "You can check manually on $TARGET_SERVER:"
    log "  cd $REMOTE_PROJECT_DIR"
    log "  git apply --check $REMOTE_PATCH_PATH"
  fi
fi

# --- 4. Cleanup Local Patch ---
log "4. Cleaning up local patch file..."
rm -f "$LOCAL_PATCH_PATH"
log_success "Removed local patch: ${LOCAL_PATCH_PATH}"

# --- 5. Get Remote HEAD After Deployment ---
log ""
log "5. Verifying remote state..."

# Get remote HEAD and verify it
REMOTE_HEAD_AFTER=""
REMOTE_HEAD_RAW="$(ssh -i "$SSH_KEY_PATH" "$TARGET_SERVER" \
  "cd '${REMOTE_PROJECT_DIR%/}' 2>/dev/null && git rev-parse HEAD 2>&1")"

# Check if we got a valid commit hash (40 character hex string)
if echo "$REMOTE_HEAD_RAW" | grep -qE '^[a-f0-9]{40}$'; then
  REMOTE_HEAD_AFTER="$REMOTE_HEAD_RAW"
  log_success "Remote HEAD after deployment: ${REMOTE_HEAD_AFTER}"

  # Compare with before (if we have it)
  if [ -n "$REMOTE_HEAD_BEFORE" ]; then
    if [ "$REMOTE_HEAD_BEFORE" = "$REMOTE_HEAD_AFTER" ]; then
      log_warning "Remote HEAD unchanged - patch may not have been applied properly"
      log "This could mean the patch had no effect or failed silently"
    else
      log_success "Remote HEAD changed: ${REMOTE_HEAD_BEFORE:0:8} -> ${REMOTE_HEAD_AFTER:0:8}"
    fi
  fi
else
  log_error "Failed to get valid remote HEAD after deployment"
  log_error "Got: $REMOTE_HEAD_RAW"
  REMOTE_HEAD_AFTER=""
fi

log ""
log_success "=========================================="
log_success "Deployment completed successfully!"
log_success "=========================================="
log ""
log "Summary:"
if [ -n "$REMOTE_HEAD_BEFORE" ]; then
  log "  Remote HEAD Before: ${REMOTE_HEAD_BEFORE}"
fi
if [ -n "$REMOTE_HEAD_AFTER" ]; then
  log "  Remote HEAD After:  ${REMOTE_HEAD_AFTER}"
fi
log ""
log "Changes have been applied to ${TARGET_SERVER}:${REMOTE_PROJECT_DIR}"
log ""
log "Next steps:"
log "  1. SSH to remote: ssh ${TARGET_SERVER}"
log "  2. Review changes: cd ${REMOTE_PROJECT_DIR} && git diff"
log "  3. Commit: git commit -am 'Deployed from local'"
