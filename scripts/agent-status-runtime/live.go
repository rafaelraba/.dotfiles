package runtime

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode/utf8"
)

type Owner struct {
	requests chan ownerRequest
	done     chan struct{}
	close    sync.Once
}

type ownerRequest struct {
	event    *Event
	cursor   *Cursor
	response chan ownerResponse
}

type ownerResponse struct {
	snapshot Snapshot
	err      error
	events   []Event
	stream   <-chan Event
}

type Cursor struct {
	Epoch    string `json:"epoch"`
	Revision uint64 `json:"revision"`
}
type Request struct {
	Op     string `json:"op"`
	Event  Event  `json:"event"`
	Cursor Cursor `json:"cursor"`
}
type Response struct {
	Type     string         `json:"type"`
	Code     string         `json:"code,omitempty"`
	Snapshot Snapshot       `json:"snapshot,omitempty"`
	Event    *ProtocolEvent `json:"event,omitempty"`
}
type ProtocolEvent struct {
	SchemaVersion    int    `json:"schema_version"`
	Epoch            string `json:"epoch"`
	Revision         uint64 `json:"revision"`
	Session          string `json:"session"`
	Pane             string `json:"pane"`
	Source           string `json:"source"`
	State            string `json:"state"`
	ProducerRevision uint64 `json:"producer_revision"`
}

func NewOwner(imported Snapshot) *Owner {
	return NewLiveOwner(LiveState{Snapshot: imported}, Config{SchemaVersion: SchemaVersion, ActiveTTL: 300, TerminalTTL: 3600}, func() int64 { return time.Now().Unix() })
}

func NewLiveOwner(imported LiveState, config Config, clock func() int64) *Owner {
	epoch := make([]byte, 16)
	if _, err := rand.Read(epoch); err != nil {
		panic(err)
	}
	state := cloneSnapshot(imported.Snapshot)
	state.SchemaVersion = SchemaVersion
	state.Epoch = hex.EncodeToString(epoch)
	state.Revision = 0
	deriveSessions(&state)
	if state.Panes == nil {
		state.Panes = []Pane{}
	}
	if state.Sessions == nil {
		state.Sessions = []Session{}
	}
	expiries := map[paneIdentity]int64{}
	for _, expiry := range imported.expiries {
		expiries[paneIdentity{session: expiry.session, pane: expiry.pane}] = expiry.at
	}
	owner := &Owner{requests: make(chan ownerRequest), done: make(chan struct{})}
	go owner.run(state, expiries, config, clock)
	return owner
}

type paneIdentity struct {
	session, pane string
}

func (o *Owner) Publish(event Event) (Snapshot, error) {
	return o.request(&event)
}

func (o *Owner) Snapshot() Snapshot {
	snapshot, _ := o.request(nil)
	return snapshot
}

func (o *Owner) Subscribe(cursor Cursor) ([]Event, <-chan Event, error) {
	response := make(chan ownerResponse, 1)
	select {
	case o.requests <- ownerRequest{cursor: &cursor, response: response}:
	case <-o.done:
		return nil, nil, configInvalid
	}
	result := <-response
	return result.events, result.stream, result.err
}

func (o *Owner) Close() { o.close.Do(func() { close(o.done) }) }

func (o *Owner) request(event *Event) (Snapshot, error) {
	response := make(chan ownerResponse, 1)
	select {
	case o.requests <- ownerRequest{event: event, response: response}:
	case <-o.done:
		return Snapshot{}, configInvalid
	}
	result := <-response
	return result.snapshot, result.err
}

