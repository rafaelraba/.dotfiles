package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	runtime "github.com/rafaelraba/dotfiles/agent-status-runtime"
)

type options struct {
	root             string
	now              int64
	schemaVersion    int
	activeTTL        int64
	terminalTTL      int64
	session          string
	pane             string
	source           string
	state            string
	producerRevision uint64
}

func main() {
	if len(os.Args) < 2 {
		os.Exit(runtime.ExitInvalid)
	}
	options, err := parseOptions(os.Args[2:])
	if err != nil {
		os.Exit(runtime.ExitInvalid)
	}
	switch os.Args[1] {
	case "serve":
		os.Exit(serve(options, os.Stderr))
	case "snapshot":
		os.Exit(snapshot(options, os.Stdout, os.Stderr))
	case "socket-snapshot":
		os.Exit(socketSnapshot(os.Stdout))
	case "socket-sessions":
		os.Exit(socketSessions(os.Stdin, os.Stdout))
	case "publish":
		os.Exit(publish(options, os.Stdout))
	case "validate":
		os.Exit(validate(options, os.Stderr))
	case "doctor":
		os.Exit(doctor(options, os.Stdout, os.Stderr))
	default:
		os.Exit(runtime.ExitInvalid)
	}
}

func serve(o options, stderr io.Writer) int {
	started := time.Now()
	explicitNow := o.now != 0
	if o.now == 0 {
		o.now = started.Unix()
	}
	state, diagnostics, exit := runtime.ImportV1Live(o.root, o.config(), o.now)
	for _, diagnostic := range diagnostics {
		fmt.Fprintln(stderr, diagnostic)
	}
	if exit == runtime.ExitInvalid {
		return exit
	}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, os.Interrupt)
	defer signal.Stop(signals)
	base, err := socketBase()
	if err != nil {
		return runtime.ExitInvalid
	}
	listener, cleanup, err := runtime.ListenSocket(base, filepath.Join(base, "agent-status.sock"))
	if err != nil {
		return runtime.ExitInvalid
	}
	defer cleanup()
	clock := func() int64 { return time.Now().Unix() }
	if explicitNow {
		clock = func() int64 { return o.now + int64(time.Since(started)/time.Second) }
	}
	owner := runtime.NewLiveOwner(state, o.config(), clock)
	defer owner.Close()
	stopped := make(chan struct{})
	go func() {
		runtime.ServeSocket(listener, owner)
		close(stopped)
	}()
	select {
	case <-signals:
		return runtime.ExitComplete
	case <-stopped:
		return runtime.ExitInvalid
	}
}

func socketBase() (string, error) {
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		runtimeDir = os.Getenv("XDG_CACHE_HOME")
	}
	if runtimeDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		runtimeDir = filepath.Join(home, ".cache")
	}
	base := filepath.Join(runtimeDir, "agent-status")
	info, err := os.Lstat(base)
	if os.IsNotExist(err) {
		if err := os.Mkdir(base, 0700); err != nil {
			return "", err
		}
		info, err = os.Lstat(base)
	}
	if err != nil {
		return "", err
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 || info.Mode().Perm() != 0700 || !ownedByCurrentUser(info) {
		return "", fmt.Errorf("unsafe socket directory")
	}
	return base, nil
}

func socketEndpoint() (string, error) {
	runtimeDir := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDir == "" {
		runtimeDir = os.Getenv("XDG_CACHE_HOME")
	}
	if runtimeDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		runtimeDir = filepath.Join(home, ".cache")
	}
	return filepath.Join(runtimeDir, "agent-status", "agent-status.sock"), nil
}

func socketRequest(request any, stdout io.Writer) int {
	response, _, exit := socketExchange(request)
	if exit != runtime.ExitComplete {
		return exit
	}
	_, _ = stdout.Write(response)
	return runtime.ExitComplete
}

func socketExchange(request any) ([]byte, runtime.Snapshot, int) {
	endpoint, err := safeSocketEndpoint()
	if err != nil {
		return nil, runtime.Snapshot{}, runtime.ExitInvalid
	}
	connection, err := net.DialTimeout("unix", endpoint, time.Second)
	if err != nil {
		return nil, runtime.Snapshot{}, runtime.ExitInvalid
	}
	defer connection.Close()
	frame, err := json.Marshal(request)
	if err != nil {
		return nil, runtime.Snapshot{}, runtime.ExitInvalid
	}
	_ = connection.SetDeadline(time.Now().Add(time.Second))
	if _, err := connection.Write(append(frame, '\n')); err != nil {
		return nil, runtime.Snapshot{}, runtime.ExitInvalid
	}
	response, err := io.ReadAll(io.LimitReader(connection, 1<<20))
	if err != nil || len(response) == 0 || len(response) >= 1<<20 || !strings.HasSuffix(string(response), "\n") {
		return nil, runtime.Snapshot{}, runtime.ExitInvalid
	}
	expected := "snapshot"
	if _, ok := request.(struct {
		Op    string                `json:"op"`
		Event runtime.ProtocolEvent `json:"event"`
	}); ok {
		expected = "ack"
	}
	snapshot, valid := strictSocketResponse(response, expected)
	if !valid {
		return nil, runtime.Snapshot{}, runtime.ExitInvalid
	}
	return response, snapshot, runtime.ExitComplete
}

