# Deployment Guide

## Overview

This project supports both local development and remote server deployment. The same commands (`just run-sim`, etc.) work identically on both local machine and server because:

1. **Project structure is preserved** during deployment
2. **Justfile uses dynamic paths** (`project_root := justfile_directory()`)
3. **Docker image names adapt to hostname** via `TAG_NAME` variable

## Deployment Scripts

### 1. `deploy_to_server.sh` - Full Deployment

Deploys both the Docker container AND project code to the remote server.

```bash
# Usage
./deploy_to_server.sh <target-server>

# Example
./deploy_to_server.sh rec-server
```

**What it does:**
1. Validates local container is running
2. Commits running container to a new image (tagged by target server)
3. Packages Docker image (compressed with zstd)
4. Packages project code as tar archive
5. Transfers both archives to remote server
6. Remote: loads image, extracts code, stops old container
7. Container is ready to run with `just run-sim` on server

**Environment Variables:**
- `LOCAL_PROJECT_DIR` - Default: `$HOME/server/`
- `REMOTE_PROJECT_DIR` - Default: `/data/nvme_data/rec_ws/server/`
- `CONTAINER_NAME` - Default: `rec-lab2.3-sim5.1`
- `IMAGE_NAME` - Default: `rec-lab2.3-sim5.1`
- `SSH_KEY_PATH` - Default: `~/.ssh/id_ed25519`

### 2. `deploy_project_codebase.sh` - Code-Only Deployment

Deploys ONLY the project code (no Docker container). Use this when the remote environment is already set up.

```bash
# Usage
./deploy_project_codebase.sh <target-server>

# Example
./deploy_project_codebase.sh rec-server
```

**What it does:**
1. Packages project directory as tar archive
2. Transfers archive to remote server
3. Remote: removes old project directory, extracts new one
4. Faster than full deployment (no Docker image transfer)

### 3. `download_from_server.sh` - Download Logs

Downloads training logs from remote server to local machine.

```bash
# Usage
./download_from_server.sh <HOST> [REMOTE_PATH]

# Examples
./download_from_server.sh rec-server
./download_from_server.sh rec-server /custom/log/path
```

**What it does:**
1. Uses rsync to efficiently sync logs
2. Saves to timestamped directory: `~/server_logs/<HOST>_<TIMESTAMP>/`
3. Default remote path: `/root/server_logs/drone_racer/logs`

## Key Design Principle

> **The same `just` commands work on both local and server because deployment preserves the project structure exactly.**

### How It Works

The justfile at `/home/rec/server/justfile`:

```justfile
project_root := justfile_directory()  # Dynamically resolves to server/ directory
TAG_NAME := if hostname == "dcj" { "train-server-ali" } else { "v0" }
```

- `project_root` resolves to the directory containing the justfile
- All volume mounts use `{{project_root}}`, so they work anywhere
- `TAG_NAME` adapts to the hostname, defaulting to `"v0"` on servers

### Volume Mounts (work identically on local and server)

```bash
-v {{project_root}}/.git:/workspace/.git
-v {{project_root}}/rsl_rl:/workspace/rsl_rl
-v {{project_root}}/drone_racer:/workspace/drone_racer
```

## Workflow

### Initial Setup (One-Time)
```bash
# 1. Build image locally
just build-sim

# 2. Run container locally
just run-sim

# 3. Full deploy to server (container + code)
./deploy_to_server.sh rec-server

# 4. On server: run with same command
just run-sim
```

### Iterative Development
```bash
# 1. Edit code locally
# 2. Deploy only code changes (faster)
./deploy_project_codebase.sh rec-server

# 3. On server: restart container to pick up changes
docker restart <container-name>
```

### Downloading Results
```bash
# Download logs from server
./download_from_server.sh rec-server
```

## Supported Servers

- `rec-server` - Main server
- `wu` - Alternative server
- `ali` - Aliyun server
