const std = @import("std");
const print = @import("std").debug.print;
const ArrayList = std.ArrayList;
const count = std.mem.count;

const mecha = @import("mecha");

const Buffer = @import("buffer.zig");
const default_commands = @import("default_commands.zig");
const editor = @import("editor.zig");
const buffer_window = @import("buffer_window.zig");
const ui_api = @import("../ui/ui.zig");

pub const FuncType = *const fn ([]PossibleValues) CommandRunError!void;
pub const CommandType = struct {
    function: FuncType,
    description: []const u8,
};

const globals = @import("../globals.zig");

const ParseError = error{
    DoubleQuoteInvalidPosition,
    InvalidNumberOfDoubleQuote,
    ContainsInvalidValues,
};

const CommandRunError = error{
    FunctionCommandMismatchedTypes,
    ExtraArgs,
    MissingArgs,
    CommandDoesNotExist,
};

const PossibleValues = union(enum) {
    int: i64,
    string: []const u8,
    float: f64,
    bool: bool,

    pub fn sameType(pv: PossibleValues, T: anytype) bool {
        return switch (pv) {
            .float, .int => (@typeInfo(T) == .Int or @typeInfo(T) == .Float),
            inline else => |v| std.meta.eql(@TypeOf(v), T),
        };
    }
};

const Token = struct {
    type: Types,
    content: []const u8,
};

const Types = enum {
    string,
    int,
    float,
    bool,
};

pub const CommandLine = struct {
    bhandle: editor.BufferHandle,
    buffer_window: editor.BufferWindowNode,
    functions: std.StringHashMap(CommandType),
    open: bool = false,

    pub fn init(allocator: std.mem.Allocator, cli_bhandle: editor.BufferHandle) CommandLine {
        const bw = editor.BufferWindow.init(cli_bhandle, 0, .up, 0);

        var cli = CommandLine{
            .bhandle = cli_bhandle,
            .buffer_window = .{ .data = bw },
            .functions = std.StringHashMap(CommandType).init(allocator),
        };

        return cli;
    }

    pub fn deinit(cli: *CommandLine) void {
        cli.functions.deinit();
    }

    pub fn addCommand(cli: *CommandLine, command: []const u8, comptime fn_ptr: anytype, description: []const u8) !void {
        const fn_info = @typeInfo(@TypeOf(fn_ptr)).Fn;
        if (fn_info.return_type.? != void)
            @compileError("The command's function return type needs to be void");
        if (fn_info.is_var_args)
            @compileError("The command's function cannot be variadic");

        if (command.len == 0) return error.EmptyCommand;
        if (std.mem.count(u8, command, " ") > 0) return error.CommandContainsSpaces;

        try cli.functions.put(command, .{
            .function = beholdMyFunctionInator(fn_ptr).funcy,
            .description = description,
        });
    }

    pub fn run(cli: *CommandLine, allocator: std.mem.Allocator, command_string: []const u8) !void {
        const command_result = try parseCommand(allocator, command_string);
        var command = command_result.value;

        var buffer: [128]PossibleValues = undefined;
        var string = command_result.rest;
        var i: u32 = 0;
        while (string.len != 0) : (i += 1) {
            var result = try parseArgs(allocator, string);
            buffer[i] = result.value;
            string = result.rest;
        }

        try cli.call(command, buffer[0..i]);
    }

    fn call(cli: *CommandLine, command: []const u8, args: []PossibleValues) !void {
        const com = cli.functions.get(command);

        if (com) |c| {
            try c.function(args);
        } else return CommandRunError.CommandDoesNotExist;
    }
};

