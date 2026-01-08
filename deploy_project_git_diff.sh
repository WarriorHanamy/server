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
# Default: $HOME/Public/
LOCAL_TMP_DIR="${LOCAL_TMP_DIR:-$HOME/Public/}"

# SSH Key Configuration (SSH密钥配置)
# Default: ~/.ssh/id_ed25519
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519}"

# ======================================================================================

set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

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
  echo "Error: Not a git repository: $LOCAL_PROJECT_DIR" >&2
  exit 1
fi

# Generate patch filename
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
PATCH_NAME="changes_${TARGET_SERVER}_${TIMESTAMP}.patch"
LOCAL_PATCH_PATH="${LOCAL_TMP_DIR}${PATCH_NAME}"
REMOTE_PATCH_PATH="$(dirname "${REMOTE_PROJECT_DIR%/}")/${PATCH_NAME}"

# Verify commit hash exists
if ! git rev-parse --verify "${COMMIT_HASH}^{commit}" >/dev/null 2>&1; then
  echo "Error: Invalid commit hash: $COMMIT_HASH" >&2
  exit 1
fi

log "Configuration:"
log "  Local Path:        ${LOCAL_PROJECT_DIR}"
log "  Remote Path:       ${REMOTE_PROJECT_DIR}"
log "  Target Server:     ${TARGET_SERVER}"
log "  Compare Commit:    ${COMMIT_HASH}"
log "  Patch File:        ${PATCH_NAME}"
log "  SSH Key Path:      ${SSH_KEY_PATH}"
log ""

# --- 1. Create Git Diff Patch ---
log "1. Creating git diff patch: ${LOCAL_PROJECT_DIR} vs ${COMMIT_HASH}..."

# Check if there are any changes
if git diff --quiet "${COMMIT_HASH}" 2>/dev/null; then
  echo "Error: No changes detected between workspace and commit ${COMMIT_HASH}" >&2
  exit 1
fi

# Create the patch
git diff "${COMMIT_HASH}" > "$LOCAL_PATCH_PATH"

# Verify patch was created and is not empty
if [ ! -s "$LOCAL_PATCH_PATH" ]; then
  echo "Error: Failed to create patch or patch is empty" >&2
  exit 1
fi

PATCH_SIZE="$(du -h "$LOCAL_PATCH_PATH" | cut -f1)"
log "    Patch created successfully (${PATCH_SIZE}): ${LOCAL_PATCH_PATH}"

# Show summary of changes
log "    Summary of changes:"
git diff --stat "${COMMIT_HASH}" | sed 's/^/      /'

# --- 2. Upload Patch to Remote Server ---
log "2. Uploading patch to ${TARGET_SERVER}:${REMOTE_PATCH_PATH}..."
scp -i "$SSH_KEY_PATH" "$LOCAL_PATCH_PATH" "${TARGET_SERVER}:${REMOTE_PATCH_PATH}"
log "    Patch uploaded successfully."

# --- 3. Apply Patch on Remote Server ---
log "3. Applying patch on remote server..."
REMOTE_OUTPUT="$(ssh -i "$SSH_KEY_PATH" "$TARGET_SERVER" \
  "PATCH_FILE='${PATCH_NAME}' \
   REMOTE_PROJECT_DIR='${REMOTE_PROJECT_DIR}' \
   PATCH_PATH='${REMOTE_PATCH_PATH}' \
   bash -s" <<'EOF'
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

# Navigate to remote project directory
cd "${REMOTE_PROJECT_DIR%/}"

# Verify we're in a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: Remote directory is not a git repository: ${REMOTE_PROJECT_DIR}" >&2
  exit 1
fi

# Check git status (require clean working tree)
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo "Error: Remote working directory has uncommitted changes" >&2
  echo "Please commit or stash changes before applying patch." >&2
  exit 1
fi

# Apply the patch
log "    Applying patch with git apply..."
if git apply --check "$PATCH_PATH" 2>/dev/null; then
  git apply "$PATCH_PATH"
  log "    Patch applied successfully."

  # Show what changed
  log "    Summary of applied changes:"
  git diff --stat | sed 's/^/      /'
else
  echo "Error: Patch does not apply cleanly to remote repository" >&2
  echo "Try running: git apply --check $PATCH_PATH on remote server to see conflicts" >&2
  exit 1
fi

# Remove the patch file after successful application
rm -f "$PATCH_PATH"
log "    Patch file removed: ${PATCH_PATH}"

EOF
)"

if [ -n "$REMOTE_OUTPUT" ]; then
  printf '%s\n' "$REMOTE_OUTPUT"
fi

# --- 4. Cleanup Local Patch ---
log "4. Cleaning up local patch file..."
rm -f "$LOCAL_PATCH_PATH"
log "    Removed local patch: ${LOCAL_PATCH_PATH}"

log ""
log "Deployment completed successfully!"
log "Changes have been applied to ${TARGET_SERVER}:${REMOTE_PROJECT_DIR}"
log "You can now review and commit the changes on the remote server."
