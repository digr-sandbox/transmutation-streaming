const std = @import("std.zig");
const builtin = @import("builtin");
const debug = std.debug;
const assert = debug.assert;
const math = std.math;
const mem = @This();
const testing = std.testing;
const Endian = std.builtin.Endian;
const native_endian = builtin.cpu.arch.endian();

/// The standard library currently thoroughly depends on byte size
/// being 8 bits.  (see the use of u8 throughout allocation code as
/// the "byte" type.)  Code which depends on this can reference this
/// declaration.  If we ever try to port the standard library to a
/// non-8-bit-byte platform, this will allow us to search for things
/// which need to be updated.
pub const byte_size_in_bits = 8;

pub const Allocator = @import("mem/Allocator.zig");

/// Stored as a power-of-two.
pub const Alignment = enum(math.Log2Int(usize)) {
    @"1" = 0,
    @"2" = 1,
    @"4" = 2,
    @"8" = 3,
    @"16" = 4,
    @"32" = 5,
    @"64" = 6,
    _,

    pub fn toByteUnits(a: Alignment) usize {
        return @as(usize, 1) << @intFromEnum(a);
    }

    pub fn fromByteUnits(n: usize) Alignment {
        assert(std.math.isPowerOfTwo(n));
        return @enumFromInt(@ctz(n));
    }

    pub inline fn of(comptime T: type) Alignment {
        return comptime fromByteUnits(@alignOf(T));
    }

    pub fn order(lhs: Alignment, rhs: Alignment) std.math.Order {
        return std.math.order(@intFromEnum(lhs), @intFromEnum(rhs));
    }

    pub fn compare(lhs: Alignment, op: std.math.CompareOperator, rhs: Alignment) bool {
        return std.math.compare(@intFromEnum(lhs), op, @intFromEnum(rhs));
    }

    pub fn max(lhs: Alignment, rhs: Alignment) Alignment {
        return @enumFromInt(@max(@intFromEnum(lhs), @intFromEnum(rhs)));
    }

    pub fn min(lhs: Alignment, rhs: Alignment) Alignment {
        return @enumFromInt(@min(@intFromEnum(lhs), @intFromEnum(rhs)));
    }

    /// Return next address with this alignment.
    pub fn forward(a: Alignment, address: usize) usize {
        const x = (@as(usize, 1) << @intFromEnum(a)) - 1;
        return (address + x) & ~x;
    }

    /// Return previous address with this alignment.
    pub fn backward(a: Alignment, address: usize) usize {
        const x = (@as(usize, 1) << @intFromEnum(a)) - 1;
        return address & ~x;
    }

    /// Return whether address is aligned to this amount.
    pub fn check(a: Alignment, address: usize) bool {
        return @ctz(address) >= @intFromEnum(a);
    }
};

/// Detects and asserts if the std.mem.Allocator interface is violated by the caller
/// or the allocator.
pub fn ValidationAllocator(comptime T: type) type {
    return struct {
        const Self = @This();

        underlying_allocator: T,

        pub fn init(underlying_allocator: T) @This() {
            return .{
                .underlying_allocator = underlying_allocator,
            };
        }

        pub fn allocator(self: *Self) Allocator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            };
        }

        fn getUnderlyingAllocatorPtr(self: *Self) Allocator {
            if (T == Allocator) return self.underlying_allocator;
            return self.underlying_allocator.allocator();
        }

        pub fn alloc(
            ctx: *anyopaque,
            n: usize,
            alignment: mem.Alignment,
            ret_addr: usize,
        ) ?[*]u8 {
            assert(n > 0);
            const self: *Self = @ptrCast(@alignCast(ctx));
            const underlying = self.getUnderlyingAllocatorPtr();
            const result = underlying.rawAlloc(n, alignment, ret_addr) orelse
                return null;
            assert(alignment.check(@intFromPtr(result)));
            return result;
        }

        pub fn resize(
            ctx: *anyopaque,
            buf: []u8,
            alignment: Alignment,
            new_len: usize,
            ret_addr: usize,
        ) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            assert(buf.len > 0);
            const underlying = self.getUnderlyingAllocatorPtr();
            return underlying.rawResize(buf, alignment, new_len, ret_addr);
        }

        pub fn remap(
            ctx: *anyopaque,
            buf: []u8,
            alignment: Alignment,
            new_len: usize,
            ret_addr: usize,
        ) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            assert(buf.len > 0);
            const underlying = self.getUnderlyingAllocatorPtr();
            return underlying.rawRemap(buf, alignment, new_len, ret_addr);
        }

        pub fn free(
            ctx: *anyopaque,
            buf: []u8,
            alignment: Alignment,
            ret_addr: usize,
        ) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            assert(buf.len > 0);
            const underlying = self.getUnderlyingAllocatorPtr();
            underlying.rawFree(buf, alignment, ret_addr);
        }

        pub fn reset(self: *Self) void {
            self.underlying_allocator.reset();
        }
    };
}

/// Wraps an allocator with basic validation checks.
/// Asserts that allocation sizes are greater than zero and returned pointers have correct alignment.
pub fn validationWrap(allocator: anytype) ValidationAllocator(@TypeOf(allocator)) {
    return ValidationAllocator(@TypeOf(allocator)).init(allocator);
}

test "Allocator basics" {
    try testing.expectError(error.OutOfMemory, testing.failing_allocator.alloc(u8, 1));
    try testing.expectError(error.OutOfMemory, testing.failing_allocator.allocSentinel(u8, 1, 0));
}

test "Allocator.resize" {
    const primitiveIntTypes = .{
        i8,
        u8,
        i16,
        u16,
        i32,
        u32,
        i64,
        u64,
        i128,
        u128,
        isize,
        usize,
    };
    inline for (primitiveIntTypes) |T| {
        var values = try testing.allocator.alloc(T, 100);
        defer testing.allocator.free(values);

        for (values, 0..) |*v, i| v.* = @as(T, @intCast(i));
        if (!testing.allocator.resize(values, values.len + 10)) return error.OutOfMemory;
        values = values.ptr[0 .. values.len + 10];
        try testing.expect(values.len == 110);
    }

    const primitiveFloatTypes = .{
        f16,
        f32,
        f64,
        f128,
    };
    inline for (primitiveFloatTypes) |T| {
        var values = try testing.allocator.alloc(T, 100);
        defer testing.allocator.free(values);

        for (values, 0..) |*v, i| v.* = @as(T, @floatFromInt(i));
        if (!testing.allocator.resize(values, values.len + 10)) return error.OutOfMemory;
        values = values.ptr[0 .. values.len + 10];
        try testing.expect(values.len == 110);
    }
}

test "Allocator alloc and remap with zero-bit type" {
    var values = try testing.allocator.alloc(void, 10);
    defer testing.allocator.free(values);

    try testing.expectEqual(10, values.len);
    const remaped = testing.allocator.remap(values, 200);
    try testing.expect(remaped != null);

    values = remaped.?;
    try testing.expectEqual(200, values.len);
}

/// Copy all of source into dest at position 0.
/// dest.len must be >= source.len.
/// If the slices overlap, dest.ptr must be <= src.ptr.
/// This function is deprecated; use @memmove instead.
pub fn copyForwards(comptime T: type, dest: []T, source: []const T) void {
    for (dest[0..source.len], source) |*d, s| d.* = s;
}

/// Copy all of source into dest at position 0.
/// dest.len must be >= source.len.
/// If the slices overlap, dest.ptr must be >= src.ptr.
/// This function is deprecated; use @memmove instead.
pub fn copyBackwards(comptime T: type, dest: []T, source: []const T) void {
    // TODO instead of manually doing this check for the whole array
    // and turning off runtime safety, the compiler should detect loops like
    // this and automatically omit safety checks for loops
    @setRuntimeSafety(false);
    assert(dest.len >= source.len);
    var i = source.len;
    while (i > 0) {
        i -= 1;
        dest[i] = source[i];
    }
}

/// Generally, Zig users are encouraged to explicitly initialize all fields of a struct explicitly rather than using this function.
/// However, it is recognized that there are sometimes use cases for initializing all fields to a "zero" value. For example, when
/// interfacing with a C API where this practice is more common and relied upon. If you are performing code review and see this
/// function used, examine closely - it may be a code smell.
/// Zero initializes the type.
/// This can be used to zero-initialize any type for which it makes sense. Structs will be initialized recursively.
pub fn zeroes(comptime T: type) T {
    switch (@typeInfo(T)) {
        .comptime_int, .int, .comptime_float, .float => {
            return @as(T, 0);
        },
        .@"enum" => {
            return @as(T, @enumFromInt(0));
        },
        .void => {
            return {};
        },
        .bool => {
            return false;
        },
        .optional, .null => {
            return null;
        },
        .@"struct" => |struct_info| {
            if (@sizeOf(T) == 0) return undefined;
            if (struct_info.layout == .@"extern") {
                var item: T = undefined;
                @memset(asBytes(&item), 0);
                return item;
            } else {
                var structure: T = undefined;
                inline for (struct_info.fields) |field| {
                    if (!field.is_comptime) {
                        @field(structure, field.name) = zeroes(field.type);
                    }
                }
                return structure;
            }
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .slice => {
                    if (ptr_info.sentinel()) |sentinel| {
                        if (ptr_info.child == u8 and sentinel == 0) {
                            return ""; // A special case for the most common use-case: null-terminated strings.
                        }
                        @compileError("Can't set a sentinel slice to zero. This would require allocating memory.");
                    } else {
                        return &[_]ptr_info.child{};
                    }
                },
                .c => {
                    return null;
                },
                .one, .many => {
                    if (ptr_info.is_allowzero) return @ptrFromInt(0);
                    @compileError("Only nullable and allowzero pointers can be set to zero.");
                },
            }
        },
        .array => |info| {
            return @splat(zeroes(info.child));
        },
        .vector => |info| {
            return @splat(zeroes(info.child));
        },
        .@"union" => |info| {
            if (info.layout == .@"extern") {
                var item: T = undefined;
                @memset(asBytes(&item), 0);
                return item;
            }
            @compileError("Can't set a " ++ @typeName(T) ++ " to zero.");
        },
        .enum_literal,
        .error_union,
        .error_set,
        .@"fn",
        .type,
        .noreturn,
        .undefined,
        .@"opaque",
        .frame,
        .@"anyframe",
        => {
            @compileError("Can't set a " ++ @typeName(T) ++ " to zero.");
        },
    }
}

test zeroes {
    const C_struct = extern struct {
        x: u32,
        y: u32 align(128),
    };

    var a = zeroes(C_struct);

    // Extern structs should have padding zeroed out.
    try testing.expectEqualSlices(u8, &[_]u8{0} ** @sizeOf(@TypeOf(a)), asBytes(&a));

    a.y += 10;

    try testing.expect(a.x == 0);
    try testing.expect(a.y == 10);

    const ZigStruct = struct {
        comptime comptime_field: u8 = 5,

        integral_types: struct {
            integer_0: i0,
            integer_8: i8,
            integer_16: i16,
            integer_32: i32,
            integer_64: i64,
            integer_128: i128,
            unsigned_0: u0,
            unsigned_8: u8,
            unsigned_16: u16,
            unsigned_32: u32,
            unsigned_64: u64,
            unsigned_128: u128,

            float_32: f32,
            float_64: f64,
        },

        pointers: struct {
            optional: ?*u8,
            c_pointer: [*c]u8,
            slice: []u8,
            nullTerminatedString: [:0]const u8,
        },

        array: [2]u32,
        vector_u32: @Vector(2, u32),
        vector_f32: @Vector(2, f32),
        vector_bool: @Vector(2, bool),
        optional_int: ?u8,
        empty: void,
        sentinel: [3:0]u8,
    };

    const b = zeroes(ZigStruct);
    try testing.expectEqual(@as(u8, 5), b.comptime_field);
    try testing.expectEqual(@as(i8, 0), b.integral_types.integer_0);
    try testing.expectEqual(@as(i8, 0), b.integral_types.integer_8);
    try testing.expectEqual(@as(i16, 0), b.integral_types.integer_16);
    try testing.expectEqual(@as(i32, 0), b.integral_types.integer_32);
    try testing.expectEqual(@as(i64, 0), b.integral_types.integer_64);
    try testing.expectEqual(@as(i128, 0), b.integral_types.integer_128);
    try testing.expectEqual(@as(u8, 0), b.integral_types.unsigned_0);
    try testing.expectEqual(@as(u8, 0), b.integral_types.unsigned_8);
    try testing.expectEqual(@as(u16, 0), b.integral_types.unsigned_16);
    try testing.expectEqual(@as(u32, 0), b.integral_types.unsigned_32);
    try testing.expectEqual(@as(u64, 0), b.integral_types.unsigned_64);
    try testing.expectEqual(@as(u128, 0), b.integral_types.unsigned_128);
    try testing.expectEqual(@as(f32, 0), b.integral_types.float_32);
    try testing.expectEqual(@as(f64, 0), b.integral_types.float_64);
    try testing.expectEqual(@as(?*u8, null), b.pointers.optional);
    try testing.expectEqual(@as([*c]u8, null), b.pointers.c_pointer);
    try testing.expectEqual(@as([]u8, &[_]u8{}), b.pointers.slice);
    try testing.expectEqual(@as([:0]const u8, ""), b.pointers.nullTerminatedString);
    for (b.array) |e| {
        try testing.expectEqual(@as(u32, 0), e);
    }
    try testing.expectEqual(@as(@TypeOf(b.vector_u32), @splat(0)), b.vector_u32);
    try testing.expectEqual(@as(@TypeOf(b.vector_f32), @splat(0.0)), b.vector_f32);
    if (!(builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .hexagon)) {
        try testing.expectEqual(@as(@TypeOf(b.vector_bool), @splat(false)), b.vector_bool);
    }
    try testing.expectEqual(@as(?u8, null), b.optional_int);
    for (b.sentinel) |e| {
        try testing.expectEqual(@as(u8, 0), e);
    }

    const C_union = extern union {
        a: u8,
        b: u32,
    };

    const c = zeroes(C_union);
    try testing.expectEqual(@as(u8, 0), c.a);
    try testing.expectEqual(@as(u32, 0), c.b);

    const comptime_union = comptime zeroes(C_union);
    try testing.expectEqual(@as(u8, 0), comptime_union.a);
    try testing.expectEqual(@as(u32, 0), comptime_union.b);

    // Ensure zero sized struct with fields is initialized correctly.
    _ = zeroes(struct { handle: void });
}

