# Tasks: Tmux Herdr Workspace

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | ~1100-1200 authored |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 protocol/config -> PR 2 tab/order -> PR 3 sound -> PR 4 adapters -> PR 5 restore/docs |
| Delivery strategy | ask-always, resolved to chained delivery |
| Chain strategy | stacked-to-main |

Decision needed before apply: No, resolved by user.
Chained PRs recommended: Yes.
Chain strategy: stacked-to-main.
400-line budget risk: High.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | Core protocol and config | PR 1 | `AGENT_STATUS_DEBUG=1 ./test/scripts/agent-status-protocol.sh` | Temp HOME + `tmux new-session -d -s test` | `scripts/agent-status.sh`, `scripts/agent-status/*`, `editors/tmux/agent-status.conf` |
| 2 | Tmux tab UX and order | PR 2 | `./test/scripts/agent-status-protocol.sh` order fixtures | `tmux` sessions named by config | `scripts/agent-status/order.sh`, `scripts/status-sessions.sh`, `scripts/session-picker.sh` |
| 3 | Sound notifications | PR 3 | `./test/scripts/agent-status-protocol.sh` sound fixtures | Fake `afplay`/`paplay` in PATH | `scripts/agent-status/notify.sh`, sound ledger |
| 4 | Adapters and wiring | PR 4 | `./test/scripts/agent-status-adapters.sh` | Simulated agent hooks in temp HOME | `scripts/claude-agent-status.sh`, `editors/opencode/plugins/tmux-agent-status.ts`, `editors/pi/agent/extensions/tmux-agent-status.ts`, `editors/codex/*`, settings files |
| 5 | Restoration and docs | PR 5 | `./restoration_scripts/01-verify-install.sh --dry-run` | Clean dotfiles restore in temp HOME | `restoration_scripts/01-verify-install.sh`, `symlinks/*.yaml`, docs |

## Phase 1: Foundation

- [x] 1.1 Create `editors/tmux/agent-status.conf` v1 schema with TTLs, order, palette, and sound defaults.
- [x] 1.2 Create `scripts/agent-status/config.sh` to load the versioned config and export validated paths/limits.
- [x] 1.3 Modify `scripts/agent-status.sh` to dispatch `set/get/clear/inspect/doctor` and parse legacy one-line state files.
- [x] 1.4 RED test: missing config/state dir falls back to safe defaults without failing.

## Phase 2: Core Protocol

- [x] 2.1 Create `scripts/agent-status/store.sh` with canonical validation, monotonic transitions, atomic writes, and TTL pruning.
- [x] 2.2 RED test: unsupported agent state normalizes to `blocked`.
- [x] 2.3 RED test: stale `running` record recovers to `idle` or `blocked`.
- [x] 2.4 RED test: terminal `done` clears active attention.
- [x] 2.5 Integration test: concurrent `set` calls preserve the last accepted event.

## Phase 3: Tmux Presentation

- [x] 3.1 Create `scripts/agent-status/order.sh` with configured session order and lexical fallback.
- [x] 3.2 RED test: identical config yields deterministic tab order across restarts.
- [x] 3.3 Modify `scripts/status-sessions.sh` to consume aggregate and render urgency, counts, and no-color labels.
- [x] 3.4 Modify `scripts/session-picker.sh` to consume the same aggregate and preserve deterministic order.
- [x] 3.5 Add distinguishable symbols and preserve contrast for color-disabled terminals.

## Phase 4: Adapters and Wiring

- [ ] 4.1 RED test: adapter path with spaces passes argv intact.
- [ ] 4.2 RED test: missing/non-executable adapter exits silently and does not break the agent.
- [ ] 4.3 RED test: hostile state/source payload is rejected without command execution.
- [ ] 4.4 Modify `scripts/claude-agent-status.sh` to emit canonical events with source/event IDs.
- [ ] 4.5 Modify `editors/opencode/plugins/tmux-agent-status.ts` to emit canonical events.
- [ ] 4.6 Modify `editors/pi/agent/extensions/tmux-agent-status.ts` to emit canonical events.
- [ ] 4.7 Create `editors/codex/agent-status.sh` and `editors/codex/hooks.json` for Codex events.
- [ ] 4.8 Create `editors/opencode/tui.json` and `editors/pi/agent/settings.json`; modify `editors/claude/settings.json` to register adapters.
- [ ] 4.9 Modify `symlinks/conf.yaml` and `symlinks/conf.macos.yaml` to move portable links and add adapter registrations.

## Phase 5: Notifications and Recovery

- [ ] 5.1 Create `scripts/agent-status/notify.sh` with dedup ledger, backend allowlist (`afplay`/`paplay`), and cooldown.
- [ ] 5.2 RED test: repeated attention transitions within cooldown produce only one sound.
- [ ] 5.3 RED test: missing sound command keeps visual status and logs a diagnostic.
- [ ] 5.4 Modify `restoration_scripts/01-verify-install.sh` to verify links, config, permissions, and `doctor` output.

## Phase 6: Final Integration and Verification

- [ ] 6.1 Run `./scripts/agent-status.sh doctor` in a temp HOME and verify all components.
- [ ] 6.2 Run `./test/scripts/agent-status-{protocol,adapters}.sh` with fake tmux and sound executables.
- [ ] 6.3 Update migration and rollback documentation.
- [ ] 6.4 Remove temporary legacy compatibility parsing after the release window.
