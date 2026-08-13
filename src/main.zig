const std = @import("std");
const Io = std.Io;

const yas = @import("yas");
const Tokenizer = yas.tokenizer.Tokenizer;

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

    try stderr.interface.print("Tokenized stdin:\n", .{});

    var tk = Tokenizer.init(src);
    while (tk.next()) |token| {
        const tag = switch (token.tag) {
            .eof => "EOF",
            .lopen => "LOPEN",
            .lclose => "LCLOSE",
            .symbol => "SYMBOL",
            .string => "STRING",
            .number => "NUMBER",
            .comment => "COMMENT",
            .unknown => "UNKNOWN",
        };
        const content = src[token.start .. token.end];
        try stdout.interface.print("<{s}:{d}:{d} {s}>\n",
            .{tag, token.start, token.end, content});
    }
}
