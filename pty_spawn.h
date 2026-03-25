#ifndef pty_spawn_h
#define pty_spawn_h

#include <sys/types.h>

/// Forks a child process attached to the given PTY master fd and execs the shell.
/// Returns the child PID on success, -1 on failure.
pid_t pty_spawn_shell(int master_fd, const char *shell);

#endif /* pty_spawn_h */
