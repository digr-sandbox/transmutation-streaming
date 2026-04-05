//! This file contains thin wrappers around OS-specific APIs, with these
//! specific goals in mind:
//! * Convert "errno"-style error codes into Zig errors.
//! * When null-terminated byte buffers are required, provide APIs which accept
//!   slices as well as APIs which accept null-terminated byte buffers. Same goes
//!   for WTF-16LE encoding.
//! * Where operating systems share APIs, e.g. POSIX, these thin wrappers provide
//!   cross platform abstracting.
//! * When there exists a corresponding libc function and linking libc, the libc
//!   implementation is used. Exceptions are made for known buggy areas of libc.
//!   On Linux libc can be side-stepped by using `std.os.linux` directly.
//! * For Windows, this file represents the API that libc would provide for
//!   Windows. For thin wrappers around Windows-specific APIs, see `std.os.windows`.

const root = @import("root");
const std = @import("std.zig");
const builtin = @import("builtin");
const assert = std.debug.assert;
const 
