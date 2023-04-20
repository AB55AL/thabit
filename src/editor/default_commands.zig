const std = @import("std");
const print = @import("std").debug.print;

const globals = @import("../globals.zig");
const Buffer = @import("buffer.zig");
const buffer_ops = @import("buffer_ops.zig");
const command_line = @import("command_line.zig");
const file_io = @import("file_io.zig");
const add = command_line.add;

const editor = globals.editor;
const internal = globals.internal;

pub fn setDefaultCommands() !void {
    try add("o", open, "Open a buffer on the current window");
    try add("oe", openEast, "Open a buffer east of the current window");
    try add("ow", openWest, "Open a buffer west of the current window");
    try add("on", openNorth, "Open a buffer north of the current window");
    try add("os", openSouth, "Open a buffer south of the current window");

    try add("save", saveFocused, "Save the buffer");
    try add("saveAs", saveAsFocused, "Save the buffer as");
    try add("forceSave", forceSaveFocused, "Force the buffer to save");
    try add("kill", killFocused, "Kill the focused buffer window");
    try add("forceKill", forceKillFocused, "Force kill the focused buffer window");
    try add("sq", saveAndQuitFocused, "Save and kill the focused buffer window");
    try add("forceSaveAndQuit", forceSaveAndQuitFocused, "Force save and kill the focused buffer window");

    try add("im.demo", imDemo, "Show imgui demo window");
    try add("ui.ins", bufferInspector, "Show the editor inspector");
}

fn imDemo(value: bool) void {
    globals.ui.imgui_demo = value;
}

fn bufferInspector(value: bool) void {
    globals.ui.inspect_editor = value;
}

fn open(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = buffer_ops.openBufferFP(file_path, null) catch |err| {
        print("open command: err={}\n", .{err});
    };
}
fn openEast(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = buffer_ops.openBufferFP(file_path, .east) catch |err| {
        print("openRight command: err={}\n", .{err});
    };
}
fn openWest(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = buffer_ops.openBufferFP(file_path, .west) catch |err| {
        print("openLeft command: err={}\n", .{err});
    };
}
fn openNorth(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = buffer_ops.openBufferFP(file_path, .north) catch |err| {
        print("openAbove command: err={}\n", .{err});
    };
}
fn openSouth(file_path: []const u8) void {
    if (file_path.len == 0) return;
    _ = buffer_ops.openBufferFP(file_path, .south) catch |err| {
        print("openBelow command: err={}\n", .{err});
    };
}

fn saveFocused() void {
    var fb = buffer_ops.focusedBuffer() orelse return;
    buffer_ops.saveBuffer(fb, false) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSave", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn saveAsFocused(file_path: []const u8) void {
    if (file_path.len == 0) return;
    var fb = buffer_ops.focusedBuffer() orelse return;

    var fp: []const u8 = undefined;
    if (std.fs.path.isAbsolute(file_path)) {
        fp = file_path;
        fb.metadata.setFilePath(fb.allocator, fp) catch |err| {
            print("err={}\n", .{err});
            return;
        };
    } else {
        var array: [4000]u8 = undefined;
        var cwd = std.os.getcwd(&array) catch |err| {
            print("err={}\n", .{err});
            return;
        };
        fp = std.mem.concat(internal.allocator, u8, &.{
            cwd,
            &.{std.fs.path.sep},
            file_path,
        }) catch |err| {
            print("err={}\n", .{err});
            return;
        };
        fb.metadata.setFilePath(fb.allocator, fp) catch |err| {
            print("err={}\n", .{err});
            return;
        };

        internal.allocator.free(fp);
    }

    buffer_ops.saveBuffer(fb, false) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSave", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn forceSaveFocused() void {
    var fb = buffer_ops.focusedBuffer() orelse return;
    buffer_ops.saveBuffer(fb, true) catch |err|
        print("err={}\n", .{err});
}

fn killFocused() void {
    var fbw = buffer_ops.focusedBW() orelse return;
    buffer_ops.killBufferWindow(fbw) catch |err| {
        if (err == buffer_ops.Error.KillingDirtyBuffer) {
            print("Cannot kill dirty buffer. Save the buffer or use forceKill", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn forceKillFocused() void {
    var fbw = buffer_ops.focusedBW() orelse return;
    buffer_ops.forceKillBufferWindow(fbw) catch |err|
        print("err={}\n", .{err});
}

fn saveAndQuitFocused() void {
    var fbw = buffer_ops.focusedBW() orelse return;
    buffer_ops.saveAndQuitWindow(fbw, false) catch |err| {
        if (err == file_io.Error.DifferentModTimes) {
            print("The file's contents might've changed since last load\n", .{});
            print("To force saving use forceSaveAndQuit", .{});
        } else {
            print("err={}\n", .{err});
        }
    };
}

fn forceSaveAndQuitFocused() void {
    var fbw = buffer_ops.focusedBW() orelse return;
    buffer_ops.saveAndQuitWindow(fbw, true) catch |err|
        print("err={}\n", .{err});
}
