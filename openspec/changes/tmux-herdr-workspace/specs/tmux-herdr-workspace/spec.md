# Tmux Herdr Workspace Specification

## Purpose

Provide a fast, vendor-neutral tmux workspace with trustworthy lifecycle visibility, detailed inspection, safe optional sound, and reproducible restoration.

## Requirements

### Requirement: Bounded and responsive rendering

The presenter MUST obtain one bounded bulk tmux snapshot per render and MUST NOT issue per-session `list-panes` calls. In shell/tmux acceptance tests, two sessions MUST render in ≤250 ms with warm commands and ≤500 ms cold; key-event handling MUST remain responsive while rendering.

#### Scenario: Two-session render
- GIVEN two sessions with panes and lifecycle records
- WHEN the status renderer refreshes
- THEN exactly one bulk pane snapshot is used and elapsed time is ≤500 ms cold (≤250 ms warm).

#### Scenario: Queued key event
- GIVEN a render is in progress and a tmux key event arrives
- WHEN the event is processed
- THEN it is not delayed by repeated synchronous per-session status commands.

### Requirement: Minimal accessible tabs

Tabs MUST show only the session name and a glanceable state color plus marker. They MUST NOT show counts or state words. Picker/inspect views MUST retain detailed state, and no-color output MUST distinguish states with markers or symbols.

#### Scenario: Mixed-state tab
- GIVEN a session contains running and permission panes
- WHEN its tab is rendered
- THEN only its name and the aggregate permission marker/color appear.

#### Scenario: No color
- GIVEN terminal color is unavailable
- WHEN tabs render
- THEN state remains distinguishable by a non-color marker.

### Requirement: Responsive hierarchical picker

The picker MUST open as a percentage-based large popup, support search, and list hierarchical session → window → pane rows. Pane rows MUST expose current command/process details, lifecycle colors/markers, and footer key hints. Structure MAY be inspired by Herdr but MUST NOT copy its UI wholesale.

#### Scenario: Search and inspect
- GIVEN sessions contain multiple windows and panes
- WHEN the user opens the picker and searches for a command
- THEN matching hierarchical rows appear with current process and lifecycle detail.

#### Scenario: Large workspace
- GIVEN more than 13 sessions or panes exist
- WHEN the picker opens
- THEN the popup supports scrolling/search without truncating the workspace to 13 rows.

### Requirement: Safe audible notification

Sound MUST remain disabled by default, provide an explicit macOS-safe audible default when enabled/configured, and MUST NOT execute arbitrary shell input. Doctor diagnostics MUST report sound configuration and availability. Visual state MUST survive all sound failures.

#### Scenario: Enabled default
- GIVEN sound is enabled on macOS without a custom command
- WHEN an attention transition occurs
- THEN the configured safe audible default is attempted and no arbitrary shell is evaluated.

#### Scenario: Sound failure
- GIVEN sound is enabled but unavailable
- WHEN an attention transition occurs
- THEN lifecycle visuals remain correct and doctor/diagnostics identify the failure.

### Requirement: Trustworthy lifecycle and recovery

The protocol MUST support `running`, `permission`, `waiting_for_input`, `blocked`, `done`, `idle`, and `error`; invalid or unsupported states MUST degrade to `blocked`. Stale records MUST recover safely, and urgency MUST be `error > permission > waiting_for_input > blocked > done > running > idle`.

#### Scenario: Unsupported or stale state
- GIVEN an adapter cannot distinguish input or a record exceeds freshness
- WHEN the presenter refreshes
- THEN it shows blocked or safely inactive/stale state without false active attention.
