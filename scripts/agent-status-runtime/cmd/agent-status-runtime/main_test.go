package main

import (
	"context"
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
