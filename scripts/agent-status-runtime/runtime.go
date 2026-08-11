package runtime

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const SchemaVersion = 2

const (
	ExitComplete = 0
	ExitInvalid  = 1
	ExitPartial  = 2
)

type codedError string

func (e codedError) Error() string { return string(e) }

const (
	configInvalid        codedError = "config_invalid"
	identityInvalid      codedError = "identity_invalid"
	schemaUnsupported    codedError = "schema_unsupported"
	revisionNonMonotonic codedError = "revision_non_monotonic"
	epochExpired         codedError = "epoch_expired"
)

type Config struct {
	SchemaVersion          int
	ActiveTTL, TerminalTTL int64
}
type Identity struct{ Session, Pane, Source string }
type Capabilities struct{ Activity, Clear bool }
type Event struct {
	SchemaVersion    int
	Epoch            string
	Revision         uint64
	Identity         Identity
	State            string
	ProducerRevision uint64
}
type Pane struct {
	Session string `json:"session"`
	Pane    string `json:"pane"`
	State   string `json:"state"`
	Token   string `json:"token,omitempty"`
}
type Session struct {
	Name  string `json:"name"`
	State string `json:"state"`
	Token string `json:"token,omitempty"`
}
type Snapshot struct {
	SchemaVersion int       `json:"schema_version"`
	Epoch         string    `json:"epoch"`
	Revision      uint64    `json:"revision"`
	Panes         []Pane    `json:"panes"`
	Sessions      []Session `json:"sessions"`
}

func MarshalSnapshot(snapshot Snapshot) (string, error) {
	bytes, err := json.Marshal(snapshot)
	return string(bytes) + "\n", err
}

func ValidateSnapshot(snapshot Snapshot) error {
	if snapshot.SchemaVersion != SchemaVersion {
		return schemaUnsupported
	}
	if snapshot.Epoch == "" {
		return configInvalid
	}
	return nil
}

func ErrorCode(err error) string {
	for _, code := range []codedError{configInvalid, identityInvalid, schemaUnsupported, revisionNonMonotonic, epochExpired} {
		if errors.Is(err, code) || err != nil && err.Error() == string(code) {
			return string(code)
		}
	}
	return string(configInvalid)
}
func ValidateConfig(c Config) error {
	if c.SchemaVersion != SchemaVersion || c.ActiveTTL < 0 || c.TerminalTTL < 0 {
		return configInvalid
	}
	return nil
}
func ValidateIdentity(id Identity) error {
	if id.Session == "" || id.Pane == "" || id.Source == "" || strings.ContainsAny(id.Session+id.Pane+id.Source, "\t\n") {
		return identityInvalid
	}
	return nil
}
func ValidateCapabilities(c Capabilities) Capabilities { return c }
func ApplyEvent(s Snapshot, e Event) (Snapshot, error) {
	if e.SchemaVersion != SchemaVersion {
		return s, schemaUnsupported
	}
	if e.Epoch != s.Epoch {
		return s, epochExpired
	}
	if e.Revision <= s.Revision {
		return s, revisionNonMonotonic
	}
	if err := ValidateIdentity(e.Identity); err != nil {
		return s, err
	}
	if e.State != "" && validState(e.State) == "" {
		return s, configInvalid
	}
	s.Revision = e.Revision
	if e.State != "" {
		updated := false
		for i := range s.Panes {
			if s.Panes[i].Session == e.Identity.Session && s.Panes[i].Pane == e.Identity.Pane {
				s.Panes[i].State = e.State
				updated = true
			}
		}
		if !updated {
			s.Panes = append(s.Panes, Pane{Session: e.Identity.Session, Pane: e.Identity.Pane, State: e.State})
		}
		deriveSessions(&s)
	}
	return s, nil
}

func deriveSessions(snapshot *Snapshot) {
	sort.Slice(snapshot.Panes, func(i, j int) bool {
		if snapshot.Panes[i].Session == snapshot.Panes[j].Session {
			return snapshot.Panes[i].Pane < snapshot.Panes[j].Pane
		}
		return snapshot.Panes[i].Session < snapshot.Panes[j].Session
	})
	states := map[string]string{}
	for _, pane := range snapshot.Panes {
		if priority(pane.State) > priority(states[pane.Session]) {
			states[pane.Session] = pane.State
		}
	}
	snapshot.Sessions = snapshot.Sessions[:0]
	for name, state := range states {
		snapshot.Sessions = append(snapshot.Sessions, Session{Name: name, State: state})
	}
	sort.Slice(snapshot.Sessions, func(i, j int) bool { return snapshot.Sessions[i].Name < snapshot.Sessions[j].Name })
}

