# Tmux Herdr Workspace

## Intent

Build a reproducible, corporate-safe tmux workspace manager that preserves Herdr's useful agent visibility without coupling tmux to any agent. Users running OpenCode, Codex, Pi, or Claude Code should see trustworthy lifecycle state, stable tabs, clear attention hierarchy, optional notifications, and automatic recovery from stale events.

## Scope

### In Scope

- A shared lifecycle protocol with canonical `running`, `permission`, `waiting_for_input`, `blocked`, `done`, `idle`, and `error` states.
- Agent adapters that translate native events; unsupported permission/input distinctions may degrade to `blocked`.
- Tmux presentation with distinct permission/input semantics, priority-based hierarchy, deterministic configured ordering with lexical fallback, and stale-state recovery.
- Configurable sound notifications, disabled by default.
- Versioned configuration, installation verification, migration, and extension contracts for future adapters.
- Phased rollout within one architecture: protocol/presenter, adapter parity, notifications/recovery, then restoration hardening.

### Out of Scope

- Replacing tmux or modifying agent vendors.
- Reproducing Herdr's full UI, remote orchestration, analytics, or process supervision.
- Requiring every agent to expose lifecycle events it cannot emit.

## Capabilities

### New Capabilities

- `agent-lifecycle-protocol`: Canonical states, event contract, degradation rules, freshness, and adapter extension points.
- `tmux-workspace-presentation`: Deterministic tabs, visual hierarchy, state aggregation, stale recovery, and default-off sound.
- `workspace-restoration`: Reproducible dotfiles installation, migration, and wiring verification.

### Modified Capabilities

None.

## Product Behavior

`permission` and `waiting_for_input` remain distinct and visually distinguishable. Aggregate urgency is `error > permission > waiting_for_input > blocked > done > running > idle`. Expired or missing producer updates cannot remain active indefinitely; the presenter recovers to a safe non-active state. Existing sessions remain usable during adapter migration.

## Approach

Keep tmux a generic consumer. Adapters emit the shared file/event protocol; protocol utilities validate and normalize state; tmux scripts aggregate and render it. Central configuration controls ordering, colors/icons, freshness thresholds, and sound policy.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `~/.dotfiles/scripts/agent-status*` | Modified | Protocol, aggregation, ordering, recovery |
| `~/.dotfiles/editors/{claude,opencode,pi}` | Modified | Adapter registration and config |
| `~/.dotfiles/editors/codex` | New | Codex adapter and hooks |
| `~/.dotfiles/install` | Modified | Restore/migrate/verify wiring |

## Migration Strategy

Accept legacy states during a compatibility window, map old `blocked` unchanged, install adapters independently, and preserve current tmux behavior until each phase is enabled. Version all previously local-only wiring.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Vendor events differ or change | High | Thin adapters, contract tests, generic degradation |
| False/stale attention | Medium | Timestamps, TTLs, terminal-event cleanup |
| Notification disruption | Low | Default-off, explicit opt-in |
| Tab churn or migration breakage | Medium | Stable ordering rules, compatibility window, verification |

## Rollback Plan

Disable new adapter registrations and presenter features, restore legacy renderer/config symlinks, and retain compatibility parsing so existing state files continue working.

## Dependencies

- tmux, shell utilities, agent hook/plugin APIs, and an optional platform sound command.

## Success Criteria

- [ ] All four agents produce accurate supported states; unsupported distinctions degrade to `blocked`.
- [ ] Permission and input waits are visibly distinct; stale active states recover automatically.
- [ ] Tabs remain deterministic across restarts and sounds remain off until enabled.
- [ ] A clean dotfiles restore installs and verifies every adapter and configuration.