/// Initializes all fields of the struct with their default value, or zero values if no default value is present.
/// If the field is present in the provided initial values, it will have that value instead.
/// Structs are initialized recursively.
pub fn zeroInit(comptime T: type, init: anytype) T {
    const Init = @TypeOf(init);

    switch (@typeInfo(T)) {
        .@"struct" => |struct_info| {
            switch (@typeInfo(Init)) {
                .@"struct" => |init_info| {
                    if (init_info.is_tuple) {
                        if (init_info.fields.len > struct_info.fields.len) {
                            @compileError("Tuple initializer has more elements than there are fields in `" ++ @typeName(T) ++ "`");
                        }
                    } else {
                        inline for (init_info.fields) |field| {
                            if (!@hasField(T, field.name)) {
                                @compileError("Encountered an initializer for `" ++ field.name ++ "`, but it is not a field of " ++ @typeName(T));
                            }
                        }
                    }

                    var value: T = if (struct_info.layout == .@"extern") zeroes(T) else undefined;

                    inline for (struct_info.fields, 0..) |field, i| {
                        if (field.is_comptime) {
                            continue;
                        }

                        if (init_info.is_tuple and init_info.fields.len > i) {
                            @field(value, field.name) = @field(init, init_info.fields[i].name);
                        } else if (@hasField(@TypeOf(init), field.name)) {
                            switch (@typeInfo(field.type)) {
                                .@"struct" => {
                                    @field(value, field.name) = zeroInit(field.type, @field(init, field.name));
                                },
                                else => {
                                    @field(value, field.name) = @field(init, field.name);
                                },
                            }
                        } else if (field.defaultValue()) |val| {
                            @field(value, field.name) = val;
                        } else {
                            switch (@typeInfo(field.type)) {
                                .@"struct" => {
                                    @field(value, field.name) = std.mem.zeroInit(field.type, .{});
                                },
                                else => {
                                    @field(value, field.name) = std.mem.zeroes(@TypeOf(@field(value, field.name)));
                                },
                            }
                        }
                    }

                    return value;
                },
                else => {
                    @compileError("The initializer must be a struct");
                },
            }
        },
        else => {
            @compileError("Can't default init a " ++ @typeName(T));
        },
    }
}

test zeroInit {
    const I = struct {
        d: f64,
    };

    const S = struct {
        a: u32,
        b: ?bool,
        c: I,
        e: [3]u8,
        f: i64 = -1,
    };

    const s = zeroInit(S, .{
        .a = 42,
    });

    try testing.expectEqual(S{
        .a = 42,
        .b = null,
        .c = .{
            .d = 0,
        },
        .e = [3]u8{ 0, 0, 0 },
        .f = -1,
    }, s);

    const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    };

    const c = zeroInit(Color, .{ 255, 255 });
    try testing.expectEqual(Color{
        .r = 255,
        .g = 255,
        .b = 0,
        .a = 0,
    }, c);

    const Foo = struct {
        foo: u8 = 69,
        bar: u8,
    };

    const f = zeroInit(Foo, .{});
    try testing.expectEqual(Foo{
        .foo = 69,
        .bar = 0,
    }, f);

    const Bar = struct {
        foo: u32 = 666,
        bar: u32 = 420,
    };

    const b = zeroInit(Bar, .{69});
    try testing.expectEqual(Bar{
        .foo = 69,
        .bar = 420,
    }, b);

    const Baz = struct {
        foo: [:0]const u8 = "bar",
    };

    const baz1 = zeroInit(Baz, .{});
    try testing.expectEqual(Baz{}, baz1);

    const baz2 = zeroInit(Baz, .{ .foo = "zab" });
    try testing.expectEqualSlices(u8, "zab", baz2.foo);

    const NestedBaz = struct {
        bbb: Baz,
    };
    const nested_baz = zeroInit(NestedBaz, .{});
    try testing.expectEqual(NestedBaz{
        .bbb = Baz{},
    }, nested_baz);
}

/// Sorts a slice in-place using a stable algorithm (maintains relative order of equal elements).
/// Average time complexity: O(n log n), worst case: O(n log n)
/// Space complexity: O(log n) for recursive calls
///
/// For slice of primitives with default ordering, consider using `std.sort.block` directly.
/// For unstable but potentially faster sorting, see `sortUnstable`.
pub fn sort(
    comptime T: type,
    items: []T,
    context: anytype,
    comptime lessThanFn: fn (@TypeOf(context), lhs: T, rhs: T) bool,
) void {
    std.sort.block(T, items, context, lessThanFn);
}

/// Sorts a slice in-place using an unstable algorithm (does not preserve relative order of equal elements).
/// Time complexity: O(n) best case, O(n log n) worst case and average case.
/// Generally faster than stable sort but order of equal elements is undefined.
///
/// Uses pattern-defeating quicksort (PDQ) algorithm which performs well on many data patterns.
/// For stable sorting that preserves equal element order, use `sort`.
pub fn sortUnstable(
    comptime T: type,
    items: []T,
    context: anytype,
    comptime lessThanFn: fn (@TypeOf(context), lhs: T, rhs: T) bool,
) void {
    std.sort.pdq(T, items, context, lessThanFn);
}

/// TODO: currently this just calls `insertionSortContext`. The block sort implementation
/// in this file needs to be adapted to use the sort context.
pub fn sortContext(a: usize, b: usize, context: anytype) void {
    std.sort.insertionContext(a, b, context);
}

/// Sorts a range [a, b) using an unstable algorithm with custom context.
/// This is a lower-level interface for sorting that works with indices instead of slices.
/// Does not preserve relative order of equal elements.
///
/// The context must provide lessThan(a_idx, b_idx) and swap(a_idx, b_idx) methods.
/// Uses pattern-defeating quicksort (PDQ) algorithm.
pub fn sortUnstableContext(a: usize, b: usize, context: anytype) void {
    std.sort.pdqContext(a, b, context);
}

/// Compares two slices of numbers lexicographically. O(n).
pub fn order(comptime T: type, lhs: []const T, rhs: []const T) math.Order {
    if (lhs.ptr != rhs.ptr) {
        const n = @min(lhs.len, rhs.len);
        for (lhs[0..n], rhs[0..n]) |lhs_elem, rhs_elem| {
            switch (math.order(lhs_elem, rhs_elem)) {
                .eq => continue,
                .lt => return .lt,
                .gt => return .gt,
            }
        }
    }
    return math.order(lhs.len, rhs.len);
}

/// Compares two many-item pointers with NUL-termination lexicographically.
pub fn orderZ(comptime T: type, lhs: [*:0]const T, rhs: [*:0]const T) math.Order {
    if (lhs == rhs) return .eq;
    var i: usize = 0;
    while (lhs[i] == rhs[i] and lhs[i] != 0) : (i += 1) {}
    return math.order(lhs[i], rhs[i]);
}

test order {
    try testing.expect(order(u8, "abcd", "bee") == .lt);
    try testing.expect(order(u8, "abc", "abc") == .eq);
    try testing.expect(order(u8, "abc", "abc0") == .lt);
    try testing.expect(order(u8, "", "") == .eq);
    try testing.expect(order(u8, "", "a") == .lt);

    const s: []const u8 = "abc";
    try testing.expect(order(u8, s, s) == .eq);
    try testing.expect(order(u8, s[0..2], s) == .lt);
}

test orderZ {
    try testing.expect(orderZ(u8, "abcd", "bee") == .lt);
    try testing.expect(orderZ(u8, "abc", "abc") == .eq);
    try testing.expect(orderZ(u8, "abc", "abc0") == .lt);
    try testing.expect(orderZ(u8, "", "") == .eq);
    try testing.expect(orderZ(u8, "", "a") == .lt);

    const s: [*:0]const u8 = "abc";
    try testing.expect(orderZ(u8, s, s) == .eq);
}

/// Returns true if lhs < rhs, false otherwise
pub fn lessThan(comptime T: type, lhs: []const T, rhs: []const T) bool {
    return order(T, lhs, rhs) == .lt;
}

test lessThan {
    try testing.expect(lessThan(u8, "abcd", "bee"));
    try testing.expect(!lessThan(u8, "abc", "abc"));
    try testing.expect(lessThan(u8, "abc", "abc0"));
    try testing.expect(!lessThan(u8, "", ""));
    try testing.expect(lessThan(u8, "", "a"));
}

const use_vectors = switch (builtin.zig_backend) {
    // These backends don't support vectors yet.
    .stage2_aarch64,
    .stage2_powerpc,
    .stage2_riscv64,
    => false,
    // The SPIR-V backend does not support the optimized path yet.
    .stage2_spirv => false,
    else => true,
};

// The naive memory comparison implementation is more useful for fuzzers to find interesting inputs.
const use_vectors_for_comparison = use_vectors and !builtin.fuzz;

/// Returns true if and only if the slices have the same length and all elements
/// compare true using equality operator.
pub fn eql(comptime T: type, a: []const T, b: []const T) bool {
    if (!@inComptime() and @sizeOf(T) != 0 and std.meta.hasUniqueRepresentation(T) and
        use_vectors_for_comparison)
    {
        return eqlBytes(sliceAsBytes(a), sliceAsBytes(b));
    }

    if (a.len != b.len) return false;
    if (a.len == 0 or a.ptr == b.ptr) return true;

    for (a, b) |a_elem, b_elem| {
        if (a_elem != b_elem) return false;
    }
    return true;
}

test eql {
    try testing.expect(eql(u8, "abcd", "abcd"));
    try testing.expect(!eql(u8, "abcdef", "abZdef"));
    try testing.expect(!eql(u8, "abcdefg", "abcdef"));

    comptime {
        try testing.expect(eql(type, &.{ bool, f32 }, &.{ bool, f32 }));
        try testing.expect(!eql(type, &.{ bool, f32 }, &.{ f32, bool }));
        try testing.expect(!eql(type, &.{ bool, f32 }, &.{bool}));

        try testing.expect(eql(comptime_int, &.{ 1, 2, 3 }, &.{ 1, 2, 3 }));
        try testing.expect(!eql(comptime_int, &.{ 1, 2, 3 }, &.{ 3, 2, 1 }));
        try testing.expect(!eql(comptime_int, &.{1}, &.{ 1, 2 }));
    }

    try testing.expect(eql(void, &.{ {}, {} }, &.{ {}, {} }));
    try testing.expect(!eql(void, &.{{}}, &.{ {}, {} }));
}

/// std.mem.eql heavily optimized for slices of bytes.
fn eqlBytes(a: []const u8, b: []const u8) bool {
    comptime assert(use_vectors_for_comparison);

    if (a.len != b.len) return false;
    if (a.len == 0 or a.ptr == b.ptr) return true;

    if (a.len <= 16) {
        if (a.len < 4) {
            const x = (a[0] ^ b[0]) | (a[a.len - 1] ^ b[a.len - 1]) | (a[a.len / 2] ^ b[a.len / 2]);
            return x == 0;
        }
        var x: u32 = 0;
        for ([_]usize{ 0, a.len - 4, (a.len / 8) * 4, a.len - 4 - ((a.len / 8) * 4) }) |n| {
            x |= @as(u32, @bitCast(a[n..][0..4].*)) ^ @as(u32, @bitCast(b[n..][0..4].*));
        }
        return x == 0;
    }

    // Figure out the fastest way to scan through the input in chunks.
    // Uses vectors when supported and falls back to usize/words when not.
    const Scan = if (std.simd.suggestVectorLength(u8)) |vec_size|
        struct {
            pub const size = vec_size;
            pub const Chunk = @Vector(size, u8);
            pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
                return @reduce(.Or, chunk_a != chunk_b);
            }
        }
    else
        struct {
            pub const size = @sizeOf(usize);
            pub const Chunk = usize;
            pub inline fn isNotEqual(chunk_a: Chunk, chunk_b: Chunk) bool {
                return chunk_a != chunk_b;
            }
        };

    inline for (1..6) |s| {
        const n = 16 << s;
        if (n <= Scan.size and a.len <= n) {
            const V = @Vector(n / 2, u8);
            var x = @as(V, a[0 .. n / 2].*) ^ @as(V, b[0 .. n / 2].*);
            x |= @as(V, a[a.len - n / 2 ..][0 .. n / 2].*) ^ @as(V, b[a.len - n / 2 ..][0 .. n / 2].*);
            const zero: V = @splat(0);
            return !@reduce(.Or, x != zero);
        }
    }
    // Compare inputs in chunks at a time (excluding the last chunk).
    for (0..(a.len - 1) / Scan.size) |i| {
        const a_chunk: Scan.Chunk = @bitCast(a[i * Scan.size ..][0..Scan.size].*);
        const b_chunk: Scan.Chunk = @bitCast(b[i * Scan.size ..][0..Scan.size].*);
        if (Scan.isNotEqual(a_chunk, b_chunk)) return false;
    }

    // Compare the last chunk using an overlapping read (similar to the previous size strategies).
    const last_a_chunk: Scan.Chunk = @bitCast(a[a.len - Scan.size ..][0..Scan.size].*);
    const last_b_chunk: Scan.Chunk = @bitCast(b[a.len - Scan.size ..][0..Scan.size].*);
    return !Scan.isNotEqual(last_a_chunk, last_b_chunk);
}

