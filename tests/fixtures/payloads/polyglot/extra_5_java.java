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

package org.apache.commons.io;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.ByteArrayInputStream;
import java.io.CharArrayWriter;
import java.io.Closeable;
import java.io.EOFException;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.PipedInputStream;
import java.io.PipedOutputStream;
import java.io.Reader;
import java.io.UncheckedIOException;
import java.io.Writer;
import java.net.HttpURLConnection;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URI;
import java.net.URL;
import java.net.URLConnection;
import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.channels.Channels;
import java.nio.channels.ReadableByteChannel;
import java.nio.channels.Selector;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.Collection;
import java.util.Iterator;
import java.util.List;
import java.util.Objects;
import java.util.function.Consumer;
import java.util.function.Supplier;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import java.util.zip.InflaterInputStream;

import org.apache.commons.io.channels.FileChannels;
import org.apache.commons.io.function.IOConsumer;
import org.apache.commons.io.function.IOSupplier;
import org.apache.commons.io.function.IOTriFunction;
import org.apache.commons.io.input.BoundedInputStream;
import org.apache.commons.io.input.CharSequenceReader;
import org.apache.commons.io.input.QueueInputStream;
import org.apache.commons.io.output.AppendableWriter;
import org.apache.commons.io.output.ByteArrayOutputStream;
import org.apache.commons.io.output.NullOutputStream;
import org.apache.commons.io.output.NullWriter;
import org.apache.commons.io.output.StringBuilderWriter;
import org.apache.commons.io.output.UnsynchronizedByteArrayOutputStream;

/**
 * General IO stream manipulation utilities.
 * <p>
 * This class provides static utility methods for input/output operations.
 * </p>
 * <ul>
 * <li>closeQuietly - these methods close a stream ignoring nulls and exceptions</li>
 * <li>toXxx/read - these methods read data from a stream</li>
 * <li>write - these methods write data to a stream</li>
 * <li>copy - these methods copy all the data from one stream to another</li>
 * <li>contentEquals - these methods compare the content of two streams</li>
 * </ul>
 * <p>
 * The byte-to-char methods and char-to-byte methods involve a conversion step. Two methods are provided in each case, one that uses the platform default
 * encoding and the other which allows you to specify an encoding. You are encouraged to always specify an encoding because relying on the platform default can
 * lead to unexpected results, for example when moving from development to production.
 * </p>
 * <p>
 * All the methods in this class that read a stream are buffered internally. This means that there is no cause to use a {@link BufferedInputStream} or
 * {@link BufferedReader}. The default buffer size of 4K has been shown to be efficient in tests.
 * </p>
 * <p>
 * The various copy methods all delegate the actual copying to one of the following methods:
 * </p>
 * <ul>
 * <li>{@link #copyLarge(InputStream, OutputStream, byte[])}</li>
 * <li>{@link #copyLarge(InputStream, OutputStream, long, long, byte[])}</li>
 * <li>{@link #copyLarge(Reader, Writer, char[])}</li>
 * <li>{@link #copyLarge(Reader, Writer, long, long, char[])}</li>
 * </ul>
 * For example, {@link #copy(InputStream, OutputStream)} calls {@link #copyLarge(InputStream, OutputStream)} which calls
 * {@link #copy(InputStream, OutputStream, int)} which creates the buffer and calls {@link #copyLarge(InputStream, OutputStream, byte[])}.
 * <p>
 * Applications can re-use buffers by using the underlying methods directly. This may improve performance for applications that need to do a lot of copying.
 * </p>
 * <p>
 * Wherever possible, the methods in this class do <em>not</em> flush or close the stream. This is to avoid making non-portable assumptions about the streams'
 * origin and further use. Thus the caller is still responsible for closing streams after use.
 * </p>
 * <p>
 * Provenance: Excalibur.
 * </p>
 */
public class IOUtils {
    // NOTE: This class is focused on InputStream, OutputStream, Reader and
    // Writer. Each method should take at least one of these as a parameter,
    // or return one of them.

    /**
     * Holder for per-thread internal scratch buffer.
     * <p>
     * Buffers are created lazily and reused within the same thread to reduce allocation overhead. In the rare case of reentrant access, a temporary buffer is
     * allocated to avoid data corruption.
     * </p>
     * <p>
     * Typical usage:
     * </p>
     *
     * <pre>{@code
     * try (ScratchBytes scratch = ScratchBytes.get()) {
     *     // use the buffer
     *     byte[] bytes = scratch.array();
     *     // ...
     * }
     * }</pre>
     */
    static final class ScratchBytes implements AutoCloseable {

        /**
         * Wraps an internal byte array. [0] boolean in use. [1] byte[] buffer.
         */
        private static final ThreadLocal<Object[]> LOCAL = ThreadLocal.withInitial(() -> new Object[] { false, byteArray() });

        private static final ScratchBytes INSTANCE = new ScratchBytes(null);

        /**
         * Gets the internal byte array buffer.
         *
         * @return the internal byte array buffer.
         */
        static ScratchBytes get() {
            final Object[] holder = LOCAL.get();
            // If already in use, return a new array
            if ((boolean) holder[0]) {
                return new ScratchBytes(byteArray());
            }
            holder[0] = true;
            return INSTANCE;
        }

        /**
         * The buffer, or null if using the thread-local buffer.
         */
        private final byte[] buffer;

        private ScratchBytes(final byte[] buffer) {
            this.buffer = buffer;
        }

        byte[] array() {
            return buffer != null ? buffer : (byte[]) LOCAL.get()[1];
        }

        /**
         * If the buffer is the internal array, clear and release it for reuse.
         */
        @Override
        public void close() {
            if (buffer == null) {
                final Object[] holder = LOCAL.get();
                Arrays.fill((byte[]) holder[1], (byte) 0);
                holder[0] = false;
            }
        }
    }

    /**
     * Holder for per-thread internal scratch buffer.
     * <p>
     * Buffers are created lazily and reused within the same thread to reduce allocation overhead. In the rare case of reentrant access, a temporary buffer is
     * allocated to avoid data corruption.
     * </p>
     * <p>
     * Typical usage:
     * </p>
     *
     * <pre>{@code
     * try (ScratchChars scratch = ScratchChars.get()) {
     *     // use the buffer
     *     char[] bytes = scratch.array();
     *     // ...
     * }
     * }</pre>
     */
    static final class ScratchChars implements AutoCloseable {

        /**
         * Wraps an internal char array. [0] boolean in use. [1] char[] buffer.
         */
        private static final ThreadLocal<Object[]> LOCAL = ThreadLocal.withInitial(() -> new Object[] { false, charArray() });

        private static final ScratchChars INSTANCE = new ScratchChars(null);

        /**
         * Gets the internal char array buffer.
         *
         * @return the internal char array buffer.
         */
        static ScratchChars get() {
            final Object[] holder = LOCAL.get();
            // If already in use, return a new array
            if ((boolean) holder[0]) {
                return new ScratchChars(charArray());
            }
            holder[0] = true;
            return INSTANCE;
        }

        /**
         * The buffer, or null if using the thread-local buffer.
         */
        private final char[] buffer;

        private ScratchChars(final char[] buffer) {
            this.buffer = buffer;
        }

        char[] array() {
            return buffer != null ? buffer : (char[]) LOCAL.get()[1];
        }

        /**
         * If the buffer is the internal array, clear and release it for reuse.
         */
        @Override
        public void close() {
            if (buffer == null) {
                final Object[] holder = LOCAL.get();
                Arrays.fill((char[]) holder[1], (char) 0);
                holder[0] = false;
            }
        }
    }

    /**
     * CR char '{@value}'.
     *
     * @since 2.9.0
     */
    public static final int CR = '\r';

    /**
     * The default buffer size ({@value}) to use in copy methods.
     */
    public static final int DEFAULT_BUFFER_SIZE = 8192;

    /**
     * The system directory separator character.
     */
    public static final char DIR_SEPARATOR = File.separatorChar;

    /**
     * The Unix directory separator character '{@value}'.
     */
    public static final char DIR_SEPARATOR_UNIX = '/';

    /**
     * The Windows directory separator character '{@value}'.
     */
    public static final char DIR_SEPARATOR_WINDOWS = '\\';

    /**
     * A singleton empty byte array.
     *
     * @since 2.9.0
     */
    public static final byte[] EMPTY_BYTE_ARRAY = {};

    /**
     * Represents the end-of-file (or stream) value {@value}.
     *
     * @since 2.5 (made public)
     */
    public static final int EOF = -1;

    /**
     * LF char '{@value}'.
     *
     * @since 2.9.0
     */
    public static final int LF = '\n';

    /**
     * The system line separator string.
     *
     * @deprecated Use {@link System#lineSeparator()}.
     */
    @Deprecated
    public static final String LINE_SEPARATOR = System.lineSeparator();

    /**
     * The Unix line separator string.
     *
     * @see StandardLineSeparator#LF
     */
    public static final String LINE_SEPARATOR_UNIX = StandardLineSeparator.LF.getString();

    /**
     * The Windows line separator string.
     *
     * @see StandardLineSeparator#CRLF
     */
    public static final String LINE_SEPARATOR_WINDOWS = StandardLineSeparator.CRLF.getString();

    /**
     * The maximum size of an array in many Java VMs.
     * <p>
     * The constant is copied from OpenJDK's {@code jdk.internal.util.ArraysSupport#SOFT_MAX_ARRAY_LENGTH}.
     * </p>
     *
     * @since 2.21.0
     */
    public static final int SOFT_MAX_ARRAY_LENGTH = Integer.MAX_VALUE - 8;

    /**
     * Returns the given InputStream if it is already a {@link BufferedInputStream}, otherwise creates a BufferedInputStream from the given InputStream.
     *
     * @param inputStream the InputStream to wrap or return (not null).
     * @return the given InputStream or a new {@link BufferedInputStream} for the given InputStream.
     * @throws NullPointerException if the input parameter is null.
     * @since 2.5
     */
    @SuppressWarnings("resource") // parameter null check
    public static BufferedInputStream buffer(final InputStream inputStream) {
        // reject null early on rather than waiting for IO operation to fail
        // not checked by BufferedInputStream
        Objects.requireNonNull(inputStream, "inputStream");
        return inputStream instanceof BufferedInputStream ? (BufferedInputStream) inputStream : new BufferedInputStream(inputStream);
    }

