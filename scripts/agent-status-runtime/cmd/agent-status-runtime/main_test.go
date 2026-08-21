package main

import (
	"bufio"
	"context"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

func TestServeCreatesSocketAndStopsOnSignal(t *testing.T) {
	for _, signal := range []os.Signal{syscall.SIGTERM, syscall.SIGINT} {
		t.Run(signal.String(), func(t *testing.T) {
			binary := buildBinary(t)
			runtimeDir := shortRuntimeDir(t)
			root := stateRoot(t)
			command := exec.Command(binary, "serve", "--root", root)
			command.Env = append(os.Environ(), "XDG_RUNTIME_DIR="+runtimeDir)
			if err := command.Start(); err != nil {
				t.Fatal(err)
			}
			endpoint := filepath.Join(runtimeDir, "agent-status", "agent-status.sock")
			t.Cleanup(func() {
				if command.ProcessState != nil {
					return
				}
				_ = command.Process.Kill()
				waitForExit(t, command, false)
			})
			waitForSocket(t, endpoint)
			if err := command.Process.Signal(signal); err != nil {
				t.Fatal(err)
			}
			waitForExit(t, command, true)
			if _, err := os.Lstat(endpoint); !os.IsNotExist(err) {
				t.Fatalf("socket remains after %s: %v", signal, err)
			}
		})
	}
}

func TestInvalidCommandsExitWithoutSocket(t *testing.T) {
	for _, args := range [][]string{{}, {"serve"}, {"unknown", "--root", t.TempDir()}} {
		t.Run("invalid", func(t *testing.T) {
			runtimeDir := shortRuntimeDir(t)
			command := exec.Command(buildBinary(t), args...)
			command.Env = append(os.Environ(), "XDG_RUNTIME_DIR="+runtimeDir)
			if err := command.Run(); err == nil {
				t.Fatal("invalid command unexpectedly succeeded")
			}
			if _, err := os.Lstat(filepath.Join(runtimeDir, "agent-status", "agent-status.sock")); !os.IsNotExist(err) {
				t.Fatalf("invalid command created socket: %v", err)
			}
		})
	}
}

func TestServeRejectsSymlinkedSocketDirectoryWithoutChangingTargetMode(t *testing.T) {
	for _, mode := range []os.FileMode{0755, 0750} {
		t.Run(mode.String(), func(t *testing.T) {
			runtimeDir := shortRuntimeDir(t)
			target := filepath.Join(t.TempDir(), "target")
			if err := os.Mkdir(target, mode); err != nil {
				t.Fatal(err)
			}
			if err := os.Symlink(target, filepath.Join(runtimeDir, "agent-status")); err != nil {
				t.Fatal(err)
			}
			command := exec.Command(buildBinary(t), "serve", "--root", stateRoot(t))
			command.Env = append(os.Environ(), "XDG_RUNTIME_DIR="+runtimeDir)
			if err := command.Run(); err == nil {
				t.Fatal("serve accepted a symlinked socket directory")
			}
			info, err := os.Stat(target)
			if err != nil {
				t.Fatal(err)
			}
			if info.Mode().Perm() != mode {
				t.Fatalf("symlink target mode = %o, want %o", info.Mode().Perm(), mode)
			}
		})
	}
}

func TestServeRejectsPermissiveSocketDirectoryWithoutChangingMode(t *testing.T) {
	for _, mode := range []os.FileMode{0755, 0750} {
		t.Run(mode.String(), func(t *testing.T) {
			runtimeDir := shortRuntimeDir(t)
			base := filepath.Join(runtimeDir, "agent-status")
			if err := os.Mkdir(base, mode); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			command := exec.CommandContext(ctx, buildBinary(t), "serve", "--root", stateRoot(t))
			command.Env = append(os.Environ(), "XDG_RUNTIME_DIR="+runtimeDir)
			if err := command.Run(); err == nil {
				t.Fatal("serve accepted a permissive socket directory")
			}
			if ctx.Err() != nil {
				t.Fatal("serve did not reject a permissive socket directory before timeout")
			}
			info, err := os.Lstat(base)
			if err != nil {
				t.Fatal(err)
			}
			if info.Mode().Perm() != mode {
				t.Fatalf("socket directory mode = %o, want %o", info.Mode().Perm(), mode)
			}
		})
	}
}

func TestSocketClientRejectsUnsafeEndpointBeforeDialing(t *testing.T) {
	runtimeDir := shortRuntimeDir(t)
	target := shortRuntimeDir(t)
	if err := os.Symlink(target, filepath.Join(runtimeDir, "agent-status")); err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("unix", filepath.Join(target, "agent-status.sock"))
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	accepted := make(chan struct{}, 1)
	go func() {
		connection, err := listener.Accept()
		if err == nil {
			accepted <- struct{}{}
			_ = connection.Close()
		}
	}()
	t.Setenv("XDG_RUNTIME_DIR", runtimeDir)
	if exit := socketSnapshot(io.Discard); exit != 1 {
		t.Fatalf("socket snapshot exit = %d, want invalid", exit)
	}
	select {
	case <-accepted:
		t.Fatal("client dialed a symlinked runtime endpoint")
	case <-time.After(50 * time.Millisecond):
	}
}

func TestSocketClientRequiresOperationSpecificStrictResponse(t *testing.T) {
	validSnapshot := `{"schema_version":2,"epoch":"epoch","revision":0,"panes":[],"sessions":[]}`
	for _, test := range []struct {
		name, operation, response string
		want                      int
	}{
		{"snapshot", "snapshot", `{"type":"snapshot","snapshot":` + validSnapshot + "}\n", 0},
		{"snapshot-rejects-ack", "snapshot", `{"type":"ack","snapshot":` + validSnapshot + "}\n", 1},
		{"publish", "publish", `{"type":"ack","snapshot":` + validSnapshot + "}\n", 0},
		{"publish-rejects-snapshot", "publish", `{"type":"snapshot","snapshot":` + validSnapshot + "}\n", 1},
		{"unknown-field", "snapshot", `{"type":"snapshot","snapshot":` + validSnapshot + `,"extra":true}` + "\n", 1},
		{"duplicate-field", "snapshot", `{"type":"snapshot","type":"snapshot","snapshot":` + validSnapshot + "}\n", 1},
		{"malformed", "snapshot", "not-json\n", 1},
	} {
		t.Run(test.name, func(t *testing.T) {
			runtimeDir := shortRuntimeDir(t)
			endpoint := filepath.Join(runtimeDir, "agent-status", "agent-status.sock")
			if err := os.Mkdir(filepath.Dir(endpoint), 0700); err != nil {
				t.Fatal(err)
			}
			listener, err := net.Listen("unix", endpoint)
			if err != nil {
				t.Fatal(err)
			}
			if err := os.Chmod(endpoint, 0600); err != nil {
				t.Fatal(err)
			}
			defer listener.Close()
			go func() {
				connection, err := listener.Accept()
				if err == nil {
					_, _ = bufio.NewReader(connection).ReadBytes('\n')
					_, _ = connection.Write([]byte(test.response))
					_ = connection.Close()
				}
			}()
			t.Setenv("XDG_RUNTIME_DIR", runtimeDir)
			var exit int
			if test.operation == "publish" {
				exit = publish(options{session: "session", pane: "pane", source: "source", state: "idle"}, io.Discard)
			} else {
				exit = socketSnapshot(io.Discard)
			}
			if exit != test.want {
				t.Fatalf("%s exit = %d, want %d", test.operation, exit, test.want)
			}
		})
	}
}

func buildBinary(t *testing.T) string {
	t.Helper()
	binary := filepath.Join(t.TempDir(), "agent-status-runtime")
	command := exec.Command("go", "build", "-o", binary, ".")
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("build command: %v\n%s", err, output)
	}
	return binary
}

func stateRoot(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	for _, directory := range []string{"panes", "sessions"} {
		if err := os.Mkdir(filepath.Join(root, directory), 0700); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func shortRuntimeDir(t *testing.T) string {
	t.Helper()
	directory, err := os.MkdirTemp("/tmp", "as-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	return directory
}

func waitForSocket(t *testing.T, endpoint string) {
	t.Helper()
	deadline := time.After(time.Second)
	ticker := time.NewTicker(5 * time.Millisecond)
	defer ticker.Stop()
	for {
		connection, err := net.DialTimeout("unix", endpoint, 20*time.Millisecond)
		if err == nil {
			_ = connection.Close()
			return
		}
		select {
		case <-deadline:
			t.Fatalf("socket never accepted connections: %v", err)
		case <-ticker.C:
		}
	}
}

func waitForExit(t *testing.T, command *exec.Cmd, requireSuccess bool) {
	t.Helper()
	done := make(chan error, 1)
	go func() { done <- command.Wait() }()
	select {
	case err := <-done:
		if err != nil && requireSuccess {
			t.Fatalf("serve exit: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("serve did not stop after signal")
	}
}
