project_root := justfile_directory()
hostname := `hostname`
TAG_NAME := if hostname == "dcj" { "train-server-ali" } else if hostname == "wfzf" { "v0" } else { "v0" }
tmp_dirname := `cd .. && pwd`
SERVER_LOGS_DIR := tmp_dirname + "/server_logs"

echo-tag: 
    echo {{TAG_NAME}}

echo-logs-dir:
    echo "SERVER_LOGS_DIR: {{SERVER_LOGS_DIR}}"

build-sim:
    docker build -f docker/isaacsim5.dockerfile \
    --network=host \
    -t {{env_var("USER")}}-lab-main-sim5.1:{{TAG_NAME}} .

build-sim-ros2:
    docker build -f docker/isaacsim5_ros2.dockerfile \
    --network=host \
    -t {{env_var("USER")}}-lab-main-sim5.1-ros2:{{TAG_NAME}} .


run-sim:
    docker run --name {{env_var("USER")}}-lab-main-sim5.1-ros2:{{TAG_NAME}} \
    -itd --privileged --gpus all --network host \
    --entrypoint bash \
    --runtime=nvidia \
    -e ACCEPT_EULA=Y -e PRIVACY_CONSENT=Y \
    -e DISPLAY -e QT_X11_NO_MITSHM=1 \
    -e PYTHONDONTWRITEBYTECODE=1 \
    -v $HOME/.Xauthority:/root/.Xauthority \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v ~/docker/isaac-sim5.1/cache/kit:/isaac-sim/kit/cache:rw \
    -v ~/docker/isaac-sim5.1/cache/ov:/root/.cache/ov:rw \
    -v ~/docker/isaac-sim5.1/cache/pip:/root/.cache/pip:rw \
    -v ~/docker/isaac-sim5.1/cache/glcache:/root/.cache/nvidia/GLCache:rw \
    -v ~/docker/isaac-sim5.1/cache/computecache:/root/.nv/ComputeCache:rw \
    -v ~/docker/isaac-sim5.1/logs:/root/.nvidia-omniverse/logs:rw \
    -v ~/docker/isaac-sim5.1/data:/root/.local/share/ov/data:rw \
    -v ~/docker/isaac-sim5.1/documents:/root/Documents:rw \
    -v {{project_root}}/.git:/workspace/.git \
    -v {{project_root}}/rsl_rl:/workspace/rsl_rl \
    -v {{project_root}}/drone_racer:/workspace/drone_racer \
    -v {{SERVER_LOGS_DIR}}:/root/server_logs:rw \
    -v {{SERVER_LOGS_DIR}}/outputs:/workspace/drone_racer/outputs:rw \
    {{env_var("USER")}}-lab-main-sim5.1-ros2:{{TAG_NAME}}

run-sim-ros2:
    docker run --name {{env_var("USER")}}-lab-main-sim5.1-ros2:{{TAG_NAME}} \
    -itd --privileged --gpus all --network host \
    --entrypoint bash \
    --runtime=nvidia \
    -e ACCEPT_EULA=Y -e PRIVACY_CONSENT=Y \
    -e DISPLAY -e QT_X11_NO_MITSHM=1 \
    -e PYTHONDONTWRITEBYTECODE=1 \
    -v $HOME/.Xauthority:/root/.Xauthority \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v ~/docker/isaac-sim5.1/cache/kit:/isaac-sim/kit/cache:rw \
    -v ~/docker/isaac-sim5.1/cache/ov:/root/.cache/ov:rw \
    -v ~/docker/isaac-sim5.1/cache/pip:/root/.cache/pip:rw \
    -v ~/docker/isaac-sim5.1/cache/glcache:/root/.cache/nvidia/GLCache:rw \
    -v ~/docker/isaac-sim5.1/cache/computecache:/root/.nv/ComputeCache:rw \
    -v ~/docker/isaac-sim5.1/logs:/root/.nvidia-omniverse/logs:rw \
    -v ~/docker/isaac-sim5.1/data:/root/.local/share/ov/data:rw \
    -v ~/docker/isaac-sim5.1/documents:/root/Documents:rw \
    -v {{project_root}}/.git:/workspace/.git \
    -v {{project_root}}/rsl_rl:/workspace/rsl_rl \
    -v {{project_root}}/drone_racer:/workspace/drone_racer \
    -v {{SERVER_LOGS_DIR}}:/root/server_logs:rw \
    -v {{SERVER_LOGS_DIR}}/outputs:/workspace/drone_racer/outputs:rw \
    {{env_var("USER")}}-lab-main-sim5.1-ros2:{{TAG_NAME}}


exec-sim-ros2:
    docker exec -it {{env_var("USER")}}-lab-main-sim5.1-ros2:{{TAG_NAME}} /bin/bash

stop-sim-ros2:
    docker stop {{env_var("USER")}}-lab-main-sim5.1-ros2:{{TAG_NAME}} || true && \
    docker rm {{env_var("USER")}}-lab-main-sim5.1-ros2:{{TAG_NAME}} || true

start-sim-ros2:
    docker restart {{env_var("USER")}}-lab-main-sim5.1-ros2:{{TAG_NAME}}


alias b := build-sim-ros2
alias r := run-sim-ros2
alias e := exec-sim-ros2
alias s := stop-sim-ros2

# ======================================================================================
# Remote Server Sync Commands
# ======================================================================================

# Full transfer: Upload entire codebase to remote server (tar-based)
# Environment variables: SERVER_IP, REMOTE_USER, LOCAL_PROJECT_DIR, REMOTE_PROJECT_DIR
push-all:
    ./scripts/transfer_codebase.sh

# Incremental transfer: Upload local changes to remote server (git diff-based)
# Environment variables: SERVER_IP, REMOTE_USER, LOCAL_PROJECT_DIR, REMOTE_PROJECT_DIR
push-incremental:
    ./scripts/transfer_codebase_incremental.sh

# Sync training logs from remote server to local
sync-logs:
    ./scripts/sync_server_logs.sh

# Create SSH tunnel for tensorboard (local_port remote_port server_ip)
tb-local-tunnel local_port remote_port server_ip:
    ssh -N -L {{local_port}}:localhost:{{remote_port}} zhw@{{server_ip}}