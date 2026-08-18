const std = @import("std");
const testing = std.testing;
const debug = std.debug;

pub const Token = struct {
    pub const Tag = enum {
        lopen, lclose,
        symbol,
        string,
        number,
        comment,
        eof,
        unknown,
    };

    tag: Tag,
    start: usize,
    end: usize,
};

pub const Tokenizer = struct {
    source: [:0] const u8,
    index: usize,

    const Self = @This();

    const State = enum {
        fresh,         // LINK: FRESH
        symbol,        // LINK: SYMBOL
        lopen,         // LINK: LOPEN
        string,        // LINK: STRING
        string_escape, // LINK: STRING
        comment,       // LINK: COMMENT
        float,         // LINK: NUMBER
        int,           // LINK: NUMBER
        invalid,       // LINK: INVALID
    };

    pub fn init(source: [:0]const u8) Self {
        return .{
            .source = source,
            .index = 0,
        };
    }

    pub fn next(self: *Self) ?Token {
        if (self.index > self.source.len) return null;

        var result = Token{
            .tag = .unknown,
            .start = self.index,
            .end = self.index,
        };

        state: switch (State.fresh) {
            .fresh => switch (self.source[self.index]) {
                0 => {
                    result.tag = .eof;
                    result.start = self.index;
                    result.end = self.index;
                    self.index += 1;
                },
                '(', '{', '[' => {
                    // LINK: LOPEN
                    result.tag = .lopen;
                    result.start = self.index;
                    self.index += 1;
                    continue :state .lopen;
                },
                ')', '}', ']' => {
                    // LINK: LCLOSE
                    result.tag = .lclose;
                    result.start = self.index;
                    result.end = self.index + 1;
                    self.index += 1;
                },
                'a'...'z', 'A'...'Z',
                '+', '-', '*', '/', '\\', '=', '<', '>',
                '?', '!', '%', '&', '|', ':', '_',
                '@' => {
                    // LINK: SYMBOL
                    result.tag = .symbol;
                    result.start = self.index;
                    self.index += 1;
                    continue :state .symbol;
                },
                '0'...'9' => {
                    // LINK: NUMBER
                    result.tag = .number;
                    result.start = self.index;
                    continue :state .int;
                },
                '.' => {
                    // LINK: NUMBER
                    result.tag = .number;
                    result.start = self.index;
                    continue :state .float;
                },
                ' ', '\t', '\n' => {
                    self.index += 1;
                    continue :state .fresh;
                },
                '"' => {
                    result.tag = .string;
                    result.start = self.index;
                    self.index += 1;
                    continue :state .string;
                },
                ';' => {
                    // LINK: COMMENT
                    result.tag = .comment;
                    result.start = self.index;
                    self.index += 1;
                    continue :state .comment;
                },
                else => {
                    self.index += 1;
                    continue :state .invalid;
                },
            },
            .symbol => {
                // LINK: SYMBOL
                switch (self.source[self.index]) {
                    'a'...'z', 'A'...'Z', '0'...'9',
                        '+', '-', '*', '/', '\\', '=', '<', '>',
                    '?', '!', '%', '&', '|', ':', '_',
                    '@', '.' => {
                        self.index += 1;
                        continue :state .symbol;
                    },
                    ')', '}', ']' => {
                        result.tag = .lclose;
                        result.end = self.index + 1;
                        self.index += 1;
                    },
                    else => {
                        result.tag = .symbol;
                        result.end = self.index;
                    },
                }
            },
            .int => {
                // LINK: NUMBER
                switch (self.source[self.index]) {
                    '0'...'9' => {
                        self.index += 1;
                        continue :state .int;
                    },
                    '.' => {
                        self.index += 1;
                        continue :state .float;
                    },
                    'a'...'z', 'A'...'Z',
                        '+', '-', '*', '/', '\\', '=', '<', '>',
                    '?', '!', '%', '&', '|', ':', '_',
                    '@' => {
                        continue :state .symbol;
                    },
                    ')', '}', ']' => {
                        self.index += 1;
                        continue :state .invalid;
                    },
                    else => {
                        result.tag = .number;
                        result.end = self.index;
                    },
                }
            },
            .float => {
                // LINK: NUMBER
                switch (self.source[self.index]) {
                    '0'...'9' => {
                        self.index += 1;
                        continue :state .float;
                    },
                    'a'...'z', 'A'...'Z',
                        '+', '-', '*', '/', '\\', '=', '<', '>',
                    '?', '!', '%', '&', '|', ':', '_',
                    '@', '.' => {
                        continue :state .symbol;
                    },
                    ')', '}', ']' => {
                        self.index += 1;
                        continue :state .invalid;
                    },
                    else => {
                        result.tag = .number;
                        result.end = self.index;
                    },
                }
            },
            .lopen => {
                // LINK: LOPEN
                switch (self.source[self.index]) {
                    'a'...'z', 'A'...'Z', '0'...'9',
                        '+', '-', '*', '/', '\\', '=', '<', '>',
                    '?', '!', '%', '&', '|', ':', '_',
                    '@' => {
                        self.index += 1;
                        continue :state .lopen;
                    },
                    else => {
                        result.tag = .lopen;
                        result.end = self.index;
                    },
                }
            },
            .string => {
                // LINK: STRING
                switch (self.source[self.index]) {
                    '"' => {
                        result.tag = .string;
                        result.end = self.index + 1;
                        self.index += 1;
                    },
                    '\\' => {
                        self.index += 1;
                        continue :state .string_escape;
                    },
                    else => {
                        self.index += 1;
                        continue :state .string;
                    }
                }
            },
            .string_escape => {
                // LINK: STRING
                switch (self.source[self.index]) {
                    '\n', 0 => continue :state .invalid,
                    else => {
                        self.index += 1;
                        continue :state .string;
                    },
                }
            },
            .comment => {
                // LINK: COMMENT
                switch (self.source[self.index]) {
                    '\n' => {
                        result.tag = .comment;
                        result.end = self.index + 1;
                        self.index += 1;
                        continue :state .fresh;
                    },
                    0 => {
                        result.tag = .comment;
                        result.end = self.index;
                    },
                    else => {
                        self.index += 1;
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

test "Tokenizer tests" {
    const PRINT = false;
    const test_cases = [_]TestCase{
        .{
            .desc = "Empty",
            .src = "",
            .expected = &[_]Token{
                .{ .tag = .eof, .start = 0, .end = 0 },
            },
        },
        .{
            .desc = "Single symbol",
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
            .desc = "Single symbol with star",
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
        .{
            .desc = "Simple number",
            .src =
                \\3.1415
                // 3  .  1  4  1  5
                // 00 01 02 03 04 05
            ,
            .expected = &[_]Token{
                .{ .tag = .number, .start = 0, .end = 6 },
                .{ .tag = .eof, .start = 6, .end = 6},
            },
        },
        .{
            .desc = "Numbers concatted with alphabets are symbol",
            .src =
                \\3.1415abc
                // 3  .  1  4  1  5  a  b  c
                // 00 01 02 03 04 05 06 07 08
            ,
            .expected = &[_]Token{
                .{ .tag = .symbol, .start = 0, .end = 9 },
                .{ .tag = .eof, .start = 9, .end = 9},
            },
        },
        .{
            .desc = "Numbers concatted with other chars are symbol",
            .src =
                \\3.1415*foo 3.14*5
                // 3  .  1  4  1  5  *  f  o  o     3  .  1  4  *  5
                // 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16
            ,
            .expected = &[_]Token{
                .{ .tag = .symbol, .start = 0, .end = 10 },
                .{ .tag = .symbol, .start = 11, .end = 17 },
                .{ .tag = .eof, .start = 17, .end = 17},
            },
        },
        .{
            .desc = "Numbers with two dots are symbols",
            .src =
                \\3.1415.
                // 3  .  1  4  1  5  .
                // 00 01 02 03 04 05 06
            ,
            .expected = &[_]Token{
                .{ .tag = .symbol, .start = 0, .end = 7 },
                .{ .tag = .eof, .start = 7, .end = 7},
            },
        },
        .{
            .desc = "Numbers between two dots are symbols",
            .src =
                \\.314.
                // .  3  1  4  .
                // 00 01 02 03 04
            ,
            .expected = &[_]Token{
                .{ .tag = .symbol, .start = 0, .end = 5 },
                .{ .tag = .eof, .start = 5, .end = 5},
            },
        },
    };

    const allocator = testing.allocator;
    if (PRINT) debug.print("\n-== Tokenizer Tests ==-\n", .{});
    for (test_cases) |tc| {
        if (PRINT) tc.printHeader();
        var tokenizer = Tokenizer.init(tc.src);

        const tokens = try testCollectTokens(allocator, &tokenizer);
        defer allocator.free(tokens);

        if (PRINT) tc.printTokens(tokens);
        testing.expectEqualSlices(Token, tc.expected, tokens) catch |e| {
            if (PRINT) tc.printFail();
            return e;
        };
    }
}
