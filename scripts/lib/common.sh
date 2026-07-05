# Shared helpers for every script in scripts/. Source it, don't execute it:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# Provides: RAC_ROOT, log/info/ok/warn/error/die/step, run_cmd, require_cmd.

[[ -n "${_RAC_COMMON_SH:-}" ]] && return 0
_RAC_COMMON_SH=1

RAC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export RAC_ROOT

if [[ -t 2 && "${NO_COLOR:-}" != "1" ]]; then
    _c_reset=$'\033[0m'
    _c_bold=$'\033[1m'
    _c_dim=$'\033[2m'
    _c_red=$'\033[31m'
    _c_green=$'\033[32m'
    _c_yellow=$'\033[33m'
    _c_blue=$'\033[34m'
else
    _c_reset='' _c_bold='' _c_dim='' _c_red='' _c_green='' _c_yellow='' _c_blue=''
fi

log()   { printf '%s\n' "$*" >&2; }
info()  { printf '%s\n' "${_c_blue}::${_c_reset} $*" >&2; }
ok()    { printf '%s\n' "${_c_green}ok${_c_reset} $*" >&2; }
warn()  { printf '%s\n' "${_c_yellow}warning:${_c_reset} $*" >&2; }
error() { printf '%s\n' "${_c_red}error:${_c_reset} $*" >&2; }
die()   { error "$*"; exit 1; }

# Section header for multi-stage scripts.
step()  { printf '\n%s\n' "${_c_bold}==> $*${_c_reset}" >&2; }

# Echo a command before running it.
run_cmd() {
    printf '%s\n' "${_c_dim}+ $*${_c_reset}" >&2
    "$@"
}

require_cmd() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "required command not found: $c"
    done
}
