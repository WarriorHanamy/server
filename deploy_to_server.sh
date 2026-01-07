#!/usr/bin/env bash
#
# Syncs a local directory and Docker container to a remote server using tar and scp.
#
# ======================================================================================
# CONFIGURATION (Environment Variables)
# ======================================================================================

# Local Directory to sync (本地项目路径)
# Default: $HOME/server/
LOCAL_PROJECT_DIR="${LOCAL_PROJECT_DIR:-$HOME/server/}"

# Remote Directory to sync to (远端存放路径)
# Default: $HOME/server/
REMOTE_PROJECT_DIR="${REMOTE_PROJECT_DIR:-/data/nvme_data/rec_ws/server/}"

# Local temporary directory root (本地临时目录)
# Default: $HOME/Public/
LOCAL_TMP_DIR="${LOCAL_TMP_DIR:-$HOME/Public/}"

# Docker Configuration
# Container name to commit and deploy (要提交和部署的容器名)
CONTAINER_NAME="${CONTAINER_NAME:-rec-lab2.3-sim5.1}"

# Image name for the committed container (提交的镜像名)
IMAGE_NAME="${IMAGE_NAME:-rec-lab2.3-sim5.1}"

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
  echo "Please carefully set LOCAL_PROJECT_DIR, REMOTE_PROJECT_DIR, CONTAINER_NAME, and IMAGE_NAME environment variables as needed."
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

# Check prerequisites (docker, ssh, scp)
for cmd in docker ssh scp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Command '$cmd' is required but not found in PATH." >&2
    exit 1
  fi
done

# Generate image and archive names based on target server
# docker tags must be lowercase and limited characters, so convert servername to slug
HOST_SLUG="$(echo "$TARGET_SERVER" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_.-]/-/g')"
HOST_SLUG="${HOST_SLUG##[-.]}"
HOST_SLUG="${HOST_SLUG%%[-.]}"
if [ -z "$HOST_SLUG" ]; then
  HOST_SLUG="host"
fi

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
IMAGE_TAG="train-server-${HOST_SLUG}"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
IMAGE_ARCHIVE_NAME="${IMAGE_NAME}_${IMAGE_TAG}_${TIMESTAMP}.tar.zst"
PROJECT_DIR_NAME="$(basename "$LOCAL_PROJECT_DIR")"
PROJECT_ARCHIVE_NAME="project_${HOST_SLUG}_${TIMESTAMP}.tar"
REMOTE_IMAGE_ARCHIVE_PATH="$(dirname "${REMOTE_PROJECT_DIR%/}")/${IMAGE_ARCHIVE_NAME}"
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

LOCAL_IMAGE_ARCHIVE_PATH="${LOCAL_ARCHIVE_TMP_DIR}/${IMAGE_ARCHIVE_NAME}"
LOCAL_PROJECT_ARCHIVE_PATH="${LOCAL_ARCHIVE_TMP_DIR}/${PROJECT_ARCHIVE_NAME}"

log "Configuration:"
log "  Local Path:       ${LOCAL_PROJECT_DIR}"
log "  Remote Path:      ${REMOTE_PROJECT_DIR}"
log "  Target Server:      ${TARGET_SERVER}"
log "  Container Name:   ${CONTAINER_NAME}"
log "  Full Image Name on Server:  ${FULL_IMAGE_NAME}"
log "  Local Archive Temp Dir: ${LOCAL_ARCHIVE_TMP_DIR}"
log "  ssh Key Path:    ${SSH_KEY_PATH}"

# --- 0. Remote Preparation (远端准备工作) ---
log "0. Preparing remote server ${TARGET_SERVER}..."
REMOTE_PREP_OUTPUT="$(ssh -i "$SSH_KEY_PATH" "$TARGET_SERVER" \
  "IMAGE_ARCHIVE='${IMAGE_ARCHIVE_NAME}' \
   PROJECT_ARCHIVE='${PROJECT_ARCHIVE_NAME}' \
   REMOTE_PROJECT_DIR='${REMOTE_PROJECT_DIR}' \
   FULL_IMAGE_NAME='${FULL_IMAGE_NAME}' \
   CONTAINER_NAME='${CONTAINER_NAME}' \
   bash -s" <<'EOF'