func (o *Owner) run(state Snapshot, expiries map[paneIdentity]int64, config Config, clock func() int64) {
	last, journal, subscribers := map[Identity]Event{}, []Event{}, map[chan Event]struct{}{}
	for {
		select {
		case <-o.done:
			return
		case request := <-o.requests:
			current := expiringSnapshot(state, expiries, clock())
			if request.cursor != nil {
				cursor := *request.cursor
				if cursor.Epoch == "" || cursor.Epoch != state.Epoch || cursor.Revision > state.Revision || (len(journal) > 0 && cursor.Revision+1 < journal[0].Revision) {
					request.response <- ownerResponse{err: epochExpired}
					continue
				}
				replay := []Event{}
				for _, event := range journal {
					if event.Revision > cursor.Revision {
						replay = append(replay, event)
					}
				}
				if len(subscribers) == 16 {
					request.response <- ownerResponse{err: configInvalid}
					continue
				}
				stream := make(chan Event, 32)
				subscribers[stream] = struct{}{}
				request.response <- ownerResponse{events: replay, stream: stream}
				continue
			}
			if request.event == nil {
				request.response <- ownerResponse{snapshot: current}
				continue
			}
			event := *request.event
			if event.State == "" || event.SchemaVersion != SchemaVersion || ValidateIdentity(event.Identity) != nil || validState(event.State) == "" || (event.Epoch != "" && event.Epoch != state.Epoch) {
				request.response <- ownerResponse{snapshot: current, err: configInvalid}
				continue
			}
			if prior, found := last[event.Identity]; found && prior.State == event.State && prior.ProducerRevision == event.ProducerRevision {
				request.response <- ownerResponse{snapshot: current}
				continue
			}
			event.Epoch, event.Revision = state.Epoch, state.Revision+1
			next, err := ApplyEvent(state, event)
			if err == nil {
				state, last[event.Identity] = next, event
				now := clock()
				expiries[paneIdentity{session: event.Identity.Session, pane: event.Identity.Pane}] = expiryAt(now, event.State, config)
				journal = append(journal, event)
				if len(journal) > 1000 {
					journal = journal[1:]
				}
				for subscriber := range subscribers {
					select {
					case subscriber <- event:
					default:
						close(subscriber)
						delete(subscribers, subscriber)
					}
				}
			}
			request.response <- ownerResponse{snapshot: expiringSnapshot(state, expiries, clock()), err: err}
		}
	}
}

func expiringSnapshot(state Snapshot, expiries map[paneIdentity]int64, now int64) Snapshot {
	result := cloneSnapshot(state)
	changed := false
	for index := range result.Panes {
		expiresAt, found := expiries[paneIdentity{session: result.Panes[index].Session, pane: result.Panes[index].Pane}]
		if found && result.Panes[index].State != "idle" && now > expiresAt {
			result.Panes[index].State = "idle"
			changed = true
		}
	}
	if changed {
		deriveSessions(&result)
	}
	return result
}

func DecodeRequest(frame []byte) (Request, error) {
	if len(frame) == 0 || len(frame) > 64<<10 || !utf8.Valid(frame) || bytes.ContainsRune(frame, 0) || !bytes.HasSuffix(frame, []byte("\n")) || bytes.Count(frame, []byte("\n")) != 1 {
		return Request{}, configInvalid
	}
	line := bytes.TrimSuffix(frame, []byte("\n"))
	if strictJSON(line) != nil {
		return Request{}, configInvalid
	}
	var raw map[string]json.RawMessage
	if json.Unmarshal(line, &raw) != nil || raw["op"] == nil || !onlyFields(raw, "op", "event", "cursor") {
		return Request{}, configInvalid
	}
	var request Request
	if json.Unmarshal(line, &request) != nil {
		return Request{}, configInvalid
	}
	switch request.Op {
	case "snapshot":
		if len(raw) != 1 {
			return Request{}, configInvalid
		}
	case "publish":
		var event ProtocolEvent
		if len(raw) != 2 || raw["event"] == nil || json.Unmarshal(raw["event"], &event) != nil {
			return Request{}, configInvalid
		}
		var eventRaw map[string]json.RawMessage
		if json.Unmarshal(raw["event"], &eventRaw) != nil || !onlyFields(eventRaw, "schema_version", "epoch", "revision", "session", "pane", "source", "state", "producer_revision") || !requiredFields(eventRaw, "schema_version", "session", "pane", "source", "state") {
			return Request{}, configInvalid
		}
		request.Event = Event{SchemaVersion: event.SchemaVersion, Epoch: event.Epoch, Revision: event.Revision, Identity: Identity{Session: event.Session, Pane: event.Pane, Source: event.Source}, State: event.State, ProducerRevision: event.ProducerRevision}
		if request.Event.SchemaVersion != SchemaVersion || !validProtocolIdentity(request.Event.Identity) || validState(request.Event.State) == "" {
			return Request{}, configInvalid
		}
	case "subscribe":
		var cursor map[string]json.RawMessage
		if len(raw) != 2 || raw["cursor"] == nil || json.Unmarshal(raw["cursor"], &cursor) != nil || !onlyFields(cursor, "epoch", "revision") || !requiredFields(cursor, "epoch", "revision") || !validProtocolID(request.Cursor.Epoch) {
			return Request{}, configInvalid
		}
	default:
		return Request{}, configInvalid
	}
	return request, nil
}