func safeSocketEndpoint() (string, error) {
	endpoint, err := socketEndpoint()
	if err != nil {
		return "", err
	}
	directory, err := os.Lstat(filepath.Dir(endpoint))
	if err != nil || !directory.IsDir() || directory.Mode()&os.ModeSymlink != 0 || directory.Mode().Perm() != 0700 || !ownedByCurrentUser(directory) {
		return "", fmt.Errorf("unsafe socket directory")
	}
	entry, err := os.Lstat(endpoint)
	if os.IsNotExist(err) {
		return endpoint, nil
	}
	if err != nil || entry.Mode()&os.ModeSocket == 0 || entry.Mode().Perm() != 0600 || !ownedByCurrentUser(entry) {
		return "", fmt.Errorf("unsafe socket endpoint")
	}
	return endpoint, nil
}

func ownedByCurrentUser(info os.FileInfo) bool {
	stat, ok := info.Sys().(*syscall.Stat_t)
	return ok && int(stat.Uid) == os.Getuid()
}

func strictSocketResponse(response []byte, expected string) (runtime.Snapshot, bool) {
	if bytes.Count(response, []byte("\n")) != 1 {
		return runtime.Snapshot{}, false
	}
	decoder := json.NewDecoder(bytes.NewReader(response))
	token, err := decoder.Token()
	if err != nil || token != json.Delim('{') {
		return runtime.Snapshot{}, false
	}
	fields := map[string]json.RawMessage{}
	for decoder.More() {
		key, err := decoder.Token()
		name, ok := key.(string)
		if err != nil || !ok || fields[name] != nil {
			return runtime.Snapshot{}, false
		}
		var value json.RawMessage
		if err := decoder.Decode(&value); err != nil {
			return runtime.Snapshot{}, false
		}
		fields[name] = value
	}
	if token, err = decoder.Token(); err != nil || token != json.Delim('}') || decoder.Decode(&struct{}{}) != io.EOF || len(fields) != 2 {
		return runtime.Snapshot{}, false
	}
	var responseType string
	snapshot, snapshotErr := runtime.DecodeSnapshotStrict(fields["snapshot"])
	return snapshot, json.Unmarshal(fields["type"], &responseType) == nil && responseType == expected && fields["snapshot"] != nil && snapshotErr == nil
}

func socketSnapshot(stdout io.Writer) int {
	return socketRequest(struct {
		Op string `json:"op"`
	}{Op: "snapshot"}, stdout)
}

func socketSessions(stdin io.Reader, stdout io.Writer) int {
	_, snapshot, exit := socketExchange(struct {
		Op string `json:"op"`
	}{Op: "snapshot"})
	if exit != runtime.ExitComplete {
		return exit
	}
	inventory, err := io.ReadAll(io.LimitReader(stdin, 1<<20+1))
	if err != nil || len(inventory) > 1<<20 || !utf8.Valid(inventory) || bytes.IndexByte(inventory, 0) >= 0 {
		return runtime.ExitInvalid
	}
	type paneKey struct{ session, pane string }
	live := map[paneKey]struct{}{}
	for _, row := range strings.Split(strings.TrimSuffix(string(inventory), "\n"), "\n") {
		fields := strings.Split(row, "\t")
		if len(fields) >= 4 {
			live[paneKey{session: fields[0], pane: sanitizeProtocolID(fields[3])}] = struct{}{}
		}
	}
	states := map[string]string{}
	for _, pane := range snapshot.Panes {
		if _, found := live[paneKey{session: pane.Session, pane: pane.Pane}]; found && statePriority(pane.State) > statePriority(states[pane.Session]) {
			states[pane.Session] = pane.State
		}
	}
	names := make([]string, 0, len(states))
	for name := range states {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		fmt.Fprintf(stdout, "%s\t%s\n", name, states[name])
	}
	return runtime.ExitComplete
}

func sanitizeProtocolID(value string) string {
	var result strings.Builder
	for _, character := range value {
		if character >= 'a' && character <= 'z' || character >= 'A' && character <= 'Z' || character >= '0' && character <= '9' || strings.ContainsRune("._-", character) {
			result.WriteRune(character)
		} else {
			result.WriteByte('_')
		}
	}
	return result.String()
}