set -euo pipefail

# --- 0.0 Initialize Environment & Paths ---
BASE_DIR="$(dirname "${REMOTE_PROJECT_DIR%/}")"
mkdir -p "$BASE_DIR"
IMAGE_ARCHIVE_PATH="${BASE_DIR}/$IMAGE_ARCHIVE"
PROJECT_ARCHIVE_PATH="${BASE_DIR}/$PROJECT_ARCHIVE"
ANY_ACTION_TAKEN=0

# --- 0.1 File System Cleanup ---
if [ -d "${REMOTE_PROJECT_DIR%/}" ]; then
    rm -rf "${REMOTE_PROJECT_DIR%/}"
    echo "    [0.1] Removed remote directory: ${REMOTE_PROJECT_DIR%/}"
    ANY_ACTION_TAKEN=1
fi

if [ -f "$IMAGE_ARCHIVE_PATH" ]; then
    rm -f "$IMAGE_ARCHIVE_PATH"
    echo "    [0.1] Removed remote image archive: $IMAGE_ARCHIVE_PATH"
    ANY_ACTION_TAKEN=1
fi

if [ -f "$PROJECT_ARCHIVE_PATH" ]; then
    rm -f "$PROJECT_ARCHIVE_PATH"
    echo "    [0.1] Removed remote project archive: $PROJECT_ARCHIVE_PATH"
    ANY_ACTION_TAKEN=1
fi

# --- 0.2 Docker Container Cleanup ---
if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    if docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
        docker stop "$CONTAINER_NAME" >/dev/null
        echo "    [0.2] Stopped running container: $CONTAINER_NAME"
    fi
    docker rm "$CONTAINER_NAME" >/dev/null
    echo "    [0.2] Removed container: $CONTAINER_NAME"
    ANY_ACTION_TAKEN=1
fi

# --- 0.3 Docker Image Cleanup ---
if docker images --format '{{.Repository}}:{{.Tag}}' | grep -Fxq "$FULL_IMAGE_NAME"; then
    docker rmi "$FULL_IMAGE_NAME" >/dev/null
    echo "    [0.3] Removed image: $FULL_IMAGE_NAME"
    ANY_ACTION_TAKEN=1
fi

# --- 0.4 Status Summary ---
if [ "$ANY_ACTION_TAKEN" -eq 0 ]; then
    echo "    [0.4] Environment is already clean. No residual files or Docker resources found."
else
    echo "    [0.4] Remote cleanup completed successfully."
fi
EOF
)"

# 在本地输出收集到的远程日志
if [ -n "$REMOTE_PREP_OUTPUT" ]; then
    printf '%s\n' "$REMOTE_PREP_OUTPUT"
fi


# --- 1. Validate Local Container (检查本地容器) ---
log "1. Validating that container ${CONTAINER_NAME} is running..."
if ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  echo "Error: Container '${CONTAINER_NAME}' is not running. Start it before deploying." >&2
  exit 1
fi


# --- 2. Clean Local Dangling Images (清理本地悬空镜像) ---
log "2. Cleaning local dangling Docker images..."
if docker images -q -f "dangling=true" >/dev/null 2>&1; then
  DANGLING_IDS="$(docker images -q -f "dangling=true")"
  if [ -n "$DANGLING_IDS" ]; then
    docker rmi $DANGLING_IDS >/dev/null || true
    log "    Removed local dangling images."
  else
    log "    No local dangling images to remove."
  fi
fi

