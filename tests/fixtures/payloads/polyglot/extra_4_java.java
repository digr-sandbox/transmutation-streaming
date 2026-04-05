/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.commons.lang3;

import java.io.UnsupportedEncodingException;
import java.nio.CharBuffer;
import java.nio.charset.Charset;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.Set;
import java.util.function.Supplier;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import org.apache.commons.lang3.function.Suppliers;
import org.apache.commons.lang3.stream.LangCollectors;
import org.apache.commons.lang3.stream.Streams;

/**
 * Operations on {@link String} that are
 * {@code null} safe.
 *
 * <ul>
 *  <li><strong>IsEmpty/IsBlank</strong>
 *      - checks if a String contains text</li>
 *  <li><strong>Trim/Strip</strong>
 *      - removes leading and trailing whitespace</li>
 *  <li><strong>Equals/Compare</strong>
 *      - compares two strings in a null-safe manner</li>
 *  <li><strong>startsWith</strong>
 *      - check if a String starts with a prefix in a null-safe manner</li>
 *  <li><strong>endsWith</strong>
 *      - check if a String ends with a suffix in a null-safe manner</li>
 *  <li><strong>IndexOf/LastIndexOf/Contains</strong>
 *      - null-safe index-of checks</li>
 *  <li><strong>IndexOfAny/LastIndexOfAny/IndexOfAnyBut/LastIndexOfAnyBut</strong>
 *      - index-of any of a set of Strings</li>
 *  <li><strong>ContainsOnly/ContainsNone/ContainsAny</strong>
 *      - checks if String contains only/none/any of these characters</li>
 *  <li><strong>Substring/Left/Right/Mid</strong>
 *      - null-safe substring extractions</li>
 *  <li><strong>SubstringBefore/SubstringAfter/SubstringBetween</strong>
 *      - substring extraction relative to other strings</li>
 *  <li><strong>Split/Join</strong>
 *      - splits a String into an array of substrings and vice versa</li>
 *  <li><strong>Remove/Delete</strong>
 *      - removes part of a String</li>
 *  <li><strong>Replace/Overlay</strong>
 *      - Searches a String and replaces one String with another</li>
 *  <li><strong>Chomp/Chop</strong>
 *      - removes the last part of a String</li>
 *  <li><strong>AppendIfMissing</strong>
 *      - appends a suffix to the end of the String if not present</li>
 *  <li><strong>PrependIfMissing</strong>
 *      - prepends a prefix to the start of the String if not present</li>
 *  <li><strong>LeftPad/RightPad/Center/Repeat</strong>
 *      - pads a String</li>
 *  <li><strong>UpperCase/LowerCase/SwapCase/Capitalize/Uncapitalize</strong>
 *      - changes the case of a String</li>
 *  <li><strong>CountMatches</strong>
 *      - counts the number of occurrences of one String in another</li>
 *  <li><strong>IsAlpha/IsNumeric/IsWhitespace/IsAsciiPrintable</strong>
 *      - checks the characters in a String</li>
 *  <li><strong>DefaultString</strong>
 *      - protects against a null input String</li>
 *  <li><strong>Rotate</strong>
 *      - rotate (circular shift) a String</li>
 *  <li><strong>Reverse/ReverseDelimited</strong>
 *      - reverses a String</li>
 *  <li><strong>Abbreviate</strong>
 *      - abbreviates a string using ellipses or another given String</li>
 *  <li><strong>Difference</strong>
 *      - compares Strings and reports on their differences</li>
 *  <li><strong>LevenshteinDistance</strong>
 *      - the number of changes needed to change one String into another</li>
 * </ul>
 *
 * <p>The {@link StringUtils} class defines certain words related to
 * String handling.</p>
 *
 * <ul>
 *  <li>null - {@code null}</li>
 *  <li>empty - a zero-length string ({@code ""})</li>
 *  <li>space - the space character ({@code ' '}, char 32)</li>
 *  <li>whitespace - the characters defined by {@link Character#isWhitespace(char)}</li>
 *  <li>trim - the characters &lt;= 32 as in {@link String#trim()}</li>
 * </ul>
 *
 * <p>{@link StringUtils} handles {@code null} input Strings quietly.
 * That is to say that a {@code null} input will return {@code null}.
 * Where a {@code boolean} or {@code int} is being returned
 * details vary by method.</p>
 *
 * <p>A side effect of the {@code null} handling is that a
 * {@link NullPointerException} should be considered a bug in
 * {@link StringUtils}.</p>
 *
 * <p>Methods in this class include sample code in their Javadoc comments to explain their operation.
 * The symbol {@code *} is used to indicate any input including {@code null}.</p>
 *
 * <p>#ThreadSafe#</p>
 *
 * @see String
 * @since 1.0
 */
//@Immutable
public class StringUtils {

    // Performance testing notes (JDK 1.4, Jul03, scolebourne)
    // Whitespace:
    // Character.isWhitespace() is faster than WHITESPACE.indexOf()
    // where WHITESPACE is a string of all whitespace characters
    //
    // Character access:
    // String.charAt(n) versus toCharArray(), then array[n]
    // String.charAt(n) is about 15% worse for a 10K string
    // They are about equal for a length 50 string
    // String.charAt(n) is about 4 times better for a length 3 string
    // String.charAt(n) is best bet overall
    //
    // Append:
    // String.concat about twice as fast as StringBuffer.append
    // (not sure who tested this)

    /**
     * This is a 3 character version of an ellipsis. There is a Unicode character for a HORIZONTAL ELLIPSIS, U+2026 'â€¦', this isn't it.
     */
    private static final String ELLIPSIS3 = "...";

    /**
     * A String for a space character.
     *
     * @since 3.2
     */
    public static final String SPACE = " ";

    /**
     * The empty String {@code ""}.
     *
     * @since 2.0
     */
    public static final String EMPTY = "";

    /**
     * The null String {@code null}. Package-private only.
     */
    static final String NULL = null;

    /**
     * A String for linefeed LF ("\n").
     *
     * @see <a href="https://docs.oracle.com/javase/specs/jls/se8/html/jls-3.html#jls-3.10.6">JLF: Escape Sequences
     *      for Character and String Literals</a>
     * @since 3.2
     */
    public static final String LF = "\n";

    /**
     * A String for carriage return CR ("\r").
     *
     * @see <a href="https://docs.oracle.com/javase/specs/jls/se8/html/jls-3.html#jls-3.10.6">JLF: Escape Sequences
     *      for Character and String Literals</a>
     * @since 3.2
     */
    public static final String CR = "\r";

    /**
     * Represents a failed index search.
     *
     * @since 2.1
     */
    public static final int INDEX_NOT_FOUND = -1;

    /**
     * The maximum size to which the padding constant(s) can expand.
     */
    private static final int PAD_LIMIT = 8192;

    /**
     * The default maximum depth at which recursive replacement will continue until no further search replacements are possible.
     */
    private static final int DEFAULT_TTL = 5;

    /**
     * Pattern used in {@link #stripAccents(String)}.
     */
    private static final Pattern STRIP_ACCENTS_PATTERN = Pattern.compile("\\p{InCombiningDiacriticalMarks}+"); //$NON-NLS-1$

    /**
     * Abbreviates a String using ellipses. This will convert "Now is the time for all good men" into "Now is the time for..."
     *
     * <p>
     * Specifically:
     * </p>
     * <ul>
     * <li>If the number of characters in {@code str} is less than or equal to {@code maxWidth}, return {@code str}.</li>
     * <li>Else abbreviate it to {@code (substring(str, 0, max - 3) + "...")}.</li>
     * <li>If {@code maxWidth} is less than {@code 4}, throw an {@link IllegalArgumentException}.</li>
     * <li>In no case will it return a String of length greater than {@code maxWidth}.</li>
     * </ul>
     *
     * <pre>
     * StringUtils.abbreviate(null, *)      = null
     * StringUtils.abbreviate("", 4)        = ""
     * StringUtils.abbreviate("abcdefg", 6) = "abc..."
     * StringUtils.abbreviate("abcdefg", 7) = "abcdefg"
     * StringUtils.abbreviate("abcdefg", 8) = "abcdefg"
     * StringUtils.abbreviate("abcdefg", 4) = "a..."
     * StringUtils.abbreviate("abcdefg", 3) = Throws {@link IllegalArgumentException}.
     * </pre>
     *
     * @param str      the String to check, may be null.
     * @param maxWidth maximum length of result String, must be at least 4.
     * @return abbreviated String, {@code null} if null String input.
     * @throws IllegalArgumentException if the width is too small.
     * @since 2.0
     */
    public static String abbreviate(final String str, final int maxWidth) {
        return abbreviate(str, ELLIPSIS3, 0, maxWidth);
    }

    /**
     * Abbreviates a String using ellipses. This will convert "Now is the time for all good men" into "...is the time for...".
     *
     * <p>
     * Works like {@code abbreviate(String, int)}, but allows you to specify a "left edge" offset. Note that this left edge is not necessarily going to be the
     * leftmost character in the result, or the first character following the ellipses, but it will appear somewhere in the result.
     * </p>
     * <p>
     * In no case will it return a String of length greater than {@code maxWidth}.
     * </p>
     *
     * <pre>
     * StringUtils.abbreviate(null, *, *)                = null
     * StringUtils.abbreviate("", 0, 4)                  = ""
     * StringUtils.abbreviate("abcdefghijklmno", -1, 10) = "abcdefg..."
     * StringUtils.abbreviate("abcdefghijklmno", 0, 10)  = "abcdefg..."
     * StringUtils.abbreviate("abcdefghijklmno", 1, 10)  = "abcdefg..."
     * StringUtils.abbreviate("abcdefghijklmno", 4, 10)  = "abcdefg..."
     * StringUtils.abbreviate("abcdefghijklmno", 5, 10)  = "...fghi..."
     * StringUtils.abbreviate("abcdefghijklmno", 6, 10)  = "...ghij..."
     * StringUtils.abbreviate("abcdefghijklmno", 8, 10)  = "...ijklmno"
     * StringUtils.abbreviate("abcdefghijklmno", 10, 10) = "...ijklmno"
     * StringUtils.abbreviate("abcdefghijklmno", 12, 10) = "...ijklmno"
     * StringUtils.abbreviate("abcdefghij", 0, 3)        = Throws {@link IllegalArgumentException}.
     * StringUtils.abbreviate("abcdefghij", 5, 6)        = Throws {@link IllegalArgumentException}.
     * </pre>
     *
     * @param str      the String to check, may be null.
     * @param offset   left edge of source String.
     * @param maxWidth maximum length of result String, must be at least 4.
     * @return abbreviated String, {@code null} if null String input.
     * @throws IllegalArgumentException if the width is too small.
     * @since 2.0
     */
    public static String abbreviate(final String str, final int offset, final int maxWidth) {
        return abbreviate(str, ELLIPSIS3, offset, maxWidth);
    }

    /**
     * Abbreviates a String using another given String as replacement marker. This will convert "Now is the time for all good men" into "Now is the time for..."
     * when "..." is the replacement marker.
     *
     * <p>
     * Specifically:
     * </p>
     * <ul>
     * <li>If the number of characters in {@code str} is less than or equal to {@code maxWidth}, return {@code str}.</li>
     * <li>Else abbreviate it to {@code (substring(str, 0, max - abbrevMarker.length) + abbrevMarker)}.</li>
     * <li>If {@code maxWidth} is less than {@code abbrevMarker.length + 1}, throw an {@link IllegalArgumentException}.</li>
     * <li>In no case will it return a String of length greater than {@code maxWidth}.</li>
     * </ul>
     *
     * <pre>
     * StringUtils.abbreviate(null, "...", *)      = null
     * StringUtils.abbreviate("abcdefg", null, *)  = "abcdefg"
     * StringUtils.abbreviate("", "...", 4)        = ""
     * StringUtils.abbreviate("abcdefg", ".", 5)   = "abcd."
     * StringUtils.abbreviate("abcdefg", ".", 7)   = "abcdefg"
     * StringUtils.abbreviate("abcdefg", ".", 8)   = "abcdefg"
     * StringUtils.abbreviate("abcdefg", "..", 4)  = "ab.."
     * StringUtils.abbreviate("abcdefg", "..", 3)  = "a.."
     * StringUtils.abbreviate("abcdefg", "..", 2)  = Throws {@link IllegalArgumentException}.
     * StringUtils.abbreviate("abcdefg", "...", 3) = Throws {@link IllegalArgumentException}.
     * </pre>
     *
     * @param str          the String to check, may be null.
     * @param abbrevMarker the String used as replacement marker.
     * @param maxWidth     maximum length of result String, must be at least {@code abbrevMarker.length + 1}.
     * @return abbreviated String, {@code null} if null String input.
     * @throws IllegalArgumentException if the width is too small.
     * @since 3.6
     */
    public static String abbreviate(final String str, final String abbrevMarker, final int maxWidth) {
        return abbreviate(str, abbrevMarker, 0, maxWidth);
    }

