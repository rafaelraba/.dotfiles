package runtime

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"io"
	"strings"
	"sync"
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
	epoch := make([]byte, 16)
	if _, err := rand.Read(epoch); err != nil {
		panic(err)
	}
	state := cloneSnapshot(imported)
	state.SchemaVersion = SchemaVersion
	state.Epoch = hex.EncodeToString(epoch)
	state.Revision = 0
	deriveSessions(&state)
	owner := &Owner{requests: make(chan ownerRequest), done: make(chan struct{})}
	go owner.run(state)
	return owner
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

func (o *Owner) run(state Snapshot) {
	last, journal, subscribers := map[Identity]Event{}, []Event{}, map[chan Event]struct{}{}
	for {
		select {
		case <-o.done:
			return
		case request := <-o.requests:
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
				request.response <- ownerResponse{snapshot: cloneSnapshot(state)}
				continue
			}
			event := *request.event
			if event.State == "" || event.SchemaVersion != SchemaVersion || ValidateIdentity(event.Identity) != nil || validState(event.State) == "" || (event.Epoch != "" && event.Epoch != state.Epoch) {
				request.response <- ownerResponse{snapshot: cloneSnapshot(state), err: configInvalid}
				continue
			}
			if prior, found := last[event.Identity]; found && prior.State == event.State && prior.ProducerRevision == event.ProducerRevision {
				request.response <- ownerResponse{snapshot: cloneSnapshot(state)}
				continue
			}
			event.Epoch, event.Revision = state.Epoch, state.Revision+1
			next, err := ApplyEvent(state, event)
			if err == nil {
				state, last[event.Identity] = next, event
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
			request.response <- ownerResponse{snapshot: cloneSnapshot(state), err: err}
		}
	}
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