func ImportV1(root string, c Config, now int64) (Snapshot, []string, int) {
	snapshot := Snapshot{SchemaVersion: SchemaVersion}
	if ValidateConfig(c) != nil {
		return snapshot, nil, ExitInvalid
	}
	var diagnostics []string
	read := func(dir string, pane bool) {
		entries, err := os.ReadDir(filepath.Join(root, dir))
		if err != nil {
			return
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			path := filepath.Join(root, dir, entry.Name())
			state, updated, token, legacy, ok := parseRecord(path)
			if !ok {
				diagnostics = appendDiagnostic(diagnostics, path)
				continue
			}
			if !legacy && stale(state, updated, c, now) {
				state = "idle"
			}
			if pane {
				session, paneID, found := strings.Cut(entry.Name(), "_")
				if !found || session == "" || paneID == "" {
					diagnostics = appendDiagnostic(diagnostics, path)
					continue
				}
				snapshot.Panes = append(snapshot.Panes, Pane{Session: session, Pane: paneID, State: state, Token: token})
			} else {
				snapshot.Sessions = append(snapshot.Sessions, Session{Name: entry.Name(), State: state, Token: token})
			}
		}
	}
	read("panes", true)
	read("sessions", false)
	sort.Slice(snapshot.Panes, func(i, j int) bool {
		if snapshot.Panes[i].Session == snapshot.Panes[j].Session {
			return snapshot.Panes[i].Pane < snapshot.Panes[j].Pane
		}
		return snapshot.Panes[i].Session < snapshot.Panes[j].Session
	})
	derived := map[string]string{}
	for _, pane := range snapshot.Panes {
		if priority(pane.State) > priority(derived[pane.Session]) {
			derived[pane.Session] = pane.State
		}
	}
	for name, state := range derived {
		snapshot.Sessions = append(snapshot.Sessions, Session{Name: name, State: state})
	}
	sort.Slice(snapshot.Sessions, func(i, j int) bool { return snapshot.Sessions[i].Name < snapshot.Sessions[j].Name })
	if len(diagnostics) > 0 {
		return snapshot, diagnostics, ExitPartial
	}
	return snapshot, nil, ExitComplete
}

func parseRecord(path string) (string, int64, string, bool, bool) {
	bytes, err := os.ReadFile(path)
	if err != nil {
		return "", 0, "", false, false
	}
	fields := strings.Fields(strings.TrimSpace(string(bytes)))
	if len(fields) == 1 {
		state := validState(fields[0])
		return state, 0, "", true, state != ""
	}
	if len(fields) != 5 || fields[0] != "1" || validState(fields[1]) == "" {
		return "", 0, "", false, false
	}
	var updated int64
	for _, char := range fields[2] {
		if char < '0' || char > '9' {
			return "", 0, "", false, false
		}
		updated = updated*10 + int64(char-'0')
	}
	return fields[1], updated, fields[4], false, true
}
func validState(state string) string {
	switch state {
	case "running", "permission", "waiting_for_input", "blocked", "done", "idle", "error":
		return state
	}
	return ""
}
func stale(state string, updated int64, c Config, now int64) bool {
	ttl := c.ActiveTTL
	if state == "done" || state == "idle" || state == "error" {
		ttl = c.TerminalTTL
	}
	return now-updated > ttl
}
func priority(state string) int {
	switch state {
	case "error":
		return 70
	case "permission":
		return 60
	case "waiting_for_input":
		return 50
	case "blocked":
		return 40
	case "done":
		return 30
	case "running":
		return 20
	case "idle":
		return 10
	}
	return 0
}
func appendDiagnostic(diagnostics []string, path string) []string {
	if len(diagnostics) == 20 {
		return diagnostics
	}
	for len(path) > 210 {
		path = path[1:]
	}
	bytes, _ := json.Marshal(struct {
		Code string `json:"code"`
		Path string `json:"path"`
	}{"record_malformed", path})
	return append(diagnostics, string(bytes))
}
