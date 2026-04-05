# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

defprotocol Enumerable do
  @moduledoc """
  Enumerable protocol used by `Enum` and `Stream` modules.

  When you invoke a function in the `Enum` module, the first argument
  is usually a collection that must implement this protocol.
  For example, the expression `Enum.map([1, 2, 3], &(&1 * 2))`
  invokes `Enumerable.reduce/3` to perform the reducing operation that
  builds a mapped list by calling the mapping function `&(&1 * 2)` on
  every element in the collection and consuming the element with an
  accumulated list.

  Internally, `Enum.map/2` is implemented as follows:

      def map(enumerable, fun) do
        reducer = fn x, acc -> {:cont, [fun.(x) | acc]} end
        Enumerable.reduce(enumerable, {:cont, []}, reducer) |> elem(1) |> :lists.reverse()
      end

  Note that the user-supplied function is wrapped into a `t:reducer/0` function.
  The `t:reducer/0` function must return a tagged tuple after each step,
  as described in the `t:acc/0` type. At the end, `Enumerable.reduce/3`
  returns `t:result/0`.

  This protocol uses tagged tuples to exchange information between the
  reducer function and the data type that implements the protocol. This
  allows enumeration of resources, such as files, to be done efficiently
  while also guaranteeing the resource will be closed at the end of the
  enumeration. This protocol also allows suspension of the enumeration,
  which is useful when interleaving between many enumerables is required
  (as in the `zip/1` and `zip/2` functions).

  This protocol requires four functions to be implemented, `reduce/3`,
  `count/1`, `member?/2`, and `slice/1`. The core of the protocol is the
  `reduce/3` function. All other functions exist as optimizations paths
  for data structures that can implement certain properties in better
  than linear time.

  ## Default implementation for lists

  Sometimes you may want to implement this protocol for a list contained
  in struct. This can be done by delegating to the `Enumerable.List` module
  in the `reduce/3` implementation and providing a straight-forward
  implementation for the remaining ones:

      defimpl Enumerable, for: CustomStruct do
        def count(struct), do: {:ok, length(struct.items)}
        def member?(struct, value), do: {:ok, value in struct.items}
        def slice(struct), do: {:error, __MODULE__}
        def reduce(struct, acc, fun), do: Enumerable.List.reduce(struct.items, acc, fun)
      end
  """

  @typedoc """
  An enumerable of elements of type `element`.

  This type is equivalent to `t:t/0` but is especially useful for documentation.

  For example, imagine you define a function that expects an enumerable of
  integers and returns an enumerable of strings:

      @spec integers_to_strings(Enumerable.t(integer())) :: Enumerable.t(String.t())
      def integers_to_strings(integers) do
        Stream.map(integers, &Integer.to_string/1)
      end

  """
  @typedoc since: "1.14.0"
  @type t(_element) :: t()

  @typedoc """
  The accumulator value for each step.

  It must be a tagged tuple with one of the following "tags":

    * `:cont`    - the enumeration should continue
    * `:halt`    - the enumeration should halt immediately
    * `:suspend` - the enumeration should be suspended immediately

  Depending on the accumulator value, the result returned by
  `Enumerable.reduce/3` will change. Please check the `t:result/0`
  type documentation for more information.

  In case a `t:reducer/0` function returns a `:suspend` accumulator,
  it must be explicitly handled by the caller and never leak.
  """
  @type acc :: {:cont, term} | {:halt, term} | {:suspend, term}

  @typedoc """
  The reducer function.

  Should be called with the `enumerable` element and the
  accumulator contents.

  Returns the accumulator for the next enumeration step.
  """
  @type reducer :: (element :: term, element_acc :: term -> acc)

  @typedoc """
  The result of the reduce operation.

  It may be *done* when the enumeration is finished by reaching
  its end, or *halted*/*suspended* when the enumeration was halted
  or suspended by the tagged accumulator.

  In case the tagged `:halt` accumulator is given, the `:halted` tuple
  with the accumulator must be returned. Functions like `Enum.take_while/2`
  use `:halt` underneath and can be used to test halting enumerables.

  In case the tagged `:suspend` accumulator is given, the caller must
  return the `:suspended` tuple with the accumulator and a continuation.
  The caller is then responsible of managing the continuation and the
  caller must always call the continuation, eventually halting or continuing
  until the end. `Enum.zip/2` uses suspension, so it can be used to test
  whether your implementation handles suspension correctly. You can also use
  `Stream.zip/2` with `Enum.take_while/2` to test the combination of
  `:suspend` with `:halt`.
  """
  @type result ::
          {:done, term}
          | {:halted, term}
          | {:suspended, term, continuation}

  @typedoc """
  A partially applied reduce function.

  The continuation is the closure returned as a result when
  the enumeration is suspended. When invoked, it expects
  a new accumulator and it returns the result.

  A continuation can be trivially implemented as long as the reduce
  function is defined in a tail recursive fashion. If the function
  is tail recursive, all the state is passed as arguments, so
  the continuation is the reducing function partially applied.
  """
  @type continuation :: (acc -> result)

  @typedoc """
  A slicing function that receives the initial position,
  the number of elements in the slice, and the step.

  The `start` position is a number `>= 0` and guaranteed to
  exist in the `enumerable`. The length is a number `>= 1`
  in a way that `start + length * step <= count`, where
  `count` is the maximum amount of elements in the enumerable.

  The function should return a non empty list where
  the amount of elements is equal to `length`.
  """
  @type slicing_fun ::
          (start :: non_neg_integer, length :: pos_integer, step :: pos_integer -> [term()])

  @typedoc """
  Receives an enumerable and returns a list.
  """
  @type to_list_fun :: (t -> [term()])

  @doc """
  Reduces the `enumerable` into an element.

  Most of the operations in `Enum` are implemented in terms of reduce.
  This function should apply the given `t:reducer/0` function to each
  element in the `enumerable` and proceed as expected by the returned
  accumulator.

  See the documentation of the types `t:result/0` and `t:acc/0` for
  more information.

  ## Examples

  As an example, here is the implementation of `reduce` for lists:

      def reduce(_list, {:halt, acc}, _fun), do: {:halted, acc}
      def reduce(list, {:suspend, acc}, fun), do: {:suspended, acc, &reduce(list, &1, fun)}
      def reduce([], {:cont, acc}, _fun), do: {:done, acc}
      def reduce([head | tail], {:cont, acc}, fun), do: reduce(tail, fun.(head, acc), fun)

  """
  @spec reduce(t, acc, reducer) :: result
  def reduce(enumerable, acc, fun)

  @doc """
  Retrieves the number of elements in the `enumerable`.

  It should return `{:ok, count}` if you can count the number of elements
  in `enumerable` in a faster way than fully traversing it.

  Otherwise it should return `{:error, __MODULE__}` and a default algorithm
  built on top of `reduce/3` that runs in linear time will be used.
  """
  @spec count(t) :: {:ok, non_neg_integer} | {:error, module}
  def count(enumerable)

  @doc """
  Checks if an `element` exists within the `enumerable`.

  It should return `{:ok, boolean}` if you can check the membership of a
  given element in `enumerable` with `===/2` without traversing the whole
  of it.

  Otherwise it should return `{:error, __MODULE__}` and a default algorithm
  built on top of `reduce/3` that runs in linear time will be used.

  When called outside guards, the [`in`](`in/2`) and [`not in`](`in/2`)
  operators work by using this function.
  """
  @spec member?(t, term) :: {:ok, boolean} | {:error, module}
  def member?(enumerable, element)

  @doc """
  Returns a function that slices the data structure contiguously.

  It should return either:

    * `{:ok, size, slicing_fun}` - if the `enumerable` has a known
      bound and can access a position in the `enumerable` without
      traversing all previous elements. The `slicing_fun` will receive
      a `start` position, the `amount` of elements to fetch, and a
      `step`.

    * `{:ok, size, to_list_fun}` - if the `enumerable` has a known bound
      and can access a position in the `enumerable` by first converting
      it to a list via `to_list_fun`.

    * `{:error, __MODULE__}` - the enumerable cannot be sliced efficiently
      and a default algorithm built on top of `reduce/3` that runs in
      linear time will be used.

  ## Differences to `count/1`

  The `size` value returned by this function is used for boundary checks,
  therefore it is extremely important that this function only returns `:ok`
  if retrieving the `size` of the `enumerable` is cheap, fast, and takes
  constant time. Otherwise the simplest of operations, such as
  `Enum.at(enumerable, 0)`, will become too expensive.

  On the other hand, the `count/1` function in this protocol should be
  implemented whenever you can count the number of elements in the collection
  without traversing it.
  """
  @spec slice(t) ::
          {:ok, size :: non_neg_integer(), slicing_fun() | to_list_fun()}
          | {:error, module()}
  def slice(enumerable)
