const std = @import("std");
const io = std.io;

const RawTerm = @import("term.zig").RawTerm;
const cursor = @import("cursor.zig");

const ComptimeStringMap = std.ComptimeStringMap;

// Reference:
// https://en.wikipedia.org/wiki/ANSI_escape_code#Terminal_input_sequences
// https://gitlab.redox-os.org/redox-os/termion/-/blob/8054e082b01c3f45f89f0db96bc374f1e378deb1/src/event.rs
// https://gitlab.redox-os.org/redox-os/termion/-/blob/8054e082b01c3f45f89f0db96bc374f1e378deb1/src/input.rs

const KeyMap = ComptimeStringMap(Key, .{
    .{ "\x01", .ctrlA },
    .{ "\x02", .ctrlB },
    .{ "\x03", .ctrlC },
    .{ "\x04", .ctrlD },
    .{ "\x05", .ctrlE },
    .{ "\x06", .ctrlF },
    .{ "\x07", .ctrlG },
    .{ "\x08", .ctrlH },
    .{ "\x09", .ctrlI },
    .{ "\x0A", .ctrlJ },
    .{ "\x0B", .ctrlK },
    .{ "\x0C", .ctrlL },
    .{ "\x0D", .ctrlM },
    .{ "\x0E", .ctrlN },
    .{ "\x0F", .ctrlO },
    .{ "\x10", .ctrlP },
    .{ "\x11", .ctrlQ },
    .{ "\x12", .ctrlR },
    .{ "\x13", .ctrlS },
    .{ "\x14", .ctrlT },
    .{ "\x15", .ctrlU },
    .{ "\x16", .ctrlV },
    .{ "\x17", .ctrlW },
    .{ "\x18", .ctrlX },
    .{ "\x19", .ctrlY },
    .{ "\x1A", .ctrlZ },
    .{ "\x1B", .escape },
    .{ "\x1C", .fs },
    .{ "\x1D", .gs },
    .{ "\x1E", .rs },
    .{ "\x1F", .us },
    .{ "\x7F", .delete },
});

pub const Key = union(enum) {
    up,
    down,
    right,
    left,

    /// char is an array because it can contain utf-8 chars
    /// it will ALWAYS contains at least one char
    // TODO: Unicode compatible
    char: u21,
    fun: u8,
    alt: u8,

    // ctrl keys
    ctrlA,
    ctrlB,
    ctrlC,
    ctrlD,
    ctrlE,
    ctrlF,
    ctrlG,
    ctrlH,
    ctrlI,
    ctrlJ,
    ctrlK,
    ctrlL,
    ctrlM,
    ctrlN,
    ctrlO,
    ctrlP,
    ctrlQ,
    ctrlR,
    ctrlS,
    ctrlT,
    ctrlU,
    ctrlV,
    ctrlW,
    ctrlX,
    ctrlY,
    ctrlZ,

    escape,
    fs,
    gs,
    rs,
    us,
    delete,

    cursor: struct { x: i16, y: i16 },
};

/// Returns the next event received.
/// If raw term is `.blocking` or term is canonical it will block until read at least one event.
/// otherwise it will return `.none` if it didnt read any event
pub fn next(in: anytype) !Event {
    var buf: [20]u8 = undefined;
    const c = try in.read(&buf);
    if (c == 0) {
        return .none;
    }

    const key = switch (buf[0]) {
        '\x1b' => {
            switch (buf[1]) {
                // can be fn (1 - 4)
                'O' => {
                    return Event{ .key = Key{ .fun = (1 + buf[2] - 'P') } };
                },

                // csi
                '[' => {
                    return try parse_csi(buf[0..c]);
                },

                else => {
                    return Event{ .key = .escape };
                },
            }
        },
        // ctrl arm + specials
        '\x01'...'\x1A', '\x1C'...'\x1F', '\x7F' => Event{ .key = KeyMap.get(buf[0..c]).? },

        // chars
        else => Event{ .key = Key{ .char = try std.unicode.utf8Decode(buf[0..c]) } },
    };

    return key;
}

