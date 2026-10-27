#!/usr/bin/env bash
# Run the local UART tests in the existing container, without rebuilding it.
set -euo pipefail
container_name=${UART_CONTAINER_NAME:-cache_design}
container_root=${UART_CONTAINER_ROOT:-/phinaow}
if [[ $# -eq 0 ]]; then
    set -- -q tests
fi
docker exec --user "$(id -u):$(id -g)" -w "$container_root" "$container_name" bash -c '
    ulimit -c 0
    if [[ ! -f pytest.ini || ! -d src || ! -d tests ]]; then
        echo "UART project not found in $PWD; check UART_CONTAINER_ROOT and the container mount" >&2
        exit 1
    fi
    python_path=
    for candidate in /opt/cache-venv/bin/python "$PWD/.venv/bin/python" /tmp/cache-cocotb-venv/bin/python; do
        if [[ -x "$candidate" ]]; then
            python_path=$candidate
            break
        fi
    done
    if [[ -z "$python_path" ]]; then
        echo "Missing container Python environment (.venv, /opt/cache-venv or /tmp/cache-cocotb-venv); see README.md" >&2
        exit 1
    fi
    if ! "$python_path" -c "import cocotb, pytest, find_libpython"; then
        echo "Test dependencies unavailable in $python_path; install requirements.txt with the container Python" >&2
        exit 1
    fi
    export PYTHONPATH="$PWD/tests:$PWD"
    LIBPYTHON_LOC=$("$python_path" -m find_libpython)
    export LIBPYTHON_LOC
    if [[ ! -f "$LIBPYTHON_LOC" ]]; then
        echo "Missing shared libpython; see README.md" >&2
        exit 1
    fi
    exec "$python_path" -m pytest -c "$PWD/pytest.ini" "$@"
' uart-tests "$@"