    /**
     * Returns the given InputStream if it is already a {@link BufferedInputStream}, otherwise creates a BufferedInputStream from the given InputStream.
     *
     * @param inputStream the InputStream to wrap or return (not null).
     * @param size        the buffer size, if a new BufferedInputStream is created.
     * @return the given InputStream or a new {@link BufferedInputStream} for the given InputStream.
     * @throws NullPointerException if the input parameter is null.
     * @since 2.5
     */
    @SuppressWarnings("resource") // parameter null check
    public static BufferedInputStream buffer(final InputStream inputStream, final int size) {
        // reject null early on rather than waiting for IO operation to fail
        // not checked by BufferedInputStream
        Objects.requireNonNull(inputStream, "inputStream");
        return inputStream instanceof BufferedInputStream ? (BufferedInputStream) inputStream : new BufferedInputStream(inputStream, size);
    }

    /**
     * Returns the given OutputStream if it is already a {@link BufferedOutputStream}, otherwise creates a BufferedOutputStream from the given OutputStream.
     *
     * @param outputStream the OutputStream to wrap or return (not null).
     * @return the given OutputStream or a new {@link BufferedOutputStream} for the given OutputStream.
     * @throws NullPointerException if the input parameter is null.
     * @since 2.5
     */
    @SuppressWarnings("resource") // parameter null check
    public static BufferedOutputStream buffer(final OutputStream outputStream) {
        // reject null early on rather than waiting for IO operation to fail
        // not checked by BufferedInputStream
        Objects.requireNonNull(outputStream, "outputStream");
        return outputStream instanceof BufferedOutputStream ? (BufferedOutputStream) outputStream : new BufferedOutputStream(outputStream);
    }

    /**
     * Returns the given OutputStream if it is already a {@link BufferedOutputStream}, otherwise creates a BufferedOutputStream from the given OutputStream.
     *
     * @param outputStream the OutputStream to wrap or return (not null).
     * @param size         the buffer size, if a new BufferedOutputStream is created.
     * @return the given OutputStream or a new {@link BufferedOutputStream} for the given OutputStream.
     * @throws NullPointerException if the input parameter is null.
     * @since 2.5
     */
    @SuppressWarnings("resource") // parameter null check
    public static BufferedOutputStream buffer(final OutputStream outputStream, final int size) {
        // reject null early on rather than waiting for IO operation to fail
        // not checked by BufferedInputStream
        Objects.requireNonNull(outputStream, "outputStream");
        return outputStream instanceof BufferedOutputStream ? (BufferedOutputStream) outputStream : new BufferedOutputStream(outputStream, size);
    }

    /**
     * Returns the given reader if it is already a {@link BufferedReader}, otherwise creates a BufferedReader from the given reader.
     *
     * @param reader the reader to wrap or return (not null).
     * @return the given reader or a new {@link BufferedReader} for the given reader.
     * @throws NullPointerException if the input parameter is null.
     * @since 2.5
     */
    public static BufferedReader buffer(final Reader reader) {
        return reader instanceof BufferedReader ? (BufferedReader) reader : new BufferedReader(reader);
    }

    /**
     * Returns the given reader if it is already a {@link BufferedReader}, otherwise creates a BufferedReader from the given reader.
     *
     * @param reader the reader to wrap or return (not null).
     * @param size   the buffer size, if a new BufferedReader is created.
     * @return the given reader or a new {@link BufferedReader} for the given reader.
     * @throws NullPointerException if the input parameter is null.
     * @since 2.5
     */
    public static BufferedReader buffer(final Reader reader, final int size) {
        return reader instanceof BufferedReader ? (BufferedReader) reader : new BufferedReader(reader, size);
    }

    /**
     * Returns the given Writer if it is already a {@link BufferedWriter}, otherwise creates a BufferedWriter from the given Writer.
     *
     * @param writer the Writer to wrap or return (not null).
     * @return the given Writer or a new {@link BufferedWriter} for the given Writer.
     * @throws NullPointerException if the input parameter is null.
     * @since 2.5
     */
    public static BufferedWriter buffer(final Writer writer) {
        return writer instanceof BufferedWriter ? (BufferedWriter) writer : new BufferedWriter(writer);
    }

    /**
     * Returns the given Writer if it is already a {@link BufferedWriter}, otherwise creates a BufferedWriter from the given Writer.
     *
     * @param writer the Writer to wrap or return (not null).
     * @param size   the buffer size, if a new BufferedWriter is created.
     * @return the given Writer or a new {@link BufferedWriter} for the given Writer.
     * @throws NullPointerException if the input parameter is null.
     * @since 2.5
     */
    public static BufferedWriter buffer(final Writer writer, final int size) {
        return writer instanceof BufferedWriter ? (BufferedWriter) writer : new BufferedWriter(writer, size);
    }

    /**
     * Returns a new byte array of size {@link #DEFAULT_BUFFER_SIZE}.
     *
     * @return a new byte array of size {@link #DEFAULT_BUFFER_SIZE}.
     * @since 2.9.0
     */
    public static byte[] byteArray() {
        return byteArray(DEFAULT_BUFFER_SIZE);
    }

    /**
     * Returns a new byte array of the given size. TODO Consider guarding or warning against large allocations.
     *
     * @param size array size.
     * @return a new byte array of the given size.
     * @throws NegativeArraySizeException if the size is negative.
     * @since 2.9.0
     */
    public static byte[] byteArray(final int size) {
        return new byte[size];
    }

    /**
     * Returns a new char array of size {@link #DEFAULT_BUFFER_SIZE}.
     *
     * @return a new char array of size {@link #DEFAULT_BUFFER_SIZE}.
     * @since 2.9.0
     */
    private static char[] charArray() {
        return charArray(DEFAULT_BUFFER_SIZE);
    }

    /**
     * Returns a new char array of the given size. TODO Consider guarding or warning against large allocations.
     *
     * @param size array size.
     * @return a new char array of the given size.
     * @since 2.9.0
     */
    private static char[] charArray(final int size) {
        return new char[size];
    }

    /**
     * Validates that the sub-range {@code [off, off + len)} is within the bounds of the given array.
     * <p>
     * The range is valid if all of the following hold:
     * </p>
     * <ul>
     * <li>{@code off >= 0}</li>
     * <li>{@code len >= 0}</li>
     * <li>{@code off + len <= array.length}</li>
     * </ul>
     * <p>
     * If the range is invalid, throws {@link IndexOutOfBoundsException} with a descriptive message.
     * </p>
     * <p>
     * Typical usage in {@link InputStream#read(byte[], int, int)} and {@link OutputStream#write(byte[], int, int)} implementations:
     * </p>
     *
     * <pre>
     * <code>
     * public int read(byte[] b, int off, int len) throws IOException {
     *     IOUtils.checkFromIndexSize(b, off, len);
     *     if (len == 0) {
     *         return 0;
     *     }
     *     ensureOpen();
     *     // perform read...
     * }
     *
     * public void write(byte[] b, int off, int len) throws IOException {
     *     IOUtils.checkFromIndexSize(b, off, len);
     *     if (len == 0) {
     *         return;
     *     }
     *     ensureOpen();
     *     // perform write...
     * }
     * </code>
     * </pre>
     *
     * @param array the array against which the range is validated.
     * @param off   the starting offset into the array (inclusive).
     * @param len   the number of elements to access.
     * @throws NullPointerException      if {@code array} is {@code null}.
     * @throws IndexOutOfBoundsException if the range {@code [off, off + len)} is out of bounds for {@code array}.
     * @see InputStream#read(byte[], int, int)
     * @see OutputStream#write(byte[], int, int)
     * @since 2.21.0
     */
    public static void checkFromIndexSize(final byte[] array, final int off, final int len) {
        checkFromIndexSize(off, len, Objects.requireNonNull(array, "byte array").length);
    }

    /**
     * Validates that the sub-range {@code [off, off + len)} is within the bounds of the given array.
     * <p>
     * The range is valid if all of the following hold:
     * </p>
     * <ul>
     * <li>{@code off >= 0}</li>
     * <li>{@code len >= 0}</li>
     * <li>{@code off + len <= array.length}</li>
     * </ul>
     * <p>
     * If the range is invalid, throws {@link IndexOutOfBoundsException} with a descriptive message.
     * </p>
     * <p>
     * Typical usage in {@link Reader#read(char[], int, int)} and {@link Writer#write(char[], int, int)} implementations:
     * </p>
     *
     * <pre>
     * <code>
     * public int read(char[] cbuf, int off, int len) throws IOException {
     *     ensureOpen();
     *     IOUtils.checkFromIndexSize(cbuf, off, len);
     *     if (len == 0) {
     *         return 0;
     *     }
     *     // perform read...
     * }
     *
     * public void write(char[] cbuf, int off, int len) throws IOException {
     *     ensureOpen();
     *     IOUtils.checkFromIndexSize(cbuf, off, len);
     *     if (len == 0) {
     *         return;
     *     }
     *     // perform write...
     * }
     * </code>
     * </pre>
     *
     * @param array the array against which the range is validated.
     * @param off   the starting offset into the array (inclusive).
     * @param len   the number of characters to access.
     * @throws NullPointerException      if {@code array} is {@code null}.
     * @throws IndexOutOfBoundsException if the range {@code [off, off + len)} is out of bounds for {@code array}.
     * @see Reader#read(char[], int, int)
     * @see Writer#write(char[], int, int)
     * @since 2.21.0
     */
    public static void checkFromIndexSize(final char[] array, final int off, final int len) {
        checkFromIndexSize(off, len, Objects.requireNonNull(array, "char array").length);
    }

    static void checkFromIndexSize(final int off, final int len, final int arrayLength) {
        if ((off | len | arrayLength) < 0 || arrayLength - len < off) {
            throw new IndexOutOfBoundsException(String.format("Range [%s, %<s + %s) out of bounds for length %s", off, len, arrayLength));
        }
    }

    /**
     * Validates that the sub-range {@code [off, off + len)} is within the bounds of the given string.
     * <p>
     * The range is valid if all of the following hold:
     * </p>
     * <ul>
     * <li>{@code off >= 0}</li>
     * <li>{@code len >= 0}</li>
     * <li>{@code off + len <= str.length()}</li>
     * </ul>
     * <p>
     * If the range is invalid, throws {@link IndexOutOfBoundsException} with a descriptive message.
     * </p>
     * <p>
     * Typical usage in {@link Writer#write(String, int, int)} implementations:
     * </p>
     *
     * <pre>
     * <code>
     * public void write(String str, int off, int len) throws IOException {
     *     IOUtils.checkFromIndexSize(str, off, len);
     *     if (len == 0) {
     *         return;
     *     }
     *     // perform write...
     * }
     * </code>
     * </pre>
     *
     * @param str the string against which the range is validated.
     * @param off the starting offset into the string (inclusive).
     * @param len the number of characters to write.
     * @throws NullPointerException      if {@code str} is {@code null}.
     * @throws IndexOutOfBoundsException if the range {@code [off, off + len)} is out of bounds for {@code str}.
     * @see Writer#write(String, int, int)
     * @since 2.21.0
     */
    public static void checkFromIndexSize(final String str, final int off, final int len) {
        checkFromIndexSize(off, len, Objects.requireNonNull(str, "str").length());
    }

