const std = @import("std");
const testing = std.testing;
const debug = std.debug;

pub const Token = struct {
    pub const Tag = enum {
        lopen, lclose,
        symbol,
        string,
        number,  // TODO
        comment, // TODO
        eof,
        unknown,
    };

    tag: Tag,
    start: usize,
    end: usize,
};

pub const Tokenizer = struct {
    src: [:0] const u8,
    idx: usize,

    const Self = @This();

    const State = enum {
        fresh,         // LINK: FRESH
        symbol,        // LINK: SYMBOL
        lopen,         // LINK: LOPEN
        string,        // LINK: STRING
        string_escape, // LINK: STRING
        comment,       // LINK: COMMENT
        invalid,       // LINK: INVALID
    };

    pub fn init(src: [:0]const u8) Self {
        return .{
            .src = src,
            .idx = 0,
        };
    }

    pub fn next(self: *Self) ?Token {
        if (self.idx > self.src.len) return null;

        var result = Token{
            .tag = .unknown,
            .start = self.idx,
            .end = self.idx,
        };

        state: switch (State.fresh) {
            .fresh => switch (self.src[self.idx]) {
                0 => {
                    result.tag = .eof;
                    result.start = self.idx;
                    result.end = self.idx;
                    self.idx += 1;
                },
                '(', '{', '[' => {
                    // LINK: LOPEN
                    result.tag = .lopen;
                    result.start = self.idx;
                    self.idx += 1;
                    continue :state .lopen;
                },
                ')', '}', ']' => {
                    // LINK: LCLOSE
                    result.tag = .lclose;
                    result.start = self.idx;
                    result.end = self.idx + 1;
                    self.idx += 1;
                },
                'a'...'z', 'A'...'Z', '0'...'9',
                '+', '-', '*', '/', '=', '<', '>',
                '?', '!', '%', '&', '|', ':', '_',
                '@' => {
                    // LINK: SYMBOL
                    result.tag = .symbol;
                    result.start = self.idx;
                    self.idx += 1;
                    continue :state .symbol;
                },
                ' ', '\t', '\n' => {
                    self.idx += 1;
                    continue :state .fresh;
                },
                '"' => {
                    result.tag = .string;
                    result.start = self.idx;
                    self.idx += 1;
                    continue :state .string;
                },
                ';' => {
                    // LINK: COMMENT
                    result.tag = .comment;
                    result.start = self.idx;
                    self.idx += 1;
                    continue :state .comment;
                },
                else => {
                    self.idx += 1;
                    continue :state .invalid;
                },
            },
            .symbol => {
                // LINK: SYMBOL
                switch (self.src[self.idx]) {
                    'a'...'z', 'A'...'Z', '0'...'9',
                    '+', '-', '*', '/', '=', '<', '>',
                    '?', '!', '%', '&', '|', ':', '_',
                    '@' => {
                        self.idx += 1;
                        continue :state .symbol;
                    },
                    ')', '}', ']' => {
                        result.tag = .lclose;
                        result.end = self.idx + 1;
                        self.idx += 1;
                    },
                    else => {
                        result.tag = .symbol;
                        result.end = self.idx;
                    },
                }
            },
            .lopen => {
                // LINK: LOPEN
                switch (self.src[self.idx]) {
                    'a'...'z', 'A'...'Z', '0'...'9',
                    '+', '-', '*', '/', '=', '<', '>',
                    '?', '!', '%', '&', '|', ':', '_',
                    '@' => {
                        self.idx += 1;
                        continue :state .lopen;
                    },
                    else => {
                        result.tag = .lopen;
                        result.end = self.idx;
                    },
                }
            },
            .string => {
                // LINK: STRING
                switch (self.src[self.idx]) {
                    '"' => {
                        result.tag = .string;
                        result.end = self.idx + 1;
                        self.idx += 1;
                    },
                    '\\' => {
                        self.idx += 1;
                        continue :state .string_escape;
                    },
                    else => {
                        self.idx += 1;
                        continue :state .string;
                    }
                }
            },
            .string_escape => {
                // LINK: STRING
                switch (self.src[self.idx]) {
                    '\n', 0 => continue :state .invalid,
                    else => {
                        self.idx += 1;
                        continue :state .string;
                    },
                }
            },
            .comment => {
                // LINK: COMMENT
                switch (self.src[self.idx]) {
                    '\n' => {
                        result.tag = .comment;
                        result.end = self.idx + 1;
                        self.idx += 1;
                        continue :state .fresh;
                    },
                    0 => {
                        result.tag = .comment;
                        result.end = self.idx;
                    },
                    else => {
                        self.idx += 1;
                        continue :state .comment;
                    }
                }
            },
            .invalid => {},
        }
        return result;
    }
};

