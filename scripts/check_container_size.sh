#!/usr/bin/env bash
#
# Diagnostic script to identify what's making docker commit slow
#

# Source common logging functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common/log_funcs.sh"

if [ "$#" -lt 1 ]; then
  log_error "Usage: $(basename "$0") <container-name>"
  exit 1
fi

CONTAINER_NAME="$1"

log "=== Analyzing container: $CONTAINER_NAME ==="
log ""

# 1. Check container size (if docker reports it)
log "1. Container size info:"
docker ps -s --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Size}}"
log ""

# 2. Find largest directories in container
log "2. Top 10 largest directories in container:"
docker exec "$CONTAINER_NAME" bash -c "du -sh /workspace/* 2>/dev/null | sort -rh | head -10" || log_warning "  (Could not access /workspace)"
log ""

# 3. Check for common build artifacts
log "3. Checking for build artifacts:"
log "  Python cache files:"
docker exec "$CONTAINER_NAME" bash -c "find /workspace -type d -name '__pycache__' 2>/dev/null | wc -l" 2>/dev/null || log_warning "  (Not found or no access)"
log "  .pyc files:"
docker exec "$CONTAINER_NAME" bash -c "find /workspace -name '*.pyc' 2>/dev/null | wc -l" 2>/dev/null || log_warning "  (Not found or no access)"
log "  node_modules:"
docker exec "$CONTAINER_NAME" bash -c "du -sh /workspace/*/node_modules 2>/dev/null" || log_warning "  (Not found)"
log ""

# 4. Check for large log files
log "4. Large log files (>10MB):"
docker exec "$CONTAINER_NAME" bash -c "find /workspace -name '*.log' -size +10M -exec ls -lh {} \; 2>/dev/null" || log_warning "  (No large log files found)"
log ""

# 5. Check for temporary/cache directories
log "5. Cache directories:"
docker exec "$CONTAINER_NAME" bash -c "du -sh ~/.cache ~/.pip 2>/dev/null" || log_warning "  (Not found)"
log ""

# 6. Show what would be committed (changes since base image)
log "6. Filesystem changes (this is what gets committed):"
log "  Running 'docker diff' to show changed files..."
docker diff "$CONTAINER_NAME" | head -50
log "  ... (showing first 50 lines)"
log ""

log "=== Recommendations ==="
log "If commit is slow due to:"
log "  - Build artifacts: Add .dockerignore with __pycache__, *.pyc, etc."
log "  - Large logs: Clean them before committing or add to .dockerignore"
log "  - Large datasets: Consider using volumes instead of storing in container"
log "  - Many small files: Consider cleaning up temp files before committing"