    /**
     * Abbreviates a String using a given replacement marker. This will convert "Now is the time for all good men" into "...is the time for..." when "..." is
     * the replacement marker.
     * <p>
     * Works like {@code abbreviate(String, String, int)}, but allows you to specify a "left edge" offset. Note that this left edge is not necessarily going to
     * be the leftmost character in the result, or the first character following the replacement marker, but it will appear somewhere in the result.
     * </p>
     * <p>
     * In no case will it return a String of length greater than {@code maxWidth}.
     * </p>
     *
     * <pre>
     * StringUtils.abbreviate(null, null, *, *)                 = null
     * StringUtils.abbreviate("abcdefghijklmno", null, *, *)    = "abcdefghijklmno"
     * StringUtils.abbreviate("", "...", 0, 4)                  = ""
     * StringUtils.abbreviate("abcdefghijklmno", "---", -1, 10) = "abcdefg---"
     * StringUtils.abbreviate("abcdefghijklmno", ",", 0, 10)    = "abcdefghi,"
     * StringUtils.abbreviate("abcdefghijklmno", ",", 1, 10)    = "abcdefghi,"
     * StringUtils.abbreviate("abcdefghijklmno", ",", 2, 10)    = "abcdefghi,"
     * StringUtils.abbreviate("abcdefghijklmno", "::", 4, 10)   = "::efghij::"
     * StringUtils.abbreviate("abcdefghijklmno", "...", 6, 10)  = "...ghij..."
     * StringUtils.abbreviate("abcdefghijklmno", "â€¦", 6, 10)    = "â€¦ghijâ€¦"
     * StringUtils.abbreviate("abcdefghijklmno", "*", 9, 10)    = "*ghijklmno"
     * StringUtils.abbreviate("abcdefghijklmno", "'", 10, 10)   = "'ghijklmno"
     * StringUtils.abbreviate("abcdefghijklmno", "!", 12, 10)   = "!ghijklmno"
     * StringUtils.abbreviate("abcdefghij", "abra", 0, 4)       = Throws {@link IllegalArgumentException}.
     * StringUtils.abbreviate("abcdefghij", "...", 5, 6)        = Throws {@link IllegalArgumentException}.
     * </pre>
     *
     * @param str          the String to check, may be null.
     * @param abbrevMarker the String used as replacement marker, for example "...", or Unicode HORIZONTAL ELLIPSIS, U+2026 'â€¦'.
     * @param offset       left edge of source String.
     * @param maxWidth     maximum length of result String, must be at least 4.
     * @return abbreviated String, {@code null} if null String input.
     * @throws IllegalArgumentException if the width is too small.
     * @since 3.6
     */
    public static String abbreviate(final String str, String abbrevMarker, int offset, final int maxWidth) {
        if (isEmpty(str)) {
            return str;
        }
        if (abbrevMarker == null) {
            abbrevMarker = EMPTY;
        }
        final int abbrevMarkerLength = abbrevMarker.length();
        final int minAbbrevWidth = abbrevMarkerLength + 1;
        final int minAbbrevWidthOffset = abbrevMarkerLength + abbrevMarkerLength + 1;

        if (maxWidth < minAbbrevWidth) {
            throw new IllegalArgumentException(String.format("Minimum abbreviation width is %d", minAbbrevWidth));
        }
        final int strLen = str.length();
        if (strLen <= maxWidth) {
            return str;
        }
        if (strLen - offset <= maxWidth - abbrevMarkerLength) {
            return abbrevMarker + str.substring(strLen - (maxWidth - abbrevMarkerLength));
        }
        if (offset <= abbrevMarkerLength + 1) {
            return str.substring(0, maxWidth - abbrevMarkerLength) + abbrevMarker;
        }
        if (maxWidth < minAbbrevWidthOffset) {
            throw new IllegalArgumentException(String.format("Minimum abbreviation width with offset is %d", minAbbrevWidthOffset));
        }
        return abbrevMarker + abbreviate(str.substring(offset), abbrevMarker, maxWidth - abbrevMarkerLength);
    }

    /**
     * Abbreviates a String to the length passed, replacing the middle characters with the supplied replacement String.
     *
     * <p>
     * This abbreviation only occurs if the following criteria is met:
     * </p>
     * <ul>
     * <li>Neither the String for abbreviation nor the replacement String are null or empty</li>
     * <li>The length to truncate to is less than the length of the supplied String</li>
     * <li>The length to truncate to is greater than 0</li>
     * <li>The abbreviated String will have enough room for the length supplied replacement String and the first and last characters of the supplied String for
     * abbreviation</li>
     * </ul>
     * <p>
     * Otherwise, the returned String will be the same as the supplied String for abbreviation.
     * </p>
     *
     * <pre>
     * StringUtils.abbreviateMiddle(null, null, 0)    = null
     * StringUtils.abbreviateMiddle("abc", null, 0)   = "abc"
     * StringUtils.abbreviateMiddle("abc", ".", 0)    = "abc"
     * StringUtils.abbreviateMiddle("abc", ".", 3)    = "abc"
     * StringUtils.abbreviateMiddle("abcdef", ".", 4) = "ab.f"
     * </pre>
     *
     * @param str    the String to abbreviate, may be null.
     * @param middle the String to replace the middle characters with, may be null.
     * @param length the length to abbreviate {@code str} to.
     * @return the abbreviated String if the above criteria is met, or the original String supplied for abbreviation.
     * @since 2.5
     */
    public static String abbreviateMiddle(final String str, final String middle, final int length) {
        if (isAnyEmpty(str, middle) || length >= str.length() || length < middle.length() + 2) {
            return str;
        }
        final int targetString = length - middle.length();
        final int startOffset = targetString / 2 + targetString % 2;
        final int endOffset = str.length() - targetString / 2;
        return str.substring(0, startOffset) + middle + str.substring(endOffset);
    }

    /**
     * Appends the suffix to the end of the string if the string does not already end with any of the suffixes.
     *
     * <pre>
     * StringUtils.appendIfMissing(null, null)      = null
     * StringUtils.appendIfMissing("abc", null)     = "abc"
     * StringUtils.appendIfMissing("", "xyz"        = "xyz"
     * StringUtils.appendIfMissing("abc", "xyz")    = "abcxyz"
     * StringUtils.appendIfMissing("abcxyz", "xyz") = "abcxyz"
     * StringUtils.appendIfMissing("abcXYZ", "xyz") = "abcXYZxyz"
     * </pre>
     * <p>
     * With additional suffixes,
     * </p>
     *
     * <pre>
     * StringUtils.appendIfMissing(null, null, null)       = null
     * StringUtils.appendIfMissing("abc", null, null)      = "abc"
     * StringUtils.appendIfMissing("", "xyz", null)        = "xyz"
     * StringUtils.appendIfMissing("abc", "xyz", new CharSequence[]{null}) = "abcxyz"
     * StringUtils.appendIfMissing("abc", "xyz", "")       = "abc"
     * StringUtils.appendIfMissing("abc", "xyz", "mno")    = "abcxyz"
     * StringUtils.appendIfMissing("abcxyz", "xyz", "mno") = "abcxyz"
     * StringUtils.appendIfMissing("abcmno", "xyz", "mno") = "abcmno"
     * StringUtils.appendIfMissing("abcXYZ", "xyz", "mno") = "abcXYZxyz"
     * StringUtils.appendIfMissing("abcMNO", "xyz", "mno") = "abcMNOxyz"
     * </pre>
     *
     * @param str      The string.
     * @param suffix   The suffix to append to the end of the string.
     * @param suffixes Additional suffixes that are valid terminators.
     * @return A new String if suffix was appended, the same string otherwise.
     * @since 3.2
     * @deprecated Use {@link Strings#appendIfMissing(String, CharSequence, CharSequence...) Strings.CS.appendIfMissing(String, CharSequence, CharSequence...)}.
     */
    @Deprecated
    public static String appendIfMissing(final String str, final CharSequence suffix, final CharSequence... suffixes) {
        return Strings.CS.appendIfMissing(str, suffix, suffixes);
    }

    /**
     * Appends the suffix to the end of the string if the string does not
     * already end, case-insensitive, with any of the suffixes.
     *
     * <pre>
     * StringUtils.appendIfMissingIgnoreCase(null, null)      = null
     * StringUtils.appendIfMissingIgnoreCase("abc", null)     = "abc"
     * StringUtils.appendIfMissingIgnoreCase("", "xyz")       = "xyz"
     * StringUtils.appendIfMissingIgnoreCase("abc", "xyz")    = "abcxyz"
     * StringUtils.appendIfMissingIgnoreCase("abcxyz", "xyz") = "abcxyz"
     * StringUtils.appendIfMissingIgnoreCase("abcXYZ", "xyz") = "abcXYZ"
     * </pre>
     * <p>With additional suffixes,</p>
     * <pre>
     * StringUtils.appendIfMissingIgnoreCase(null, null, null)       = null
     * StringUtils.appendIfMissingIgnoreCase("abc", null, null)      = "abc"
     * StringUtils.appendIfMissingIgnoreCase("", "xyz", null)        = "xyz"
     * StringUtils.appendIfMissingIgnoreCase("abc", "xyz", new CharSequence[]{null}) = "abcxyz"
     * StringUtils.appendIfMissingIgnoreCase("abc", "xyz", "")       = "abc"
     * StringUtils.appendIfMissingIgnoreCase("abc", "xyz", "mno")    = "abcxyz"
     * StringUtils.appendIfMissingIgnoreCase("abcxyz", "xyz", "mno") = "abcxyz"
     * StringUtils.appendIfMissingIgnoreCase("abcmno", "xyz", "mno") = "abcmno"
     * StringUtils.appendIfMissingIgnoreCase("abcXYZ", "xyz", "mno") = "abcXYZ"
     * StringUtils.appendIfMissingIgnoreCase("abcMNO", "xyz", "mno") = "abcMNO"
     * </pre>
     *
     * @param str The string.
     * @param suffix The suffix to append to the end of the string.
     * @param suffixes Additional suffixes that are valid terminators.
     * @return A new String if suffix was appended, the same string otherwise.
     * @since 3.2
     * @deprecated Use {@link Strings#appendIfMissing(String, CharSequence, CharSequence...) Strings.CI.appendIfMissing(String, CharSequence, CharSequence...)}.
     */
    @Deprecated
    public static String appendIfMissingIgnoreCase(final String str, final CharSequence suffix, final CharSequence... suffixes) {
        return Strings.CI.appendIfMissing(str, suffix, suffixes);
    }

    /**
     * Computes the capacity required for a StringBuilder to hold {@code items} of {@code maxElementChars} characters plus the separators between them. The
     * separator is assumed to be 1 character.
     *
     * @param count           The number of items.
     * @param maxElementChars The maximum number of characters per item.
     * @return A StringBuilder with the appropriate capacity.
     */
    private static StringBuilder capacity(final int count, final byte maxElementChars) {
        return new StringBuilder(count * maxElementChars + count - 1);
    }

