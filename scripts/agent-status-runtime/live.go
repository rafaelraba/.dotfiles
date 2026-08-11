package runtime

import (
	"crypto/rand"
	"encoding/hex"
	"sync"
)

type Owner struct {
	requests chan ownerRequest
	done     chan struct{}
	close    sync.Once
}

type ownerRequest struct {
	event    *Event
	response chan ownerResponse
}

type ownerResponse struct {
	snapshot Snapshot
	err      error
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
	last := map[Identity]Event{}
	for {
		select {
		case <-o.done:
			return
		case request := <-o.requests:
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
			}
			request.response <- ownerResponse{snapshot: cloneSnapshot(state), err: err}
		}
	}
}

func cloneSnapshot(snapshot Snapshot) Snapshot {
	clone := snapshot
	clone.Panes = append([]Pane(nil), snapshot.Panes...)
	clone.Sessions = append([]Session(nil), snapshot.Sessions...)
	return clone
}
