/**
 * This module contains a collection of bit-level operations.
 *
 * Copyright: Copyright Don Clugston 2005 - 2013.
 * License:   $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Authors:   Don Clugston, Sean Kelly, Walter Bright, Alex RÃ¸nne Petersen, Thomas Stuart Bockman
 * Source:    $(DRUNTIMESRC core/_bitop.d)
 */

module core.bitop;

nothrow:
@safe:
@nogc:

version (D_InlineAsm_X86_64)
    version = AsmX86;
else version (D_InlineAsm_X86)
    version = AsmX86;

version (X86_64)
    version = AnyX86;
else version (X86)
    version = AnyX86;

// Use to implement 64-bit bitops on 32-bit arch.
private union Split64
{
    ulong u64;
    struct
    {
        version (LittleEndian)
        {
            uint lo;
            uint hi;
        }
        else
        {
            uint hi;
            uint lo;
        }
    }

    pragma(inline, true)
    this(ulong u64) @safe pure nothrow @nogc
    {
        if (__ctfe)
        {
            lo = cast(uint) u64;
     
