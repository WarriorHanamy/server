# Push to Server Procedure

This document describes the deployment system for pushing code from the local development environment to the remote server.

## Overview

The deployment system provides two main strategies for transferring code to the remote server:

| Strategy | Script | Use Case | Transfer Size |
|----------|--------|----------|---------------|
| Full Deployment | `transfer_codebase.sh` | Clean deployments, first-time setup | Entire codebase |
| Incremental Deployment | `transfer_codebase_incremental.sh` | Frequent updates, preserves history | Only changes |

Additional utilities:
- `push_submodule.sh` - Check and push submodule changes to Git remote
- `sync_server_logs.sh` - Continuously sync training logs from remote

## Prerequisites

### Required Tools
- `ssh` - Remote shell access
- `scp` - Secure copy for file transfers
- `rsync` - Efficient file synchronization
- `tar` - Archive creation
- `git` - Version control

### SSH Access
Ensure SSH key authentication is configured:
```bash
# Test SSH connection
ssh -i ~/.ssh/id_rsa.pub zhw@14.103.52.172
```

## Configuration

All scripts share common configuration via environment variables:

| Variable | Default Value | Description |
|----------|---------------|-------------|
| `SERVER_IP` | `14.103.52.172` | Remote server IP address |
| `REMOTE_USER` | `zhw` | Remote user account |
| `LOCAL_PROJECT_DIR` | `$HOME/framework/server/` | Local project directory |
| `REMOTE_PROJECT_DIR` | `/home/zhw/framework/server/` | Remote project directory |
| `SSH_KEY_PATH` | `$HOME/.ssh/id_rsa.pub` | SSH private key path |

### Customizing Configuration

You can override defaults by setting environment variables:

```bash
# Use custom server IP
SERVER_IP=192.168.1.100 ./scripts/transfer_codebase.sh

# Use custom SSH key
SSH_KEY_PATH=~/.ssh/custom_key ./scripts/transfer_codebase.sh
```

## Script Reference

### 1. `push_submodule.sh`

Checks if the `drone_racer` submodule can be pushed to its Git remote and handles the push if possible.

**Usage:**
```bash
./scripts/push_submodule.sh
```

**States Handled:**
- **Ahead**: Can push directly (fast-forward). Script will prompt to push.
- **Behind**: Cannot push. Must pull/rebase first.
- **Diverged**: Cannot push. Histories have forked, must rebase.

**Example Output:**
```
========================================
Checking drone_racer submodule status...
========================================
(1) Checking submodule exists...
    OK: Submodule found
(2) Fetching remote and comparing commits...
    Current HEAD: a1b2c3d
    Remote main: e5f6g7h
(3) Determining if push is possible...

    => CAN PUSH to origin/main (fast-forward)
    => 2 commit(s) ahead

    Commits to push:
          a1b2c3d Fix training bug
          b2c3d4e Add new feature

    Push now? (y/n)
```

### 2. `transfer_codebase.sh`

Performs a **full destructive deployment** to the remote server. The remote directory is completely removed before deployment.

**Usage:**
```bash
./scripts/transfer_codebase.sh
```

**Process:**
1. Prompts for confirmation (safety check)
2. Removes remote directory completely
3. Creates tar archive of local codebase
4. Transfers archive via rsync
5. Extracts archive on remote server
6. Cleans up temporary files

**Excludes:** The `shared/` directory from transfer

**Warning:** This is destructive - all remote changes will be lost.

**Example:**
```
==========================================
Transfer Codebase
==========================================

Configuration:
  Local Path:      /home/rec/framework/server/
  Remote Path:     /home/zhw/framework/server/
  Target Server:   zhw@14.103.52.172
  SSH Key:         /home/rec/.ssh/id_rsa.pub

================================================================================
  WARNING: This will perform destructive operations on zhw@14.103.52.172:
================================================================================
  - Remove remote directory: /home/zhw/framework/server/

  The following will be deployed:
  - Project code from: /home/rec/framework/server/
================================================================================

Do you want to proceed? (yes/no):
```

### 3. `transfer_codebase_incremental.sh`

Performs **incremental deployment** using git diff. Only transfers changes, preserving remote git history.

**Usage:**
```bash
./scripts/transfer_codebase_incremental.sh
```

**Process:**
1. Queries remote repository state (HEAD commits)
2. Creates git bundles for committed changes
3. Creates patches for uncommitted changes
4. Handles submodules separately
5. Transfers Git LFS files
6. Applies changes on remote server
7. Fixes LFS pointer files

**Features:**
- Handles both committed and uncommitted changes
- Preserves git history on remote
- Handles Git LFS files properly
- Works with submodules

**Example Output:**
```
==========================================
Transfer Codebase by Git Diff
==========================================

Configuration:
  Local Path:      /home/rec/framework/server/
  Remote Path:     /home/zhw/framework/server/
  Target Server:   zhw@14.103.52.172

0. Querying remote repository state...
  Remote main HEAD: a1b2c3d4
  Remote drone_racer HEAD: e5f6g7h

1. Creating bundles and patches...
  main repo: Bundle created (a1b2c3d..b2c3d4e)
  main repo: Uncommitted patch created (12K)
  drone_racer: Bundle created (e5f6g7h..f7g8h9i)

[12:34:56] Created 2 bundle(s) and 1 patch(es)

2. Uploading to remote server...
  Uploaded: main.bundle
  Uploaded: drone_racer.bundle
  Uploaded: main.patch

[12:35:02] All files uploaded

3. Applying changes on remote server...
[12:35:03] Applying bundles (commits)...
[12:35:04] Resetting to b2c2d4e...
[12:35:04] main repo: Reset to b2c3d4e
[12:35:05] drone_racer: Reset to f7g8h9i

4. Transferring LFS files (3 files)...

5. Checking for LFS pointer files on remote...

==========================================
Deployment completed!
==========================================
```

