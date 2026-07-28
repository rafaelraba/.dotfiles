# Design: Tmux Herdr Workspace Correction

## Technical Approach

Replace per-session status queries with one tmux pane snapshot per render, then join lifecycle records in-process. Tabs become name plus state marker/color; the picker reuses the hierarchy for searchable session, window, and pane rows. Default-off, allowlisted sound gains a macOS default and actionable `doctor` output. The correction stays below 400 authored changed lines and preserves protocol, ordering, TTL, and visual fallbacks.

## Architecture Decisions

| Option | Tradeoff | Decision |
|---|---|---|
| Per-session CLI calls vs one bulk snapshot | A join step bounds tmux IPC | Run exactly one `tmux list-panes -a`; aggregate all visible sessions from it |
| Cross-render cache vs render-local snapshot | Caching saves IPC but risks stale pane/state UI and invalidation complexity | No persistent cache; one render-local snapshot is authoritative and discarded after status render or picker close |
| Rich tabs vs progressive detail | Detail moves one keypress away | Tabs show marker and name; words/counts live in picker and `inspect`; no-color keeps markers |
| Fixed picker vs percentage popup | Percentage sizing is less content-tight but scales predictably | Use a 90% wide, 80% high popup with fzf search, scrolling, hierarchy, and footer keys |
| Custom sound command vs backend policy | Arbitrary commands are flexible but unsafe | Keep `afplay`/`paplay` allowlisting; on macOS, enabled sound with no file resolves to `/System/Library/Sounds/Glass.aiff` |
| Amend PR #6 vs follow-up | Mixing picker work into sound PR harms review focus | Correct macOS default and doctor diagnostics in PR #6; deliver snapshot/tabs/picker in the next stacked-to-main PR |

## Data Flow

```text
tmux list-panes -a (once) -> snapshot rows -> lifecycle join/urgency
                                |-> minimal status tabs
                                `-> hierarchy file -> 90%x80% fzf picker -> select target
adapter event -> atomic state -> visual state -> best-effort allowlisted sound
```

Snapshot rows carry session, window index/name, pane id, command, title, and path. Lifecycle records are read once per pane; malformed, missing, expired, or vanished panes resolve safely. Hidden stable target/search fields back visible indented rows; session/window rows provide context and pane rows expose process and lifecycle detail.

## File Changes and Review Boundaries

| File | Action | Description / forecast |
|---|---|---|
| `scripts/agent-status.sh`, `scripts/agent-status/store.sh` | Modify | Bulk snapshot aggregation API; no per-session `list-panes` (~55 lines) |
| `scripts/status-sessions.sh` | Modify | Minimal marker/color tabs and no-color marker (~45 lines) |
| `scripts/session-picker-wrapper.sh`, `scripts/session-picker.sh` | Modify | One hierarchical capture, percentage popup, search/footer/targets (~125 lines) |
| `scripts/agent-status/{config,notify}.sh`, `editors/tmux/agent-status.conf` | Modify | Safe macOS default resolution and diagnostics (~45 lines; PR #6) |
| `test/scripts/agent-status-protocol.sh` | Modify | IPC count, timing, tab, hierarchy, and sound doctor tests (~90 lines) |

Forecast: **~360 authored additions plus deletions**, no generated files. Preserve unrelated `editors/claude/settings.json`, `editors/herdr/config.toml`, and `.atl/` changes.

## Interfaces / Contracts

The internal bulk row is tab-delimited: `session, window_index, window_name, pane_id, command, title, path`. Fields are data, never evaluated. `doctor` reports `sound_enabled`, resolved backend/file, and `sound_status` (`disabled|ready|unsupported_backend|backend_missing|file_missing`). Sound failures never change lifecycle state.

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Unit | urgency, minimal/no-color tabs, hierarchy and targets, doctor states | Fake tmux/state/sound fixtures |
| Integration | exactly one bulk pane call; >13 searchable rows; command search | Invocation log plus real/fake fzf input |
| Performance | two-session cold/warm render and queued key responsiveness | Isolated tmux server; `/usr/bin/time` over 10 runs, first cold then nine warm; assert cold ≤500 ms, each warm ≤250 ms and one `list-panes` |

## Threat Matrix

| Boundary | Applicability | Safe/failure behavior | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | N/A: no executable classification | N/A | N/A |
| Git repository selection | N/A: no VCS operation | N/A | N/A |
| Commit state | N/A: no VCS operation | N/A | N/A |
| Push state | N/A: no VCS operation | N/A | N/A |
| PR commands | N/A: no PR automation | N/A | N/A |
| Tmux/sound subprocess | Applicable | Fixed commands and argv only; malformed rows are data, missing/hung optional sound degrades to diagnostics while visuals survive | Assert one tmux snapshot; shell-sensitive fields do not execute; unsupported/missing/failing sound preserves state and reports status |

## Migration / Rollout

PR #6 changes only sound defaults/doctor and rolls back by reverting those files or setting `AGENT_STATUS_SOUND_ENABLED=0`. The stacked presentation PR changes snapshot/tabs/picker and rolls back independently by restoring the three presenter scripts. Bash/tmux/fzf behavior is portable across macOS/Linux; default sound is platform-resolved, with `paplay` remaining opt-in on Linux. No state migration is required.

## Open Questions

None.