    /**
     * Validates that the sub-sequence {@code [fromIndex, toIndex)} is within the bounds of the given {@link CharSequence}.
     * <p>
     * The sub-sequence is valid if all of the following hold:
     * </p>
     * <ul>
     * <li>{@code fromIndex >= 0}</li>
     * <li>{@code fromIndex <= toIndex}</li>
     * <li>{@code toIndex <= seq.length()}</li>
     * </ul>
     * <p>
     * If {@code seq} is {@code null}, it is treated as the literal string {@code "null"} (length {@code 4}).
     * </p>
     * <p>
     * If the range is invalid, throws {@link IndexOutOfBoundsException} with a descriptive message.
     * </p>
     * <p>
     * Typical usage in {@link Appendable#append(CharSequence, int, int)} implementations:
     * </p>
     *
     * <pre>
     * <code>
     * public Appendable append(CharSequence csq, int start, int end) throws IOException {
     *     IOUtils.checkFromToIndex(csq, start, end);
     *     // perform append...
     *     return this;
     * }
     * </code>
     * </pre>
     *
     * @param seq       the character sequence to validate (may be {@code null}, treated as {@code "null"}).
     * @param fromIndex the starting index (inclusive).
     * @param toIndex   the ending index (exclusive).
     * @throws IndexOutOfBoundsException if the range {@code [fromIndex, toIndex)} is out of bounds for {@code seq}.
     * @see Appendable#append(CharSequence, int, int)
     * @since 2.21.0
     */
    public static void checkFromToIndex(final CharSequence seq, final int fromIndex, final int toIndex) {
        checkFromToIndex(fromIndex, toIndex, seq != null ? seq.length() : 4);
    }

    static void checkFromToIndex(final int fromIndex, final int toIndex, final int length) {
        if (fromIndex < 0 || toIndex < fromIndex || length < toIndex) {
            throw new IndexOutOfBoundsException(String.format("Range [%s, %s) out of bounds for length %s", fromIndex, toIndex, length));
        }
    }

    /**
     * Clears any state.
     * <ul>
     * <li>Removes the current thread's value for thread-local variables.</li>
     * <li>Sets static scratch arrays to 0s.</li>
     * </ul>
     *
     * @see IO#clear()
     */
    static void clear() {
        ScratchBytes.LOCAL.remove();
        ScratchChars.LOCAL.remove();
    }

    /**
     * Closes the given {@link Closeable} as a null-safe operation.
     *
     * @param closeable The resource to close, may be null.
     * @throws IOException if an I/O error occurs.
     * @since 2.7
     */
    public static void close(final Closeable closeable) throws IOException {
        if (closeable != null) {
            closeable.close();
        }
    }

    /**
     * Closes the given {@link Closeable}s as null-safe operations.
     *
     * @param closeables The resource(s) to close, may be null.
     * @throws IOExceptionList if an I/O error occurs.
     * @since 2.8.0
     */
    public static void close(final Closeable... closeables) throws IOExceptionList {
        IOConsumer.forAll(IOUtils::close, closeables);
    }

    /**
     * Closes the given {@link Closeable} as a null-safe operation.
     *
     * @param closeable The resource to close, may be null.
     * @param consumer  Consume the IOException thrown by {@link Closeable#close()}.
     * @throws IOException if an I/O error occurs.
     * @since 2.7
     */
    public static void close(final Closeable closeable, final IOConsumer<IOException> consumer) throws IOException {
        if (closeable != null) {
            try {
                closeable.close();
            } catch (final IOException e) {
                if (consumer != null) {
                    consumer.accept(e);
                }
            } catch (final Exception e) {
                if (consumer != null) {
                    consumer.accept(new IOException(e));
                }
            }
        }
    }

    /**
     * Closes a URLConnection.
     *
     * @param conn the connection to close.
     * @since 2.4
     */
    public static void close(final URLConnection conn) {
        if (conn instanceof HttpURLConnection) {
            ((HttpURLConnection) conn).disconnect();
        }
    }

    /**
     * Avoids the need to type cast.
     *
     * @param closeable the object to close, may be null.
     */
    private static void closeQ(final Closeable closeable) {
        closeQuietly(closeable, (Consumer<Exception>) null);
    }

    /**
     * Closes a {@link Closeable} unconditionally.
     * <p>
     * Equivalent to {@link Closeable#close()}, except any exceptions will be ignored. This is typically used in finally blocks.
     * <p>
     * Example code:
     * </p>
     *
     * <pre>
     * Closeable closeable = null;
     * try {
     *     closeable = new FileReader(&quot;foo.txt&quot;);
     *     // process closeable
     *     closeable.close();
     * } catch (Exception e) {
     *     // error handling
     * } finally {
     *     IOUtils.closeQuietly(closeable);
     * }
     * </pre>
     * <p>
     * Closing all streams:
     * </p>
     *
     * <pre>
     * try {
     *     return IOUtils.copy(inputStream, outputStream);
     * } finally {
     *     IOUtils.closeQuietly(inputStream);
     *     IOUtils.closeQuietly(outputStream);
     * }
     * </pre>
     * <p>
     * Also consider using a try-with-resources statement where appropriate.
     * </p>
     *
     * @param closeable the objects to close, may be null or already closed.
     * @since 2.0
     * @see Throwable#addSuppressed(Throwable)
     */
    public static void closeQuietly(final Closeable closeable) {
        closeQuietly(closeable, (Consumer<Exception>) null);
    }

    /**
     * Closes a {@link Closeable} unconditionally.
     * <p>
     * Equivalent to {@link Closeable#close()}, except any exceptions will be ignored.
     * <p>
     * This is typically used in finally blocks to ensure that the closeable is closed even if an Exception was thrown before the normal close statement was
     * reached.
     * </p>
     * <p>
     * <strong>It should not be used to replace the close statement(s) which should be present for the non-exceptional case.</strong>
     * </p>
     * It is only intended to simplify tidying up where normal processing has already failed and reporting close failure as well is not necessary or useful.
     * <p>
     * Example code:
     * </p>
     *
     * <pre>
     * Closeable closeable = null;
     * try {
     *     closeable = new FileReader(&quot;foo.txt&quot;);
     *     // processing using the closeable; may throw an Exception
     *     closeable.close(); // Normal close - exceptions not ignored
     * } catch (Exception e) {
     *     // error handling
     * } finally {
     *     <strong>IOUtils.closeQuietly(closeable); // In case normal close was skipped due to Exception</strong>
     * }
     * </pre>
     * <p>
     * Closing all streams:
     * </p>
     *
     * <pre>
     * try {
     *     return IOUtils.copy(inputStream, outputStream);
     * } finally {
     *     IOUtils.closeQuietly(inputStream, outputStream);
     * }
     * </pre>
     * <p>
     * Also consider using a try-with-resources statement where appropriate.
     * </p>
     *
     * @param closeables the objects to close, may be null or already closed.
     * @see #closeQuietly(Closeable)
     * @since 2.5
     * @see Throwable#addSuppressed(Throwable)
     */
    public static void closeQuietly(final Closeable... closeables) {
        if (closeables != null) {
            closeQuietly(Arrays.stream(closeables));
        }
    }

    /**
     * Closes the given {@link Closeable} as a null-safe operation while consuming IOException by the given {@code consumer}.
     *
     * @param closeable The resource to close, may be null.
     * @param consumer  Consumes the Exception thrown by {@link Closeable#close()}.
     * @since 2.7
     */
    public static void closeQuietly(final Closeable closeable, final Consumer<Exception> consumer) {
        if (closeable != null) {
            try {
                closeable.close();
            } catch (final Exception e) {
                if (consumer != null) {
                    consumer.accept(e);
                }
            }
        }
    }

    /**
     * Closes an {@link InputStream} unconditionally.
     * <p>
     * Equivalent to {@link InputStream#close()}, except any exceptions will be ignored. This is typically used in finally blocks.
     * </p>
     * <p>
     * Example code:
     * </p>
     *
     * <pre>
     * byte[] data = new byte[1024];
     * InputStream in = null;
     * try {
     *     in = new FileInputStream("foo.txt");
     *     in.read(data);
     *     in.close(); // close errors are handled
     * } catch (Exception e) {
     *     // error handling
     * } finally {
     *     IOUtils.closeQuietly(in);
     * }
     * </pre>
     * <p>
     * Also consider using a try-with-resources statement where appropriate.
     * </p>
     *
     * @param input the InputStream to close, may be null or already closed.
     * @see Throwable#addSuppressed(Throwable)
     */
    public static void closeQuietly(final InputStream input) {
        closeQ(input);
    }

    /**
     * Closes an iterable of {@link Closeable} unconditionally.
     * <p>
     * Equivalent calling {@link Closeable#close()} on each element, except any exceptions will be ignored.
     * </p>
     *
     * @param closeables the objects to close, may be null or already closed.
     * @see #closeQuietly(Closeable)
     * @since 2.12.0
     */
    public static void closeQuietly(final Iterable<Closeable> closeables) {
        if (closeables != null) {
            closeables.forEach(IOUtils::closeQuietly);
        }
    }

    /**
     * Closes an {@link OutputStream} unconditionally.
     * <p>
     * Equivalent to {@link OutputStream#close()}, except any exceptions will be ignored. This is typically used in finally blocks.
     * </p>
     * <p>
     * Example code:
     * </p>
     *
     * <pre>
     * byte[] data = "Hello, World".getBytes();
     * OutputStream out = null;
     * try {
     *     out = new FileOutputStream("foo.txt");
     *     out.write(data);
     *     out.close(); // close errors are handled
     * } catch (IOException e) {
     *     // error handling
     * } finally {
     *     IOUtils.closeQuietly(out);
     * }
     * </pre>
     * <p>
     * Also consider using a try-with-resources statement where appropriate.
     * </p>
     *
     * @param output the OutputStream to close, may be null or already closed.
     * @see Throwable#addSuppressed(Throwable)
     */
    public static void closeQuietly(final OutputStream output) {
        closeQ(output);
    }