end

defmodule Enum do
  import Kernel, except: [max: 2, min: 2]

  @moduledoc """
  Functions for working with collections (known as enumerables).

  In Elixir, an enumerable is any data type that implements the
  `Enumerable` protocol. `List`s (`[1, 2, 3]`), `Map`s (`%{foo: 1, bar: 2}`)
  and `Range`s (`1..3`) are common data types used as enumerables:

      iex> Enum.map([1, 2, 3], fn x -> x * 2 end)
      [2, 4, 6]

      iex> Enum.sum([1, 2, 3])
      6

      iex> Enum.map(1..3, fn x -> x * 2 end)
      [2, 4, 6]

      iex> Enum.sum(1..3)
      6

      iex> map = %{"a" => 1, "b" => 2}
      iex> Enum.map(map, fn {k, v} -> {k, v * 2} end)
      [{"a", 2}, {"b", 4}]

  Many other enumerables exist in the language, such as `MapSet`s
  and the data type returned by `File.stream!/3` which allows a file to be
  traversed as if it was an enumerable.

  For a general overview of all functions in the `Enum` module, see
  [the `Enum` cheatsheet](enum-cheat.cheatmd).

  The functions in this module work in linear time. This means that, the
  time it takes to perform an operation grows at the same rate as the length
  of the enumerable. This is expected on operations such as `Enum.map/2`.
  After all, if we want to traverse every element on a list, the longer the
  list, the more elements we need to traverse, and the longer it will take.

  This linear behavior should also be expected on operations like `count/1`,
  `member?/2`, `at/2` and similar. While Elixir does allow data types to
  provide performant variants for such operations, you should not expect it
  to always be available, since the `Enum` module is meant to work with a
  large variety of data types and not all data types can provide optimized
  behavior.

  Finally, note the functions in the `Enum` module are eager: they will
  traverse the enumerable as soon as they are invoked. This is particularly
  dangerous when working with infinite enumerables. In such cases, you should
  use the `Stream` module, which allows you to lazily express computations,
  without traversing collections, and work with possibly infinite collections.
  See the `Stream` module for examples and documentation.
  """

  @compile :inline_list_funcs

  @type t :: Enumerable.t()
  @type acc :: any
  @type element :: any

  @typedoc "Zero-based index. It can also be a negative integer."
  @type index :: integer

  @type default :: any

  require Stream.Reducers, as: R

  defmacrop skip(acc) do
    acc
  end

  defmacrop next(_, entry, acc) do
    quote(do: [unquote(entry) | unquote(acc)])
  end

  defmacrop acc(head, state, _) do
    quote(do: {unquote(head), unquote(state)})
  end

  defmacrop next_with_acc(_, entry, head, state, _) do
    quote do
      {[unquote(entry) | unquote(head)], unquote(state)}
    end
  end

  @doc """
  Returns `true` if all elements in `enumerable` are truthy.

  When an element has a falsy value (`false` or `nil`) iteration stops immediately
  and `false` is returned. In all other cases `true` is returned.

  ## Examples

      iex> Enum.all?([1, 2, 3])
      true

      iex> Enum.all?([1, nil, 3])
      false

      iex> Enum.all?([])
      true

  """
  @spec all?(t) :: boolean
  def all?(enumerable) when is_list(enumerable) do
    all_list(enumerable)
  end

  def all?(enumerable) do
    Enumerable.reduce(enumerable, {:cont, true}, fn entry, _ ->
      if entry, do: {:cont, true}, else: {:halt, false}
    end)
    |> elem(1)
  end

  @doc """
  Returns `true` if `fun.(element)` is truthy for all elements in `enumerable`.

  Iterates over `enumerable` and invokes `fun` on each element. If `fun` ever
  returns a falsy value (`false` or `nil`), iteration stops immediately and
  `false` is returned. Otherwise, `true` is returned.

  ## Examples

      iex> Enum.all?([2, 4, 6], fn x -> rem(x, 2) == 0 end)
      true

      iex> Enum.all?([2, 3, 4], fn x -> rem(x, 2) == 0 end)
      false

      iex> Enum.all?([], fn _ -> nil end)
      true

  As the last example shows, `Enum.all?/2` returns `true` if `enumerable` is
  empty, regardless of `fun`. In an empty enumerable there is no element for
  which `fun` returns a falsy value, so the result must be `true`. This is a
  well-defined logical argument for empty collections.

  """
  @spec all?(t, (element -> as_boolean(term))) :: boolean
  def all?(enumerable, fun) when is_list(enumerable) do
    predicate_list(enumerable, true, fun)
  end

  def all?(first..last//step, fun) do
    predicate_range(first, last, step, true, fun)
  end

  def all?(enumerable, fun) do
    Enumerable.reduce(enumerable, {:cont, true}, fn entry, _ ->
      if fun.(entry), do: {:cont, true}, else: {:halt, false}
    end)
    |> elem(1)
  end

  @doc """
  Returns `true` if at least one element in `enumerable` is truthy.

  When an element has a truthy value (neither `false` nor `nil`) iteration stops
  immediately and `true` is returned. In all other cases `false` is returned.

  ## Examples

      iex> Enum.any?([false, false, false])
      false

      iex> Enum.any?([false, true, false])
      true

      iex> Enum.any?([])
      false

  """
  @spec any?(t) :: boolean
  def any?(enumerable) when is_list(enumerable) do
    any_list(enumerable)
  end

  def any?(enumerable) do
    Enumerable.reduce(enumerable, {:cont, false}, fn entry, _ ->
      if entry, do: {:halt, true}, else: {:cont, false}
    end)
    |> elem(1)
  end

  @doc """
  Returns `true` if `fun.(element)` is truthy for at least one element in `enumerable`.

  Iterates over the `enumerable` and invokes `fun` on each element. When an invocation
  of `fun` returns a truthy value (neither `false` nor `nil`) iteration stops
  immediately and `true` is returned. In all other cases `false` is returned.

  ## Examples

      iex> Enum.any?([2, 4, 6], fn x -> rem(x, 2) == 1 end)
      false

      iex> Enum.any?([2, 3, 4], fn x -> rem(x, 2) == 1 end)
      true

      iex> Enum.any?([], fn x -> x > 0 end)
      false

  """
  @spec any?(t, (element -> as_boolean(term))) :: boolean
  def any?(enumerable, fun) when is_list(enumerable) do
    predicate_list(enumerable, false, fun)
  end

  def any?(first..last//step, fun) do
    predicate_range(first, last, step, false, fun)
  end

  def any?(enumerable, fun) do
    Enumerable.reduce(enumerable, {:cont, false}, fn entry, _ ->
      if fun.(entry), do: {:halt, true}, else: {:cont, false}
    end)
    |> elem(1)
  end

  @doc """
  Finds the element at the given `index` (zero-based).

  Returns `default` if `index` is out of bounds.

  A negative `index` can be passed, which means the `enumerable` is
  enumerated once and the `index` is counted from the end (for example,
  `-1` finds the last element).

  ## Examples

      iex> Enum.at([2, 4, 6], 0)
      2

      iex> Enum.at([2, 4, 6], 2)
      6

      iex> Enum.at([2, 4, 6], 4)
      nil

      iex> Enum.at([2, 4, 6], 4, :none)
      :none

  """
  @spec at(t, index, default) :: element | default
  def at(enumerable, index, default \\ nil) when is_integer(index) do
    case slice_forward(enumerable, index, 1, 1) do
      [value] -> value
      [] -> default
    end
  end

  @doc false
  @deprecated "Use Enum.chunk_every/2 instead"
  def chunk(enumerable, count), do: chunk(enumerable, count, count, nil)

  @doc false
  @deprecated "Use Enum.chunk_every/3 instead"
  def chunk(enum, n, step) do
    chunk_every(enum, n, step, :discard)
  end

  @doc false
  @deprecated "Use Enum.chunk_every/4 instead"
  def chunk(enumerable, count, step, leftover) do
    chunk_every(enumerable, count, step, leftover || :discard)
  end

  @doc """
  Shortcut to `chunk_every(enumerable, count, count)`.
  """
  @doc since: "1.5.0"
  @spec chunk_every(t, pos_integer) :: [list]
  def chunk_every(enumerable, count), do: chunk_every(enumerable, count, count, [])

  @doc """
  Returns list of lists containing `count` elements each, where
  each new chunk starts `step` elements into the `enumerable`.

  `step` is optional and, if not passed, defaults to `count`, i.e.
  chunks do not overlap. Chunking will stop as soon as the collection
  ends or when we emit an incomplete chunk.

  If the last chunk does not have `count` elements to fill the chunk,
  elements are taken from `leftover` to fill in the chunk. If `leftover`
  does not have enough elements to fill the chunk, then a partial chunk
  is returned with less than `count` elements.

  If `:discard` is given in `leftover`, the last chunk is discarded
  unless it has exactly `count` elements.

  ## Examples

      iex> Enum.chunk_every([1, 2, 3, 4, 5, 6], 2)
      [[1, 2], [3, 4], [5, 6]]

      iex> Enum.chunk_every([1, 2, 3, 4, 5, 6], 3, 2, :discard)
      [[1, 2, 3], [3, 4, 5]]

      iex> Enum.chunk_every([1, 2, 3, 4, 5, 6], 3, 2, [7])
      [[1, 2, 3], [3, 4, 5], [5, 6, 7]]

      iex> Enum.chunk_every([1, 2, 3, 4], 3, 3, [])
      [[1, 2, 3], [4]]

      iex> Enum.chunk_every([1, 2, 3, 4], 10)
      [[1, 2, 3, 4]]

      iex> Enum.chunk_every([1, 2, 3, 4, 5], 2, 3, [])
      [[1, 2], [4, 5]]

      iex> Enum.chunk_every([1, 2, 3, 4], 3, 3, Stream.cycle([0]))
      [[1, 2, 3], [4, 0, 0]]

  """
  @doc since: "1.5.0"
  @spec chunk_every(t, pos_integer, pos_integer, t | :discard) :: [list]
  def chunk_every(enumerable, count, step, leftover \\ [])
      when is_integer(count) and count > 0 and is_integer(step) and step > 0 do
    R.chunk_every(&chunk_while/4, enumerable, count, step, leftover)
  end

  @doc """
  Chunks the `enumerable` with fine grained control when every chunk is emitted.

  `chunk_fun` receives the current element and the accumulator and must return:

    * `{:cont, chunk, acc}` to emit a chunk and continue with the accumulator
    * `{:cont, acc}` to not emit any chunk and continue with the accumulator
    * `{:halt, acc}` to halt chunking over the `enumerable`.

  `after_fun` is invoked with the final accumulator when iteration is
  finished (or `halt`ed) to handle any trailing elements that were returned
  as part of an accumulator, but were not emitted as a chunk by `chunk_fun`.
  It must return:

    * `{:cont, chunk, acc}` to emit a chunk. The chunk will be appended to the
      list of already emitted chunks.
    * `{:cont, acc}` to not emit a chunk

  The `acc` in `after_fun` is required in order to mirror the tuple format
  from `chunk_fun` but it will be discarded since the traversal is complete.

  Returns a list of emitted chunks.

  ## Examples

      iex> chunk_fun = fn element, acc ->
      ...>   if rem(element, 2) == 0 do
      ...>     {:cont, Enum.reverse([element | acc]), []}
      ...>   else
      ...>     {:cont, [element | acc]}
      ...>   end
      ...> end
      iex> after_fun = fn
      ...>   [] -> {:cont, []}
      ...>   acc -> {:cont, Enum.reverse(acc), []}
      ...> end
      iex> Enum.chunk_while(1..10, [], chunk_fun, after_fun)
      [[1, 2], [3, 4], [5, 6], [7, 8], [9, 10]]
      iex> Enum.chunk_while([1, 2, 3, 5, 7], [], chunk_fun, after_fun)
      [[1, 2], [3, 5, 7]]

  """
  @doc since: "1.5.0"
  @spec chunk_while(
          t,
          acc,
          (element, acc -> {:cont, chunk, acc} | {:cont, acc} | {:halt, acc}),
          (acc -> {:cont, chunk, acc} | {:cont, acc})
        ) :: Enumerable.t()
        when chunk: any
  def chunk_while(enumerable, acc, chunk_fun, after_fun) do
    {_, {res, acc}} =
      Enumerable.reduce(enumerable, {:cont, {[], acc}}, fn entry, {buffer, acc} ->
        case chunk_fun.(entry, acc) do
          {:cont, chunk, acc} -> {:cont, {[chunk | buffer], acc}}
          {:cont, acc} -> {:cont, {buffer, acc}}
          {:halt, acc} -> {:halt, {buffer, acc}}
        end
      end)

    case after_fun.(acc) do
      {:cont, _acc} -> :lists.reverse(res)
      {:cont, chunk, _acc} -> :lists.reverse([chunk | res])
    end
  end

  @doc """
  Splits enumerable on every element for which `fun` returns a new
  value.

  Returns a list of lists.

  ## Examples

      iex> Enum.chunk_by([1, 2, 2, 3, 4, 4, 6, 7, 7], &(rem(&1, 2) == 1))
      [[1], [2, 2], [3], [4, 4, 6], [7, 7]]

  """
  @spec chunk_by(t, (element -> any)) :: [list]
  def chunk_by(enumerable, fun) do
    R.chunk_by(&chunk_while/4, enumerable, fun)
  end

  @doc """
  Given an enumerable of enumerables, concatenates the `enumerables` into
  a single list.

  ## Examples

      iex> Enum.concat([1..3, 4..6, 7..9])
      [1, 2, 3, 4, 5, 6, 7, 8, 9]

      iex> Enum.concat([[1, [2], 3], [4], [5, 6]])
      [1, [2], 3, 4, 5, 6]

  """
  @spec concat(t) :: t
  def concat(enumerables)

  def concat(list) when is_list(list) do
    concat_list(list)
  end

  def concat(enums) do
    concat_enum(enums)
  end

  @doc """
  Concatenates the enumerable on the `right` with the enumerable on the
  `left`.

  This function produces the same result as the `++/2` operator
  for lists.

  ## Examples

      iex> Enum.concat(1..3, 4..6)
      [1, 2, 3, 4, 5, 6]

      iex> Enum.concat([1, 2, 3], [4, 5, 6])
      [1, 2, 3, 4, 5, 6]

  """
  @spec concat(t, t) :: t
  def concat(left, right) when is_list(left) and is_list(right) do
    left ++ right
  end

  def concat(left, right) do
    concat_enum([left, right])
  end

  @doc """
  Returns the size of the `enumerable`.

  ## Examples

      iex> Enum.count([1, 2, 3])
      3

  """
  @spec count(t) :: non_neg_integer
  def count(enumerable) when is_list(enumerable) do
    length(enumerable)
  end

  def count(enumerable) do
    case Enumerable.count(enumerable) do
      {:ok, value} when is_integer(value) ->
        value

      {:error, module} ->
        enumerable |> module.reduce({:cont, 0}, fn _, acc -> {:cont, acc + 1} end) |> elem(1)
    end
  end

  @doc """
  Returns the count of elements in the `enumerable` for which `fun` returns
  a truthy value.

  ## Examples

      iex> Enum.count([1, 2, 3, 4, 5], fn x -> rem(x, 2) == 0 end)
      2

  """
  @spec count(t, (element -> as_boolean(term))) :: non_neg_integer
  def count(enumerable, fun) do
    reduce(enumerable, 0, fn entry, acc ->
      if(fun.(entry), do: acc + 1, else: acc)
    end)
  end

  @doc """
  Counts the enumerable stopping at `limit`.

  This is useful for checking certain properties of the count of an enumerable
  without having to actually count the entire enumerable. For example, if you
  wanted to check that the count was exactly, at least, or more than a value.

  If the enumerable implements `c:Enumerable.count/1`, the enumerable is
  not traversed and we return the lower of the two numbers. To force
  enumeration, use `count_until/3` with `fn _ -> true end` as the second
  argument.

  ## Examples

      iex> Enum.count_until(1..20, 5)
      5
      iex> Enum.count_until(1..20, 50)
      20
      iex> Enum.count_until(1..10, 10) == 10 # At least 10
      true
      iex> Enum.count_until(1..11, 10 + 1) > 10 # More than 10
      true
      iex> Enum.count_until(1..5, 10) < 10 # Less than 10
      true
      iex> Enum.count_until(1..10, 10 + 1) == 10 # Exactly ten
      true

  """
  @doc since: "1.12.0"
  @spec count_until(t, pos_integer) :: non_neg_integer
  def count_until(enumerable, limit) when is_integer(limit) and limit > 0 do
    case enumerable do
      list when is_list(list) -> count_until_list(list, limit, 0)
      _ -> count_until_enum(enumerable, limit)
    end
  end

  def count_until(_enumerable, limit) when is_integer(limit) do
    raise ArgumentError, "expected limit to be greater than 0, got: #{limit}"
  end

  @doc """
  Counts the elements in the enumerable for which `fun` returns a truthy value, stopping at `limit`.

  See `count/2` and `count_until/2` for more information.

  ## Examples

      iex> Enum.count_until(1..20, fn x -> rem(x, 2) == 0 end, 7)
      7
      iex> Enum.count_until(1..20, fn x -> rem(x, 2) == 0 end, 11)
      10
  """
  @doc since: "1.12.0"
  @spec count_until(t, (element -> as_boolean(term)), pos_integer) :: non_neg_integer
  def count_until(enumerable, fun, limit) when is_integer(limit) and limit > 0 do
    case enumerable do
      list when is_list(list) -> count_until_list(list, fun, limit, 0)
      _ -> count_until_enum(enumerable, fun, limit)
    end
  end

  def count_until(_enumerable, _fun, limit) when is_integer(limit) do
    raise ArgumentError, "expected limit to be greater than 0, got: #{limit}"
  end

  @doc """
  Enumerates the `enumerable`, returning a list where all consecutive
  duplicate elements are collapsed to a single element.

  Elements are compared using `===/2`.

  If you want to remove all duplicate elements, regardless of order,
  see `uniq/1`.

  ## Examples

      iex> Enum.dedup([1, 2, 3, 3, 2, 1])
      [1, 2, 3, 2, 1]

      iex> Enum.dedup([1, 1, 2, 2.0, :three, :three])
      [1, 2, 2.0, :three]

  """
  @spec dedup(t) :: list
  def dedup(enumerable) when is_list(enumerable) do
    dedup_list(enumerable, []) |> :lists.reverse()
  end

  def dedup(enumerable) do
    reduce(enumerable, [], fn x, acc ->
      case acc do
        [^x | _] -> acc
        _ -> [x | acc]
      end
    end)
    |> :lists.reverse()
  end

  @doc """
  Enumerates the `enumerable`, returning a list where all consecutive
  duplicate elements are collapsed to a single element.

  The function `fun` maps every element to a term which is used to
  determine if two elements are duplicates.

  ## Examples

      iex> Enum.dedup_by([{1, :a}, {2, :b}, {2, :c}, {1, :a}], fn {x, _} -> x end)
      [{1, :a}, {2, :b}, {1, :a}]

      iex> Enum.dedup_by([5, 1, 2, 3, 2, 1], fn x -> x > 2 end)
      [5, 1, 3, 2]

  """
  @spec dedup_by(t, (element -> term)) :: list
  def dedup_by(enumerable, fun) do
    {list, _} = reduce(enumerable, {[], []}, R.dedup(fun))
    :lists.reverse(list)
  end

  @doc """
  Drops the `amount` of elements from the `enumerable`.

  If a negative `amount` is given, the `amount` of last values will be dropped.
  The `enumerable` will be enumerated once to retrieve the proper index and
  the remaining calculation is performed from the end.

  ## Examples

      iex> Enum.drop([1, 2, 3], 2)
      [3]

      iex> Enum.drop([1, 2, 3], 10)
      []

      iex> Enum.drop([1, 2, 3], 0)
      [1, 2, 3]

      iex> Enum.drop([1, 2, 3], -1)
      [1, 2]

  """
  @spec drop(t, integer) :: list
  def drop(enumerable, amount)
      when is_list(enumerable) and is_integer(amount) and amount >= 0 do
    drop_list(enumerable, amount)
  end

  def drop(enumerable, 0) do
    to_list(enumerable)
  end

  def drop(enumerable, amount) when is_integer(amount) and amount > 0 do
    {result, _} = reduce(enumerable, {[], amount}, R.drop())
    if is_list(result), do: :lists.reverse(result), else: []
  end

  def drop(enumerable, amount) when is_integer(amount) and amount < 0 do
    {count, fun} = slice_count_and_fun(enumerable, 1)
    amount = Kernel.min(amount + count, count)

    if amount > 0 do
      fun.(0, amount, 1)
    else
      []
    end
  end

  @doc """
  Returns a list of every `nth` element in the `enumerable` dropped,
  starting with the first element.

  The first element is always dropped, unless `nth` is 0.

  The second argument specifying every `nth` element must be a non-negative
  integer.

  ## Examples

      iex> Enum.drop_every(1..10, 2)
      [2, 4, 6, 8, 10]

      iex> Enum.drop_every(1..10, 0)
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

      iex> Enum.drop_every([1, 2, 3], 1)
      []

  """
  @spec drop_every(t, non_neg_integer) :: list
  def drop_every(enumerable, nth)

  def drop_every(_enumerable, 1), do: []
  def drop_every(enumerable, 0), do: to_list(enumerable)
  def drop_every([], nth) when is_integer(nth), do: []

  def drop_every(enumerable, nth) when is_integer(nth) and nth > 1 do
    {res, _} = reduce(enumerable, {[], :first}, R.drop_every(nth))
    :lists.reverse(res)
  end

  @doc """
  Drops elements at the beginning of the `enumerable` while `fun` returns a
  truthy value.

  ## Examples

      iex> Enum.drop_while([1, 2, 3, 2, 1], fn x -> x < 3 end)
      [3, 2, 1]

  """
  @spec drop_while(t, (element -> as_boolean(term))) :: list
  def drop_while(enumerable, fun) when is_list(enumerable) do
    drop_while_list(enumerable, fun)
  end

  def drop_while(enumerable, fun) do
    {res, _} = reduce(enumerable, {[], true}, R.drop_while(fun))
    :lists.reverse(res)
  end

  @doc """
  Invokes the given `fun` for each element in the `enumerable`.

  Returns `:ok`.

  ## Examples

      Enum.each(["some", "example"], fn x -> IO.puts(x) end)
      some
      example
      #=> :ok

  """
  @spec each(t, (element -> any)) :: :ok
  def each(enumerable, fun) when is_list(enumerable) do
    :lists.foreach(fun, enumerable)
  end

  def each(enumerable, fun) do
    reduce(enumerable, nil, fn entry, _ ->
      fun.(entry)
      nil
    end)

    :ok
  end

  @doc """
  Determines if the `enumerable` is empty.

  Returns `true` if `enumerable` is empty, otherwise `false`.

  ## Examples

      iex> Enum.empty?([])
      true

      iex> Enum.empty?([1, 2, 3])
      false

  """
  @spec empty?(t) :: boolean
  def empty?(enumerable) when is_list(enumerable) do
    enumerable == []
  end

  def empty?(enumerable) do
    case Enumerable.slice(enumerable) do
      {:ok, value, _} ->
        value == 0

      {:error, module} ->
        enumerable
        |> module.reduce({:cont, true}, fn _, _ -> {:halt, false} end)
        |> elem(1)
    end
  end

  @doc """
  Finds the element at the given `index` (zero-based).

  Returns `{:ok, element}` if found, otherwise `:error`.

  A negative `index` can be passed, which means the `enumerable` is
  enumerated once and the `index` is counted from the end (for example,
  `-1` fetches the last element).

  ## Examples

      iex> Enum.fetch([2, 4, 6], 0)
      {:ok, 2}

      iex> Enum.fetch([2, 4, 6], -3)
      {:ok, 2}

      iex> Enum.fetch([2, 4, 6], 2)
      {:ok, 6}

      iex> Enum.fetch([2, 4, 6], 4)
      :error

  """
  @spec fetch(t, index) :: {:ok, element} | :error
  def fetch(enumerable, index) when is_integer(index) do
    case slice_forward(enumerable, index, 1, 1) do
      [value] -> {:ok, value}
      [] -> :error
    end
  end

  @doc """
  Finds the element at the given `index` (zero-based).

  Raises `OutOfBoundsError` if the given `index` is outside the range of
  the `enumerable`.

  ## Examples

      iex> Enum.fetch!([2, 4, 6], 0)
      2

      iex> Enum.fetch!([2, 4, 6], 2)
      6

      iex> Enum.fetch!([2, 4, 6], 4)
      ** (Enum.OutOfBoundsError) out of bounds error at position 4 when traversing enumerable [2, 4, 6]

  """
  @spec fetch!(t, index) :: element
  def fetch!(enumerable, index) when is_integer(index) do
    case slice_forward(enumerable, index, 1, 1) do
      [value] -> value
      [] -> raise Enum.OutOfBoundsError, index: index, enumerable: enumerable
    end
  end

  @doc """
  Filters the `enumerable`, i.e. returns only those elements
  for which `fun` returns a truthy value.

  See also `reject/2` which discards all elements where the
  function returns a truthy value.

  ## Examples

      iex> Enum.filter([1, 2, 3], fn x -> rem(x, 2) == 0 end)
      [2]
      iex> Enum.filter(["apple", "pear", "banana"], fn fruit -> String.contains?(fruit, "a") end)
      ["apple", "pear", "banana"]
      iex> Enum.filter([4, 21, 24, 904], fn seconds -> seconds > 1000 end)
      []

  Keep in mind that `filter` is not capable of filtering and
  transforming an element at the same time. If you would like
  to do so, consider using `flat_map/2`. For example, if you
  want to convert all strings that represent an integer and
  discard the invalid one in one pass:

      strings = ["1234", "abc", "12ab"]

      Enum.flat_map(strings, fn string ->
        case Integer.parse(string) do
          # transform to integer
          {int, _rest} -> [int]
          # skip the value
          :error -> []
        end
      end)

  """
  @spec filter(t, (element -> as_boolean(term))) :: list
  def filter(enumerable, fun) when is_list(enumerable) do
    filter_list(enumerable, fun)
  end

  def filter(enumerable, fun) do
    reduce(enumerable, [], R.filter(fun)) |> :lists.reverse()
  end

  @doc false
  @deprecated "Use Enum.filter/2 + Enum.map/2 or for comprehensions instead"
  def filter_map(enumerable, filter, mapper) when is_list(enumerable) do
    for element <- enumerable, filter.(element), do: mapper.(element)
  end

  def filter_map(enumerable, filter, mapper) do
    enumerable
    |> reduce([], R.filter_map(filter, mapper))
    |> :lists.reverse()
  end

  @doc """
  Returns the first element for which `fun` returns a truthy value.
  If no such element is found, returns `default`.

  ## Examples

      iex> Enum.find([2, 3, 4], fn x -> rem(x, 2) == 1 end)
      3

      iex> Enum.find([2, 4, 6], fn x -> rem(x, 2) == 1 end)
      nil
      iex> Enum.find([2, 4, 6], 0, fn x -> rem(x, 2) == 1 end)
      0

  """
  @spec find(t, default, (element -> any)) :: element | default
  def find(enumerable, default \\ nil, fun)

  def find(enumerable, default, fun) when is_list(enumerable) do
    find_list(enumerable, default, fun)
  end

  def find(enumerable, default, fun) do
    Enumerable.reduce(enumerable, {:cont, default}, fn entry, default ->
      if fun.(entry), do: {:halt, entry}, else: {:cont, default}
    end)
    |> elem(1)
  end

  @doc """
  Similar to `find/3`, but returns the index (zero-based)
  of the element instead of the element itself.

  ## Examples

      iex> Enum.find_index([2, 4, 6], fn x -> rem(x, 2) == 1 end)
      nil

      iex> Enum.find_index([2, 3, 4], fn x -> rem(x, 2) == 1 end)
      1

  """
  @spec find_index(t, (element -> any)) :: non_neg_integer | nil
  def find_index(enumerable, fun) when is_list(enumerable) do
    find_index_list(enumerable, 0, fun)
  end

  def find_index(enumerable, fun) do
    result =
      Enumerable.reduce(enumerable, {:cont, {:not_found, 0}}, fn entry, {_, index} ->
        if fun.(entry), do: {:halt, {:found, index}}, else: {:cont, {:not_found, index + 1}}
      end)

    case elem(result, 1) do
      {:found, index} -> index
      {:not_found, _} -> nil
    end
  end

  @doc """
  Similar to `find/3`, but returns the value of the function
  invocation instead of the element itself.

  The return value is considered to be found when the result is truthy
  (neither `nil` nor `false`).

  ## Examples

      iex> Enum.find_value([2, 3, 4], fn x ->
      ...>   if x > 2, do: x * x
      ...> end)
      9

      iex> Enum.find_value([2, 4, 6], fn x -> rem(x, 2) == 1 end)
      nil

      iex> Enum.find_value([2, 3, 4], fn x -> rem(x, 2) == 1 end)
      true

      iex> Enum.find_value([1, 2, 3], "no bools!", &is_boolean/1)
      "no bools!"

  """
  @spec find_value(t, default, (element -> found_value)) :: found_value | default
        when found_value: term
  def find_value(enumerable, default \\ nil, fun)

  def find_value(enumerable, default, fun) when is_list(enumerable) do
    find_value_list(enumerable, default, fun)
  end

  def find_value(enumerable, default, fun) do
    Enumerable.reduce(enumerable, {:cont, default}, fn entry, default ->
      fun_entry = fun.(entry)
      if fun_entry, do: {:halt, fun_entry}, else: {:cont, default}
    end)
    |> elem(1)
  end

  @doc """
  Maps the given `fun` over `enumerable` and flattens the result only one level deep.

  This function returns a new enumerable built by appending the result of invoking `fun`
  on each element of `enumerable` together; conceptually, this is similar to a
  combination of `map/2` and `concat/1`.

  ## Examples

      iex> Enum.flat_map([:a, :b, :c], fn x -> [x, x] end)
      [:a, :a, :b, :b, :c, :c]

      iex> Enum.flat_map([{1, 3}, {4, 6}], fn {x, y} -> x..y end)
      [1, 2, 3, 4, 5, 6]

      iex> Enum.flat_map([:a, :b, :c], fn x -> [[x]] end)
      [[:a], [:b], [:c]]

  This is frequently used to transform and filter in one pass, returning empty
  lists to exclude results:

      iex> Enum.flat_map([4, 0, 2, 0], fn x ->
      ...>   if x != 0, do: [1 / x], else: []
      ...> end)
      [0.25, 0.5]

  """
  @spec flat_map(t, (element -> t)) :: list
  def flat_map(enumerable, fun) when is_list(enumerable) do
    flat_map_list(enumerable, fun)
  end

  def flat_map(enumerable, fun) do
    reduce(enumerable, [], fn entry, acc ->
      case fun.(entry) do
        [] -> acc
        list when is_list(list) -> [list | acc]
        other -> [to_list(other) | acc]
      end
    end)
    |> flat_reverse([])
  end

  # the first clause is an optimization
  defp flat_reverse([[elem] | t], acc), do: flat_reverse(t, [elem | acc])
  defp flat_reverse([h | t], acc), do: flat_reverse(t, h ++ acc)
  defp flat_reverse([], acc), do: acc

  @doc """
  Maps and reduces an `enumerable`, flattening the results only one level deep.

  It expects an accumulator and a function that receives each enumerable
  element, and must return a tuple containing a new enumerable (often a list)
  with the new accumulator or a tuple with `:halt` as first element and
  the accumulator as second.

  Returns a 2-element tuple where the first element is the results flattened one level deep and
  the second element is the last accumulator.

  ## Examples

      iex> enumerable = 1..100
      iex> n = 3
      iex> Enum.flat_map_reduce(enumerable, 0, fn x, acc ->
      ...>   if acc < n, do: {[x], acc + 1}, else: {:halt, acc}
      ...> end)
      {[1, 2, 3], 3}

      iex> Enum.flat_map_reduce(1..5, 0, fn x, acc -> {[[x]], acc + x} end)
      {[[1], [2], [3], [4], [5]], 15}

  """
  @spec flat_map_reduce(t, acc, fun) :: {[any], acc}
        when fun: (element, acc -> {t, acc} | {:halt, acc})
  def flat_map_reduce(enumerable, acc, fun) do
    {_, {list, acc}} =
      Enumerable.reduce(enumerable, {:cont, {[], acc}}, fn entry, {list, acc} ->
        case fun.(entry, acc) do
          {:halt, acc} ->
            {:halt, {list, acc}}

          {[], acc} ->
            {:cont, {list, acc}}

          {[entry], acc} ->
            {:cont, {[entry | list], acc}}

          {entries, acc} ->
            {:cont, {reduce(entries, list, &[&1 | &2]), acc}}
        end
      end)

    {:lists.reverse(list), acc}
  end

  @doc """
  Returns a map with keys as unique elements of `enumerable` and values
  as the count of every element.

  ## Examples

      iex> Enum.frequencies(~w{ant buffalo ant ant buffalo dingo})
      %{"ant" => 3, "buffalo" => 2, "dingo" => 1}

  """
  @doc since: "1.10.0"
  @spec frequencies(t) :: map
  def frequencies(enumerable) do
    reduce(enumerable, %{}, fn key, acc ->
      case acc do
        %{^key => value} -> %{acc | key => value + 1}
        %{} -> Map.put(acc, key, 1)
      end
    end)
  end

  @doc """
  Returns a map with keys as unique elements given by `key_fun` and values
  as the count of every element.

  ## Examples

      iex> Enum.frequencies_by(~w{aa aA bb cc}, &String.downcase/1)
      %{"aa" => 2, "bb" => 1, "cc" => 1}

      iex> Enum.frequencies_by(~w{aaa aA bbb cc c}, &String.length/1)
      %{3 => 2, 2 => 2, 1 => 1}

  """
  @doc since: "1.10.0"
  @spec frequencies_by(t, (element -> any)) :: map
  def frequencies_by(enumerable, key_fun) when is_function(key_fun) do
    reduce(enumerable, %{}, fn entry, acc ->
      key = key_fun.(entry)

      case acc do
        %{^key => value} -> %{acc | key => value + 1}
        %{} -> Map.put(acc, key, 1)
      end
    end)
  end

  @doc """
  Splits the `enumerable` into groups based on `key_fun`.

  The result is a map where each key is given by `key_fun`
  and each value is a list of elements given by `value_fun`.
  The order of elements within each list is preserved from the `enumerable`.
  However, like all maps, the resulting map is unordered.

  ## Examples

      iex> Enum.group_by(~w{ant buffalo cat dingo}, &String.length/1)
      %{3 => ["ant", "cat"], 5 => ["dingo"], 7 => ["buffalo"]}

      iex> Enum.group_by(~w{ant buffalo cat dingo}, &String.length/1, &String.first/1)
      %{3 => ["a", "c"], 5 => ["d"], 7 => ["b"]}

  The key can be any Elixir value. For example, you may use a tuple
  to group by multiple keys:

      iex> collection = [
      ...>   %{id: 1, lang: "Elixir", seq: 1},
      ...>   %{id: 1, lang: "Java", seq: 1},
      ...>   %{id: 1, lang: "Ruby", seq: 2},
      ...>   %{id: 2, lang: "Python", seq: 1},
      ...>   %{id: 2, lang: "C#", seq: 2},
      ...>   %{id: 2, lang: "Haskell", seq: 2},
      ...> ]
      iex> Enum.group_by(collection, &{&1.id, &1.seq})
      %{
        {1, 1} => [%{id: 1, lang: "Elixir", seq: 1}, %{id: 1, lang: "Java", seq: 1}],
        {1, 2} => [%{id: 1, lang: "Ruby", seq: 2}],
        {2, 1} => [%{id: 2, lang: "Python", seq: 1}],
        {2, 2} => [%{id: 2, lang: "C#", seq: 2}, %{id: 2, lang: "Haskell", seq: 2}]
      }
      iex> Enum.group_by(collection, &{&1.id, &1.seq}, &{&1.id, &1.lang})
      %{
        {1, 1} => [{1, "Elixir"}, {1, "Java"}],
        {1, 2} => [{1, "Ruby"}],
        {2, 1} => [{2, "Python"}],
        {2, 2} => [{2, "C#"}, {2, "Haskell"}]
      }

  """
  @spec group_by(t, (element -> any), (element -> any)) :: map
  def group_by(enumerable, key_fun, value_fun \\ fn x -> x end)

  def group_by(enumerable, key_fun, value_fun) when is_function(key_fun) do
    reduce(reverse(enumerable), %{}, fn entry, acc ->
      key = key_fun.(entry)
      value = value_fun.(entry)

      case acc do
        %{^key => existing} -> %{acc | key => [value | existing]}
        %{} -> Map.put(acc, key, [value])
      end
    end)
  end

  def group_by(enumerable, dict, fun) do
    IO.warn(
      "Enum.group_by/3 with a map/dictionary as second element is deprecated. " <>
        "A map is used by default and it is no longer required to pass one to this function"
    )

    # Avoid warnings about Dict
    dict_module = String.to_atom("Dict")

    reduce(reverse(enumerable), dict, fn entry, categories ->
      dict_module.update(categories, fun.(entry), [entry], &[entry | &1])
    end)
  end

  @doc """
  Intersperses `separator` between each element of the enumeration.

  ## Examples

      iex> Enum.intersperse([1, 2, 3], 0)
      [1, 0, 2, 0, 3]

      iex> Enum.intersperse([1], 0)
      [1]

      iex> Enum.intersperse([], 0)
      []

  """
  @spec intersperse(t, element) :: list
  def intersperse(enumerable, separator) when is_list(enumerable) do
    case enumerable do
      [] -> []
      list -> intersperse_non_empty_list(list, separator)
    end
  end

  def intersperse(enumerable, separator) do
    list =
      enumerable
      |> reduce([], fn x, acc -> [x, separator | acc] end)
      |> :lists.reverse()

    # Head is a superfluous separator
    case list do
      [] -> []
      [_ | t] -> t
    end
  end

  @doc """
  Inserts the given `enumerable` into a `collectable`.

  Note that passing a non-empty list as the `collectable` is deprecated.
  If you're collecting into a non-empty keyword list, consider using
  `Keyword.merge(collectable, Enum.to_list(enumerable))`. If you're collecting
  into a non-empty list, consider something like `Enum.to_list(enumerable) ++ collectable`.

  ## Examples

      iex> Enum.into([1, 2], [])
      [1, 2]

      iex> Enum.into([a: 1, b: 2], %{})
      %{a: 1, b: 2}

      iex> Enum.into(%{a: 1}, %{b: 2})
      %{a: 1, b: 2}

      iex> Enum.into([a: 1, a: 2], %{})
      %{a: 2}

      iex> Enum.into([a: 2], %{a: 1, b: 3})
      %{a: 2, b: 3}

  """
  @spec into(Enumerable.t(), Collectable.t()) :: Collectable.t()
  def into(enumerable, collectable)

  def into(enumerable, []) do
    to_list(enumerable)
  end

  def into(enumerable, collectable) when is_struct(collectable, MapSet) do
    if MapSet.size(collectable) == 0 do
      MapSet.new(enumerable)
    else
      MapSet.new(enumerable) |> MapSet.union(collectable)
    end
  end

  def into(%_{} = enumerable, collectable) do
    into_protocol(enumerable, collectable)
  end

  def into(enumerable, %_{} = collectable) do
    into_protocol(enumerable, collectable)
  end

  def into(enumerable, %{} = collectable) do
    if map_size(collectable) == 0 do
      into_map(enumerable)
    else
      into_map(enumerable, collectable)
    end
  end

  def into(enumerable, collectable) do
    into_protocol(enumerable, collectable)
  end

  defp into_map(%{} = enumerable), do: enumerable
  defp into_map(enumerable) when is_list(enumerable), do: :maps.from_list(enumerable)
  defp into_map(enumerable), do: enumerable |> Enum.to_list() |> :maps.from_list()

  defp into_map(%{} = enumerable, collectable), do: Map.merge(collectable, enumerable)

  defp into_map(enumerable, collectable) when is_list(enumerable),
    do: Map.merge(collectable, :maps.from_list(enumerable))

  defp into_map(enumerable, collectable),
    do: reduce(enumerable, collectable, fn {key, val}, acc -> Map.put(acc, key, val) end)

  defp into_protocol(enumerable, collectable) do
    {initial, fun} = Collectable.into(collectable)

    try do
      reduce_into_protocol(enumerable, initial, fun)
    catch
      kind, reason ->
        fun.(initial, :halt)
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      acc -> fun.(acc, :done)
    end
  end

  defp reduce_into_protocol(enumerable, initial, fun) when is_list(enumerable) do
    :lists.foldl(fn x, acc -> fun.(acc, {:cont, x}) end, initial, enumerable)
  end

  defp reduce_into_protocol(enumerable, initial, fun) do
    enumerable
    |> Enumerable.reduce({:cont, initial}, fn x, acc ->
      {:cont, fun.(acc, {:cont, x})}
    end)
    |> elem(1)
  end

  @doc """
  Inserts the given `enumerable` into a `collectable` according to the
  transformation function.

  ## Examples

      iex> Enum.into([1, 2, 3], [], fn x -> x * 3 end)
      [3, 6, 9]

      iex> Enum.into(%{a: 1, b: 2}, %{c: 3}, fn {k, v} -> {k, v * 2} end)
      %{a: 2, b: 4, c: 3}

  """
  @spec into(Enumerable.t(), Collectable.t(), (term -> term)) :: Collectable.t()
  def into(enumerable, [], transform) do
    map(enumerable, transform)
  end

  def into(enumerable, collectable, transform) when is_struct(collectable, MapSet) do
    if MapSet.size(collectable) == 0 do
      MapSet.new(enumerable, transform)
    else
      MapSet.new(enumerable, transform) |> MapSet.union(collectable)
    end
  end

  def into(enumerable, %_{} = collectable, transform) do
    into_protocol(enumerable, collectable, transform)
  end

  def into(enumerable, %{} = collectable, transform) do
    if map_size(collectable) == 0 do
      enumerable |> map(transform) |> :maps.from_list()
    else
      reduce(enumerable, collectable, fn entry, acc ->
        {key, val} = transform.(entry)
        Map.put(acc, key, val)
      end)
    end
  end

  def into(enumerable, collectable, transform) do
    into_protocol(enumerable, collectable, transform)
  end

  defp into_protocol(enumerable, collectable, transform) do
    {initial, fun} = Collectable.into(collectable)

    try do
      reduce_into_protocol(enumerable, initial, transform, fun)
    catch
      kind, reason ->
        fun.(initial, :halt)
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      acc -> fun.(acc, :done)
    end
  end

  defp reduce_into_protocol(enumerable, initial, transform, fun) when is_list(enumerable) do
    :lists.foldl(fn x, acc -> fun.(acc, {:cont, transform.(x)}) end, initial, enumerable)
  end

  defp reduce_into_protocol(enumerable, initial, transform, fun) do
    enumerable
    |> Enumerable.reduce({:cont, initial}, fn x, acc ->
      {:cont, fun.(acc, {:cont, transform.(x)})}
    end)
    |> elem(1)
  end

  @doc """
  Joins the given `enumerable` into a string using `joiner` as a
  separator.

  If `joiner` is not passed at all, it defaults to an empty string.

  All elements in the `enumerable` must be convertible to a string
  or be a binary, otherwise an error is raised.

  ## Examples

      iex> Enum.join([1, 2, 3])
      "123"

      iex> Enum.join([1, 2, 3], " = ")
      "1 = 2 = 3"

      iex> Enum.join([["a", "b"], ["c", "d", "e", ["f", "g"]], "h", "i"], " ")
      "ab cdefg h i"

  """
  @spec join(t, binary()) :: binary()
  def join(enumerable, joiner \\ "")

  def join(enumerable, "") do
    enumerable
    |> map(&entry_to_string(&1))
    |> IO.iodata_to_binary()
  end

  def join(enumerable, joiner) when is_list(enumerable) and is_binary(joiner) do
    join_list(enumerable, joiner)
  end

  def join(enumerable, joiner) whe