func EncodeResponse(value Response) ([]byte, error) {
	if value.Type != "ack" && value.Type != "snapshot" && value.Type != "event" && value.Type != "gap" && value.Type != "error" {
		return nil, configInvalid
	}
	encoded, err := json.Marshal(value)
	if err != nil || len(encoded) >= 1<<20 {
		return nil, configInvalid
	}
	return append(encoded, '\n'), nil
}

func DecodeSnapshotStrict(encoded []byte) (Snapshot, error) {
	if strictJSON(encoded) != nil {
		return Snapshot{}, configInvalid
	}
	var raw map[string]json.RawMessage
	if json.Unmarshal(encoded, &raw) != nil || !requiredFields(raw, "schema_version", "epoch", "revision", "panes", "sessions") || !onlyFields(raw, "schema_version", "epoch", "revision", "panes", "sessions") {
		return Snapshot{}, configInvalid
	}
	var snapshot Snapshot
	if json.Unmarshal(raw["schema_version"], &snapshot.SchemaVersion) != nil || snapshot.SchemaVersion != SchemaVersion || json.Unmarshal(raw["epoch"], &snapshot.Epoch) != nil || snapshot.Epoch == "" || json.Unmarshal(raw["revision"], &snapshot.Revision) != nil {
		return Snapshot{}, configInvalid
	}
	var panes []json.RawMessage
	var sessions []json.RawMessage
	if !jsonArray(raw["panes"], &panes) || !jsonArray(raw["sessions"], &sessions) {
		return Snapshot{}, configInvalid
	}
	paneIdentities := map[paneIdentity]struct{}{}
	aggregated := map[string]string{}
	for _, encodedPane := range panes {
		var fields map[string]json.RawMessage
		if json.Unmarshal(encodedPane, &fields) != nil || !requiredFields(fields, "session", "pane", "state") || !onlyFields(fields, "session", "pane", "state", "token") {
			return Snapshot{}, configInvalid
		}
		var pane Pane
		if json.Unmarshal(fields["session"], &pane.Session) != nil || json.Unmarshal(fields["pane"], &pane.Pane) != nil || json.Unmarshal(fields["state"], &pane.State) != nil || !validProtocolID(pane.Session) || !validProtocolID(pane.Pane) || validState(pane.State) == "" {
			return Snapshot{}, configInvalid
		}
		if fields["token"] != nil && json.Unmarshal(fields["token"], &pane.Token) != nil {
			return Snapshot{}, configInvalid
		}
		identity := paneIdentity{session: pane.Session, pane: pane.Pane}
		if _, duplicate := paneIdentities[identity]; duplicate {
			return Snapshot{}, configInvalid
		}
		paneIdentities[identity] = struct{}{}
		if priority(pane.State) > priority(aggregated[pane.Session]) {
			aggregated[pane.Session] = pane.State
		}
		snapshot.Panes = append(snapshot.Panes, pane)
	}
	seenSessions := map[string]struct{}{}
	for _, encodedSession := range sessions {
		var fields map[string]json.RawMessage
		if json.Unmarshal(encodedSession, &fields) != nil || !requiredFields(fields, "name", "state") || !onlyFields(fields, "name", "state", "token") {
			return Snapshot{}, configInvalid
		}
		var session Session
		if json.Unmarshal(fields["name"], &session.Name) != nil || json.Unmarshal(fields["state"], &session.State) != nil || !validProtocolID(session.Name) || validState(session.State) == "" || aggregated[session.Name] != session.State {
			return Snapshot{}, configInvalid
		}
		if fields["token"] != nil && json.Unmarshal(fields["token"], &session.Token) != nil {
			return Snapshot{}, configInvalid
		}
		if _, duplicate := seenSessions[session.Name]; duplicate {
			return Snapshot{}, configInvalid
		}
		seenSessions[session.Name] = struct{}{}
		snapshot.Sessions = append(snapshot.Sessions, session)
	}
	if len(seenSessions) != len(aggregated) {
		return Snapshot{}, configInvalid
	}
	return snapshot, nil
}

