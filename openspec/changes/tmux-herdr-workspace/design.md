# Design: Tmux Herdr Workspace

## Technical Approach

Retain `agent-status.sh` as the stable, agent-neutral CLI and split its internals into small Bash modules for configuration, storage/aggregation, ordering, and notification policy. Claude, OpenCode, Pi, and Codex remain thin translators. Both tmux renderers consume the same aggregate and ordering APIs; no renderer knows vendor events.

## Architecture Decisions

| Option | Tradeoff | Decision |
|---|---|---|
| Versioned TSV state files vs JSON/database | TSV is shell-portable but intentionally schema-limited | Store `version, state, updated_epoch, source, event_id`; accept legacy one-line files during migration |
| Atomic rename only vs `flock` | `flock` is not standard on macOS | Use same-directory temp files plus `mv`; protect state/notification read-modify-write with bounded `mkdir` locks and stale-lock recovery |
| Shared config vs per-renderer constants | Sourced Bash config is trusted local code | Put state priority, TTLs, order, appearance, and notification settings in one versioned config; never `eval` data |
| Event-driven vs render-driven sound | Event-driven requires deduplication but avoids repeated tmux refresh sounds | Notify only after accepted transitions; default off, backend allowlist (`afplay`/`paplay`), configurable attention states and cooldown |
| Full framework vs shell modules | A framework would exceed dotfiles needs | Use four sourceable modules behind one CLI and dependency-free shell tests |

## Data Flow

```text
vendor event -> adapter -> agent-status.sh set/clear
                           |-> store.sh -> atomic state file
                           `-> notify.sh -> dedup ledger -> sound
tmux -> order.sh -> store.sh aggregate -> status-sessions.sh/session-picker.sh
```

`error > permission > waiting_for_input > blocked > done > running > idle`. Configured session names come first; unmatched sessions sort lexically. Missing, malformed, or expired records resolve to `idle`. Active-state TTLs are short and terminal-state TTLs are longer, both configurable; reads may prune expired records. Pane records for missing panes are removed.

## File Changes

| File | Action | Description |
|---|---|---|
| `scripts/agent-status.sh` | Modify | Stable `set/get/clear/inspect/doctor` CLI and compatibility parsing |
| `scripts/agent-status/{config,store,order,notify}.sh` | Create | Configuration loading, transitions/aggregation, deterministic ordering, sound policy |
| `scripts/{status-sessions,session-picker}.sh` | Modify | Shared order/aggregate consumption and distinct state rendering |
| `scripts/claude-agent-status.sh`, `editors/opencode/plugins/tmux-agent-status.ts`, `editors/pi/agent/extensions/tmux-agent-status.ts` | Modify | Canonical event translation with source/event IDs and best-effort failures |
| `editors/codex/{agent-status.sh,hooks.json}` | Create | Codex translator and registration |
| `editors/tmux/agent-status.conf` | Create | Versioned schema v1, TTL, order, palette, sound settings |
| `editors/{opencode/tui.json,pi/agent/settings.json}` | Create | Explicit adapter registration |
| `editors/claude/settings.json` | Modify | Remove obsolete Herdr wiring; preserve unrelated hooks |
| `symlinks/conf.yaml`, `symlinks/conf.macos.yaml` | Modify | Move portable agent links to common config and add registrations |
| `restoration_scripts/01-verify-install.sh` | Modify | Verify links, registration, executable permissions, config, and `doctor` |
| `test/scripts/agent-status-{protocol,adapters}.sh` | Create | Dependency-free contract/integration tests with fake tmux and sound executables |

## Interfaces / Contracts

`agent-status.sh set STATE [SESSION] [PANE] [SOURCE] [EVENT_ID]`; existing calls remain valid. Adapters may emit only canonical states and MUST degrade an unsupported permission/input distinction to `blocked`. `inspect` emits stable TSV diagnostics including stored/effective state, age, and stale reason. Debug logs are opt-in through `AGENT_STATUS_DEBUG=1`; adapter failures never interrupt agents.

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Unit | validation, legacy parsing, priority, TTL, order, dedup | Temp HOME/cache, fake clock/tmux/sound |
| Integration | concurrent writers, stale locks/panes, renderer output, all adapter mappings | Parallel shell processes and fixture payloads |
| Restore | clean links/config and rollback compatibility | Run verifier against a temporary HOME |

## Threat Matrix

| Boundary | Applicability | Safe/failure behavior | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A: no executable classification | N/A | N/A |
| Git repository selection | N/A: no VCS operation | N/A | N/A |
| Commit state | N/A: no VCS operation | N/A | N/A |
| Push state | N/A: no VCS operation | N/A | N/A |
| PR commands | N/A: no PR automation | N/A | N/A |
| Adapter subprocess | Applicable | Fixed executable path, validated argv, no shell composition, one-second timeout; missing/hung CLI is ignored with optional debug output | Path containing spaces is passed intact; missing/non-executable and timeout do not break agent; hostile state/source is rejected without command execution |

## Migration / Rollout

1. Install protocol/config and compatibility reader; keep legacy rendering.
2. Enable shared rendering/order, then adapters independently: Claude, OpenCode, Pi, Codex.
3. Enable TTL cleanup; sounds remain off until explicit opt-in.
4. Back up unmanaged runtime configs before symlinking, run `doctor` and restore verification, then remove compatibility parsing after one release window.

Rollback disables registrations and sound, restores backed-up configs/legacy renderer links, and keeps v1 files readable by the compatibility CLI. macOS and Linux use Bash, tmux, `mktemp`, `mkdir`, and `mv`; sound is optional per platform.

## Open Questions

None.
