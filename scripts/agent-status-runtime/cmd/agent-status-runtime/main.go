package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	runtime "github.com/rafaelraba/dotfiles/agent-status-runtime"
)

type options struct {
	root          string
	now           int64
	schemaVersion int
	activeTTL     int64
	terminalTTL   int64
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
	case "validate":
		os.Exit(validate(options, os.Stderr))
	case "doctor":
		os.Exit(doctor(options, os.Stdout, os.Stderr))
	default:
		os.Exit(runtime.ExitInvalid)
	}
}

func serve(o options, stderr io.Writer) int {
	state, exit := importState(o, stderr)
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
	owner := runtime.NewOwner(state)
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

func ownedByCurrentUser(info os.FileInfo) bool {
	stat, ok := info.Sys().(*syscall.Stat_t)
	return ok && int(stat.Uid) == os.Getuid()
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
	recordsOK := false
	if configOK && pathsOK {
		_, exit := importState(o, stderr)
		recordsOK = exit == runtime.ExitComplete
	}
	check(stdout, "protocol", "required", configOK)
	check(stdout, "configuration", "required", configOK)
	check(stdout, "runtime", "required", true)
	check(stdout, "paths", "required", pathsOK)
	check(stdout, "records", "required", recordsOK)
	fmt.Fprintln(stdout, "adapter\toptional\tunavailable")
	if configOK && pathsOK && recordsOK {
		return runtime.ExitComplete
	}
	return runtime.ExitInvalid
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