fn testCollectTokens(allocator: std.mem.Allocator, tokenizer: *Tokenizer) ![] const Token {
    var result = try std.ArrayList(Token).initCapacity(allocator, 4);
    errdefer result.deinit(allocator);
    while (tokenizer.next()) |token|
        try result.append(allocator, token);
    return result.toOwnedSlice(allocator);
}

const TestCase = struct {
    desc: []const u8 = "",
    src: [:0] const u8,
    expected: []const Token,

    fn printHeader(self: @This()) void {
        if (self.desc.len > 0) {
            debug.print("\n--- {s} ---\n", .{self.desc});
        } else {
            debug.print("-----------\n", .{});
        }
        debug.print("{s}\n", .{self.src});
    }

    fn printTokens(self: @This(), tokens: [] const Token) void {
        for (tokens) |t| std.debug.print("<{any}>: '{s}'\n", .{t, self.src[t.start .. t.end]});
    }

    fn printFail(self: @This()) void {
        debug.print("test failed: {s}\n", .{self.desc});
    }
};

test "Basic Tokenizer tests" {
    const test_cases = [_]TestCase{
        .{
            .desc = "Empty",
            .src = "",
            .expected = &[_]Token{
                .{ .tag = .eof, .start = 0, .end = 0 },
            },
        },
        .{
            .desc = "Single Symbol",
            .src =
                \\foobar
                // f  o  o  b  a  r
                // 00 01 02 03 04 05
            ,
            .expected = &[_]Token{
                .{ .tag = .symbol, .start = 0, .end = 6 },
                .{ .tag = .eof, .start = 6, .end = 6 },
            },
        },
        .{
            .desc = "Single Symbol with star",
            .src =
                \\foo*bar*baz
                // f  o  o  *  b  a  r  *  b  a  z
                // 00 01 02 03 04 05 06 07 08 09 10
            ,
            .expected = &[_]Token{
                .{ .tag = .symbol, .start = 0, .end = 11 },
                .{ .tag = .eof, .start = 11, .end = 11 },
            },
        },
        .{
            .desc = "Multi symbols with whitespaces",
            .src =
                \\*foo* *bar*
                // *  f  o  o  *     *  b  a  r  *
                // 00 01 02 03 04 05 06 07 08 09 10
            ,
            .expected = &[_]Token{
                .{ .tag = .symbol, .start = 0, .end = 5 },
                .{ .tag = .symbol, .start = 6, .end = 11 },
                .{ .tag = .eof, .start = 11, .end = 11 },
            },
        },
        .{
            .desc = "Simple parentheses",
            .src =
                \\( + foo bar )
                // (     +     f  o  o     b  a  r     )
                // 00 01 02 03 04 05 06 07 08 09 10 11 12
            ,
            .expected = &[_]Token{
                .{ .tag = .lopen, .start = 0, .end = 1 },
                .{ .tag = .symbol, .start = 2, .end = 3 },
                .{ .tag = .symbol, .start = 4, .end = 7 },
                .{ .tag = .symbol, .start = 8, .end = 11 },
                .{ .tag = .lclose, .start = 12, .end = 13 },
                .{ .tag = .eof, .start = 13, .end = 13 },
            },
        },
        .{
            .desc = "Annotated parentheses",
            .src =
                \\(! + foo bar !)
                // (  !     +     f  o  o     b  a  r     !  )
                // 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14
            ,
            .expected = &[_]Token{
                .{ .tag = .lopen, .start = 0, .end = 2 },
                .{ .tag = .symbol, .start = 3, .end = 4 },
                .{ .tag = .symbol, .start = 5, .end = 8 },
                .{ .tag = .symbol, .start = 9, .end = 12 },
                .{ .tag = .lclose, .start = 13, .end = 15 },
                .{ .tag = .eof, .start = 15, .end = 15},
            },
        },
        .{
            .desc = "Simple string",
            .src =
                \\"Hello world string"
                // "  H  e  l  l  o     w  o  r  l  d     s  t  r  i  n  g  "
                // 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19
            ,
            .expected = &[_]Token{
                .{ .tag = .string, .start = 0, .end = 20 },
                .{ .tag = .eof, .start = 20, .end = 20},
            },
        },
        .{
            .desc = "Two string",
            .src =
                \\"ABC" "xyz"
                // "  A  B  C  "     "  x  y  z  "
                // 00 01 02 03 04 05 06 07 08 09 10
            ,
            .expected = &[_]Token{
                .{ .tag = .string, .start = 0, .end = 5 },
                .{ .tag = .string, .start = 6, .end = 11},
                .{ .tag = .eof, .start = 11, .end = 11},
            },
        },
        .{
            .desc = "String with escape",
            .src =
                \\"ABC\"HELLO\"xyz"
                // "  A  B  C  \  "  H  E  L  L  O  \  "  x  y  z  "
                // 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16
            ,
            .expected = &[_]Token{
                .{ .tag = .string, .start = 0, .end = 17 },
                .{ .tag = .eof, .start = 17, .end = 17},
            },
        },
        .{
            .desc = "Two strings with escape",
            .src =
                \\"ABC\"xyz" "foo\"*meh*\"bar"
                // "  A  B  C  \  "  x  y  z  "     "  f  o  o  \  "  *  m  e  h  *  \  "  b  a  r  "
                // 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27
            ,
            .expected = &[_]Token{
                .{ .tag = .string, .start = 0, .end = 10 },
                .{ .tag = .string, .start = 11, .end = 28 },
                .{ .tag = .eof, .start = 28, .end = 28},
            },
        },
        .{
            .desc = "Simple comment",
            .src =
                \\;comment
                // ;  c  o  m  m  e  n  t
                // 00 01 02 03 04 05 06 07
            ,
            .expected = &[_]Token{
                .{ .tag = .comment, .start = 0, .end = 8 },
                .{ .tag = .eof, .start = 8, .end = 8},
            },
        },
        .{
            .desc = "Comment after code",
            .src =
                \\*foobar*;comment *foobar*
                // *  f  o  o  b  a  r  *  ;  c  o  m  m  e  n  t     *  f  o  o  b  a  r  *
                // 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24
            ,
            .expected = &[_]Token{
                .{ .tag = .symbol, .start = 0, .end = 8 },
                .{ .tag = .comment, .start = 8, .end = 25 },
                .{ .tag = .eof, .start = 25, .end = 25},
            },
        },
        .{
            .desc = "Comment after code space",
            .src =
                \\*foobar* ;comment *foobar*
                // *  f  o  o  b  a  r  *     ;  c  o  m  m  e  n  t     *  f  o  o  b  a  r  *
                // 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25
            ,
            .expected = &[_]Token{
                .{ .tag = .symbol, .start = 0, .end = 8 },
                .{ .tag = .comment, .start = 9, .end = 26 },
                .{ .tag = .eof, .start = 26, .end = 26},
            },
        },
    };

    const allocator = testing.allocator;
    for (test_cases) |tc| {
        tc.printHeader();
        var tokenizer = Tokenizer.init(tc.src);

        const tokens = try testCollectTokens(allocator, &tokenizer);
        defer allocator.free(tokens);

        tc.printTokens(tokens);
        testing.expectEqualSlices(Token, tc.expected, tokens) catch |e| {
            tc.printFail();
            return e;
        };
    }
}