/// Deprecated in favor of `findDiff`.
pub const indexOfDiff = findDiff;

/// Compares two slices and returns the index of the first inequality.
/// Returns null if the slices are equal.
pub fn findDiff(comptime T: type, a: []const T, b: []const T) ?usize {
    const shortest = @min(a.len, b.len);
    if (a.ptr == b.ptr)
        return if (a.len == b.len) null else shortest;
    var index: usize = 0;
    while (index < shortest) : (index += 1) if (a[index] != b[index]) return index;
    return if (a.len == b.len) null else shortest;
}

test findDiff {
    try testing.expectEqual(findDiff(u8, "one", "one"), null);
    try testing.expectEqual(findDiff(u8, "one two", "one"), 3);
    try testing.expectEqual(findDiff(u8, "one", "one two"), 3);
    try testing.expectEqual(findDiff(u8, "one twx", "one two"), 6);
    try testing.expectEqual(findDiff(u8, "xne", "one"), 0);
}

/// Takes a sentinel-terminated pointer and returns a slice preserving pointer attributes.
/// `[*c]` pointers are assumed to be 0-terminated and assumed to not be allowzero.
fn Span(comptime T: type) type {
    switch (@typeInfo(T)) {
        .optional => |optional_info| {
            return ?Span(optional_info.child);
        },
        .pointer => |ptr_info| {
            const new_sentinel: ?ptr_info.child = switch (ptr_info.size) {
                .one, .slice => @compileError("invalid type given to std.mem.span: " ++ @typeName(T)),
                .many => ptr_info.sentinel() orelse @compileError("invalid type given to std.mem.span: " ++ @typeName(T)),
                .c => 0,
            };
            return @Pointer(.slice, .{
                .@"const" = ptr_info.is_const,
                .@"volatile" = ptr_info.is_volatile,
                .@"allowzero" = ptr_info.is_allowzero and ptr_info.size != .c,
                .@"align" = ptr_info.alignment,
                .@"addrspace" = ptr_info.address_space,
            }, ptr_info.child, new_sentinel);
        },
        else => {},
    }
    @compileError("invalid type given to std.mem.span: " ++ @typeName(T));
}

test Span {
    try testing.expect(Span([*:1]u16) == [:1]u16);
    try testing.expect(Span(?[*:1]u16) == ?[:1]u16);
    try testing.expect(Span([*:1]const u8) == [:1]const u8);
    try testing.expect(Span(?[*:1]const u8) == ?[:1]const u8);
    try testing.expect(Span([*c]u16) == [:0]u16);
    try testing.expect(Span(?[*c]u16) == ?[:0]u16);
    try testing.expect(Span([*c]const u8) == [:0]const u8);
    try testing.expect(Span(?[*c]const u8) == ?[:0]const u8);
}

/// Takes a sentinel-terminated pointer and returns a slice, iterating over the
/// memory to find the sentinel and determine the length.
/// Pointer attributes such as const are preserved.
/// `[*c]` pointers are assumed to be non-null and 0-terminated.
pub fn span(ptr: anytype) Span(@TypeOf(ptr)) {
    if (@typeInfo(@TypeOf(ptr)) == .optional) {
        if (ptr) |non_null| {
            return span(non_null);
        } else {
            return null;
        }
    }
    const Result = Span(@TypeOf(ptr));
    const l = len(ptr);
    const ptr_info = @typeInfo(Result).pointer;
    if (ptr_info.sentinel()) |s| {
        return ptr[0..l :s];
    } else {
        return ptr[0..l];
    }
}

test span {
    var array: [5]u16 = [_]u16{ 1, 2, 3, 4, 5 };
    const ptr = @as([*:3]u16, array[0..2 :3]);
    try testing.expect(eql(u16, span(ptr), &[_]u16{ 1, 2 }));
    try testing.expectEqual(@as(?[:0]u16, null), span(@as(?[*:0]u16, null)));
}

/// Helper for the return type of sliceTo()
fn SliceTo(comptime T: type, comptime end: std.meta.Elem(T)) type {
    switch (@typeInfo(T)) {
        .optional => |optional_info| {
            return ?SliceTo(optional_info.child, end);
        },
        .pointer => |ptr_info| {
            const Elem = std.meta.Elem(T);
            const have_sentinel: bool = switch (ptr_info.size) {
                .one, .slice, .many => if (std.meta.sentinel(T)) |s| s == end else false,
                .c => false,
            };
            return @Pointer(.slice, .{
                .@"const" = ptr_info.is_const,
                .@"volatile" = ptr_info.is_volatile,
                .@"allowzero" = ptr_info.is_allowzero and ptr_info.size != .c,
                .@"align" = ptr_info.alignment,
                .@"addrspace" = ptr_info.address_space,
            }, Elem, if (have_sentinel) end else null);
        },
        else => {},
    }
    @compileError("invalid type given to std.mem.sliceTo: " ++ @typeName(T));
}

/// Takes a pointer to an array, a sentinel-terminated pointer, or a slice and iterates searching for
/// the first occurrence of `end`, returning the scanned slice.
/// If `end` is not found, the full length of the array/slice/sentinel terminated pointer is returned.
/// If the pointer type is sentinel terminated and `end` matches that terminator, the
/// resulting slice is also sentinel terminated.
/// Pointer properties such as mutability and alignment are preserved.
/// C pointers are assumed to be non-null.
pub fn sliceTo(ptr: anytype, comptime end: std.meta.Elem(@TypeOf(ptr))) SliceTo(@TypeOf(ptr), end) {
    if (@typeInfo(@TypeOf(ptr)) == .optional) {
        const non_null = ptr orelse return null;
        return sliceTo(non_null, end);
    }
    const Result = SliceTo(@TypeOf(ptr), end);
    const length = lenSliceTo(ptr, end);
    const ptr_info = @typeInfo(Result).pointer;
    if (ptr_info.sentinel()) |s| {
        return ptr[0..length :s];
    } else {
        return ptr[0..length];
    }
}

test sliceTo {
    try testing.expectEqualSlices(u8, "aoeu", sliceTo("aoeu", 0));

    {
        var array: [5]u16 = [_]u16{ 1, 2, 3, 4, 5 };
        try testing.expectEqualSlices(u16, &array, sliceTo(&array, 0));
        try testing.expectEqualSlices(u16, array[0..3], sliceTo(array[0..3], 0));
        try testing.expectEqualSlices(u16, array[0..2], sliceTo(&array, 3));
        try testing.expectEqualSlices(u16, array[0..2], sliceTo(array[0..3], 3));

        const sentinel_ptr = @as([*:5]u16, @ptrCast(&array));
        try testing.expectEqualSlices(u16, array[0..2], sliceTo(sentinel_ptr, 3));
        try testing.expectEqualSlices(u16, array[0..4], sliceTo(sentinel_ptr, 99));

        const optional_sentinel_ptr = @as(?[*:5]u16, @ptrCast(&array));
        try testing.expectEqualSlices(u16, array[0..2], sliceTo(optional_sentinel_ptr, 3).?);
        try testing.expectEqualSlices(u16, array[0..4], sliceTo(optional_sentinel_ptr, 99).?);

        const c_ptr = @as([*c]u16, &array);
        try testing.expectEqualSlices(u16, array[0..2], sliceTo(c_ptr, 3));

        const slice: []u16 = &array;
        try testing.expectEqualSlices(u16, array[0..2], sliceTo(slice, 3));
        try testing.expectEqualSlices(u16, &array, sliceTo(slice, 99));

        const sentinel_slice: [:5]u16 = array[0..4 :5];
        try testing.expectEqualSlices(u16, array[0..2], sliceTo(sentinel_slice, 3));
        try testing.expectEqualSlices(u16, array[0..4], sliceTo(sentinel_slice, 99));
    }
    {
        var sentinel_array: [5:0]u16 = [_:0]u16{ 1, 2, 3, 4, 5 };
        try testing.expectEqualSlices(u16, sentinel_array[0..2], sliceTo(&sentinel_array, 3));
        try testing.expectEqualSlices(u16, &sentinel_array, sliceTo(&sentinel_array, 0));
        try testing.expectEqualSlices(u16, &sentinel_array, sliceTo(&sentinel_array, 99));
    }

    try testing.expectEqual(@as(?[]u8, null), sliceTo(@as(?[]u8, null), 0));
}

/// Private helper for sliceTo(). If you want the length, use sliceTo(foo, x).len
fn lenSliceTo(ptr: anytype, comptime end: std.meta.Elem(@TypeOf(ptr))) usize {
    switch (@typeInfo(@TypeOf(ptr))) {
        .pointer => |ptr_info| switch (ptr_info.size) {
            .one => switch (@typeInfo(ptr_info.child)) {
                .array => |array_info| {
                    if (array_info.sentinel()) |s| {
                        if (s == end) {
                            return indexOfSentinel(array_info.child, end, ptr);
                        }
                    }
                    return findScalar(array_info.child, ptr, end) orelse array_info.len;
                },
                else => {},
            },
            .many => if (ptr_info.sentinel()) |s| {
                if (s == end) {
                    return indexOfSentinel(ptr_info.child, end, ptr);
                }
                // We're looking for something other than the sentinel,
                // but iterating past the sentinel would be a bug so we need
                // to check for both.
                var i: usize = 0;
                while (ptr[i] != end and ptr[i] != s) i += 1;
                return i;
            },
            .c => {
                assert(ptr != null);
                return indexOfSentinel(ptr_info.child, end, ptr);
            },
            .slice => {
                if (ptr_info.sentinel()) |s| {
                    if (s == end) {
                        return indexOfSentinel(ptr_info.child, s, ptr);
                    }
                }
                return findScalar(ptr_info.child, ptr, end) orelse ptr.len;
            },
        },
        else => {},
    }
    @compileError("invalid type given to std.mem.sliceTo: " ++ @typeName(@TypeOf(ptr)));
}

test lenSliceTo {
    try testing.expect(lenSliceTo("aoeu", 0) == 4);

    {
        var array: [5]u16 = [_]u16{ 1, 2, 3, 4, 5 };
        try testing.expectEqual(@as(usize, 5), lenSliceTo(&array, 0));
        try testing.expectEqual(@as(usize, 3), lenSliceTo(array[0..3], 0));
        try testing.expectEqual(@as(usize, 2), lenSliceTo(&array, 3));
        try testing.expectEqual(@as(usize, 2), lenSliceTo(array[0..3], 3));

        const sentinel_ptr = @as([*:5]u16, @ptrCast(&array));
        try testing.expectEqual(@as(usize, 2), lenSliceTo(sentinel_ptr, 3));
        try testing.expectEqual(@as(usize, 4), lenSliceTo(sentinel_ptr, 99));

        const c_ptr = @as([*c]u16, &array);
        try testing.expectEqual(@as(usize, 2), lenSliceTo(c_ptr, 3));

        const slice: []u16 = &array;
        try testing.expectEqual(@as(usize, 2), lenSliceTo(slice, 3));
        try testing.expectEqual(@as(usize, 5), lenSliceTo(slice, 99));

        const sentinel_slice: [:5]u16 = array[0..4 :5];
        try testing.expectEqual(@as(usize, 2), lenSliceTo(sentinel_slice, 3));
        try testing.expectEqual(@as(usize, 4), lenSliceTo(sentinel_slice, 99));
    }
    {
        var sentinel_array: [5:0]u16 = [_:0]u16{ 1, 2, 3, 4, 5 };
        try testing.expectEqual(@as(usize, 2), lenSliceTo(&sentinel_array, 3));
        try testing.expectEqual(@as(usize, 5), lenSliceTo(&sentinel_array, 0));
        try testing.expectEqual(@as(usize, 5), lenSliceTo(&sentinel_array, 99));
    }
}

