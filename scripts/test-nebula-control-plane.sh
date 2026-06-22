#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$repo_root/nebula-core-module/bin/nebula-core"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export NEBULA_DATA_DIR="$tmp/data"
export NEBULA_MODULE_DIR="$repo_root/nebula-core-module"
export NEBULA_MODULE_PROP="$repo_root/nebula-core-module/module.prop"
export NEBULA_GIT_COMMIT="host-test"

json_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
print(obj.get(sys.argv[2], ""))
PY
}

status="$(sh "$cli" status --json)"
[[ "$(json_field "$status" protocol_version)" == "1" ]]
[[ "$(json_field "$status" profile)" == "safe" ]]

safe="$(sh "$cli" safe-mode get --json)"
[[ "$(json_field "$safe" safe_mode)" == "False" ]]

sh "$cli" safe-mode enable >/dev/null
safe="$(sh "$cli" safe-mode get --json)"
[[ "$(json_field "$safe" safe_mode)" == "True" ]]
[[ -f "$NEBULA_DATA_DIR/safe_mode" ]]

sh "$cli" profile set phone >/dev/null
profile="$(sh "$cli" profile get --json)"
[[ "$(json_field "$profile" profile)" == "phone" ]]
[[ "$(json_field "$profile" safe_mode)" == "False" ]]

set +e
dock_out="$(sh "$cli" profile set dock 2>/dev/null)"
dock_code=$?
compat_out="$(sh "$cli" profile set compatibility 2>/dev/null)"
compat_code=$?
set -e
[[ "$dock_code" -ne 0 ]]
[[ "$compat_code" -ne 0 ]]
[[ "$(json_field "$dock_out" error)" == "BLOCKED_NOT_READY" ]]
[[ "$(json_field "$compat_out" error)" == "BLOCKED_NOT_READY" ]]

caps="$(sh "$cli" capabilities --json)"
python3 - "$caps" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
ids = {item["id"] for item in obj["capabilities"]}
required = {"profile.safe", "profile.phone", "profile.dock", "profile.compatibility", "safe-mode", "logs.tail"}
missing = sorted(required - ids)
if missing:
    raise SystemExit(f"missing capabilities: {missing}")
PY

logs="$(sh "$cli" logs tail --lines 10)"
python3 - "$logs" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
if not isinstance(obj.get("lines"), list):
    raise SystemExit("logs.lines is not a list")
PY

if rg -n 'WayLandIE|Wayland|Gamescope|Xwayland|DRM|compositor|linux|am start|monkey' "$repo_root/nebula-core-module/service.sh"; then
  echo "service.sh contains forbidden backend launch strings" >&2
  exit 1
fi

rg -n 'NEBULA_CORE_PROTOCOL_VERSION = 1|NEBULA_CORE_PROTOCOL_VERSION=1' "$repo_root/app/src/main/java/io/droidspaces/nebula/core/NebulaCoreProtocol.java" >/dev/null
rg -n 'protocolMismatch|moduleVersionMismatch|Invalid module JSON' "$repo_root/app/src/main/java/io/droidspaces/nebula/core" >/dev/null

echo "Nebula control plane host tests passed."