    /**
     * Closes an {@link Reader} unconditionally.
     * <p>
     * Equivalent to {@link Reader#close()}, except any exceptions will be ignored. This is typically used in finally blocks.
     * </p>
     * <p>
     * Example code:
     * </p>
     *
     * <pre>
     * char[] data = new char[1024];
     * Reader in = null;
     * try {
     *     in = new FileReader("foo.txt");
     *     in.read(data);
     *     in.close(); // close errors are handled
     * } catch (Exception e) {
     *     // error handling
     * } finally {
     *     IOUtils.closeQuietly(in);
     * }
     * </pre>
     * <p>
     * Also consider using a try-with-resources statement where appropriate.
     * </p>
     *
     * @param reader the Reader to close, may be null or already closed.
     * @see Throwable#addSuppressed(Throwable)
     */
    public static void closeQuietly(final Reader reader) {
        closeQ(reader);
    }

    /**
     * Closes a {@link Selector} unconditionally.
     * <p>
     * Equivalent to {@link Selector#close()}, except any exceptions will be ignored. This is typically used in finally blocks.
     * </p>
     * <p>
     * Example code:
     * </p>
     *
     * <pre>
     * Selector selector = null;
     * try {
     *     selector = Selector.open();
     *     // process socket
     * } catch (Exception e) {
     *     // error handling
     * } finally {
     *     IOUtils.closeQuietly(selector);
     * }
     * </pre>
     * <p>
     * Also consider using a try-with-resources statement where appropriate.
     * </p>
     *
     * @param selector the Selector to close, may be null or already closed.
     * @since 2.2
     * @see Throwable#addSuppressed(Throwable)
     */
    public static void closeQuietly(final Selector selector) {
        closeQ(selector);
    }

    /**
     * Closes a {@link ServerSocket} unconditionally.
     * <p>
     * Equivalent to {@link ServerSocket#close()}, except any exceptions will be ignored. This is typically used in finally blocks.
     * </p>
     * <p>
     * Example code:
     * </p>
     *
     * <pre>
     * ServerSocket socket = null;
     * try {
     *     socket = new ServerSocket();
     *     // process socket
     *     socket.close();
     * } catch (Exception e) {
     *     // error handling
     * } finally {
     *     IOUtils.closeQuietly(socket);
     * }
     * </pre>
     * <p>
     * Also consider using a try-with-resources statement where appropriate.
     * </p>
     *
     * @param serverSocket the ServerSocket to close, may be null or already closed.
     * @since 2.2
     * @see Throwable#addSuppressed(Throwable)
     */
    public static void closeQuietly(final ServerSocket serverSocket) {
        closeQ(serverSocket);
    }

    /**
     * Closes a {@link Socket} unconditionally.
     * <p>
     * Equivalent to {@link Socket#close()}, except any exceptions will be ignored. This is typically used in finally blocks.
     * </p>
     * <p>
     * Example code:
     * </p>
     *
     * <pre>
     * Socket socket = null;
     * try {
     *     socket = new Socket("http://www.foo.com/", 80);
     *     // process socket
     *     socket.close();
     * } catch (Exception e) {
     *     // error handling
     * } finally {
     *     IOUtils.closeQuietly(socket);
     * }
     * </pre>
     * <p>
     * Also consider using a try-with-resources statement where appropriate.
     * </p>
     *
     * @param socket the Socket to close, may be null or already closed.
     * @since 2.0
     * @see Throwable#addSuppressed(Throwable)
     */
    public static void closeQuietly(final Socket socket) {
        closeQ(socket);
    }

    /**
     * Closes a stream of {@link Closeable} unconditionally.
     * <p>
     * Equivalent calling {@link Closeable#close()} on each element, except any exceptions will be ignored.
     * </p>
     *
     * @param closeables the objects to close, may be null or already closed.
     * @see #closeQuietly(Closeable)
     * @since 2.12.0
     */
    public static void closeQuietly(final Stream<Closeable> closeables) {
        if (closeables != null) {
            closeables.forEach(IOUtils::closeQuietly);
        }
    }

    /**
     * Closes an {@link Writer} unconditionally.
     * <p>
     * Equivalent to {@link Writer#close()}, except any exceptions will be ignored. This is typically used in finally blocks.
     * </p>
     * <p>
     * Example code:
     * </p>
     *
     * <pre>
     * Writer out = null;
     * try {
     *     out = new StringWriter();
     *     out.write("Hello World");
     *     out.close(); // close errors are handled
     * } catch (Exception e) {
     *     // error handling
     * } finally {
     *     IOUtils.closeQuietly(out);
     * }
     * </pre>
     * <p>
     * Also consider using a try-with-resources statement where appropriate.
     * </p>
     *
     * @param writer the Writer to close, may be null or already closed.
     * @see Throwable#addSuppressed(Throwable)
     */
    public static void closeQuietly(final Writer writer) {
        closeQ(writer);
    }

    /**
     * Closes a {@link Closeable} unconditionally and adds any exception thrown by the {@code close()} to the given Throwable.
     * <p>
     * For example:
     * </p>
     *
     * <pre>
     * Closeable closeable = ...;
     * try {
     *     // process closeable.
     * } catch (Exception e) {
     *     // Handle exception.
     *     throw IOUtils.closeQuietlySuppress(closeable, e);
     * }
     * </pre>
     * <p>
     * Also consider using a try-with-resources statement where appropriate.
     * </p>
     *
     * @param <T>       The Throwable type.
     * @param closeable The object to close, may be null or already closed.
     * @param throwable Add the exception throw by the closeable to the given Throwable.
     * @return The given Throwable.
     * @since 2.22.0
     * @see Throwable#addSuppressed(Throwable)
     */
    public static <T extends Throwable> T closeQuietlySuppress(final Closeable closeable, final T throwable) {
        closeQuietly(closeable, throwable::addSuppressed);
        return throwable;
    }

    /**
     * Consumes bytes from a {@link InputStream} and ignores them.
     * <p>
     * The buffer size is given by {@link #DEFAULT_BUFFER_SIZE}.
     * </p>
     *
     * @param input the {@link InputStream} to read.
     * @return the number of bytes copied. or {@code 0} if {@code input is null}.
     * @throws NullPointerException if the InputStream is {@code null}.
     * @throws IOException          if an I/O error occurs.
     * @since 2.8.0
     */
    public static long consume(final InputStream input) throws IOException {
        return copyLarge(input, NullOutputStream.INSTANCE);
    }

    /**
     * Consumes characters from a {@link Reader} and ignores them.
     * <p>
     * The buffer size is given by {@link #DEFAULT_BUFFER_SIZE}.
     * </p>
     *
     * @param input the {@link Reader} to read.
     * @return the number of bytes copied. or {@code 0} if {@code input is null}.
     * @throws NullPointerException if the Reader is {@code null}.
     * @throws IOException          if an I/O error occurs.
     * @since 2.12.0
     */
    public static long consume(final Reader input) throws IOException {
        return copyLarge(input, NullWriter.INSTANCE);
    }

    /**
     * Compares the contents of two Streams to determine if they are equal or not.
     * <p>
     * This method buffers the input internally using {@link BufferedInputStream} if they are not already buffered.
     * </p>
     *
     * @param input1 the first stream.
     * @param input2 the second stream.
     * @return true if the content of the streams are equal or they both don't. exist, false otherwise.
     * @throws IOException if an I/O error occurs.
     */
    @SuppressWarnings("resource") // Caller closes input streams
    public static boolean contentEquals(final InputStream input1, final InputStream input2) throws IOException {
        // Before making any changes, please test with org.apache.commons.io.jmh.IOUtilsContentEqualsInputStreamsBenchmark
        if (input1 == input2) {
            return true;
        }
        if (input1 == null || input2 == null) {
            return false;
        }
        // We do not close FileChannels because that closes the owning InputStream.
        return FileChannels.contentEquals(Channels.newChannel(input1), Channels.newChannel(input2), DEFAULT_BUFFER_SIZE);
    }

    // TODO Consider making public
    private static boolean contentEquals(final Iterator<?> iterator1, final Iterator<?> iterator2) {
        while (iterator1.hasNext()) {
            if (!iterator2.hasNext() || !Objects.equals(iterator1.next(), iterator2.next())) {
                return false;
            }
        }
        return !iterator2.hasNext();
    }

    /**
     * Compares the contents of two Readers to determine if they are equal or not.
     * <p>
     * This method buffers the input internally using {@link BufferedReader} if they are not already buffered.
     * </p>
     *
     * @param input1 the first reader.
     * @param input2 the second reader.
     * @return true if the content of the readers are equal or they both don't exist, false otherwise.
     * @throws NullPointerException if either input is null.
     * @throws IOException          if an I/O error occurs.
     * @since 1.1
     */
    public static boolean contentEquals(final Reader input1, final Reader input2) throws IOException {
        if (input1 == input2) {
            return true;
        }
        if (input1 == null || input2 == null) {
            return false;
        }
        try (ScratchChars scratch = IOUtils.ScratchChars.get()) {
            final char[] array1 = scratch.array();
            final char[] array2 = charArray();
            int pos1;
            int pos2;
            int count1;
            int count2;
            while (true) {
                pos1 = 0;
                pos2 = 0;
                for (int index = 0; index < DEFAULT_BUFFER_SIZE; index++) {
                    if (pos1 == index) {
                        do {
                            count1 = input1.read(array1, pos1, DEFAULT_BUFFER_SIZE - pos1);
                        } while (count1 == 0);
                        if (count1 == EOF) {
                            return pos2 == index && input2.read() == EOF;
                        }
                        pos1 += count1;
                    }
                    if (pos2 == index) {
                        do {
                            count2 = input2.read(array2, pos2, DEFAULT_BUFFER_SIZE - pos2);
                        } while (count2 == 0);
                        if (count2 == EOF) {
                            return pos1 == index && input1.read() == EOF;
                        }
                        pos2 += count2;
                    }
                    if (array1[index] != array2[index]) {
                        return false;
                    }
                }
            }
        }
    }

    // TODO Consider making public
    private static boolean contentEquals(final Stream<?> stream1, final Stream<?> stream2) {
        if (stream1 == stream2) {
            return true;
        }
        if (stream1 == null || stream2 == null) {
            return false;
        }
        return contentEquals(stream1.iterator(), stream2.iterator());
    }

    // TODO Consider making public
    private static boolean contentEqualsIgnoreEOL(final BufferedReader reader1, final BufferedReader reader2) {
        if (reader1 == reader2) {
            return true;
        }
        if (reader1 == null || reader2 == null) {
            return false;
        }
        return contentEquals(reader1.lines(), reader2.lines());
    }