### 4. `sync_server_logs.sh`

Continuously monitors and syncs training logs from the remote server to local directory.

**Usage:**
```bash
# Continuous sync with default settings
./scripts/sync_server_logs.sh

# Custom sync interval (5 seconds)
./scripts/sync_server_logs.sh -i 5

# Single sync and exit
./scripts/sync_server_logs.sh --once

# Custom paths
./scripts/sync_server_logs.sh -r /remote/path -l /local/path
```

**Options:**
| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-i, --interval SEC` | Sync interval in seconds (default: 10) |
| `-r, --remote PATH` | Remote log directory path |
| `-l, --local PATH` | Local log directory path |
| `-1, --once` | Sync once and exit |

**Environment Variables:**
| Variable | Default |
|----------|---------|
| `REMOTE_LOG_DIR` | `/home/zhw/framework/server_logs` |
| `LOCAL_LOG_DIR` | `$HOME/framework/server_logs` |
| `SYNC_INTERVAL` | `10` (seconds) |

**Features:**
- Incremental sync (only adds new/updated files)
- Never deletes local files
- Fixes file permissions on sync
- Handles connection failures gracefully

## Workflows

### Full Deployment Workflow

Use this for:
- First-time deployment
- When remote state is corrupted
- Clean slate deployments

```bash
# 1. Ensure you're on the correct branch
git checkout main

# 2. Commit any changes
git add -A
git commit -m "Prepare for deployment"

# 3. Run full deployment
./scripts/transfer_codebase.sh

# 4. Type "yes" when prompted
```

### Incremental Deployment Workflow (Recommended)

Use this for:
- Frequent updates during development
- When you want to preserve remote history
- Faster deployments

```bash
# Option 1: Deploy with committed changes
git add -A
git commit -m "Update feature"
./scripts/transfer_codebase_incremental.sh

# Option 2: Deploy with uncommitted changes
# (includes both committed and uncommitted)
./scripts/transfer_codebase_incremental.sh
```

### Submodule Management Workflow

```bash
# 1. Make changes in submodule
cd drone_racer
# ... make changes ...
git add -A
git commit -m "Update submodule"

# 2. Check and push submodule
cd ..
./scripts/push_submodule.sh

# 3. If prompted, type 'y' to push

# 4. Update main repo submodule reference
git add drone_racer
git commit -m "Update submodule reference"

# 5. Deploy (incremental or full)
./scripts/transfer_codebase_incremental.sh
```

### Log Synchronization Workflow

```bash
# Terminal 1: Start training on remote (if needed)
ssh zhw@14.103.52.172
cd /home/zhw/framework/server
# ... start training ...

# Terminal 2: Sync logs locally
./scripts/sync_server_logs.sh -i 5

# Logs will be synced to ~/framework/server_logs/
```

## Troubleshooting

### SSH Connection Issues

**Problem:** Cannot connect to remote server

```bash
# Test SSH connection
ssh -i ~/.ssh/id_rsa.pub zhw@14.103.52.172

# If connection fails, check:
# 1. SSH key exists
ls -la ~/.ssh/id_rsa.pub

# 2. Server is reachable
ping 14.103.52.172

# 3. Firewall settings
```

### Permission Denied

**Problem:** Permission denied when accessing remote directories

```bash
# Verify remote directory exists
ssh zhw@14.103.52.172 "ls -la /home/zhw/framework/"

# Check SSH key permissions
chmod 600 ~/.ssh/id_rsa.pub
```

### Git Submodule Issues

**Problem:** Submodule is not initialized

```bash
# Initialize submodules
git submodule update --init --recursive

# Update submodules to latest
git submodule update --remote
```

### LFS Pointer Files on Remote

**Problem:** Files show as LFS pointers instead of actual content

The incremental script automatically handles this by:
1. Detecting LFS pointer files on remote
2. Transferring actual content from local
3. Replacing pointers with real files

If issues persist, run:
```bash
# On remote server
ssh zhw@14.103.52.172
cd /home/zhw/framework/server/drone_racer
git lfs pull
```

### Patch Apply Failures

**Problem:** `transfer_codebase_incremental.sh` fails to apply patches

**Solution:** The remote workspace has uncommitted changes that conflict. The script will clean these automatically. If issues persist:

```bash
# On remote server, manually clean
ssh zhw@14.103.52.172
cd /home/zhw/framework/server
git reset --hard HEAD
git clean -fd
cd drone_racer
git reset --hard HEAD
git clean -fd
```

Then re-run the incremental deployment from local.

### Sync Logs Not Working

**Problem:** `sync_server_logs.sh` shows "Remote directory not found"

```bash
# Verify remote log directory exists
ssh zhw@14.103.52.172 "ls -la /home/zhw/framework/server_logs"

# Create if missing
ssh zhw@14.103.52.172 "mkdir -p /home/zhw/framework/server_logs"
```
