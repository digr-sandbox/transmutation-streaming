# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

# Use elixir_bootstrap module to be able to bootstrap Kernel.
# The bootstrap module provides simpler implementations of the
# functions removed, simple enough to bootstrap.
import Kernel,
  except: [@: 1, defmodule: 2, def: 1, def: 2, defp: 2, defmacro: 1, defmacro: 2, defmacrop: 2]

import :elixir_bootstrap

defmodule Kernel do
  @moduledoc """
  `Kernel` is Elixir's default environment.

  It mainly consists of:

    * basic language primitives, such as arithmetic operators, spawning of processes,
      data type handling, and others
    * macros for control-flow and defining new functionality (modules, functions, and the like)
    * guard checks for augmenting pattern matching

  You can invoke `Kernel` functions and macros anywhere in Elixir code
  without the use of the `Kernel.` prefix since they have all been
  automatically imported. For example, in IEx, you can call:

      iex> is_number(13)
      true

  If you don't want to import a function or macro from `Kernel`, use the `:except`
  option and then list the function/macro by arity:

      import Kernel, except: [if: 2, is_number: 1]

  See `import/2` for more information on importing.

  Elixir also has special forms that are always imported and
  cannot be skipped. These are described in `Kernel.SpecialForms`.

  ## The standard library

  `Kernel` provides the basic capabilities the Elixir standard library
  is built on top of. It is recommended to explore the standard library
  for advanced functionality. Here are the main groups of modules in the
  standard library (this list is not a complete reference, see the
  documentation sidebar for all entries).

  ### Built-in types

  The following modules handle Elixir built-in data types:

    * `Atom` - literal constants with a name (`true`, `false`, and `nil` are atoms)
    * `Float` - numbers with floating point precision
    * `Function` - a reference to code chunk, created with the `fn/1` special form
    * `Integer` - whole numbers (not fractions)
    * `List` - collections of a variable number of elements (linked lists)
    * `Map` - collections of key-value pairs
    * `Process` - light-weight threads of execution
    * `Port` - mechanisms to interact with the external world
    * `Tuple` - collections of a fixed number of elements

  There are two data types without an accompanying module:

    * Bitstring - a sequence of bits, created with `<<>>/1`.
      When the number of bits is divisible by 8, they are called binaries and can
      be manipulated with Erlang's [`:binary`](`:binary`) module
    * Reference - a unique value in the runtime system, created with `make_ref/0`

  ### Data types

  Elixir also provides other data types that are built on top of the types
  listed above. Some of them are:

    * `Date` - `year-month-day` structs in a given calendar
    * `DateTime` - date and time with time zone in a given calendar
    * `Exception` - data raised from errors and unexpected scenarios
    * `MapSet` - unordered collections of unique elements
    * `NaiveDateTime` - date and time without time zone in a given calendar
    * `Keyword` - lists of two-element tuples, often representing optional values
    * `Range` - inclusive ranges between two integers
    * `Regex` - regular expressions
    * `String` - UTF-8 encoded binaries representing characters
    * `Time` - `hour:minute:second` structs in a given calendar
    * `URI` - representation of URIs that identify resources
    * `Version` - representation of versions and requirements

  ### System modules

  Modules that interface with the underlying system, such as:

    * `IO` - handles input and output
    * `File` - interacts with the underlying file system
    * `Path` - manipulates file system paths
    * `System` - reads and writes system information

  ### Protocols

  Protocols add polymorphic dispatch to Elixir. They are contracts
  implementable by data types. See `Protocol` for more information on
  protocols. Elixir provides the following protocols in the standard library:

    * `Collectable` - collects data into a data type
    * `Enumerable` - handles collections in Elixir. The `Enum` module
      provides eager functions for working with collections, the `Stream`
      module provides lazy functions
    * `Inspect` - converts data types into their programming language
      representation
    * `List.Chars` - converts data types to their outside world
      representation as charlists (non-programming based)
    * `String.Chars` - converts data types to their outside world
      representation as strings (non-programming based)

  ### Process-based and application-centric functionality

  The following modules build on top of processes to provide concurrency,
  fault-tolerance, and more.

    * `Agent` - a process that encapsulates mutable state
    * `Application` - functions for starting, stopping and configuring
      applications
    * `GenServer` - a generic client-server API
    * `Registry` - a key-value process-based storage
    * `Supervisor` - a process that is responsible for starting,
      supervising and shutting down other processes
    * `Task` - a process that performs computations
    * `Task.Supervisor` - a supervisor for managing tasks exclusively

  ### Supporting documents

  Under the "Pages" section in sidebar you will find tutorials, guides,
  and reference documents that outline Elixir semantics and behaviors
  in more detail. Those are:

    * [Compatibility and deprecations](compatibility-and-deprecations.md) - lists
      compatibility between every Elixir version and Erlang/OTP, release schema;
      lists all deprecated functions, when they were deprecated and alternatives
    * [Library guidelines](library-guidelines.md) - general guidelines, anti-patterns,
      and rules for those writing libraries
    * [Naming conventions](naming-conventions.md) - naming conventions for Elixir code
    * [Operators reference](operators.md) - lists all Elixir operators and their precedences
    * [Patterns and guards](patterns-and-guards.md) - an introduction to patterns,
      guards, and extensions
    * [Syntax reference](syntax-reference.md) - the language syntax reference
    * [Typespecs reference](typespecs.md)- types and function specifications, including list of types
    * [Unicode syntax](unicode-syntax.md) - outlines Elixir support for Unicode

  ## Guards

  This module includes the built-in guards used by Elixir developers.
  They are a predefined set of functions and macros that augment pattern
  matching, typically invoked after the `when` operator. For example:

      def drive(%User{age: age}) when age >= 16 do
        ...
      end

  The clause above will only be invoked if the user's age is more than
  or equal to 16. Guards also support joining multiple conditions with
  `and` and `or`. The whole guard is true if all guard expressions will
  evaluate to `true`. A more complete introduction to guards is available
  in the [Patterns and guards](patterns-and-guards.md) page.

  ## Truthy and falsy values

  Besides the booleans `true` and `false`, Elixir has the
  concept of a "truthy" or "falsy" value.

    *  a value is truthy when it is neither `false` nor `nil`
    *  a value is falsy when it is either `false` or `nil`

  Elixir has functions, like `and/2`, that *only* work with
  booleans, but also functions that work with these
  truthy/falsy values, like `&&/2` and `!/1`.

  ## Structural comparison

  The functions in this module perform structural comparison. This allows
  different data types to be compared using comparison operators:

      1 < :an_atom

  This is possible so Elixir developers can create collections, such as
  dictionaries and ordered sets, that store a mixture of data types in them.
  To understand why this matters, let's discuss the two types of comparisons
  we find in software: _structural_ and _semantic_.

  Structural means we are comparing the underlying data structures and we often
  want those operations to be as fast as possible, because it is used to power
  several algorithms and data structures in the language. A semantic comparison
  worries about what each data type represents. For example, semantically
  speaking, it doesn't make sense to compare `Time` with `Date`.

  One example that shows the differences between structural and semantic
  comparisons are strings: "alien" sorts less than "office" (`"alien" < "office"`)
  but "Ã¡lien" is greater than "office". This happens because `<` compares the
  underlying bytes that form the string. If you were doing alphabetical listing,
  you may want "Ã¡lien" to also appear before "office".

  This means **comparisons in Elixir are structural**, as it has the goal
  of comparing data types as efficiently as possible to create flexible
  and performant data structures. This distinction is specially important
  for functions that provide ordering, such as `>/2`, `</2`, `>=/2`,
  `<=/2`, `min/2`, and `max/2`. For example:

      ~D[2017-03-31] > ~D[2017-04-01]

  will return `true` because structural comparison compares the `:day`
  field before `:month` or `:year`. Luckily, the Elixir compiler will
  detect whenever comparing structs or whenever comparing code that is
  either always true or false, and emit a warning accordingly.

  In order to perform semantic comparisons, the relevant data-types
  provide a `compare/2` function, such as `Date.compare/2`:

      iex> Date.compare(~D[2017-03-31], ~D[2017-04-01])
      :lt

  Alternatively, you can use the functions in the `Enum` module to
  sort or compute a maximum/minimum:

      iex> Enum.sort([~D[2017-03-31], ~D[2017-04-01]], Date)
      [~D[2017-03-31], ~D[2017-04-01]]
      iex> Enum.max([~D[2017-03-31], ~D[2017-04-01]], Date)
      ~D[2017-04-01]

  The second argument is precisely the module to be used for semantic
  comparison. Keeping this distinction is important, because if semantic
  comparison was used by default for implementing data structures and
  algorithms, they could become orders of magnitude slower!

  Finally, note there is an overall structural sorting order, called
  "Term Ordering", defined below. This order is provided for reference
  purposes, it is not required for Elixir developers to know it by heart.

  ### Term ordering

  ```
  number < atom < reference < function < port < pid < tuple < map < list < bitstring
  ```

  When comparing two numbers of different types (a number being either
  an integer or a float), a conversion to the type with greater precision
  will always occur, unless the comparison operator used is either `===/2`
  or `!==/2`. A float will be considered more precise than an integer, unless
  the float is greater/less than +/-9007199254740992.0 respectively,
  at which point all the significant figures of the float are to the left
  of the decimal point. This behavior exists so that the comparison of large
  numbers remains transitive.

  The collection types are compared using the following rules:

  * Tuples are compared by size, then element by element.
  * Maps are compared by size, then by key-value pairs.
  * Lists are compared element by element.
  * Bitstrings are compared byte by byte, incomplete bytes are compared bit by bit.
  * Atoms are compared using their string value, codepoint by codepoint.

  ### Examples

  We can check the truthiness of a value by using the `!/1`
  function twice.

  Truthy values:

      iex> !!true
      true
      iex> !!5
      true
      iex> !![1,2]
      true
      iex> !!"foo"
      true

  Falsy values (of which there are exactly two):

      iex> !!false
      false
      iex> !!nil
      false

  ## Inlining

  Some of the functions described in this module are inlined by
  the Elixir compiler into their Erlang counterparts in the
  [`:erlang`](`:erlang`) module.
  Those functions are called BIFs (built-in internal functions)
  in Erlang-land and they exhibit interesting properties, as some
  of them are allowed in guards and others are used for compiler
  optimizations.

  Most of the inlined functions can be seen in effect when
  capturing the function:

      iex> &Kernel.is_atom/1
      &:erlang.is_atom/1

  Those functions will be explicitly marked in their docs as
  "inlined by the compiler".
  """

  # We need this check only for bootstrap purposes.
  # Once Kernel is loaded and we recompile, it is a no-op.
  @compile {:inline, bootstrapped?: 1}
  case :code.ensure_loaded(Kernel) do
    {:module, _} ->
      defp bootstrapped?(module), do: is_atom(module)

    {:error, _} ->
      defp bootstrapped?(module), do: :code.ensure_loaded(module) == {:module, module}
  end

  ## Delegations to Erlang with inlining (macros)

  @doc """
  Returns an integer or float which is the arithmetical absolute value of `number`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> abs(-3.33)
      3.33

      iex> abs(-3)
      3

  """
  @doc guard: true
  @spec abs(number) :: number
  def abs(number) do
    :erlang.abs(number)
  end

  @doc """
  Invokes the given anonymous function `fun` with the list of
  arguments `args`.

  If the number of arguments is known at compile time, prefer
  `fun.(arg_1, arg_2, ..., arg_n)` as it is clearer than
  `apply(fun, [arg_1, arg_2, ..., arg_n])`.

  Inlined by the compiler.

  ## Examples

      iex> apply(fn x -> x * 2 end, [2])
      4

  """
  @spec apply(fun, [any]) :: any
  def apply(fun, args) do
    :erlang.apply(fun, args)
  end

  @doc """
  Invokes the given function from `module` with the list of
  arguments `args`.

  `apply/3` is used to invoke functions where the module, function
  name or arguments are defined dynamically at runtime. For this
  reason, you can't invoke macros using `apply/3`, only functions.

  If the number of arguments and the function name are known at compile time,
  prefer `module.function(arg_1, arg_2, ..., arg_n)` as it is clearer than
  `apply(module, :function, [arg_1, arg_2, ..., arg_n])`.

  `apply/3` cannot be used to call private functions.

  Inlined by the compiler.

  ## Examples

      iex> apply(Enum, :reverse, [[1, 2, 3]])
      [3, 2, 1]

  """
  @spec apply(module, function_name :: atom, [any]) :: any
  def apply(module, function_name, args) do
    :erlang.apply(module, function_name, args)
  end

  @doc """
  Extracts the part of the binary at `start` with `size`.

  If `start` or `size` reference in any way outside the binary,
  an `ArgumentError` exception is raised.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> binary_part("foo", 1, 2)
      "oo"

  A negative `size` can be used to extract bytes that come *before* the byte
  at `start`:

      iex> binary_part("Hello", 5, -3)
      "llo"

  An `ArgumentError` is raised when the `size` is outside of the binary:

      binary_part("Hello", 0, 10)
      ** (ArgumentError) argument error

  """
  @doc guard: true
  @spec binary_part(binary, non_neg_integer, integer) :: binary
  def binary_part(binary, start, size) do
    :erlang.binary_part(binary, start, size)
  end

  @doc """
  Returns an integer which is the size in bits of `bitstring`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> bit_size(<<433::16, 3::3>>)
      19

      iex> bit_size(<<1, 2, 3>>)
      24

  """
  @doc guard: true
  @spec bit_size(bitstring) :: non_neg_integer
  def bit_size(bitstring) do
    :erlang.bit_size(bitstring)
  end

  @doc """
  Returns the number of bytes needed to contain `bitstring`.

  That is, if the number of bits in `bitstring` is not divisible by 8, the
  resulting number of bytes will be rounded up (by excess). This operation
  happens in constant time.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> byte_size(<<433::16, 3::3>>)
      3

      iex> byte_size(<<1, 2, 3>>)
      3

  """
  @doc guard: true
  @spec byte_size(bitstring) :: non_neg_integer
  def byte_size(bitstring) do
    :erlang.byte_size(bitstring)
  end

  @doc """
  Returns the smallest integer greater than or equal to `number`.

  If you want to perform ceil operation on other decimal places,
  use `Float.ceil/2` instead.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> ceil(10)
      10

      iex> ceil(10.1)
      11

      iex> ceil(-10.1)
      -10

  """
  @doc since: "1.8.0", guard: true
  @spec ceil(number) :: integer
  def ceil(number) do
    :erlang.ceil(number)
  end

  @doc """
  Performs an integer division.

  Raises an `ArithmeticError` exception if one of the arguments is not an
  integer, or when the `divisor` is `0`.

  `div/2` performs *truncated* integer division. This means that
  the result is always rounded towards zero.

  If you want to perform floored integer division (rounding towards negative infinity),
  use `Integer.floor_div/2` instead.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> div(5, 2)
      2

      iex> div(6, -4)
      -1

      iex> div(-99, 2)
      -49

      div(100, 0)
      ** (ArithmeticError) bad argument in arithmetic expression

  """
  @doc guard: true
  @spec div(integer, neg_integer | pos_integer) :: integer
  def div(dividend, divisor) do
    :erlang.div(dividend, divisor)
  end

  @doc """
  Stops the execution of the calling process with the given reason.

  Since evaluating this function causes the process to terminate,
  it has no return value.

  Inlined by the compiler.

  ## Examples

  When a process reaches its end, by default it exits with
  reason `:normal`. You can also call `exit/1` explicitly if you
  want to terminate a process but not signal any failure:

      exit(:normal)

  In case something goes wrong, you can also use `exit/1` with
  a different reason:

      exit(:seems_bad)

  If the exit reason is not `:normal`, all the processes linked to the process
  that exited will crash (unless they are trapping exits).

  ## OTP exits

  Exits are used by the OTP to determine if a process exited abnormally
  or not. The following exits are considered "normal":

    * `exit(:normal)`
    * `exit(:shutdown)`
    * `exit({:shutdown, term})`

  Exiting with any other reason is considered abnormal and treated
  as a crash. This means the default supervisor behavior kicks in,
  error reports are emitted, and so forth.

  This behavior is relied on in many different places. For example,
  `ExUnit` uses `exit(:shutdown)` when exiting the test process to
  signal linked processes, supervision trees and so on to politely
  shut down too.

  ## CLI exits

  Building on top of the exit signals mentioned above, if the
  process started by the command line exits with any of the three
  reasons above, its exit is considered normal and the Operating
  System process will exit with status 0.

  It is, however, possible to customize the operating system exit
  signal by invoking:

      exit({:shutdown, integer})

  This will cause the operating system process to exit with the status given by
  `integer` while signaling all linked Erlang processes to politely
  shut down.

  Any other exit reason will cause the operating system process to exit with
  status `1` and linked Erlang processes to crash.
  """
  @spec exit(term) :: no_return
  def exit(reason) do
    :erlang.exit(reason)
  end

  @doc """
  Returns the largest integer smaller than or equal to `number`.

  If you want to perform floor operation on other decimal places,
  use `Float.floor/2` instead.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> floor(10)
      10

      iex> floor(9.7)
      9

      iex> floor(-9.7)
      -10

  """
  @doc since: "1.8.0", guard: true
  @spec floor(number) :: integer
  def floor(number) do
    :erlang.floor(number)
  end

  @doc """
  Returns the head of a list. Raises `ArgumentError` if the list is empty.

  The head of a list is its first element.

  It works with improper lists.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> hd([1, 2, 3, 4])
      1

      iex> hd([1 | 2])
      1

  Giving it an empty list raises:

      hd([])
      ** (ArgumentError) argument error

  """
  @doc guard: true
  @spec hd(nonempty_maybe_improper_list(elem, term)) :: elem when elem: term
  def hd(list) do
    :erlang.hd(list)
  end

  @doc """
  Returns `true` if `term` is an atom, otherwise returns `false`.

  Note `true`, `false`, and `nil` are atoms in Elixir, as well as
  module names. Therefore this function will return `true` to all
  of those values.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_atom(:name)
      true

      iex> is_atom(false)
      true

      iex> is_atom(AnAtom)
      true

      iex> is_atom("string")
      false

  """
  @doc guard: true
  @spec is_atom(term) :: boolean
  def is_atom(term) do
    :erlang.is_atom(term)
  end

  @doc """
  Returns `true` if `term` is a binary, otherwise returns `false`.

  A binary always contains a complete number of bytes.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_binary("foo")
      true
      iex> is_binary(<<1::3>>)
      false

  """
  @doc guard: true
  @spec is_binary(term) :: boolean
  def is_binary(term) do
    :erlang.is_binary(term)
  end

  @doc """
  Returns `true` if `term` is a bitstring (including a binary), otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_bitstring("foo")
      true
      iex> is_bitstring(<<1::3>>)
      true

  """
  @doc guard: true
  @spec is_bitstring(term) :: boolean
  def is_bitstring(term) do
    :erlang.is_bitstring(term)
  end

  @doc """
  Returns `true` if `term` is either the atom `true` or the atom `false` (i.e.,
  a boolean), otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_boolean(false)
      true

      iex> is_boolean(true)
      true

      iex> is_boolean(:test)
      false

  """
  @doc guard: true
  @spec is_boolean(term) :: boolean
  def is_boolean(term) do
    :erlang.is_boolean(term)
  end

  @doc """
  Returns `true` if `term` is a floating-point number, otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_float(2.15)
      true

      iex> is_float(3.45e5)
      true

      iex> is_float(5)
      false
  """
  @doc guard: true
  @spec is_float(term) :: boolean
  def is_float(term) do
    :erlang.is_float(term)
  end

  @doc """
  Returns `true` if `term` is a function, otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_function(fn x -> x + x end)
      true

      iex> is_function("not a function")
      false

  """
  @doc guard: true
  @spec is_function(term) :: boolean
  def is_function(term) do
    :erlang.is_function(term)
  end

  @doc """
  Returns `true` if `term` is a function that can be applied with `arity` number of arguments;
  otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_function(fn x -> x * 2 end, 1)
      true
      iex> is_function(fn x -> x * 2 end, 2)
      false

  """
  @doc guard: true
  @spec is_function(term, non_neg_integer) :: boolean
  def is_function(term, arity) do
    :erlang.is_function(term, arity)
  end

  @doc """
  Returns `true` if `term` is an integer, otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_integer(5)
      true

      iex> is_integer(5.0)
      false
  """
  @doc guard: true
  @spec is_integer(term) :: boolean
  def is_integer(term) do
    :erlang.is_integer(term)
  end

  @doc """
  Returns `true` if `term` is a list with zero or more elements, otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_list([1, 2, 3])
      true

      iex> is_list(key: :sum, value: 3)
      true

      iex> is_list({1, 2, 3})
      false
  """
  @doc guard: true
  @spec is_list(term) :: boolean
  def is_list(term) do
    :erlang.is_list(term)
  end

  @doc """
  Returns `true` if `term` is either an integer or a floating-point number;
  otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_number(2.15)
      true

      iex> is_number(5)
      true

      iex> is_number(:one)
      false
  """
  @doc guard: true
  @spec is_number(term) :: boolean
  def is_number(term) do
    :erlang.is_number(term)
  end

  @doc """
  Returns `true` if `term` is a PID (process identifier), otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> {:ok, agent_pid} = Agent.start_link(fn -> 0 end)
      iex> is_pid(agent_pid)
      true

      iex> is_pid(self())
      true

      iex> is_pid(:pid)
      false
  """
  @doc guard: true
  @spec is_pid(term) :: boolean
  def is_pid(term) do
    :erlang.is_pid(term)
  end

  @doc """
  Returns `true` if `term` is a port identifier, otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> [port | _] = Port.list()
      iex> is_port(port)
      true

      iex> is_port(:port)
      false
  """
  @doc guard: true
  @spec is_port(term) :: boolean
  def is_port(term) do
    :erlang.is_port(term)
  end

  @doc """
  Returns `true` if `term` is a reference, otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> ref = make_ref()
      iex> is_reference(ref)
      true

      iex> is_reference(:ref)
      false
  """
  @doc guard: true
  @spec is_reference(term) :: boolean
  def is_reference(term) do
    :erlang.is_reference(term)
  end

  @doc """
  Returns `true` if `term` is a tuple, otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_tuple({1, 2, 3})
      true

      iex> is_tuple({})
      true

      iex> is_tuple(true)
      false
  """
  @doc guard: true
  @spec is_tuple(term) :: boolean
  def is_tuple(term) do
    :erlang.is_tuple(term)
  end

  @doc """
  Returns `true` if `term` is a map, otherwise returns `false`.

  Allowed in guard tests. Inlined by the compiler.

  > #### Structs are maps {: .info}
  >
  > Structs are also maps, and many of Elixir data structures are implemented
  > using structs: `Range`s, `Regex`es, `Date`s...
  >
  >     iex> is_map(1..10)
  >     true
  >     iex> is_map(~D[2024-04-18])
  >     true
  >
  > If you mean to specifically check for non-struct maps, use
  > `is_non_struct_map/1` instead.
  >
  >     iex> is_non_struct_map(1..10)
  >     false
  """
  @doc guard: true
  @spec is_map(term) :: boolean
  def is_map(term) do
    :erlang.is_map(term)
  end

  @doc """
  Returns `true` if `key` is a key in `map`, otherwise returns `false`.

  It raises `BadMapError` if the first element is not a map.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> is_map_key(%{a: "foo", b: "bar"}, :a)
      true

      iex> is_map_key(%{a: "foo", b: "bar"}, :c)
      false
  """
  @doc guard: true, since: "1.10.0"
  @spec is_map_key(map, term) :: boolean
  def is_map_key(map, key) do
    :erlang.is_map_key(key, map)
  end

  @doc """
  Returns the length of `list`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> length([1, 2, 3, 4, 5, 6, 7, 8, 9])
      9

  """
  @doc guard: true
  @spec length(list) :: non_neg_integer
  def length(list) do
    :erlang.length(list)
  end

  @doc """
  Returns an almost unique reference.

  The returned reference will re-occur after approximately 2^82 calls;
  therefore it is unique enough for practical purposes.

  Inlined by the compiler.

  ## Examples

      make_ref()
      #=> #Reference<0.0.0.135>

  """
  @spec make_ref() :: reference
  def make_ref() do
    :erlang.make_ref()
  end

  @doc """
  Returns the size of a map.

  The size of a map is the number of key-value pairs that the map contains.

  This operation happens in constant time.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> map_size(%{a: "foo", b: "bar"})
      2

  """
  @doc guard: true
  @spec map_size(map) :: non_neg_integer
  def map_size(map) do
    :erlang.map_size(map)
  end

  @doc """
  Returns the biggest of the two given terms according to
  their structural comparison.

  If the terms compare equal, the first one is returned.

  This performs a structural comparison where all Elixir
  terms can be compared with each other. See the ["Structural
  comparison"](#module-structural-comparison) section
  for more information.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> max(1, 2)
      2
      iex> max("a", "b")
      "b"

  """
  @doc guard: true
  @spec max(first, second) :: first | second when first: term, second: term
  def max(first, second) do
    :erlang.max(first, second)
  end

  @doc """
  Returns the smallest of the two given terms according to
  their structural comparison.

  If the terms compare equal, the first one is returned.

  This performs a structural comparison where all Elixir
  terms can be compared with each other. See the ["Structural
  comparison"](#module-structural-comparison) section
  for more information.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> min(1, 2)
      1
      iex> min("foo", "bar")
      "bar"

  """
  @doc guard: true
  @spec min(first, second) :: first | second when first: term, second: term
  def min(first, second) do
    :erlang.min(first, second)
  end

  @doc """
  Returns an atom representing the name of the local node.
  If the node is not alive, `:nonode@nohost` is returned instead.

  Allowed in guard tests. Inlined by the compiler.
  """
  @doc guard: true
  @spec node() :: node
  def node do
    :erlang.node()
  end

  @doc """
  Returns the node where the given argument is located.
  The argument can be a PID, a reference, or a port.
  If the local node is not alive, `:nonode@nohost` is returned.

  Allowed in guard tests. Inlined by the compiler.
  """
  @doc guard: true
  @spec node(pid | reference | port) :: node
  def node(arg) do
    :erlang.node(arg)
  end

  @doc """
  Computes the remainder of an integer division.

  `rem/2` uses truncated division, which means that
  the result will always have the sign of the `dividend`.

  Raises an `ArithmeticError` exception if one of the arguments is not an
  integer, or when the `divisor` is `0`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> rem(5, 2)
      1
      iex> rem(6, -4)
      2

  """
  @doc guard: true
  @spec rem(integer, neg_integer | pos_integer) :: integer
  def rem(dividend, divisor) do
    :erlang.rem(dividend, divisor)
  end

  @doc """
  Rounds a number to the nearest integer.

  If the number is equidistant to the two nearest integers, rounds away from zero.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> round(5.6)
      6

      iex> round(5.2)
      5

      iex> round(-9.9)
      -10

      iex> round(-9)
      -9

      iex> round(2.5)
      3

      iex> round(-2.5)
      -3

  """
  @doc guard: true
  @spec round(number) :: integer
  def round(number) do
    :erlang.round(number)
  end

  @doc """
  Sends a message to the given `dest` and returns the message.

  `dest` may be a remote or local PID, a local port, a locally
  registered name, or a tuple in the form of `{registered_name, node}` for a
  registered name at another node.

  For additional documentation, see the [`!` operator Erlang
  documentation](https://www.erlang.org/doc/reference_manual/expressions#send).

  Inlined by the compiler.

  ## Examples

      iex> send(self(), :hello)
      :hello

  """
  @spec send(dest :: Process.dest(), message) :: message when message: any
  def send(dest, message) do
    :erlang.send(dest, message)
  end

  @doc """
  Returns the PID (process identifier) of the calling process.

  Allowed in guard clauses. Inlined by the compiler.
  """
  @doc guard: true
  @spec self() :: pid
  def self() do
    :erlang.self()
  end

  @doc """
  Spawns the given function and returns its PID.

  Typically developers do not use the `spawn` functions, instead they use
  abstractions such as `Task`, `GenServer` and `Agent`, built on top of
  `spawn`, that spawns processes with more conveniences in terms of
  introspection and debugging.

  Check the `Process` module for more process-related functions.

  The anonymous function receives 0 arguments, and may return any value.

  Inlined by the compiler.

  ## Examples

      iex> current = self()
      iex> child = spawn(fn -> send(current, {self(), 1 + 2}) end)
      iex> receive do
      ...>   {^child, 3} -> :ok
      ...> end
      :ok

  """
  @spec spawn((-> any)) :: pid
  def spawn(fun) do
    :erlang.spawn(fun)
  end

  @doc """
  Spawns the given function `fun` from the given `module` passing it the given
  `args` and returns its PID.

  Typically developers do not use the `spawn` functions, instead they use
  abstractions such as `Task`, `GenServer` and `Agent`, built on top of
  `spawn`, that spawns processes with more conveniences in terms of
  introspection and debugging.

  Check the `Process` module for more process-related functions.

  Inlined by the compiler.

  ## Examples

      spawn(SomeModule, :function, [1, 2, 3])

  """
  @spec spawn(module, atom, list) :: pid
  def spawn(module, fun, args) do
    :erlang.spawn(module, fun, args)
  end

  @doc """
  Spawns the given function, links it to the current process, and returns its PID.

  Typically developers do not use the `spawn` functions, instead they use
  abstractions such as `Task`, `GenServer` and `Agent`, built on top of
  `spawn`, that spawns processes with more conveniences in terms of
  introspection and debugging.

  Check the `Process` module for more process-related functions. For more
  information on linking, check `Process.link/1`.

  The anonymous function receives 0 arguments, and may return any value.

  Inlined by the compiler.

  ## Examples

      iex> current = self()
      iex> child = spawn_link(fn -> send(current, {self(), 1 + 2}) end)
      iex> receive do
      ...>   {^child, 3} -> :ok
      ...> end
      :ok

  """
  @spec spawn_link((-> any)) :: pid
  def spawn_link(fun) do
    :erlang.spawn_link(fun)
  end

  @doc """
  Spawns the given function `fun` from the given `module` passing it the given
  `args`, links it to the current process, and returns its PID.

  Typically developers do not use the `spawn` functions, instead they use
  abstractions such as `Task`, `GenServer` and `Agent`, built on top of
  `spawn`, that spawns processes with more conveniences in terms of
  introspection and debugging.

  Check the `Process` module for more process-related functions. For more
  information on linking, check `Process.link/1`.

  Inlined by the compiler.

  ## Examples

      spawn_link(SomeModule, :function, [1, 2, 3])

  """
  @spec spawn_link(module, atom, list) :: pid
  def spawn_link(module, fun, args) do
    :erlang.spawn_link(module, fun, args)
  end

  @doc """
  Spawns the given function, monitors it and returns its PID
  and monitoring reference.

  Typically developers do not use the `spawn` functions, instead they use
  abstractions such as `Task`, `GenServer` and `Agent`, built on top of
  `spawn`, that spawns processes with more conveniences in terms of
  introspection and debugging.

  Check the `Process` module for more process-related functions.

  The anonymous function receives 0 arguments, and may return any value.

  Inlined by the compiler.

  ## Examples

      iex> current = self()
      iex> {child, _ref} = spawn_monitor(fn -> send(current, {self(), 1 + 2}) end)
      iex> receive do
      ...>   {^child, 3} -> :ok
      ...> end
      :ok

  """
  @spec spawn_monitor((-> any)) :: {pid, reference}
  def spawn_monitor(fun) do
    :erlang.spawn_monitor(fun)
  end

  @doc """
  Spawns the given module and function passing the given args,
  monitors it and returns its PID and monitoring reference.

  Typically developers do not use the `spawn` functions, instead they use
  abstractions such as `Task`, `GenServer` and `Agent`, built on top of
  `spawn`, that spawns processes with more conveniences in terms of
  introspection and debugging.

  Check the `Process` module for more process-related functions.

  Inlined by the compiler.

  ## Examples

      spawn_monitor(SomeModule, :function, [1, 2, 3])

  """
  @spec spawn_monitor(module, atom, list) :: {pid, reference}
  def spawn_monitor(module, fun, args) do
    :erlang.spawn_monitor(module, fun, args)
  end

  @doc """
  Pipes the first argument, `value`, into the second argument, a function `fun`,
  and returns `value` itself.

  Useful for running synchronous side effects in a pipeline, using the `|>/2` operator.

  ## Examples

      iex> tap(1, fn x -> x + 1 end)
      1

  Most commonly, this is used in pipelines, using the `|>/2` operator.
  For example, let's suppose you want to inspect part of a data structure.
  You could write:

      %{a: 1}
      |> Map.update!(:a, & &1 + 2)
      |> tap(&IO.inspect(&1.a))
      |> Map.update!(:a, & &1 * 2)

  """
  @doc since: "1.12.0"
  defmacro tap(value, fun) do
    quote bind_quoted: [fun: fun, value: value] do
      _ = fun.(value)
      value
    end
  end

  @doc """
  A non-local return from a function.

  Using `throw/1` is generally discouraged, as it allows a function
  to escape from its regular execution flow, which can make the code
  harder to read. Furthermore, all thrown values must be caught by
  `try/catch`. See `try/1` for more information.

  Inlined by the compiler.
  """
  @spec throw(term) :: no_return
  def throw(term) do
    :erlang.throw(term)
  end

  @doc """
  Returns the tail of a list. Raises `ArgumentError` if the list is empty.

  The tail of a list is the list without its first element.

  It works with improper lists.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> tl([1, 2, 3, :go])
      [2, 3, :go]

      iex> tl([:one])
      []

      iex> tl([:a, :b | :improper_end])
      [:b | :improper_end]

      iex> tl([:a | %{b: 1}])
      %{b: 1}

  Giving it an empty list raises:

      tl([])
      ** (ArgumentError) argument error

  """
  @doc guard: true
  @spec tl(nonempty_maybe_improper_list(elem, last)) :: maybe_improper_list(elem, last) | last
        when elem: term, last: term
  def tl(list) do
    :erlang.tl(list)
  end

  @doc """
  Returns the integer part of `number`.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> trunc(5.4)
      5

      iex> trunc(-5.99)
      -5

      iex> trunc(-5)
      -5

  """
  @doc guard: true
  @spec trunc(number) :: integer
  def trunc(number) do
    :erlang.trunc(number)
  end

  @doc """
  Returns the size of a tuple.

  This operation happens in constant time.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> tuple_size({:a, :b, :c})
      3

  """
  @doc guard: true
  @spec tuple_size(tuple) :: non_neg_integer
  def tuple_size(tuple) do
    :erlang.tuple_size(tuple)
  end

  @doc """
  Arithmetic addition operator.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 + 2
      3

  """
  @doc guard: true
  @spec integer + integer :: integer
  @spec float + float :: float
  @spec integer + float :: float
  @spec float + integer :: float
  def left + right do
    :erlang.+(left, right)
  end

  @doc """
  Arithmetic subtraction operator.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 - 2
      -1

  """
  @doc guard: true
  @spec integer - integer :: integer
  @spec float - float :: float
  @spec integer - float :: float
  @spec float - integer :: float
  def left - right do
    :erlang.-(left, right)
  end

  @doc """
  Arithmetic positive unary operator.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> +1
      1

  """
  @doc guard: true
  @spec +integer :: integer
  @spec +float :: float
  def +value do
    :erlang.+(value)
  end

  @doc """
  Arithmetic negative unary operator.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> -2
      -2

  """
  @doc guard: true
  @spec -0 :: 0
  @spec -pos_integer :: neg_integer
  @spec -neg_integer :: pos_integer
  @spec -float :: float
  def -value do
    :erlang.-(value)
  end

  @doc """
  Arithmetic multiplication operator.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 * 2
      2

  """
  @doc guard: true
  @spec integer * integer :: integer
  @spec float * float :: float
  @spec integer * float :: float
  @spec float * integer :: float
  def left * right do
    :erlang.*(left, right)
  end

  @doc """
  Arithmetic division operator.

  The result is always a float. Use `div/2` and `rem/2` if you want
  an integer division or the remainder.

  Raises `ArithmeticError` if `right` is 0 or 0.0.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 / 2
      0.5

      iex> -3.0 / 2.0
      -1.5

      iex> 5 / 1
      5.0

      7 / 0
      ** (ArithmeticError) bad argument in arithmetic expression

  """
  @doc guard: true
  @spec number / number :: float
  def left / right do
    :erlang./(left, right)
  end

  @doc """
  List concatenation operator. Concatenates a proper list and a term, returning a list.

  The complexity of `a ++ b` is proportional to `length(a)`, so avoid repeatedly
  appending to lists of arbitrary length, for example, `list ++ [element]`.
  Instead, consider prepending via `[element | rest]` and then reversing.

  If the `right` operand is not a proper list, it returns an improper list.
  If the `left` operand is not a proper list, it raises `ArgumentError`.
  If the `left` operand is an empty list, it returns the `right` operand.

  Inlined by the compiler.

  ## Examples

      iex> [1] ++ [2, 3]
      [1, 2, 3]

      iex> ~c"foo" ++ ~c"bar"
      ~c"foobar"

      # a non-list on the right will return an improper list
      # with said element at the end
      iex> [1, 2] ++ 3
      [1, 2 | 3]
      iex> [1, 2] ++ {3, 4}
      [1, 2 | {3, 4}]

      # improper list on the right will return an improper list
      iex> [1] ++ [2 | 3]
      [1, 2 | 3]

      # empty list on the left will return the right operand
      iex> [] ++ 1
      1

  The `++/2` operator is right associative, meaning:

      iex> [1, 2, 3] -- [1] ++ [2]
      [3]

  As it is equivalent to:

      iex> [1, 2, 3] -- ([1] ++ [2])
      [3]

  """
  @spec [] ++ a :: a when a: term()
  @spec nonempty_list() ++ term() :: maybe_improper_list()
  def left ++ right do
    :erlang.++(left, right)
  end

  @doc """
  List subtraction operator. Removes the first occurrence of an element
  on the left list for each element on the right.

  This function is optimized so the complexity of `a -- b` is proportional
  to `length(a) * log(length(b))`. See also the [Erlang efficiency
  guide](https://www.erlang.org/doc/system/efficiency_guide.html).

  Inlined by the compiler.

  ## Examples

      iex> [1, 2, 3] -- [1, 2]
      [3]

      iex> [1, 2, 3, 2, 1] -- [1, 2, 2]
      [3, 1]

  The `--/2` operator is right associative, meaning:

      iex> [1, 2, 3] -- [2] -- [3]
      [1, 3]

  As it is equivalent to:

      iex> [1, 2, 3] -- ([2] -- [3])
      [1, 3]

  """
  @spec list -- list :: list
  def left -- right do
    :erlang.--(left, right)
  end

  @doc """
  Strictly boolean "not" operator.

  `value` must be a boolean; if it's not, an `ArgumentError` exception is raised.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> not false
      true

  """
  @doc guard: true
  @spec not true :: false
  @spec not false :: true
  def not value do
    :erlang.not(value)
  end

  @doc """
  Less-than operator.

  Returns `true` if `left` is less than `right`.

  This performs a structural comparison where all Elixir
  terms can be compared with each other. See the ["Structural
  comparison"](#module-structural-comparison) section
  for more information.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 < 2
      true

  """
  @doc guard: true
  @spec term < term :: boolean
  def left < right do
    :erlang.<(left, right)
  end

  @doc """
  Greater-than operator.

  Returns `true` if `left` is more than `right`.

  This performs a structural comparison where all Elixir
  terms can be compared with each other. See the ["Structural
  comparison"](#module-structural-comparison) section
  for more information.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 > 2
      false

  """
  @doc guard: true
  @spec term > term :: boolean
  def left > right do
    :erlang.>(left, right)
  end

  @doc """
  Less-than or equal to operator.

  Returns `true` if `left` is less than or equal to `right`.

  This performs a structural comparison where all Elixir
  terms can be compared with each other. See the ["Structural
  comparison"](#module-structural-comparison) section
  for more information.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 <= 2
      true

  """
  @doc guard: true
  @spec term <= term :: boolean
  def left <= right do
    :erlang."=<"(left, right)
  end

  @doc """
  Greater-than or equal to operator.

  Returns `true` if `left` is more than or equal to `right`.

  This performs a structural comparison where all Elixir
  terms can be compared with each other. See the ["Structural
  comparison"](#module-structural-comparison) section
  for more information.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 >= 2
      false

  """
  @doc guard: true
  @spec term >= term :: boolean
  def left >= right do
    :erlang.>=(left, right)
  end

  @doc """
  Equal to operator. Returns `true` if the two terms are equal.

  This operator considers 1 and 1.0 to be equal. For stricter
  semantics, use `===/2` instead.

  This performs a structural comparison where all Elixir
  terms can be compared with each other. See the ["Structural
  comparison"](#module-structural-comparison) section
  for more information.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 == 2
      false

      iex> 1 == 1.0
      true

  """
  @doc guard: true
  @spec term == term :: boolean
  def left == right do
    :erlang.==(left, right)
  end

  @doc """
  Not equal to operator.

  Returns `true` if the two terms are not equal.

  This operator considers 1 and 1.0 to be equal. For match
  comparison, use `!==/2` instead.

  This performs a structural comparison where all Elixir
  terms can be compared with each other. See the ["Structural
  comparison"](#module-structural-comparison) section
  for more information.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 != 2
      true

      iex> 1 != 1.0
      false

  """
  @doc guard: true
  @spec term != term :: boolean
  def left != right do
    :erlang."/="(left, right)
  end

  @doc """
  Strictly equal to operator.

  Returns `true` if the two terms are exactly equal.

  The terms are only considered to be exactly equal if they
  have the same value and are of the same type. For example,
  `1 == 1.0` returns `true`, but since they are of different
  types, `1 === 1.0` returns `false`.

  This performs a structural comparison where all Elixir
  terms can be compared with each other. See the ["Structural
  comparison"](#module-structural-comparison) section
  for more information.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 === 2
      false

      iex> 1 === 1.0
      false

  """
  @doc guard: true
  @spec term === term :: boolean
  def left === right do
    :erlang."=:="(left, right)
  end

  @doc """
  Strictly not equal to operator.

  Returns `true` if the two terms are not exactly equal.
  See `===/2` for a definition of what is considered "exactly equal".

  This performs a structural comparison where all Elixir
  terms can be compared with each other. See the ["Structural
  comparison"](#module-structural-comparison) section
  for more information.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> 1 !== 2
      true

      iex> 1 !== 1.0
      true

  """
  @doc guard: true
  @spec term !== term :: boolean
  def left !== right do
    :erlang."=/="(left, right)
  end

  @doc """
  Gets the element at the zero-based `index` in `tuple`.

  It raises `ArgumentError` when index is negative or it is out of range of the tuple elements.

  Allowed in guard tests. Inlined by the compiler.

  ## Examples

      iex> tuple = {:foo, :bar, 3}
      iex> elem(tuple, 1)
      :bar

      elem({}, 0)
      ** (ArgumentError) argument error

      elem({:foo, :bar}, 2)
      ** (ArgumentError) argument error

  """
  @doc guard: true
  @spec elem(tuple, non_neg_integer) :: term
  def elem(tuple, index) do
    :erlang.element(index + 1, tuple)
  end

  @doc """
  Puts `value` at the given zero-based `index` in `tuple`.

  Inlined by the compiler.

  ## Examples

      iex> tuple = {:foo, :bar, 3}
      iex> put_elem(tuple, 0, :baz)
      {:baz, :bar, 3}

  """
  @spec put_elem(tuple, non_neg_integer, term) :: tuple
  def put_elem(tuple, index, value) do
    :erlang.setelement(index + 1, tuple, value)
  end

  ## Implemented in Elixir

  defp annotate_case(extra, {:case, meta, args}) do
    {:case, extra ++ meta, args}
  end

  defp x_is_false_or_nil do
    quote generated: true do
      :erlang.orelse(:erlang."=:="(x, false), :erlang."=:="(x, nil))
    end
  end

  @doc """
  Strictly boolean "or" operator.

  If `left` is `true`, returns `true`, otherwise returns `right`.

  Requires only the `left` operand to be a boolean since it short-circuits.
  If the `left` operand is not a boolean, a `BadBooleanError` exception is
  raised.

  Allowed in guard tests.

  ## Examples

      iex> true or false
      true

      iex> false or 42
      42

      iex> 42 or false
      ** (BadBooleanError) expected a boolean on left-side of "or", got: 42

  """
  @doc guard: true
  defmacro left or right do
    case __CALLER__.context do
      nil -> build_boolean_check(:or, left, true, right)
      :match -> invalid_match!(:or)
      :guard -> quote(do: :erlang.orelse(unquote(left), unquote(right)))
    end
  end

  @doc """
  Strictly boolean "and" operator.

  If `left` is `false`, returns `false`, otherwise returns `right`.

  Requires only the `left` operand to be a boolean since it short-circuits. If
  the `left` operand is not a boolean, a `BadBooleanError` exception is raised.

  Allowed in guard tests.

  ## Examples

      iex> true and false
      false

      iex> true and "yay!"
      "yay!"

      iex> "yay!" and true
      ** (BadBooleanError) expected a boolean on left-side of "and", got: "yay!"

  """
  @doc guard: true
  defmacro left and right do
    case __CALLER__.context do
      nil -> build_boolean_check(:and, left, right, false)
      :match -> invalid_match!(:and)
      :guard -> quote(do: :erlang.andalso(unquote(left), unquote(right)))
    end
  end

  defp build_boolean_check(operator, check, true_clause, false_clause) do
    bools =
      quote do
        false -> unquote(false_clause)
        true -> unquote(true_clause)
      end

    error =
      quote generated: true do
        other -> :erlang.error({:badbool, unquote(operator), other})
      end

    annotate_case(
      [optimize_boolean: true, type_check: {:case, operator}],
      {:case, [], [check, [do: bools ++ error]]}
    )
  end

  @doc """
  Boolean "not" operator.

  Receives any value (not just booleans) and returns `true` if `value`
  is `false` or `nil`; returns `false` otherwise.

  Not allowed in guard clauses.

  ## Examples

      iex> !Enum.empty?([])
      false

      iex> !List.first([])
      true

  """
  defmacro !value

  defmacro !{:!, _, [value]} do
    assert_no_match_or_guard_scope(__CALLER__.context, "!")

    annotate_case(
      [optimize_boolean: true, type_check: {:case, :!}],
      quote do
        case unquote(value) do
          x when unquote(x_is_false_or_nil()) -> false
          _ -> true
        end
      end
    )
  end

  defmacro !value do
    assert_no_match_or_guard_scope(__CALLER__.context, "!")

    annotate_case(
      [optimize_boolean: true, type_check: {:case, :!}],
      quote do
        case unquote(value) do
          x when unquote(x_is_false_or_nil()) -> true
          _ -> false
        end
      end
    )
  end

  @doc """
  Binary concatenation operator. Concatenates two binaries.

  Raises an `ArgumentError` if one of the sides aren't binaries.

  ## Examples

      iex> "foo" <> "bar"
      "foobar"

  The `<>/2` operator can also be used in pattern matching (and guard clauses) as
  long as the left argument is a literal binary:

      iex> "foo" <> x = "foobar"
      iex> x
      "bar"

  `x <> "bar" = "foobar"` would result in an `ArgumentError` exception.

  """
  defmacro left <> right do
    concats = extract_concatenations({:<>, [], [left, right]}, __CALLER__)
    quote(do: <<unquote_splicing(concats)>>)
  end

  # Extracts concatenations in order to optimize many
  # concatenations into one single clause.
  defp extract_concatenations({:<>, _, [left, right]}, caller) do
    [wrap_concatenation(left, :left, caller) | extract_concatenations(right, caller)]
  end

  defp extract_concatenations(other, caller) do
    [wrap_concatenation(other, :right, caller)]
  end

  defp wrap_concatenation(binary, _side, _caller) when is_binary(binary) do
    binary
  end

  defp wrap_concatenation(literal, _side, _caller)
       when is_list(literal) or is_atom(literal) or is_integer(literal) or is_float(literal) do
    :erlang.error(
      ArgumentError.exception(
        "expected binary argument in <> operator but got: #{Macro.to_string(literal)}"
      )
    )
  end

  defp wrap_concatenation(other, side, caller) do
    expanded = expand_concat_argument(other, side, caller)
    {:"::", [], [expanded, {:binary, [], nil}]}
  end

  defp expand_concat_argument(arg, :left, %{context: :match} = caller) do
    expanded_arg =
      case bootstrapped?(Macro) do
        true -> Macro.expand(arg, caller)
        false -> arg
      end

    case expanded_arg do
      {var, _, nil} when is_atom(var) ->
        invalid_concat_left_argument_error(Atom.to_string(var))

      _ ->
        expanded_arg
    end
  end

  defp expand_concat_argument(arg, _, _) do
    arg
  end

  defp invalid_concat_left_argument_error(arg) do
    :erlang.error(
      ArgumentError.exception(
        "cannot perform prefix match because the left operand of <> has unknown size. " <>
          "The left operand of <> inside a match should either be a literal binary or " <>
          "an existing variable with the pin operator (such as ^some_var). Got: #{arg}"
      )
    )
  end

  @doc """
  Raises an exception.

  If `message` is a string, it raises a `RuntimeError` exception with it.

  If `message` is an atom, it just calls `raise/2` with the atom as the first
  argument and `[]` as the second one.

  If `message` is an exception struct, it is raised as is.

  If `message` is anything else, `raise` will fail with an `ArgumentError`
  exception.

  ## Examples

      iex> raise "oops"
      ** (RuntimeError) oops

      try do
        1 + :foo
      rescue
        x in [ArithmeticError] ->
          IO.puts("that was expected")
          raise x
      end

  """
  defmacro raise(message) do
    # Try to figure out the type at compilation time
    # to avoid dead code and make Dialyzer happy.
    message =
      case not is_binary(message) and bootstrapped?(Macro) do
        true -> Macro.expand(message, __CALLER__)
        false -> message
      end

    erlang_error =
      fn x ->
        quote do
          :erlang.error(unquote(x), :none, error_info: %{module: Exception})
        end
      end

    case message do
      message when is_binary(message) ->
        erlang_error.(quote do: RuntimeError.exception(unquote(message)))

      {:<<>>, _, _} = message ->
        erlang_error.(quote do: RuntimeError.exception(unquote(message)))

      alias when is_atom(alias) ->
        erlang_error.(quote do: unquote(alias).exception([]))

      _ ->
        erlang_error.(quote do: Kernel.Utils.raise(unquote(message)))
    end
  end

  @doc """
  Raises an exception.

  Calls the `exception/1` function on the given argument (which has to be a
  module name like `ArgumentError` or `RuntimeError`) passing `attributes`
  in order to retrieve the exception struct.

  Any module that contains a call to the `defexception/1` macro automatically
  implements the `c:Exception.exception/1` callback expected by `raise/2`.
  For more information, see `defexception/1`.

  ## Examples

      iex> raise(ArgumentError, "Sample")
      ** (ArgumentError) Sample

  """
  defmacro raise(exception, attributes) do
    quote do
      :erlang.error(unquote(exception).exception(unquote(attributes)))
    end
  end

  @doc """
  Raises an exception preserving a previous stacktrace.

  Works like `raise/1` but does not generate a new stacktrace.

  Note that `__STACKTRACE__` can be used inside catch/rescue
  to retrieve the current stacktrace.

  ## Examples

      iex> try do
      ...>  raise "oops"
      ...> rescue
      ...>  exception ->
      ...>    reraise exception, __STACKTRACE__
      ...> end
      ** (RuntimeError) oops

  """
  defmacro reraise(message, stacktrace) do
    # Try to figure out the type at compilation time
    # to avoid dead code and make Dialyzer happy.
    case Macro.expand(message, __CALLER__) do
      message when is_binary(message) ->
        quote do
          :erlang.raise(:error, RuntimeError.exception(unquote(message)), unquote(stacktrace))
        end

      {:<<>>, _, _} = message ->
        quote do
          :erlang.raise(:error, RuntimeError.exception(unquote(message)), unquote(stacktrace))
        end

      alias when is_atom(alias) ->
        quote do
          :erlang.raise(:error, unquote(alias).exception([]), unquote(stacktrace))
        end

      message ->
        quote do
          :erlang.raise(:error, Kernel.Utils.raise(unquote(message)), unquote(stacktrace))
        end
    end
  end

  @doc """
  Raises an exception preserving a previous stacktrace.

  `reraise/3` works like `reraise/2`, except it passes arguments to the
  `exception/1` function as explained in `raise/2`.

  ## Examples

      try do
        raise "oops"
      rescue
        exception ->
          reraise WrapperError, [exception: exception], __STACKTRACE__
      end

  """
  defmacro reraise(exception, attributes, stacktrace) do
    quote do
      :erlang.raise(
        :error,
        unquote(exception).exception(unquote(attributes)),
        unquote(stacktrace)
      )
    end
  end

  @doc """
  Text-based match operator. Matches the string on the `left`
  against the regular expression or string on the `right`.

  If `right` is a regular expression, returns `true` if `left` matches right.

  If `right` is a string, returns `true` if `left` contains `right`.

  ## Examples

      iex> "abcd" =~ ~r/c(d)/
      true

      iex> "abcd" =~ ~r/e/
      false

      iex> "abcd" =~ ~r//
      true

      iex> "abcd" =~ "bc"
      true

      iex> "abcd" =~ "ad"
      false

      iex> "abcd" =~ "abcd"
      true

      iex> "abcd" =~ ""
      true

  For more information about regular expressions, please check the `Regex` module.
  """
  @spec String.t() =~ (String.t() | Regex.t()) :: boolean
  def left =~ "" when is_binary(left), do: true

  def left =~ right when is_binary(left) and is_binary(right) do
    :binary.match(left, right) != :nomatch
  end

  def left =~ right when is_binary(left) do
    Regex.match?(right, left)
  end

  @doc ~S"""
  Inspects the given argument according to the `Inspect` protocol.
  The second argument is a keyword list with options to control
  inspection.

  ## Options

  `inspect/2` accepts a list of options that are internally
  translated to an `Inspect.Opts` struct. Check the docs for
  `Inspect.Opts` to see the supported options.

  ## Examples

      iex> inspect(:foo)
      ":foo"

      iex> inspect([1, 2, 3, 4, 5], limit: 3)
      "[1, 2, 3, ...]"

      iex> inspect([1, 2, 3], pretty: true, width: 0)
      "[1,\n 2,\n 3]"

      iex> inspect("olÃ¡" <> <<0>>)
      "<<111, 108, 195, 161, 0>>"

      iex> inspect("olÃ¡" <> <<0>>, binaries: :as_strings)
      "\"olÃ¡\\0\""

      iex> inspect("olÃ¡", binaries: :as_binaries)
      "<<111, 108, 195, 161>>"

      iex> inspect(~c"bar")
      "~c\"bar\""

      iex> inspect([0 | ~c"bar"])
      "[0, 98, 97, 114]"

      iex> inspect(100, base: :octal)
      "0o144"

      iex> inspect(100, base: :hex)
      "0x64"

  Note that the `Inspect` protocol does not necessarily return a valid
  representation of an Elixir term. In such cases, the inspected result
  must start with `#`. For example, inspecting a function will return:

      inspect(fn a, b -> a + b end)
      #=> #Function<...>

  The `Inspect` protocol can be derived to hide certain fields
  from structs, so they don't show up in logs, inspects and similar.
  See the "Deriving" section of the documentation of the `Inspect`
  protocol for more information.
  """
  @spec inspect(Inspect.t(), [Inspect.Opts.new_opt()]) :: String.t()
  def inspect(term, opts \\ []) when is_list(opts) do
    opts = Inspect.Opts.new(opts)

    limit =
      case opts.pretty do
        true -> opts.width
        false -> :infinity
      end

    doc = Inspect.Algebra.group(Inspect.Algebra.to_doc(term, opts))
    IO.iodata_to_binary(Inspect.Algebra.format(doc, limit))
  end

  @doc """
  Creates and updates a struct.

  The `struct` argument may be an atom (which defines `defstruct`)
  or a `struct` itself. The second argument is any `Enumerable` that
  emits two-element tuples (key-value pairs) during enumeration.

  Keys in the `Enumerable` that don't exist in the struct are automatically
  discarded. Note that keys must be atoms, as only atoms are allowed when
  defining a struct. If there are duplicate keys in the `Enumerable`, the last
  entry will be taken (same behavior as `Map.new/1`).

  This function is useful for dynamically creating and updating structs, as
  well as for converting maps to structs; in the latter case, just inserting
  the appropriate `:__struct__` field into the map may not be enough and
  `struct/2` should be used instead.

  ## Examples

      defmodule User do
        defstruct name: "john"
      end

      struct(User)
      #=> %User{name: "john"}

      opts = [name: "meg"]
      user = struct(User, opts)
      #=> %User{name: "meg"}

      struct(user, unknown: "value")
      #=> %User{name: "meg"}

      struct(User, %{name: "meg"})
      #=> %User{name: "meg"}

      # String keys are ignored
      struct(User, %{"name" => "meg"})
      #=> %User{name: "john"}

  """
  @spec struct(module | struct, Enumerable.t()) :: struct
  def struct(struct, fields \\ []) do
    struct(struct, fields, fn
      {:__struct__, _val}, acc ->
        acc

      {key, val}, acc ->
        case acc do
          %{^key => _} -> %{acc | key => val}
          _ -> acc
        end
    end)
  end

  @doc """
  Similar to `struct/2` but checks for key validity.

  The function `struct!/2` emulates the compile time behavior
  of structs. This means that:

    * when building a struct, as in `struct!(SomeStruct, key: :value)`,
      it is equivalent to `%SomeStruct{key: :value}` and therefore this
      function will check if every given key-value belongs to the struct.
      If the struct is enforcing any key via `@enforce_keys`, those will
      be enforced as well;

    * when updating a struct, as in `struct!(%SomeStruct{}, key: :value)`,
      it is equivalent to `%SomeStruct{struct | key: :value}` and therefore this
      function will check if every given key-value belongs to the struct.

  """
  @spec struct!(module | struct, Enumerable.t()) :: struct
  def struct!(struct, fields \\ [])

  def struct!(struct, fields) when is_atom(struct) do
    validate_struct!(struct.__struct__(fields), struct, 1)
  end

  def struct!(struct, fields) when is_map(struct) do
    struct(struct, fields, fn
      {:__struct__, _}, acc ->
        acc

      {key, val}, acc ->
        Map.replace!(acc, key, val)
    end)
  end

  defp struct(struct, [], _fun) when is_atom(struct) do
    validate_struct!(struct.__struct__(), struct, 0)
  end

  defp struct(struct, fields, fun) when is_atom(struct) do
    struct(validate_struct!(struct.__struct__(), struct, 0), fields, fun)
  end

  defp struct(%_{} = struct, [], _fun) do
    struct
  end

  defp struct(%_{} = struct, fields, fun) do
    Enum.reduce(fields, struct, fun)
  end

  defp validate_struct!(%{__struct__: module} = struct, module, _arity) do
    struct
  end

  defp validate_struct!(%{__struct__: struct_name}, module, arity) when is_atom(struct_name) do
    error_message =
      "expected struct name returned by #{inspect(module)}.__struct__/#{arity} to be " <>
        "#{inspect(module)}, got: #{inspect(struct_name)}"

    :erlang.error(ArgumentError.exception(error_message))
  end

  defp validate_struct!(expr, module, arity) do
    error_message =
      "expected #{inspect(module)}.__struct__/#{arity} to return a map with a :__struct__ " <>
        "key that holds the name of the struct (atom), got: #{inspect(expr)}"

    :erlang.error(ArgumentError.exception(error_message))
  end

  @doc """
  Returns `true` if `term` is a struct, otherwise returns `false`.

  Allowed in guard tests.

  ## Examples

      iex> is_struct(URI.parse("/"))
      true

      iex> is_struct(%{})
      false

  """
  @doc since: "1.10.0", guard: true
  defmacro is_struct(term) do
    case __CALLER__.context do
      nil ->
        quote do
          case unquote(term) do
            %_{} -> true
            _ -> false
          end
        end

      :match ->
        invalid_match!(:is_struct)

      :guard ->
        quote do
          is_map(unquote(term)) and :erlang.is_map_key(:__struct__, unquote(term)) and
            is_atom(:erlang.map_get(:__struct__, unquote(term)))
        end
    end
  end

  @doc """
  Returns `true` if `term` is a struct of `name`, otherwise returns `false`.

  `is_struct/2` does not check that `name` exists and is a valid struct.
  If you want such validations, you must pattern match on the struct
  instead, such as `match?(%URI{}, arg)`.

  Allowed in guard tests.

  ## Examples

      iex> is_struct(URI.parse("/"), URI)
      true

      iex> is_struct(URI.parse("/"), Macro.Env)
      false

  """
  @doc since: "1.11.0", guard: true
  defmacro is_struct(term, name) do
    case __CALLER__.context do
      nil ->
        quote generated: true do
          case unquote(name) do
            name when is_atom(name) ->
              case unquote(term) do
                %{__struct__: ^name} -> true
                _ -> false
              end

            _ ->
              raise ArgumentError
          end
        end

      :match ->
        invalid_match!(:is_struct)

      :guard ->
        quote do
          is_map(unquote(term)) and
            (is_atom(unquote(name)) or :fail) and
            :erlang.is_map_key(:__struct__, unquote(term)) and
            :erlang.map_get(:__struct__, unquote(term)) == unquote(name)
        end
    end
  end

  @doc """
  Returns `true` if `term` is a map that is not a struct, otherwise
  returns `false`.

  Allowed in guard tests.

  ## Examples

      iex> is_non_struct_map(%{})
      true

      iex> is_non_struct_map(URI.parse("/"))
      false

      iex> is_non_struct_map(nil)
      false

  """
  @doc since: "1.17.0", guard: true
  defmacro is_non_struct_map(term) do
    case __CALLER__.context do
      nil ->
        quote do
          case unquote(term) do
            %_{} -> false
            %{} -> true
            _ -> false
          end
        end

      :match ->
        invalid_match!(:is_non_struct_map)

      :guard ->
        quote do
          is_map(unquote(term)) and
            not (:erlang.is_map_key(:__struct__, unquote(term)) and
                   is_atom(:erlang.map_get(:__struct__, unquote(term))))
        end
    end
  end

  @doc """
  Returns `true` if `term` is an exception, otherwise returns `false`.

  Allowed in guard tests.

  ## Examples

      iex> is_exception(%RuntimeError{})
      true

      iex> is_exception(%{})
      false

  """
  @doc since: "1.11.0", guard: true
  defmacro is_exception(term) do
    case __CALLER__.context do
      nil ->
        quote do
          case unquote(term) do
            %_{__exception__: true} -> true
            _ -> false
          end
        end

      :match ->
        invalid_match!(:is_exception)

      :guard ->
        quote do
          is_map(unquote(term)) and :erlang.is_map_key(:__struct__, unquote(term)) and
            is_atom(:erlang.map_get(:__struct__, unquote(term))) and
            :erlang.is_map_key(:__exception__, unquote(term)) and
            :erlang.map_get(:__exception__, unquote(term)) == true
        end
    end
  end

  @doc """
  Returns `true` if `term` is an exception of `name`, otherwise returns `false`.

  Allowed in guard tests.

  ## Examples

      iex> is_exception(%RuntimeError{}, RuntimeError)
      true

      iex> is_exception(%RuntimeError{}, Macro.Env)
      false

  """
  @doc since: "1.11.0", guard: true
  defmacro is_exception(term, name) do
    case __CALLER__.context do
      nil ->
        quote do
          case unquote(name) do
            name when is_atom(name) ->
              case unquote(term) do
                %{__struct__: ^name, __exception__: true} -> true
                _ -> false
              end

            _ ->
              raise ArgumentError
          end
        end

      :match ->
        invalid_match!(:is_exception)

      :guard ->
        quote do
          is_map(unquote(term)) and
            (is_atom(unquote(name)) or :fail) and
            :erlang.is_map_key(:__struct__, unquote(term)) and
            :erlang.map_get(:__struct__, unquote(term)) == unquote(name) and
            :erlang.is_map_key(:__exception__, unquote(term)) and
            :erlang.map_get(:__exception__, unquote(term)) == true
        end
    end
  end

  @doc """
  Pipes the first argument, `value`, into the second argument, a function `fun`,
  and returns the result of calling `fun`.

  In other words, it invokes the function `fun` with `value` as argument,
  and returns its result.

  This is most commonly used in pipelines, using the `|>/2` operator, allowing you
  to pipe a value to a function outside of its first argument.

  ## Examples

      iex> 1 |> then(fn x -> x * 2 end)
      2

      iex> 1 |> then(fn x -> Enum.drop(["a", "b", "c"], x) end)
      ["b", "c"]
  """
  @doc since: "1.12.0"
  defmacro then(value, fun) do
    quote do
      unquote(fun).(unquote(value))
    end
  end

  @doc """
  Gets a value from a nested structure with nil-safe handling.

  Uses the `Access` module to traverse the structures
  according to the given `keys`, unless the `key` is a
  function, which is detailed in a later section.

  ## Examples

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> get_in(users, ["john", :age])
      27
      iex> # Equivalent to:
      iex> users["john"][:age]
      27

  `get_in/2` can also use the accessors in the `Access` module
  to traverse more complex data structures. For example, here we
  use `Access.all/0` to traverse a list:

      iex> users = [%{name: "john", age: 27}, %{name: "meg", age: 23}]
      iex> get_in(users, [Access.all(), :age])
      [27, 23]

  In case any of the components returns `nil`, `nil` will be returned
  and `get_in/2` won't traverse any further:

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> get_in(users, ["unknown", :age])
      nil
      iex> # Equivalent to:
      iex> users["unknown"][:age]
      nil

  ## Functions as keys

  If a key given to `get_in/2` is a function, the function will be invoked
  passing three arguments:

    * the operation (`:get`)
    * the data to be accessed
    * a function to be invoked next

  This means `get_in/2` can be extended to provide custom lookups.
  That's precisely how the `Access.all/0` key in the previous section
  behaves. For example, we can manually implement such traversal as
  follows:

      iex> users = [%{name: "john", age: 27}, %{name: "meg", age: 23}]
      iex> all = fn :get, data, next -> Enum.map(data, next) end
      iex> get_in(users, [all, :age])
      [27, 23]

  The `Access` module ships with many convenience accessor functions.
  See `Access.all/0`, `Access.key/2`, and others as examples.

  ## Working with structs

  By default, structs do not implement the `Access` behaviour required
  by this function. Therefore, you can't do this:

      get_in(some_struct, [:some_key, :nested_key])

  There are two alternatives. Given structs have predefined keys,
  we can use the `struct.field` notation:

      some_struct.some_key.nested_key

  However, the code above will fail if any of the values return `nil`.
  If you also want to handle nil values, you can use `get_in/1`:

      get_in(some_struct.some_key.nested_key)

  Pattern-matching is another option for handling such cases,
  which can be especially useful if you want to match on several
  fields at once or provide custom return values:

      case some_struct do
        %{some_key: %{nested_key: value}} -> value
        %{} -> nil
      end

  """
  @spec get_in(Access.t(), nonempty_list(term)) :: term
  def get_in(data, keys)

  def get_in(nil, [_ | _]), do: nil

  def get_in(data, [h]) when is_function(h), do: h.(:get, data, & &1)
  def get_in(data, [h | t]) when is_function(h), do: h.(:get, data, &get_in(&1, t))

  def get_in(data, [h]), do: Access.get(data, h)
  def get_in(data, [h | t]), do: get_in(Access.get(data, h), t)

  @doc """
  Puts a value in a nested structure.

  Uses the `Access` module to traverse the structures
  according to the given `keys`, unless the `key` is a
  function. If the key is a function, it will be invoked
  as specified in `get_and_update_in/3`.

  ## Examples

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> put_in(users, ["john", :age], 28)
      %{"john" => %{age: 28}, "meg" => %{age: 23}}

  If any of the intermediate values are nil, it will raise:

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> put_in(users, ["jane", :age], "oops")
      ** (ArgumentError) could not put/update key :age on a nil value

  """
  @spec put_in(Access.t(), nonempty_list(term), term) :: Access.t()
  def put_in(data, [_ | _] = keys, value) do
    elem(get_and_update_in(data, keys, fn _ -> {nil, value} end), 1)
  end

  @doc """
  Updates a key in a nested structure.

  Uses the `Access` module to traverse the structures
  according to the given `keys`, unless the `key` is a
  function. If the key is a function, it will be invoked
  as specified in `get_and_update_in/3`.

  `data` is a nested structure (that is, a map, keyword
  list, or struct that implements the `Access` behaviour).
  The `fun` argument receives the value of `key` (or `nil`
  if `key` is not present) and the result replaces the value
  in the structure.

  ## Examples

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> update_in(users, ["john", :age], &(&1 + 1))
      %{"john" => %{age: 28}, "meg" => %{age: 23}}

  Note the current value given to the anonymous function may be `nil`.
  If any of the intermediate values are nil, it will raise:

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> update_in(users, ["jane", :age], & &1 + 1)
      ** (ArgumentError) could not put/update key :age on a nil value

  """
  @spec update_in(Access.t(), nonempty_list(term), (term -> term)) :: Access.t()
  def update_in(data, [_ | _] = keys, fun) when is_function(fun) do
    elem(get_and_update_in(data, keys, fn x -> {nil, fun.(x)} end), 1)
  end

  @doc """
  Gets a value and updates a nested structure.

  `data` is a nested structure (that is, a map, keyword
  list, or struct that implements the `Access` behaviour).

  The `fun` argument receives the value of `key` (or `nil` if `key`
  is not present) and must return one of the following values:

    * a two-element tuple `{current_value, new_value}`. In this case,
      `current_value` is the retrieved value which can possibly be operated on before
      being returned. `new_value` is the new value to be stored under `key`.

    * `:pop`, which implies that the current value under `key`
      should be removed from the structure and returned.

  This function uses the `Access` module to traverse the structures
  according to the given `keys`, unless the `key` is a function,
  which is detailed in a later section.

  ## Examples

  This function is useful when there is a need to retrieve the current
  value (or something calculated in function of the current value) and
  update it at the same time. For example, it could be used to read the
  current age of a user while increasing it by one in one pass:

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> get_and_update_in(users, ["john", :age], &{&1, &1 + 1})
      {27, %{"john" => %{age: 28}, "meg" => %{age: 23}}}

  Note the current value given to the anonymous function may be `nil`.
  If any of the intermediate values are nil, it will raise:

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> get_and_update_in(users, ["jane", :age], &{&1, &1 + 1})
      ** (ArgumentError) could not put/update key :age on a nil value

  ## Functions as keys

  If a key is a function, the function will be invoked passing three
  arguments:

    * the operation (`:get_and_update`)
    * the data to be accessed
    * a function to be invoked next

  This means `get_and_update_in/3` can be extended to provide custom
  lookups. The downside is that functions cannot be stored as keys
  in the accessed data structures.

  When one of the keys is a function, the function is invoked.
  In the example below, we use a function to get and increment all
  ages inside a list:

      iex> users = [%{name: "john", age: 27}, %{name: "meg", age: 23}]
      iex> all = fn :get_and_update, data, next ->
      ...>   data |> Enum.map(next) |> Enum.unzip()
      ...> end
      iex> get_and_update_in(users, [all, :age], &{&1, &1 + 1})
      {[27, 23], [%{name: "john", age: 28}, %{name: "meg", age: 24}]}

  If the previous value before invoking the function is `nil`,
  the function *will* receive `nil` as a value and must handle it
  accordingly (be it by failing or providing a sane default).

  The `Access` module ships with many convenience accessor functions,
  like the `all` anonymous function defined above. See `Access.all/0`,
  `Access.key/2`, and others as examples.
  """
  @spec get_and_update_in(
          structure,
          keys,
          (term | nil -> {current_value, new_value} | :pop)
        ) :: {current_value, new_structure :: structure}
        when structure: Access.t(),
             keys: nonempty_list(term),
             current_value: Access.value(),
             new_value: Access.value()
  def get_and_update_in(data, keys, fun)

  def get_and_update_in(data, [head], fun) when is_function(head, 3),
    do: head.(:get_and_update, data, fun)

  def get_and_update_in(data, [head | tail], fun) when is_function(head, 3),
    do: head.(:get_and_update, data, &get_and_update_in(&1, tail, fun))

  def get_and_update_in(data, [head], fun) when is_function(fun, 1),
    do: Access.get_and_update(data, head, fun)

  def get_and_update_in(data, [head | tail], fun) when is_function(fun, 1),
    do: Access.get_and_update(data, head, &get_and_update_in(&1, tail, fun))

  @doc """
  Pops a key from the given nested structure.

  Uses the `Access` protocol to traverse the structures
  according to the given `keys`, unless the `key` is a
  function. If the key is a function, it will be invoked
  as specified in `get_and_update_in/3`.

  ## Examples

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> pop_in(users, ["john", :age])
      {27, %{"john" => %{}, "meg" => %{age: 23}}}

  In case any entry returns `nil`, its key will be removed
  and the deletion will be considered a success.

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> pop_in(users, ["jane", :age])
      {nil, %{"john" => %{age: 27}, "meg" => %{age: 23}}}

  """
  @spec pop_in(data, nonempty_list(Access.get_and_update_fun(term, data) | term)) :: {term, data}
        when data: Access.container()
  def pop_in(data, keys)

  def pop_in(nil, [key | _]) do
    raise ArgumentError, "could not pop key #{inspect(key)} on a nil value"
  end

  def pop_in(data, [_ | _] = keys) do
    pop_in_data(data, keys)
  end

  defp pop_in_data(nil, [_ | _]), do: :pop

  defp pop_in_data(data, [fun]) when is_function(fun),
    do: fun.(:get_and_update, data, fn _ -> :pop end)

  defp pop_in_data(data, [fun | tail]) when is_function(fun),
    do: fun.(:get_and_update, data, &pop_in_data(&1, tail))

  defp pop_in_data(data, [key]), do: Access.pop(data, key)

  defp pop_in_data(data, [key | tail]),
    do: Access.get_and_update(data, key, &pop_in_data(&1, tail))

  @doc """
  Gets a key from the nested structure via the given `path`, with
  nil-safe handling.

  This is similar to `get_in/2`, except the path is extracted via
  a macro rather than passing a list. For example:

      get_in(opts[:foo][:bar])

  Is equivalent to:

      get_in(opts, [:foo, :bar])

  Additionally, this macro can traverse structs:

      get_in(struct.foo.bar)

  In case any of the keys returns `nil`, then `nil` will be returned
  and `get_in/1` won't traverse any further.

  Note that in order for this macro to work, the complete path must always
  be visible by this macro. For more information about the supported path
  expressions, please check `get_and_update_in/2` docs.

  ## Examples

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> get_in(users["john"].age)
      27
      iex> get_in(users["unknown"].age)
      nil

  """
  @doc since: "1.17.0"
  defmacro get_in(path) do
    {[h | t], _} = unnest(path, [], true, "get_in/1")
    nest_get_in(h, quote(do: x), t)
  end

  defp nest_get_in(h, _var, []) do
    h
  end

  defp nest_get_in(h, var, [{:map, key} | tail]) do
    quote generated: true do
      case unquote(h) do
        %{unquote(key) => unquote(var)} -> unquote(nest_get_in(var, var, tail))
        nil -> nil
        unquote(var) -> :erlang.error({:badkey, unquote(key), unquote(var)})
      end
    end
  end

  defp nest_get_in(h, var, [{:access, key} | tail]) do
    h = quote do: Access.get(unquote(h), unquote(key))
    nest_get_in(h, var, tail)
  end

  @doc """
  Puts a value in a nested structure via the given `path`.

  This is similar to `put_in/3`, except the path is extracted via
  a macro rather than passing a list. For example:

      put_in(opts[:foo][:bar], :baz)

  Is equivalent to:

      put_in(opts, [:foo, :bar], :baz)

  This also works with nested structs and the `struct.path.to.value` way to specify
  paths:

      put_in(struct.foo.bar, :baz)

  Note that in order for this macro to work, the complete path must always
  be visible by this macro. For more information about the supported path
  expressions, please check `get_and_update_in/2` docs.

  ## Examples

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> put_in(users["john"][:age], 28)
      %{"john" => %{age: 28}, "meg" => %{age: 23}}

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> put_in(users["john"].age, 28)
      %{"john" => %{age: 28}, "meg" => %{age: 23}}

  """
  defmacro put_in(path, value) do
    case unnest(path, [], true, "put_in/2") do
      {[h | t], true} ->
        nest_map_update_in(h, t, quote(do: fn _ -> unquote(value) end))

      {[h | t], false} ->
        expr = nest_get_and_update_in(h, t, quote(do: fn _ -> {nil, unquote(value)} end))
        quote(do: :erlang.element(2, unquote(expr)))
    end
  end

  @doc """
  Pops a key from the nested structure via the given `path`.

  This is similar to `pop_in/2`, except the path is extracted via
  a macro rather than passing a list. For example:

      pop_in(opts[:foo][:bar])

  Is equivalent to:

      pop_in(opts, [:foo, :bar])

  Note that in order for this macro to work, the complete path must always
  be visible by this macro. For more information about the supported path
  expressions, please check `get_and_update_in/2` docs.

  ## Examples

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> pop_in(users["john"][:age])
      {27, %{"john" => %{}, "meg" => %{age: 23}}}

      iex> users = %{john: %{age: 27}, meg: %{age: 23}}
      iex> pop_in(users.john[:age])
      {27, %{john: %{}, meg: %{age: 23}}}

  In case any entry returns `nil`, its key will be removed
  and the deletion will be considered a success.
  """
  defmacro pop_in(path) do
    {[h | t], _} = unnest(path, [], true, "pop_in/1")
    nest_pop_in(:map, h, t)
  end

  @doc """
  Updates a nested structure via the given `path`.

  This is similar to `update_in/3`, except the path is extracted via
  a macro rather than passing a list. For example:

      update_in(opts[:foo][:bar], &(&1 + 1))

  Is equivalent to:

      update_in(opts, [:foo, :bar], &(&1 + 1))

  This also works with nested structs and the `struct.path.to.value` way to specify
  paths:

      update_in(struct.foo.bar, &(&1 + 1))

  Note that in order for this macro to work, the complete path must always
  be visible by this macro. For more information about the supported path
  expressions, please check `get_and_update_in/2` docs.

  ## Examples

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> update_in(users["john"][:age], &(&1 + 1))
      %{"john" => %{age: 28}, "meg" => %{age: 23}}

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> update_in(users["john"].age, &(&1 + 1))
      %{"john" => %{age: 28}, "meg" => %{age: 23}}

  """
  defmacro update_in(path, fun) do
    case unnest(path, [], true, "update_in/2") do
      {[h | t], true} ->
        nest_map_update_in(h, t, fun)

      {[h | t], false} ->
        expr = nest_get_and_update_in(h, t, quote(do: fn x -> {nil, unquote(fun).(x)} end))
        quote(do: :erlang.element(2, unquote(expr)))
    end
  end

  @doc """
  Gets a value and updates a nested data structure via the given `path`.

  This is similar to `get_and_update_in/3`, except the path is extracted
  via a macro rather than passing a list. For example:

      get_and_update_in(opts[:foo][:bar], &{&1, &1 + 1})

  Is equivalent to:

      get_and_update_in(opts, [:foo, :bar], &{&1, &1 + 1})

  This also works with nested structs and the `struct.path.to.value` way to specify
  paths:

      get_and_update_in(struct.foo.bar, &{&1, &1 + 1})

  Note that in order for this macro to work, the complete path must always
  be visible by this macro. See the "Paths" section below.

  ## Examples

      iex> users = %{"john" => %{age: 27}, "meg" => %{age: 23}}
      iex> get_and_update_in(users["john"].age, &{&1, &1 + 1})
      {27, %{"john" => %{age: 28}, "meg" => %{age: 23}}}

  ## Paths

  A path may start with a variable, local or remote call, and must be
  followed by one or more:

    * `foo[bar]` - accesses the key `bar` in `foo`; in case `foo` is nil,
      `nil` is returned

    * `foo.bar` - accesses a map/struct field; in case the field is not
      present, an error is raised

  Here are some valid paths:

      users["john"][:age]
      users["john"].age
      User.all()["john"].age
      all_users()["john"].age

  Here are some invalid ones:

      # Does a remote call after the initial value
      users["john"].do_something(arg1, arg2)

      # Does not access any key or field
      users

  """
  defmacro get_and_update_in(path, fun) do
    {[h | t], _} = unnest(path, [], true, "get_and_update_in/2")
    nest_get_and_update_in(h, t, fun)
  end

  defp nest_map_update_in([], fun), do: fun

  defp nest_map_update_in(list, fun) do
    quote do
      fn x -> unquote(nest_map_update_in(quote(do: x), list, fun)) end
    end
  end

  defp nest_map_update_in(h, [{:map, key} | t], fun) do
    quote do
      Map.update!(unquote(h), unquote(key), unquote(nest_map_update_in(t, fun)))
    end
  end

  defp nest_get_and_update_in([], fun), do: fun

  defp nest_get_and_update_in(list, fun) do
    quote do
      fn x -> unquote(nest_get_and_update_in(quote(do: x), list, fun)) end
    end
  end

  defp nest_get_and_update_in(h, [{:access, key} | t], fun) do
    quote do
      Access.get_and_update(unquote(h), unquote(key), unquote(nest_get_and_update_in(t, fun)))
    end
  end

  defp nest_get_and_update_in(h, [{:map, key} | t], fun) do
    quote do
      Map.get_and_update!(unquote(h), unquote(key), unquote(nest_get_and_update_in(t, fun)))
    end
  end

  defp nest_pop_in(kind, list) do
    quote do
      fn x -> unquote(nest_pop_in(kind, quote(do: x), list)) end
    end
  end

  defp nest_pop_in(:map, h, [{:access, key}]) do
    quote generated: true do
      case unquote(h) do
        nil -> {nil, nil}
        h -> Access.pop(h, unquote(key))
      end
    end
  end

  defp nest_pop_in(_, _, [{:map, key}]) do
    raise ArgumentError,
          "cannot use pop_in when the last segment is a map/struct field. " <>
            "This would effectively remove the field #{inspect(key)} from the map/struct"
  end

  defp nest_pop_in(_, h, [{:map, key} | t]) do
    quote do
      Map.get_and_update!(unquote(h), unquote(key), unquote(nest_pop_in(:map, t)))
    end
  end

  defp nest_pop_in(_, h, [{:access, key}]) do
    quote generated: true do
      case unquote(h) do
        nil -> :pop
        h -> Access.pop(h, unquote(key))
      end
    end
  end

  defp nest_pop_in(_, h, [{:access, key} | t]) do
    quote do
      Access.get_and_update(unquote(h), unquote(key), unquote(nest_pop_in(:access, t)))
    end
  end

  defp unnest({{:., _, [Access, :get]}, _, [expr, key]}, acc, _all_map?, kind) do
    unnest(expr, [{:access, key} | acc], false, kind)
  end

  defp unnest({{:., _, [expr, key]}, _, []}, acc, all_map?, kind)
       when is_tuple(expr) and :erlang.element(1, expr) != :__aliases__ and
              :erlang.element(1, expr) != :__MODULE__ do
    unnest(expr, [{:map, key} | acc], all_map?, kind)
  end

  defp unnest(other, [], _all_map?, kind) do
    raise ArgumentError,
          "expected expression given to #{kind} to access at least one element, " <>
            "got: #{Macro.to_string(other)}"
  end

  defp unnest(other, acc, all_map?, kind) do
    case proper_start?(other) do
      true ->
        {[other | acc], all_map?}

      false ->
        raise ArgumentError,
              "expression given to #{kind} must start with a variable, local or remote call " <>
                "and be followed by an element access, got: #{Macro.to_string(other)}"
    end
  end

  defp proper_start?({{:., _, [expr, _]}, _, _args})
       when is_atom(expr)
       when :erlang.element(1, expr) == :__aliases__
       when :erlang.element(1, expr) == :__MODULE__,
       do: true

  defp proper_start?({atom, _, _args})
       when is_atom(atom),
       do: true

  defp proper_start?(other), do: not is_tuple(other)

  @doc """
  Converts the argument to a string according to the
  `String.Chars` protocol.

  This is invoked when there is string interpolation.

  ## Examples

      iex> to_string(:foo)
      "foo"

  """
  defmacro to_string(term) do
    quote(do: :"Elixir.String.Chars".to_string(unquote(term)))
  end

  @doc """
  Converts the given term to a charlist according to the `List.Chars` protocol.

  ## Examples

      iex> to_charlist(:foo)
      ~c"foo"

  """
  defmacro to_charlist(term) do
    quote(do: :"Elixir.List.Chars".to_charlist(unquote(term)))
  end

  @doc """
  Returns `true` if `term` is `nil`, `false` otherwise.

  Allowed in guard clauses.

  ## Examples

      iex> is_nil(1 + 2)
      false

      iex> is_nil(nil)
      true

  """
  @doc guard: true
  defmacro is_nil(term) do
    quote(do: unquote(term) == nil)
  end

  @doc """
  A convenience macro that checks if the result of `expression` matches `pattern`.

  ## Examples

      iex> match?(1, 1)
      true

      iex> match?({1, _}, {1, 2})
      true

      iex> map = %{a: 1, b: 2}
      iex> match?(%{a: _}, map)
      true

      iex> a = 1
      iex> match?(^a, 1)
      true

  `match?/2` is very useful when filtering or finding a value in an enumerable:

      iex> list = [a: 1, b: 2, a: 3]
      iex> Enum.filter(list, &match?({:a, _}, &1))
      [a: 1, a: 3]

  Guard clauses can also be given to the match:

      iex> list = [a: 1, b: 2, a: 3]
      iex> Enum.filter(list, &match?({:a, x} when x < 2, &1))
      [a: 1]

  Variables assigned in the match will not be available outside of the
  function call (unlike regular pattern matching with the `=` operator):

      iex> match?(_x, 1)
      true
      iex> binding()
      []

  ## Values vs patterns

  Remember the pin operator matches _values_, not _patterns_.
  Passing a variable as the pattern will always return `true` and will
  result in a warning that the variable is unused. Don't do this:

      pattern = %{a: :a}
      match?(pattern, %{b: :b})
      #=> true

  Similarly, moving an expression out the pattern may no longer preserve
  its semantics. For example:

      iex> match?([_ | _], [1, 2, 3])
      true

      pattern = [_ | _]
      match?(pattern, [1, 2, 3])
      ** (CompileError) invalid use of _. _ can only be used inside patterns to ignore values and cannot be used in expressions. Make sure you are inside a pattern or change it accordingly

  Another example is that a map as a pattern performs a subset match, but not
  once assigned to a variable:

      iex> match?(%{x: 1}, %{x: 1, y: 2})
      true

      iex> attrs = %{x: 1}
      iex> match?(^attrs, %{x: 1, y: 2})
      false

  The pin operator will check if the values are equal, using `===/2`, while
  patterns have their own rules when matching maps, lists, and so forth.
  Such behavior is not specific to `match?/2`. The following code also
  throws an exception:

      attrs = %{x: 1}
      ^attrs = %{x: 1, y: 2}
      #=> (MatchError) no match of right hand side value: %{x: 1, y: 2}

  """
  defmacro match?(pattern, expression) do
    success =
      quote do
        unquote(pattern) -> true
      end

    failure =
      quote generated: true do
        _ -> false
      end

    {:case, [], [expression, [do: success ++ failure]]}
  end

  @doc """
  Module attribute unary operator.

  Reads and writes attributes in the current module.

  The canonical example for attributes is annotating that a module
  implements an OTP behaviour, such as `GenServer`:

      defmodule MyServer do
        @behaviour GenServer
        # ... callbacks ...
      end

  By default Elixir supports all the module attributes supported by Erlang, but
  custom attributes can be used as well:

      defmodule MyServer do
        @my_data 13
        IO.inspect(@my_data)
        #=> 13
      end

  Unlike Erlang, such attributes are not stored in the module by default since
  it is common in Elixir to use custom attributes to store temporary data that
  will be available at compile-time. Custom attributes may be configured to
  behave closer to Erlang by using `Module.register_attribute/3`.

  > #### Prefixing module attributes {: .tip}
  >
  > Libraries and frameworks should consider prefixing any
  > module attributes that are private by underscore, such as `@_my_data`,
  > so code completion tools do not show them on suggestions and prompts.

  Finally, note that attributes can also be read inside functions:

      defmodule MyServer do
        @my_data 11
        def first_data, do: @my_data
        @my_data 13
        def second_data, do: @my_data
      end

      MyServer.first_data()
      #=> 11

      MyServer.second_data()
      #=> 13

  It is important to note that reading an attribute takes a snapshot of
  its current value. In other words, the value is read at compilation
  time and not at runtime. Check the `Module` module for other functions
  to manipulate module attributes.

  ## Attention! Multiple references of the same attribute

  As mentioned above, every time you read a module attribute, a snapshot
  of its current value is taken. Therefore, if you are storing large
  values inside module attributes (for example, embedding external files
  in module attributes), you should avoid referencing the same attribute
  multiple times. For example, don't do this:

      @files %{
        example1: File.read!("lib/example1.data"),
        example2: File.read!("lib/example2.data")
      }

      def example1, do: @files[:example1]
      def example2, do: @files[:example2]

  In the above, each reference to `@files` may end-up with a complete
  and individual copy of the whole `@files` module attribute. Instead,
  reference the module attribute once in a private function:

      @files %{
        example1: File.read!("lib/example1.data"),
        example2: File.read!("lib/example2.data")
      }

      defp files(), do: @files
      def example1, do: files()[:example1]
      def example2, do: files()[:example2]

  """
  defmacro @expr

  defmacro @{:__aliases__, _meta, _args} do
    raise ArgumentError, "module attributes set via @ cannot start with an uppercase letter"
  end

  defmacro @{name, meta, args} do
    assert_module_scope(__CALLER__, :@, 1)
    function? = __CALLER__.function != nil

    cond do
      # Check for Macro as it is compiled later than Kernel
      not bootstrapped?(Macro) ->
        nil

      not function? and (__CALLER__.context == :match or __CALLER__.context == :guard) ->
        raise ArgumentError,
              """
              invalid usage of module attributes. Module attributes cannot be used inside \
              pattern matching (and guards) outside of a function. If you are trying to \
              define an attribute, do not do this:

                  @foo = :value

              Instead, do this:

                  @foo :value
              """

      # Typespecs attributes are currently special cased by the compiler
      is_list(args) and typespec?(name) ->
        case bootstrapped?(Kernel.Typespec) do
          false ->
            :ok

          true ->
            pos = :elixir_module.cache_env(__CALLER__)
            %{line: line, file: file, module: module} = __CALLER__

            quote do
              Kernel.Typespec.deftypespec(
                unquote(name),
                unquote(Macro.escape(hd(args), unquote: true)),
                unquote(line),
                unquote(file),
                unquote(module),
                unquote(pos)
              )
            end
        end

      true ->
        do_at(args, meta, name, function?, __CALLER__)
    end
  end

  # @attribute(value)
  defp do_at([arg], meta, name, function?, env) do
    line =
      case :lists.keymember(:context, 1, meta) do
       
