const std = @import("std");
const print = std.debug.print;
const StringArrayHashMap = std.StringArrayHashMap;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const input_layer_main = @import("main.zig");
const core = @import("core");
const input = core.input;
const Key = input.Key;
const cif = core.common_input_functions;

const Position = core.Buffer.Position;

pub const Mode = enum {
    normal,
    insert,
    visual,
    LEN,
};

pub const MappingFunctions = struct {
    ft_function: ?input.MappingSystem.FunctionType = null,
    default_ft_function: ?input.MappingSystem.FunctionType = null,
};

pub const state = struct {
    pub var mode: Mode = .normal;
    pub var mappings: [@enumToInt(Mode.LEN)]input.MappingSystem = undefined;
    pub var keys = std.BoundedArray(Key, 100).init(0) catch unreachable;
};

fn setMode(mode: Mode) void {
    state.mode = mode;
}

pub fn getMapping(mode: Mode) *core.input.MappingSystem {
    return &state.mappings[@enumToInt(mode)];
}

pub fn putFunction(mode: Mode, file_type: []const u8, keys: []const Key, function: input.MappingSystem.FunctionType, override_mapping: bool) !void {
    try getMapping(mode).put(file_type, keys, function, override_mapping);
}

pub fn getModeFunctions(mode: Mode, file_type: []const u8, keys: []const Key) MappingFunctions {
    var mapping = getMapping(mode);

    var mapping_functions = MappingFunctions{
        .ft_function = mapping.get(file_type, keys),
        .default_ft_function = mapping.get("", keys),
    };

    // TODO: Don's forget to ask if i need to wait for more keys
    if (!mapping.arePrefixKeys(file_type, keys) and !mapping.arePrefixKeys("", keys))
        state.keys.len = 0;

    return mapping_functions;
}

////////////////////////////////////////////////////////////////////////////////
// Function wrappers
////////////////////////////////////////////////////////////////////////////////
pub fn setNormalMode() void {
    setMode(.normal);
    resetSelection(&(core.focusedBW() orelse return).data);
}
pub fn setInsertMode() void {
    setMode(.insert);
    resetSelection(&(core.focusedBW() orelse return).data);
}
pub fn setVisualMode() void {
    setMode(.visual);

    var f = core.focusedBufferAndBW() orelse return;
    f.buffer.selection.anchor = f.buffer.getPoint(f.bw.data.cursor() orelse return);
}

pub fn openCommandLine() void {
    setMode(.insert);
    core.openCLI();
}

pub fn closeCommandLine() void {
    setMode(.normal);
    core.command_line.close();
}

pub fn enterKey() void {
    if (core.cliIsOpen()) {
        core.runCLI();
        setMode(.normal);
    } else insertNewLineAtCursor();
}

pub fn insertNewLineAtCursor() void {
    input_layer_main.characterInput("\n");
}

pub fn moveForward() void {
    const d = core.motions.white_space;
    _ = d;

    var f = core.focusedBufferAndBW() orelse return;
    const cursor = f.bw.data.cursor() orelse return;
    _ = cursor;
    // const range = core.motions.forward(f.buffer, index, &d) orelse return;
    // const end = range.endPreviousCP(f.buffer);

    // f.bw.data.setCursor(f.buffer.getPoint(end));
}

pub fn moveBackwards() void {
    const d = core.motions.white_space;
    _ = d;
    var f = core.focusedBufferAndBW() orelse return;
    _ = f;

    // const index = f.buffer.getIndex(f.bw.data.cursor());
    // const range = core.motions.backward(f.buffer, index, &d) orelse return;

    // f.bw.data.setCursor(f.buffer.getPoint(range.start));
}

pub fn paste() void {
    var fb = core.focusedBuffer() orelse return;
    _ = fb;

    // var clipboard = glfw.getClipboardString() orelse {
    //     core.notify("Clipboard", "Empty", 2000);
    //     return;
    // };
    // fb.insertBeforeCursor(clipboard) catch |err| {
    //     print("input_layer.paste()\n\t{}\n", .{err});
    // };
}

pub fn moveRight() void {
    var bw = &(core.focusedBW() orelse return).data;
    var buffer = core.getBuffer(bw.bhandle) orelse return;
    const cursor = bw.cursor() orelse return;
    bw.setCursor(buffer.moveRelativeColumn(cursor, 1));
    resetSelection(bw);
}

pub fn moveLeft() void {
    var bw = &(core.focusedBW() orelse return).data;
    var buffer = core.getBuffer(bw.bhandle) orelse return;
    const cursor = bw.cursor() orelse return;
    bw.setCursor(buffer.moveRelativeColumn(cursor, -1));
    resetSelection(bw);
}

pub fn moveUp() void {
    var bw = &(core.focusedBW() orelse return).data;
    var buffer = core.getBuffer(bw.bhandle) orelse return;
    const cursor = bw.cursor() orelse return;
    bw.setCursor(buffer.moveRelativeRow(cursor, -1));
    resetSelection(bw);
}

pub fn moveDown() void {
    var bw = &(core.focusedBW() orelse return).data;
    var buffer = core.getBuffer(bw.bhandle) orelse return;
    const cursor = bw.cursor() orelse return;
    bw.setCursor(buffer.moveRelativeRow(cursor, 1));
    resetSelection(bw);
}

fn resetSelection(bw: *core.BufferWindow) void {
    var buffer = core.getBuffer(bw.bhandle) orelse return;
    if (state.mode != .visual) buffer.selection.reset();
}