/// Takes a sentinel-terminated pointer and iterates over the memory to find the
/// sentinel and determine the length.
/// `[*c]` pointers are assumed to be non-null and 0-terminated.
pub fn len(value: anytype) usize {
    switch (@typeInfo(@TypeOf(value))) {
        .pointer => |info| switch (info.size) {
            .many => {
                const sentinel = info.sentinel() orelse
                    @compileError("invalid type given to std.mem.len: " ++ @typeName(@TypeOf(value)));
                return indexOfSentinel(info.child, sentinel, value);
            },
            .c => {
                assert(value != null);
                return indexOfSentinel(info.child, 0, value);
            },
            else => @compileError("invalid type given to std.mem.len: " ++ @typeName(@TypeOf(value))),
        },
        else => @compileError("invalid type given to std.mem.len: " ++ @typeName(@TypeOf(value))),
    }
}

test len {
    var array: [5]u16 = [_]u16{ 1, 2, 0, 4, 5 };
    const ptr = @as([*:4]u16, array[0..3 :4]);
    try testing.expect(len(ptr) == 3);
    const c_ptr = @as([*c]u16, ptr);
    try testing.expect(len(c_ptr) == 2);
}

/// Deprecated in favor of `findSentinel`.
pub const indexOfSentinel = findSentinel;

/// Returns the index of the sentinel value in a sentinel-terminated pointer.
/// Linear search through memory until the sentinel is found.
pub fn findSentinel(comptime T: type, comptime sentinel: T, p: [*:sentinel]const T) usize {
    var i: usize = 0;

    if (use_vectors_for_comparison and
        !std.debug.inValgrind() and // https://github.com/ziglang/zig/issues/17717
        !@inComptime() and
        (@typeInfo(T) == .int or @typeInfo(T) == .float) and std.math.isPowerOfTwo(@bitSizeOf(T)))
    {
        switch (@import("builtin").cpu.arch) {
            // The below branch assumes that reading past the end of the buffer is valid, as long
            // as we don't read into a new page. This should be the case for most architectures
            // which use paged memory, however should be confirmed before adding a new arch below.
            .aarch64, .x86, .x86_64 => if (std.simd.suggestVectorLength(T)) |block_len| {
                const page_size = std.heap.page_size_min;
                const block_size = @sizeOf(T) * block_len;
                const Block = @Vector(block_len, T);
                const mask: Block = @splat(sentinel);

                comptime assert(std.heap.page_size_min % @sizeOf(Block) == 0);
                assert(page_size % @sizeOf(Block) == 0);

                // First block may be unaligned
                const start_addr = @intFromPtr(&p[i]);
                const offset_in_page = start_addr & (page_size - 1);
                if (offset_in_page <= page_size - @sizeOf(Block)) {
                    // Will not read past the end of a page, full block.
                    const block: Block = p[i..][0..block_len].*;
                    const matches = block == mask;
                    if (@reduce(.Or, matches)) {
                        return i + std.simd.firstTrue(matches).?;
                    }

                    i += @divExact(std.mem.alignForward(usize, start_addr, block_size) - start_addr, @sizeOf(T));
                } else {
                    @branchHint(.unlikely);
                    // Would read over a page boundary. Per-byte at a time until aligned or found.
                    // 0.39% chance this branch is taken for 4K pages at 16b block length.
                    //
                    // An alternate strategy is to do read a full block (the last in the page) and
                    // mask the entries before the pointer.
                    while ((@intFromPtr(&p[i]) & (block_size - 1)) != 0) : (i += 1) {
                        if (p[i] == sentinel) return i;
                    }
                }

                std.debug.assertAligned(&p[i], .fromByteUnits(block_size));
                while (true) {
                    const block: Block = p[i..][0..block_len].*;
                    const matches = block == mask;
                    if (@reduce(.Or, matches)) {
                        return i + std.simd.firstTrue(matches).?;
                    }
                    i += block_len;
                }
            },
            else => {},
        }
    }

    while (p[i] != sentinel) {
        i += 1;
    }
    return i;
}

test "indexOfSentinel vector paths" {
    const Types = [_]type{ u8, u16, u32, u64 };
    const allocator = std.testing.allocator;
    const page_size = std.heap.page_size_min;

    inline for (Types) |T| {
        const block_len = std.simd.suggestVectorLength(T) orelse continue;

        // Allocate three pages so we guarantee a page-crossing address with a full page after
        const memory = try allocator.alloc(T, 3 * page_size / @sizeOf(T));
        defer allocator.free(memory);
        @memset(memory, 0xaa);

        // Find starting page-alignment = 0
        var start: usize = 0;
        const start_addr = @intFromPtr(&memory);
        start += (std.mem.alignForward(usize, start_addr, page_size) - start_addr) / @sizeOf(T);
        try testing.expect(start < page_size / @sizeOf(T));

        // Validate all sub-block alignments
        const search_len = page_size / @sizeOf(T);
        memory[start + search_len] = 0;
        for (0..block_len) |offset| {
            try testing.expectEqual(search_len - offset, indexOfSentinel(T, 0, @ptrCast(&memory[start + offset])));
        }
        memory[start + search_len] = 0xaa;

        // Validate page boundary crossing
        const start_page_boundary = start + (page_size / @sizeOf(T));
        memory[start_page_boundary + block_len] = 0;
        for (0..block_len) |offset| {
            try testing.expectEqual(2 * block_len - offset, indexOfSentinel(T, 0, @ptrCast(&memory[start_page_boundary - block_len + offset])));
        }
    }
}

/// Returns true if all elements in a slice are equal to the scalar value provided
pub fn allEqual(comptime T: type, slice: []const T, scalar: T) bool {
    for (slice) |item| {
        if (item != scalar) return false;
    }
    return true;
}

/// Remove a set of values from the beginning of a slice.
pub fn trimStart(comptime T: type, slice: []const T, values_to_strip: []const T) []const T {
    var begin: usize = 0;
    while (begin < slice.len and findScalar(T, values_to_strip, slice[begin]) != null) : (begin += 1) {}
    return slice[begin..];
}

test trimStart {
    try testing.expectEqualSlices(u8, "foo\n ", trimStart(u8, " foo\n ", " \n"));
}

/// Deprecated: use `trimStart` instead.
pub const trimLeft = trimStart;

/// Remove a set of values from the end of a slice.
pub fn trimEnd(comptime T: type, slice: []const T, values_to_strip: []const T) []const T {
    var end: usize = slice.len;
    while (end > 0 and findScalar(T, values_to_strip, slice[end - 1]) != null) : (end -= 1) {}
    return slice[0..end];
}

test trimEnd {
    try testing.expectEqualSlices(u8, " foo", trimEnd(u8, " foo\n ", " \n"));
}

/// Deprecated: use `trimEnd` instead.
pub const trimRight = trimEnd;

/// Remove a set of values from the beginning and end of a slice.
pub fn trim(comptime T: type, slice: []const T, values_to_strip: []const T) []const T {
    var begin: usize = 0;
    var end: usize = slice.len;
    while (begin < end and findScalar(T, values_to_strip, slice[begin]) != null) : (begin += 1) {}
    while (end > begin and findScalar(T, values_to_strip, slice[end - 1]) != null) : (end -= 1) {}
    return slice[begin..end];
}

test trim {
    try testing.expectEqualSlices(u8, "foo", trim(u8, " foo\n ", " \n"));
    try testing.expectEqualSlices(u8, "foo", trim(u8, "foo", " \n"));
}

/// Deprecated in favor of `findScalar`.
pub const indexOfScalar = findScalar;

/// Linear search for the index of a scalar value inside a slice.
pub fn findScalar(comptime T: type, slice: []const T, value: T) ?usize {
    return indexOfScalarPos(T, slice, 0, value);
}

/// Deprecated in favor of `findScalarLast`.
pub const lastIndexOfScalar = findScalarLast;

/// Linear search for the last index of a scalar value inside a slice.
pub fn findScalarLast(comptime T: type, slice: []const T, value: T) ?usize {
    var i: usize = slice.len;
    while (i != 0) {
        i -= 1;
        if (slice[i] == value) return i;
    }
    return null;
}

/// Deprecated in favor of `findScalarPos`.
pub const indexOfScalarPos = findScalarPos;

/// Linear search for the index of a scalar value inside a slice, starting from a given position.
/// Returns null if the value is not found.
pub fn findScalarPos(comptime T: type, slice: []const T, start_index: usize, value: T) ?usize {
    if (start_index >= slice.len) return null;

    var i: usize = start_index;
    if (use_vectors_for_comparison and
        !std.debug.inValgrind() and // https://github.com/ziglang/zig/issues/17717
        !@inComptime() and
        (@typeInfo(T) == .int or @typeInfo(T) == .float) and std.math.isPowerOfTwo(@bitSizeOf(T)))
    {
        if (std.simd.suggestVectorLength(T)) |block_len| {
            // For Intel Nehalem (2009) and AMD Bulldozer (2012) or later, unaligned loads on aligned data result
            // in the same execution as aligned loads. We ignore older arch's here and don't bother pre-aligning.
            //
            // Use `std.simd.suggestVectorLength(T)` to get the same alignment as used in this function
            // however this usually isn't necessary unless your arch has a performance penalty due to this.
            //
            // This may differ for other arch's. Arm for example costs a cycle when loading across a cache
            // line so explicit alignment prologues may be worth exploration.

            // Unrolling here is ~10% improvement. We can then do one bounds check every 2 blocks
            // instead of one which adds up.
            const Block = @Vector(block_len, T);
            if (i + 2 * block_len < slice.len) {
                const mask: Block = @splat(value);
                while (true) {
                    inline for (0..2) |_| {
                        const block: Block = slice[i..][0..block_len].*;
                        const matches = block == mask;
                        if (@reduce(.Or, matches)) {
                            return i + std.simd.firstTrue(matches).?;
                        }
                        i += block_len;
                    }
                    if (i + 2 * block_len >= slice.len) break;
                }
            }

            // {block_len, block_len / 2} check
            inline for (0..2) |j| {
                const block_x_len = block_len / (1 << j);
                comptime if (block_x_len < 4) break;

                const BlockX = @Vector(block_x_len, T);
                if (i + block_x_len < slice.len) {
                    const mask: BlockX = @splat(value);
                    const block: BlockX = slice[i..][0..block_x_len].*;
                    const matches = block == mask;
                    if (@reduce(.Or, matches)) {
                        return i + std.simd.firstTrue(matches).?;
                    }
                    i += block_x_len;
                }
            }
        }
    }

    for (slice[i..], i..) |c, j| {
        if (c == value) return j;
    }
    return null;
}

test indexOfScalarPos {
    const Types = [_]type{ u8, u16, u32, u64 };

    inline for (Types) |T| {
        var memory: [64 / @sizeOf(T)]T = undefined;
        @memset(&memory, 0xaa);
        memory[memory.len - 1] = 0;

        for (0..memory.len) |i| {
            try testing.expectEqual(memory.len - i - 1, indexOfScalarPos(T, memory[i..], 0, 0).?);
        }
    }
}

/// Deprecated in favor of `findAny`.
pub const indexOfAny = findAny;

/// Linear search for the index of any value in the provided list inside a slice.
/// Returns null if no values are found.
pub fn findAny(comptime T: type, slice: []const T, values: []const T) ?usize {
    return indexOfAnyPos(T, slice, 0, values);
}

/// Deprecated in favor of `findLastAny`.
pub const lastIndexOfAny = findLastAny;

/// Linear search for the last index of any value in the provided list inside a slice.
/// Returns null if no values are found.
pub fn findLastAny(comptime T: type, slice: []const T, values: []const T) ?usize {
    var i: usize = slice.len;
    while (i != 0) {
        i -= 1;
        for (values) |value| {
            if (slice[i] == value) return i;
        }
    }
    return null;
}

/// Deprecated in favor of `findAnyPos`.
pub const indexOfAnyPos = findAnyPos;

/// Linear search for the index of any value in the provided list inside a slice, starting from a given position.
/// Returns null if no values are found.
pub fn findAnyPos(comptime T: type, slice: []const T, start_index: usize, values: []const T) ?usize {
    if (start_index >= slice.len) return null;
    for (slice[start_index..], start_index..) |c, i| {
        for (values) |value| {
            if (c == value) return i;
        }
    }
    return null;
}

/// Deprecated in favor of `findNone`.
pub const indexOfNone = findNone;

/// Find the first item in `slice` which is not contained in `values`.
///
/// Comparable to `strspn` in the C standard library.
pub fn findNone(comptime T: type, slice: []const T, values: []const T) ?usize {
    return indexOfNonePos(T, slice, 0, values);
}

test findNone {
    try testing.expect(findNone(u8, "abc123", "123").? == 0);
    try testing.expect(findLastNone(u8, "abc123", "123").? == 2);
    try testing.expect(findNone(u8, "123abc", "123").? == 3);
    try testing.expect(findLastNone(u8, "123abc", "123").? == 5);
    try testing.expect(findNone(u8, "123123", "123") == null);
    try testing.expect(findNone(u8, "333333", "123") == null);

    try testing.expect(indexOfNonePos(u8, "abc123", 3, "321") == null);
}

/// Deprecated in favor of `findLastNone`.
pub const lastIndexOfNone = findLastNone;

/// Find the last item in `slice` which is not contained in `values`.
///
/// Like `strspn` in the C standard library, but searches from the end.
pub fn findLastNone(comptime T: type, slice: []const T, values: []const T) ?usize {
    var i: usize = slice.len;
    outer: while (i != 0) {
        i -= 1;
        for (values) |value| {
            if (slice[i] == value) continue :outer;
        }
        return i;
    }
    return null;
}

