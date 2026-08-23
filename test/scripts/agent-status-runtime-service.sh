#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$ROOT/scripts/agent-status-runtime/install-launch-agent.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

home="$TMP/home & portable"
cache="$TMP/cache & portable"
runtime="$TMP/runtime & stable"
launch_agents="$home/Library/LaunchAgents"
launchctl_log="$TMP/launchctl.log"
mkdir -p "$home" "$cache" "$(dirname "$runtime")" "$TMP/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$runtime"
chmod +x "$runtime"
cat >"$TMP/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AGENT_STATUS_LAUNCHCTL_LOG"
[[ "$1" != bootout ]]
EOF
chmod +x "$TMP/bin/launchctl"

install_service() {
  HOME="$home" XDG_CACHE_HOME="$cache" DOTFILES_PATH="$ROOT" AGENT_STATUS_RUNTIME_ENABLED=1 \
    AGENT_STATUS_PLATFORM=Darwin AGENT_STATUS_RUNTIME_SERVICE_BINARY="$runtime" \
    AGENT_STATUS_LAUNCH_AGENTS_DIR="$launch_agents" AGENT_STATUS_LAUNCHCTL="$TMP/bin/launchctl" \
    AGENT_STATUS_LAUNCHCTL_LOG="$launchctl_log" bash "$INSTALLER" "$1" >/dev/null
}

install_service install
plist="$launch_agents/com.rafaelraba.agent-status-runtime.plist"
first_hash="$(shasum -a 256 "$plist")"
install_service install
[[ "$first_hash" == "$(shasum -a 256 "$plist")" ]] || { printf 'FAIL: repeated install changed generated plist\n' >&2; exit 1; }

python3 - "$plist" "$runtime" "$cache/agent-status" "$home" "$cache" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    service = plistlib.load(source)

expected_arguments = [
    sys.argv[2],
    "serve",
    "--root",
    sys.argv[3],
    "--active-ttl",
    "300",
    "--terminal-ttl",
    "3600",
]
assert service["Label"] == "com.rafaelraba.agent-status-runtime"
assert service["ProgramArguments"] == expected_arguments
assert "--now" not in service["ProgramArguments"]
assert service["RunAtLoad"] is True
assert service["KeepAlive"] is True
assert service["ThrottleInterval"] == 10
assert service["EnvironmentVariables"] == {"HOME": sys.argv[4], "XDG_CACHE_HOME": sys.argv[5]}
PY

[[ "$(grep -c '^bootstrap ' "$launchctl_log")" == 2 ]] || { printf 'FAIL: repeated install did not bootstrap exactly once per run\n' >&2; exit 1; }
[[ "$(grep -c '^enable ' "$launchctl_log")" == 2 ]] || { printf 'FAIL: repeated install did not enable exactly once per run\n' >&2; exit 1; }

HOME="$home" XDG_CACHE_HOME="$cache" DOTFILES_PATH="$ROOT" AGENT_STATUS_RUNTIME_ENABLED=1 \
  AGENT_STATUS_RUNTIME_SERVICE_ENABLED=0 AGENT_STATUS_PLATFORM=Darwin \
  AGENT_STATUS_LAUNCH_AGENTS_DIR="$launch_agents" AGENT_STATUS_LAUNCHCTL="$TMP/bin/launchctl" \
  AGENT_STATUS_LAUNCHCTL_LOG="$launchctl_log" bash "$INSTALLER" auto >/dev/null
[[ ! -e "$plist" ]] || { printf 'FAIL: service opt-out retained generated plist\n' >&2; exit 1; }
grep -q '^disable gui/' "$launchctl_log" || { printf 'FAIL: service opt-out did not persist launchctl disable state\n' >&2; exit 1; }

printf 'agent-status runtime service checks passed\n'
