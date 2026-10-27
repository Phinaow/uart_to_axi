FROM debian:13 AS base

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    autotools-dev \
    bc \
    bison \
    build-essential \
    ccache \
    clang \
    cmake \
    curl \
    device-tree-compiler \
    flex \
    gawk \
    gcc gcc-multilib \
    git \
    git-lfs \
    gperf \
    help2man \
    libboost-regex-dev \
    libboost-system-dev \
    libc6 libc6:i386 \
    libexpat-dev \
    libfl-dev \
    libfl2 \
    libfreetype6 \
    libftdi1-dev \
    libglib2.0-dev \
    libgmp-dev \
    libgoogle-perftools-dev \
    libjim-dev \
    libmpc-dev \
    libmpfr-dev \
    libtool \
    libusb-1.0-0-dev \
    libxcursor1 \
    libxext6 libxext6:i386 \
    libxfixes3 \
    libxft2 libxft2:i386 \
    libxi6 \
    libxinerama1 \
    libxrandr2 \
    libxrender1 \
    libxtst6 \
    lld \
    locales \
    ninja-build \
    numactl \
    openfpgaloader \
    patchutils \
    perl \
    perl-doc \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    texinfo \
    unzip \
    usbutils \
    wget \
    xxd \
    zlib1g-dev \
    sudo \
    && \
    rm -rf /var/lib/apt/lists/*

# Verilator Build =============================================================

FROM base AS verilator-build

ARG JOBS="1"

RUN git clone https://github.com/verilator/verilator.git && \
    cd verilator && \
    autoconf && \
    ./configure --prefix=/usr/local && \
    make -j && \
    make install && \
    cd .. && \
    rm -rf verilator

# Verible Build ===============================================================

FROM base AS verible-build

RUN curl -L https://github.com/bazelbuild/bazelisk/releases/download/v1.19.0/bazelisk-linux-amd64 \
    -o /usr/local/bin/bazel \
    && chmod +x /usr/local/bin/bazel

RUN git clone https://github.com/chipsalliance/verible.git && \
    cd verible && \
    bazel build -c opt //... && \
    bazel build -c opt :install-binaries && \
    .github/bin/simple-install.sh /usr/local/bin && \
    cd .. && \
    rm -rf verible


FROM base AS final

COPY --from=verilator-build /usr/local /usr/local
COPY --from=verible-build /usr/local /usr/local

RUN apt-get update && apt-get install -y \
    ffmpeg \
    libpython3-dev

# Cocotb embeds Python in the simulator: libpython3-dev supplies libpython.so.
# Keep the environment inside the image, independent of host-mounted venvs.
COPY requirements.txt /tmp/cache-requirements.txt
RUN python3 -m venv /opt/cache-venv && \
    /opt/cache-venv/bin/python -m pip install --no-cache-dir -r /tmp/cache-requirements.txt
ENV PATH="/opt/cache-venv/bin:${PATH}"

RUN apt-get update -qq && apt-get install -y libpython3.13

WORKDIR /phinaow

COPY .bashrc /etc/bash.bashrc
RUN chmod 644 /etc/bash.bashrc

ARG SUDO_PASS
ARG ID
ARG USER

RUN useradd -u ${ID} -ms /bin/bash "$USER" && echo "${USER}:${SUDO_PASS}" | chpasswd && adduser ${USER} sudo
USER ${USER}