pub const indexOfNonePos = findNonePos;

/// Find the first item in `slice[start_index..]` which is not contained in `values`.
/// The returned index will be relative to the start of `slice`, and never less than `start_index`.
///
/// Comparable to `strspn` in the C standard library.
pub fn findNonePos(comptime T: type, slice: []const T, start_index: usize, values: []const T) ?usize {
    if (start_index >= slice.len) return null;
    outer: for (slice[start_index..], start_index..) |c, i| {
        for (values) |value| {
            if (c == value) continue :outer;
        }
        return i;
    }
    return null;
}

/// Deprecated in favor of `find`.
pub const indexOf = find;

/// Search for needle in haystack and return the index of the first occurrence.
/// Uses Boyer-Moore-Horspool algorithm on large inputs; linear search on small inputs.
/// Returns null if needle is not found.
pub fn find(comptime T: type, haystack: []const T, needle: []const T) ?usize {
    return indexOfPos(T, haystack, 0, needle);
}

/// Deprecated in favor of `findLastLinear`.
pub const lastIndexOfLinear = findLastLinear;

/// Find the index in a slice of a sub-slice, searching from the end backwards.
/// To start looking at a different index, slice the haystack first.
/// Consider using `lastIndexOf` instead of this, which will automatically use a
/// more sophisticated algorithm on larger inputs.
pub fn findLastLinear(comptime T: type, haystack: []const T, needle: []const T) ?usize {
    if (needle.len > haystack.len) return null;
    var i: usize = haystack.len - needle.len;
    while (true) : (i -= 1) {
        if (mem.eql(T, haystack[i..][0..needle.len], needle)) return i;
        if (i == 0) return null;
    }
}

pub const indexOfPosLinear = findPosLinear;

/// Consider using `indexOfPos` instead of this, which will automatically use a
/// more sophisticated algorithm on larger inputs.
pub fn findPosLinear(comptime T: type, haystack: []const T, start_index: usize, needle: []const T) ?usize {
    if (needle.len > haystack.len) return null;
    var i: usize = start_index;
    const end = haystack.len - needle.len;
    while (i <= end) : (i += 1) {
        if (eql(T, haystack[i..][0..needle.len], needle)) return i;
    }
    return null;
}

test findPosLinear {
    try testing.expectEqual(0, findPosLinear(u8, "", 0, ""));
    try testing.expectEqual(0, findPosLinear(u8, "123", 0, ""));

    try testing.expectEqual(null, findPosLinear(u8, "", 0, "1"));
    try testing.expectEqual(0, findPosLinear(u8, "1", 0, "1"));
    try testing.expectEqual(null, findPosLinear(u8, "2", 0, "1"));
    try testing.expectEqual(1, findPosLinear(u8, "21", 0, "1"));
    try testing.expectEqual(null, findPosLinear(u8, "222", 0, "1"));

    try testing.expectEqual(null, findPosLinear(u8, "", 0, "12"));
    try testing.expectEqual(null, findPosLinear(u8, "1", 0, "12"));
    try testing.expectEqual(null, findPosLinear(u8, "2", 0, "12"));
    try testing.expectEqual(0, findPosLinear(u8, "12", 0, "12"));
    try testing.expectEqual(null, findPosLinear(u8, "21", 0, "12"));
    try testing.expectEqual(1, findPosLinear(u8, "212", 0, "12"));
    try testing.expectEqual(0, findPosLinear(u8, "122", 0, "12"));
    try testing.expectEqual(1, findPosLinear(u8, "212112", 0, "12"));
}

fn boyerMooreHorspoolPreprocessReverse(pattern: []const u8, table: *[256]usize) void {
    for (table) |*c| {
        c.* = pattern.len;
    }

    var i: usize = pattern.len - 1;
    // The first item is intentionally ignored and the skip size will be pattern.len.
    // This is the standard way Boyer-Moore-Horspool is implemented.
    while (i > 0) : (i -= 1) {
        table[pattern[i]] = i;
    }
}

fn boyerMooreHorspoolPreprocess(pattern: []const u8, table: *[256]usize) void {
    for (table) |*c| {
        c.* = pattern.len;
    }

    var i: usize = 0;
    // The last item is intentionally ignored and the skip size will be pattern.len.
    // This is the standard way Boyer-Moore-Horspool is implemented.
    while (i < pattern.len - 1) : (i += 1) {
        table[pattern[i]] = pattern.len - 1 - i;
    }
}

/// Deprecated in favor of `find`.
pub const lastIndexOf = findLast;

/// Find the index in a slice of a sub-slice, searching from the end backwards.
/// To start looking at a different index, slice the haystack first.
/// Uses the Reverse Boyer-Moore-Horspool algorithm on large inputs;
/// `lastIndexOfLinear` on small inputs.
pub fn findLast(comptime T: type, haystack: []const T, needle: []const T) ?usize {
    if (needle.len > haystack.len) return null;
    if (needle.len == 0) return haystack.len;

    if (!std.meta.hasUniqueRepresentation(T) or haystack.len < 52 or needle.len <= 4)
        return lastIndexOfLinear(T, haystack, needle);

    const haystack_bytes = sliceAsBytes(haystack);
    const needle_bytes = sliceAsBytes(needle);

    var skip_table: [256]usize = undefined;
    boyerMooreHorspoolPreprocessReverse(needle_bytes, skip_table[0..]);

    var i: usize = haystack_bytes.len - needle_bytes.len;
    while (true) {
        if (i % @sizeOf(T) == 0 and mem.eql(u8, haystack_bytes[i .. i + needle_bytes.len], needle_bytes)) {
            return @divExact(i, @sizeOf(T));
        }
        const skip = skip_table[haystack_bytes[i]];
        if (skip > i) break;
        i -= skip;
    }

    return null;
}

/// Deprecated in favor of `findPos`.
pub const indexOfPos = findPos;

/// Uses Boyer-Moore-Horspool algorithm on large inputs; `indexOfPosLinear` on small inputs.
pub fn findPos(comptime T: type, haystack: []const T, start_index: usize, needle: []const T) ?usize {
    if (needle.len > haystack.len) return null;
    if (needle.len < 2) {
        if (needle.len == 0) return start_index;
        // indexOfScalarPos is significantly faster than indexOfPosLinear
        return indexOfScalarPos(T, haystack, start_index, needle[0]);
    }

    if (!std.meta.hasUniqueRepresentation(T) or haystack.len < 52 or needle.len <= 4)
        return indexOfPosLinear(T, haystack, start_index, needle);

    const haystack_bytes = sliceAsBytes(haystack);
    const needle_bytes = sliceAsBytes(needle);

    var skip_table: [256]usize = undefined;
    boyerMooreHorspoolPreprocess(needle_bytes, skip_table[0..]);

    var i: usize = start_index * @sizeOf(T);
    while (i <= haystack_bytes.len - needle_bytes.len) {
        if (i % @sizeOf(T) == 0 and mem.eql(u8, haystack_bytes[i .. i + needle_bytes.len], needle_bytes)) {
            return @divExact(i, @sizeOf(T));
        }
        i += skip_table[haystack_bytes[i + needle_bytes.len - 1]];
    }

    return null;
}

test indexOf {
    try testing.expect(indexOf(u8, "one two three four five six seven eight nine ten eleven", "three four").? == 8);
    try testing.expect(lastIndexOf(u8, "one two three four five six seven eight nine ten eleven", "three four").? == 8);
    try testing.expect(indexOf(u8, "one two three four five six seven eight nine ten eleven", "two two") == null);
    try testing.expect(lastIndexOf(u8, "one two three four five six seven eight nine ten eleven", "two two") == null);

    try testing.expect(indexOf(u8, "one two three four five six seven eight nine ten", "").? == 0);
    try testing.expect(lastIndexOf(u8, "one two three four five six seven eight nine ten", "").? == 48);

    try testing.expect(indexOf(u8, "one two three four", "four").? == 14);
    try testing.expect(lastIndexOf(u8, "one two three two four", "two").? == 14);
    try testing.expect(indexOf(u8, "one two three four", "gour") == null);
    try testing.expect(lastIndexOf(u8, "one two three four", "gour") == null);
    try testing.expect(indexOf(u8, "foo", "foo").? == 0);
    try testing.expect(lastIndexOf(u8, "foo", "foo").? == 0);
    try testing.expect(indexOf(u8, "foo", "fool") == null);
    try testing.expect(lastIndexOf(u8, "foo", "lfoo") == null);
    try testing.expect(lastIndexOf(u8, "foo", "fool") == null);

    try testing.expect(indexOf(u8, "foo foo", "foo").? == 0);
    try testing.expect(lastIndexOf(u8, "foo foo", "foo").? == 4);
    try testing.expect(lastIndexOfAny(u8, "boo, cat", "abo").? == 6);
    try testing.expect(findScalarLast(u8, "boo", 'o').? == 2);
}

test "indexOf multibyte" {
    {
        // make haystack and needle long enough to trigger Boyer-Moore-Horspool algorithm
        const haystack = [1]u16{0} ** 100 ++ [_]u16{ 0xbbaa, 0xccbb, 0xddcc, 0xeedd, 0xffee, 0x00ff };
        const needle = [_]u16{ 0xbbaa, 0xccbb, 0xddcc, 0xeedd, 0xffee };
        try testing.expectEqual(indexOfPos(u16, &haystack, 0, &needle), 100);

        // check for misaligned false positives (little and big endian)
        const needleLE = [_]u16{ 0xbbbb, 0xcccc, 0xdddd, 0xeeee, 0xffff };
        try testing.expectEqual(indexOfPos(u16, &haystack, 0, &needleLE), null);
        const needleBE = [_]u16{ 0xaacc, 0xbbdd, 0xccee, 0xddff, 0xee00 };
        try testing.expectEqual(indexOfPos(u16, &haystack, 0, &needleBE), null);
    }

    {
        // make haystack and needle long enough to trigger Boyer-Moore-Horspool algorithm
        const haystack = [_]u16{ 0xbbaa, 0xccbb, 0xddcc, 0xeedd, 0xffee, 0x00ff } ++ [1]u16{0} ** 100;
        const needle = [_]u16{ 0xbbaa, 0xccbb, 0xddcc, 0xeedd, 0xffee };
        try testing.expectEqual(lastIndexOf(u16, &haystack, &needle), 0);

        // check for misaligned false positives (little and big endian)
        const needleLE = [_]u16{ 0xbbbb, 0xcccc, 0xdddd, 0xeeee, 0xffff };
        try testing.expectEqual(lastIndexOf(u16, &haystack, &needleLE), null);
        const needleBE = [_]u16{ 0xaacc, 0xbbdd, 0xccee, 0xddff, 0xee00 };
        try testing.expectEqual(lastIndexOf(u16, &haystack, &needleBE), null);
    }
}

test "indexOfPos empty needle" {
    try testing.expectEqual(indexOfPos(u8, "abracadabra", 5, ""), 5);
}

/// Returns the number of needles inside the haystack
/// needle.len must be > 0
/// does not count overlapping needles
pub fn count(comptime T: type, haystack: []const T, needle: []const T) usize {
    if (needle.len == 1) return countScalar(T, haystack, needle[0]);
    assert(needle.len > 0);
    var i: usize = 0;
    var found: usize = 0;

    while (indexOfPos(T, haystack, i, needle)) |idx| {
        i = idx + needle.len;
        found += 1;
    }

    return found;
}

test count {
    try testing.expect(count(u8, "", "h") == 0);
    try testing.expect(count(u8, "h", "h") == 1);
    try testing.expect(count(u8, "hh", "h") == 2);
    try testing.expect(count(u8, "world!", "hello") == 0);
    try testing.expect(count(u8, "hello world!", "hello") == 1);
    try testing.expect(count(u8, "   abcabc   abc", "abc") == 3);
    try testing.expect(count(u8, "udexdcbvbruhasdrw", "bruh") == 1);
    try testing.expect(count(u8, "foo bar", "o bar") == 1);
    try testing.expect(count(u8, "foofoofoo", "foo") == 3);
    try testing.expect(count(u8, "fffffff", "ff") == 3);
    try testing.expect(count(u8, "owowowu", "owowu") == 1);
}

/// Returns the number of times `element` appears in a slice of memory.
pub fn countScalar(comptime T: type, list: []const T, element: T) usize {
    const n = list.len;
    var i: usize = 0;
    var found: usize = 0;

    if (use_vectors_for_comparison and
        (@typeInfo(T) == .int or @typeInfo(T) == .float) and std.math.isPowerOfTwo(@bitSizeOf(T)))
    {
        if (std.simd.suggestVectorLength(T)) |block_size| {
            const Block = @Vector(block_size, T);

            const letter_mask: Block = @splat(element);
            while (n - i >= block_size) : (i += block_size) {
                const haystack_block: Block = list[i..][0..block_size].*;
                found += std.simd.countTrues(letter_mask == haystack_block);
            }
        }
    }

    for (list[i..n]) |item| {
        found += @intFromBool(item == element);
    }

    return found;
}