    /**
     * Compares the contents of two Readers to determine if they are equal or not, ignoring EOL characters.
     * <p>
     * This method buffers the input internally using {@link BufferedReader} if they are not already buffered.
     * </p>
     *
     * @param reader1 the first reader.
     * @param reader2 the second reader.
     * @return true if the content of the readers are equal (ignoring EOL differences), false otherwise.
     * @throws NullPointerException if either input is null.
     * @throws UncheckedIOException if an I/O error occurs.
     * @since 2.2
     */
    @SuppressWarnings("resource")
    public static boolean contentEqualsIgnoreEOL(final Reader reader1, final Reader reader2) throws UncheckedIOException {
        if (reader1 == reader2) {
            return true;
        }
        if (reader1 == null || reader2 == null) {
            return false;
        }
        return contentEqualsIgnoreEOL(toBufferedReader(reader1), toBufferedReader(reader2));
    }

    /**
     * Copies bytes from an {@link InputStream} to an {@link OutputStream}.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     * <p>
     * Large streams (over 2GB) will return a bytes copied value of {@code -1} after the copy has completed since the correct number of bytes cannot be returned
     * as an int. For large streams use the {@link #copyLarge(InputStream, OutputStream)} method.
     * </p>
     *
     * @param inputStream  the {@link InputStream} to read.
     * @param outputStream the {@link OutputStream} to write.
     * @return the number of bytes copied, or -1 if greater than {@link Integer#MAX_VALUE}.
     * @throws NullPointerException if the InputStream is {@code null}.
     * @throws NullPointerException if the OutputStream is {@code null}.
     * @throws IOException          if an I/O error occurs.
     * @since 1.1
     */
    public static int copy(final InputStream inputStream, final OutputStream outputStream) throws IOException {
        final long count = copyLarge(inputStream, outputStream);
        return count > Integer.MAX_VALUE ? EOF : (int) count;
    }

    /**
     * Copies bytes from an {@link InputStream} to an {@link OutputStream} using an internal buffer of the given size.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     *
     * @param inputStream  the {@link InputStream} to read.
     * @param outputStream the {@link OutputStream} to write to.
     * @param bufferSize   the bufferSize used to copy from the input to the output.
     * @return the number of bytes copied.
     * @throws NullPointerException if the InputStream is {@code null}.
     * @throws NullPointerException if the OutputStream is {@code null}.
     * @throws IOException          if an I/O error occurs.
     * @since 2.5
     */
    public static long copy(final InputStream inputStream, final OutputStream outputStream, final int bufferSize) throws IOException {
        return copyLarge(inputStream, outputStream, byteArray(bufferSize));
    }

    /**
     * Copies bytes from an {@link InputStream} to chars on a {@link Writer} using the virtual machine's {@linkplain Charset#defaultCharset() default charset}.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     * <p>
     * This method uses {@link InputStreamReader}.
     * </p>
     *
     * @param input  the {@link InputStream} to read.
     * @param writer the {@link Writer} to write to.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 1.1
     * @deprecated Use {@link #copy(InputStream, Writer, Charset)} instead.
     */
    @Deprecated
    public static void copy(final InputStream input, final Writer writer) throws IOException {
        copy(input, writer, Charset.defaultCharset());
    }

    /**
     * Copies bytes from an {@link InputStream} to chars on a {@link Writer} using the specified character encoding.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     * <p>
     * This method uses {@link InputStreamReader}.
     * </p>
     *
     * @param input        the {@link InputStream} to read.
     * @param writer       the {@link Writer} to write to.
     * @param inputCharset the charset to use for the input stream, null means platform default.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 2.3
     */
    public static void copy(final InputStream input, final Writer writer, final Charset inputCharset) throws IOException {
        copy(new InputStreamReader(input, Charsets.toCharset(inputCharset)), writer);
    }

    /**
     * Copies bytes from an {@link InputStream} to chars on a {@link Writer} using the specified character encoding.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     * <p>
     * Character encoding names can be found at <a href="https://www.iana.org/assignments/character-sets">IANA</a>.
     * </p>
     * <p>
     * This method uses {@link InputStreamReader}.
     * </p>
     *
     * @param input            the {@link InputStream} to read.
     * @param writer           the {@link Writer} to write to.
     * @param inputCharsetName the name of the requested charset for the InputStream, null means platform default.
     * @throws NullPointerException                         if the input or output is null.
     * @throws IOException                                  if an I/O error occurs.
     * @throws java.nio.charset.UnsupportedCharsetException if the encoding is not supported.
     * @since 1.1
     */
    public static void copy(final InputStream input, final Writer writer, final String inputCharsetName) throws IOException {
        copy(input, writer, Charsets.toCharset(inputCharsetName));
    }

    /**
     * Copies bytes from a {@link ByteArrayOutputStream} to a {@link QueueInputStream}.
     * <p>
     * Unlike using JDK {@link PipedInputStream} and {@link PipedOutputStream} for this, this solution works safely in a single thread environment.
     * </p>
     * <p>
     * Example usage:
     * </p>
     *
     * <pre>
     * ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
     * outputStream.writeBytes("hello world".getBytes(StandardCharsets.UTF_8));
     * InputStream inputStream = IOUtils.copy(outputStream);
     * </pre>
     *
     * @param outputStream the {@link ByteArrayOutputStream} to read.
     * @return the {@link QueueInputStream} filled with the content of the outputStream.
     * @throws NullPointerException if the {@link ByteArrayOutputStream} is {@code null}.
     * @throws IOException          if an I/O error occurs.
     * @since 2.12
     */
    @SuppressWarnings("resource") // streams are closed by the caller.
    public static QueueInputStream copy(final java.io.ByteArrayOutputStream outputStream) throws IOException {
        Objects.requireNonNull(outputStream, "outputStream");
        final QueueInputStream in = new QueueInputStream();
        outputStream.writeTo(in.newQueueOutputStream());
        return in;
    }

    /**
     * Copies chars from a {@link Reader} to a {@link Appendable}.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedReader}.
     * </p>
     * <p>
     * Large streams (over 2GB) will return a chars copied value of {@code -1} after the copy has completed since the correct number of chars cannot be returned
     * as an int. For large streams use the {@link #copyLarge(Reader, Writer)} method.
     * </p>
     *
     * @param reader the {@link Reader} to read.
     * @param output the {@link Appendable} to write to.
     * @return the number of characters copied, or -1 if &gt; Integer.MAX_VALUE.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 2.7
     */
    public static long copy(final Reader reader, final Appendable output) throws IOException {
        return copy(reader, output, CharBuffer.allocate(DEFAULT_BUFFER_SIZE));
    }

    /**
     * Copies chars from a {@link Reader} to an {@link Appendable}.
     * <p>
     * This method uses the provided buffer, so there is no need to use a {@link BufferedReader}.
     * </p>
     *
     * @param reader the {@link Reader} to read.
     * @param output the {@link Appendable} to write to.
     * @param buffer the buffer to be used for the copy.
     * @return the number of characters copied.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 2.7
     */
    public static long copy(final Reader reader, final Appendable output, final CharBuffer buffer) throws IOException {
        long count = 0;
        int n;
        while (EOF != (n = reader.read(buffer))) {
            buffer.flip();
            output.append(buffer, 0, n);
            count += n;
        }
        return count;
    }

    /**
     * Copies chars from a {@link Reader} to bytes on an {@link OutputStream} using the virtual machine's {@linkplain Charset#defaultCharset() default charset},
     * and calling flush.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedReader}.
     * </p>
     * <p>
     * Due to the implementation of OutputStreamWriter, this method performs a flush.
     * </p>
     * <p>
     * This method uses {@link OutputStreamWriter}.
     * </p>
     *
     * @param reader the {@link Reader} to read.
     * @param output the {@link OutputStream} to write to.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 1.1
     * @deprecated Use {@link #copy(Reader, OutputStream, Charset)} instead.
     */
    @Deprecated
    public static void copy(final Reader reader, final OutputStream output) throws IOException {
        copy(reader, output, Charset.defaultCharset());
    }

    /**
     * Copies chars from a {@link Reader} to bytes on an {@link OutputStream} using the specified character encoding, and calling flush.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedReader}.
     * </p>
     * <p>
     * Due to the implementation of OutputStreamWriter, this method performs a flush.
     * </p>
     * <p>
     * This method uses {@link OutputStreamWriter}.
     * </p>
     *
     * @param reader        the {@link Reader} to read.
     * @param output        the {@link OutputStream} to write to.
     * @param outputCharset the charset to use for the OutputStream, null means platform default.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 2.3
     */
    public static void copy(final Reader reader, final OutputStream output, final Charset outputCharset) throws IOException {
        final OutputStreamWriter writer = new OutputStreamWriter(output, Charsets.toCharset(outputCharset));
        copy(reader, writer);
        // XXX Unless anyone is planning on rewriting OutputStreamWriter,
        // we have to flush here.
        writer.flush();
    }

    /**
     * Copies chars from a {@link Reader} to bytes on an {@link OutputStream} using the specified character encoding, and calling flush.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedReader}.
     * </p>
     * <p>
     * Character encoding names can be found at <a href="https://www.iana.org/assignments/character-sets">IANA</a>.
     * </p>
     * <p>
     * Due to the implementation of OutputStreamWriter, this method performs a flush.
     * </p>
     * <p>
     * This method uses {@link OutputStreamWriter}.
     * </p>
     *
     * @param reader            the {@link Reader} to read.
     * @param output            the {@link OutputStream} to write to.
     * @param outputCharsetName the name of the requested charset for the OutputStream, null means platform default.
     * @throws NullPointerException                         if the input or output is null.
     * @throws IOException                                  if an I/O error occurs.
     * @throws java.nio.charset.UnsupportedCharsetException if the encoding is not supported.
     * @since 1.1
     */
    public static void copy(final Reader reader, final OutputStream output, final String outputCharsetName) throws IOException {
        copy(reader, output, Charsets.toCharset(outputCharsetName));
    }

    /**
     * Copies chars from a {@link Reader} to a {@link Writer}.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedReader}.
     * </p>
     * <p>
     * Large streams (over 2GB) will return a chars copied value of {@code -1} after the copy has completed since the correct number of chars cannot be returned
     * as an int. For large streams use the {@link #copyLarge(Reader, Writer)} method.
     * </p>
     *
     * @param reader the {@link Reader} to read.
     * @param writer the {@link Writer} to write.
     * @return the number of characters copied, or -1 if &gt; Integer.MAX_VALUE.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 1.1
     */
    public static int copy(final Reader reader, final Writer writer) throws IOException {
        final long count = copyLarge(reader, writer);
        if (count > Integer.MAX_VALUE) {
            return EOF;
        }
        return (int) count;
    }

