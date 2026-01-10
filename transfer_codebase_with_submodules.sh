#!/usr/bin/env bash
#
# Creates a git diff patch from current workspace and deploys it to a remote server.
# This version supports GIT SUBMODULES - it detects, patches, and applies changes
# in both the main repository and all submodules.
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

# Auto-commit on remote after applying patch (远端自动提交)
# Default: false (changes remain in working directory for manual review)
# Set to "true" to automatically commit after applying patch
AUTO_COMMIT_REMOTE="${AUTO_COMMIT_REMOTE:-false}"

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
  echo "  LOCAL_TMP_DIR        Local temp directory (default: \$TMPDIR or /tmp/)"
  echo "  SSH_KEY_PATH         SSH key path (default: ~/.ssh/id_ed25519)"
  echo "  AUTO_COMMIT_REMOTE   Auto-commit on remote after apply (default: false)"
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

# Detect submodules with changes (commit hash or uncommitted files)
# Returns list of changed submodule paths
detect_changed_submodules() {
  local baseline="$1"
  local changed_submodules=()

  # Check if .gitmodules exists
  if [ ! -f .gitmodules ]; then
    # No submodules in this repository
    return 0
  fi

  # Get list of all submodules
  local submodule_paths
  submodule_paths="$(git config --file .gitmodules --get-regexp path 2>/dev/null | awk '{print $2}')"

  if [ -z "$submodule_paths" ]; then
    return 0
  fi

  for submodule_path in $submodule_paths; do
    local has_changes=false

    # Check 1: Submodule commit hash changed vs baseline
    local old_commit new_commit
    old_commit="$(git ls-tree "$baseline" "$submodule_path" 2>/dev/null | awk '{print $3}')"
    new_commit="$(git ls-tree HEAD "$submodule_path" 2>/dev/null | awk '{print $3}')"

    if [ "$old_commit" != "$new_commit" ]; then
      has_changes=true
      echo "  Submodule commit changed: $submodule_path (${old_commit:0:8} -> ${new_commit:0:8})" >&2
    fi

    # Check 2: Uncommitted changes within submodule
    if [ -d "$submodule_path/.git" ]; then
      if ! git -C "$submodule_path" diff --quiet 2>/dev/null || \
         ! git -C "$submodule_path" diff --cached --quiet 2>/dev/null; then
        has_changes=true
        echo "  Uncommitted changes in: $submodule_path" >&2
      fi
    fi

    if $has_changes; then
      changed_submodules+=("$submodule_path")
    fi
  done

  # Return list (one per line)
  printf '%s\n' "${changed_submodules[@]}"
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

# --- 1. Detect Submodule Changes ---
log "1. Detecting submodule changes..."
CHANGED_SUBMODULES=()
while IFS= read -r submodule; do
  [ -n "$submodule" ] && CHANGED_SUBMODULES+=("$submodule")
done < <(detect_changed_submodules "${BASELINE_COMMIT}")

if [ ${#CHANGED_SUBMODULES[@]} -gt 0 ]; then
  log_success "Found ${#CHANGED_SUBMODULES[@]} changed submodules: ${CHANGED_SUBMODULES[*]}"
else
  log "No submodule changes detected"
fi

# --- 2. Create Patch Bundle Directory ---
PATCH_DIR="${LOCAL_TMP_DIR%/}/patch_bundle_${TIMESTAMP}"
mkdir -p "$PATCH_DIR"

# --- 3. Create Main Repository Patch ---
log "2. Creating git diff patch for main repository..."

# Check if there are any changes in main repo (excluding submodules)
if git diff --quiet "${BASELINE_COMMIT}" 2>/dev/null; then
  log_warning "No changes detected in main repository"
  # Create empty main.patch for consistency
  touch "$PATCH_DIR/main.patch"
else
  # Create the patch (exclude submodule directory changes)
  git diff "${BASELINE_COMMIT}" > "$PATCH_DIR/main.patch"

  # Verify patch was created and is not empty
  if [ ! -s "$PATCH_DIR/main.patch" ]; then
    log_error "Failed to create main repository patch"
    exit 1
  fi

  MAIN_PATCH_SIZE="$(du -h "$PATCH_DIR/main.patch" | cut -f1)"
  log_success "Main patch created (${MAIN_PATCH_SIZE})"
fi

# --- 4. Create Submodule Patches ---
for submodule in "${CHANGED_SUBMODULES[@]}"; do
  log "Creating patch for submodule: $submodule"

  # Determine baseline for submodule (commit recorded in baseline)
  local old_submodule_commit
  old_submodule_commit="$(git ls-tree "${BASELINE_COMMIT}" "$submodule" 2>/dev/null | awk '{print $3}')"

  if [ -z "$old_submodule_commit" ]; then
    log_warning "  No previous commit recorded for $submodule, using HEAD~1"
    old_submodule_commit="HEAD~1"
  fi

  # Create patch within submodule
  local patch_name="${submodule##*/}.patch"
  local patch_path="$PATCH_DIR/$patch_name"

  if ! git -C "$submodule" diff "${old_submodule_commit}" > "$patch_path" 2>/dev/null; then
    log_warning "  Failed to create patch for $submodule"
    rm -f "$patch_path"
    continue
  fi

  if [ -s "$patch_path" ]; then
    local patch_size
    patch_size="$(du -h "$patch_path" | cut -f1)"
    log_success "  Submodule patch created: $patch_name (${patch_size})"
  else
    log_warning "  No actual changes in $submodule, skipping patch"
    rm -f "$patch_path"
  fi
done

# --- 5. Create Manifest and Bundle ---
cat > "$PATCH_DIR/MANIFEST.txt" <<EOF
Patch Bundle Manifest
=====================
Timestamp: ${TIMESTAMP}
Baseline Commit: ${BASELINE_COMMIT}
Main Repository: main.patch
Submodules:
$(for sm in "${CHANGED_SUBMODULES[@]}"; do
  if [ -f "$PATCH_DIR/${sm##*/}.patch" ]; then
    echo "  - $sm: ${sm##*/}.patch"
  fi
done)
EOF

# Create bundle archive
log "5. Creating patch bundle archive..."
cd "$PATCH_DIR/.."
tar -czf "${LOCAL_PATCH_PATH}" "patch_bundle_${TIMESTAMP}"
cd "$LOCAL_PROJECT_DIR"
rm -rf "$PATCH_DIR"

BUNDLE_SIZE="$(du -h "$LOCAL_PATCH_PATH" | cut -f1)"
log_success "Patch bundle created (${BUNDLE_SIZE}): ${LOCAL_PATCH_PATH}"

# --- 6. Show Summary of Changes ---
log "Summary of changes:"
git diff --stat "${BASELINE_COMMIT}" | sed 's/^/      /'

# ======================================================================================

# --- 6. Upload Patch Bundle to Remote Server ---
log "6. Uploading patch bundle to ${TARGET_SERVER}:${REMOTE_PATCH_PATH}..."
scp -i "$SSH_KEY_PATH" "$LOCAL_PATCH_PATH" "${TARGET_SERVER}:${REMOTE_PATCH_PATH}"
log_success "Patch uploaded successfully"

# --- 7. Apply Patch Bundle on Remote Server ---
log "7. Applying patch bundle on remote server..."
REMOTE_OUTPUT="$(ssh -i "$SSH_KEY_PATH" "$TARGET_SERVER" \
  "PATCH_BUNDLE='${REMOTE_PATCH_PATH}' \
   REMOTE_PROJECT_DIR='${REMOTE_PROJECT_DIR}' \
   BASELINE_COMMIT='${BASELINE_COMMIT}' \
   AUTO_COMMIT_REMOTE='${AUTO_COMMIT_REMOTE}' \
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
}

# Check git status - if uncommitted changes exist, reset them
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  log_warning "Remote working directory has uncommitted changes"
  log "Resetting remote workspace (git reset --hard)..."
  git reset --hard HEAD
  log_success "Remote workspace reset to clean state"
fi

# Extract patch bundle
EXTRACT_DIR="$(dirname "${REMOTE_PROJECT_DIR%/}")/patch_extract_$$"
mkdir -p "$EXTRACT_DIR"
log "Extracting patch bundle to: $EXTRACT_DIR"
tar -xzf "$PATCH_BUNDLE" -C "$EXTRACT_DIR" || {
  log_error "Failed to extract patch bundle"
  exit 1
}

# Show manifest if available
if [ -f "$EXTRACT_DIR/MANIFEST.txt" ]; then
  log "Patch bundle manifest:"
  cat "$EXTRACT_DIR/MANIFEST.txt" | sed 's/^/  /'
fi

# Apply main repository patch
MAIN_PATCH="$EXTRACT_DIR/main.patch"
if [ -f "$MAIN_PATCH" ]; then
  log "Applying main repository patch..."
  if [ -s "$MAIN_PATCH" ]; then
    APPLY_OUTPUT="$(git apply --check "$MAIN_PATCH" 2>&1)" || true
    APPLY_EXIT=$?

    if [ $APPLY_EXIT -eq 0 ]; then
      git apply "$MAIN_PATCH"
      log_success "Main patch applied successfully"
    else
      log_error "Main patch does not apply cleanly"
      log "git apply --check output:"
      printf '%s\n' "$APPLY_OUTPUT" | sed 's/^/    /'
      exit 1
    fi
  else
    log "Main patch is empty, skipping"
  fi
fi

# Initialize submodules if any exist
if [ -f .gitmodules ]; then
  log "Initializing submodules..."
  git submodule update --init --recursive 2>/dev/null || true
  log_success "Submodules initialized"
fi

# Apply submodule patches
for patch_file in "$EXTRACT_DIR"/*.patch; do
  # Skip main.patch and MANIFEST.txt
  [ "$(basename "$patch_file")" = "main.patch" ] && continue
  [ "$(basename "$patch_file")" = "MANIFEST.txt" ] && continue
  [ ! -f "$patch_file" ] && continue

  # Extract submodule name from patch filename
  submodule_name="$(basename "$patch_file" .patch)"
  log "Applying patch for submodule: $submodule_name"

  # Find the submodule path
  submodule_path=""
  if git config --file .gitmodules --get-regexp path >/dev/null 2>&1; then
    for sm_path in $(git config --file .gitmodules --get-regexp path | awk '{print $2}'); do
      if [ "$(basename "$sm_path")" = "$submodule_name" ]; then
        submodule_path="$sm_path"
        break
      fi
    done
  fi

  if [ -z "$submodule_path" ]; then
    log_warning "  Could not find submodule path for: $submodule_name"
    continue
  fi

  # Check if submodule directory exists
  if [ ! -d "$submodule_path" ]; then
    log_warning "  Submodule directory not found: $submodule_path"
    continue
  fi

  # Apply patch within submodule
  cd "$submodule_path" || {
    log_warning "  Cannot enter $submodule_path, skipping"
    cd "${REMOTE_PROJECT_DIR%/}"
    continue
  }

  # Check if submodule is a valid git repo
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    log_warning "  Not a valid git repository: $submodule_path"
    cd "${REMOTE_PROJECT_DIR%/}"
    continue
  fi

  # Check and apply patch
  APPLY_OUTPUT="$(git apply --check "$patch_file" 2>&1)" || true
  APPLY_EXIT=$?

  if [ $APPLY_EXIT -eq 0 ]; then
    git apply "$patch_file"
    log_success "  Submodule patch applied: $submodule_name"
  else
    log_warning "  Submodule patch does not apply cleanly to $submodule_name"
    log "  git apply --check output:"
    printf '%s\n' "$APPLY_OUTPUT" | sed 's/^/    /'
  fi

  cd "${REMOTE_PROJECT_DIR%/}"
done

# Update submodule references in main repo
if [ -f .gitmodules ]; then
  log "Updating submodule references..."
  for submodule_path in $(git config --file .gitmodules --get-regexp path | awk '{print $2}'); do
    if [ -d "$submodule_path/.git" ]; then
      git add "$submodule_path"
    fi
  done
  log_success "Submodule references updated"
fi

# Show changes
log "Summary of applied changes:"
git diff --stat | sed 's/^/    /'

# Auto-commit if requested
if [ "$AUTO_COMMIT_REMOTE" = "true" ]; then
  log "Auto-committing changes on remote..."
  git add -A
  git commit -m "Deployed from local via transfer_codebase_with_submodules.sh"
  log_success "Changes committed on remote"
fi

# Cleanup
rm -rf "$EXTRACT_DIR"
rm -f "$PATCH_BUNDLE"
log_success "Cleanup completed"

EOF
)" || true

if [ -n "$REMOTE_OUTPUT" ]; then
  printf '%s\n' "$REMOTE_OUTPUT"
fi

# --- 6. Cleanup Local Patch ---
log "6. Cleaning up local patch file..."
rm -f "$LOCAL_PATCH_PATH"
log_success "Removed local patch: ${LOCAL_PATCH_PATH}"

# --- 7. Get Remote HEAD After Deployment ---
log ""
log "7. Verifying remote state..."

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
      log "Remote HEAD unchanged (expected with git apply - changes are in working directory only)"
      log "Commit the changes on remote to update HEAD: cd ${REMOTE_PROJECT_DIR} && git commit -am 'Deployed from local'"
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
