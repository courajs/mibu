const builtin = @import("builtin");
const std = @import("std");
const os = std.os;
const io = std.io;

const cursor = @import("cursor.zig");

const winsize = std.os.system.winsize;

pub const ReadKind = enum {
    blocking,
    nonblocking,
};

pub const TermSize = struct {
    width: u16,
    height: u16,
};

/// A raw terminal representation, you can enter terminal raw mode
/// using this struct. Raw mode is essential to create a TUI.
pub const RawTerm = struct {
    orig_termios: os.termios,

    /// The OS-specific file descriptor or file handle.
    handle: os.system.fd_t,

    // in: io.Reader,
    // out: io.Writer,

    const Self = @This();

    /// Enters to Raw Mode, don't forget to run `disableRawMode`
    /// at the end, to return to the previous terminal state.
    pub fn enableRawMode(handle: os.system.fd_t, blocking: ReadKind) !Self {
        var original_termios = try os.tcgetattr(handle);

        var termios = original_termios;

        // https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html
        // All of this are bitflags, so we do NOT and then AND to disable

        // ICRNL (iflag) : fix CTRL-M (carriage returns)
        // IXON (iflag)  : disable Ctrl-S and Ctrl-Q

        // OPOST (oflag) : turn off all output processing

        // ECHO (lflag)  : disable prints every key to terminal
        // ICANON (lflag): disable to reads byte per byte instead of line (or when user press enter)
        // IEXTEN (lflag): disable Ctrl-V
        // ISIG (lflag)  : disable Ctrl-C and Ctrl-Z

        // Miscellaneous flags (most modern terminal already have them disabled)
        // BRKINT, INPCK, ISTRIP and CS8

        termios.iflag &= ~(os.system.BRKINT | os.system.ICRNL | os.system.INPCK | os.system.ISTRIP | os.system.IXON);
        termios.oflag &= ~(os.system.OPOST);
        termios.cflag |= (os.system.CS8);
        termios.lflag &= ~(os.system.ECHO | os.system.ICANON | os.system.IEXTEN | os.system.ISIG);

        // Read will wait until reads one byte or zero
        // depending of mode
        switch (blocking) {
            .blocking => termios.cc[os.system.V.MIN] = 1,
            .nonblocking => termios.cc[os.system.V.MIN] = 0,
        }
        termios.cc[os.system.V.TIME] = 1;

        // apply changes
        try os.tcsetattr(handle, .FLUSH, termios);

        return Self{
            .orig_termios = original_termios,
            .handle = handle,
        };
    }

    pub fn disableRawMode(self: *Self) !void {
        try os.tcsetattr(self.handle, .FLUSH, self.orig_termios);
    }
};

// Doesn't work on all platforms, so you have `getSizeAsEvent`
pub fn getSize() !TermSize {
    return getSizeFd(0);
}
pub fn getSizeFd(fd: std.os.fd_t) !TermSize {
    var ws: winsize = undefined;

    const ioctl = switch (builtin.os.tag) {
        .linux => std.os.linux.ioctl,
        else => std.c.ioctl,
    };

    // https://github.com/ziglang/zig/blob/master/lib/std/os/linux/errno/generic.zig
    const err = ioctl(fd, os.system.T.IOCGWINSZ, @ptrToInt(&ws));
    if (std.os.errno(err) != .SUCCESS) {
        return error.IoctlError;
    }

    return TermSize{
        .width = ws.ws_col,
        .height = ws.ws_row,
    };
}

test "" {
    const stdin = io.getStdIn();
    _ = try getSize();

    var term = try RawTerm.enableRawMode(stdin.handle, .blocking); // stdin.handle is the same as os.STDIN_FILENO
    defer term.disableRawMode() catch {};

    var stdin_reader = stdin.reader();
    var buf: [3]u8 = undefined;
    while ((try stdin_reader.read(&buf)) != 0 and buf[0] != 'q')
        std.debug.print("read: {s}\n\r", .{buf});

    std.debug.print("bye bye\n", .{});
}