fn parse_csi(buf: []const u8) !Event {
    // Cursor position report
    if (buf[buf.len - 1] == 'R') {
        var row_offset: usize = 2;
        var row_length = try read_until(buf[row_offset..], ';');
        var col_offset = row_offset + row_length + 1;
        var col_length = try read_until(buf[col_offset..], 'R');

        return Event{ .key = .{ .cursor = .{
            .x = try std.fmt.parseInt(i16, buf[col_offset .. col_offset + col_length], 10),
            .y = try std.fmt.parseInt(i16, buf[row_offset .. row_offset + row_length], 10),
        } } };
    }

    // so we skip the first 2 chars (\x1b[)
    switch (buf[2]) {
        // keys
        'A' => return Event{ .key = .up },
        'B' => return Event{ .key = .down },
        'C' => return Event{ .key = .right },
        'D' => return Event{ .key = .left },

        '1'...'2' => {
            switch (buf[3]) {
                '5' => return Event{ .key = Key{ .fun = 5 } },
                '7' => return Event{ .key = Key{ .fun = 6 } },
                '8' => return Event{ .key = Key{ .fun = 7 } },
                '9' => return Event{ .key = Key{ .fun = 8 } },
                '0' => return Event{ .key = Key{ .fun = 9 } },
                '1' => return Event{ .key = Key{ .fun = 10 } },
                '3' => return Event{ .key = Key{ .fun = 11 } },
                '4' => return Event{ .key = Key{ .fun = 12 } },
                else => {},
            }
        },

        else => {},
    }

    return .not_supported;
}

fn read_until(buf: []const u8, del: u8) !usize {
    var offset: usize = 0;

    while (offset < buf.len) {
        offset += 1;

        if (buf[offset] == del) {
            return offset;
        }
    }

    return error.CantReadEvent;
}

pub const Event = union(enum) {
    key: Key,
    resize,
    mouse,
    not_supported,
    none,
};

fn test_event_equal(bytes: []const u8, expected: Event) !void {
    var stream = std.io.fixedBufferStream(bytes);
    var event = try next(stream.reader());
    try std.testing.expectEqual(expected, event);
}

test "ctrl keys" {
    try test_event_equal("\x03", Event{ .key = Key.ctrlC });
    try test_event_equal("\x0a", Event{ .key = Key.ctrlJ }); // aka newline
    try test_event_equal("\x0d", Event{ .key = Key.ctrlM }); // aka carriage return
    try test_event_equal("\x1b", Event{ .key = Key.escape });
}

test "low function keys" {
    try test_event_equal("\x1bOP", Event{ .key = Key{ .fun = 1 } });
    try test_event_equal("\x1bOQ", Event{ .key = Key{ .fun = 2 } });
    try test_event_equal("\x1bOR", Event{ .key = Key{ .fun = 3 } });
    try test_event_equal("\x1bOS", Event{ .key = Key{ .fun = 4 } });
}

test "high function keys" {
    try test_event_equal("\x1b[15~", Event{ .key = Key{ .fun = 5 } });
    try test_event_equal("\x1b[17~", Event{ .key = Key{ .fun = 6 } });
    try test_event_equal("\x1b[18~", Event{ .key = Key{ .fun = 7 } });
    try test_event_equal("\x1b[19~", Event{ .key = Key{ .fun = 8 } });
    try test_event_equal("\x1b[20~", Event{ .key = Key{ .fun = 9 } });
    try test_event_equal("\x1b[21~", Event{ .key = Key{ .fun = 10 } });
    try test_event_equal("\x1b[23~", Event{ .key = Key{ .fun = 11 } });
    try test_event_equal("\x1b[24~", Event{ .key = Key{ .fun = 12 } });
}

test "arrow keys" {
    try test_event_equal("\x1b[A", Event{ .key = Key.up });
    try test_event_equal("\x1b[B", Event{ .key = Key.down });
    try test_event_equal("\x1b[C", Event{ .key = Key.right });
    try test_event_equal("\x1b[D", Event{ .key = Key.left });
}

test "cursor position report" {
    try test_event_equal("\x1b[19;24R", Event{ .key = Key{ .cursor = .{ .x = 24, .y = 19 } } });
}

test "normal characters" {
    try test_event_equal("q", Event{ .key = Key{ .char = 'q' } });
    try test_event_equal("😁", Event{ .key = Key{ .char = '😁' } });
}