# --- 2.5 Clean Container Before Commit (提交前清理容器) ---
log "2.5 Cleaning container to speed up commit..."
docker exec "$CONTAINER_NAME" bash -c "
  # Remove NVIDIA driver libraries that were accidentally installed
  rm -rf /usr/lib/x86_64-linux-gnu/libnvidia* 2>/dev/null || true
  rm -rf /usr/lib/x86_64-linux-gnu/vdpau/libvdpau_nvidia* 2>/dev/null || true
  rm -rf /usr/lib/x86_64-linux-gnu/nvidia 2>/dev/null || true
  rm -rf /usr/lib/firmware/nvidia 2>/dev/null || true
  rm -rf /usr/lib/x86_64-linux-gnu/libGLX_nvidia.so* 2>/dev/null || true
  rm -rf /usr/lib/x86_64-linux-gnu/libEGL_nvidia.so* 2>/dev/null || true
  rm -rf /usr/lib/x86_64-linux-gnu/libGLESv2_nvidia.so* 2>/dev/null || true
  rm -rf /usr/lib/x86_64-linux-gnu/libGLESv1_CM_nvidia.so* 2>/dev/null || true

  # Clean Python cache
  find /workspace -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
  find /workspace -name '*.pyc' -delete 2>/dev/null || true
" >/dev/null 2>&1
log "    Container cleaned."

# --- 3. Package Docker Image (打包Docker镜像) ---
log "3. Committing running container ${CONTAINER_NAME} to image ${FULL_IMAGE_NAME}..."
docker commit "$CONTAINER_NAME" "$FULL_IMAGE_NAME" >/dev/null

log "    Saving image ${FULL_IMAGE_NAME} to archive ${LOCAL_IMAGE_ARCHIVE_PATH}..."
docker save "$FULL_IMAGE_NAME" | zstd -T0 > "$LOCAL_IMAGE_ARCHIVE_PATH"
# --- 4. Package Local Project (打包本地项目) ---
log "4. Packaging local project ${LOCAL_PROJECT_DIR} to archive ${LOCAL_PROJECT_ARCHIVE_PATH}..."
tar -cf "$LOCAL_PROJECT_ARCHIVE_PATH" -C "$(dirname "$LOCAL_PROJECT_DIR")" "$PROJECT_DIR_NAME"

log "    Local image archive:  ${LOCAL_IMAGE_ARCHIVE_PATH}"
log "    Local project archive: ${LOCAL_PROJECT_ARCHIVE_PATH}"

# --- 5. Transfer Archives (传输归档文件) ---
log "5. Transferring image archive to ${TARGET_SERVER}:${REMOTE_IMAGE_ARCHIVE_PATH}..."
scp -i "$SSH_KEY_PATH" "$LOCAL_IMAGE_ARCHIVE_PATH" "${TARGET_SERVER}:${REMOTE_IMAGE_ARCHIVE_PATH}"

log "    Transferring project archive to ${TARGET_SERVER}:${REMOTE_PROJECT_ARCHIVE_PATH}..."
scp -i "$SSH_KEY_PATH" "$LOCAL_PROJECT_ARCHIVE_PATH" "${TARGET_SERVER}:${REMOTE_PROJECT_ARCHIVE_PATH}"

log "    Remote image archive:  ${REMOTE_IMAGE_ARCHIVE_PATH}"
log "    Remote project archive: ${REMOTE_PROJECT_ARCHIVE_PATH}"

# --- 6. Remote Deployment (远端部署) ---
log "6. Loading image, unpacking project, and launching container on ${TARGET_SERVER}..."
ssh -i "$SSH_KEY_PATH" "$TARGET_SERVER" \
  "IMAGE_ARCHIVE='${IMAGE_ARCHIVE_NAME}' \
   PROJECT_ARCHIVE='${PROJECT_ARCHIVE_NAME}' \
   PROJECT_DIR_NAME='${PROJECT_DIR_NAME}' \
   REMOTE_PROJECT_DIR='${REMOTE_PROJECT_DIR}' \
   FULL_IMAGE_NAME='${FULL_IMAGE_NAME}' \
   CONTAINER_NAME='${CONTAINER_NAME}' \
   bash -s" <<'EOF'
