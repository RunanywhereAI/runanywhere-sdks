#include "util/term.h"

#include <cstdio>   // stdout/stderr/stdin, _fileno (Windows TTY checks below)
#include <cstdlib>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <io.h>
#include <windows.h>
#else
#include <sys/ioctl.h>
#include <unistd.h>
#endif

namespace rcli::term {

bool stdout_is_tty() {
#if defined(_WIN32)
    return _isatty(_fileno(stdout)) != 0;
#else
    return isatty(STDOUT_FILENO) == 1;
#endif
}

bool stderr_is_tty() {
#if defined(_WIN32)
    return _isatty(_fileno(stderr)) != 0;
#else
    return isatty(STDERR_FILENO) == 1;
#endif
}

bool stdin_is_tty() {
#if defined(_WIN32)
    return _isatty(_fileno(stdin)) != 0;
#else
    return isatty(STDIN_FILENO) == 1;
#endif
}

int terminal_width() {
#if defined(_WIN32)
    CONSOLE_SCREEN_BUFFER_INFO info{};
    if (GetConsoleScreenBufferInfo(GetStdHandle(STD_ERROR_HANDLE), &info)) {
        return static_cast<int>(info.srWindow.Right - info.srWindow.Left + 1);
    }
#else
    winsize ws{};
    if (ioctl(STDERR_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
        return ws.ws_col;
    }
#endif
    return 80;
}

bool color_enabled() {
    return stderr_is_tty() && std::getenv("NO_COLOR") == nullptr;
}

}  // namespace rcli::term
