#!/usr/bin/env bash
# RunAnywhere v2 C++ core — Linux Docker end-to-end harness.
#
# Usage:
#   scripts/docker-e2e.sh            # build + run ctest
#   scripts/docker-e2e.sh build      # just build the image
#   scripts/docker-e2e.sh test       # run ctest inside the image
#   scripts/docker-e2e.sh server     # run the OpenAI server (needs RA_MODEL)
#   scripts/docker-e2e.sh shell      # drop into an interactive shell
set -euo pipefail

readonly IMAGE="${RA_DOCKER_IMAGE:-ra-core-linux}"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MODELS_DIR="${RA_MODELS_DIR:-$HOME/.ra-models}"

log() { printf '[docker-e2e] %s\n' "$*" >&2; }

cmd_build() {
    log "building $IMAGE from infra/docker/Dockerfile.cpp-linux …"
    docker build \
        -f "$REPO_ROOT/infra/docker/Dockerfile.cpp-linux" \
        -t "$IMAGE" \
        "$REPO_ROOT"
}

cmd_test() {
    log "running ctest inside $IMAGE …"
    docker run --rm "$IMAGE"
}

cmd_server() {
    mkdir -p "$MODELS_DIR"
    log "serving runanywhere-server on :8080 (models: $MODELS_DIR)"
    docker run --rm \
        -p 8080:8080 \
        -e "RA_TEST_GGUF=${RA_TEST_GGUF:-}" \
        -v "$MODELS_DIR:/models" \
        "$IMAGE" runanywhere-server
}

cmd_shell() {
    docker run --rm -it --entrypoint bash "$IMAGE"
}

main() {
    local action="${1:-all}"
    case "$action" in
        build)  cmd_build ;;
        test)   cmd_test ;;
        server) cmd_server ;;
        shell)  cmd_shell ;;
        all|"") cmd_build && cmd_test ;;
        *)
            printf 'unknown action: %s\n' "$action" >&2
            printf 'usage: %s [build|test|server|shell]\n' "$0" >&2
            exit 2
            ;;
    esac
}

main "$@"
