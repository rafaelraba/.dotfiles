package runtime

import (
	"os"
	"reflect"
	"testing"
)

func TestApplyEventUpdatesDeterministicState(t *testing.T) {
	base := Snapshot{
		SchemaVersion: SchemaVersion,
		Epoch:         "epoch",
		Revision:      1,
		Panes: []Pane{
			{Session: "zeta", Pane: "%2", State: "done"},
		},
	}
	event := Event{
		SchemaVersion:    SchemaVersion,
		Epoch:            "epoch",
		Revision:         2,
		Identity:         Identity{Session: "alpha", Pane: "%1", Source: "agent"},
		State:            "permission",
		ProducerRevision: 4,
	}
	got, err := ApplyEvent(base, event)
	if err != nil {
		t.Fatalf("ApplyEvent() error = %v", err)
	}
	want := Snapshot{
		SchemaVersion: SchemaVersion,
		Epoch:         "epoch",
		Revision:      2,
		Panes: []Pane{
			{Session: "alpha", Pane: "%1", State: "permission"},
			{Session: "zeta", Pane: "%2", State: "done"},
		},
		Sessions: []Session{
			{Name: "alpha", State: "permission"},
			{Name: "zeta", State: "done"},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("ApplyEvent() = %#v, want %#v", got, want)
	}
}
func TestApplyEventRejectsInvalidStateAndIdentity(t *testing.T) {
	base := Snapshot{SchemaVersion: SchemaVersion, Epoch: "epoch", Revision: 1}
	for _, event := range []Event{
		{SchemaVersion: SchemaVersion, Epoch: "epoch", Revision: 2, Identity: Identity{Session: "work", Pane: "%1", Source: "agent"}, State: "unknown"},
		{SchemaVersion: SchemaVersion, Epoch: "epoch", Revision: 2, Identity: Identity{Session: "work", Pane: "%1"}, State: "running"},
	} {
		got, err := ApplyEvent(base, event)
		if err == nil || !reflect.DeepEqual(got, base) {
			t.Fatalf("ApplyEvent(%#v) = %#v, %v; want unchanged state and error", event, got, err)
		}
	}
}
func TestApplyEventReplacesExistingPaneState(t *testing.T) {
	base := Snapshot{SchemaVersion: SchemaVersion, Epoch: "epoch", Revision: 1, Panes: []Pane{{Session: "work", Pane: "%1", State: "running"}}}
	got, err := ApplyEvent(base, Event{SchemaVersion: SchemaVersion, Epoch: "epoch", Revision: 2, Identity: Identity{Session: "work", Pane: "%1", Source: "agent"}, State: "error"})
	if err != nil || !reflect.DeepEqual(got.Panes, []Pane{{Session: "work", Pane: "%1", State: "error"}}) || !reflect.DeepEqual(got.Sessions, []Session{{Name: "work", State: "error"}}) {
		t.Fatalf("ApplyEvent() = %#v, %v", got, err)
	}
}

func TestImportV1PreservesRecordTokens(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(root+"/panes", 0700); err != nil {
		t.Fatal(err)
	}
	mustWrite(t, root+"/panes/work_%1", "1\trunning\t10\tagent\tproducer-7\n")
	mustWrite(t, root+"/panes/bad", "invalid\n")
	if err := os.MkdirAll(root+"/sessions", 0700); err != nil {
		t.Fatal(err)
	}
	snapshot, diagnostics, exit := ImportV1(root, Config{SchemaVersion: SchemaVersion, ActiveTTL: 100, TerminalTTL: 100}, 20)
	if exit != ExitPartial || len(diagnostics) != 1 {
		t.Fatalf("ImportV1() diagnostics = %#v, exit = %d", diagnostics, exit)
	}
	if got := snapshot.Panes; !reflect.DeepEqual(got, []Pane{{Session: "work", Pane: "%1", State: "running", Token: "producer-7"}}) {
		t.Fatalf("ImportV1() panes = %#v", got)
	}
}

func TestOwnerPublishesOrderedDeterministicSnapshots(t *testing.T) {
	owner := NewOwner(Snapshot{SchemaVersion: SchemaVersion, Panes: []Pane{{Session: "zeta", Pane: "%2", State: "done"}}})
	defer owner.Close()
	first, err := owner.Publish(Event{SchemaVersion: SchemaVersion, Identity: Identity{Session: "alpha", Pane: "%1", Source: "agent"}, State: "running", ProducerRevision: 1})
	if err != nil {
		t.Fatalf("first Publish() error = %v", err)
	}
	second, err := owner.Publish(Event{SchemaVersion: SchemaVersion, Identity: Identity{Session: "alpha", Pane: "%1", Source: "agent"}, State: "permission", ProducerRevision: 2})
	if err != nil {
		t.Fatalf("second Publish() error = %v", err)
	}
	if first.Epoch == "" || len(first.Epoch) != 32 || first.Revision != 1 || second.Revision != 2 {
		t.Fatalf("revisions = %#v, %#v", first, second)
	}
	if got := second.Panes; !reflect.DeepEqual(got, []Pane{{Session: "alpha", Pane: "%1", State: "permission"}, {Session: "zeta", Pane: "%2", State: "done"}}) {
		t.Fatalf("snapshot panes = %#v", got)
	}
}

func TestOwnerRejectsInvalidEventWithoutRevision(t *testing.T) {
	owner := NewOwner(Snapshot{SchemaVersion: SchemaVersion})
	defer owner.Close()
	before := owner.Snapshot()
	if _, err := owner.Publish(Event{SchemaVersion: SchemaVersion, Identity: Identity{Session: "work", Pane: "%1", Source: "agent"}, State: "invalid"}); err == nil {
		t.Fatal("Publish() error = nil")
	}
	if after := owner.Snapshot(); !reflect.DeepEqual(after, before) {
		t.Fatalf("snapshot changed: before %#v, after %#v", before, after)
	}
}

func TestOwnerSerializesConcurrentPublishes(t *testing.T) {
	owner := NewOwner(Snapshot{SchemaVersion: SchemaVersion})
	defer owner.Close()
	results := make(chan Snapshot, 2)
	for _, pane := range []string{"%1", "%2"} {
		go func(pane string) {
			snapshot, err := owner.Publish(Event{SchemaVersion: SchemaVersion, Identity: Identity{Session: "work", Pane: pane, Source: "agent"}, State: "running"})
			if err != nil {
				t.Errorf("Publish(%s) error = %v", pane, err)
				return
			}
			results <- snapshot
		}(pane)
	}
	first, second := <-results, <-results
	if first.Revision+second.Revision != 3 || owner.Snapshot().Revision != 2 {
		t.Fatalf("revisions = %d, %d, final = %d", first.Revision, second.Revision, owner.Snapshot().Revision)
	}
}