    /**
     * Capitalizes a String changing the first character to title case as per {@link Character#toTitleCase(int)}. No other characters are changed.
     *
     * <p>
     * For a word based algorithm, see {@link org.apache.commons.text.WordUtils#capitalize(String)}. A {@code null} input String returns {@code null}.
     * </p>
     *
     * <pre>
     * StringUtils.capitalize(null)    = null
     * StringUtils.capitalize("")      = ""
     * StringUtils.capitalize("cat")   = "Cat"
     * StringUtils.capitalize("cAt")   = "CAt"
     * StringUtils.capitalize("'cat'") = "'cat'"
     * </pre>
     *
     * @param str the String to capitalize, may be null.
     * @return the capitalized String, {@code null} if null String input.
     * @see org.apache.commons.text.WordUtils#capitalize(String)
     * @see #uncapitalize(String)
     * @since 2.0
     */
    public static String capitalize(final String str) {
        if (isEmpty(str)) {
            return str;
        }
        final int firstCodepoint = str.codePointAt(0);
        final int newCodePoint = Character.toTitleCase(firstCodepoint);
        if (firstCodepoint == newCodePoint) {
            // already capitalized
            return str;
        }
        final int[] newCodePoints = str.codePoints().toArray();
        newCodePoints[0] = newCodePoint; // copy the first code point
        return new String(newCodePoints, 0, newCodePoints.length);
    }

    /**
     * Centers a String in a larger String of size {@code size} using the space character (' ').
     *
     * <p>
     * If the size is less than the String length, the original String is returned. A {@code null} String returns {@code null}. A negative size is treated as
     * zero.
     * </p>
     *
     * <p>
     * Equivalent to {@code center(str, size, " ")}.
     * </p>
     *
     * <pre>
     * StringUtils.center(null, *)   = null
     * StringUtils.center("", 4)     = "    "
     * StringUtils.center("ab", -1)  = "ab"
     * StringUtils.center("ab", 4)   = " ab "
     * StringUtils.center("abcd", 2) = "abcd"
     * StringUtils.center("a", 4)    = " a  "
     * </pre>
     *
     * @param str  the String to center, may be null.
     * @param size the int size of new String, negative treated as zero.
     * @return centered String, {@code null} if null String input.
     */
    public static String center(final String str, final int size) {
        return center(str, size, ' ');
    }

    /**
     * Centers a String in a larger String of size {@code size}. Uses a supplied character as the value to pad the String with.
     *
     * <p>
     * If the size is less than the String length, the String is returned. A {@code null} String returns {@code null}. A negative size is treated as zero.
     * </p>
     *
     * <pre>
     * StringUtils.center(null, *, *)     = null
     * StringUtils.center("", 4, ' ')     = "    "
     * StringUtils.center("ab", -1, ' ')  = "ab"
     * StringUtils.center("ab", 4, ' ')   = " ab "
     * StringUtils.center("abcd", 2, ' ') = "abcd"
     * StringUtils.center("a", 4, ' ')    = " a  "
     * StringUtils.center("a", 4, 'y')    = "yayy"
     * </pre>
     *
     * @param str     the String to center, may be null.
     * @param size    the int size of new String, negative treated as zero.
     * @param padChar the character to pad the new String with.
     * @return centered String, {@code null} if null String input.
     * @since 2.0
     */
    public static String center(String str, final int size, final char padChar) {
        if (str == null || size <= 0) {
            return str;
        }
        final int strLen = str.length();
        final int pads = size - strLen;
        if (pads <= 0) {
            return str;
        }
        str = leftPad(str, strLen + pads / 2, padChar);
        return rightPad(str, size, padChar);
    }

    /**
     * Centers a String in a larger String of size {@code size}. Uses a supplied String as the value to pad the String with.
     *
     * <p>
     * If the size is less than the String length, the String is returned. A {@code null} String returns {@code null}. A negative size is treated as zero.
     * </p>
     *
     * <pre>
     * StringUtils.center(null, *, *)     = null
     * StringUtils.center("", 4, " ")     = "    "
     * StringUtils.center("ab", -1, " ")  = "ab"
     * StringUtils.center("ab", 4, " ")   = " ab "
     * StringUtils.center("abcd", 2, " ") = "abcd"
     * StringUtils.center("a", 4, " ")    = " a  "
     * StringUtils.center("a", 4, "yz")   = "yayz"
     * StringUtils.center("abc", 7, null) = "  abc  "
     * StringUtils.center("abc", 7, "")   = "  abc  "
     * </pre>
     *
     * @param str    the String to center, may be null.
     * @param size   the int size of new String, negative treated as zero.
     * @param padStr the String to pad the new String with, must not be null or empty.
     * @return centered String, {@code null} if null String input.
     * @throws IllegalArgumentException if padStr is {@code null} or empty.
     */
    public static String center(String str, final int size, String padStr) {
        if (str == null || size <= 0) {
            return str;
        }
        if (isEmpty(padStr)) {
            padStr = SPACE;
        }
        final int strLen = str.length();
        final int pads = size - strLen;
        if (pads <= 0) {
            return str;
        }
        str = leftPad(str, strLen + pads / 2, padStr);
        return rightPad(str, size, padStr);
    }

    /**
     * Removes one newline from end of a String if it's there, otherwise leave it alone. A newline is &quot;{@code \n}&quot;, &quot;{@code \r}&quot;, or
     * &quot;{@code \r\n}&quot;.
     *
     * <p>
     * NOTE: This method changed in 2.0. It now more closely matches Perl chomp.
     * </p>
     *
     * <pre>
     * StringUtils.chomp(null)          = null
     * StringUtils.chomp("")            = ""
     * StringUtils.chomp("abc \r")      = "abc "
     * StringUtils.chomp("abc\n")       = "abc"
     * StringUtils.chomp("abc\r\n")     = "abc"
     * StringUtils.chomp("abc\r\n\r\n") = "abc\r\n"
     * StringUtils.chomp("abc\n\r")     = "abc\n"
     * StringUtils.chomp("abc\n\rabc")  = "abc\n\rabc"
     * StringUtils.chomp("\r")          = ""
     * StringUtils.chomp("\n")          = ""
     * StringUtils.chomp("\r\n")        = ""
     * </pre>
     *
     * @param str the String to chomp a newline from, may be null.
     * @return String without newline, {@code null} if null String input.
     */
    public static String chomp(final String str) {
        if (isEmpty(str)) {
            return str;
        }
        if (str.length() == 1) {
            final char ch = str.charAt(0);
            if (ch == CharUtils.CR || ch == CharUtils.LF) {
                return EMPTY;
            }
            return str;
        }
        int lastIdx = str.length() - 1;
        final char last = str.charAt(lastIdx);
        if (last == CharUtils.LF) {
            if (str.charAt(lastIdx - 1) == CharUtils.CR) {
                lastIdx--;
            }
        } else if (last != CharUtils.CR) {
            lastIdx++;
        }
        return str.substring(0, lastIdx);
    }

    /**
     * Removes {@code separator} from the end of {@code str} if it's there, otherwise leave it alone.
     *
     * <p>
     * NOTE: This method changed in version 2.0. It now more closely matches Perl chomp. For the previous behavior, use
     * {@link #substringBeforeLast(String, String)}. This method uses {@link String#endsWith(String)}.
     * </p>
     *
     * <pre>
     * StringUtils.chomp(null, *)         = null
     * StringUtils.chomp("", *)           = ""
     * StringUtils.chomp("foobar", "bar") = "foo"
     * StringUtils.chomp("foobar", "baz") = "foobar"
     * StringUtils.chomp("foo", "foo")    = ""
     * StringUtils.chomp("foo ", "foo")   = "foo "
     * StringUtils.chomp(" foo", "foo")   = " "
     * StringUtils.chomp("foo", "foooo")  = "foo"
     * StringUtils.chomp("foo", "")       = "foo"
     * StringUtils.chomp("foo", null)     = "foo"
     * </pre>
     *
     * @param str       the String to chomp from, may be null.
     * @param separator separator String, may be null.
     * @return String without trailing separator, {@code null} if null String input.
     * @deprecated This feature will be removed in Lang 4, use {@link StringUtils#removeEnd(String, String)} instead.
     */
    @Deprecated
    public static String chomp(final String str, final String separator) {
        return Strings.CS.removeEnd(str, separator);
    }

    /**
     * Removes the last character from a String.
     *
     * <p>
     * If the String ends in {@code \r\n}, then remove both of them.
     * </p>
     *
     * <pre>
     * StringUtils.chop(null)          = null
     * StringUtils.chop("")            = ""
     * StringUtils.chop("abc \r")      = "abc "
     * StringUtils.chop("abc\n")       = "abc"
     * StringUtils.chop("abc\r\n")     = "abc"
     * StringUtils.chop("abc")         = "ab"
     * StringUtils.chop("abc\nabc")    = "abc\nab"
     * StringUtils.chop("a")           = ""
     * StringUtils.chop("\r")          = ""
     * StringUtils.chop("\n")          = ""
     * StringUtils.chop("\r\n")        = ""
     * </pre>
     *
     * @param str the String to chop last character from, may be null.
     * @return String without last character, {@code null} if null String input.
     */
    public static String chop(final String str) {
        if (str == null) {
            return null;
        }
        final int strLen = str.length();
        if (strLen < 2) {
            return EMPTY;
        }
        final int lastIdx = strLen - 1;
        final String ret = str.substring(0, lastIdx);
        final char last = str.charAt(lastIdx);
        if (last == CharUtils.LF && ret.charAt(lastIdx - 1) == CharUtils.CR) {
            return ret.substring(0, lastIdx - 1);
        }
        return ret;
    }

    /**
     * Compares two Strings lexicographically, as per {@link String#compareTo(String)}, returning :
     * <ul>
     * <li>{@code int = 0}, if {@code str1} is equal to {@code str2} (or both {@code null})</li>
     * <li>{@code int < 0}, if {@code str1} is less than {@code str2}</li>
     * <li>{@code int > 0}, if {@code str1} is greater than {@code str2}</li>
     * </ul>
     *
     * <p>
     * This is a {@code null} safe version of:
     * </p>
     *
     * <pre>
     * str1.compareTo(str2)
     * </pre>
     *
     * <p>
     * {@code null} value is considered less than non-{@code null} value. Two {@code null} references are considered equal.
     * </p>
     *
     * <pre>{@code
     * StringUtils.compare(null, null)   = 0
     * StringUtils.compare(null , "a")   < 0
     * StringUtils.compare("a", null)   > 0
     * StringUtils.compare("abc", "abc") = 0
     * StringUtils.compare("a", "b")     < 0
     * StringUtils.compare("b", "a")     > 0
     * StringUtils.compare("a", "B")     > 0
     * StringUtils.compare("ab", "abc")  < 0
     * }</pre>
     *
     * @param str1 the String to compare from.
     * @param str2 the String to compare to.
     * @return &lt; 0, 0, &gt; 0, if {@code str1} is respectively less, equal or greater than {@code str2}.
     * @see #compare(String, String, boolean)
     * @see String#compareTo(String)
     * @since 3.5
     * @deprecated Use {@link Strings#compare(String, String) Strings.CS.compare(String, String)}.
     */
    @Deprecated
    public static int compare(final String str1, final String str2) {
        return Strings.CS.compare(str1, str2);
    }

    /**
     * Compares two Strings lexicographically, as per {@link String#compareTo(String)}, returning :
     * <ul>
     * <li>{@code int = 0}, if {@code str1} is equal to {@code str2} (or both {@code null})</li>
     * <li>{@code int < 0}, if {@code str1} is less than {@code str2}</li>
     * <li>{@code int > 0}, if {@code str1} is greater than {@code str2}</li>
     * </ul>
     *
     * <p>
     * This is a {@code null} safe version of :
     * </p>
     *
     * <pre>
     * str1.compareTo(str2)
     * </pre>
     *
     * <p>
     * {@code null} inputs are handled according to the {@code nullIsLess} parameter. Two {@code null} references are considered equal.
     * </p>
     *
     * <pre>{@code
     * StringUtils.compare(null, null, *)     = 0
     * StringUtils.compare(null , "a", true)  < 0
     * StringUtils.compare(null , "a", false) > 0
     * StringUtils.compare("a", null, true)   > 0
     * StringUtils.compare("a", null, false)  < 0
     * StringUtils.compare("abc", "abc", *)   = 0
     * StringUtils.compare("a", "b", *)       < 0
     * StringUtils.compare("b", "a", *)       > 0
     * StringUtils.compare("a", "B", *)       > 0
     * StringUtils.compare("ab", "abc", *)    < 0
     * }</pre>
     *
     * @param str1       the String to compare from.
     * @param str2       the String to compare to.
     * @param nullIsLess whether consider {@code null} value less than non-{@code null} value.
     * @return &lt; 0, 0, &gt; 0, if {@code str1} is respectively less, equal ou greater than {@code str2}.
     * @see String#compareTo(String)
     * @since 3.5
     */
    public static int compare(final String str1, final String str2, final boolean nullIsLess) {
        if (str1 == str2) { // NOSONARLINT this intentionally uses == to allow for both null
            return 0;
        }
        if (str1 == null) {
            return nullIsLess ? -1 : 1;
        }
        if (str2 == null) {
            return nullIsLess ? 1 : -1;
        }
        return str1.compareTo(str2);
    }

