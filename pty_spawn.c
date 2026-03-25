#include "pty_spawn.h"
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <termios.h>

pid_t pty_spawn_shell(int master_fd, const char *shell) {
    // Get the slave PTY device name from the already-opened master
    char *slave_name = ptsname(master_fd);
    if (!slave_name) return -1;

    int slave_fd = open(slave_name, O_RDWR);
    if (slave_fd < 0) return -1;

    // Disable echo at the termios level so the app handles its own input display
    struct termios t;
    if (tcgetattr(slave_fd, &t) == 0) {
        t.c_lflag &= ~(ECHO | ECHOE | ECHOK | ECHONL);
        tcsetattr(slave_fd, TCSANOW, &t);
    }

    // Set a reasonable window size on the slave
    struct winsize ws = { .ws_row = 24, .ws_col = 80 };
    ioctl(slave_fd, TIOCSWINSZ, &ws);

    pid_t pid = fork();

    if (pid == 0) {
        // Child: become a new session leader and attach the PTY as controlling terminal
        setsid();
        ioctl(slave_fd, TIOCSCTTY, 0);

        dup2(slave_fd, STDIN_FILENO);
        dup2(slave_fd, STDOUT_FILENO);
        dup2(slave_fd, STDERR_FILENO);

        close(master_fd);
        close(slave_fd);

        // Change to home directory before starting the shell
        const char *home = getenv("HOME");
        if (home) chdir(home);

        setenv("TERM", "xterm-256color", 1);
        setenv("TERM_PROGRAM", "LamaS", 1);
        execl(shell, shell, "--login", "-i", (char *)NULL);
        _exit(1);
    }

    // Parent: close slave end, return child PID
    close(slave_fd);
    return pid;
}