test countScalar {
    try testing.expectEqual(0, countScalar(u8, "", 'h'));
    try testing.expectEqual(1, countScalar(u8, "h", 'h'));
    try testing.expectEqual(2, countScalar(u8, "hh", 'h'));
    try testing.expectEqual(2, countScalar(u8, "ahhb", 'h'));
    try testing.expectEqual(3, countScalar(u8, "   abcabc   abc", 'b'));
}

/// Returns true if the haystack contains expected_count or more needles
/// needle.len must be > 0
/// does not count overlapping needles
//
/// See also: `containsAtLeastScalar`
pub fn containsAtLeast(comptime T: type, haystack: []const T, expected_count: usize, needle: []const T) bool {
    if (needle.len == 1) return containsAtLeastScalar(T, haystack, expected_count, needle[0]);
    assert(needle.len > 0);
    if (expected_count == 0) return true;

    var i: usize = 0;
    var found: usize = 0;

    while (indexOfPos(T, haystack, i, needle)) |idx| {
        i = idx + needle.len;
        found += 1;
        if (found == expected_count) return true;
    }
    return false;
}

test containsAtLeast {
    try testing.expect(containsAtLeast(u8, "aa", 0, "a"));
    try testing.expect(containsAtLeast(u8, "aa", 1, "a"));
    try testing.expect(containsAtLeast(u8, "aa", 2, "a"));
    try testing.expect(!containsAtLeast(u8, "aa", 3, "a"));

    try testing.expect(containsAtLeast(u8, "radaradar", 1, "radar"));
    try testing.expect(!containsAtLeast(u8, "radaradar", 2, "radar"));

    try testing.expect(containsAtLeast(u8, "radarradaradarradar", 3, "radar"));
    try testing.expect(!containsAtLeast(u8, "radarradaradarradar", 4, "radar"));

    try testing.expect(containsAtLeast(u8, "   radar      radar   ", 2, "radar"));
    try testing.expect(!containsAtLeast(u8, "   radar      radar   ", 3, "radar"));
}

/// Deprecated in favor of `containsAtLeastScalar2`.
pub fn containsAtLeastScalar(comptime T: type, list: []const T, minimum: usize, element: T) bool {
    return containsAtLeastScalar2(T, list, element, minimum);
}

/// Returns true if `element` appears at least `minimum` number of times in `list`.
//
/// Related:
/// * `containsAtLeast`
/// * `countScalar`
pub fn containsAtLeastScalar2(comptime T: type, list: []const T, element: T, minimum: usize) bool {
    const n = list.len;
    var i: usize = 0;
    var found: usize = 0;

    if (use_vectors_for_comparison and
        (@typeInfo(T) == .int or @typeInfo(T) == .float) and std.math.isPowerOfTwo(@bitSizeOf(T)))
    {
        if (std.simd.suggestVectorLength(T)) |block_size| {
            const Block = @Vector(block_size, T);

            const letter_mask: Block = @splat(element);
            while (n - i >= block_size) : (i += block_size) {
                const haystack_block: Block = list[i..][0..block_size].*;
                found += std.simd.countTrues(letter_mask == haystack_block);
                if (found >= minimum) return true;
            }
        }
    }

    for (list[i..n]) |item| {
        found += @intFromBool(item == element);
        if (found >= minimum) return true;
    }

    return false;
}

test containsAtLeastScalar2 {
    try testing.expect(containsAtLeastScalar2(u8, "aa", 'a', 0));
    try testing.expect(containsAtLeastScalar2(u8, "aa", 'a', 1));
    try testing.expect(containsAtLeastScalar2(u8, "aa", 'a', 2));
    try testing.expect(!containsAtLeastScalar2(u8, "aa", 'a', 3));

    try testing.expect(containsAtLeastScalar2(u8, "adadda", 'd', 3));
    try testing.expect(!containsAtLeastScalar2(u8, "adadda", 'd', 4));
}

/// Reads an integer from memory with size equal to bytes.len.
/// T specifies the return type, which must be large enough to store
/// the result.
pub fn readVarInt(comptime ReturnType: type, bytes: []const u8, endian: Endian) ReturnType {
    assert(@typeInfo(ReturnType).int.bits >= bytes.len * 8);
    const bits = @typeInfo(ReturnType).int.bits;
    const signedness = @typeInfo(ReturnType).int.signedness;
    const WorkType = std.meta.Int(signedness, @max(16, bits));
    var result: WorkType = 0;
    switch (endian) {
        .big => {
            for (bytes) |b| {
                result = (result << 8) | b;
            }
        },
        .little => {
            const ShiftType = math.Log2Int(WorkType);
            for (bytes, 0..) |b, index| {
                result = result | (@as(WorkType, b) << @as(ShiftType, @intCast(index * 8)));
            }
        },
    }
    return @truncate(result);
}

test readVarInt {
    try testing.expect(readVarInt(u0, &[_]u8{}, .big) == 0x0);
    try testing.expect(readVarInt(u0, &[_]u8{}, .little) == 0x0);
    try testing.expect(readVarInt(u8, &[_]u8{0x12}, .big) == 0x12);
    try testing.expect(readVarInt(u8, &[_]u8{0xde}, .little) == 0xde);
    try testing.expect(readVarInt(u16, &[_]u8{ 0x12, 0x34 }, .big) == 0x1234);
    try testing.expect(readVarInt(u16, &[_]u8{ 0x12, 0x34 }, .little) == 0x3412);

    try testing.expect(readVarInt(i8, &[_]u8{0xff}, .big) == -1);
    try testing.expect(readVarInt(i8, &[_]u8{0xfe}, .little) == -2);
    try testing.expect(readVarInt(i16, &[_]u8{ 0xff, 0xfd }, .big) == -3);
    try testing.expect(readVarInt(i16, &[_]u8{ 0xfc, 0xff }, .little) == -4);

    // Return type can be oversized (bytes.len * 8 < @typeInfo(ReturnType).int.bits)
    try testing.expect(readVarInt(u9, &[_]u8{0x12}, .little) == 0x12);
    try testing.expect(readVarInt(u9, &[_]u8{0xde}, .big) == 0xde);
    try testing.expect(readVarInt(u80, &[_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0, 0x24 }, .big) == 0x123456789abcdef024);
    try testing.expect(readVarInt(u80, &[_]u8{ 0xec, 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe }, .little) == 0xfedcba9876543210ec);

    try testing.expect(readVarInt(i9, &[_]u8{0xff}, .big) == 0xff);
    try testing.expect(readVarInt(i9, &[_]u8{0xfe}, .little) == 0xfe);
}

/// Loads an integer from packed memory with provided bit_count, bit_offset, and signedness.
/// Asserts that T is large enough to store the read value.
pub fn readVarPackedInt(
    comptime T: type,
    bytes: []const u8,
    bit_offset: usize,
    bit_count: usize,
    endian: std.builtin.Endian,
    signedness: std.builtin.Signedness,
) T {
    const uN = std.meta.Int(.unsigned, @bitSizeOf(T));
    const iN = std.meta.Int(.signed, @bitSizeOf(T));
    const Log2N = std.math.Log2Int(T);

    const read_size = (bit_count + (bit_offset % 8) + 7) / 8;
    const bit_shift = @as(u3, @intCast(bit_offset % 8));
    const pad = @as(Log2N, @intCast(@bitSizeOf(T) - bit_count));

    const lowest_byte = switch (endian) {
        .big => bytes.len - (bit_offset / 8) - read_size,
        .little => bit_offset / 8,
    };
    const read_bytes = bytes[lowest_byte..][0..read_size];

    if (@bitSizeOf(T) <= 8) {
        // These are the same shifts/masks we perform below, but adds `@truncate`/`@intCast`
        // where needed since int is smaller than a byte.
        const value = if (read_size == 1) b: {
            break :b @as(uN, @truncate(read_bytes[0] >> bit_shift));
        } else b: {
            const i: u1 = @intFromBool(endian == .big);
            const head = @as(uN, @truncate(read_bytes[i] >> bit_shift));
            const tail_shift = @as(Log2N, @intCast(@as(u4, 8) - bit_shift));
            const tail = @as(uN, @truncate(read_bytes[1 - i]));
            break :b (tail << tail_shift) | head;
        };
        switch (signedness) {
            .signed => return @as(T, @intCast((@as(iN, @bitCast(value)) << pad) >> pad)),
            .unsigned => return @as(T, @intCast((@as(uN, @bitCast(value)) << pad) >> pad)),
        }
    }

    // Copy the value out (respecting endianness), accounting for bit_shift
    var int: uN = 0;
    switch (endian) {
        .big => {
            for (read_bytes[0 .. read_size - 1]) |elem| {
                int = elem | (int << 8);
            }
            int = (read_bytes[read_size - 1] >> bit_shift) | (int << (@as(u4, 8) - bit_shift));
        },
        .little => {
            int = read_bytes[0] >> bit_shift;
            for (read_bytes[1..], 0..) |elem, i| {
                int |= (@as(uN, elem) << @as(Log2N, @intCast((8 * (i + 1) - bit_shift))));
            }
        },
    }
    switch (signedness) {
        .signed => return @as(T, @intCast((@as(iN, @bitCast(int)) << pad) >> pad)),
        .unsigned => return @as(T, @intCast((@as(uN, @bitCast(int)) << pad) >> pad)),
    }
}

test readVarPackedInt {
    const T = packed struct(u16) { a: u3, b: u7, c: u6 };
    var st = T{ .a = 1, .b = 2, .c = 4 };
    const b_field = readVarPackedInt(u64, std.mem.asBytes(&st), @bitOffsetOf(T, "b"), 7, builtin.cpu.arch.endian(), .unsigned);
    try std.testing.expectEqual(st.b, b_field);
}

/// Reads an integer from memory with bit count specified by T.
/// The bit count of T must be evenly divisible by 8.
/// This function cannot fail and cannot cause undefined behavior.
pub inline fn readInt(comptime T: type, buffer: *const [@divExact(@typeInfo(T).int.bits, 8)]u8, endian: Endian) T {
    const value: T = @bitCast(buffer.*);
    return if (endian == native_endian) value else @byteSwap(value);
}

test readInt {
    try testing.expect(readInt(u0, &[_]u8{}, .big) == 0x0);
    try testing.expect(readInt(u0, &[_]u8{}, .little) == 0x0);

    try testing.expect(readInt(u8, &[_]u8{0x32}, .big) == 0x32);
    try testing.expect(readInt(u8, &[_]u8{0x12}, .little) == 0x12);

    try testing.expect(readInt(u16, &[_]u8{ 0x12, 0x34 }, .big) == 0x1234);
    try testing.expect(readInt(u16, &[_]u8{ 0x12, 0x34 }, .little) == 0x3412);

    try testing.expect(readInt(u72, &[_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0, 0x24 }, .big) == 0x123456789abcdef024);
    try testing.expect(readInt(u72, &[_]u8{ 0xec, 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe }, .little) == 0xfedcba9876543210ec);

    try testing.expect(readInt(i8, &[_]u8{0xff}, .big) == -1);
    try testing.expect(readInt(i8, &[_]u8{0xfe}, .little) == -2);

    try testing.expect(readInt(i16, &[_]u8{ 0xff, 0xfd }, .big) == -3);
    try testing.expect(readInt(i16, &[_]u8{ 0xfc, 0xff }, .little) == -4);

    try moreReadIntTests();
    try comptime moreReadIntTests();
}

fn readPackedIntLittle(comptime T: type, bytes: []const u8, bit_offset: usize) T {
    const uN = std.meta.Int(.unsigned, @bitSizeOf(T));
    const Log2N = std.math.Log2Int(T);

    const bit_count = @as(usize, @bitSizeOf(T));
    const bit_shift = @as(u3, @intCast(bit_offset % 8));

    const load_size = (bit_count + 7) / 8;
    const load_tail_bits = @as(u3, @intCast((load_size * 8) - bit_count));
    const LoadInt = std.meta.Int(.unsigned, load_size * 8);

    if (bit_count == 0)
        return 0;

    // Read by loading a LoadInt, and then follow it up with a 1-byte read
    // of the tail if bit_offset pushed us over a byte boundary.
    const read_bytes = bytes[bit_offset / 8 ..];
    const val = @as(uN, @truncate(readInt(LoadInt, read_bytes[0..load_size], .little) >> bit_shift));
    if (bit_shift > load_tail_bits) {
        const tail_bits = @as(Log2N, @intCast(bit_shift - load_tail_bits));
        const tail_byte = read_bytes[load_size];
        const tail_truncated = if (bit_count < 8) @as(uN, @truncate(tail_byte)) else @as(uN, tail_byte);
        return @as(T, @bitCast(val | (tail_truncated << (@as(Log2N, @truncate(bit_count)) -% tail_bits))));
    } else return @as(T, @bitCast(val));
}

