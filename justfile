build-sim:
    docker build -f docker/isaacsim5.dockerfile \
    --network=host \
    -t lab2.3-sim5.1:v0 .


run-sim:
    docker run --name lab2.3-sim5.1 -itd --privileged --gpus all --network host \
    --entrypoint bash \
    --runtime=nvidia \
    -e ACCEPT_EULA=Y -e PRIVACY_CONSENT=Y \
    -e DISPLAY -e QT_X11_NO_MITSHM=1 \
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
    -v ${HOME}/server/.git:/workspace/.git \
    -v ${HOME}/server/rsl_rl:/workspace/rsl_rl \
    -v ${HOME}/server/drone_racer:/workspace/drone_racer \
    lab2.3-sim5.1:v0

exec-sim:
    docker exec -it lab2.3-sim5.1 /bin/bash

stop-sim:
    docker stop lab2.3-sim5.1 || true && \
    docker rm lab2.3-sim5.1 || true

start:
    docker restart lab2.3-sim5.1:v0

alias b := build-sim
alias r := run-sim
alias e := exec-sim
alias s := stop-sim
