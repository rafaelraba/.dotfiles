package runtime

import (
	"encoding/json"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"
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

func TestDecodeRequestRejectsUnsafeFrames(t *testing.T) {
	for _, frame := range []string{
		"\n",
		`{"op":"snapshot"}` + "\nextra",
		`{"op":"snapshot","op":"snapshot"}` + "\n",
		`{"op":"unknown"}` + "\n",
		`{"op":"publish","event":{"schema_version":2,"session":"work","pane":"p1","source":"agent","state":"running","extra":true}}` + "\n",
		`{"op":"publish","event":{"schema_version":2,"session":"work","pane":"p1","source":"agent","state":"running","state":"done"}}` + "\n",
		`{"op":"publish","event":{"schema_version":2,"session":"bad/id","pane":"p1","source":"agent","state":"running"}}` + "\n",
		`{"op":"subscribe","cursor":{"epoch":"epoch","revision":1,"extra":true}}` + "\n",
		strings.Repeat("x", 64<<10) + "\n",
	} {
		if _, err := DecodeRequest([]byte(frame)); err == nil {
			t.Fatalf("DecodeRequest(%q) accepted unsafe frame", frame[:min(len(frame), 20)])
		}
	}
	for _, frame := range []string{
		`{"op":"snapshot"}` + "\n",
		`{"op":"publish","event":{"schema_version":2,"session":"work","pane":"p1","source":"agent","state":"running"}}` + "\n",
		`{"op":"subscribe","cursor":{"epoch":"epoch","revision":1}}` + "\n",
	} {
		if _, err := DecodeRequest([]byte(frame)); err != nil {
			t.Fatalf("DecodeRequest(%q) error = %v", frame, err)
		}
	}
}

func TestEncodeResponseProducesBoundedMachineReadableNDJSON(t *testing.T) {
	encoded, err := EncodeResponse(Response{Type: "event", Event: &ProtocolEvent{SchemaVersion: 2, Epoch: "epoch", Revision: 1, Session: "work", Pane: "p1", Source: "agent", State: "running"}})
	if err != nil {
		t.Fatalf("EncodeResponse() error = %v", err)
	}
	var value map[string]any
	if err := json.Unmarshal(encoded, &value); err != nil {
		t.Fatalf("encoded response is not JSON: %v", err)
	}
	if string(encoded[len(encoded)-1]) != "\n" || value["type"] != "event" || value["event"].(map[string]any)["schema_version"] != float64(2) {
		t.Fatalf("EncodeResponse() = %s", encoded)
	}
}

func TestOwnerSubscribeReplaysThenStreamsOnce(t *testing.T) {
	owner := NewOwner(Snapshot{SchemaVersion: SchemaVersion})
	defer owner.Close()
	for _, pane := range []string{"p1", "p2"} {
		if _, err := owner.Publish(Event{SchemaVersion: SchemaVersion, Identity: Identity{Session: "work", Pane: pane, Source: "agent"}, State: "running"}); err != nil {
			t.Fatal(err)
		}
	}
	state := owner.Snapshot()
	replay, stream, err := owner.Subscribe(Cursor{Epoch: state.Epoch, Revision: 0})
	if err != nil || len(replay) != 2 || replay[0].Revision != 1 || replay[1].Revision != 2 {
		t.Fatalf("Subscribe() = %#v, %v", replay, err)
	}
	if _, err := owner.Publish(Event{SchemaVersion: SchemaVersion, Identity: Identity{Session: "work", Pane: "p3", Source: "agent"}, State: "done"}); err != nil {
		t.Fatal(err)
	}
	select {
	case event := <-stream:
		if event.Revision != 3 {
			t.Fatalf("stream revision = %d", event.Revision)
		}
	case <-time.After(time.Second):
		t.Fatal("stream did not receive live event")
	}
	_, slow, err := owner.Subscribe(Cursor{Epoch: state.Epoch, Revision: state.Revision})
	if err != nil {
		t.Fatal(err)
	}
	for i := 1; i <= 33; i++ {
		if _, err := owner.Publish(Event{SchemaVersion: SchemaVersion, Identity: Identity{Session: "work", Pane: "slow", Source: "agent"}, State: "running", ProducerRevision: uint64(i)}); err != nil {
			t.Fatal(err)
		}
	}
	count := 0
	for range slow {
		count++
	}
	if count != 32 {
		t.Fatalf("slow queue = %d", count)
	}
	for _, cursor := range []Cursor{{}, {Epoch: "old", Revision: 0}, {Epoch: state.Epoch, Revision: 99}} {
		if _, _, err := owner.Subscribe(cursor); err == nil {
			t.Fatalf("cursor %#v accepted", cursor)
		}
	}
}