set -euo pipefail

BASE_DIR="$(dirname "${REMOTE_PROJECT_DIR%/}")"
mkdir -p "$BASE_DIR"
IMAGE_ARCHIVE_PATH="${BASE_DIR}/$IMAGE_ARCHIVE"
PROJECT_ARCHIVE_PATH="${BASE_DIR}/$PROJECT_ARCHIVE"
EXTRACTED_PROJECT_PATH="${BASE_DIR}/$PROJECT_DIR_NAME"

# Validate archives exist
if [ ! -f "$IMAGE_ARCHIVE_PATH" ]; then
  echo "Error: Image archive not found: $IMAGE_ARCHIVE_PATH" >&2
  exit 1
fi

if [ ! -f "$PROJECT_ARCHIVE_PATH" ]; then
  echo "Error: Project archive not found: $PROJECT_ARCHIVE_PATH" >&2
  exit 1
fi

# Load Docker image
zstd -dcf "$IMAGE_ARCHIVE_PATH" | docker load 

# Verify image was loaded successfully
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -Fxq "$FULL_IMAGE_NAME"; then
  echo "Error: Failed to load Docker image: $FULL_IMAGE_NAME" >&2
  exit 1
fi

# Extract project archive
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

# Stop and remove existing container if it exists
if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  if docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    docker stop "$CONTAINER_NAME" >/dev/null
  fi
  docker rm "$CONTAINER_NAME" >/dev/null
  echo "  -> Removed remote container: $CONTAINER_NAME"
fi

# Start new container with Isaac Sim volumes
docker run --name "$CONTAINER_NAME" -itd --privileged --gpus all --network host \
  --entrypoint bash \
  -e ACCEPT_EULA=Y -e PRIVACY_CONSENT=Y \
  -v "$HOME/docker/isaac-sim/cache/kit:/isaac-sim/kit/cache:rw" \
  -v "$HOME/docker/isaac-sim/cache/ov:/root/.cache/ov:rw" \
  -v "$HOME/docker/isaac-sim/cache/pip:/root/.cache/pip:rw" \
  -v "$HOME/docker/isaac-sim/cache/glcache:/root/.cache/nvidia/GLCache:rw" \
  -v "$HOME/docker/isaac-sim/cache/computecache:/root/.nv/ComputeCache:rw" \
  -v "$HOME/docker/isaac-sim/logs:/root/.nvidia-omniverse/logs:rw" \
  -v "$HOME/docker/isaac-sim/data:/root/.local/share/ov/data:rw" \
  -v "$HOME/docker/isaac-sim/documents:/root/Documents:rw" \
  -v "${REMOTE_PROJECT_DIR%/}/.git:/workspace/.git" \
  -v "${REMOTE_PROJECT_DIR%/}/rsl_rl:/workspace/rsl_rl" \
  -v "${REMOTE_PROJECT_DIR%/}/drone_racer:/workspace/drone_racer" \
  "$FULL_IMAGE_NAME"

# Verify container is running
if ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  echo "Error: Container failed to start: $CONTAINER_NAME" >&2
  exit 1
fi
echo "  -> Container started successfully: $CONTAINER_NAME"

# Cleanup archives
rm -f "$IMAGE_ARCHIVE_PATH" "$PROJECT_ARCHIVE_PATH"
EOF

log "Deployment to ${TARGET_SERVER} completed successfully."
LOCAL_ARCHIVE_TMP_DIR_DISPLAY="$LOCAL_ARCHIVE_TMP_DIR"
cleanup
trap - EXIT
LOCAL_ARCHIVE_TMP_DIR=""
log "Removed local archive temp directory: ${LOCAL_ARCHIVE_TMP_DIR_DISPLAY}"
log "Done! You can now docker exec into the container to run your code."