    /**
     * Copies bytes from a {@link URL} to an {@link OutputStream}.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     * <p>
     * The buffer size is given by {@link #DEFAULT_BUFFER_SIZE}.
     * </p>
     *
     * @param url  the {@link URL} to read.
     * @param file the {@link OutputStream} to write.
     * @return the number of bytes copied.
     * @throws NullPointerException if the URL is {@code null}.
     * @throws NullPointerException if the OutputStream is {@code null}.
     * @throws IOException          if an I/O error occurs.
     * @since 2.9.0
     */
    public static long copy(final URL url, final File file) throws IOException {
        try (OutputStream outputStream = Files.newOutputStream(Objects.requireNonNull(file, "file").toPath())) {
            return copy(url, outputStream);
        }
    }

    /**
     * Copies bytes from a {@link URL} to an {@link OutputStream}.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     * <p>
     * The buffer size is given by {@link #DEFAULT_BUFFER_SIZE}.
     * </p>
     *
     * @param url          the {@link URL} to read.
     * @param outputStream the {@link OutputStream} to write.
     * @return the number of bytes copied.
     * @throws NullPointerException if the URL is {@code null}.
     * @throws NullPointerException if the OutputStream is {@code null}.
     * @throws IOException          if an I/O error occurs.
     * @since 2.9.0
     */
    public static long copy(final URL url, final OutputStream outputStream) throws IOException {
        try (InputStream inputStream = Objects.requireNonNull(url, "url").openStream()) {
            return copyLarge(inputStream, outputStream);
        }
    }

    /**
     * Copies bytes from a large (over 2GB) {@link InputStream} to an {@link OutputStream}.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     * <p>
     * The buffer size is given by {@link #DEFAULT_BUFFER_SIZE}.
     * </p>
     *
     * @param inputStream  the {@link InputStream} to read.
     * @param outputStream the {@link OutputStream} to write.
     * @return the number of bytes copied.
     * @throws NullPointerException if the InputStream is {@code null}.
     * @throws NullPointerException if the OutputStream is {@code null}.
     * @throws IOException          if an I/O error occurs.
     * @since 1.3
     */
    public static long copyLarge(final InputStream inputStream, final OutputStream outputStream) throws IOException {
        return copy(inputStream, outputStream, DEFAULT_BUFFER_SIZE);
    }

    /**
     * Copies bytes from a large (over 2GB) {@link InputStream} to an {@link OutputStream}.
     * <p>
     * This method uses the provided buffer, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     *
     * @param inputStream  the {@link InputStream} to read.
     * @param outputStream the {@link OutputStream} to write.
     * @param buffer       the buffer to use for the copy.
     * @return the number of bytes copied.
     * @throws NullPointerException if the InputStream is {@code null}.
     * @throws NullPointerException if the OutputStream is {@code null}.
     * @throws IOException          if an I/O error occurs.
     * @since 2.2
     */
    @SuppressWarnings("resource") // streams are closed by the caller.
    public static long copyLarge(final InputStream inputStream, final OutputStream outputStream, final byte[] buffer) throws IOException {
        Objects.requireNonNull(inputStream, "inputStream");
        Objects.requireNonNull(outputStream, "outputStream");
        long count = 0;
        int n;
        while (EOF != (n = inputStream.read(buffer))) {
            outputStream.write(buffer, 0, n);
            count += n;
        }
        return count;
    }

    /**
     * Copies some or all bytes from a large (over 2GB) {@link InputStream} to an {@link OutputStream}, optionally skipping input bytes.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     * <p>
     * Note that the implementation uses {@link #skip(InputStream, long)}. This means that the method may be considerably less efficient than using the actual
     * skip implementation, this is done to guarantee that the correct number of characters are skipped.
     * </p>
     * The buffer size is given by {@link #DEFAULT_BUFFER_SIZE}.
     *
     * @param input       the {@link InputStream} to read.
     * @param output      the {@link OutputStream} to write.
     * @param inputOffset number of bytes to skip from input before copying, these bytes are ignored.
     * @param length      number of bytes to copy.
     * @return the number of bytes copied.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 2.2
     */
    public static long copyLarge(final InputStream input, final OutputStream output, final long inputOffset, final long length) throws IOException {
        try (ScratchBytes scratch = ScratchBytes.get()) {
            return copyLarge(input, output, inputOffset, length, scratch.array());
        }
    }

    /**
     * Copies some or all bytes from a large (over 2GB) {@link InputStream} to an {@link OutputStream}, optionally skipping input bytes.
     * <p>
     * This method uses the provided buffer, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     * <p>
     * Note that the implementation uses {@link #skip(InputStream, long)}. This means that the method may be considerably less efficient than using the actual
     * skip implementation, this is done to guarantee that the correct number of characters are skipped.
     * </p>
     *
     * @param input       the {@link InputStream} to read.
     * @param output      the {@link OutputStream} to write.
     * @param inputOffset number of bytes to skip from input before copying, these bytes are ignored.
     * @param length      number of bytes to copy.
     * @param buffer      the buffer to use for the copy.
     * @return the number of bytes copied.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 2.2
     */
    public static long copyLarge(final InputStream input, final OutputStream output, final long inputOffset, final long length, final byte[] buffer)
            throws IOException {
        if (inputOffset > 0) {
            skipFully(input, inputOffset);
        }
        if (length == 0) {
            return 0;
        }
        final int bufferLength = buffer.length;
        int bytesToRead = bufferLength;
        if (length > 0 && length < bufferLength) {
            bytesToRead = (int) length;
        }
        int read;
        long totalRead = 0;
        while (bytesToRead > 0 && EOF != (read = input.read(buffer, 0, bytesToRead))) {
            output.write(buffer, 0, read);
            totalRead += read;
            if (length > 0) { // only adjust length if not reading to the end
                // Note the cast must work because bufferLength = buffer.length is an integer
                bytesToRead = (int) Math.min(length - totalRead, bufferLength);
            }
        }
        return totalRead;
    }

    /**
     * Copies chars from a large (over 2GB) {@link Reader} to a {@link Writer}.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedReader}.
     * </p>
     * <p>
     * The buffer size is given by {@link #DEFAULT_BUFFER_SIZE}.
     * </p>
     *
     * @param reader the {@link Reader} to source.
     * @param writer the {@link Writer} to target.
     * @return the number of characters copied.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 1.3
     */
    public static long copyLarge(final Reader reader, final Writer writer) throws IOException {
        try (ScratchChars scratch = IOUtils.ScratchChars.get()) {
            return copyLarge(reader, writer, scratch.array());
        }
    }

    /**
     * Copies chars from a large (over 2GB) {@link Reader} to a {@link Writer}.
     * <p>
     * This method uses the provided buffer, so there is no need to use a {@link BufferedReader}.
     * </p>
     *
     * @param reader the {@link Reader} to source.
     * @param writer the {@link Writer} to target.
     * @param buffer the buffer to be used for the copy.
     * @return the number of characters copied.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 2.2
     */
    public static long copyLarge(final Reader reader, final Writer writer, final char[] buffer) throws IOException {
        long count = 0;
        int n;
        while (EOF != (n = reader.read(buffer))) {
            writer.write(buffer, 0, n);
            count += n;
        }
        return count;
    }

    /**
     * Copies some or all chars from a large (over 2GB) {@link InputStream} to an {@link OutputStream}, optionally skipping input chars.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedReader}.
     * </p>
     * <p>
     * The buffer size is given by {@link #DEFAULT_BUFFER_SIZE}.
     * </p>
     *
     * @param reader      the {@link Reader} to read.
     * @param writer      the {@link Writer} to write to.
     * @param inputOffset number of chars to skip from input before copying -ve values are ignored.
     * @param length      number of chars to copy. -ve means all.
     * @return the number of chars copied.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 2.2
     */
    public static long copyLarge(final Reader reader, final Writer writer, final long inputOffset, final long length) throws IOException {
        try (ScratchChars scratch = IOUtils.ScratchChars.get()) {
            return copyLarge(reader, writer, inputOffset, length, scratch.array());
        }
    }

    /**
     * Copies some or all chars from a large (over 2GB) {@link InputStream} to an {@link OutputStream}, optionally skipping input chars.
     * <p>
     * This method uses the provided buffer, so there is no need to use a {@link BufferedReader}.
     * </p>
     *
     * @param reader      the {@link Reader} to read.
     * @param writer      the {@link Writer} to write to.
     * @param inputOffset number of chars to skip from input before copying -ve values are ignored.
     * @param length      number of chars to copy. -ve means all.
     * @param buffer      the buffer to be used for the copy.
     * @return the number of chars copied.
     * @throws NullPointerException if the input or output is null.
     * @throws IOException          if an I/O error occurs.
     * @since 2.2
     */
    public static long copyLarge(final Reader reader, final Writer writer, final long inputOffset, final long length, final char[] buffer) throws IOException {
        if (inputOffset > 0) {
            skipFully(reader, inputOffset);
        }
        if (length == 0) {
            return 0;
        }
        int bytesToRead = buffer.length;
        if (length > 0 && length < buffer.length) {
            bytesToRead = (int) length;
        }
        int read;
        long totalRead = 0;
        while (bytesToRead > 0 && EOF != (read = reader.read(buffer, 0, bytesToRead))) {
            writer.write(buffer, 0, read);
            totalRead += read;
            if (length > 0) { // only adjust length if not reading to the end
                // Note the cast must work because buffer.length is an integer
                bytesToRead = (int) Math.min(length - totalRead, buffer.length);
            }
        }
        return totalRead;
    }

    /**
     * Copies up to {@code size} bytes from the given {@link InputStream} into a new {@link UnsynchronizedByteArrayOutputStream}.
     *
     * @param input      The {@link InputStream} to read; must not be {@code null}.
     * @param limit      The maximum number of bytes to read; must be {@code >= 0}. The actual bytes read are validated to equal {@code size}.
     * @param bufferSize The buffer size of the output stream; must be {@code > 0}.
     * @return a ByteArrayOutputStream containing the read bytes.
     */
    static UnsynchronizedByteArrayOutputStream copyToOutputStream(final InputStream input, final long limit, final int bufferSize) throws IOException {
        try (UnsynchronizedByteArrayOutputStream output = UnsynchronizedByteArrayOutputStream.builder().setBufferSize(bufferSize).get();
                InputStream boundedInput = BoundedInputStream.builder().setMaxCount(limit).setPropagateClose(false).setInputStream(input).get()) {
            output.write(boundedInput);
            return output;
        }
    }