func statePriority(state string) int {
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
	default:
		return 0
	}
}

func publish(o options, stdout io.Writer) int {
	event := runtime.ProtocolEvent{SchemaVersion: runtime.SchemaVersion, Session: o.session, Pane: o.pane, Source: o.source, State: o.state, ProducerRevision: o.producerRevision}
	return socketRequest(struct {
		Op    string                `json:"op"`
		Event runtime.ProtocolEvent `json:"event"`
	}{Op: "publish", Event: event}, stdout)
}

func parseOptions(args []string) (options, error) {
	result := options{schemaVersion: runtime.SchemaVersion, activeTTL: 300, terminalTTL: 3600}
	flags := flag.NewFlagSet("agent-status-runtime", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	flags.StringVar(&result.root, "root", "", "v1 state root")
	flags.Int64Var(&result.now, "now", 0, "unix timestamp")
	flags.IntVar(&result.schemaVersion, "schema-version", runtime.SchemaVersion, "schema version")
	flags.Int64Var(&result.activeTTL, "active-ttl", 300, "active TTL")
	flags.Int64Var(&result.terminalTTL, "terminal-ttl", 3600, "terminal TTL")
	flags.StringVar(&result.session, "session", "", "session")
	flags.StringVar(&result.pane, "pane", "", "pane")
	flags.StringVar(&result.source, "source", "", "source")
	flags.StringVar(&result.state, "state", "", "state")
	flags.Uint64Var(&result.producerRevision, "producer-revision", 0, "producer revision")
	if err := flags.Parse(args); err != nil || result.root == "" {
		return options{}, fmt.Errorf("invalid options")
	}
	return result, nil
}

func (o options) config() runtime.Config {
	return runtime.Config{SchemaVersion: o.schemaVersion, ActiveTTL: o.activeTTL, TerminalTTL: o.terminalTTL}
}

func importState(o options, stderr io.Writer) (runtime.Snapshot, int) {
	snapshot, diagnostics, exit := runtime.ImportV1(o.root, o.config(), o.now)
	for _, diagnostic := range diagnostics {
		fmt.Fprintln(stderr, diagnostic)
	}
	return snapshot, exit
}

func snapshot(o options, stdout, stderr io.Writer) int {
	state, exit := importState(o, stderr)
	if exit == runtime.ExitInvalid {
		return exit
	}
	encoded, err := runtime.MarshalSnapshot(state)
	if err != nil {
		return runtime.ExitInvalid
	}
	fmt.Fprint(stdout, encoded)
	return exit
}

func validate(o options, stderr io.Writer) int {
	_, exit := importState(o, stderr)
	return exit
}

func doctor(o options, stdout, stderr io.Writer) int {
	configOK := runtime.ValidateConfig(o.config()) == nil
	pathsOK := statePathsExist(o.root)
	runtimeEnabled := os.Getenv("AGENT_STATUS_RUNTIME_ENABLED") == "1"
	runtimeOK := !runtimeEnabled || safeSocketDirectory()
	recordsOK := false
	if configOK && pathsOK {
		_, exit := importState(o, stderr)
		recordsOK = exit == runtime.ExitComplete
	}
	check(stdout, "protocol", "required", configOK)
	check(stdout, "configuration", "required", configOK)
	if runtimeEnabled {
		check(stdout, "runtime", "required", runtimeOK)
	} else {
		fmt.Fprintln(stdout, "runtime\toptional\tunavailable")
	}
	check(stdout, "paths", "required", pathsOK)
	check(stdout, "records", "required", recordsOK)
	fmt.Fprintln(stdout, "adapter\toptional\tunavailable")
	if configOK && pathsOK && recordsOK && runtimeOK {
		return runtime.ExitComplete
	}
	return runtime.ExitInvalid
}

func safeSocketDirectory() bool {
	endpoint, err := socketEndpoint()
	if err != nil {
		return false
	}
	info, err := os.Lstat(filepath.Dir(endpoint))
	return err == nil && info.IsDir() && info.Mode()&os.ModeSymlink == 0 && info.Mode().Perm() == 0700
}

func statePathsExist(root string) bool {
	for _, directory := range []string{"panes", "sessions"} {
		info, err := os.Stat(filepath.Join(root, directory))
		if err != nil || !info.IsDir() {
			return false
		}
	}
	return true
}

func check(writer io.Writer, name, classification string, ok bool) {
	status := "fail"
	if ok {
		status = "ok"
	}
	fmt.Fprintf(writer, "%s\t%s\t%s\n", name, classification, status)
}
