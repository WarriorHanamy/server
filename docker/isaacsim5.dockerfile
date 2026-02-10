ARG ISAACSIM_BASE_IMAGE=nvcr.io/nvidia/isaac-sim
ARG ISAACSIM_VERSION=5.1.0

FROM ${ISAACSIM_BASE_IMAGE}:${ISAACSIM_VERSION} AS simulation

ARG ISAACSIM_PATH=/isaac-sim
ARG ISAACLAB_PATH=/workspace/isaaclab
ARG DOCKER_USER_HOME=/root

# ${ISAACLAB_PATH}/_isaac_sim is a symlink to ${ISAACSIM_PATH}

ENV ISAACSIM_VERSION=${ISAACSIM_VERSION} \
    ISAACLAB_PATH=${ISAACLAB_PATH} \
    ISAACSIM_PATH=${ISAACSIM_PATH} \
    DOCKER_USER_HOME=${DOCKER_USER_HOME} \
    LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    FASTRTPS_DEFAULT_PROFILES_FILE=${DOCKER_USER_HOME}/.ros/fastdds.xml \
    CYCLONEDDS_URI=${DOCKER_USER_HOME}/.ros/cyclonedds.xml \
    OMNI_KIT_ALLOW_ROOT=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all \
    PATH="/root/.local/bin:$PATH"

SHELL ["/bin/bash", "-c"]

USER root

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    libglib2.0-0 \
    ncurses-term \
    wget \
    curl \
    gedit \
    tmux \
    software-properties-common



WORKDIR /workspace
COPY ./IsaacLab ${ISAACLAB_PATH}
RUN chmod +x ${ISAACLAB_PATH}/isaaclab.sh
RUN ln -sf ${ISAACSIM_PATH} ${ISAACLAB_PATH}/_isaac_sim

ENV PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
ENV PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn
ENV PIP_DEFAULT_TIMEOUT=100
RUN ${ISAACLAB_PATH}/isaaclab.sh -p -m pip install --upgrade pip
RUN ${ISAACLAB_PATH}/isaaclab.sh -i


RUN echo "export ISAACLAB_PATH=${ISAACLAB_PATH}" >> ${DOCKER_USER_HOME}/.bashrc && \
    echo "alias isaaclab=${ISAACLAB_PATH}/isaaclab.sh" >> ${DOCKER_USER_HOME}/.bashrc && \
    echo "alias python=${ISAACLAB_PATH}/_isaac_sim/python.sh" >> ${DOCKER_USER_HOME}/.bashrc && \
    echo "alias python3=${ISAACLAB_PATH}/_isaac_sim/python.sh" >> ${DOCKER_USER_HOME}/.bashrc && \
    echo "alias pip='${ISAACLAB_PATH}/_isaac_sim/python.sh -m pip'" >> ${DOCKER_USER_HOME}/.bashrc && \
    echo "alias pip3='${ISAACLAB_PATH}/_isaac_sim/python.sh -m pip'" >> ${DOCKER_USER_HOME}/.bashrc && \
    echo "alias tensorboard='${ISAACLAB_PATH}/_isaac_sim/python.sh ${ISAACLAB_PATH}/_isaac_sim/tensorboard'" >> ${DOCKER_USER_HOME}/.bashrc && \
    echo "export TZ=$(date +%Z)" >> ${DOCKER_USER_HOME}/.bashrc && \
    echo "shopt -s histappend" >> ${DOCKER_USER_HOME}/.bashrc && \
    echo "PROMPT_COMMAND='history -a'" >> ${DOCKER_USER_HOME}/.bashrc

RUN mkdir -p ${ISAACSIM_PATH}/kit/cache && \
    mkdir -p ${DOCKER_USER_HOME}/.cache/ov && \
    mkdir -p ${DOCKER_USER_HOME}/.cache/pip && \
    mkdir -p ${DOCKER_USER_HOME}/.cache/nvidia/GLCache && \
    mkdir -p ${DOCKER_USER_HOME}/.nv/ComputeCache && \
    mkdir -p ${DOCKER_USER_HOME}/.nvidia-omniverse/logs && \
    mkdir -p ${DOCKER_USER_HOME}/.local/share/ov/data && \
    mkdir -p ${DOCKER_USER_HOME}/Documents

RUN touch /bin/nvidia-smi && \
    touch /bin/nvidia-debugdump && \
    touch /bin/nvidia-persistenced && \
    touch /bin/nvidia-cuda-mps-control && \
    touch /bin/nvidia-cuda-mps-server && \
    touch /etc/localtime && \
    mkdir -p /var/run/nvidia-persistenced && \
    touch /var/run/nvidia-persistenced/socket


VOLUME [ \
    "${ISAACSIM_PATH}/kit/cache", \
    "${DOCKER_USER_HOME}/.cache/ov", \
    "${DOCKER_USER_HOME}/.cache/pip", \
    "${DOCKER_USER_HOME}/.cache/nvidia/GLCache", \
    "${DOCKER_USER_HOME}/.nv/ComputeCache", \
    "${DOCKER_USER_HOME}/.nvidia-omniverse/logs", \
    "${DOCKER_USER_HOME}/.local/share/ov/data", \
    "${ISAACLAB_PATH}/docs/_build", \
    "${ISAACLAB_PATH}/logs", \
    "${ISAACLAB_PATH}/data_storage" \
]


RUN apt install just && \
    echo "alias j='just'" >> ${DOCKER_USER_HOME}/.bashrc


RUN ${ISAACLAB_PATH}/isaaclab.sh -p -m pip install manifold3d

RUN rm /workspace/isaaclab/_isaac_sim/kit/python/lib/python3.11/site-packages/rsl_rl_lib-3.1.2.dist-info/ -r && \
    rm /workspace/isaaclab/_isaac_sim/kit/python/lib/python3.11/site-packages/rsl_rl/ -r

COPY ./rsl_rl /workspace/rsl_rl
RUN cd /workspace/rsl_rl && \
    ${ISAACLAB_PATH}/isaaclab.sh -p -m pip install -e .

RUN add-apt-repository ppa:maveonair/helix-editor && \
    apt update && \
    apt install helix && \
    echo "alias vim='hx'" >> /root/.bashrc

ENTRYPOINT ["/bin/bash"]