fn readPackedIntBig(comptime T: type, bytes: []const u8, bit_offset: usize) T {
    const uN = std.meta.Int(.unsigned, @bitSizeOf(T));
    const Log2N = std.math.Log2Int(T);

    const bit_count = @as(usize, @bitSizeOf(T));
    const bit_shift = @as(u3, @intCast(bit_offset % 8));
    const byte_count = (@as(usize, bit_shift) + bit_count + 7) / 8;

    const load_size = (bit_count + 7) / 8;
    const load_tail_bits = @as(u3, @intCast((load_size * 8) - bit_count));
    const LoadInt = std.meta.Int(.unsigned, load_size * 8);

    if (bit_count == 0)
        return 0;

    // Read by loading a LoadInt, and then follow it up with a 1-byte read
    // of the tail if bit_offset pushed us over a byte boundary.
    const end = bytes.len - (bit_offset / 8);
    const read_bytes = bytes[(end - byte_count)..end];
    const val = @as(uN, @truncate(readInt(LoadInt, bytes[(end - load_size)..end][0..load_size], .big) >> bit_shift));
    if (bit_shift > load_tail_bits) {
        const tail_bits = @as(Log2N, @intCast(bit_shift - load_tail_bits));
        const tail_byte = if (bit_count < 8) @as(uN, @truncate(read_bytes[0])) else @as(uN, read_bytes[0]);
        return @as(T, @bitCast(val | (tail_byte << (@as(Log2N, @truncate(bit_count)) -% tail_bits))));
    } else return @as(T, @bitCast(val));
}

pub const readPackedIntNative = switch (native_endian) {
    .little => readPackedIntLittle,
    .big => readPackedIntBig,
};

pub const readPackedIntForeign = switch (native_endian) {
    .little => readPackedIntBig,
    .big => readPackedIntLittle,
};

/// Loads an integer from packed memory.
/// Asserts that buffer contains at least bit_offset + @bitSizeOf(T) bits.
pub fn readPackedInt(comptime T: type, bytes: []const u8, bit_offset: usize, endian: Endian) T {
    switch (endian) {
        .little => return readPackedIntLittle(T, bytes, bit_offset),
        .big => return readPackedIntBig(T, bytes, bit_offset),
    }
}

test readPackedInt {
    const T = packed struct(u16) { a: u3, b: u7, c: u6 };
    var st = T{ .a = 1, .b = 2, .c = 4 };
    const b_field = readPackedInt(u7, std.mem.asBytes(&st), @bitOffsetOf(T, "b"), builtin.cpu.arch.endian());
    try std.testing.expectEqual(st.b, b_field);
}

test "comptime read/write int" {
    comptime {
        var bytes: [2]u8 = undefined;
        writeInt(u16, &bytes, 0x1234, .little);
        const result = readInt(u16, &bytes, .big);
        try testing.expect(result == 0x3412);
    }
    comptime {
        var bytes: [2]u8 = undefined;
        writeInt(u16, &bytes, 0x1234, .big);
        const result = readInt(u16, &bytes, .little);
        try testing.expect(result == 0x3412);
    }
}

/// Writes an integer to memory, storing it in twos-complement.
/// This function always succeeds, has defined behavior for all inputs, but
/// the integer bit width must be divisible by 8.
pub inline fn writeInt(comptime T: type, buffer: *[@divExact(@typeInfo(T).int.bits, 8)]u8, value: T, endian: Endian) void {
    buffer.* = @bitCast(if (endian == native_endian) value else @byteSwap(value));
}

test writeInt {
    var buf0: [0]u8 = undefined;
    var buf1: [1]u8 = undefined;
    var buf2: [2]u8 = undefined;
    var buf9: [9]u8 = undefined;

    writeInt(u0, &buf0, 0x0, .big);
    try testing.expect(eql(u8, buf0[0..], &[_]u8{}));
    writeInt(u0, &buf0, 0x0, .little);
    try testing.expect(eql(u8, buf0[0..], &[_]u8{}));

    writeInt(u8, &buf1, 0x12, .big);
    try testing.expect(eql(u8, buf1[0..], &[_]u8{0x12}));
    writeInt(u8, &buf1, 0x34, .little);
    try testing.expect(eql(u8, buf1[0..], &[_]u8{0x34}));

    writeInt(u16, &buf2, 0x1234, .big);
    try testing.expect(eql(u8, buf2[0..], &[_]u8{ 0x12, 0x34 }));
    writeInt(u16, &buf2, 0x5678, .little);
    try testing.expect(eql(u8, buf2[0..], &[_]u8{ 0x78, 0x56 }));

    writeInt(u72, &buf9, 0x123456789abcdef024, .big);
    try testing.expect(eql(u8, buf9[0..], &[_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0, 0x24 }));
    writeInt(u72, &buf9, 0xfedcba9876543210ec, .little);
    try testing.expect(eql(u8, buf9[0..], &[_]u8{ 0xec, 0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe }));

    writeInt(i8, &buf1, -1, .big);
    try testing.expect(eql(u8, buf1[0..], &[_]u8{0xff}));
    writeInt(i8, &buf1, -2, .little);
    try testing.expect(eql(u8, buf1[0..], &[_]u8{0xfe}));

    writeInt(i16, &buf2, -3, .big);
    try testing.expect(eql(u8, buf2[0..], &[_]u8{ 0xff, 0xfd }));
    writeInt(i16, &buf2, -4, .little);
    try testing.expect(eql(u8, buf2[0..], &[_]u8{ 0xfc, 0xff }));
}

fn writePackedIntLittle(comptime T: type, bytes: []u8, bit_offset: usize, value: T) void {
    const uN = std.meta.Int(.unsigned, @bitSizeOf(T));
    const Log2N = std.math.Log2Int(T);

    const bit_count = @as(usize, @bitSizeOf(T));
    const bit_shift = @as(u3, @intCast(bit_offset % 8));

    const store_size = (@bitSizeOf(T) + 7) / 8;
    const store_tail_bits = @as(u3, @intCast((store_size * 8) - bit_count));
    const StoreInt = std.meta.Int(.unsigned, store_size * 8);

    if (bit_count == 0)
        return;

    // Write by storing a StoreInt, and then follow it up with a 1-byte tail
    // if bit_offset pushed us over a byte boundary.
    const write_bytes = bytes[bit_offset / 8 ..];
    const head = write_bytes[0] & ((@as(u8, 1) << bit_shift) - 1);

    var write_value = (@as(StoreInt, @as(uN, @bitCast(value))) << bit_shift) | @as(StoreInt, @intCast(head));
    if (bit_shift > store_tail_bits) {
        const tail_len = @as(Log2N, @intCast(bit_shift - store_tail_bits));
        write_bytes[store_size] &= ~((@as(u8, 1) << @as(u3, @intCast(tail_len))) - 1);
        write_bytes[store_size] |= @as(u8, @intCast((@as(uN, @bitCast(value)) >> (@as(Log2N, @truncate(bit_count)) -% tail_len))));
    } else if (bit_shift < store_tail_bits) {
        const tail_len = store_tail_bits - bit_shift;
        const tail = write_bytes[store_size - 1] & (@as(u8, 0xfe) << (7 - tail_len));
        write_value |= @as(StoreInt, tail) << (8 * (store_size - 1));
    }

    writeInt(StoreInt, write_bytes[0..store_size], write_value, .little);
}

fn writePackedIntBig(comptime T: type, bytes: []u8, bit_offset: usize, value: T) void {
    const uN = std.meta.Int(.unsigned, @bitSizeOf(T));
    const Log2N = std.math.Log2Int(T);

    const bit_count = @as(usize, @bitSizeOf(T));
    const bit_shift = @as(u3, @intCast(bit_offset % 8));
    const byte_count = (bit_shift + bit_count + 7) / 8;

    const store_size = (@bitSizeOf(T) + 7) / 8;
    const store_tail_bits = @as(u3, @intCast((store_size * 8) - bit_count));
    const StoreInt = std.meta.Int(.unsigned, store_size * 8);

    if (bit_count == 0)
        return;

    // Write by storing a StoreInt, and then follow it up with a 1-byte tail
    // if bit_offset pushed us over a byte boundary.
    const end = bytes.len - (bit_offset / 8);
    const write_bytes = bytes[(end - byte_count)..end];
    const head = write_bytes[byte_count - 1] & ((@as(u8, 1) << bit_shift) - 1);

    var write_value = (@as(StoreInt, @as(uN, @bitCast(value))) << bit_shift) | @as(StoreInt, @intCast(head));
    if (bit_shift > store_tail_bits) {
        const tail_len = @as(Log2N, @intCast(bit_shift - store_tail_bits));
        write_bytes[0] &= ~((@as(u8, 1) << @as(u3, @intCast(tail_len))) - 1);
        write_bytes[0] |= @as(u8, @intCast((@as(uN, @bitCast(value)) >> (@as(Log2N, @truncate(bit_count)) -% tail_len))));
    } else if (bit_shift < store_tail_bits) {
        const tail_len = store_tail_bits - bit_shift;
        const tail = write_bytes[0] & (@as(u8, 0xfe) << (7 - tail_len));
        write_value |= @as(StoreInt, tail) << (8 * (store_size - 1));
    }

    writeInt(StoreInt, write_bytes[(byte_count - store_size)..][0..store_size], write_value, .big);
}

pub const writePackedIntNative = switch (native_endian) {
    .little => writePackedIntLittle,
    .big => writePackedIntBig,
};

pub const writePackedIntForeign = switch (native_endian) {
    .little => writePackedIntBig,
    .big => writePackedIntLittle,
};

/// Stores an integer to packed memory.
/// Asserts that buffer contains at least bit_offset + @bitSizeOf(T) bits.
pub fn writePackedInt(comptime T: type, bytes: []u8, bit_offset: usize, value: T, endian: Endian) void {
    switch (endian) {
        .little => writePackedIntLittle(T, bytes, bit_offset, value),
        .big => writePackedIntBig(T, bytes, bit_offset, value),
    }
}

test writePackedInt {
    const T = packed struct(u16) { a: u3, b: u7, c: u6 };
    var st = T{ .a = 1, .b = 2, .c = 4 };
    writePackedInt(u7, std.mem.asBytes(&st), @bitOffsetOf(T, "b"), 0x7f, builtin.cpu.arch.endian());
    try std.testing.expectEqual(T{ .a = 1, .b = 0x7f, .c = 4 }, st);
}

/// Stores an integer to packed memory with provided bit_offset, bit_count, and signedness.
/// If negative, the written value is sign-extended.
pub fn writeVarPackedInt(bytes: []u8, bit_offset: usize, bit_count: usize, value: anytype, endian: std.builtin.Endian) void {
    const T = @TypeOf(value);
    const uN = std.meta.Int(.unsigned, @bitSizeOf(T));

    const bit_shift = @as(u3, @intCast(bit_offset % 8));
    const write_size = (bit_count + bit_shift + 7) / 8;
    const lowest_byte = switch (endian) {
        .big => bytes.len - (bit_offset / 8) - write_size,
        .little => bit_offset / 8,
    };
    const write_bytes = bytes[lowest_byte..][0..write_size];

    if (write_size == 0) {
        return;
    } else if (write_size == 1) {
        // Single byte writes are handled specially, since we need to mask bits
        // on both ends of the byte.
        const mask = (@as(u8, 0xff) >> @as(u3, @intCast(8 - bit_count)));
        const new_bits = @as(u8, @intCast(@as(uN, @bitCast(value)) & mask)) << bit_shift;
        write_bytes[0] = (write_bytes[0] & ~(mask << bit_shift)) | new_bits;
        return;
    }

    var remaining: T = value;

    // Iterate bytes forward for Little-endian, backward for Big-endian
    const delta: i2 = if (endian == .big) -1 else 1;
    const start = if (endian == .big) @as(isize, @intCast(write_bytes.len - 1)) else 0;

    var i: isize = start; // isize for signed index arithmetic

    // Write first byte, using a mask to protects bits preceding bit_offset
    const head_mask = @as(u8, 0xff) >> bit_shift;
    write_bytes[@intCast(i)] &= ~(head_mask << bit_shift);
    write_bytes[@intCast(i)] |= @as(u8, @intCast(@as(uN, @bitCast(remaining)) & head_mask)) << bit_shift;
    remaining = math.shr(T, remaining, @as(u4, 8) - bit_shift);
    i += delta;

    // Write bytes[1..bytes.len - 1]
    if (@bitSizeOf(T) > 8) {
        const loop_end = start + delta * (@as(isize, @intCast(write_size)) - 1);
        while (i != loop_end) : (i += delta) {
            write_bytes[@as(usize, @intCast(i))] = @as(u8, @truncate(@as(uN, @bitCast(remaining))));
            remaining >>= 8;
        }
    }

    // Write last byte, using a mask to protect bits following bit_offset + bit_count
    const following_bits = -%@as(u3, @truncate(bit_shift + bit_count));
    const tail_mask = (@as(u8, 0xff) << following_bits) >> following_bits;
    write_bytes[@as(usize, @intCast(i))] &= ~tail_mask;
    write_bytes[@as(usize, @intCast(i))] |= @as(u8, @intCast(@as(uN, @bitCast(remaining)) & tail_mask));
}

test writeVarPackedInt {
    const T = packed struct(u16) { a: u3, b: u7, c: u6 };
    var st = T{ .a = 1, .b = 2, .c = 4 };
    const value: u64 = 0x7f;
    writeVarPackedInt(std.mem.asBytes(&st), @bitOffsetOf(T, "b"), 7, value, builtin.cpu.arch.endian());
    try testing.expectEqual(T{ .a = 1, .b = value, .c = 4 }, st);
}