    /**
     * Returns the length of the given array in a null-safe manner.
     *
     * @param array an array or null.
     * @return the array length, or 0 if the given array is null.
     * @since 2.7
     */
    public static int length(final byte[] array) {
        return array == null ? 0 : array.length;
    }

    /**
     * Returns the length of the given array in a null-safe manner.
     *
     * @param array an array or null.
     * @return the array length, or 0 if the given array is null.
     * @since 2.7
     */
    public static int length(final char[] array) {
        return array == null ? 0 : array.length;
    }

    /**
     * Returns the length of the given CharSequence in a null-safe manner.
     *
     * @param csq a CharSequence or null.
     * @return the CharSequence length, or 0 if the given CharSequence is null.
     * @since 2.7
     */
    public static int length(final CharSequence csq) {
        return csq == null ? 0 : csq.length();
    }

    /**
     * Returns the length of the given array in a null-safe manner.
     *
     * @param array an array or null.
     * @return the array length, or 0 if the given array is null.
     * @since 2.7
     */
    public static int length(final Object[] array) {
        return array == null ? 0 : array.length;
    }

    /**
     * Returns an Iterator for the lines in an {@link InputStream}, using the character encoding specified (or default encoding if null).
     * <p>
     * {@link LineIterator} holds a reference to the open {@link InputStream} specified here. When you have finished with the iterator you should close the
     * stream to free internal resources. This can be done by using a try-with-resources block, closing the stream directly, or by calling
     * {@link LineIterator#close()}.
     * </p>
     * <p>
     * The recommended usage pattern is:
     * </p>
     *
     * <pre>
     * try {
     *     LineIterator it = IOUtils.lineIterator(stream, charset);
     *     while (it.hasNext()) {
     *         String line = it.nextLine();
     *         /// do something with line
     *     }
     * } finally {
     *     IOUtils.closeQuietly(stream);
     * }
     * </pre>
     *
     * @param input   the {@link InputStream} to read, not null.
     * @param charset the charset to use, null means platform default.
     * @return an Iterator of the lines in the reader, never null.
     * @throws IllegalArgumentException if the input is null.
     * @since 2.3
     */
    public static LineIterator lineIterator(final InputStream input, final Charset charset) {
        return new LineIterator(new InputStreamReader(input, Charsets.toCharset(charset)));
    }

    /**
     * Returns an Iterator for the lines in an {@link InputStream}, using the character encoding specified (or default encoding if null).
     * <p>
     * {@link LineIterator} holds a reference to the open {@link InputStream} specified here. When you have finished with the iterator you should close the
     * stream to free internal resources. This can be done by using a try-with-resources block, closing the stream directly, or by calling
     * {@link LineIterator#close()}.
     * </p>
     * <p>
     * The recommended usage pattern is:
     * </p>
     *
     * <pre>
     * try {
     *     LineIterator it = IOUtils.lineIterator(stream, StandardCharsets.UTF_8.name());
     *     while (it.hasNext()) {
     *         String line = it.nextLine();
     *         /// do something with line
     *     }
     * } finally {
     *     IOUtils.closeQuietly(stream);
     * }
     * </pre>
     *
     * @param input       the {@link InputStream} to read, not null.
     * @param charsetName the encoding to use, null means platform default.
     * @return an Iterator of the lines in the reader, never null.
     * @throws IllegalArgumentException                     if the input is null.
     * @throws java.nio.charset.UnsupportedCharsetException if the encoding is not supported.
     * @since 1.2
     */
    public static LineIterator lineIterator(final InputStream input, final String charsetName) {
        return lineIterator(input, Charsets.toCharset(charsetName));
    }

    /**
     * Returns an Iterator for the lines in a {@link Reader}.
     * <p>
     * {@link LineIterator} holds a reference to the open {@link Reader} specified here. When you have finished with the iterator you should close the reader to
     * free internal resources. This can be done by using a try-with-resources block, closing the reader directly, or by calling {@link LineIterator#close()}.
     * </p>
     * <p>
     * The recommended usage pattern is:
     * </p>
     *
     * <pre>
     * try {
     *     LineIterator it = IOUtils.lineIterator(reader);
     *     while (it.hasNext()) {
     *         String line = it.nextLine();
     *         /// do something with line
     *     }
     * } finally {
     *     IOUtils.closeQuietly(reader);
     * }
     * </pre>
     *
     * @param reader the {@link Reader} to read, not null.
     * @return an Iterator of the lines in the reader, never null.
     * @throws NullPointerException if the reader is null.
     * @since 1.2
     */
    public static LineIterator lineIterator(final Reader reader) {
        return new LineIterator(reader);
    }

    /**
     * Reads bytes from an input stream.
     * <p>
     * This implementation guarantees that it will read as many bytes as possible before giving up; this may not always be the case for subclasses of
     * {@link InputStream}.
     * </p>
     *
     * @param input  where to read input from.
     * @param buffer destination.
     * @return actual length read; may be less than requested if EOF was reached.
     * @throws NullPointerException if {@code input} or {@code buffer} is null.
     * @throws IOException          if a read error occurs.
     * @since 2.2
     */
    public static int read(final InputStream input, final byte[] buffer) throws IOException {
        return read(input, buffer, 0, buffer.length);
    }

    /**
     * Reads bytes from an input stream.
     * <p>
     * This implementation guarantees that it will read as many bytes as possible before giving up; this may not always be the case for subclasses of
     * {@link InputStream}.
     * </p>
     *
     * @param input  where to read input.
     * @param buffer destination.
     * @param offset initial offset into buffer.
     * @param length length to read, must be &gt;= 0.
     * @return actual length read; may be less than requested if EOF was reached.
     * @throws NullPointerException      if {@code input} or {@code buffer} is null.
     * @throws IndexOutOfBoundsException if {@code offset} or {@code length} is negative, or if {@code offset + length} is greater than {@code buffer.length}.
     * @throws IOException               if a read error occurs.
     * @since 2.2
     */
    public static int read(final InputStream input, final byte[] buffer, final int offset, final int length) throws IOException {
        checkFromIndexSize(buffer, offset, length);
        int remaining = length;
        while (remaining > 0) {
            final int location = length - remaining;
            final int count = input.read(buffer, offset + location, remaining);
            if (EOF == count) {
                break;
            }
            remaining -= count;
        }
        return length - remaining;
    }

    /**
     * Reads bytes from a ReadableByteChannel.
     * <p>
     * This implementation guarantees that it will read as many bytes as possible before giving up; this may not always be the case for subclasses of
     * {@link ReadableByteChannel}.
     * </p>
     *
     * @param input  the byte channel to read.
     * @param buffer byte buffer destination.
     * @return the actual length read; may be less than requested if EOF was reached.
     * @throws IOException if a read error occurs.
     * @since 2.5
     */
    public static int read(final ReadableByteChannel input, final ByteBuffer buffer) throws IOException {
        final int length = buffer.remaining();
        while (buffer.remaining() > 0) {
            final int count = input.read(buffer);
            if (EOF == count) { // EOF
                break;
            }
        }
        return length - buffer.remaining();
    }

    /**
     * Reads characters from an input character stream.
     * <p>
     * This implementation guarantees that it will read as many characters as possible before giving up; this may not always be the case for subclasses of
     * {@link Reader}.
     * </p>
     *
     * @param reader where to read input from.
     * @param buffer destination.
     * @return actual length read; may be less than requested if EOF was reached.
     * @throws IOException if a read error occurs.
     * @since 2.2
     */
    public static int read(final Reader reader, final char[] buffer) throws IOException {
        return read(reader, buffer, 0, buffer.length);
    }

    /**
     * Reads characters from an input character stream.
     * <p>
     * This implementation guarantees that it will read as many characters as possible before giving up; this may not always be the case for subclasses of
     * {@link Reader}.
     * </p>
     *
     * @param reader where to read input from.
     * @param buffer destination.
     * @param offset initial offset into buffer.
     * @param length length to read, must be &gt;= 0.
     * @return actual length read; may be less than requested if EOF was reached.
     * @throws NullPointerException      if {@code reader} or {@code buffer} is null.
     * @throws IndexOutOfBoundsException if {@code offset} or {@code length} is negative, or if {@code offset + length} is greater than {@code buffer.length}.
     * @throws IOException               if a read error occurs.
     * @since 2.2
     */
    public static int read(final Reader reader, final char[] buffer, final int offset, final int length) throws IOException {
        checkFromIndexSize(buffer, offset, length);
        int remaining = length;
        while (remaining > 0) {
            final int location = length - remaining;
            final int count = reader.read(buffer, offset + location, remaining);
            if (EOF == count) { // EOF
                break;
            }
            remaining -= count;
        }
        return length - remaining;
    }

    /**
     * Reads the requested number of bytes or fail if there are not enough left.
     * <p>
     * This allows for the possibility that {@link InputStream#read(byte[], int, int)} may not read as many bytes as requested (most likely because of reaching
     * EOF).
     * </p>
     *
     * @param input  where to read input from.
     * @param buffer destination.
     * @throws NullPointerException if {@code input} or {@code buffer} is null.
     * @throws EOFException         if the number of bytes read was incorrect.
     * @throws IOException          if there is a problem reading the file.
     * @since 2.2
     */
    public static void readFully(final InputStream input, final byte[] buffer) throws IOException {
        readFully(input, buffer, 0, buffer.length);
    }

    /**
     * Reads the requested number of bytes or fail if there are not enough left.
     * <p>
     * This allows for the possibility that {@link InputStream#read(byte[], int, int)} may not read as many bytes as requested (most likely because of reaching
     * EOF).
     * </p>
     *
     * @param input  where to read input from.
     * @param buffer destination.
     * @param offset initial offset into buffer.
     * @param length length to read, must be &gt;= 0.
     * @throws NullPointerException      if {@code input} or {@code buffer} is null.
     * @throws IndexOutOfBoundsException if {@code offset} or {@code length} is negative, or if {@code offset + length} is greater than {@code buffer.length}.
     * @throws EOFException              if the number of bytes read was incorrect.
     * @throws IOException               if there is a problem reading the file.
     * @since 2.2
     */
    public static void readFully(final InputStream input, final byte[] buffer, final int offset, final int length) throws IOException {
        final int actual = read(input, buffer, offset, length);
        if (actual != length) {
            throw new EOFException("Length to read: " + length + " actual: " + actual);
        }
    }

