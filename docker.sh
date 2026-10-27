#!/bin/bash

set -e

BUILD=0
DETACH=0
PERSIST=0
IMAGE="cache_design:latest"
NAME=cache_design

while [[ $# -gt 0 ]]; do
    case $1 in
        --build)
            BUILD=1
            shift
            ;;
        --persist)
            PERSIST=1
            shift
            ;;
        --detach|-d)
            DETACH=1
            if [[ -n "${2:-}" ]]; then
                NAME=$2
                shift 2
            else
                shift
            fi
            ;;
        *)
            if [[ $1 == -* ]]; then
                echo "Unknown parameter: $1"
                exit 1
            else
                NAME=$1
                shift
            fi
            ;;
    esac
done

cd "$(dirname "$0")"

image_exists() {

    docker images --format "{{.Repository}}:{{.Tag}}" |
        awk -v image="$IMAGE" '$0 == image {found=1} END {print found+0}'
}

RUN_CMD=(docker run -it --network host --privileged --name $NAME)

user="${SUDO_USER:-$(id -un)}"
home="$(getent passwd "$user" | cut -d: -f6)"

if [ -n "${DISPLAY:-}" ]; then
    xauth="${XAUTHORITY:-$home/.Xauthority}"

    RUN_CMD+=(
        --uts host
        -v /tmp/.X11-unix:/tmp/.X11-unix
        -e "DISPLAY=$DISPLAY"
    )

    if [ -f "$xauth" ]; then
        RUN_CMD+=(
            -v "$xauth:/tmp/.Xauthority:ro"
            -e XAUTHORITY=/tmp/.Xauthority
        )
    fi
fi

uid="${SUDO_USER:-$(id -u)}"
un="${SUDO_USER:-$(id -un)}"

if [[ $(image_exists) -eq 0 ]] || [[ $BUILD -eq 1 ]]; then
    read -s -p "Enter a password : " password
    echo
    read -s -p "Confirm : " password_confirm
    echo

    if [ "$password" != "$password_confirm" ]; then
        echo "Wrong password"
        exit 1
    fi
    docker build --build-arg SUDO_PASS="$password" --build-arg USER="$un" --build-arg ID="$uid" -t $IMAGE .
fi

if [ $PERSIST -eq 0 ]; then
    RUN_CMD+=(--rm)
fi

if [ $DETACH -eq 1 ]; then
    RUN_CMD+=(-d)
fi

RUN_CMD+=(-v "$PWD:/phinaow" -w /phinaow)

RUN_CMD+=("$@" "$IMAGE")

# Execute docker run
"${RUN_CMD[@]}"
