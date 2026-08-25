package runtime

import (
	"bufio"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"sync"
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

func TestOwnerClearRemovesStateAndAllowsSameProducerToReenter(t *testing.T) {
	owner := NewOwner(Snapshot{SchemaVersion: SchemaVersion})
	defer owner.Close()
	event := Event{SchemaVersion: SchemaVersion, Identity: Identity{Session: "work", Pane: "p1", Source: "agent"}, State: "permission", ProducerRevision: 7}
	if _, err := owner.Publish(event); err != nil {
		t.Fatal(err)
	}
	cleared, err := owner.Clear("work", "p1")
	if err != nil {
		t.Fatal(err)
	}
	if len(cleared.Panes) != 0 || len(cleared.Sessions) != 0 || cleared.Revision != 2 {
		t.Fatalf("cleared snapshot = %#v", cleared)
	}
	reentered, err := owner.Publish(event)
	if err != nil {
		t.Fatal(err)
	}
	if len(reentered.Panes) != 1 || reentered.Panes[0].State != "permission" || reentered.Revision != 3 {
		t.Fatalf("reentered snapshot = %#v", reentered)
	}
}

func TestOwnerClearRemovesPaneFromSubscribedStateImmediately(t *testing.T) {
	owner := NewOwner(Snapshot{SchemaVersion: SchemaVersion})
	defer owner.Close()
	subscribed := owner.Snapshot()
	_, stream, err := owner.Subscribe(Cursor{Epoch: subscribed.Epoch, Revision: subscribed.Revision})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := owner.Publish(Event{SchemaVersion: SchemaVersion, Identity: Identity{Session: "work", Pane: "p1", Source: "agent"}, State: "permission", ProducerRevision: 1}); err != nil {
		t.Fatal(err)
	}
	published := <-stream
	subscribed, err = ApplyEvent(subscribed, published)
	if err != nil || len(subscribed.Panes) != 1 {
		t.Fatalf("subscribed publish = %#v, %v", subscribed, err)
	}
	cleared, err := owner.Clear("work", "p1")
	if err != nil || len(cleared.Panes) != 0 {
		t.Fatalf("Clear() = %#v, %v", cleared, err)
	}
	deleted := <-stream
	if !deleted.Deleted || deleted.State != "" {
		t.Fatalf("clear event = %#v", deleted)
	}
	subscribed, err = ApplyEvent(subscribed, deleted)
	if err != nil || len(subscribed.Panes) != 0 || len(subscribed.Sessions) != 0 || subscribed.Revision != cleared.Revision {
		t.Fatalf("subscribed clear = %#v, %v", subscribed, err)
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
		`{"op":"clear","session":"bad/id","pane":"p1"}` + "\n",
		`{"op":"clear","pane":"p1"}` + "\n",
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
		`{"op":"clear","session":"work","pane":"p1"}` + "\n",
		`{"op":"clear","session":"work"}` + "\n",
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

func TestDecodeSnapshotStrictRejectsMalformedState(t *testing.T) {
	valid := `{"schema_version":2,"epoch":"epoch","revision":1,"panes":[{"session":"work","pane":"p1","state":"running"}],"sessions":[{"name":"work","state":"running"}]}`
	if _, err := DecodeSnapshotStrict([]byte(valid)); err != nil {
		t.Fatalf("valid snapshot rejected: %v", err)
	}
	for _, malformed := range []string{
		`{"schema_version":2,"epoch":"epoch","revision":1,"panes":null,"sessions":[]}`,
		`{"schema_version":2,"epoch":"epoch","revision":1,"panes":[{"session":"work","pane":"p1","state":"running","extra":true}],"sessions":[{"name":"work","state":"running"}]}`,
		`{"schema_version":2,"epoch":"epoch","revision":1,"panes":[{"session":"work","pane":"p1","state":"running"}],"sessions":[{"name":"work","state":"idle"}]}`,
		`{"schema_version":2,"epoch":"epoch","revision":1,"panes":[{"session":"work","pane":"p1","state":"running"},{"session":"work","pane":"p1","state":"running"}],"sessions":[{"name":"work","state":"running"}]}`,
	} {
		if _, err := DecodeSnapshotStrict([]byte(malformed)); err == nil {
			t.Fatalf("malformed snapshot accepted: %s", malformed)
		}
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
func TestListenSocketRejectsUnsafeEndpointsAndCleansOnlyOwnedInode(t *testing.T) {
	root := socketRoot(t)
	unsafe := filepath.Join(root, "unsafe")
	if err := os.Mkdir(unsafe, 0755); err != nil {
		t.Fatal(err)
	}
	if _, _, err := ListenSocket(root, filepath.Join(unsafe, "runtime.sock")); err == nil {
		t.Fatal("ListenSocket accepted a permissive parent")
	}
	secure := filepath.Join(root, "secure")
	if err := os.Mkdir(secure, 0700); err != nil {
		t.Fatal(err)
	}
	endpoint := filepath.Join(secure, "runtime.sock")
	mustWrite(t, endpoint, "file")
	if _, _, err := ListenSocket(root, endpoint); err == nil {
		t.Fatal("ListenSocket overwrote a regular file")
	}
	if err := os.Remove(endpoint); err != nil {
		t.Fatal(err)
	}
	_, cleanup, err := ListenSocket(root, endpoint)
	if err != nil {
		t.Fatal(err)
	}
	if info, err := os.Lstat(endpoint); err != nil || info.Mode().Perm() != 0600 {
		t.Fatalf("created socket mode = %v, %v; want 0600", info.Mode(), err)
	}
	cleanup()
	if _, err := os.Lstat(endpoint); !os.IsNotExist(err) {
		t.Fatalf("cleanup retained owned socket: %v", err)
	}
	_, cleanup, err = ListenSocket(root, endpoint)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(endpoint); err != nil {
		t.Fatal(err)
	}
	mustWrite(t, endpoint, "replacement")
	cleanup()
	if _, err := os.Stat(endpoint); err != nil {
		t.Fatalf("cleanup removed replacement endpoint: %v", err)
	}
	if _, _, err := ListenSocket(root, filepath.Join(t.TempDir(), "runtime.sock")); err == nil {
		t.Fatal("ListenSocket accepted endpoint outside root")
	}
	if err := os.Symlink(t.TempDir(), filepath.Join(root, "linked")); err != nil {
		t.Fatal(err)
	}
	if _, _, err := ListenSocket(root, filepath.Join(root, "linked", "runtime.sock")); err == nil {
		t.Fatal("ListenSocket accepted symlinked ancestor")
	}
	staleEndpoint := filepath.Join(root, "stale.sock")
	stale, _, err := ListenSocket(root, staleEndpoint)
	if err != nil {
		t.Fatal(err)
	}
	if err := stale.Close(); err != nil {
		t.Fatal(err)
	}
	replacement, replacementCleanup, err := ListenSocket(root, staleEndpoint)
	if err != nil {
		t.Fatalf("ListenSocket did not reclaim stale owned socket: %v", err)
	}
	defer replacementCleanup()
	if _, _, err := ListenSocket(root, staleEndpoint); err == nil {
		t.Fatal("ListenSocket replaced an active socket")
	}
	if connection, err := net.Dial("unix", replacement.Addr().String()); err != nil {
		t.Fatalf("active socket was disturbed: %v", err)
	} else {
		_ = connection.Close()
	}
}
func TestServeSocketSerializesConcurrentPublishAndSnapshot(t *testing.T) {
	root := socketRoot(t)
	listener, cleanup, err := ListenSocket(root, filepath.Join(root, "runtime.sock"))
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()
	owner := NewOwner(Snapshot{SchemaVersion: SchemaVersion})
	defer owner.Close()
	go ServeSocket(listener, owner)
	var group sync.WaitGroup
	for revision, pane := range []string{"p1", "p2"} {
		group.Add(1)
		go func(pane string) {
			defer group.Done()
			publishSocketEvent(t, listener, pane, revision+1)
		}(pane)
	}
	group.Wait()
	if snapshot := socketResponse(t, listener, `{"op":"snapshot"}`+"\n").Snapshot; snapshot.Revision != 2 || len(snapshot.Panes) != 2 {
		t.Fatalf("snapshot = %#v", snapshot)
	}
}

func TestServeSocketClearIsVisibleImmediately(t *testing.T) {
	root := socketRoot(t)
	listener, cleanup, err := ListenSocket(root, filepath.Join(root, "runtime.sock"))
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()
	owner := NewOwner(Snapshot{SchemaVersion: SchemaVersion})
	defer owner.Close()
	go ServeSocket(listener, owner)
	publishSocketEvent(t, listener, "p1", 1)
	response := socketResponse(t, listener, `{"op":"clear","session":"work","pane":"p1"}`+"\n")
	if response.Type != "ack" || len(response.Snapshot.Panes) != 0 || len(response.Snapshot.Sessions) != 0 || response.Snapshot.Revision != 2 {
		t.Fatalf("clear response = %#v", response)
	}
	if snapshot := socketResponse(t, listener, `{"op":"snapshot"}`+"\n").Snapshot; len(snapshot.Panes) != 0 || snapshot.Revision != 2 {
		t.Fatalf("post-clear snapshot = %#v", snapshot)
	}
}

func TestServeSocketExpiresActiveStateAcrossSnapshotsWithoutRestart(t *testing.T) {
	root := socketRoot(t)
	listener, cleanup, err := ListenSocket(root, filepath.Join(root, "runtime.sock"))
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()
	now := int64(100)
	owner := NewLiveOwner(LiveState{
		Snapshot: Snapshot{SchemaVersion: SchemaVersion, Panes: []Pane{{Session: "work", Pane: "p1", State: "running"}}},
		expiries: []paneExpiry{{session: "work", pane: "p1", at: 101}},
	}, Config{SchemaVersion: SchemaVersion, ActiveTTL: 1, TerminalTTL: 10}, func() int64 { return now })
	defer owner.Close()
	go ServeSocket(listener, owner)

	first := socketResponse(t, listener, `{"op":"snapshot"}`+"\n").Snapshot
	now = 102
	second := socketResponse(t, listener, `{"op":"snapshot"}`+"\n").Snapshot
	if first.Epoch == "" || first.Epoch != second.Epoch || first.Revision != second.Revision {
		t.Fatalf("server identity changed across snapshots: first=%#v second=%#v", first, second)
	}
	if first.Panes[0].State != "running" || second.Panes[0].State != "idle" || second.Sessions[0].State != "idle" {
		t.Fatalf("TTL snapshots = %#v then %#v", first, second)
	}
}

func TestServeSocketProvesConcurrentSnapshotSubscriptionAndSlowDisconnect(t *testing.T) {
	root := socketRoot(t)
	listener, cleanup, err := ListenSocket(root, filepath.Join(root, "runtime.sock"))
	if err != nil {
		t.Fatal(err)
	}
	defer cleanup()
	owner := NewOwner(Snapshot{SchemaVersion: SchemaVersion})
	defer owner.Close()
	go ServeSocket(listener, owner)
	state := socketResponse(t, listener, `{"op":"snapshot"}`+"\n").Snapshot
	publishSocketEvent(t, listener, "slow", 1)
	subscriber, err := net.Dial("unix", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer subscriber.Close()
	if _, err := subscriber.Write([]byte(`{"op":"subscribe","cursor":{"epoch":"` + state.Epoch + `","revision":0}}` + "\n")); err != nil {
		t.Fatal(err)
	}
	reader := bufio.NewReader(subscriber)
	if replay, err := socketResponseReader(reader); err != nil || replay.Event == nil || replay.Event.Revision != 1 || replay.Event.ProducerRevision != 1 {
		t.Fatalf("subscribe replay = %#v, %v", replay, err)
	}
	publishSocketEvent(t, listener, "slow", 2)
	if live, err := socketResponseReader(reader); err != nil || live.Event == nil || live.Event.Revision != 2 || live.Event.ProducerRevision != 2 {
		t.Fatalf("subscribe live event = %#v, %v", live, err)
	}
	publisher, err := net.Dial("unix", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := publisher.Write([]byte(`{"op":"publish","event":{"schema_version":2,"session":"work","pane":"slow","source":"agent","state":"running","producer_revision":3}}` + "\n")); err != nil {
		t.Fatal(err)
	}
	if published, err := socketResponseReader(reader); err != nil || published.Event == nil || published.Event.Revision != 3 || published.Event.ProducerRevision != 3 {
		t.Fatalf("concurrent socket publication = %#v, %v", published, err)
	}
	snapshot := socketResponse(t, listener, `{"op":"snapshot"}`+"\n")
	if snapshot.Type != "snapshot" || snapshot.Snapshot.Epoch != state.Epoch || snapshot.Snapshot.Revision != 3 {
		t.Fatalf("concurrent socket snapshot = %#v", snapshot)
	}
	if ack, err := socketResponseReader(bufio.NewReader(publisher)); err != nil || ack.Type != "ack" || ack.Snapshot.Revision != 3 {
		t.Fatalf("concurrent socket publish = %#v, %v", ack, err)
	}
	for i := 4; i <= 2000; i++ {
		publishSocketEvent(t, listener, "slow", i)
	}
	if healthy := socketResponse(t, listener, `{"op":"snapshot"}`+"\n"); healthy.Type != "snapshot" || healthy.Snapshot.Revision != 2000 {
		t.Fatalf("healthy socket snapshot = %#v", healthy)
	}
	_ = subscriber.SetReadDeadline(time.Now().Add(3 * time.Second))
	for {
		if _, err := reader.ReadBytes('\n'); err != nil {
			if timeout, ok := err.(net.Error); ok && timeout.Timeout() {
				t.Fatal("slow socket subscriber was not disconnected")
			}
			break
		}
	}
}
func publishSocketEvent(t *testing.T, listener *net.UnixListener, pane string, revision int) {
	t.Helper()
	frame := `{"op":"publish","event":{"schema_version":2,"session":"work","pane":"` + pane + `","source":"agent","state":"running","producer_revision":` + strconv.Itoa(revision) + `}}` + "\n"
	if response := socketResponse(t, listener, frame); response.Type != "ack" {
		t.Fatalf("publish response = %#v", response)
	}
}
func socketResponse(t *testing.T, listener *net.UnixListener, frame string) Response {
	t.Helper()
	connection, err := net.Dial("unix", listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	if _, err := connection.Write([]byte(frame)); err != nil {
		t.Fatal(err)
	}
	decoded, err := socketResponseReader(bufio.NewReader(connection))
	if err != nil {
		t.Fatal(err)
	}
	return decoded
}
func socketResponseReader(reader *bufio.Reader) (decoded Response, err error) {
	response, err := reader.ReadBytes('\n')
	if err == nil {
		err = json.Unmarshal(response, &decoded)
	}
	return decoded, err
}
func socketRoot(t *testing.T) string {
	root := filepath.Join("/tmp", "as-"+strconv.Itoa(os.Getpid()))
	if err := os.MkdirAll(root, 0700); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(root) })
	return root
}
