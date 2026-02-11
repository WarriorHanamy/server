#!/usr/bin/env bash
#
# Deploys a local Docker image to a remote server
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common/log_funcs.sh"

# Configuration
IMAGE_NAME="${IMAGE_NAME:-${USER}-lab2.3-sim5.1:train-server-ali}"

if [ "$#" -lt 1 ]; then
  cat <<EOF
Usage: $(basename "$0") <target-server>

Arguments:
  target-server    Remote server name (rec-server, wu, ali)

Environment Variables:
  IMAGE_NAME       Image name for deployment
                   Default: rec-server:train-server-ali

Example:
  $(basename "$0") ali
  IMAGE_NAME=my-image:tag $(basename "$0") rec-server
EOF
  exit 1
fi

TARGET_SERVER="$1"

# Check prerequisites
for cmd in docker ssh scp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Command '$cmd' is required but not found"
    exit 1
  fi
done

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
SAFE_IMAGE_NAME="${IMAGE_NAME//\//-}"
ARCHIVE_NAME="${SAFE_IMAGE_NAME}_${TIMESTAMP}.tar.zst"
LOCAL_ARCHIVE="/tmp/${ARCHIVE_NAME}"
REMOTE_ARCHIVE="/tmp/${ARCHIVE_NAME}"

log "Checking image ${IMAGE_NAME} exists..."
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -Fxq "$IMAGE_NAME"; then
  log_error "Image '${IMAGE_NAME}' not found. Build it first with: just build-server"
  exit 1
fi

log "Saving image to ${LOCAL_ARCHIVE}..."
docker save "$IMAGE_NAME" | zstd -T0 > "$LOCAL_ARCHIVE"

log "Transferring to ${TARGET_SERVER}..."
scp "$LOCAL_ARCHIVE" "${TARGET_SERVER}:${REMOTE_ARCHIVE}"

log "Loading image on ${TARGET_SERVER}..."
ssh "$TARGET_SERVER" "zstd -dcf ${REMOTE_ARCHIVE} | docker load && rm -f ${REMOTE_ARCHIVE}"

log "Cleaning up local archive..."
rm -f "$LOCAL_ARCHIVE"

log_success "Image ${IMAGE_NAME} deployed to ${TARGET_SERVER}"