func jsonArray(encoded json.RawMessage, target *[]json.RawMessage) bool {
	trimmed := bytes.TrimSpace(encoded)
	return len(trimmed) > 0 && trimmed[0] == '[' && json.Unmarshal(trimmed, target) == nil
}

func ListenSocket(root, endpoint string) (*net.UnixListener, func(), error) {
	if !filepath.IsAbs(root) || !filepath.IsAbs(endpoint) {
		return nil, nil, configInvalid
	}
	relative, err := filepath.Rel(root, endpoint)
	if err != nil || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return nil, nil, configInvalid
	}
	if err := secureSocketAncestors(root, filepath.Dir(relative)); err != nil {
		return nil, nil, configInvalid
	}
	if _, err := os.Lstat(endpoint); err == nil {
		if err := removeStaleSocket(endpoint); err != nil {
			return nil, nil, configInvalid
		}
	} else if !os.IsNotExist(err) {
		return nil, nil, configInvalid
	}
	listener, err := net.ListenUnix("unix", &net.UnixAddr{Name: endpoint, Net: "unix"})
	if err != nil {
		return nil, nil, err
	}
	listener.SetUnlinkOnClose(false)
	created, err := os.Lstat(endpoint)
	if err != nil || created.Mode()&os.ModeSocket == 0 || !ownedByCurrentUser(created) {
		listener.Close()
		return nil, nil, configInvalid
	}
	cleanup := func() {
		_ = listener.Close()
		if current, err := os.Lstat(endpoint); err == nil && sameInode(created, current) {
			_ = os.Remove(endpoint)
		}
	}
	if err := os.Chmod(endpoint, 0600); err != nil {
		cleanup()
		return nil, nil, err
	}
	created, err = os.Lstat(endpoint)
	if err != nil || created.Mode().Perm() != 0600 || !ownedByCurrentUser(created) {
		cleanup()
		return nil, nil, configInvalid
	}
	return listener, cleanup, nil
}

func removeStaleSocket(endpoint string) error {
	created, err := os.Lstat(endpoint)
	if err != nil || created.Mode()&os.ModeSocket == 0 || created.Mode().Perm() != 0600 || !ownedByCurrentUser(created) {
		return configInvalid
	}
	connection, dialErr := net.DialTimeout("unix", endpoint, 100*time.Millisecond)
	if dialErr == nil {
		_ = connection.Close()
		return configInvalid
	}
	if !errors.Is(dialErr, syscall.ECONNREFUSED) && !errors.Is(dialErr, syscall.ENOENT) {
		return configInvalid
	}
	current, err := os.Lstat(endpoint)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil || !sameInode(created, current) {
		return configInvalid
	}
	return os.Remove(endpoint)
}

func secureSocketAncestors(root, relative string) error {
	path := root
	for _, component := range append([]string{"."}, strings.Split(relative, string(filepath.Separator))...) {
		if component != "." {
			path = filepath.Join(path, component)
		}
		info, err := os.Lstat(path)
		if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 || info.Mode().Perm() != 0700 || !ownedByCurrentUser(info) {
			return configInvalid
		}
	}
	return nil
}
func ServeSocket(listener *net.UnixListener, owner *Owner) {
	for {
		connection, err := listener.AcceptUnix()
		if err != nil {
			return
		}
		go serveConnection(connection, owner)
	}
}
func serveConnection(connection *net.UnixConn, owner *Owner) {
	defer connection.Close()
	_ = connection.SetReadDeadline(time.Now().Add(time.Second))
	frame, err := bufio.NewReader(io.LimitReader(connection, 64<<10+1)).ReadBytes('\n')
	if err != nil || len(frame) > 64<<10 {
		return
	}
	request, err := DecodeRequest(frame)
	if err != nil {
		writeResponse(connection, Response{Type: "error", Code: "invalid"})
		return
	}
	switch request.Op {
	case "snapshot":
		writeResponse(connection, Response{Type: "snapshot", Snapshot: owner.Snapshot()})
	case "publish":
		snapshot, err := owner.Publish(request.Event)
		if err != nil {
			writeResponse(connection, Response{Type: "error", Code: "invalid"})
			return
		}
		writeResponse(connection, Response{Type: "ack", Snapshot: snapshot})
	case "subscribe":
		replay, stream, err := owner.Subscribe(request.Cursor)
		if err != nil {
			writeResponse(connection, Response{Type: "gap"})
			return
		}
		for _, event := range replay {
			if !writeResponse(connection, Response{Type: "event", Event: protocolEvent(event)}) {
				return
			}
		}
		for event := range stream {
			if !writeResponse(connection, Response{Type: "event", Event: protocolEvent(event)}) {
				return
			}
		}
	}
}

