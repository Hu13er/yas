const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const testing = std.testing;
const ArenaAllocator = std.heap.ArenaAllocator;

const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;
const Tokenizer = tokenizer.Tokenizer;

//
// Program = Form*
// Form = Number | String | List
// List = "(smth" Form* "smth)"
//

const Node = union (enum) {
    list: List,
    symbol: Symbol,
    string: String,
    number: Number,

    const List = struct {
        items: []const Node,
        annotated: bool,
    };
    const Symbol = struct {
        value: []const u8,
    };
    const String = struct {
        value: []const u8,
    };
    const Number = struct {
        value: f32,
        is_float: bool,
    };
};

const Parser = struct {
    source: [:0]const u8,
    tokens: []const Token,
    index: usize,

    symbols_table: Table,
    strings_table: Table,
    arena: *ArenaAllocator,

    const Self = @This();

    const Table = struct {
        inner: std.StringArrayHashMapUnmanaged(void) = .empty,

        const empty: @This() = .{ .inner = .empty };

        fn ensure(self: *@This(), gpa: mem.Allocator, key: []const u8) ![]const u8 {
            if (self.inner.getKey(key)) |k| return k;
            const d = try gpa.dupe(u8, key);
            try self.inner.put(gpa, d, {});
            return d;
        }
    };

    const Error = error {
        unexpected_token,
        unexpected_eof,
        unknown_token,
        unmatching_lclose,
        parse_error,
    };

    fn init(gpa: mem.Allocator, source: [:0] const u8, tokens: []const Token) !Self {
        const arena = try gpa.create(ArenaAllocator);
        errdefer gpa.destroy(arena);

        arena.* = ArenaAllocator.init(gpa);
        errdefer arena.deinit();

        return .{
            .source = source,
            .tokens = tokens,
            .index = 0,
            .symbols_table = .empty,
            .strings_table = .empty,
            .arena = arena,
        };
    }

    fn deinit(self: *Self, gpa: mem.Allocator) void {
        self.arena.deinit();
        gpa.destroy(self.arena);
    }

    // {fn *foobar* [ n ] (+ n 1 +) fn}
    fn parse(self: *Self) (mem.Allocator.Error||Error)!?Node {
        const head = self.tokens[self.index];
        return switch (head.tag) {
            .lopen => try self.parseList(),
            .lclose => Error.unexpected_token,
            .symbol => try self.parseSymbol(),
            .string => try self.parseString(),
            .number => try self.parseNumber(),
            .comment => {
                self.index += 1;
                return self.parse();
            },
            .unknown => Error.unknown_token,
            .eof => null,
        };
    }

    fn parseList(self: *Self) (mem.Allocator.Error||Error)!Node {
        const start_token = self.tokens[self.index];
        self.index += 1;
        if (start_token.tag != .lopen) return Error.unexpected_token;

        const start_kind = self.source[start_token.start];
        const start_annot = if (start_token.end > start_token.start+1)
            self.source[start_token.start+1 .. start_token.end]
        else
            null;

        const allocator = self.arena.allocator();
        var items = try std.ArrayList(Node).initCapacity(allocator, 2);
        errdefer items.deinit(allocator);

        if (start_annot) |annot| {
            const symbol = annot;
            const allocated = try self.symbols_table.ensure(allocator, symbol);
            try items.append(allocator, .{ .symbol = .{ .value = allocated } });
        }

        debug.print("start_kind {c}\n", .{start_kind});
        if (start_annot) |ca| debug.print("start_anot {s}\n", .{ca});

        while (true) {
            const current_token = self.tokens[self.index];
            switch (current_token.tag) {
                .lclose => {
                    const current_kind = self.source[current_token.end-1];
                    const current_annot = if (current_token.end > current_token.start+1)
                        self.source[current_token.start .. current_token.end-1]
                    else
                        null;
                    self.index += 1;

                    debug.print("current_kind {c}\n", .{current_kind});
                    if (current_annot) |ca| debug.print("current_anot {s}\n", .{ca});

                    // matching list terminals should have same annotation and kind
                    // for example:
                    // {foo ... foo} -> valid
                    // {foo ... bar] -> invalid
                    if (check_failed: {
                        if (start_kind == '(' and current_kind != ')')
                            break :check_failed true;
                        if (start_kind == '{' and current_kind != '}')
                            break :check_failed true;
                        if (start_kind == '[' and current_kind != ']')
                            break :check_failed true;
                        if ((start_annot == null) != (current_annot == null))
                            break :check_failed true;
                        if (start_annot != null and current_annot != null) {
                            break :check_failed !mem.eql(u8, start_annot.?, current_annot.?);
                        }
                        break :check_failed false;
                    }) {
                        return Error.unmatching_lclose;
                    }

                    return .{ .list = .{
                        .items = try items.toOwnedSlice(allocator),
                        .annotated = start_annot != null,
                    } };
                },
                else => {
                    const child = try self.parse() orelse return Error.unexpected_eof;
                    try items.append(allocator, child);
                },
            }
        }
    }

    fn parseSymbol(self: *Self) !Node {
        const allocator = self.arena.allocator();

        const head = self.tokens[self.index];
        self.index += 1;
        if (head.tag != .symbol) return Error.unexpected_token;
        const symbol = self.source[head.start .. head.end];

        const allocated = try self.symbols_table.ensure(allocator, symbol);
        return .{ .symbol = .{ .value = allocated } };
    }

    fn parseString(self: *Self) !Node {
        const allocator = self.arena.allocator();

        const head = self.tokens[self.index];
        self.index += 1;
        if (head.tag != .string) return Error.unexpected_token;
        const string = self.source[head.start+1 .. head.end-1];

        // TODO: Parse strings; escapings excluded for now
        const allocated = try self.strings_table.ensure(allocator, string);
        return .{ .string = .{ .value = allocated } };
    }

    fn parseNumber(self: *Self) !Node {
        const head = self.tokens[self.index];
        self.index += 1;
        const number_str = self.source[head.start .. head.end];

        const value = std.fmt.parseFloat(f32, number_str) catch return Error.parse_error;
        const is_float = mem.countScalar(u8, number_str, '.') > 0;
        return .{ .number = .{ .value = value, .is_float = is_float} };
    }
};

