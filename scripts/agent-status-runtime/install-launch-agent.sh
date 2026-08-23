#!/usr/bin/env bash
set -euo pipefail

readonly LABEL="com.rafaelraba.agent-status-runtime"
readonly PLATFORM="${AGENT_STATUS_PLATFORM:-$(uname -s)}"

usage() {
  cat <<'EOF'
Usage: install-launch-agent.sh [auto|install|disable]

  auto     Install unless AGENT_STATUS_RUNTIME_ENABLED or
           AGENT_STATUS_RUNTIME_SERVICE_ENABLED is 0.
  install  Generate, load, and start the per-user macOS LaunchAgent.
  disable  Unload, disable, and remove the generated LaunchAgent.
EOF
}

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  printf '%s' "$value"
}

action="${1:-auto}"
case "$action" in
  auto|install|disable) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

if [[ "$PLATFORM" != Darwin ]]; then
  printf 'agent-status runtime service is only installed on macOS\n'
  exit 0
fi

DOTFILES_PATH="${DOTFILES_PATH:-$HOME/.dotfiles}"
config_script="$DOTFILES_PATH/scripts/agent-status/config.sh"
if [[ -r "$config_script" ]]; then
  # shellcheck source=/dev/null
  source "$config_script"
  agent_status_load_config
fi

service_enabled="${AGENT_STATUS_RUNTIME_SERVICE_ENABLED:-${AGENT_STATUS_RUNTIME_ENABLED:-1}}"
if [[ "$action" == auto ]]; then
  if [[ "$service_enabled" == 1 ]]; then
    action=install
  else
    action=disable
  fi
fi

launchctl_command="${AGENT_STATUS_LAUNCHCTL:-/bin/launchctl}"
service_uid="${AGENT_STATUS_RUNTIME_SERVICE_UID:-$(id -u)}"
domain="gui/$service_uid"
target="$domain/$LABEL"
launch_agents_dir="${AGENT_STATUS_LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
plist="$launch_agents_dir/$LABEL.plist"

if [[ "$action" == disable ]]; then
  "$launchctl_command" bootout "$target" >/dev/null 2>&1 || true
  "$launchctl_command" disable "$target" >/dev/null 2>&1 || true
  rm -f "$plist"
  printf 'agent-status runtime LaunchAgent disabled\n'
  exit 0
fi

runtime_binary="${AGENT_STATUS_RUNTIME_SERVICE_BINARY:-$DOTFILES_PATH/scripts/agent-status-runtime/bin/agent-status-runtime}"
state_root="${AGENT_STATUS_STATE_DIR:-${STATUS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/agent-status}}"
active_ttl="${AGENT_STATUS_ACTIVE_TTL:-300}"
terminal_ttl="${AGENT_STATUS_TERMINAL_TTL:-3600}"

[[ "$runtime_binary" = /* && -x "$runtime_binary" ]] || { printf 'runtime binary is unavailable: %s\n' "$runtime_binary" >&2; exit 1; }
[[ "$state_root" = /* && "$launch_agents_dir" = /* ]] || { printf 'runtime service paths must be absolute\n' >&2; exit 1; }
[[ "$active_ttl" =~ ^[0-9]+$ && "$terminal_ttl" =~ ^[0-9]+$ ]] || { printf 'runtime TTL values must be non-negative integers\n' >&2; exit 1; }

umask 077
mkdir -p "$state_root/panes" "$state_root/sessions" "$launch_agents_dir"
[[ -d "$state_root" && ! -L "$state_root" ]] || { printf 'runtime state root must be a real directory: %s\n' "$state_root" >&2; exit 1; }
chmod 700 "$state_root"

temporary="$(mktemp "$launch_agents_dir/.$LABEL.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
{
  cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
EOF
  printf '  <string>%s</string>\n' "$(xml_escape "$LABEL")"
  cat <<'EOF'
  <key>ProgramArguments</key>
  <array>
EOF
  printf '    <string>%s</string>\n' "$(xml_escape "$runtime_binary")"
  printf '    <string>serve</string>\n'
  printf '    <string>--root</string>\n'
  printf '    <string>%s</string>\n' "$(xml_escape "$state_root")"
  printf '    <string>--active-ttl</string>\n'
  printf '    <string>%s</string>\n' "$active_ttl"
  printf '    <string>--terminal-ttl</string>\n'
  printf '    <string>%s</string>\n' "$terminal_ttl"
  cat <<'EOF'
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
EOF
  printf '    <string>%s</string>\n' "$(xml_escape "$HOME")"
  if [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    printf '    <key>XDG_CACHE_HOME</key>\n'
    printf '    <string>%s</string>\n' "$(xml_escape "$XDG_CACHE_HOME")"
  fi
  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    printf '    <key>XDG_RUNTIME_DIR</key>\n'
    printf '    <string>%s</string>\n' "$(xml_escape "$XDG_RUNTIME_DIR")"
  fi
  cat <<EOF
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>ExitTimeOut</key>
  <integer>5</integer>
  <key>Umask</key>
  <string>077</string>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$state_root/runtime.log")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$state_root/runtime.err.log")</string>
</dict>
</plist>
EOF
} >"$temporary"
chmod 600 "$temporary"
if cmp -s "$temporary" "$plist"; then
  rm -f "$temporary"
else
  mv "$temporary" "$plist"
fi
trap - EXIT

"$launchctl_command" bootout "$target" >/dev/null 2>&1 || true
"$launchctl_command" enable "$target"
"$launchctl_command" bootstrap "$domain" "$plist"
printf 'agent-status runtime LaunchAgent installed: %s\n' "$plist"