    /**
     * Compares two Strings lexicographically, ignoring case differences, as per {@link String#compareToIgnoreCase(String)}, returning :
     * <ul>
     * <li>{@code int = 0}, if {@code str1} is equal to {@code str2} (or both {@code null})</li>
     * <li>{@code int < 0}, if {@code str1} is less than {@code str2}</li>
     * <li>{@code int > 0}, if {@code str1} is greater than {@code str2}</li>
     * </ul>
     *
     * <p>
     * This is a {@code null} safe version of:
     * </p>
     *
     * <pre>
     * str1.compareToIgnoreCase(str2)
     * </pre>
     *
     * <p>
     * {@code null} value is considered less than non-{@code null} value. Two {@code null} references are considered equal. Comparison is case insensitive.
     * </p>
     *
     * <pre>{@code
     * StringUtils.compareIgnoreCase(null, null)   = 0
     * StringUtils.compareIgnoreCase(null , "a")   < 0
     * StringUtils.compareIgnoreCase("a", null)    > 0
     * StringUtils.compareIgnoreCase("abc", "abc") = 0
     * StringUtils.compareIgnoreCase("abc", "ABC") = 0
     * StringUtils.compareIgnoreCase("a", "b")     < 0
     * StringUtils.compareIgnoreCase("b", "a")     > 0
     * StringUtils.compareIgnoreCase("a", "B")     < 0
     * StringUtils.compareIgnoreCase("A", "b")     < 0
     * StringUtils.compareIgnoreCase("ab", "ABC")  < 0
     * }</pre>
     *
     * @param str1 the String to compare from.
     * @param str2 the String to compare to.
     * @return &lt; 0, 0, &gt; 0, if {@code str1} is respectively less, equal ou greater than {@code str2}, ignoring case differences.
     * @see #compareIgnoreCase(String, String, boolean)
     * @see String#compareToIgnoreCase(String)
     * @since 3.5
     * @deprecated Use {@link Strings#compare(String, String) Strings.CI.compare(String, String)}.
     */
    @Deprecated
    public static int compareIgnoreCase(final String str1, final String str2) {
        return Strings.CI.compare(str1, str2);
    }

    /**
     * Compares two Strings lexicographically, ignoring case differences, as per {@link String#compareToIgnoreCase(String)}, returning :
     * <ul>
     * <li>{@code int = 0}, if {@code str1} is equal to {@code str2} (or both {@code null})</li>
     * <li>{@code int < 0}, if {@code str1} is less than {@code str2}</li>
     * <li>{@code int > 0}, if {@code str1} is greater than {@code str2}</li>
     * </ul>
     *
     * <p>
     * This is a {@code null} safe version of :
     * </p>
     * <pre>
     * str1.compareToIgnoreCase(str2)
     * </pre>
     *
     * <p>
     * {@code null} inputs are handled according to the {@code nullIsLess} parameter. Two {@code null} references are considered equal. Comparison is case
     * insensitive.
     * </p>
     *
     * <pre>{@code
     * StringUtils.compareIgnoreCase(null, null, *)     = 0
     * StringUtils.compareIgnoreCase(null , "a", true)  < 0
     * StringUtils.compareIgnoreCase(null , "a", false) > 0
     * StringUtils.compareIgnoreCase("a", null, true)   > 0
     * StringUtils.compareIgnoreCase("a", null, false)  < 0
     * StringUtils.compareIgnoreCase("abc", "abc", *)   = 0
     * StringUtils.compareIgnoreCase("abc", "ABC", *)   = 0
     * StringUtils.compareIgnoreCase("a", "b", *)       < 0
     * StringUtils.compareIgnoreCase("b", "a", *)       > 0
     * StringUtils.compareIgnoreCase("a", "B", *)       < 0
     * StringUtils.compareIgnoreCase("A", "b", *)       < 0
     * StringUtils.compareIgnoreCase("ab", "abc", *)    < 0
     * }</pre>
     *
     * @param str1       the String to compare from.
     * @param str2       the String to compare to.
     * @param nullIsLess whether consider {@code null} value less than non-{@code null} value.
     * @return &lt; 0, 0, &gt; 0, if {@code str1} is respectively less, equal ou greater than {@code str2}, ignoring case differences.
     * @see String#compareToIgnoreCase(String)
     * @since 3.5
     */
    public static int compareIgnoreCase(final String str1, final String str2, final boolean nullIsLess) {
        if (str1 == str2) { // NOSONARLINT this intentionally uses == to allow for both null
            return 0;
        }
        if (str1 == null) {
            return nullIsLess ? -1 : 1;
        }
        if (str2 == null) {
            return nullIsLess ? 1 : -1;
        }
        return str1.compareToIgnoreCase(str2);
    }

    /**
     * Tests if CharSequence contains a search CharSequence, handling {@code null}.
     * This method uses {@link String#indexOf(String)} if possible.
     *
     * <p>A {@code null} CharSequence will return {@code false}.</p>
     *
     * <pre>
     * StringUtils.contains(null, *)     = false
     * StringUtils.contains(*, null)     = false
     * StringUtils.contains("", "")      = true
     * StringUtils.contains("abc", "")   = true
     * StringUtils.contains("abc", "a")  = true
     * StringUtils.contains("abc", "z")  = false
     * </pre>
     *
     * @param seq  the CharSequence to check, may be null
     * @param searchSeq  the CharSequence to find, may be null
     * @return true if the CharSequence contains the search CharSequence,
     *  false if not or {@code null} string input
     * @since 2.0
     * @since 3.0 Changed signature from contains(String, String) to contains(CharSequence, CharSequence)
     * @deprecated Use {@link Strings#contains(CharSequence, CharSequence) Strings.CS.contains(CharSequence, CharSequence)}.
     */
    @Deprecated
    public static boolean contains(final CharSequence seq, final CharSequence searchSeq) {
        return Strings.CS.contains(seq, searchSeq);
    }

    /**
     * Tests if CharSequence contains a search character, handling {@code null}. This method uses {@link String#indexOf(int)} if possible.
     *
     * <p>
     * A {@code null} or empty ("") CharSequence will return {@code false}.
     * </p>
     *
     * <pre>
     * StringUtils.contains(null, *)    = false
     * StringUtils.contains("", *)      = false
     * StringUtils.contains("abc", 'a') = true
     * StringUtils.contains("abc", 'z') = false
     * </pre>
     *
     * @param seq        the CharSequence to check, may be null
     * @param searchChar the character to find
     * @return true if the CharSequence contains the search character, false if not or {@code null} string input
     * @since 2.0
     * @since 3.0 Changed signature from contains(String, int) to contains(CharSequence, int)
     */
    public static boolean contains(final CharSequence seq, final int searchChar) {
        if (isEmpty(seq)) {
            return false;
        }
        return CharSequenceUtils.indexOf(seq, searchChar, 0) >= 0;
    }