    /**
     * Reads the requested number of bytes or fail if there are not enough left.
     * <p>
     * This allows for the possibility that {@link InputStream#read(byte[], int, int)} may not read as many bytes as requested (most likely because of reaching
     * EOF).
     * </p>
     *
     * @param input  where to read input from.
     * @param length length to read, must be &gt;= 0.
     * @return the bytes read from input.
     * @throws IOException              if there is a problem reading the file.
     * @throws IllegalArgumentException if length is negative.
     * @throws EOFException             if the number of bytes read was incorrect.
     * @since 2.5
     * @deprecated Use {@link #toByteArray(InputStream, int)}.
     */
    @Deprecated
    public static byte[] readFully(final InputStream input, final int length) throws IOException {
        return toByteArray(input, length);
    }

    /**
     * Reads the requested number of bytes or fail if there are not enough left.
     * <p>
     * This allows for the possibility that {@link ReadableByteChannel#read(ByteBuffer)} may not read as many bytes as requested (most likely because of
     * reaching EOF).
     * </p>
     *
     * @param input  the byte channel to read.
     * @param buffer byte buffer destination.
     * @throws IOException  if there is a problem reading the file.
     * @throws EOFException if the number of bytes read was incorrect.
     * @since 2.5
     */
    public static void readFully(final ReadableByteChannel input, final ByteBuffer buffer) throws IOException {
        final int expected = buffer.remaining();
        final int actual = read(input, buffer);
        if (actual != expected) {
            throw new EOFException("Length to read: " + expected + " actual: " + actual);
        }
    }

    /**
     * Reads the requested number of characters or fail if there are not enough left.
     * <p>
     * This allows for the possibility that {@link Reader#read(char[], int, int)} may not read as many characters as requested (most likely because of reaching
     * EOF).
     * </p>
     *
     * @param reader where to read input from.
     * @param buffer destination.
     * @throws NullPointerException if {@code reader} or {@code buffer} is null.
     * @throws EOFException         if the number of characters read was incorrect.
     * @throws IOException          if there is a problem reading the file.
     * @since 2.2
     */
    public static void readFully(final Reader reader, final char[] buffer) throws IOException {
        readFully(reader, buffer, 0, buffer.length);
    }

    /**
     * Reads the requested number of characters or fail if there are not enough left.
     * <p>
     * This allows for the possibility that {@link Reader#read(char[], int, int)} may not read as many characters as requested (most likely because of reaching
     * EOF).
     * </p>
     *
     * @param reader where to read input from.
     * @param buffer destination.
     * @param offset initial offset into buffer.
     * @param length length to read, must be &gt;= 0.
     * @throws NullPointerException      if {@code reader} or {@code buffer} is null.
     * @throws IndexOutOfBoundsException if {@code offset} or {@code length} is negative, or if {@code offset + length} is greater than {@code buffer.length}.
     * @throws EOFException              if the number of characters read was incorrect.
     * @throws IOException               if there is a problem reading the file.
     * @since 2.2
     */
    public static void readFully(final Reader reader, final char[] buffer, final int offset, final int length) throws IOException {
        final int actual = read(reader, buffer, offset, length);
        if (actual != length) {
            throw new EOFException("Length to read: " + length + " actual: " + actual);
        }
    }

    /**
     * Gets the contents of a {@link CharSequence} as a list of Strings, one entry per line.
     *
     * @param csq the {@link CharSequence} to read, not null.
     * @return the list of Strings, never null.
     * @throws UncheckedIOException if an I/O error occurs.
     * @since 2.18.0
     */
    public static List<String> readLines(final CharSequence csq) throws UncheckedIOException {
        try (CharSequenceReader reader = new CharSequenceReader(csq)) {
            return readLines(reader);
        }
    }

    /**
     * Gets the contents of an {@link InputStream} as a list of Strings, one entry per line, using the virtual machine's {@linkplain Charset#defaultCharset()
     * default charset}.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     *
     * @param input the {@link InputStream} to read, not null.
     * @return the list of Strings, never null.
     * @throws NullPointerException if the input is null.
     * @throws UncheckedIOException if an I/O error occurs.
     * @since 1.1
     * @deprecated Use {@link #readLines(InputStream, Charset)} instead.
     */
    @Deprecated
    public static List<String> readLines(final InputStream input) throws UncheckedIOException {
        return readLines(input, Charset.defaultCharset());
    }

    /**
     * Gets the contents of an {@link InputStream} as a list of Strings, one entry per line, using the specified character encoding.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     *
     * @param input   the {@link InputStream} to read, not null.
     * @param charset the charset to use, null means platform default.
     * @return the list of Strings, never null.
     * @throws NullPointerException if the input is null.
     * @throws UncheckedIOException if an I/O error occurs.
     * @since 2.3
     */
    public static List<String> readLines(final InputStream input, final Charset charset) throws UncheckedIOException {
        return readLines(new InputStreamReader(input, Charsets.toCharset(charset)));
    }

    /**
     * Gets the contents of an {@link InputStream} as a list of Strings, one entry per line, using the specified character encoding.
     * <p>
     * Character encoding names can be found at <a href="https://www.iana.org/assignments/character-sets">IANA</a>.
     * </p>
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedInputStream}.
     * </p>
     *
     * @param input       the {@link InputStream} to read, not null.
     * @param charsetName the name of the requested charset, null means platform default.
     * @return the list of Strings, never null.
     * @throws NullPointerException                         if the input is null.
     * @throws UncheckedIOException                         if an I/O error occurs.
     * @throws java.nio.charset.UnsupportedCharsetException if the encoding is not supported.
     * @since 1.1
     */
    public static List<String> readLines(final InputStream input, final String charsetName) throws UncheckedIOException {
        return readLines(input, Charsets.toCharset(charsetName));
    }

    /**
     * Gets the contents of a {@link Reader} as a list of Strings, one entry per line.
     * <p>
     * This method buffers the input internally, so there is no need to use a {@link BufferedReader}.
     * </p>
     *
     * @param reader the {@link Reader} to read, not null.
     * @return the list of Strings, never null.
     * @throws NullPointerException if the input is null.
     * @throws UncheckedIOException if an I/O error occurs.
     * @since 1.1
     */
    @SuppressWarnings("resource") // reader wraps input and is the responsibility of the caller.
    public static List<String> readLines(final Reader reader) throws UncheckedIOException {
        return toBufferedReader(reader).lines().collect(Collectors.toList());
    }

    /**
     * Gets the contents of a resource as a byte array.
     * <p>
     * Delegates to {@link #resourceToByteArray(String, ClassLoader) resourceToByteArray(String, null)}.
     * </p>
     *
     * @param name The resource name.
     * @return the requested byte array.
     * @throws IOException if an I/O error occurs or the resource is not found.
     * @see #resourceToByteArray(String, ClassLoader)
     * @since 2.6
     */
    public static byte[] resourceToByteArray(final String name) throws IOException {
        return resourceToByteArray(name, null);
    }

    /**
     * Gets the contents of a resource as a byte array.
     * <p>
     * Delegates to {@link #resourceToURL(String, ClassLoader)}.
     * </p>
     *
     * @param name        The resource name.
     * @param classLoader the class loader that the resolution of the resource is delegated to.
     * @return the requested byte array.
     * @throws IOException if an I/O error occurs or the resource is not found.
     * @see #resourceToURL(String, ClassLoader)
     * @since 2.6
     */
    public static byte[] resourceToByteArray(final String name, final ClassLoader classLoader) throws IOException {
        return toByteArray(resourceToURL(name, classLoader));
    }

    /**
     * Gets the contents of a resource as a String using the specified character encoding.
     * <p>
     * Delegates to {@link #resourceToString(String, Charset, ClassLoader) resourceToString(String, Charset, null)}.
     * </p>
     *
     * @param name    The resource name.
     * @param charset the charset to use, null means platform default.
     * @return the requested String.
     * @throws IOException if an I/O error occurs or the resource is not found.
     * @see #resourceToString(String, Charset, ClassLoader)
     * @since 2.6
     */
    public static String resourceToString(final String name, final Charset charset) throws IOException {
        return resourceToString(name, charset, null);
    }

    /**
     * Gets the contents of a resource as a String using the specified character encoding.
     * <p>
     * Delegates to {@link #resourceToURL(String, ClassLoader)}.
     * </p>
     *
     * @param name        The resource name.
     * @param charset     the Charset to use, null means platform default.
     * @param classLoader the class loader that the resolution of the resource is delegated to.
     * @return the requested String.
     * @throws IOException if an I/O error occurs.
     * @see #resourceToURL(String, ClassLoader)
     * @since 2.6
     */
    public static String resourceToString(final String name, final Charset charset, final ClassLoader classLoader) throws IOException {
        return toString(resourceToURL(name, classLoader), charset);
    }

    /**
     * Gets a URL pointing to the given resource.
     * <p>
     * Delegates to {@link #resourceToURL(String, ClassLoader) resourceToURL(String, null)}.
     * </p>
     *
     * @param name The resource name.
     * @return A URL object for reading the resource.
     * @throws IOException if the resource is not found.
     * @since 2.6
     */
    public static URL resourceToURL(final String name) throws IOException {
        return resourceToURL(name, null);
    }

    /**
     * Gets a URL pointing to the given resource.
     * <p>
     * If the {@code classLoader} is not null, call {@link ClassLoader#getResource(String)}, otherwise call {@link Class#getResource(String)
     * IOUtils.class.getResource(name)}.
     * </p>
     *
     * @param name        The resource name.
     * @param classLoader Delegate to this class loader if not null.
     * @return A URL object for reading the resource.
     * @throws IOException if the resource is not found.
     * @since 2.6
     */
    public static URL resourceToURL(final String name, final ClassLoader classLoader) throws IOException {
        // What about the thread context class loader?
        // What about the system class loader?
        final URL resource = classLoader == null ? IOUtils.class.getResource(name) : classLoader.getResource(name);
        if (resource == null) {
            throw new IOException("Resource not found: " + name);
        }
        return resource;
    }

    /**
     * Skips bytes from an input byte stream.
     * <p>
     * This implementation guarantees that it will read as many bytes as possible before giving up; this may not always be the case for skip() implementations
     * in subclasses of {@link InputStream}.
     * </p>
     * <p>
     * Note that the implementation uses {@link InputStream#read(byte[], int, int)} rather than delegating to {@link InputStream#skip(long)}. This means that
     * the method may be considerably less efficient than using the actual skip implementation, this is done to guarantee that the correct number of bytes are
     * skipped.
     * </p>
     *
     * @param input byte stream to skip.
     * @param skip  number of bytes to skip.
     * @return number of bytes actually skipped.
     * @throws IOException              if there is a problem reading the file.
     * @throws IllegalArgumentException if toSkip is negative.
     * @see InputStream#
