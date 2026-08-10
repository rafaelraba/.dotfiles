package runtime

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestValidateContracts(t *testing.T) {
	identity := Identity{Session: "work", Pane: "%1", Source: "opencode"}
	if err := ValidateIdentity(identity); err != nil {
		t.Fatalf("valid identity: %v", err)
	}
	if err := ValidateConfig(Config{SchemaVersion: 2, ActiveTTL: 10, TerminalTTL: 20}); err != nil {
		t.Fatalf("valid config: %v", err)
	}
	if code := ErrorCode(ValidateConfig(Config{SchemaVersion: 1})); code != "config_invalid" {
		t.Fatalf("config code = %q", code)
	}
	if code := ErrorCode(ValidateIdentity(Identity{Session: "work"})); code != "identity_invalid" {
		t.Fatalf("identity code = %q", code)
	}
	if got := ValidateCapabilities(Capabilities{}); !reflect.DeepEqual(got, Capabilities{Activity: false, Clear: false}) {
		t.Fatalf("capabilities = %#v", got)
	}
}

func TestApplyEventRejectsSchemaAndReplay(t *testing.T) {
	base := Snapshot{SchemaVersion: 2, Epoch: "new", Revision: 4}
	event := Event{SchemaVersion: 2, Epoch: "new", Revision: 5, Identity: Identity{Session: "work", Pane: "%1", Source: "opencode"}}
	if got, err := ApplyEvent(base, event); err != nil || got.Revision != 5 {
		t.Fatalf("apply event = %#v, %v", got, err)
	}
	for _, tc := range []struct {
		name  string
		event Event
		code  string
	}{
		{"unknown schema", Event{SchemaVersion: 3}, "schema_unsupported"},
		{"old revision", Event{SchemaVersion: 2, Epoch: "new", Revision: 4, Identity: event.Identity}, "revision_non_monotonic"},
		{"old epoch", Event{SchemaVersion: 2, Epoch: "old", Revision: 6, Identity: event.Identity}, "epoch_expired"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if code := ErrorCode(func() error { _, err := ApplyEvent(base, tc.event); return err }()); code != tc.code {
				t.Fatalf("code = %q", code)
			}
		})
	}
}

func TestValidateSnapshotRejectsUnknownSchema(t *testing.T) {
	if code := ErrorCode(ValidateSnapshot(Snapshot{SchemaVersion: 3, Epoch: "epoch"})); code != "schema_unsupported" {
		t.Fatalf("snapshot code = %q", code)
	}
}

func TestImportV1IsDeterministicReadOnlyAndBounded(t *testing.T) {
	root := t.TempDir()
	panes := filepath.Join(root, "panes")
	sessions := filepath.Join(root, "sessions")
	if err := os.MkdirAll(panes, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(sessions, 0700); err != nil {
		t.Fatal(err)
	}
	mustWrite(t, filepath.Join(panes, "zeta__2"), "1\trunning\t60\topencode\t1\n")
	mustWrite(t, filepath.Join(panes, "alpha__1"), "1\tdone\t60\tclaude\t2\n")
	mustWrite(t, filepath.Join(panes, "bad"), strings.Repeat("x", 300))
	mustWrite(t, filepath.Join(sessions, "legacy"), "permission\n")
	before := sourceState(t, root)
	first, diagnostics, exit := ImportV1(root, Config{SchemaVersion: 2, ActiveTTL: 10, TerminalTTL: 100}, 100)
	second, diagnosticsAgain, exitAgain := ImportV1(root, Config{SchemaVersion: 2, ActiveTTL: 10, TerminalTTL: 100}, 100)
	if exit != 2 || exitAgain != 2 || !reflect.DeepEqual(first, second) || !reflect.DeepEqual(diagnostics, diagnosticsAgain) {
		t.Fatalf("import is not deterministic: %#v %#v %d %d", first, diagnostics, exit, exitAgain)
	}
	if got := []string{first.Panes[0].Session, first.Panes[0].Pane, first.Panes[0].State, first.Panes[1].State, first.Sessions[1].State}; !reflect.DeepEqual(got, []string{"alpha", "_1", "done", "idle", "permission"}) {
		t.Fatalf("snapshot = %#v", got)
	}
	if len(diagnostics) != 1 || len(diagnostics[0]) > 256 || !strings.Contains(diagnostics[0], `"code":"record_malformed"`) {
		t.Fatalf("diagnostics = %#v", diagnostics)
	}
	if !reflect.DeepEqual(before, sourceState(t, root)) {
		t.Fatal("import mutated v1 source")
	}
}

func mustWrite(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
}

type sourceMetadata struct {
	bytes    string
	size     int64
	mode     os.FileMode
	modified int64
}

func sourceState(t *testing.T, root string) map[string]sourceMetadata {
	t.Helper()
	result := map[string]sourceMetadata{}
	for _, dir := range []string{"panes", "sessions"} {
		entries, err := os.ReadDir(filepath.Join(root, dir))
		if err != nil {
			t.Fatal(err)
		}
		for _, entry := range entries {
			path := filepath.Join(root, dir, entry.Name())
			info, err := entry.Info()
			if err != nil {
				t.Fatal(err)
			}
			bytes, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			result[dir+"/"+entry.Name()] = sourceMetadata{string(bytes), info.Size(), info.Mode(), info.ModTime().UnixNano()}
		}
	}
	return result
}

func TestErrorCode(t *testing.T) {
	if got := ErrorCode(errors.New("other")); got != "config_invalid" {
		t.Fatalf("fallback code = %q", got)
	}
}

func TestExitCodesAreCentralized(t *testing.T) {
	if ExitComplete != 0 || ExitInvalid != 1 || ExitPartial != 2 {
		t.Fatalf("exit codes = %d, %d, %d", ExitComplete, ExitInvalid, ExitPartial)
	}
}

func TestMarshalSnapshotIsStable(t *testing.T) {
	snapshot := Snapshot{SchemaVersion: 2, Epoch: "epoch", Revision: 7, Panes: []Pane{{Session: "work", Pane: "_1", State: "running"}}}
	first, err := MarshalSnapshot(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	second, err := MarshalSnapshot(snapshot)
	if err != nil || first != second || first != `{"schema_version":2,"epoch":"epoch","revision":7,"panes":[{"session":"work","pane":"_1","state":"running"}],"sessions":null}`+"\n" {
		t.Fatalf("snapshot JSON = %q, %v", first, err)
	}
}
