#!/usr/bin/env bash
#
# Packages and deploys a local project directory to a remote server.
# (Docker image deployment not included)
#
# ======================================================================================
# CONFIGURATION (Environment Variables)
# ======================================================================================

# Local Directory to sync (本地项目路径)
# Default: $HOME/server/
LOCAL_PROJECT_DIR="${LOCAL_PROJECT_DIR:-$HOME/server/}"

# Remote Directory to sync to (远端存放路径)
# Default: $HOME/server/
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/data/nvme_data/rec_ws/serverss/}"

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
  echo "Usage: $(basename "$0") <target-server>"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") rec-server"
  echo "  $(basename "$0") wu"
  echo ""
  echo "Please carefully set LOCAL_PROJECT_DIR and REMOTE_PROJECT_DIR environment variables."
  echo "This script packages and deploys the project codebase only (no Docker images)."
  exit 1
fi

TARGET_SERVER="$1"
case "$TARGET_SERVER" in
  rec-server)
    ;;
  wu)
    ;;
  ali)
    ;;
  *)
    echo "Unsupported target server: $TARGET_SERVER" >&2
    exit 1
    ;;
esac

# Check if local directory exists
if [ ! -d "$LOCAL_PROJECT_DIR" ]; then
  echo "Error: Local directory not found: $LOCAL_PROJECT_DIR" >&2
  exit 1
fi

# Check prerequisites (ssh, scp, tar)
for cmd in ssh scp tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Command '$cmd' is required but not found in PATH." >&2
    exit 1
  fi
done

# Generate archive names based on target server
HOST_SLUG="$(echo "$TARGET_SERVER" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/-/g')"
HOST_SLUG="${HOST_SLUG##[-.]}"
HOST_SLUG="${HOST_SLUG%%[-.]}"
if [ -z "$HOST_SLUG" ]; then
  HOST_SLUG="host"
fi

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
PROJECT_DIR_NAME="$(basename "$LOCAL_PROJECT_DIR")"
PROJECT_ARCHIVE_NAME="project_${HOST_SLUG}_${TIMESTAMP}.tar"
REMOTE_PROJECT_ARCHIVE_PATH="$(dirname "${REMOTE_PROJECT_DIR%/}")/${PROJECT_ARCHIVE_NAME}"

# Prepare temporary space
mkdir -p "$LOCAL_TMP_DIR"
LOCAL_ARCHIVE_TMP_DIR="$(mktemp -d "${LOCAL_TMP_DIR%/}/deploy_XXXXXX")"
cleanup() {
  if [ -d "$LOCAL_ARCHIVE_TMP_DIR" ]; then
    rm -rf "$LOCAL_ARCHIVE_TMP_DIR"
  fi
}
trap cleanup EXIT

LOCAL_PROJECT_ARCHIVE_PATH="${LOCAL_ARCHIVE_TMP_DIR}/${PROJECT_ARCHIVE_NAME}"

log "Configuration:"
log "  Local Path:       ${LOCAL_PROJECT_DIR}"
log "  Remote Path:      ${REMOTE_PROJECT_DIR}"
log "  Target Server:    ${TARGET_SERVER}"
log "  Local Archive:    ${LOCAL_PROJECT_ARCHIVE_PATH}"
log "  SSH Key Path:     ${SSH_KEY_PATH}"

# --- 0. Remote Preparation (远端准备工作) ---
log ""
log "0. Preparing remote server ${TARGET_SERVER}..."
REMOTE_PREP_OUTPUT="$(ssh -i "$SSH_KEY_PATH" "$TARGET_SERVER" \
  "PROJECT_ARCHIVE='${PROJECT_ARCHIVE_NAME}' \
   REMOTE_PROJECT_DIR='${REMOTE_PROJECT_DIR}' \
   bash -s" <<'EOF'
set -euo pipefail

# --- 0.0 Initialize Environment & Paths ---
BASE_DIR="$(dirname "${REMOTE_PROJECT_DIR%/}")"
mkdir -p "$BASE_DIR"
PROJECT_ARCHIVE_PATH="${BASE_DIR}/$PROJECT_ARCHIVE"
ANY_ACTION_TAKEN=0

# --- 0.1 File System Cleanup ---
if [ -d "${REMOTE_PROJECT_DIR%/}" ]; then
    # Backup existing directory with timestamp
    BACKUP_NAME="${REMOTE_PROJECT_DIR%/}_backup_$(date '+%Y%m%d_%H%M%S')"
    mv "${REMOTE_PROJECT_DIR%/}" "$BACKUP_NAME"
    echo "    [0.1] Backed up remote directory to: $BACKUP_NAME"
    ANY_ACTION_TAKEN=1
fi

if [ -f "$PROJECT_ARCHIVE_PATH" ]; then
  rm -f "$PROJECT_ARCHIVE_PATH"
  echo "    [0.1] Removed remote project archive: $PROJECT_ARCHIVE_PATH"
  ANY_ACTION_TAKEN=1