pub fn beholdMyFunctionInator(comptime function: anytype) type {
    const fn_info = @typeInfo(@TypeOf(function)).Fn;

    return struct {
        pub fn funcy(args: []PossibleValues) CommandRunError!void {
            if (fn_info.params.len == 0) {
                function();
            } else if (args.len > 0 and args.len == fn_info.params.len) {
                const Tuple = std.meta.ArgsTuple(@TypeOf(function));
                var args_tuple: Tuple = undefined;
                inline for (args_tuple, 0..) |_, index| {
                    if (!args[index].sameType(@TypeOf(args_tuple[index]))) {
                        return CommandRunError.FunctionCommandMismatchedTypes;
                    }

                    const ArgTupleType = @TypeOf(args_tuple[index]);
                    const argtuple_type_info = @typeInfo(ArgTupleType);

                    if (args[index] == .int and (argtuple_type_info == .Int or argtuple_type_info == .Float)) {
                        if (argtuple_type_info == .Int)
                            args_tuple[index] = @intCast(ArgTupleType, args[index].int)
                        else {
                            args_tuple[index] = @intToFloat(ArgTupleType, args[index].int);
                        }
                    } else if (args[index] == .float and argtuple_type_info == .Float) {
                        args_tuple[index] = @floatCast(ArgTupleType, args[index].float);
                    } else if (args[index] == .float and argtuple_type_info == .Int) {
                        args_tuple[index] = @floatToInt(ArgTupleType, args[index].float);
                    } else if (args[index] == .string and std.meta.eql(ArgTupleType, []const u8)) {
                        args_tuple[index] = args[index].string;
                    } else if (args[index] == .bool and std.meta.eql(ArgTupleType, bool)) {
                        args_tuple[index] = args[index].bool;
                    }
                }

                @call(.never_inline, function, args_tuple);
            } else if (args.len < fn_info.params.len) {
                return CommandRunError.MissingArgs;
            } else if (args.len > fn_info.params.len) {
                return CommandRunError.ExtraArgs;
            }
        }
    };
}

const parseCommand = mecha.combine(.{
    mecha.many(mecha.utf8.not(mecha.utf8.char(' ')), .{ .collect = false }),
    discardManyWhiteSpace,
});

const parseArgs = mecha.combine(.{
    mecha.oneOf(.{
        parseBool,
        parseInt,
        parseFloat,
        parseString,
        parseQuotlessString,
    }),
    discardManyWhiteSpace,
});

const parseBool = mecha.map(toBool, mecha.combine(.{
    mecha.many(mecha.oneOf(.{
        mecha.string("true"),
        mecha.string("false"),
    }), .{ .max = 1, .collect = false }),

    discardWhiteSpace,
}));

const parseString = mecha.map(toString, mecha.combine(.{
    mecha.discard(mecha.utf8.char('"')),
    mecha.many(mecha.utf8.not(mecha.utf8.char('"')), .{ .collect = false }),
    mecha.discard(mecha.utf8.char('"')),
}));

const parseQuotlessString = mecha.map(toString, mecha.many(mecha.utf8.not(mecha.ascii.whitespace), .{ .collect = false }));

const parseFloat = mecha.convert(toFloat, mecha.many(mecha.oneOf(.{
    mecha.ascii.char('-'),
    mecha.ascii.digit(10),
    mecha.ascii.char('.'),
}), .{ .collect = false }));

const parseInt = mecha.convert(toInt, mecha.combine(.{
    mecha.many(mecha.oneOf(.{
        mecha.ascii.char('-'),
        mecha.ascii.digit(10),
    }), .{ .collect = false }),
    discardWhiteSpace,
}));

const discardWhiteSpace = mecha.discard(mecha.ascii.whitespace);
const discardManyWhiteSpace = mecha.discard(mecha.many(discardWhiteSpace, .{ .collect = false }));

fn toBool(string: []const u8) PossibleValues {
    return .{ .bool = std.mem.eql(u8, "true", string) };
}

fn toString(string: []const u8) PossibleValues {
    return .{ .string = string };
}

fn toFloat(allocator: std.mem.Allocator, string: []const u8) mecha.Error!PossibleValues {
    _ = allocator;
    return .{ .float = std.fmt.parseFloat(f64, string) catch return mecha.Error.ParserFailed };
}

fn toInt(allocator: std.mem.Allocator, string: []const u8) mecha.Error!PossibleValues {
    _ = allocator;
    const value = std.fmt.parseInt(i64, string, 10) catch |err| blk: {
        if (err == error.Overflow) {
            if (string[0] == '-')
                break :blk @intCast(i64, std.math.minInt(i64))
            else
                break :blk @intCast(i64, std.math.maxInt(i64));
        }

        return mecha.Error.ParserFailed;
    };
    return .{ .int = value };
}
