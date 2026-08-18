const std = @import("std");
const debug = std.debug;
const Io = std.Io;

const yas = @import("yas");
const Token = yas.tokenizer.Token;
const Tokenizer = yas.tokenizer.Tokenizer;
const Parser = yas.parser.Parser;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var stdin = Io.File.stdin().reader(io, &.{});
    var stderr = Io.File.stderr().writer(io, &.{});
    var stdout = Io.File.stdout().writer(io, &.{});

    try stderr.interface.print("-: YAS :-\n", .{});

    const src = try stdin.interface.allocRemainingAlignedSentinel(
        allocator,
        .limited(1024 * 1024),
        .of(u8),
        comptime 0);

    const tokens = blk: {
        var tknizer = Tokenizer.init(src);
        var tokens = try std.ArrayList(Token).initCapacity(allocator, 2);
        while (tknizer.next()) |t|
            try tokens.append(allocator, t);
        break :blk try tokens.toOwnedSlice(allocator);
    };

    var parser = try Parser.init(allocator, src, tokens);
    const ast = try parser.parse();

    try stderr.interface.print("Parsed stdin:\n", .{});
    if (ast) |a| {
        try a.print(&stdout.interface);
    } else {
        try stdout.interface.print("<NULL>\n", .{});
    }
}
