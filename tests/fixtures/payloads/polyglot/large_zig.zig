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
           