/// Swap the byte order of all the members of the fields of a struct
/// (Changing their endianness)
pub fn byteSwapAllFields(comptime S: type, ptr: *S) void {
    switch (@typeInfo(S)) {
        .@"struct" => {
            inline for (std.meta.fields(S)) |f| {
                switch (@typeInfo(f.type)) {
                    .@"struct" => |struct_info| if (struct_info.backing_integer) |Int| {
                        @field(ptr, f.name) = @bitCast(@byteSwap(@as(Int, @bitCast(@field(ptr, f.name)))));
                    } else {
                        byteSwapAllFields(f.type, &@field(ptr, f.name));
                    },
                    .@"union", .array => byteSwapAllFields(f.type, &@field(ptr, f.name)),
                    .@"enum" => {
                        @field(ptr, f.name) = @enumFromInt(@byteSwap(@intFromEnum(@field(ptr, f.name))));
                    },
                    .bool => {},
                    .float => |float_info| {
                        @field(ptr, f.name) = @bitCast(@byteSwap(@as(std.meta.Int(.unsigned, float_info.bits), @bitCast(@field(ptr, f.name)))));
                    },
                    else => {
                        @field(ptr, f.name) = @byteSwap(@field(ptr, f.name));
                    },
                }
            }
        },
        .@"union" => |union_info| {
            if (union_info.tag_type != null) {
                @compileError("byteSwapAllFields expects an untagged union");
            }

            const first_size = @bitSizeOf(union_info.fields[0].type);
            inline for (union_info.fields) |field| {
                if (@bitSizeOf(field.type) != first_size) {
                    @compileError("Unable to byte-swap unions with varying field sizes");
                }
            }

            const BackingInt = std.meta.Int(.unsigned, @bitSizeOf(S));
            ptr.* = @bitCast(@byteSwap(@as(BackingInt, @bitCast(ptr.*))));
        },
        .array => |info| {
            byteSwapAllElements(info.child, ptr);
        },
        else => {
            ptr.* = @byteSwap(ptr.*);
        },
    }
}

test byteSwapAllFields {
    const T = extern struct {
        f0: u8,
        f1: u16,
        f2: u32,
        f3: [1]u8,
        f4: bool,
        f5: f32,
        f6: extern union { f0: u16, f1: u16 },
    };
    const K = extern struct {
        f0: u8,
        f1: T,
        f2: u16,
        f3: [1]u8,
        f4: bool,
        f5: f32,
    };
    var s = T{
        .f0 = 0x12,
        .f1 = 0x1234,
        .f2 = 0x12345678,
        .f3 = .{0x12},
        .f4 = true,
        .f5 = @as(f32, @bitCast(@as(u32, 0x4640e400))),
        .f6 = .{ .f0 = 0x1234 },
    };
    var k = K{
        .f0 = 0x12,
        .f1 = s,
        .f2 = 0x1234,
        .f3 = .{0x12},
        .f4 = false,
        .f5 = @as(f32, @bitCast(@as(u32, 0x45d42800))),
    };
    byteSwapAllFields(T, &s);
    byteSwapAllFields(K, &k);
    try std.testing.expectEqual(T{
        .f0 = 0x12,
        .f1 = 0x3412,
        .f2 = 0x78563412,
        .f3 = .{0x12},
        .f4 = true,
        .f5 = @as(f32, @bitCast(@as(u32, 0x00e44046))),
        .f6 = .{ .f0 = 0x3412 },
    }, s);
    try std.testing.expectEqual(K{
        .f0 = 0x12,
        .f1 = s,
        .f2 = 0x3412,
        .f3 = .{0x12},
        .f4 = false,
        .f5 = @as(f32, @bitCast(@as(u32, 0x0028d445))),
    }, k);
}

/// Reverses the byte order of all elements in a slice.
/// Handles structs, unions, arrays, enums, floats, and integers recursively.
/// Useful for converting between little-endian and big-endian representations.
pub fn byteSwapAllElements(comptime Elem: type, slice: []Elem) void {
    for (slice) |*elem| {
        switch (@typeInfo(@TypeOf(elem.*))) {
            .@"struct", .@"union", .array => byteSwapAllFields(@TypeOf(elem.*), elem),
            .@"enum" => {
                elem.* = @enumFromInt(@byteSwap(@intFromEnum(elem.*)));
            },
            .bool => {},
            .float => |float_info| {
                elem.* = @bitCast(@byteSwap(@as(std.meta.Int(.unsigned, float_info.bits), @bitCast(elem.*))));
            },
            else => {
                elem.* = @byteSwap(elem.*);
            },
        }
    }
}

/// Returns an iterator that iterates over the slices of `buffer` that are not
/// any of the items in `delimiters`.
///
/// `tokenizeAny(u8, "   abc|def ||  ghi  ", " |")` will return slices
/// for "abc", "def", "ghi", null, in that order.
///
/// If `buffer` is empty, the iterator will return null.
/// If none of `delimiters` exist in buffer,
/// the iterator will return `buffer`, null, in that order.
///
/// See also: `tokenizeSequence`, `tokenizeScalar`,
///           `splitSequence`,`splitAny`, `splitScalar`,
///           `splitBackwardsSequence`, `splitBackwardsAny`, and `splitBackwardsScalar`
pub fn tokenizeAny(comptime T: type, buffer: []const T, delimiters: []const T) TokenIterator(T, .any) {
    return .{
        .index = 0,
        .buffer = buffer,
        .delimiter = delimiters,
    };
}

/// Returns an iterator that iterates over the slices of `buffer` that are not
/// the sequence in `delimiter`.
///
/// `tokenizeSequence(u8, "<>abc><def<><>ghi", "<>")` will return slices
/// for "abc><def", "ghi", null, in that order.
///
/// If `buffer` is empty, the iterator will return null.
/// If `delimiter` does not exist in buffer,
/// the iterator will return `buffer`, null, in that order.
/// The delimiter length must not be zero.
///
/// See also: `tokenizeAny`, `tokenizeScalar`,
///           `splitSequence`,`splitAny`, and `splitScalar`
///           `splitBackwardsSequence`, `splitBackwardsAny`, and `splitBackwardsScalar`
pub fn tokenizeSequence(comptime T: type, buffer: []const T, delimiter: []const T) TokenIterator(T, .sequence) {
    assert(delimiter.len != 0);
    return .{
        .index = 0,
        .buffer = buffer,
        .delimiter = delimiter,
    };
}

/// Returns an iterator that iterates over the slices of `buffer` that are not
/// `delimiter`.
///
/// `tokenizeScalar(u8, "   abc def     ghi  ", ' ')` will return slices
/// for "abc", "def", "ghi", null, in that order.
///
/// If `buffer` is empty, the iterator will return null.
/// If `delimiter` does not exist in buffer,
/// the iterator will return `buffer`, null, in that order.
///
/// See also: `tokenizeAny`, `tokenizeSequence`,
///           `splitSequence`,`splitAny`, and `splitScalar`
///           `splitBackwardsSequence`, `splitBackwardsAny`, and `splitBackwardsScalar`
pub fn tokenizeScalar(comptime T: type, buffer: []const T, delimiter: T) TokenIterator(T, .scalar) {
    return .{
        .index = 0,
        .buffer = buffer,
        .delimiter = delimiter,
    };
}

test tokenizeScalar {
    var it = tokenizeScalar(u8, "   abc def   ghi  ", ' ');
    try testing.expect(eql(u8, it.next().?, "abc"));
    try testing.expect(eql(u8, it.peek().?, "def"));
    try testing.expect(eql(u8, it.next().?, "def"));
    try testing.expect(eql(u8, it.next().?, "ghi"));
    try testing.expect(it.next() == null);

    it = tokenizeScalar(u8, "..\\bob", '\\');
    try testing.expect(eql(u8, it.next().?, ".."));
    try testing.expect(eql(u8, "..", "..\\bob"[0..it.index]));
    try testing.expect(eql(u8, it.next().?, "bob"));
    try testing.expect(it.next() == null);

    it = tokenizeScalar(u8, "//a/b", '/');
    try testing.expect(eql(u8, it.next().?, "a"));
    try testing.expect(eql(u8, it.next().?, "b"));
    try testing.expect(eql(u8, "//a/b", "//a/b"[0..it.index]));
    try testing.expect(it.next() == null);

    it = tokenizeScalar(u8, "|", '|');
    try testing.expect(it.next() == null);
    try testing.expect(it.peek() == null);

    it = tokenizeScalar(u8, "", '|');
    try testing.expect(it.next() == null);
    try testing.expect(it.peek() == null);

    it = tokenizeScalar(u8, "hello", ' ');
    try testing.expect(eql(u8, it.next().?, "hello"));
    try testing.expect(it.next() == null);

    var it16 = tokenizeScalar(
        u16,
        std.unicode.utf8ToUtf16LeStringLiteral("hello"),
        ' ',
    );
    try testing.expect(eql(u16, it16.next().?, std.unicode.utf8ToUtf16LeStringLiteral("hello")));
    try testing.expect(it16.next() == null);
}

test tokenizeAny {
    var it = tokenizeAny(u8, "a|b,c/d e", " /,|");
    try testing.expect(eql(u8, it.next().?, "a"));
    try testing.expect(eql(u8, it.peek().?, "b"));
    try testing.expect(eql(u8, it.next().?, "b"));
    try testing.expect(eql(u8, it.next().?, "c"));
    try testing.expect(eql(u8, it.next().?, "d"));
    try testing.expect(eql(u8, it.next().?, "e"));
    try testing.expect(it.next() == null);
    try testing.expect(it.peek() == null);

    it = tokenizeAny(u8, "hello", "");
    try testing.expect(eql(u8, it.next().?, "hello"));
    try testing.expect(it.next() == null);

    var it16 = tokenizeAny(
        u16,
        std.unicode.utf8ToUtf16LeStringLiteral("a|b,c/d e"),
        std.unicode.utf8ToUtf16LeStringLiteral(" /,|"),
    );
    try testing.expect(eql(u16, it16.next().?, std.unicode.utf8ToUtf16LeStringLiteral("a")));
    try testing.expect(eql(u16, it16.next().?, std.unicode.utf8ToUtf16LeStringLiteral("b")));
    try testing.expect(eql(u16, it16.next().?, std.unicode.utf8ToUtf16LeStringLiteral("c")));
    try testing.expect(eql(u16, it16.next().?, std.unicode.utf8ToUtf16LeStringLiteral("d")));
    try testing.expect(eql(u16, it16.next().?, std.unicode.utf8ToUtf16LeStringLiteral("e")));
    try testing.expect(it16.next() == null);
}

test tokenizeSequence {
    var it = tokenizeSequence(u8, "a<>b<><>c><>d><", "<>");
    try testing.expectEqualStrings("a", it.next().?);
    try testing.expectEqualStrings("b", it.peek().?);
    try testing.expectEqualStrings("b", it.next().?);
    try testing.expectEqualStrings("c>", it.next().?);
    try testing.expectEqualStrings("d><", it.next().?);
    try testing.expect(it.next() == null);
    try testing.expect(it.peek() == null);

    var it16 = tokenizeSequence(
        u16,
        std.unicode.utf8ToUtf16LeStringLiteral("a<>b<><>c><>d><"),
        std.unicode.utf8ToUtf16LeStringLiteral("<>"),
    );
    try testing.expect(eql(u16, it16.next().?, std.unicode.utf8ToUtf16LeStringLiteral("a")));
    try testing.expect(eql(u16, it16.next().?, std.unicode.utf8ToUtf16LeStringLiteral("b")));
    try testing.expect(eql(u16, it16.next().?, std.unicode.utf8ToUtf16LeStringLiteral("c>")));
    try testing.expect(eql(u16, it16.next().?, std.unicode.utf8ToUtf16LeStringLiteral("d><")));
    try testing.expect(it16.next() == null);
}

test "tokenize (reset)" {
    {
        var it = tokenizeAny(u8, "   abc def   ghi  ", " ");
        try testing.expect(eql(u8, it.next().?, "abc"));
        try testing.expect(eql(u8, it.next().?, "def"));
        try testing.expect(eql(u8, it.next().?, "ghi"));

        it.reset();

        try testing.expect(eql(u8, it.next().?, "abc"));
        try testing.expect(eql(u8, it.next().?, "def"));
        try testing.expect(eql(u8, it.next().?, "ghi"));
        try testing.expect(it.next() == null);
    }
    {
        var it = tokenizeSequence(u8, "<><>abc<>def<><>ghi<>", "<>");
        try testing.expect(eql(u8, it.next().?, "abc"));
        try testing.expect(eql(u8, it.next().?, "def"));
        try testing.expect(eql(u8, it.next().?, "ghi"));

        it.reset();

        try testing.expect(eql(u8, it.next().?, "abc"));
        try testing.expect(eql(u8, it.next().?, "def"));
        try testing.expect(eql(u8, it.next().?, "ghi"));
        try testing.expect(it.next() == null);
    }
    {
        var it = tokenizeScalar(u8, "   abc def   ghi  ", ' ');
        try testing.expect(eql(u8, it.next().?, "abc"));
        try testing.expect(eql(u8, it.next().?, "def"));
        try testing.expect(eql(u8, it.next().?, "ghi"));

        it.reset();

        try testing.expect(eql(u8, it.next().?, "abc"));
        try testing.expect(eql(u8, it.next().?, "def"));
        try testing.expect(eql(u8, it.next().?, "ghi"));
        try testing.expect(it.next() == null);
    }
}

/// Re
