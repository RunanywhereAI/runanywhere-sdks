#include "util/term.h"

#include <sys/ioctl.h>
#include <unistd.h>

#include <cstdlib>

namespace rcli::term {

bool stdout_is_tty() {
    return isatty(STDOUT_FILENO) == 1;
}

bool stderr_is_tty() {
    return isatty(STDERR_FILENO) == 1;
}

bool stdin_is_tty() {
    return isatty(STDIN_FILENO) == 1;
}

int terminal_width() {
    winsize ws{};
    if (ioctl(STDERR_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
        return ws.ws_col;
    }
    return 80;
}

bool color_enabled() {
    return stderr_is_tty() && std::getenv("NO_COLOR") == nullptr;
}

}  // namespace rcli::term
