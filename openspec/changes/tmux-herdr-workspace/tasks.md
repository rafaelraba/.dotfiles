# Tasks: Tmux Herdr Workspace

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~360 authored (~70 PR #6, ~290 next PR) |
| 400-line budget risk | Medium |
| Chained PRs recommended | Yes |
| Suggested split | PR #6 sound correction → next stacked-to-main presentation PR |
| Delivery strategy | auto-chain |
| Chain strategy | stacked-to-main |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Est. lines | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|------------|----------------------|-----------------|-------------------|
| 1 | Sound default and doctor correction | PR #6 | ~70 | `./test/scripts/agent-status-protocol.sh` | Fake `afplay` in PATH; Linux tests doctor only | `scripts/agent-status/config.sh`, `scripts/agent-status/notify.sh`, `editors/tmux/agent-status.conf`, `agent-status.sh` doctor branch |
| 2 | One-pass render, minimal tabs, hierarchical picker | Next stacked-to-main | ~290 | `./test/scripts/agent-status-protocol.sh` | Isolated tmux server with ≥14 panes | `scripts/agent-status.sh`, `scripts/agent-status/store.sh`, `scripts/status-sessions.sh`, `scripts/session-picker*.sh` |

Preserve unrelated local changes: `editors/claude/settings.json`, `editors/herdr/config.toml`, `.atl/`.

## Phase 1: PR #6 Sound Correction

- [x] 1.1 RED test: enabled macOS sound with empty `AGENT_STATUS_SOUND_FILE` plays `/System/Library/Sounds/Glass.aiff`.
- [x] 1.2 Modify `scripts/agent-status/config.sh` to default `AGENT_STATUS_SOUND_FILE` on macOS when enabled and empty.
- [x] 1.3 Modify `scripts/agent-status/notify.sh` to expose `sound_status` (`disabled|ready|unsupported_backend|backend_missing|file_missing`) without affecting lifecycle state.
- [x] 1.4 Modify `scripts/agent-status.sh` `doctor` branch to report `sound_enabled`, backend, file, and `sound_status`.
- [x] 1.5 GREEN test: doctor reports each `sound_status` accurately.

## Phase 2: Bulk Pane Snapshot Foundation

- [x] 2.1 RED test: two-session render issues exactly one `tmux list-panes -a` call and zero per-session `list-panes` calls.
- [x] 2.2 Add `store_bulk_snapshot` API in `scripts/agent-status/store.sh` returning tab-delimited `session\twindow_index\twindow_name\tpane_id\tcommand\ttitle\tpath` rows.
- [x] 2.3 Refactor `scripts/agent-status.sh` `aggregate_session_state` and `aggregate_session_count` to consume the bulk snapshot.
- [x] 2.4 RED test: cold render ≤500 ms and warm render ≤250 ms over 10 runs.

## Phase 3: Minimal Accessible Tabs

- [x] 3.1 RED test: tab output contains only session name and marker; no counts or state words.
- [x] 3.2 Modify `scripts/status-sessions.sh` to render name + marker/color tabs and preserve `NO_COLOR` markers.
- [x] 3.3 GREEN test: `NO_COLOR=1` tabs distinguish states via `agent_status_state_symbol`.

## Phase 4: Hierarchical Picker

- [x] 4.1 RED test: picker popup opens at 90% width × 80% height.
- [x] 4.2 Modify `scripts/session-picker-wrapper.sh` to capture one bulk pane snapshot and launch the percentage popup.
- [x] 4.3 Modify `scripts/session-picker.sh` to render indented session → window → pane rows with process and lifecycle detail.
- [x] 4.4 GREEN test: >13 rows are searchable by command without truncation.

## Phase 5: Verification

- [x] 5.1 Update `test/scripts/agent-status-protocol.sh` with snapshot IPC count, timing, tab, hierarchy, and doctor tests.
- [x] 5.2 Run `./test/scripts/agent-status-protocol.sh` and confirm all scenarios pass.
