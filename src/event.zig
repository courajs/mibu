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
};

/// Returns the next event received.
/// If raw term is `.blocking` or term is canonical it will block until read at least one event.
/// otherwise it will return `.none` if it didnt read any event
pub fn next(buf: []const u8) !EventParseResult {
    if (buf.len == 0) {
        return .none;
    }
    return switch (buf[0]) {
        '\x1b' => {
            if (buf.len == 1) {
                return EventParseResult{ .event = .{ .bytes_read = 1, .event = Event{ .key = .escape } } };
            }
            switch (buf[1]) {
                // can be fn (1 - 4)
                'O' => {
                    if (buf.len == 2) {
                        return .not_supported;
                    }
                    return EventParseResult{ .event = .{
                        .bytes_read = 3,
                        .event = Event{ .key = Key{ .fun = (buf[2] - 'O') } },
                    } };
                },

                // csi
                '[' => {
                    return try parse_cs(buf[2..]);
                },
                else => return .not_supported,
            }
        },
        // ctrl arm + specials
        '\x01'...'\x1A', '\x1C'...'\x1F', '\x7F' => EventParseResult{ .event = .{
            .bytes_read = 1,
            .event = Event{ .key = KeyMap.get(buf[0..1]).? },
        } },

        // chars
        else => {
            var len = try std.unicode.utf8ByteSequenceLength(buf[0]);
            if (buf.len < len) {
                return .incomplete;
            } else {
                return EventParseResult{ .event = .{
                    .bytes_read = len,
                    .event = Event{ .key = Key{ .char = try std.unicode.utf8Decode(buf[0..len]) } },
                } };
            }
        },
    };
}

fn parse_cs(buf: []const u8) !EventParseResult {
    if (buf.len == 0) {
        return .incomplete;
    }
    return switch (buf[0]) {
        // keys
        'A' => EventParseResult{ .event = .{ .event = Event{ .key = .up }, .bytes_read = 3 } },
        'B' => EventParseResult{ .event = .{ .event = Event{ .key = .down }, .bytes_read = 3 } },
        'C' => EventParseResult{ .event = .{ .event = Event{ .key = .right }, .bytes_read = 3 } },
        'D' => EventParseResult{ .event = .{ .event = Event{ .key = .left }, .bytes_read = 3 } },

        '1'...'2' => {
            if (buf.len < 2) {
                return .incomplete;
            }
            return switch (buf[1]) {
                '5' => EventParseResult{ .event = .{ .event = Event{ .key = Key{ .fun = 5 } }, .bytes_read = 5 } },
                '7' => EventParseResult{ .event = .{ .event = Event{ .key = Key{ .fun = 6 } }, .bytes_read = 5 } },
                '8' => EventParseResult{ .event = .{ .event = Event{ .key = Key{ .fun = 7 } }, .bytes_read = 5 } },
                '9' => EventParseResult{ .event = .{ .event = Event{ .key = Key{ .fun = 8 } }, .bytes_read = 5 } },
                '0' => EventParseResult{ .event = .{ .event = Event{ .key = Key{ .fun = 9 } }, .bytes_read = 5 } },
                '1' => EventParseResult{ .event = .{ .event = Event{ .key = Key{ .fun = 10 } }, .bytes_read = 5 } },
                '3' => EventParseResult{ .event = .{ .event = Event{ .key = Key{ .fun = 11 } }, .bytes_read = 5 } },
                '4' => EventParseResult{ .event = .{ .event = Event{ .key = Key{ .fun = 12 } }, .bytes_read = 5 } },
                else => .not_supported,
            };
        },
        else => .not_supported,
    };
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

pub const CursorLocation = struct {
    row: usize,
    col: usize,
};
pub const Event = union(enum) {
    key: Key,
    // cursor_report: CursorLocation,
    // resize,
    // mouse,
};
pub const EventParseResult = union(enum) {
    none,
    not_supported,
    incomplete,
    event: struct {
        bytes_read: usize,
        event: Event,
    },
};

fn test_event_equal(bytes: []const u8, expected: Event) !void {
    try std.testing.expectEqual(expected, (try next(bytes)).event.event);
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

test "normal characters" {
    try test_event_equal("q", Event{ .key = Key{ .char = 'q' } });
    try test_event_equal("😁", Event{ .key = Key{ .char = '😁' } });
}

test "incompletes" {
    // Utf8 incomplete code point
    try std.testing.expectEqual(try next(&[_]u8{0b11000000}), .incomplete);
    // Incomplete csi sequence
    try std.testing.expectEqual(try next("\x1b["), .incomplete);
    // incomplete prefix of a supported command sequence
    try std.testing.expectEqual(try next("\x1b[1"), .incomplete);
    // (compared to unsupported command sequences)
    try std.testing.expectEqual(try next("\x1b[34~"), .not_supported);
}

// For example, pasting into the terminal
// Or, maybe your program just doesn't read often enough
// and the user typed multiple characters
test "long text" {
    var event = (try next("abcdefg")).event.event;
    try std.testing.expectEqual(Event{ .key = Key{ .char = 'a' } }, event);
}