    /**
     * Tests if the CharSequence contains any character in the given set of characters.
     *
     * <p>
     * A {@code null} CharSequence will return {@code false}. A {@code null} or zero length search array will return {@code false}.
     * </p>
     *
     * <pre>
     * StringUtils.containsAny(null, *)                  = false
     * StringUtils.containsAny("", *)                    = false
     * StringUtils.containsAny(*, null)                  = false
     * StringUtils.containsAny(*, [])                    = false
     * StringUtils.containsAny("zzabyycdxx", 'z', 'a')   = true
     * StringUtils.containsAny("zzabyycdxx", 'b', 'y')   = true
     * StringUtils.containsAny("zzabyycdxx", 'z', 'y')   = true
     * StringUtils.containsAny("aba", 'z])               = false
     * </pre>
     *
     * @param cs          the CharSequence to check, may be null.
     * @param searchChars the chars to search for, may be null.
     * @return the {@code true} if any of the chars are found, {@code false} if no match or null input.
     * @since 2.4
     * @since 3.0 Changed signature from containsAny(String, char[]) to containsAny(CharSequence, char...)
     */
    public static boolean containsAny(final CharSequence cs, final char... searchChars) {
        if (isEmpty(cs) || ArrayUtils.isEmpty(searchChars)) {
            return false;
        }
        final int csLength = cs.length();
        final int searchLength = searchChars.length;
        final int csLast = csLength - 1;
        final int searchLast = searchLength - 1;
        for (int i = 0; i < csLength; i++) {
            final char ch = cs.charAt(i);
            for (int j = 0; j < searchLength; j++) {
                if (searchChars[j] == ch) {
                    if (!Character.isHighSurrogate(ch) || j == searchLast || i < csLast && searchChars[j + 1] == cs.charAt(i + 1)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    /**
     * Tests if the CharSequence contains any character in the given set of characters.
     *
     * <p>
     * A {@code null} CharSequence will return {@code false}. A {@code null} search CharSequence will return {@code false}.
     * </p>
     *
     * <pre>
     * StringUtils.containsAny(null, *)               = false
     * StringUtils.containsAny("", *)                 = false
     * StringUtils.containsAny(*, null)               = false
     * StringUtils.containsAny(*, "")                 = false
     * StringUtils.containsAny("zzabyycdxx", "za")    = true
     * StringUtils.containsAny("zzabyycdxx", "by")    = true
     * StringUtils.containsAny("zzabyycdxx", "zy")    = true
     * StringUtils.containsAny("zzabyycdxx", "\tx")   = true
     * StringUtils.containsAny("zzabyycdxx", "$.#yF") = true
     * StringUtils.containsAny("aba", "z")            = false
     * </pre>
     *
     * @param cs          the CharSequence to check, may be null.
     * @param searchChars the chars to search for, may be null.
     * @return the {@code true} if any of the chars are found, {@code false} if no match or null input.
     * @since 2.4
     * @since 3.0 Changed signature from containsAny(String, String) to containsAny(CharSequence, CharSequence)
     */
    public static boolean containsAny(final CharSequence cs, final CharSequence searchChars) {
        if (searchChars == null) {
            return false;
        }
        return containsAny(cs, CharSequenceUtils.toCharArray(searchChars));
    }

    /**
     * Tests if the CharSequence contains any of the CharSequences in the given array.
     *
     * <p>
     * A {@code null} {@code cs} CharSequence will return {@code false}. A {@code null} or zero length search array will
     * return {@code false}.
     * </p>
     *
     * <pre>
     * StringUtils.containsAny(null, *)            = false
     * StringUtils.containsAny("", *)              = false
     * StringUtils.containsAny(*, null)            = false
     * StringUtils.containsAny(*, [])              = false
     * StringUtils.containsAny("abcd", "ab", null) = true
     * StringUtils.containsAny("abcd", "ab", "cd") = true
     * StringUtils.containsAny("abc", "d", "abc")  = true
     * </pre>
     *
     * @param cs The CharSequence to check, may be null.
     * @param searchCharSequences The array of CharSequences to search for, may be null. Individual CharSequences may be
     *        null as well.
     * @return {@code true} if any of the search CharSequences are found, {@code false} otherwise.
     * @since 3.4
     * @deprecated Use {@link Strings#containsAny(CharSequence, CharSequence...) Strings.CS.containsAny(CharSequence, CharSequence...)}.
     */
    @Deprecated
    public static boolean containsAny(final CharSequence cs, final CharSequence... searchCharSequences) {
        return Strings.CS.containsAny(cs, searchCharSequences);
    }

    /**
     * Tests if the CharSequence contains any of the CharSequences in the given array, ignoring case.
     *
     * <p>
     * A {@code null} {@code cs} CharSequence will return {@code false}. A {@code null} or zero length search array will
     * return {@code false}.
     * </p>
     *
     * <pre>
     * StringUtils.containsAny(null, *)            = false
     * StringUtils.containsAny("", *)              = false
     * StringUtils.containsAny(*, null)            = false
     * StringUtils.containsAny(*, [])              = false
     * StringUtils.containsAny("abcd", "ab", null) = true
     * StringUtils.containsAny("abcd", "ab", "cd") = true
     * StringUtils.containsAny("abc", "d", "abc")  = true
     * StringUtils.containsAny("abc", "D", "ABC")  = true
     * StringUtils.containsAny("ABC", "d", "abc")  = true
     * </pre>
     *
     * @param cs The CharSequence to check, may be null.
     * @param searchCharSequences The array of CharSequences to search for, may be null. Individual CharSequences may be
     *        null as well.
     * @return {@code true} if any of the search CharSequences are found, {@code false} otherwise
     * @since 3.12.0
     * @deprecated Use {@link Strings#containsAny(CharSequence, CharSequence...) Strings.CI.containsAny(CharSequence, CharSequence...)}.
     */
    @Deprecated
    public static boolean containsAnyIgnoreCase(final CharSequence cs, final CharSequence... searchCharSequences) {
        return Strings.CI.containsAny(cs, searchCharSequences);
    }

    /**
     * Tests if CharSequence contains a search CharSequence irrespective of case, handling {@code null}. Case-insensitivity is defined as by
     * {@link String#equalsIgnoreCase(String)}.
     *
     * <p>
     * A {@code null} CharSequence will return {@code false}.
     * </p>
     *
     * <pre>
     * StringUtils.containsIgnoreCase(null, *)    = false
     * StringUtils.containsIgnoreCase(*, null)    = false
     * StringUtils.containsIgnoreCase("", "")     = true
     * StringUtils.containsIgnoreCase("abc", "")  = true
     * StringUtils.containsIgnoreCase("abc", "a") = true
     * StringUtils.containsIgnoreCase("abc", "z") = false
     * StringUtils.containsIgnoreCase("abc", "A") = true
     * StringUtils.containsIgnoreCase("abc", "Z") = false
     * </pre>
     *
     * @param str       the CharSequence to check, may be null.
     * @param searchStr the CharSequence to find, may be null.
     * @return true if the CharSequence contains the search CharSequence irrespective of case or false if not or {@code null} string input.
     * @since 3.0 Changed signature from containsIgnoreCase(String, String) to containsIgnoreCase(CharSequence, CharSequence).
     * @deprecated Use {@link Strings#contains(CharSequence, CharSequence) Strings.CI.contains(CharSequence, CharSequence)}.
     */
    @Deprecated
    public static boolean containsIgnoreCase(final CharSequence str, final CharSequence searchStr) {
        return Strings.CI.contains(str, searchStr);
    }

    /**
     * Tests that the CharSequence does not contain certain characters.
     *
     * <p>
     * A {@code null} CharSequence will return {@code true}. A {@code null} invalid character array will return {@code true}. An empty CharSequence (length()=0)
     * always returns true.
     * </p>
     *
     * <pre>
     * StringUtils.containsNone(null, *)               = true
     * StringUtils.containsNone(*, null)               = true
     * StringUtils.containsNone("", *)                 = true
     * StringUtils.containsNone("ab", '')              = true
     * StringUtils.containsNone("abab", 'x', 'y', 'z') = true
     * StringUtils.containsNone("ab1", 'x', 'y', 'z')  = true
     * StringUtils.containsNone("abz", 'x', 'y', 'z')  = false
     * </pre>
     *
     * @param cs          the CharSequence to check, may be null.
     * @param searchChars an array of invalid chars, may be null.
     * @return true if it contains none of the invalid chars, or is null.
     * @since 2.0
     * @since 3.0 Changed signature from containsNone(String, char[]) to containsNone(CharSequence, char...)
     */
    public static boolean containsNone(final CharSequence cs, final char... searchChars) {
        if (cs == null || searchChars == null) {
            return true;
        }
        final int csLen = cs.length();
        final int csLast = csLen - 1;
        final int searchLen = searchChars.length;
        final int searchLast = searchLen - 1;
        for (int i = 0; i < csLen; i++) {
            final char ch = cs.charAt(i);
            for (int j = 0; j < searchLen; j++) {
                if (searchChars[j] == ch) {
                    if (!Character.isHighSurrogate(ch) || j == searchLast || i < csLast && searchChars[j + 1] == cs.charAt(i + 1)) {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    /**
     * Tests that the CharSequence does not contain certain characters.
     *
     * <p>
     * A {@code null} CharSequence will return {@code true}. A {@code null} invalid character array will return {@code true}. An empty String ("") always
     * returns true.
     * </p>
     *
     * <pre>
     * StringUtils.containsNone(null, *)       = true
     * StringUtils.containsNone(*, null)       = true
     * StringUtils.containsNone("", *)         = true
     * StringUtils.containsNone("ab", "")      = true
     * StringUtils.containsNone("abab", "xyz") = true
     * StringUtils.containsNone("ab1", "xyz")  = true
     * StringUtils.containsNone("abz", "xyz")  = false
     * </pre>
     *
     * @param cs           the CharSequence to check, may be null.
     * @param invalidChars a String of invalid chars, may be null.
     * @return true if it contains none of the invalid chars, or is null.
     * @since 2.0
     * @since 3.0 Changed signature from containsNone(String, String) to containsNone(CharSequence, String)
     */
    public static boolean containsNone(final CharSequence cs, final String invalidChars) {
        if (invalidChars == null) {
            return true;
        }
        return containsNone(cs, invalidChars.toCharArray());
    }

    /**
     * Tests if the CharSequence contains only certain characters.
     *
     * <p>
     * A {@code null} CharSequence will return {@code false}. A {@code null} valid character array will return {@code false}. An empty CharSequence (length()=0)
     * always returns {@code true}.
     * </p>
     *
     * <pre>
     * StringUtils.containsOnly(null, *)               = false
     * StringUtils.containsOnly(*, null)               = false
     * StringUtils.containsOnly("", *)                 = true
     * StringUtils.containsOnly("ab", '')              = false
     * StringUtils.containsOnly("abab", 'a', 'b', 'c') = true
     * StringUtils.containsOnly("ab1", 'a', 'b', 'c')  = false
     * StringUtils.containsOnly("abz", 'a', 'b', 'c')  = false
     * </pre>
     *
     * @param cs    the String to check, may be null.
     * @param valid an array of valid chars, may be null.
     * @return true if it only contains valid chars and is non-null.
     * @since 3.0 Changed signature from containsOnly(String, char[]) to containsOnly(CharSequence, char...)
     */
    public static boolean containsOnly(final CharSequence cs, final char... valid) {
        // All these pre-checks are to maintain API with an older version
        if (valid == null || cs == null) {
            return false;
        }
        if (cs.length() == 0) {
            return true;
        }
        if (valid.length == 0) {
            return false;
        }
        return indexOfAnyBut(cs, valid) == INDEX_NOT_FOUND;
    }

    /**
     * Tests if the CharSequence contains only certain characters.
     *
     * <p>
     * A {@code null} CharSequence will return {@code false}. A {@code null} valid character String will return {@code false}. An empty String (length()=0)
     * always returns {@code true}.
     * </p>
     *
     * <pre>
     * StringUtils.containsOnly(null, *)       = false
     * StringUtils.containsOnly(*, null)       = false
     * StringUtils.containsOnly("", *)         = true
     * StringUtils.containsOnly("ab", "")      = false
     * StringUtils.containsOnly("abab", "abc") = true
     * StringUtils.containsOnly("ab1", "abc")  = false
     * StringUtils.containsOnly("abz", "abc")  = false
     * </pre>
     *
     * @param cs         the CharSequence to check, may be null.
     * @param validChars a String of valid chars, may be null.
     * @return true if it only contains valid chars and is non-null.
     * @since 2.0
     * @since 3.0 Changed signature from containsOnly(String, String) to containsOnly(CharSequence, String)
     */
    public static boolean containsOnly(final CharSequence cs, final String validChars) {
        if (cs == null || validChars == null) {
            return false;
        }
        return containsOnly(cs, validChars.toCharArray());
    }

    /**
     * Tests whether the given CharSequence contains any whitespace characters.
     *
     * <p>
     * Whitespace is defined by {@link Character#isWhitespace(char)}.
     * </p>
     *
     * <pre>
     * StringUtils.containsWhitespace(null)       = false
     * StringUtils.containsWhitespace("")         = false
     * StringUtils.containsWhitespace("ab")       = false
     * StringUtils.containsWhitespace(" ab")      = true
     * StringUtils.containsWhitespace("a b")      = true
     * StringUtils.containsWhitespace("ab ")      = true
     * </pre>
     *
     * @param seq the CharSequence to check (may be {@code null}).
     * @return {@code true} if the CharSequence is not empty and contains at least 1 (breaking) whitespace character.
     * @since 3.0
     */
    public static boolean containsWhitespace(final CharSequence seq) {
        if (isEmpty(seq)) {
            return false;
        }
        final int strLen = seq.length();
        for (int i = 0; i < strLen; i++) {
            if (Character.isWhitespace(seq.charAt(i))) {
                return true;
            }
        }
        return false;
    }

    private static void convertRemainingAccentCharacters(final StringBuilder decomposed) {
        for (int i = 0; i < decomposed.length(); i++) {
            final char charAt = decomposed.charAt(i);
            switch (charAt) {
            case '\u0141':
                decomposed.setCharAt(i, 'L');
                break;
            case '\u0142':
                decomposed.setCharAt(i, 'l');
                break;
            // D with stroke
            case '\u0110':
                // LATIN CAPITAL LETTER D WITH STROKE
                decomposed.setCharAt(i, 'D');
                break;
            case '\u0111':
                // LATIN SMALL LETTER D WITH STROKE
                decomposed.setCharAt(i, 'd');
                break;
            // I with bar
            case '\u0197':
                decomposed.setCharAt(i, 'I');
                break;
            case '\u0268':
                decomposed.setCharAt(i, 'i');
                break;
            case '\u1D7B':
                decomposed.setCharAt(i, 'I');
                break;
            case '\u1DA4':
                decomposed.setCharAt(i, 'i');
                break;
            case '\u1DA7':
                decomposed.setCharAt(i, 'I');
                break;
            // U with bar
            case '\u0244':
                // LATIN CAPITAL LETTER U BAR
                decomposed.setCharAt(i, 'U');
                break;
            case '\u0289':
                // LATIN SMALL LETTER U BAR
                decomposed.setCharAt(i, 'u');
                break;
            case '\u1D7E':
                // LATIN SMALL CAPITAL LETTER U WITH STROKE
                decomposed.setCharAt(i, 'U');
                break;
            case '\u1DB6':
                // MODIFIER LETTER SMALL U BAR
                decomposed.setCharAt(i, 'u');
                break;
            // T with stroke
            case '\u0166':
                // LATIN CAPITAL LETTER T WITH STROKE
                decomposed.setCharAt(i, 'T');
                break;
            case '\u0167':
                // LATIN SMALL LETTER T WITH STROKE
                decomposed.setCharAt(i, 't');
                break;
            default:
                break;
            }
        }
    }

    /**
     * Counts how many times the char appears in the given string.
     *
     * <p>
     * A {@code null} or empty ("") String input returns {@code 0}.
     * </p>
     *
     * <pre>
     * StringUtils.countMatches(null, *)     = 0
     * StringUtils.countMatches("", *)       = 0
     * StringUtils.countMatches("abba", 0)   = 0
     * StringUtils.countMatches("abba", 'a') = 2
     * StringUtils.countMatches("abba", 'b') = 2
     * StringUtils.countMatches("abba", 'x') = 0
     * </pre>
     *
     * @param str the CharSequence to check, may be null.
     * @param ch  the char to count.
     * @return the number of occurrences, 0 if the CharSequence is {@code null}.
     * @since 3.4
     */
    public static int countMatches(final CharSequence str, final char ch) {
        if (isEmpty(str)) {
            return 0;
        }
        int count = 0;
        // We could also call str.toCharArray() for faster lookups but that would generate more garbage.
        for (int i = 0; i < str.length(); i++) {
            if (ch == str.charAt(i)) {
                count++;
            }
        }
        return count;
    }

    /**
     * Counts how many times the substring appears in the larger string. Note that the code only counts non-overlapping matches.
     *
     * <p>
     * A {@code null} or empty ("") String input returns {@code 0}.
     * </p>
     *
     * <pre>
     * StringUtils.countMatches(null, *)        = 0
     * StringUtils.countMatches("", *)          = 0
     * StringUtils.countMatches("abba", null)   = 0
     * StringUtils.countMatches("abba", "")     = 0
     * StringUtils.countMatches("abba", "a")    = 2
     * StringUtils.countMatches("abba", "ab")   = 1
     * StringUtils.countMatches("abba", "xxx")  = 0
     * StringUtils.countMatches("ababa", "aba") = 1
     * </pre>
     *
     * @param str the CharSequence to check, may be null.
     * @param sub the substring to count, may be null.
     * @return the number of occurrences, 0 if either CharSequence is {@code null}.
     * @since 3.0 Changed signature from countMatches(String, String) to countMatches(CharSequence, CharSequence)
     */
    public static int countMatches(final CharSequence str, final CharSequence sub) {
        if (isEmpty(str) || isEmpty(sub)) {
            return 0;
        }
        int count = 0;
        int idx = 0;
        while ((idx = CharSequenceUtils.indexOf(str, sub, idx)) != INDEX_NOT_FOUND) {
            count++;
            idx += sub.length();
        }
        return count;
    }

    /**
     * Returns either the passed in CharSequence, or if the CharSequence is {@link #isBlank(CharSequence) blank} (whitespaces, empty ({@code ""}), or
     * {@code null}), the value of {@code defaultStr}.
     *
     * <p>
     * Whitespace is defined by {@link Character#isWhitespace(char)}.
     * </p>
     *
     * <pre>
     * StringUtils.defaultIfBlank(null, "NULL")  = "NULL"
     * StringUtils.defaultIfBlank("", "NULL")    = "NULL"
     * StringUtils.defaultIfBlank(" ", "NULL")   = "NULL"
     * StringUtils.defaultIfBlank("bat", "NULL") = "bat"
     * StringUtils.defaultIfBlank("", null)      = null
     * </pre>
     *
     * @param <T>        the specific kind of CharSequence.
     * @param str        the CharSequence to check, may be null.
     * @param defaultStr the default CharSequence to return if {@code str} is {@link #isBlank(CharSequence) blank} (whitespaces, empty ({@code ""}), or
     *                   {@code null}); may be null.
     * @return the passed in CharSequence, or the default.
     * @see StringUtils#defaultString(String, String)
     * @see #isBlank(CharSequence)
     */
    public static <T extends CharSequence> T defaultIfBlank(final T str, final T defaultStr) {
        return isBlank(str) ? defaultStr : str;
    }

    /**
     * Returns either the passed in CharSequence, or if the CharSequence is empty or {@code null}, the value of {@code defaultStr}.
     *
     * <pre>
     * StringUtils.defaultIfEmpty(null, "NULL")  = "NULL"
     * StringUtils.defaultIfEmpty("", "NULL")    = "NULL"
     * StringUtils.defaultIfEmpty(" ", "NULL")   = " "
     * StringUtils.defaultIfEmpty("bat", "NULL") = "bat"
     * StringUtils.defaultIfEmpty("", null)      = null
     * </pre>
     *
     * @param <T>        the specific kind of CharSequence.
     * @param str        the CharSequence to check, may be null.
     * @param defaultStr the default CharSequence to return if the input is empty ("") or {@code null}, may be null.
     * @return the passed in CharSequence, or the default.
     * @see StringUtils#defaultString(String, String)
     */
    public static <T extends CharSequence> T defaultIfEmpty(final T str, final T defaultStr) {
        return isEmpty(str) ? defaultStr : str;
    }

    /**
     * Returns either the passed in String, or if the String is {@code null}, an empty String ("").
     *
     * <pre>
     * StringUtils.defaultString(null)  = ""
     * StringUtils.defaultString("")    = ""
     * StringUtils.defaultString("bat") = "bat"
     * </pre>
     *
     * @param str the String to check, may be null.
     * @return the passed in String, or the empty String if it was {@code null}.
     * @see Objects#toString(Object, String)
     * @see String#valueOf(Object)
     */
    public static String defaultString(final String str) {
        return Objects.toString(str, EMPTY);
    }

    /**
     * Returns either the given String, or if the String is {@code null}, {@code nullDefault}.
     *
     * <pre>
     * StringUtils.defaultString(null, "NULL")  = "NULL"
     * StringUtils.defaultString("", "NULL")    = ""
     * StringUtils.defaultString("bat", "NULL") = "bat"
     * </pre>
     * <p>
     * Since this is now provided by Java, instead call {@link Objects#toString(Object, String)}:
     * </p>
     *
     * <pre>
     * Objects.toString(null, "NULL")  = "NULL"
     * Objects.toString("", "NULL")    = ""
     * Objects.toString("bat", "NULL") = "bat"
     * </pre>
     *
     * @param str         the String to check, may be null.
     * @param nullDefault the default String to return if the input is {@code null}, may be null.
     * @return the passed in String, or the default if it was {@code null}.
     * @see Objects#toString(Object, String)
     * @see String#valueOf(Object)
     * @deprecated Use {@link Objects#toString(Object, String)}.
     */
    @Deprecated
    public static String defaultString(final String str, final String nullDefault) {
        return Objects.toString(str, nullDefault);
    }

    /**
     * Deletes all whitespaces from a String as defined by {@link Character#isWhitespace(char)}.
     *
     * <pre>
     * StringUtils.deleteWhitespace(null)         = null
     * StringUtils.deleteWhitespace("")           = ""
     * StringUtils.deleteWhitespace("abc")        = "abc"
     * StringUtils.deleteWhitespace("   ab  c  ") = "abc"
     * </pre>
     *
     * @param str the String to delete whitespace from, may be null.
     * @return the String without whitespaces, {@code null} if null String input.
     */
    public static String deleteWhitespace(final String str) {
        if (isEmpty(str)) {
            return str;
        }
        final int sz = str.length();
        final char[] chs = new char[sz];
        int count = 0;
        for (int i = 0; i < sz; i++) {
            if (!Character.isWhitespace(str.charAt(i))) {
                chs[count++] = str.charAt(i);
            }
        }
        if (count == sz) {
            return str;
        }
        if (count == 0) {
            return EMPTY;
        }
        return new String(chs, 0, count);
    }

    /**
     * Compares two Strings, and returns the portion where they differ. More precisely, return the remainder of the second String, starting from where it's
     * different from the first. This means that the difference between "abc" and "ab" is the empty String and not "c".
     *
     * <p>
     * For example, {@code difference("i am a machine", "i am a robot") -> "robot"}.
     * </p>
     *
     * <pre>
     * StringUtils.difference(null, null)       = null
     * StringUtils.difference("", "")           = ""
     * StringUtils.difference("", "abc")        = "abc"
     * StringUtils.difference("abc", "")        = ""
     * StringUtils.difference("abc", "abc")     = ""
     * StringUtils.difference("abc", "ab")      = ""
     * StringUtils.difference("ab", "abxyz")    = "xyz"
     * StringUtils.difference("abcde", "abxyz") = "xyz"
     * StringUtils.difference("abcde", "xyz")   = "xyz"
     * </pre>
     *
     * @param str1 the first String, may be null.
     * @param str2 the second String, may be null.
     * @return the portion of str2 where it differs from str1; returns the empty String if they are equal.
     * @see #indexOfDifference(CharSequence,CharSequence)
     * @since 2.0
     */
    public static String difference(final String str1, final String str2) {
        if (str1 == null) {
            return str2;
        }
        if (str2 == null) {
            return str1;
        }
        final int at = indexOfDifference(str1, str2);
        if (at == INDEX_NOT_FOUND) {
            return EMPTY;
        }
        return str2.substring(at);
    }

    /**
     * Tests if a CharSequence ends with a specified suffix.
     *
     * <p>
     * {@code null}s are handled without exceptions. Two {@code null} references are considered to be equal. The comparison is case-sensitive.
     * </p>
     *
     * <pre>
     * StringUtils.endsWith(null, null)      = true
     * StringUtils.endsWith(null, "def")     = false
     * StringUtils.endsWith("abcdef", null)  = false
     * StringUtils.endsWith("abcdef", "def") = true
     * StringUtils.endsWith("ABCDEF", "def") = false
     * StringUtils.endsWith("ABCDEF", "cde") = false
     * StringUtils.endsWith("ABCDEF", "")    = true
     * </pre>
     *
     * @param str    the CharSequence to check, may be null.
     * @param suffix the suffix to find, may be null.
     * @return {@code true} if the CharSequence ends with the suffix, case-sensitive, or both {@code null}.
     * @see String#endsWith(String)
     * @since 2.4
     * @since 3.0 Changed signature from endsWith(String, String) to endsWith(CharSequence, CharSequence)
     * @deprecated Use {@link Strings#endsWith(CharSequence, CharSequence) Strings.CS.endsWith(CharSequence, CharSequence)}.
     */
    @Deprecated
    public static boolean endsWith(final CharSequence str, final CharSequence suffix) {
        return Strings.CS.endsWith(str, suffix);
    }

    /**
     * Tests if a CharSequence ends with any of the provided case-sensitive suffixes.
     *
     * <pre>
     * StringUtils.endsWithAny(null, null)                  = false
     * StringUtils.endsWithAny(null, new String[] {"abc"})  = false
     * StringUtils.endsWithAny("abcxyz", null)              = false
     * StringUtils.endsWithAny("abcxyz", new String[] {""}) = true
     * StringUtils.endsWithAny("abcxyz", new String[] {"xyz"}) = true
     * StringUtils.endsWithAny("abcxyz", new String[] {null, "xyz", "abc"}) = true
     * StringUtils.endsWithAny("abcXYZ", "def", "XYZ")      = true
     * StringUtils.endsWithAny("abcXYZ", "def", "xyz")      = false
     * </pre>
     *
     * @param sequence      the CharSequence to check, may be null.
     * @param searchStrings the case-sensitive CharSequences to find, may be empty or contain {@code null}.
     * @return {@code true} if the input {@code sequence} is {@code null} AND no {@code searchStrings} are provided, or the input {@code sequence} ends in any
     *         of the provided case-sensitive {@code searchStrings}.
     * @see StringUtils#endsWith(CharSequence, CharSequence)
     * @since 3.0
     * @deprecated Use {@link Strings#endsWithAny(CharSequence, CharSequence...) Strings.CS.endsWithAny(CharSequence, CharSequence...)}.
     */
    @Deprecated
    public static boolean endsWithAny(final CharSequence sequence, final CharSequence... searchStrings) {
        return Strings.CS.endsWithAny(sequence, searchStrings);
    }

    /**
     * Case-insensitive check if a CharSequence ends with a specified suffix.
     *
     * <p>
     * {@code null}s are handled without exceptions. Two {@code null} references are considered to be equal. The comparison is case insensitive.
     * </p>
     *
     * <pre>
     * StringUtils.endsWithIgnoreCase(null, null)      = true
     * StringUtils.endsWithIgnoreCase(null, "def")     = false
     * StringUtils.endsWithIgnoreCase("abcdef", null)  = false
     * StringUtils.endsWithIgnoreCase("abcdef", "def") = true
     * StringUtils.endsWithIgnoreCase("ABCDEF", "def") = true
     * StringUtils.endsWithIgnoreCase("ABCDEF", "cde") = false
     * </pre>
     *
     * @param str    the CharSequence to check, may be null
     * @param suffix the suffix to find, may be null
     * @return {@code true} if the CharSequence ends with the suffix, case-insensitive, or both {@code null}
     * @see String#endsWith(String)
     * @since 2.4
     * @since 3.0 Changed signature from endsWithIgnoreCase(String, String) to endsWithIgnoreCase(CharSequence, CharSequence)
     * @deprecated Use {@link Strings#endsWith(CharSequence, CharSequence) Strings.CI.endsWith(CharSequence, CharSequence)}.
     */
    @Deprecated
    public static boolean endsWithIgnoreCase(final CharSequence str, final CharSequence suffix) {
        return Strings.CI.endsWith(str, suffix);
    }

    /**
     * Compares two CharSequences, returning {@code true} if they represent equal sequences of characters.
     *
     * <p>
     * {@code null}s are handled without exceptions. Two {@code null} references are considered to be equal. The comparison is <strong>case-sensitive</strong>.
     * </p>
     *
     * <pre>
     * StringUtils.equals(null, null)   = true
     * StringUtils.equals(null, "abc")  = false
     * StringUtils.equals("abc", null)  = false
     * StringUtils.equals("abc", "abc") = true
     * StringUtils.equals("abc", "ABC") = false
     * </pre>
     *
     * @param cs1 the first CharSequence, may be {@code null}.
     * @param cs2 the second CharSequence, may be {@code null}.
     * @return {@code true} if the CharSequences are equal (case-sensitive), or both {@code null}.
     * @since 3.0 Changed signature from equals(String, String) to equals(CharSequence, CharSequence)
     * @see Object#equals(Object)
     * @see #equalsIgnoreCase(CharSequence, CharSequence)
     * @deprecated Use {@link Strings#equals(CharSequence, CharSequence) Strings.CS.equals(CharSequence, CharSequence)}.
     */
    @Deprecated
    public static boolean equals(final CharSequence cs1, final CharSequence cs2) {
        return Strings.CS.equals(cs1, cs2);
    }

    /**
     * Compares given {@code string} to a CharSequences vararg of {@code searchStrings}, returning {@code true} if the {@code string} is equal to any of the
     * {@code searchStrings}.
     *
     * <pre>
     * StringUtils.equalsAny(null, (CharSequence[]) null) = false
     * StringUtils.equalsAny(null, null, null)    = true
     * StringUtils.equalsAny(null, "abc", "def")  = false
     * StringUtils.equalsAny("abc", null, "def")  = false
     * StringUtils.equalsAny("abc", "abc", "def") = true
     * StringUtils.equalsAny("abc", "ABC", "DEF") = false
     * </pre>
     *
     * @param string        to compare, may be {@code null}.
     * @param searchStrings a vararg of strings, may be {@code null}.
     * @return {@code true} if the string is equal (case-sensitive) to any other element of {@code searchStrings}; {@code false} if {@code searchStrings} is
     *         null or contains no matches.
     * @since 3.5
     * @deprecated Use {@link Strings#equalsAny(CharSequence, CharSequence...) Strings.CS.equalsAny(CharSequence, CharSequence...)}.
     */
    @Deprecated
    public static boolean equalsAny(final CharSequence string, final CharSequence... searchStrings) {
        return Strings.CS.equalsAny(string, searchStrings);
    }

    /**
     * Compares given {@code string} to a CharSequences vararg of {@code searchStrings},
     * returning {@code true} if the {@code string} is equal to any of the {@code searchStrings}, ignoring case.
     *
     * <pre>
     * StringUtils.equalsAnyIgnoreCase(null, (CharSequence[]) null) = false
     * StringUtils.equalsAnyIgnoreCase(null, null, null)    = true
     * StringUtils.equalsAnyIgnoreCase(null, "abc", "def")  = false
     * StringUtils.equalsAnyIgnoreCase("abc", null, "def")  = false
     * StringUtils.equalsAnyIgnoreCase("abc", "abc", "def") = true
     * StringUtils.equalsAnyIgnoreCase("abc", "ABC", "DEF") = true
     * </pre>
     *
     * @param string to compare, may be {@code null}.
     * @param searchStrings a vararg of strings, may be {@code null}.
     * @return {@code true} if the string is equal (case-insensitive) to any other element of {@code searchStrings};
     * {@code false} if {@code searchStrings} is null or contains no matches.
     * @since 3.5
     * @deprecated Use {@link Strings#equalsAny(CharSequence, CharSequence...) Strings.CI.equalsAny(CharSequence, CharSequence...)}.
     */
    @Deprecated
    public static boolean equalsAnyIgnoreCase(final CharSequence string, final CharSequence... searchStrings) {
        return Strings.CI.equalsAny(string, searchStrings);
    }

    /**
     * Compares two CharSequences, returning {@code true} if they represent equal sequences of characters, ignoring case.
     *
     * <p>
     * {@code null}s are handled without exceptions. Two {@code null} references are considered equal. The comparison is <strong>case insensitive</strong>.
     * </p>
     *
     * <pre>
     * StringUtils.equalsIgnoreCase(null, null)   = true
     * StringUtils.equalsIgnoreCase(null, "abc")  = false
     * StringUtils.equalsIgnoreCase("abc", null)  = false
     * StringUtils.equalsIgnoreCase("abc", "abc") = true
     * StringUtils.equalsIgnoreCase("abc", "ABC") = true
     * </pre>
     *
     * @param cs1 the first CharSequence, may be {@code null}.
     * @param cs2 the second CharSequence, may be {@code null}.
     * @return {@code true} if the CharSequences are equal (case-insensitive), or both {@code null}.
     * @since 3.0 Changed signature from equalsIgnoreCase(String, String) to equalsIgnoreCase(CharSequence, CharSequence)
     * @see #equals(CharSequence, CharSequence)
     * @deprecated Use {@link Strings#equals(CharSequence, CharSequence) Strings.CI.equals(CharSequence, CharSequence)}.
     */
    @Deprecated
    public static boolean equalsIgnoreCase(final CharSequence cs1, final CharSequence cs2) {
        return Strings.CI.equals(cs1, cs2);
    }

    /**
     * Returns the first value in the array which is not empty (""), {@code null} or whitespace only.
     *
     * <p>
     * Whitespace is defined by {@link Character#isWhitespace(char)}.
     * </p>
     *
     * <p>
     * If all values are blank or the array is {@code null} or empty then {@code null} is returned.
     * </p>
     *
     * <pre>
     * StringUtils.firstNonBlank(null, null, null)     = null
     * StringUtils.firstNonBlank(null, "", " ")        = null
     * StringUtils.firstNonBlank("abc")                = "abc"
     * StringUtils.firstNonBlank(null, "xyz")          = "xyz"
     * StringUtils.firstNonBlank(null, "", " ", "xyz") = "xyz"
     * StringUtils.firstNonBlank(null, "xyz", "abc")   = "xyz"
     * StringUtils.firstNonBlank()                     = null
     * </pre>
     *
     * @param <T>    the specific kind of CharSequence.
     * @param values the values to test, may be {@code null} or empty.
     * @return the first value from {@code values} which is not blank, or {@code null} if there are no non-blank values.
     * @since 3.8
     */
    @SafeVarargs
    public static <T extends CharSequence> T firstNonBlank(final T... values) {
        if (values != null) {
            for (final T val : values) {
                if (isNotBlank(val)) {
                    return val;
                }
            }
        }
        return null;
    }

    /**
     * Returns the first value in the array which is not empty.
     *
     * <p>
     * If all values are empty or the array is {@code null} or empty then {@code null} is returned.
     * </p>
     *
     * <pre>
     * StringUtils.firstNonEmpty(null, null, null)   = null
     * StringUtils.firstNonEmpty(null, null, "")     = null
     * StringUtils.firstNonEmpty(null, "", " ")      = " "
     * StringUtils.firstNonEmpty("abc")              = "abc"
     * StringUtils.firstNonEmpty(null, "xyz")        = "xyz"
     * StringUtils.firstNonEmpty("", "xyz")          = "xyz"
     * StringUtils.firstNonEmpty(null, "xyz", "abc") = "xyz"
     * StringUtils.firstNonEmpty()                   = null
     * </pre>
     *
     * @param <T>    the specific kind of CharSequence.
     * @param values the values to test, may be {@code null} or empty.
     * @return the first value from {@code values} which is not empty, or {@code null} if there are no non-empty values.
     * @since 3.8
     */
    @SafeVarargs
    public static <T extends CharSequence> T firstNonEmpty(final T... values) {
        if (values != null) {
            for (final T val : values) {
                if (isNotEmpty(val)) {
                    return val;
                }
            }
        }
        return null;
    }

    /**
     * Calls {@link String#getBytes(Charset)} in a null-safe manner.
     *
     * @param string input string.
     * @param charset The {@link Charset} to encode the {@link String}. If null, then use the default Charset.
     * @return The empty byte[] if {@code string} is null, the result of {@link String#getBytes(Charset)} otherwise.
     * @see String#getBytes(Charset)
     * @since 3.10
     */
    public static byte[] getBytes(final String string, final Charset charset) {
        return string == null ? ArrayUtils.EMPTY_BYTE_ARRAY : string.getBytes(Charsets.toCharset(charset));
    }

    /**
     * Calls {@link String#getBytes(String)} in a null-safe manner.
     *
     * @param string input string.
     * @param charset The {@link Charset} name to encode the {@link String}. If null, then use the default Charset.
     * @return The empty byte[] if {@code string} is null, the result of {@link String#getBytes(String)} otherwise.
     * @throws UnsupportedEncodingException Thrown when the named charset is not supported.
     * @see String#getBytes(String)
     * @since 3.10
     */
    public static byte[] getBytes(final String string, final String charset) throws UnsupportedEncodingException {
        return string == null ? ArrayUtils.EMPTY_BYTE_ARRAY : string.getBytes(Charsets.toCharsetName(charset));
    }

    /**
     * Compares all Strings in an array and returns the initial sequence of characters that is common to all of them.
     *
     * <p>
     * For example, {@code getCommonPrefix("i am a machine", "i am a robot") -&gt; "i am a "}
     * </p>
     *
     * <pre>
     * StringUtils.getCommonPrefix(null)                             = ""
     * StringUtils.getCommonPrefix(new String[] {})                  = ""
     * StringUtils.getCommonPrefix(new String[] {"abc"})             = "abc"
     * StringUtils.getCommonPrefix(new String[] {null, null})        = ""
     * StringUtils.getCommonPrefix(new String[] {"", ""})            = ""
     * StringUtils.getCommonPrefix(new String[] {"", null})          = ""
     * StringUtils.getCommonPrefix(new String[] {"abc", null, null}) = ""
     * StringUtils.getCommonPrefix(new String[] {null, null, "abc"}) = ""
     * StringUtils.getCommonPrefix(new String[] {"", "abc"})         = ""
     * StringUtils.getCommonPrefix(new String[] {"abc", ""})         = ""
     * StringUtils.getCommonPrefix(new String[] {"abc", "abc"})      = "abc"
     * StringUtils.getCommonPrefix(new String[] {"abc", "a"})        = "a"
     * StringUtils.getCommonPrefix(new String[] {"ab", "abxyz"})     = "ab"
     * StringUtils.getCommonPrefix(new String[] {"abcde", "abxyz"})  = "ab"
     * StringUtils.getCommonPrefix(new String[] {"abcde", "xyz"})    = ""
     * StringUtils.getCommonPrefix(new String[] {"xyz", "abcde"})    = ""
     * StringUtils.getCommonPrefix(new String[] {"i am a machine", "i am a robot"}) = "i am a "
     * </pre>
     *
     * @param strs array of String objects, entries may be null.
     * @return the initial sequence of characters that are common to all Strings in the array; empty String if the array is null, the elements are all null or
     *         if there is no common prefix.
     * @since 2.4
     */
    public static String getCommonPrefix(final String... strs) {
        if (ArrayUtils.isEmpty(strs)) {
            return EMPTY;
        }
        final int smallestIndexOfDiff = indexOfDifference(strs);
        if (smallestIndexOfDiff == INDEX_NOT_FOUND) {
            // all strings were identical
            if (strs[0] == null) {
                return EMPTY;
            }
            return strs[0];
        }
        if (smallestIndexOfDiff == 0) {
            // there were no common initial characters
            return EMPTY;
        }
        // we found a common initial character sequence
        return strs[0].substring(0, smallestIndexOfDiff);
    }

    /**
     * Checks if a String {@code str} contains Unicode digits, if yes then concatenate all the digits in {@code str} and return it as a String.
     *
     * <p>
     * An empty ("") String will be returned if no digits found in {@code str}.
     * </p>
     *
     * <pre>
     * StringUtils.getDigits(null)                 = null
     * StringUtils.getDigits("")                   = ""
     * StringUtils.getDigits("abc")                = ""
     * StringUtils.getDigits("1000$")              = "1000"
     * StringUtils.getDigits("1123~45")            = "112345"
     * StringUtils.getDigits("(541) 754-3010")     = "5417543010"
     * StringUtils.getDigits("\u0967\u0968\u0969") = "\u0967\u0968\u0969"
     * </pre>
     *
     * @param str the String to extract digits from, may be null.
     * @return String with only digits, or an empty ("") String if no digits found, or {@code null} String if {@code str} is null.
     * @since 3.6
     */
    public static String getDigits(final String str) {
        if (isEmpty(str)) {
            return str;
        }
        final int len = str.length();
        final char[] buffer = new char[len];
        int count = 0;

        for (int i = 0; i < len; i++) {
            final char tempChar = str.charAt(i);
            if (Character.isDigit(tempChar)) {
                buffer[count++] = tempChar;
            }
        }
        return new String(buffer, 0, count);
    }

    /**
     * Gets the Fuzzy Distance which indicates the similarity score between two Strings.
     *
     * <p>
     * This string matching algorithm is similar to the algorithms of editors such as Sublime Text, TextMate, Atom and others. One point is given for every
     * matched character. Subsequent matches yield two bonus points. A higher score indicates a higher similarity.
     * </p>
     *
     * <pre>
     * StringUtils.getFuzzyDistance(null, null, null)                                    = Throws {@link IllegalArgumentException}
     * StringUtils.getFuzzyDistance("", "", Locale.ENGLISH)                              = 0
     * StringUtils.getFuzzyDistance("Workshop", "b", Locale.ENGLISH)                     = 0
     * StringUtils.getFuzzyDistance("Room", "o", Locale.ENGLISH)                         = 1
     * StringUtils.getFuzzyDistance("Workshop", "w", Locale.ENGLISH)                     = 1
     * StringUtils.getFuzzyDistance("Workshop", "ws", Locale.ENGLISH)                    = 2
     * StringUtils.getFuzzyDistance("Workshop", "wo", Locale.ENGLISH)                    = 4
     * StringUtils.getFuzzyDistance("Apache Software Foundation", "asf", Locale.ENGLISH) = 3
     * </pre>
     *
     * @param term   a full term that should be matched against, must not be null.
     * @param query  the query that will be matched against a term, must not be null.
     * @param locale This string matching logic is case-insensitive. A locale is necessary to normalize both Strings to lower case.
     * @return result score.
     * @throws IllegalArgumentException if either String input {@code null} or Locale input {@code null}.
     * @since 3.4
     * @deprecated As of 3.6, use Apache Commons Text
     *             <a href="https://commons.apache.org/proper/commons-text/javadocs/api-release/org/apache/commons/text/similarity/FuzzyScore.html">
     *             FuzzyScore</a> instead.
     */
    @Deprecated
    public static int getFuzzyDistance(final CharSequence term, final CharSequence query, final Locale locale) {
        if (term == null || query == null) {
            throw new IllegalArgumentException("Strings must not be null");
        }
        if (locale == null) {
            throw new IllegalArgumentException("Locale must not be null");
        }
        // fuzzy logic is case-insensitive. We normalize the Strings to lower
        // case right from the start. Turning characters to lower case
        // via Character.toLowerCase(char) is unfortunately insufficient
        // as it does not accept a locale.
        final String termLowerCase = term.toString().toLowerCase(locale);
        final String queryLowerCase = query.toString().toLowerCase(locale);
        // the resulting score
        int score = 0;
        // the position in the term which will be scanned next for potential
        // query character matches
        int termIndex = 0;
        // index of the previously matched character in the term
        int previousMatchingCharacterIndex = Integer.MIN_VALUE;
        for (int queryIndex = 0; queryIndex < queryLowerCase.length(); queryIndex++) {
            final char queryChar = queryLowerCase.charAt(queryIndex);
            boolean termCharacterMatchFound = false;
            for (; termIndex < termLowerCase.length() && !termCharacterMatchFound; termIndex++) {
                final char termChar = termLowerCase.charAt(termIndex);
                if (queryChar == termChar) {
                    // simple character matches result in one point
                    score++;
                    // subsequent character matches further improve
                    // the score.
                    if (previousMatchingCharacterIndex + 1 == termIndex) {
                        score += 2;
                    }
                    previousMatchingCharacterIndex = termIndex;
                    // we can leave the nested loop. Every character in the
                    // query can match at most one character in the term.
                    termCharacterMatchFound = true;
                }
            }
        }
        return score;
    }

    /**
     * Returns either the passed in CharSequence, or if the CharSequence is {@link #isBlank(CharSequence) blank} (whitespaces, empty ({@code ""}), or
     * {@code null}), the value supplied by {@code defaultStrSupplier}.
     *
     * <p>
     * Whitespace is defined by {@link Character#isWhitespace(char)}.
     * </p>
     *
     * <p>
     * Caller responsible for thread-safety and exception handling of default value supplier
     * </p>
     *
     * <pre>
     * {@code
     * StringUtils.getIfBlank(null, () -> "NULL")   = "NULL"
     * StringUtils.getIfBlank("", () -> "NULL")     = "NULL"
     * StringUtils.getIfBlank(" ", () -> "NULL")    = "NULL"
     * StringUtils.getIfBlank("bat", () -> "NULL")  = "bat"
     * StringUtils.getIfBlank("", () -> null)       = null
     * StringUtils.getIfBlank("", null)             = null
     * }</pre>
     *
     * @param <T>             the specific kind of CharSequence.
     * @param str             the CharSequence to check, may be null.
     * @param defaultSupplier the supplier of default CharSequence to return if the input is {@link #isBlank(CharSequence) blank} (whitespaces, empty
     *                        ({@code ""}), or {@code null}); may be null.
     * @return the passed in CharSequence, or the default
     * @see StringUtils#defaultString(String, String)
     * @see #isBlank(CharSequence)
     * @since 3.10
     */
    public static <T extends CharSequence> T getIfBlank(final T str, final Supplier<T> defaultSupplier) {
        return isBlank(str) ? Suppliers.get(defaultSupplier) : str;
    }

    /**
     * Returns either the passed in CharSequence, or if the CharSequence is empty or {@code null}, the value supplied by {@code defaultStrSupplier}.
     *
     * <p>
     * Caller responsible for thread-safety and exception handling of default value supplier
     * </p>
     *
     * <pre>
     * {@code
     * StringUtils.getIfEmpty(null, () -> "NULL")    = "NULL"
     * StringUtils.getIfEmpty("", () -> "NULL")      = "NULL"
     * StringUtils.getIfEmpty(" ", () -> "NULL")     = " "
     * StringUtils.getIfEmpty("bat", () -> "NULL")   = "bat"
     * StringUtils.getIfEmpty("", () -> null)        = null
     * StringUtils.getIfEmpty("", null)              = null
     * }
     * </pre>
     *
     * @param <T>             the specific kind of CharSequence.
     * @param str             the CharSequence to check, may be null.
     * @param defaultSupplier the supplier of default CharSequence to return if the input is empty ("") or {@code null}, may be null.
     * @return the passed in CharSequence, or the default.
     * @see StringUtils#defaultString(String, String)
     * @since 3.10
     */
    public static <T extends CharSequence> T getIfEmpty(final T str, final Supplier<T> defaultSupplier) {
        return isEmpty(str) ? Suppliers.get(defaultSupplier) : str;
    }

    /**
     * Gets the Jaro Winkler Distance which indicates the similarity score between two Strings.
     *
     * <p>
     * The Jaro measure is the weighted sum of percentage of matched characters from each file and transposed characters. Winkler increased this measure for
     * matching initial characters.
     * </p>
     *
     * <p>
     * This implementation is based on the Jaro Winkler similarity algorithm from
     * <a href="https://en.wikipedia.org/wiki/Jaro%E2%80%93Winkler_distance">https://en.wikipedia.org/wiki/Jaro%E2%80%93Winkler_distance</a>.
     * </p>
     *
     * <pre>
     * StringUtils.getJaroWinklerDistance(null, null)          = Throws {@link IllegalArgumentException}
     * StringUtils.getJaroWinklerDistance("", "")              = 0.0
     * StringUtils.getJaroWinklerDistance("", "a")             = 0.0
     * StringUtils.getJaroWinklerDistance("aaapppp", "")       = 0.0
     * StringUtils.getJaroWinklerDistance("frog", "fog")       = 0.93
     * StringUtils.getJaroWinklerDistance("fly", "ant")        = 0.0
     * StringUtils.getJaroWinklerDistance("elephant", "hippo") = 0.44
     * StringUtils.getJaroWinklerDistance("hippo", "elephant") = 0.44
     * StringUtils.getJaroWinklerDistance("hippo", "zzzzzzzz") = 0.0
     * StringUtils.getJaroWinklerDistance("hello", "hallo")    = 0.88
     * StringUtils.getJaroWinklerDistance("ABC Corporation", "ABC Corp") = 0.93
     * StringUtils.getJaroWinklerDistance("D N H Enterprises Inc", "D &amp; H Enterprises, Inc.") = 0.95
     * StringUtils.getJaroWinklerDistance("My Gym Children's Fitness Center", "My Gym. Childrens Fitness") = 0.92
     * StringUtils.getJaroWinklerDistance("PENNSYLVANIA", "PENNCISYLVNIA") = 0.88
     * </pre>
     *
     * @param first  the first String, must not be null.
     * @param second the second String, must not be null.
     * @return result distance.
     * @throws IllegalArgumentException if either String input {@code null}.
     * @since 3.3
     * @deprecated As of 3.6, use Apache Commons Text
     *             <a href="https://commons.apache.org/proper/commons-text/javadocs/api-release/org/apache/commons/text/similarity/JaroWinklerDistance.html">
     *             JaroWinklerDistance</a> instead.
     */
    @Deprecated
    public static double getJaroWinklerDistance(final CharSequence first, final CharSequence second) {
        final double DEFAULT_SCALING_FACTOR = 0.1;

        if (first == null || second == null) {
            throw new IllegalArgumentException("Strings must not be null");
        }

        final int[] mtp = matches(first, second);
        final double m = mtp[0];
        if (m == 0) {
            return 0D;
        }
        final double j = (m / first.length() + m / second.length() + (m - mtp[1]) / m) / 3;
        final double jw = j < 0.7D ? j : j + Math.min(DEFAULT_SCALING_FACTOR, 1D / mtp[3]) * mtp[2] * (1D - j);
        return Math.round(jw * 100.0D) / 100.0D;
    }

    /**
     * Gets the Levenshtein distance between two Strings.
     *
     * <p>
     * This is the number of changes needed to change one String into another, where each change is a single character modification (deletion, insertion or
     * substitution).
     * </p>
     *
     * <p>
     * The implementation uses a single-dimensional array of length s.length() + 1. See
     * <a href="https://blog.softwx.net/2014/12/optimizing-levenshtein-algorithm-in-c.html">
     * https://blog.softwx.net/2014/12/optimizing-levenshtein-algorithm-in-c.html</a> for details.
     * </p>
     *
     * <pre>
     * StringUtils.getLevenshteinDistance(null, *)             = Throws {@link IllegalArgumentException}
     * StringUtils.getLevenshteinDistance(*, null)             = Throws {@link IllegalArgumentException}
     * StringUtils.getLevenshteinDistance("", "")              = 0
     * StringUtils.getLevenshteinDistance("", "a")             = 1
     * StringUtils.getLevenshteinDistance("aaapppp", "")       = 7
     * StringUtils.getLevenshteinDistance("frog", "fog")       = 1
     * StringUtils.getLevenshteinDistance("fly", "ant")        = 3
     * StringUtils.getLevenshteinDistance("elephant", "hippo") = 7
     * StringUtils.getLevenshteinDistance("hippo", "elephant") = 7
     * StringUtils.getLevenshteinDistance("hippo", "zzzzzzzz") = 8
     * StringUtils.getLevenshteinDistance("hello", "hallo")    = 1
     * </pre>
     *
     * @param s the first String, must not be null.
     * @param t the second String, must not be null.
     * @return result distance.
     * @throws IllegalArgumentException if either String input {@code null}.
     * @since 3.0 Changed signature from getLevenshteinDistance(String, String) to getLevenshteinDistance(CharSequence, CharSequence)
     * @deprecated As of 3.6, use Apache Common
