# Tmux Herdr Workspace Specification

## Purpose

Define a vendor-neutral, reproducible tmux workspace that exposes trustworthy agent lifecycle state while remaining safe when events are incomplete, stale, unsupported, or unavailable.

## ADDED Requirements

### Requirement: Canonical lifecycle contract

The protocol MUST accept `running`, `permission`, `waiting_for_input`, `blocked`, `done`, `idle`, and `error`, with producer identity, session/pane identity, event time, and freshness metadata. Adapters MUST normalize invalid or unsupported states to `blocked`.

#### Scenario: Valid event

- **GIVEN** a registered adapter emits a supported state with identifiers and timestamp
- **WHEN** the event is consumed
- **THEN** the canonical record is accepted and rendered for its pane.

#### Scenario: Unsupported distinction

- **GIVEN** an adapter cannot distinguish permission from input
- **WHEN** it reports the condition
- **THEN** the record is `blocked`, never falsely labeled as permission or input.

### Requirement: Explicit transitions and freshness

State changes MUST be monotonic per event sequence, terminal states MUST clear active attention, and records older than configured freshness MUST recover to `idle` or `blocked` without claiming active work.

#### Scenario: Completion

- **GIVEN** a pane is `running`
- **WHEN** a valid `done` event arrives
- **THEN** attention stops and the pane remains inspectable as done.

#### Scenario: Stale producer

- **GIVEN** no update arrives before the freshness limit
- **WHEN** the presenter refreshes
- **THEN** the pane is marked safely inactive and visibly stale/error-qualified.

### Requirement: Permission and waiting semantics

The presenter MUST distinguish permission from waiting input in icon, label, and attention treatment; `error > permission > waiting_for_input > blocked > done > running > idle` MUST define urgency.

#### Scenario: Concurrent attention

- **GIVEN** panes require permission and input simultaneously
- **WHEN** session urgency is computed
- **THEN** permission leads while both meanings remain visible.

### Requirement: Pane/session aggregation

Pane state MUST be independently addressable; session state MUST aggregate the highest urgency and retain counts for each non-idle state.

#### Scenario: Mixed session

- **GIVEN** one session has running, done, and blocked panes
- **WHEN** its tab is rendered
- **THEN** the tab shows blocked urgency and deterministic counts without losing pane detail.

### Requirement: Adapter parity

OpenCode, Codex, Pi, and Claude Code adapters MUST implement the contract independently, emit supported native states, and degrade gracefully when hooks or APIs are absent.

#### Scenario: Missing integration

- **GIVEN** an agent exposes no usable lifecycle event
- **WHEN** its adapter initializes
- **THEN** the workspace remains usable and reports unavailable/blocked rather than failing tmux.

### Requirement: Stable tab ordering

Tabs MUST sort by configured order, then stable session identity using lexical fallback; ordering MUST NOT depend on event arrival, urgency, or restart timing.

#### Scenario: Restart determinism

- **GIVEN** identical sessions and configuration across two starts
- **WHEN** tabs are rendered
- **THEN** both orders are identical, including ties.

### Requirement: Accessible status rendering

Status output MUST expose text labels in addition to color, use distinguishable symbols, preserve contrast, and provide a no-color readable mode.

#### Scenario: Color unavailable

- **GIVEN** a terminal disables color
- **WHEN** status is rendered
- **THEN** state names/symbols still communicate urgency and meaning.

### Requirement: Optional sound policy

Sounds MUST be disabled by default, explicitly configurable, and deduplicated by state transition and pane/session identity within a configured cooldown.

#### Scenario: Repeated event

- **GIVEN** sound is enabled and the same attention state is refreshed repeatedly
- **WHEN** events arrive within cooldown
- **THEN** only the first transition produces sound.

### Requirement: Recovery and restoration

Configuration and persisted state MUST be versioned; restore MUST migrate supported prior versions, preserve existing sessions, verify adapters/presenter wiring, and permit rollback to legacy rendering.

#### Scenario: Older install

- **GIVEN** a supported older configuration
- **WHEN** restoration runs
- **THEN** it migrates, validates, and reports each component without disrupting current tmux sessions.

### Requirement: Extension and security contract

New adapters MUST declare identity, capabilities, event schema/version, and failure behavior. Inputs MUST be treated as untrusted data, writes MUST be scoped to configured state locations, and malformed events MUST NOT execute commands or crash the presenter.

#### Scenario: Malformed event

- **GIVEN** an event contains invalid fields or shell-sensitive text
- **WHEN** parsed
- **THEN** it is rejected or safely normalized, logged without secrets, and the workspace continues operating.

### Requirement: Graceful degradation

If tmux, an adapter, sound command, or state source is unavailable, unaffected workspace functions MUST continue and the user MUST receive actionable diagnostics.

#### Scenario: Sound unavailable

- **GIVEN** notification is enabled but the platform command is missing
- **WHEN** an attention transition occurs
- **THEN** visual status remains correct and diagnostics identify the optional failure.
