# shellcheck shell=bash
# Fetch one asset from a private GitHub release, using curl and the REST API.
#
# Deliberately NOT `gh`: self-hosted runners do not necessarily have it, and a
# QHexRT download failed with a bare "gh: command not found" on a box where the
# tool was never installed. curl ships with Windows, macOS and every Linux image
# we use, so this is one code path everywhere rather than a provisioning
# requirement per runner.
#
# Usage: fetch_release_asset <repo> <tag> <asset-name> <dest-dir> <token> <py>
# Prints nothing on success; writes "<dest-dir>/<asset-name>".

fetch_release_asset() {
    local repo="$1" tag="$2" name="$3" dest="$4" token="$5" py="$6"
    local api="https://api.github.com/repos/${repo}"

    # Every current caller (download-neurt.sh, download-qhexrt.sh,
    # download-qairt-runtime.sh, check_engine_prebuilt_pins.sh) requires a real
    # NEURUN_TOKEN and exits before reaching here without one -- NeuRT, QHexRT and
    # the QAIRT runtime are all private assets on the neurun repo. This guard just
    # avoids ever sending a literally empty Bearer header (GitHub rejects that
    # outright) if a future caller legitimately has none.
    local auth=()
    [[ -n "$token" ]] && auth=(-H "Authorization: Bearer ${token}")

    local meta; meta="$(mktemp)"
    if ! curl -sSL --fail-with-body \
            "${auth[@]}" \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -o "$meta" "${api}/releases/tags/${tag}"; then
        echo "[ERROR] could not read release ${tag} from ${repo}" >&2
        sed 's/^/        /' "$meta" >&2 || true
        rm -f "$meta"; return 1
    fi

    # Resolve the asset id by exact name. A prefix match would silently pick the
    # .sha256 sidecar, whose name starts with the tarball's.
    local asset_id
    asset_id="$("$py" - "$meta" "$name" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    rel = json.load(fh)
for a in rel.get("assets", []):
    if a.get("name") == sys.argv[2]:
        print(a["id"]); break
PY
)"
    rm -f "$meta"
    if [[ -z "$asset_id" ]]; then
        echo "[ERROR] release ${tag} in ${repo} has no asset named ${name}" >&2
        return 1
    fi

    mkdir -p "$dest"
    # octet-stream is what returns the bytes; the default Accept returns JSON.
    if ! curl -sSL --fail-with-body \
            "${auth[@]}" \
            -H "Accept: application/octet-stream" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            -o "${dest}/${name}" "${api}/releases/assets/${asset_id}"; then
        echo "[ERROR] could not download ${name} from ${repo}@${tag}" >&2
        rm -f "${dest}/${name}"; return 1
    fi
}