func writeResponse(connection *net.UnixConn, response Response) bool {
	encoded, err := EncodeResponse(response)
	if err != nil {
		return false
	}
	_ = connection.SetWriteDeadline(time.Now().Add(time.Second))
	_, err = connection.Write(encoded)
	return err == nil
}

func protocolEvent(event Event) *ProtocolEvent {
	return &ProtocolEvent{SchemaVersion: event.SchemaVersion, Epoch: event.Epoch, Revision: event.Revision, Session: event.Identity.Session, Pane: event.Identity.Pane, Source: event.Identity.Source, State: event.State, ProducerRevision: event.ProducerRevision}
}
func ownedByCurrentUser(info os.FileInfo) bool {
	stat, ok := info.Sys().(*syscall.Stat_t)
	return ok && int(stat.Uid) == os.Getuid()
}

func sameInode(first, second os.FileInfo) bool {
	a, aOK := first.Sys().(*syscall.Stat_t)
	b, bOK := second.Sys().(*syscall.Stat_t)
	return aOK && bOK && a.Dev == b.Dev && a.Ino == b.Ino
}

func strictJSON(line []byte) error {
	decoder := json.NewDecoder(bytes.NewReader(line))
	if err := validateJSONValue(decoder); err != nil {
		return err
	}
	_, err := decoder.Token()
	if err != io.EOF {
		return configInvalid
	}
	return nil
}

func validateJSONValue(decoder *json.Decoder) error {
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	delimiter, ok := token.(json.Delim)
	if !ok {
		return nil
	}
	if delimiter == '{' {
		seen := map[string]bool{}
		for decoder.More() {
			key, err := decoder.Token()
			if err != nil || seen[key.(string)] {
				return configInvalid
			}
			seen[key.(string)] = true
			if err := validateJSONValue(decoder); err != nil {
				return err
			}
		}
	} else if delimiter == '[' {
		for decoder.More() {
			if err := validateJSONValue(decoder); err != nil {
				return err
			}
		}
	}
	_, err = decoder.Token()
	return err
}

func onlyFields(values map[string]json.RawMessage, fields ...string) bool {
	allowed := map[string]bool{}
	for _, field := range fields {
		allowed[field] = true
	}
	for field := range values {
		if !allowed[field] {
			return false
		}
	}
	return true
}

func requiredFields(values map[string]json.RawMessage, fields ...string) bool {
	for _, field := range fields {
		if values[field] == nil {
			return false
		}
	}
	return true
}

func validProtocolIdentity(identity Identity) bool {
	return validProtocolID(identity.Session) && validProtocolID(identity.Pane) && validProtocolID(identity.Source)
}

func validProtocolID(value string) bool {
	if len(value) == 0 || len(value) > 64 {
		return false
	}
	for _, character := range value {
		if character >= 'a' && character <= 'z' || character >= 'A' && character <= 'Z' || character >= '0' && character <= '9' || strings.ContainsRune("._-", character) {
			continue
		}
		return false
	}
	return true
}

func cloneSnapshot(snapshot Snapshot) Snapshot {
	clone := snapshot
	clone.Panes = append([]Pane(nil), snapshot.Panes...)
	clone.Sessions = append([]Session(nil), snapshot.Sessions...)
	return clone
}