fi

# --- 0.2 Status Summary ---
if [ "$ANY_ACTION_TAKEN" -eq 0 ]; then
    echo "    [0.2] Environment is already clean."
else
    echo "    [0.2] Remote cleanup completed successfully."
fi
EOF
)"

# Output collected remote logs
if [ -n "$REMOTE_PREP_OUTPUT" ]; then
    printf '%s\n' "$REMOTE_PREP_OUTPUT"
fi

# --- 1. Package Local Project (打包本地项目) ---
log ""
log "1. Packaging local project ${LOCAL_PROJECT_DIR}..."
log "    Creating archive: ${LOCAL_PROJECT_ARCHIVE_PATH}"

# Create tar archive
tar -cf "$LOCAL_PROJECT_ARCHIVE_PATH" -C "$(dirname "$LOCAL_PROJECT_DIR")" "$PROJECT_DIR_NAME"

# Get archive size
ARCHIVE_SIZE="$(du -h "$LOCAL_PROJECT_ARCHIVE_PATH" | cut -f1)"
log "    Archive created successfully (${ARCHIVE_SIZE})"

# Show archive contents summary
log "    Archive contents summary:"
tar -tf "$LOCAL_PROJECT_ARCHIVE_PATH" 2>/dev/null | head -20 | sed 's/^/      /'
FILE_COUNT="$(tar -tf "$LOCAL_PROJECT_ARCHIVE_PATH" 2>/dev/null | wc -l)"
if [ "$FILE_COUNT" -gt 20 ]; then
  log "      ... and $((FILE_COUNT - 20)) more files"
fi
log "      Total: ${FILE_COUNT} files"

# --- 2. Transfer Archive (传输归档文件) ---
log ""
log "2. Transferring archive to ${TARGET_SERVER}:${REMOTE_PROJECT_ARCHIVE_PATH}..."
scp -i "$SSH_KEY_PATH" "$LOCAL_PROJECT_ARCHIVE_PATH" "${TARGET_SERVER}:${REMOTE_PROJECT_ARCHIVE_PATH}"
log "    Transfer completed successfully."

# --- 3. Remote Deployment (远端部署) ---
log ""
log "3. Extracting archive on ${TARGET_SERVER}..."
REMOTE_OUTPUT="$(ssh -i "$SSH_KEY_PATH" "$TARGET_SERVER" \
  "PROJECT_ARCHIVE='${PROJECT_ARCHIVE_NAME}' \
   PROJECT_DIR_NAME='${PROJECT_DIR_NAME}' \
   REMOTE_PROJECT_DIR='${REMOTE_PROJECT_DIR}' \
   bash -s" <<'EOF'
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

BASE_DIR="$(dirname "${REMOTE_PROJECT_DIR%/}")"
mkdir -p "$BASE_DIR"
PROJECT_ARCHIVE_PATH="${BASE_DIR}/$PROJECT_ARCHIVE"
EXTRACTED_PROJECT_PATH="${BASE_DIR}/$PROJECT_DIR_NAME"

# Validate archive exists
if [ ! -f "$PROJECT_ARCHIVE_PATH" ]; then
  echo "Error: Project archive not found: $PROJECT_ARCHIVE_PATH" >&2
  exit 1
fi

# Extract project archive
log "    Extracting archive..."
tar -xf "$PROJECT_ARCHIVE_PATH" -C "$BASE_DIR"

# Verify extracted directory exists
if [ ! -d "$EXTRACTED_PROJECT_PATH" ]; then
  echo "Error: Extracted directory missing: $EXTRACTED_PROJECT_PATH" >&2
  exit 1
fi

# Rename if necessary
if [ "$EXTRACTED_PROJECT_PATH" != "${REMOTE_PROJECT_DIR%/}" ]; then
  mv "$EXTRACTED_PROJECT_PATH" "${REMOTE_PROJECT_DIR%/}"
fi

log "    Project extracted to: ${REMOTE_PROJECT_DIR%/}"

# Show directory contents
log "    Directory contents:"
ls -lh "${REMOTE_PROJECT_DIR%/}" | head -10 | sed 's/^/      /'

# Cleanup archive
rm -f "$PROJECT_ARCHIVE_PATH"
log "    Archive removed: ${PROJECT_ARCHIVE_PATH}"

EOF
)"

if [ -n "$REMOTE_OUTPUT" ]; then
  printf '%s\n' "$REMOTE_OUTPUT"
fi

log ""
log "Deployment to ${TARGET_SERVER} completed successfully!"
log "Project codebase deployed to: ${TARGET_SERVER}:${REMOTE_PROJECT_DIR}"

# Cleanup local temp directory
cleanup
trap - EXIT
log "Removed local archive temp directory: ${LOCAL_ARCHIVE_TMP_DIR}"