fn testCollectTokens(allocator: std.mem.Allocator, tknizer: *Tokenizer) ![] const Token {
    var result = try std.ArrayList(Token).initCapacity(allocator, 4);
    errdefer result.deinit(allocator);
    while (tknizer.next()) |token|
        try result.append(allocator, token);
    return result.toOwnedSlice(allocator);
}

const TestCase = struct {
    desc: []const u8 = "",
    src: [:0] const u8,
    expected: ?Node,

    fn printHeader(self: @This()) void {
        if (self.desc.len > 0) {
            debug.print("\n--- {s} ---\n", .{self.desc});
        } else {
            debug.print("-----------\n", .{});
        }
        debug.print("{s}\n", .{self.src});
    }

    fn printAst(self: @This(), ast: ?Node) void {
        self.printAstTabs(ast, 0);
    }

    fn printAstTabs(self: @This(), ast: ?Node, tabs: usize) void {
        for (0..tabs) |_| debug.print("\t", .{});
        if (ast) |a| {
            switch (a) {
                .string => |s| debug.print("<STRING:'{s}'>\n", .{s.value}),
                .symbol => |s| debug.print("<SYMBOL:'{s}'>\n", .{s.value}),
                .number => |n| debug.print("<NUMBER:'{d}',is_float:{}>\n", .{n.value, n.is_float}),
                .list => |l| {
                    debug.print("<LIST,len:{},annotated:{}>:\n", .{l.items.len, l.annotated});
                    for (l.items) |i|
                        self.printAstTabs(i, tabs+1);
                },
            }
        } else {
            debug.print("<NULL>\n", .{});
        }
    }

    fn printFail(self: @This()) void {
        debug.print("test failed: {s}\n", .{self.desc});
    }
};

test "Parser tests" {
    const PRINT = true;
    const test_cases = [_]TestCase{
        .{
            .desc = "Empty",
            .src = "",
            .expected = null,
        },
        .{
            .desc = "Single symbol",
            .src =
                \\*foobar*
            ,
            .expected = .{ .symbol = .{ .value = "*foobar*" } },
        },
        .{
            .desc = "Simple string",
            .src =
                \\"Hello, world!"
            ,
            .expected = .{ .string = .{ .value = "Hello, world!" } },
        },
        .{
            .desc = "Simple list",
            .src =
                \\( simple list )
            ,
            .expected = .{ .list = .{
                .items = &[_]Node{
                    .{ .symbol = .{ .value = "simple" } },
                    .{ .symbol = .{ .value = "list" } },
                },
                .annotated = false,
            } },
        },
        .{
            .desc = "Simple annotated list",
            .src =
                \\(* x y *)
            ,
            .expected = .{ .list = .{
                .items = &[_]Node{
                    .{ .symbol = .{ .value = "*" } },
                    .{ .symbol = .{ .value = "x" } },
                    .{ .symbol = .{ .value = "y" } },
                },
                .annotated = true,
            } },
        },
        .{
            .desc = "Nested annotated list",
            .src =
            \\(* x ( foobar 10 20 ) y *)
            ,
            .expected = .{ .list = .{
                .items = &[_]Node{
                    .{ .symbol = .{ .value = "*" } },
                    .{ .symbol = .{ .value = "x" } },
                    .{ .list = .{
                        .items = &[_]Node{
                            .{ .symbol = .{ .value = "foobar" } },
                            .{ .number = .{ .value = 10.0, .is_float = false } },
                            .{ .number = .{ .value = 20.0, .is_float = false } },
                        },
                        .annotated = false,
                    } },
                    .{ .symbol = .{ .value = "y" } },
                },
                .annotated = true,
            } },
        },
    };

    const allocator = testing.allocator;
    if (PRINT) debug.print("\n-== Parser Tests ==-\n", .{});
    for (test_cases) |tc| {
        if (PRINT) tc.printHeader();
        var tknizer = Tokenizer.init(tc.src);

        const tokens = try testCollectTokens(allocator, &tknizer);
        defer allocator.free(tokens);

        var parser = try Parser.init(allocator, tc.src, tokens);
        defer parser.deinit(allocator);
        const ast = try parser.parse();

        if (PRINT) tc.printAst(ast);
        testing.expectEqualDeep(tc.expected, ast) catch |e| {
            if (PRINT) tc.printFail();
            return e;
        };
    }
}
