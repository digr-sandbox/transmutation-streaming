# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

defmodule List do
  @moduledoc """
  Linked lists hold zero, one, or more elements in the chosen order.

  Lists in Elixir are specified between square brackets:

      iex> [1, "two", 3, :four]
      [1, "two", 3, :four]

  Two lists can be concatenated and subtracted using the
  `++/2` and `--/2` operators:

      iex> [1, 2, 3] ++ [4, 5, 6]
      [1, 2, 3, 4, 5, 6]
      iex> [1, true, 2, false, 3, true] -- [true, false]
      [1, 2, 3, true]

  An element can be prepended to a list using `|`:

      iex> new = 0
      iex> list = [1, 2, 3]
      iex> [new | list]
      [0, 1, 2, 3]

  Lists in Elixir are effectively linked lists, which means
  they are internally represented in pairs containing the
  head and the tail of a list:

      iex> [head | tail] = [1, 2, 3]
      iex> head
      1
      iex> tail
      [2, 3]

  Similarly, we could write the li
