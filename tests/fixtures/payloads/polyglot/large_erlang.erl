%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 1996-2025. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%
-module(lists).
-moduledoc """
List processing functions.

This module contains functions for list processing.

Unless otherwise stated, all functions assume that position numbering starts
at 1. That is, the first element of a list is at position 1.

Two terms `T1` and `T2` compare equal if `T1 == T2` evaluates to `true`. They
match if `T1 =:= T2` evaluates to `true`.

Whenever an _ordering function_{: #ordering_function } `F` is expected as
argument, it is assumed that the following properties hold of `F` for all x, y,
and z:

- If x `F` y and y `F` x, then x = y (`F` is antisymmetric).
- If x `F` y and y `F` z, then x `F` z (`F` is transitive).
- x `F` y or y `F` x (`F` is total).

An example of a typical ordering function is less than or equal to: `=</2`.
""".

-compile({no_auto_import,[max/2]}).
-compile({no_auto_import,[min/2]}).

%% BIFs (implemented in the runtime system).
-export([keyfind/3, keymember/3, keysearch/3, member/2, reverse/2]).

%% Miscellaneous list functions that don't take funs as
%% arguments. Please keep in alphabetical order.
-export([append/1, append/2, concat/1,
         delete/2, droplast/1, duplicate/2,
         enumerate/1, enumerate/2, enumerate/3,
         flatlength/1, flatten/1, flatten/2,
         join/2, last/1, min/1, max/1,
         nth/2, nthtail/2,
         prefix/2, reverse/1, seq/2, seq/3,
         split/2, sublist/2, sublist/3,
         subtract/2, suffix/2, sum/1,
         uniq/1, unzip/1, unzip3/1,
         zip/2, zip/3, zip3/3, zip3/4]).

%% Functions taking a list of tuples and a position within the tuple.
-export([keydelete/3, keyreplace/4, keymap/3,
         keytake/3, keystore/4]).

%% Sort functions that operate on list of tuples.
-export([keymerge/3, keysort/2, ukeymerge/3, ukeysort/2]).

%% Sort and merge functions.
-export([merge/1, merge/2, merge/3, merge3/3,
         sort/1, sort/2,
         umerge/1, umerge/2, umerge/3, umerge3/3,
         usort/1, usort/2]).

%% Functions that take fun arguments (high-order functions). Please
%% keep in alphabetical order.
-export([all/2, any/2, dropwhile/2,
         filter/2, filtermap/2, flatmap/2,
         foldl/3, foldr/3, foreach/2,
         map/2, mapfoldl/3, mapfoldr/3,
         partition/2, search/2,
         splitwith/2, takewhile/2, uniq/2,
         zipwith/3, zipwith/4, zipwith3/4, zipwith3/5]).

%% Undocumented old name for filtermap
-export([zf/2]).
-deprecated([{zf,2,"use filtermap/2 instead"}]).

%% Undocumented and unused merge functions for lists sorted in reverse
%% order. They are exported so that the fundamental building blocks
%% for the sort functions can be tested. (Removing them would save
%% very little because they are thin wrappers calling helper functions
%% used by the documented sort functions.)
-export([rkeymerge/3, rmerge/2, rmerge/3, rmerge3/3,
         rukeymerge/3, rumerge/2, rumerge/3, rumerge3/3]).

%% Shadowed by erl_bif_types: lists:keyfind/3
-doc """
Searches the list of tuples `TupleList` for a tuple whose `N`th element compares
equal to `Key`.

Returns `Tuple` if such a tuple is found; otherwise, returns `false`.

## Examples

```erlang
1> lists:keyfind(b, 1, [{a,10}, {b,20}, {c,30}]).
{b,20}
2> lists:keyfind(unknown, 1, [{a,10}, {b,20}, {c,30}]).
false
```
""".
-spec keyfind(Key, N, TupleList) -> Tuple | false when
      Key :: term(),
      N :: pos_integer(),
      TupleList :: [Tuple],
      Tuple :: tuple().

keyfind(_, _, _) ->
    erlang:nif_error(undef).

%% Shadowed by erl_bif_types: lists:keymember/3
-doc """
Returns `true` if `TupleList` contains a tuple whose `N`th element compares
equal to `Key`; otherwise, returns `false`.

## Examples

```erlang
1> lists:keymember(b, 1, [{a,10}, {b,20}, {c,30}]).
true
2> lists:keymember(unknown, 1, [{a,10}, {b,20}, {c,30}]).
false
```
""".
-spec keymember(Key, N, TupleList) -> boolean() when
      Key :: term(),
      N :: pos_integer(),
      TupleList :: [Tuple],
      Tuple :: tuple().

keymember(_, _, _) ->
    erlang:nif_error(undef).

%% Shadowed by erl_bif_types: lists:keysearch/3
-doc """
Searches the list of tuples `TupleList` for a tuple whose `N`th element compares
equal to `Key`.

Returns `{value, Tuple}` if such a tuple is found; otherwise, returns
`false`.

> #### Note {: .info }
>
> This function is retained for backward compatibility. Function `keyfind/3` is
> easier to use and more efficient.
""".
-spec keysearch(Key, N, TupleList) -> {value, Tuple} | false when
      Key :: term(),
      N :: pos_integer(),
      TupleList :: [Tuple],
      Tuple :: tuple().

keysearch(_, _, _) ->
    erlang:nif_error(undef).

%% Shadowed by erl_bif_types: lists:member/2
-doc """
Returns `true` if `Elem` matches some element of `List`; otherwise, returns `false`.

## Examples

```erlang
1> lists:member(2, [1,2,3]).
true
2> lists:member(nope, [1,2,3]).
false
```
""".
-spec member(Elem, List) -> boolean() when
      Elem :: T,
      List :: [T],
      T :: term().

member(_, _) ->
    erlang:nif_error(undef).

%% Shadowed by erl_bif_types: lists:reverse/2
-doc """
Returns a list containing the elements of `List1` in reverse order,
with tail `Tail` appended.

## Examples

```erlang
1> lists:reverse([1, 2, 3, 4], [a, b, c]).
[4,3,2,1,a,b,c]
```
""".
-spec reverse(List1, Tail) -> List2 when
      List1 :: [T],
      Tail :: term(),
      List2 :: [T],
      T :: term().

reverse(_, _) ->
    erlang:nif_error(undef).

%%% End of BIFs

-doc """
Returns a new list, `List3`, consisting of the elements of
`List1`, followed by the elements of `List2`.

## Examples

```erlang
1> lists:append("abc", "def").
"abcdef"
```

`lists:append(A, B)` is equivalent to `A ++ B`.
""".
-spec append(List1, List2) -> List3 when
      List1 :: [T],
      List2 :: [T],
      List3 :: [T],
      T :: term().

append(L1, L2) -> L1 ++ L2.

-doc """
Returns a list in which all sublists of `ListOfLists` have been concatenated.

## Examples

```erlang
1> lists:append([[1, 2, 3], [a, b], [4, 5, 6]]).
[1,2,3,a,b,4,5,6]
```
""".
-spec append(ListOfLists) -> List1 when
      ListOfLists :: [List],
      List :: [T],
      List1 :: [T],
      T :: term().

append([E]) -> E;
append([H|T]) -> H ++ append(T);
append([]) -> [].

-doc """
Returns a new list, `List3`, which is a copy of `List1` with the
following modification: for each element in `List2`, its first
occurrence in `List1` is removed.

## Examples

```erlang
1> lists:subtract("123212", "212").
"312"
```

`lists:subtract(A, B)` is equivalent to `A -- B`.
""".
-spec subtract(List1, List2) -> List3 when
      List1 :: [T],
      List2 :: [T],
      List3 :: [T],
      T :: term().

subtract(L1, L2) -> L1 -- L2.

-doc """
Returns a list containing the elements in `List1` in reverse order.

## Examples

```erlang
1> lists:reverse([1,2,3]).
[3,2,1]
```
""".
-spec reverse(List1) -> List2 when
      List1 :: [T],
      List2 :: [T],
      T :: term().

reverse([] = L) ->
    L;
reverse([_] = L) ->
    L;
reverse([A, B]) ->
    [B, A];
reverse([A, B | L]) ->
    lists:reverse(L, [B, A]).


-doc """
Returns the `N`th element of `List`.

## Examples

```erlang
1> lists:nth(3, [a, b, c, d, e]).
c
```
""".
-spec nth(N, List) -> Elem when
      N :: pos_integer(),
      List :: [T,...],
      Elem :: T,
      T :: term().

nth(1, [H|_]) -> H;
nth(N, [_|_]=L) when is_integer(N), N > 1 ->
    nth_1(N, L).

nth_1(1, [H|_]) -> H;
nth_1(N, [_|T]) ->
    nth_1(N - 1, T).

-doc """
Returns the `N`th tail of `List`, meaning the sublist of `List`
starting at `N+1` and continuing to the end of the list.

## Examples

```erlang
1> lists:nthtail(3, [a, b, c, d, e]).
[d,e]
2> tl(tl(tl([a, b, c, d, e]))).
[d,e]
3> lists:nthtail(0, [a, b, c, d, e]).
[a,b,c,d,e]
4> lists:nthtail(5, [a, b, c, d, e]).
[]
```
""".
-spec nthtail(N, List) -> Tail when
      N :: non_neg_integer(),
      List :: [T],
      Tail :: [T],
      T :: term().

nthtail(0, []) -> [];
nthtail(0, [_|_]=L) -> L;
nthtail(1, [_|T]) -> T;
nthtail(N, [_|_]=L) when is_integer(N), N > 1 ->
    nthtail_1(N, L).

nthtail_1(1, [_|T]) -> T;
nthtail_1(N, [_|T]) ->
    nthtail_1(N - 1, T).

-doc """
Returns `true` if `List1` is a prefix of `List2`; otherwise, returns `false`.

A prefix of a list is the first part of the list, starting from the
beginning and stopping at any point.

## Examples

```erlang
1> lists:prefix("abc", "abcdef").
true
2> lists:prefix("def", "abcdef").
false
3> lists:prefix([], "any list").
true
4> lists:prefix("abc", "abc").
true
```
""".
-spec prefix(List1, List2) -> boolean() when
      List1 :: [T],
      List2 :: [T],
      T :: term().

prefix([X|PreTail], [X|Tail]) ->
    prefix(PreTail, Tail);
prefix([], List) when is_list(List) -> true;
prefix([_|_], List) when is_list(List) -> false.

-doc """
Returns `true` if `List1` is a suffix of `List2`; otherwise, returns `false`.

A suffix of a list is the last part of the list, starting from any position
and going all the way to the end.

## Examples

```erlang
1> lists:suffix("abc", "abcdef").
false
2> lists:suffix("def", "abcdef").
true
3> lists:suffix([], "any list").
true
4> lists:suffix("abc", "abc").
true
```
""".
-spec suffix(List1, List2) -> boolean() when
      List1 :: [T],
      List2 :: [T],
      T :: term().

suffix(Suffix, List) ->
    Delta = length(List) - length(Suffix),
    Delta >= 0 andalso nthtail(Delta, List) =:= Suffix.

-doc """
Drops the last element of a `List`.

The list must be non-empty; otherwise, the function raises a
`function_clause` exception.

## Examples

```erlang
1> lists:droplast([1]).
[]
2> lists:droplast([1,2,3]).
[1,2]
3> lists:droplast([]).
** exception error: no function clause matching lists:droplast([])
```
""".
-doc(#{since => <<"OTP 17.0">>}).
-spec droplast(List) -> InitList when
      List :: [T, ...],
      InitList :: [T],
      T :: term().

%% This is the simple recursive implementation.
%% reverse(tl(reverse(L))) is faster on average,
%% but creates more garbage.
droplast([_T])  -> [];
droplast([H|T]) -> [H|droplast(T)].

-doc """
Returns the last element in `List`.

The list must be non-empty; otherwise, the function raises a
`function_clause` exception.

## Examples

```erlang
1> lists:last([1]).
1
2> lists:last([1,2,3]).
3
3> lists:last([]).
** exception error: no function clause matching lists:last([])
```
""".
-spec last(List) -> Last when
      List :: [T,...],
      Last :: T,
      T :: term().

last([E|Es]) -> last(E, Es).

last(_, [E|Es]) -> last(E, Es);
last(E, []) -> E.

-doc(#{equiv => seq(From, To, 1)}).
-spec seq(From, To) -> Seq when
      From :: integer(),
      To :: integer(),
      Seq :: [integer()].

seq(First, Last)
  when is_integer(First), is_integer(Last), First-1 =< Last ->
    seq_loop(Last-First+1, Last, []).

seq_loop(N, X, L) when N >= 4 ->
    seq_loop(N-4, X-4, [X-3,X-2,X-1,X|L]);
seq_loop(N, X, L) when N >= 2 ->
    seq_loop(N-2, X-2, [X-1,X|L]);
seq_loop(1, X, L) ->
    [X|L];
seq_loop(0, _, L) ->
     L.

-doc """
Returns a sequence of integers that starts with `From` and contains the
successive results of adding `Incr` to the previous element, until `To` is
reached or passed (in the latter case, `To` is not an element of the sequence).

`Incr` defaults to 1.

Failures:

- If `To < From - Incr` and `Incr > 0`.
- If `To > From - Incr` and `Incr < 0`.
- If `Incr =:= 0` and `From =/= To`.

The following equalities hold for all sequences:

```erlang
length(lists:seq(From, To)) =:= To - From + 1
length(lists:seq(From, To, Incr)) =:= (To - From + Incr) div Incr
```

## Examples

```erlang
1> lists:seq(1, 10).
[1,2,3,4,5,6,7,8,9,10]
2> lists:seq(1, 20, 3).
[1,4,7,10,13,16,19]
3> lists:seq(1, 0, 1).
[]
4> lists:seq(10, 6, 4).
[]
5> lists:seq(1, 1, 0).
[1]
```
""".
-spec seq(From, To, Incr) -> Seq when
      From :: integer(),
      To :: integer(),
      Incr :: integer(),
      Seq :: [integer()].

seq(First, Last, Inc)
    when is_integer(First), is_integer(Last), is_integer(Inc),
        (Inc > 0 andalso First - Inc =< Last) orelse
        (Inc < 0 andalso First - Inc >= Last) ->
    N = (Last - First + Inc) div Inc,
    seq_loop(N, Inc * (N - 1) + First, Inc, []);
seq(Same, Same, 0) when is_integer(Same) ->
    [Same];
seq(First, Last, Inc) ->
    error(badarg, [First, Last, Inc],
          [{error_info, #{module => erl_stdlib_errors}}]).

seq_loop(N, X, D, L) when N >= 4 ->
     Y = X-D, Z = Y-D, W = Z-D,
     seq_loop(N-4, W-D, D, [W,Z,Y,X|L]);
seq_loop(N, X, D, L) when N >= 2 ->
     Y = X-D,
     seq_loop(N-2, Y-D, D, [Y,X|L]);
seq_loop(1, X, _, L) ->
     [X|L];
seq_loop(0, _, _, L) ->
     L.

-doc """
Returns the sum of the elements in `List`.

## Examples

```erlang
1> lists:sum([]).
0
2> lists:sum([1,2,3]).
6
```
""".
-spec sum(List) -> number() when
      List :: [number()].

sum(L)          -> sum(L, 0).

sum([H|T], Sum) -> sum(T, Sum + H);
sum([], Sum)    -> Sum.

-doc """
Returns a list containing `N` copies of term `Elem`.

## Examples

```erlang
1> lists:duplicate(5, xx).
[xx,xx,xx,xx,xx]
```
""".
-spec duplicate(N, Elem) -> List when
      N :: non_neg_integer(),
      Elem :: T,
      List :: [T],
      T :: term().

duplicate(N, X) when is_integer(N), N >= 0 -> duplicate(N, X, []).

duplicate(0, _, L) -> L;
duplicate(N, X, L) -> duplicate(N-1, X, [X|L]).

-doc """
Returns the first element of `List` that compares less than or equal to all
other elements of `List`.

## Examples

```erlang
1> lists:min([17,19,7,55]).
7
2> lists:min([]).
** exception error: no function clause matching lists:min([])
```
""".
-spec min(List) -> Min when
      List :: [T,...],
      Min :: T,
      T :: term().

min([H|T]) -> min(T, H).

min([H|T], Min) when H < Min -> min(T, H);
min([_|T], Min)              -> min(T, Min);
min([],    Min)              -> Min. 

-doc """
Returns the first element of `List` that compares greater than or equal to all
other elements of `List`.

## Examples

```erlang
1> lists:max([17,19,7,55]).
55
2> lists:max([]).
** exception error: no function clause matching lists:max([])
```
""".
-spec max(List) -> Max when
      List :: [T,...],
      Max :: T,
      T :: term().

max([H|T]) -> max(T, H).

max([H|T], Max) when H > Max -> max(T, H);
max([_|T], Max)              -> max(T, Max);
max([],    Max)              -> Max.

-doc """
Returns the sublist of `List1` starting at `Start` and with no more than `Len`
elements.

It is not an error for `Start+Len` to exceed the length of the list.

## Examples

```erlang
1> lists:sublist([1,2,3,4], 2, 2).
[2,3]
2> lists:sublist([1,2,3,4], 2, 5).
[2,3,4]
3> lists:sublist([1,2,3,4], 5, 2).
[]
```
""".
-spec sublist(List1, Start, Len) -> List2 when
      List1 :: [T],
      List2 :: [T],
      Start :: pos_integer(),
      Len :: non_neg_integer(),
      T :: term().

sublist(List, 1, L) when is_list(List), is_integer(L), L >= 0 ->
    sublist(List, L);
sublist([], S, _L) when is_integer(S), S >= 2 ->
    [];
sublist([_H|T], S, L) when is_integer(S), S >= 2 ->
    sublist(T, S-1, L).

-doc """
Returns the sublist of `List1` starting at position 1 and with no more than `Len`
elements.

It is not an error for `Len` to exceed the length of the list, in which
case the whole list is returned.

## Examples

```erlang
1> lists:sublist([1,2,3,4,5], 2).
[1,2]
2> lists:sublist([1,2,3,4,5], 99).
[1,2,3,4,5]
```
""".
-spec sublist(List1, Len) -> List2 when
      List1 :: [T],
      List2 :: [T],
      Len :: non_neg_integer(),
      T :: term().

sublist(List, L) when is_integer(L), is_list(List) ->
    sublist_2(List, L).

sublist_2([H|T], L) when L > 0 ->
    [H|sublist_2(T, L-1)];
sublist_2(_, 0) ->
    [];
sublist_2(List, L) when is_list(List), L > 0 ->
    [].

-doc """
Returns a copy of `List1` where the first element matching `Elem` is removed, if
there is such an element.

## Examples

```erlang
1> lists:delete(b, [a,b,c]).
[a,c]
2> lists:delete(x, [a,b,c]).
[a,b,c]
```
""".
-spec delete(Elem, List1) -> List2 when
      Elem :: T,
      List1 :: [T],
      List2 :: [T],
      T :: term().

delete(Item, [Item|Rest]) -> Rest;
delete(Item, [H|Rest]) -> 
    [H|delete(Item, Rest)];
delete(_, []) -> [].

-doc(#{equiv => zip(List1, List2, fail)}).
-spec zip(List1, List2) -> List3 when
      List1 :: [A],
      List2 :: [B],
      List3 :: [{A, B}],
      A :: term(),
      B :: term().

zip(Xs, Ys) -> zip(Xs, Ys, fail).

-doc """
"Zips" two lists into one list of two-tuples, where the first element of each
tuple is taken from the first list and the second element is taken from the
corresponding element in the second list.

The `How` parameter specifies the behavior if the given lists are of different
lengths.

- **`fail`** - The call will fail if the given lists are not of equal length.
  This is the default.

- **`trim`** - Surplus elements from the longer list will be ignored.

  ## Examples

  ```erlang
  1> lists:zip([a, b], [1, 2, 3], trim).
  [{a,1},{b,2}]
  2> lists:zip([a, b, c], [1, 2], trim).
  [{a,1},{b,2}]
  ```

- **`{pad, Defaults}`** - The shorter list will be padded to the length of the
  longer list, using the respective elements from the given `Defaults` tuple.

  ## Examples

  ```erlang
  1> lists:zip([a, b], [1, 2, 3], {pad, {x, 0}}).
  [{a,1},{b,2},{x,3}]
  2> lists:zip([a, b, c], [1, 2], {pad, {x, 0}}).
  [{a,1},{b,2},{c,0}]
  ```
""".
-doc(#{since => <<"OTP 26.0">>}).
-spec zip(List1, List2, How) -> List3 when
      List1 :: [A],
      List2 :: [B],
      List3 :: [{A | DefaultA, B | DefaultB}],
      A :: term(),
      B :: term(),
      How :: 'fail' | 'trim' | {'pad', {DefaultA, DefaultB}},
      DefaultA :: term(),
      DefaultB :: term().

zip([X | Xs], [Y | Ys], How) ->
    [{X, Y} | zip(Xs, Ys, How)];
zip([], [], fail) ->
    [];
zip([], [], trim) ->
    [];
zip([], [], {pad, {_, _}}) ->
    [];
zip([_ | _], [], trim) ->
    [];
zip([], [_ | _], trim) ->
    [];
zip([], [_ | _]=Ys, {pad, {X, _}}) ->
    [{X, Y} || Y <- Ys];
zip([_ | _]=Xs, [], {pad, {_, Y}}) ->
    [{X, Y} || X <- Xs].


-doc """
"Unzips" a list of two-tuples into two lists, where the first list contains the
first element of each tuple, and the second list contains the second element of
each tuple.

## Examples

```erlang
1> lists:unzip([{1, a}, {2, b}]).
{[1,2],[a,b]}
```
""".
-spec unzip(List1) -> {List2, List3} when
      List1 :: [{A, B}],
      List2 :: [A],
      List3 :: [B],
      A :: term(),
      B :: term().

unzip(Ts) -> unzip(Ts, [], []).

unzip([{X, Y} | Ts], Xs, Ys) -> unzip(Ts, [X | Xs], [Y | Ys]);
unzip([], Xs, Ys) -> {reverse(Xs), reverse(Ys)}.

-doc(#{equiv => zip3(List1, List2, List3, fail)}).
-spec zip3(List1, List2, List3) -> List4 when
      List1 :: [A],
      List2 :: [B],
      List3 :: [C],
      List4 :: [{A, B, C}],
      A :: term(),
      B :: term(),
      C :: term().

zip3(Xs, Ys, Zs) -> zip3(Xs, Ys, Zs, fail).

-doc """
"Zips" three lists into one list of three-tuples, where the first element of
each tuple is taken from the first list, the second element is taken from the
corresponding element in the second list, and the third element is taken from
the corresponding element in the third list.

For a description of the `How` parameter, see `zip/3`.

## Examples

```erlang
1> lists:zip3([a], [1, 2, 3], [17, 19], trim).
[{a,1,17}]
2> lists:zip3([a], [1, 2, 3], [17, 19], {pad, {z, 0, 0}}).
[{a,1,17}, {z,2,19}, {z,3,0}]
```
""".
-doc(#{since => <<"OTP 26.0">>}).
-spec zip3(List1, List2, List3, How) -> List4 when
      List1 :: [A],
      List2 :: [B],
      List3 :: [C],
      List4 :: [{A | DefaultA, B | DefaultB, C | DefaultC}],
      A :: term(),
      B :: term(),
      C :: term(),
      How :: 'fail' | 'trim' | {'pad', {DefaultA, DefaultB, DefaultC}},
      DefaultA :: term(),
      DefaultB :: term(),
      DefaultC :: term().

zip3([X | Xs], [Y | Ys], [Z | Zs], How) ->
    [{X, Y, Z} | zip3(Xs, Ys, Zs, How)];
zip3([], [], [], fail) ->
    [];
zip3([], [], [], trim) ->
    [];
zip3(Xs, Ys, Zs, trim) when is_list(Xs), is_list(Ys), is_list(Zs) ->
    [];
zip3([], [], [], {pad, {_, _, _}}) ->
    [];
zip3([], [], [_ |_]=Zs, {pad, {X, Y, _}}) ->
    [{X, Y, Z} || Z <- Zs];
zip3([], [_ | _]=Ys, [], {pad, {X, _, Z}}) ->
    [{X, Y, Z} || Y <- Ys];
zip3([_ | _]=Xs, [], [], {pad, {_, Y, Z}}) ->
    [{X, Y, Z} || X <- Xs];
zip3([], [Y | Ys], [Z | Zs], {pad, {X, _, _}} = How) ->
    [{X, Y, Z} | zip3([], Ys, Zs, How)];
zip3([X | Xs], [], [Z | Zs], {pad, {_, Y, _}} = How) ->
    [{X, Y, Z} | zip3(Xs, [], Zs, How)];
zip3([X | Xs], [Y | Ys], [], {pad, {_, _, Z}} = How) ->
    [{X, Y, Z} | zip3(Xs, Ys, [], How)].

-doc """
"Unzips" a list of three-tuples into three lists, where the first list contains
the first element of each tuple, the second list contains the second element of
each tuple, and the third list contains the third element of each tuple.

## Examples

```erlang
1> lists:unzip3([{a, 1, 2}, {b, 777, 999}]).
{[a,b],[1,777],[2,999]}
```
""".
-spec unzip3(List1) -> {List2, List3, List4} when
      List1 :: [{A, B, C}],
      List2 :: [A],
      List3 :: [B],
      List4 :: [C],
      A :: term(),
      B :: term(),
      C :: term().

unzip3(Ts) -> unzip3(Ts, [], [], []).

unzip3([{X, Y, Z} | Ts], Xs, Ys, Zs) ->
    unzip3(Ts, [X | Xs], [Y | Ys], [Z | Zs]);
unzip3([], Xs, Ys, Zs) ->
    {reverse(Xs), reverse(Ys), reverse(Zs)}.

-doc(#{equiv => zipwith(Combine, List1, List2, fail)}).
-spec zipwith(Combine, List1, List2) -> List3 when
      Combine :: fun((X, Y) -> T),
      List1 :: [X],
      List2 :: [Y],
      List3 :: [T],
      X :: term(),
      Y :: term(),
      T :: term().

zipwith(F, Xs, Ys) -> zipwith(F, Xs, Ys, fail).

-doc """
Combines the elements of two lists into a single list using the `Combine` fun.

For each pair `X, Y` of list elements from the two lists, the element
in the result list is `Combine(X, Y)`.

For a description of the `How` parameter, see `zip/3`.

[`zipwith(fun(X, Y) -> {X,Y} end, List1, List2)`](`zipwith/3`) is equivalent to
[`zip(List1, List2)`](`zip/2`).

## Examples

```erlang
1> lists:zipwith(fun(X, Y) -> X+Y end, [1,2,3], [4,5,6], fail).
[5,7,9]
```
""".
-doc(#{since => <<"OTP 26.0">>}).
-spec zipwith(Combine, List1, List2, How) -> List3 when
      Combine :: fun((X | DefaultX, Y | DefaultY) -> T),
      List1 :: [X],
      List2 :: [Y],
      List3 :: [T],
      X :: term(),
      Y :: term(),
      How :: 'fail' | 'trim' | {'pad', {DefaultX, DefaultY}},
      DefaultX :: term(),
      DefaultY :: term(),
      T :: term().

zipwith(F, [X | Xs], [Y | Ys], How) ->
    [F(X, Y) | zipwith(F, Xs, Ys, How)];
zipwith(F, [], [], fail) when is_function(F, 2) ->
    [];
zipwith(F, [], [], trim) when is_function(F, 2) ->
    [];
zipwith(F, [], [], {pad, {_, _}}) when is_function(F, 2) ->
    [];
zipwith(F, [_ | _], [], trim) when is_function(F, 2) ->
    [];
zipwith(F, [], [_ | _], trim) when is_function(F, 2) ->
    [];
zipwith(F, [], [_ | _]=Ys, {pad, {X, _}}) ->
    [F(X, Y) || Y <- Ys];
zipwith(F, [_ | _]=Xs, [], {pad, {_, Y}}) ->
    [F(X, Y) || X <- Xs].

-doc(#{equiv => zipwith3(Combine, List1, List2, List3, fail)}).
-spec zipwith3(Combine, List1, List2, List3) -> List4 when
      Combine :: fun((X, Y, Z) -> T),
      List1 :: [X],
      List2 :: [Y],
      List3 :: [Z],
      List4 :: [T],
      X :: term(),
      Y :: term(),
      Z :: term(),
      T :: term().

zipwith3(F, Xs, Ys, Zs) -> zipwith3(F, Xs, Ys, Zs, fail).

-doc """
Combines the elements of three lists into a single list using the
`Combine` fun.

For each triple `X, Y, Z` of list elements from the three lists, the
element in the result list is `Combine(X, Y, Z)`.

For a description of the `How` parameter, see `zip/3`.

[`zipwith3(fun(X, Y, Z) -> {X,Y,Z} end, List1, List2, List3)`](`zipwith3/4`) is
equivalent to [`zip3(List1, List2, List3)`](`zip3/3`).

## Examples

```erlang
1> lists:zipwith3(fun(X, Y, Z) -> X+Y+Z end, [1,2,3], [4,5,6], [7,8,9], fail).
[12,15,18]
2> lists:zipwith3(fun(X, Y, Z) -> [X,Y,Z] end, [a,b,c], [x,y,z], [1,2,3], fail).
[[a,x,1],[b,y,2],[c,z,3]]
```
""".
-doc(#{since => <<"OTP 26.0">>}).
-spec zipwith3(Combine, List1, List2, List3, How) -> List4 when
      Combine :: fun((X | DefaultX, Y | DefaultY, Z | DefaultZ) -> T),
      List1 :: [X],
      List2 :: [Y],
      List3 :: [Z],
      List4 :: [T],
      X :: term(),
      Y :: term(),
      Z :: term(),
      How :: 'fail' | 'trim' | {'pad', {DefaultX, DefaultY, DefaultZ}},
      DefaultX :: term(),
      DefaultY :: term(),
      DefaultZ :: term(),
      T :: term().

zipwith3(F, [X | Xs], [Y | Ys], [Z | Zs], How) ->
    [F(X, Y, Z) | zipwith3(F, Xs, Ys, Zs, How)];
zipwith3(F, [], [], [], fail) when is_function(F, 3) ->
    [];
zipwith3(F, [], [], [], trim) when is_function(F, 3) ->
    [];
zipwith3(F, Xs, Ys, Zs, trim) when is_function(F, 3), is_list(Xs), is_list(Ys), is_list(Zs) ->
    [];
zipwith3(F, [], [], [], {pad, {_, _, _}}) when is_function(F, 3) ->
    [];
zipwith3(F, [], [], [_ | _]=Zs, {pad, {X, Y, _}}) ->
    [F(X, Y, Z) || Z <- Zs];
zipwith3(F, [], [_ | _]=Ys, [], {pad, {X, _, Z}}) ->
    [F(X, Y, Z) || Y <- Ys];
zipwith3(F, [_ | _]=Xs, [], [], {pad, {_, Y, Z}}) ->
    [F(X, Y, Z) || X <- Xs];
zipwith3(F, [], [Y | Ys], [Z | Zs], {pad, {X, _, _}} = How) ->
    [F(X, Y, Z) | zipwith3(F, [], Ys, Zs, How)];
zipwith3(F, [X | Xs], [], [Z | Zs], {pad, {_, Y, _}} = How) ->
    [F(X, Y, Z) | zipwith3(F, Xs, [], Zs, How)];
zipwith3(F, [X | Xs], [Y | Ys], [], {pad, {_, _, Z}} = How) ->
    [F(X, Y, Z) | zipwith3(F, Xs, Ys, [], How)].

-doc """
Returns a list containing the sorted elements of `List1`.

The sort is stable.

## Examples

```erlang
1> lists:sort([4,1,3,2]).
[1,2,3,4]
2> lists:sort([a,4,3,b,9]).
[3,4,9,a,b]
```
Since the sort is stable, the relative order of elements that compare
equal is not changed:

```erlang
1> lists:sort([1.0,1]).
[1.0,1]
2> lists:sort([1,1.0]).
[1,1.0]
```
""".
-spec sort(List1) -> List2 when
      List1 :: [T],
      List2 :: [T],
      T :: term().

sort([X, Y | L] = L0) when X =< Y ->
    case L of
	[] -> 
	    L0;
	[Z] when Y =< Z ->
	    L0;
	[Z] when X =< Z ->
	    [X, Z, Y];
	[Z] ->
	    [Z, X, Y];
	_ when X == Y ->
	    sort_1(Y, L, [X]);
	_ ->
	    split_1(X, Y, L, [], [])
    end;
sort([X, Y | L]) ->
    case L of
	[] ->
	    [Y, X];
	[Z] when X =< Z ->
	    [Y, X | L];
	[Z] when Y =< Z ->
	    [Y, Z, X];
	[Z] ->
	    [Z, Y, X];
	_ ->
	    split_2(X, Y, L, [], [])
    end;
sort([_] = L) ->
    L;
sort([] = L) ->
    L.

sort_1(X, [Y | L], R) when X == Y ->
    sort_1(Y, L, [X | R]);
sort_1(X, [Y | L], R) when X < Y ->
    split_1(X, Y, L, R, []);
sort_1(X, [Y | L], R) ->
    split_2(X, Y, L, [], [lists:reverse(R, [])]);
sort_1(X, [], R) ->
    lists:reverse(R, [X]).

-doc """
Returns the sorted list formed by merging all sublists of `ListOfLists`.

All sublists must be sorted before evaluating this function.

When two elements compare equal, the element from the sublist with the lowest
position in `ListOfLists` is picked before the other element.

## Examples

```erlang
1> lists:merge([[b,l,l], [g,k,q]]).
[b,g,k,l,l,q]
```
""".
-spec merge(ListOfLists) -> List1 when
      ListOfLists :: [List],
      List :: [T],
      List1 :: [T],
      T :: term().

merge(L) ->
    mergel(L, []).

-doc """
Returns the sorted list formed by merging `List1`, `List2`, and `List3`.

All of `List1`, `List2`, and `List3` must be sorted before evaluating
this function.

When two elements compare equal, the element from `List1`, if there is such an
element, is picked before the other element, otherwise the element from `List2`
is picked before the element from `List3`.

## Examples

```erlang
1> lists:merge3([a,o], [g,q], [j]).
[a,g,j,o,q]
```
""".
-spec merge3(List1, List2, List3) -> List4 when
      List1 :: [X],
      List2 :: [Y],
      List3 :: [Z],
      List4 :: [(X | Y | Z)],
      X :: term(),
      Y :: term(),
      Z :: term().

merge3([_|_]=L1, [H2 | T2], [H3 | T3]) ->
   lists:reverse(merge3_1(L1, [], H2, T2, H3, T3), []);
merge3([_|_]=L1, [_|_]=L2, []) ->
    merge(L1, L2);
merge3([_|_]=L1, [], [_|_]=L3) ->
    merge(L1, L3);
merge3([_|_]=L1, [], []) ->
    L1;
merge3([], [_|_]=L2, [_|_]=L3) ->
    merge(L2, L3);
merge3([], [_|_]=L2, []) ->
    L2;
merge3([], [], [_|_]=L3) ->
    L3;
merge3([], [], []) ->
    [].

%% rmerge3(X, Y, Z) -> L
%%  merges three reversed sorted lists X, Y and Z

-doc false.
-spec rmerge3([X], [Y], [Z]) -> [(X | Y | Z)].

rmerge3([_|_]=L1, [H2 | T2], [H3 | T3]) ->
   lists:reverse(rmerge3_1(L1, [], H2, T2, H3, T3), []);
rmerge3([_|_]=L1, [_|_]=L2, []) ->
    rmerge(L1, L2);
rmerge3([_|_]=L1, [], [_|_]=L3) ->
    rmerge(L1, L3);
rmerge3([_|_]=L1, [], []) ->
    L1;
rmerge3([], [_|_]=L2, [_|_]=L3) ->
    rmerge(L2, L3);
rmerge3([], [_|_]=L2, []) ->
    L2;
rmerge3([], [], [_|_]=L3) ->
    L3;
rmerge3([], [], []) ->
    [].

-doc """
Returns the sorted list formed by merging `List1` and `List2`.

Both `List1` and `List2` must be sorted before evaluating this function.

When two elements compare equal, the element from `List1` is picked before the
element from `List2`.

## Examples

```erlang
1> lists:merge([a,o], [b,x]).
[a,b,o,x]
```
""".
-spec merge(List1, List2) -> List3 when
      List1 :: [X],
      List2 :: [Y],
      List3 :: [(X | Y)],
      X :: term(),
      Y :: term().

merge([_|_]=T1, [H2 | T2]) ->
    lists:reverse(merge2_1(T1, H2, T2, []), []);
merge([_|_]=L1, []) ->
    L1;
merge([], [_|_]=L2) ->
    L2;
merge([], []) ->
    [].

%% rmerge(X, Y) -> L
%%  merges two reversed sorted lists X and Y

%% reverse(rmerge(reverse(A),reverse(B))) is equal to merge(I,A,B).

-doc false.
-spec rmerge([X], [Y]) -> [(X | Y)].

rmerge([_|_]=T1, [H2 | T2]) ->
    lists:reverse(rmerge2_1(T1, H2, T2, []), []);
rmerge([_|_]=L1, []) ->
    L1;
rmerge([], [_|_]=L2) ->
    L2;
rmerge([], []) ->
    [].

-doc """
Concatenates the text representation of the elements of `Things`.

The elements of `Things` can be atoms, integers, floats, or strings.

## Examples

```erlang
1> lists:concat([doc, '/', file, '.', 3]).
"doc/file.3"
```
""".
-spec concat(Things) -> string() when
      Things :: [Thing],
      Thing :: atom() | integer() | float() | string().

concat(List) ->
    flatmap(fun thing_to_list/1, List).

thing_to_list(X) when is_integer(X) -> integer_to_list(X);
thing_to_list(X) when is_float(X)   -> float_to_list(X);
thing_to_list(X) when is_atom(X)    -> atom_to_list(X);
thing_to_list(X) when is_list(X)    -> X.	%Assumed to be a string

-doc """
Returns a flattened version of `DeepList`.

## Examples

```erlang
1> lists:flatten([a,[b,c,[d,e]],f]).
[a,b,c,d,e,f]
```
""".
-spec flatten(DeepList) -> List when
      DeepList :: [term() | DeepList],
      List :: [term()].

flatten(List) when is_list(List) ->
    do_flatten(List, []).

-doc """
Returns a flattened version of `DeepList` with tail `Tail` appended.

## Examples

```erlang
1> lists:flatten([a,[b,c,[d,e]],f], [g,h,i]).
[a,b,c,d,e,f,g,h,i]
```
""".
-spec flatten(DeepList, Tail) -> List when
      DeepList :: [term() | DeepList],
      Tail :: [term()],
      List :: [term()].

flatten(List, Tail) when is_list(List), is_list(Tail) ->
    do_flatten(List, Tail).

do_flatten([H|T], Tail) when is_list(H) ->
    do_flatten(H, do_flatten(T, Tail));
do_flatten([H|T], Tail) ->
    [H|do_flatten(T, Tail)];
do_flatten([], Tail) ->
    Tail.

%% flatlength(List)
%%  Calculate the length of a list of lists.

-doc """
Equivalent to [`length(flatten(DeepList))`](`length/1`), but more efficient.

## Examples

```erlang
1> lists:flatlength([a,[b,c,[d,e]],f,[[g,h,i]]]).
9
2> lists:flatlength([[[]]]).
0
```

""".
-spec flatlength(DeepList) -> non_neg_integer() when
      DeepList :: [term() | DeepList].

flatlength(List) ->
    flatlength(List, 0).

flatlength([H|T], L) when is_list(H) ->
    flatlength(H, flatlength(T, L));
flatlength([_|T], L) ->
    flatlength(T, L + 1);
flatlength([], L) -> L.

%% keymember(Key, Index, [Tuple]) Now a BIF!
%% keyfind(Key, Index, [Tuple]) A BIF!
%% keysearch(Key, Index, [Tuple]) Now a BIF!
%% keydelete(Key, Index, [Tuple])
%% keyreplace(Key, Index, [Tuple], NewTuple)
%% keytake(Key, Index, [Tuple])
%% keystore(Key, Index, [Tuple], NewTuple)
%% keysort(Index, [Tuple])
%% keymerge(Index, [Tuple], [Tuple])
%% ukeysort(Index, [Tuple])
%% ukeymerge(Index, [Tuple], [Tuple])
%% keymap(Function, Index, [Tuple])
%% keymap(Function, ExtraArgs, Index, [Tuple])

-doc """
Returns a copy of `TupleList1`, where the first occurrence of a tuple
whose `N`th element compares equal to `Key` is removed, if there is
such a tuple.

## Examples

```erlang
1> lists:keydelete(c, 1, [{b,1}, {c,55}, {d,75}]).
[{b,1},{d,75}]
2> lists:keydelete(unknown, 1, [{b,1}, {c,55}, {d,75}]).
[{b,1},{c,55},{d,75}]
```
""".
-spec keydelete(Key, N, TupleList1) -> TupleList2 when
      Key :: term(),
      N :: pos_integer(),
      TupleList1 :: [Tuple],
      TupleList2 :: [Tuple],
      Tuple :: tuple().

keydelete(K, N, L) when is_integer(N), N > 0 ->
    keydelete3(K, N, L).

keydelete3(Key, N, [H|T]) when element(N, H) == Key -> T;
keydelete3(Key, N, [H|T]) ->
    [H|keydelete3(Key, N, T)];
keydelete3(_, _, []) -> [].

-doc """
Returns a copy of `TupleList1` where the first occurrence of a tuple `T` whose
`N`th element compares equal to `Key` is replaced with `NewTuple`, if there is
such a tuple `T`.

## Examples

```erlang
1> lists:keyreplace(c, 1, [{b,1}, {c,55}, {d,75}], {new,tuple}).
[{b,1},{new,tuple},{d,75}]
2> lists:keyreplace(unknown, 1, [{b,1}, {c,55}, {d,75}], {new,tuple}).
[{b,1},{c,55},{d,75}]
```
""".
-spec keyreplace(Key, N, TupleList1, NewTuple) -> TupleList2 when
      Key :: term(),
      N :: pos_integer(),
      TupleList1 :: [Tuple],
      TupleList2 :: [Tuple],
      NewTuple :: Tuple,
      Tuple :: tuple().

keyreplace(K, N, L, New) when is_integer(N), N > 0, is_tuple(New) ->
    keyreplace3(K, N, L, New).

keyreplace3(Key, Pos, [Tup|Tail], New) when element(Pos, Tup) == Key ->
    [New|Tail];
keyreplace3(Key, Pos, [H|T], New) ->
    [H|keyreplace3(Key, Pos, T, New)];
keyreplace3(_, _, [], _) -> [].

-doc """
Searches the list of tuples `TupleList1` for a tuple whose `N`th
element compares equal to `Key`, returning `{value, Tuple,
TupleList2}` if found, where `TupleList2` is a copy of `TupleList1`
with the first occurrence of `Tuple` removed.

Otherwise, returns `false` if no such tuple is found.

## Examples

```erlang
1> lists:keytake(b, 1, [{a, 10}, {b, 23}, {c, 99}]).
{value,{b,23},[{a, 10},{c, 99}]}
2> lists:keytake(z, 1, [{a, 10}, {b, 23}, {c, 99}]).
false
```
""".
-spec keytake(Key, N, TupleList1) -> {value, Tuple, TupleList2} | false when
      Key :: term(),
      N :: pos_integer(),
      TupleList1 :: [tuple()],
      TupleList2 :: [tuple()],
      Tuple :: tuple().

keytake(Key, N, L) when is_integer(N), N > 0 ->
    keytake(Key, N, L, []).

keytake(Key, N, [H|T], L) when element(N, H) == Key ->
    {value, H, lists:reverse(L, T)};
keytake(Key, N, [H|T], L) ->
    keytake(Key, N, T, [H|L]);
keytake(_K, _N, [], _L) -> false.

-doc """
Returns a copy of `TupleList1` with the first tuple whose `N`th
element compares equal to `Key` replaced by `NewTuple`, or with
`[NewTuple]` appended if no such tuple exists.

## Examples

```erlang
1> lists:keystore(b, 1, [{a, 10}, {b, 23}, {c, 99}], {bb, 1}).
[{a, 10}, {bb, 1}, {c, 99}]
2> lists:keystore(z, 1, [{a, 10}, {b, 23}, {c, 99}], {z, 2}).
[{a, 10}, {b, 23}, {c, 99}, {z, 2}]
```
""".
-spec keystore(Key, N, TupleList1, NewTuple) -> TupleList2 when
      Key :: term(),
      N :: pos_integer(),
      TupleList1 :: [Tuple],
      TupleList2 :: [Tuple, ...],
      NewTuple :: Tuple,
      Tuple :: tuple().

keystore(K, N, L, New) when is_integer(N), N > 0, is_tuple(New) ->
    keystore2(K, N, L, New).

keystore2(Key, N, [H|T], New) when element(N, H) == Key ->
    [New|T];
keystore2(Key, N, [H|T], New) ->
    [H|keystore2(Key, N, T, New)];
keystore2(_Key, _N, [], New) ->
    [New].

-doc """

Returns a list of the elements in `TupleList1`, sorted by the `N`th
element of each tuple.

The sort is stable.

## Examples

```erlang
1> lists:keysort(2, [{a, 99}, {b, 17}, {c, 50}, {d, 50}]).
[{b,17},{c,50},{d,50},{a,99}]
```
""".
-spec keysort(N, TupleList1) -> TupleList2 when
      N :: pos_integer(),
      TupleList1 :: [Tuple],
      TupleList2 :: [Tuple],
      Tuple :: tuple().

keysort(I, L) when is_integer(I), I > 0 ->
    case L of
	[] -> L;
	[_] -> L;
	[X, Y | T] ->
	    case {element(I, X), element(I, Y)} of
		{EX, EY} when EX =< EY ->
		    case T of
			[] ->
			    L;
			[Z] ->
			    case element(I, Z) of
				EZ when EY =< EZ ->
				    L;
				EZ when EX =< EZ ->
				    [X, Z, Y];
				_EZ ->
				    [Z, X, Y]
			    end;
			_ when X == Y ->
			    keysort_1(I, Y, EY, T, [X]);
			_ ->
			    keysplit_1(I, X, EX, Y, EY, T, [], [])
		    end;
		{EX, EY} ->
		    case T of
			[] ->
			    [Y, X];
			[Z] ->
			    case element(I, Z) of
				EZ when EX =< EZ ->
				    [Y, X | T];
				EZ when EY =< EZ ->
				    [Y, Z, X];
				_EZ ->
				    [Z, Y, X]
			    end;
			_ ->
			    keysplit_2(I, X, EX, Y, EY, T, [], [])
		    end
	    end
    end.

keysort_1(I, X, EX, [Y | L], R) ->
    case element(I, Y) of
	EY when EX < EY ->
	    keysplit_1(I, X, EX, Y, EY, L, R, []);
	EY when EX > EY ->
	    keysplit_2(I, X, EX, Y, EY, L, [], [lists:reverse(R)]);
        EY -> % EX == EY
            keysort_1(I, Y, EY, L, [X | R])
    end;
keysort_1(_I, X, _EX, [], R) ->
    lists:reverse(R, [X]).

-doc """
Returns the sorted list formed by merging `TupleList1` and `TupleList2`.

The merge is performed on the `N`th element of each tuple. Both
`TupleList1` and `TupleList2` must be key-sorted before evaluating
this function. When the key elements of the two tuples compare equal,
the tuple from `TupleList1` is picked before the tuple from
`TupleList2`.

## Examples

```erlang
1> lists:keymerge(2, [{b, 50}], [{c, 20}, {a, 50}]).
[{c,20},{b,50},{a,50}]
```
""".
-spec keymerge(N, TupleList1, TupleList2) -> TupleList3 when
      N :: pos_integer(),
      TupleList1 :: [T1],
      TupleList2 :: [T2],
      TupleList3 :: [(T1 | T2)],
      T1 :: Tuple,
      T2 :: Tuple,
      Tuple :: tuple().

keymerge(Index, L1, L2) when is_integer(Index), Index > 0 ->
    keymerge_1(Index, L1, L2).

keymerge_1(Index, [_|_]=T1, [H2 | T2]) -> 
    E2 = element(Index, H2),
    M = keymerge2_1(Index, T1, E2, H2, T2, []),
    lists:reverse(M, []);
keymerge_1(_Index, [_|_]=L1, []) ->
    L1;
keymerge_1(_Index, [], [_|_]=L2) ->
    L2;
keymerge_1(_Index, [], []) ->
    [].

%% reverse(rkeymerge(I,reverse(A),reverse(B))) is equal to keymerge(I,A,B).

-doc false.
-spec rkeymerge(pos_integer(), [X], [Y]) ->
	[R] when X :: tuple(), Y :: tuple(), R :: tuple().

rkeymerge(Index, L1, L2) when is_integer(Index), Index > 0 ->
    rkeymerge_1(Index, L1, L2).

rkeymerge_1(Index, [_|_]=T1, [H2 | T2]) -> 
    E2 = element(Index, H2),
    M = rkeymerge2_1(Index, T1, E2, H2, T2, []),
    lists:reverse(M, []);
rkeymerge_1(_Index, [_|_]=L1, []) ->
    L1;
rkeymerge_1(_Index, [], [_|_]=L2) ->
    L2;
rkeymerge_1(_Index, [], []) ->
    [].

-doc """
Returns a sorted list of the elements in `TupleList1`, keeping only the
first occurrence of tuples whose `N`th elements compare equal.

Sorting is performed on the `N`th element of the tuples.

## Examples

```erlang
1> lists:ukeysort(2, [{a, 27}, {d, 23}, {e, 23}]).
[{d,23}, {a, 27}]
```
""".
-spec ukeysort(N, TupleList1) -> TupleList2 when
      N :: pos_integer(),
      TupleList1 :: [Tuple],
      TupleList2 :: [Tuple],
      Tuple :: tuple().

ukeysort(I, L) when is_integer(I), I > 0 ->
    case L of
	[] -> L;
	[_] -> L;
	[X, Y | T] ->
            case {element(I, X), element(I, Y)} of
                {EX, EY} when EX == EY ->
                    ukeysort_1(I, X, EX, T);
                {EX, EY} when EX < EY ->
                    case T of
                        [] ->
                            L;
                        [Z] ->
                            case element(I, Z) of
                                EZ when EY == EZ ->
                                    [X, Y];
                                EZ when EY < EZ ->
                                    [X, Y, Z];
                                EZ when EZ == EX ->
                                    [X, Y];
                                EZ when EX =< EZ ->
                                    [X, Z, Y];
                                _EZ ->
                                    [Z, X, Y]
                            end;
                        _ ->
                            ukeysplit_1(I, X, EX, Y, EY, T, [], [])
                    end;
                {EX, EY} ->
                    case T of
                        [] ->
                            [Y, X];
                        [Z] ->
                            case element(I, Z) of
                                EZ when EX == EZ ->
                                    [Y, X];
                                EZ when EX < EZ ->
                                    [Y, X, Z];
                                EZ when EY == EZ ->
                                    [Y, X];
                                EZ when EY =< EZ ->
                                    [Y, Z, X];
                                _EZ ->
                                    [Z, Y, X]
                            end;
                        _ ->
			    ukeysplit_2(I, Y, EY, T, [X])
                    end
	    end
    end.

ukeysort_1(I, X, EX, [Y | L]) ->
    case element(I, Y) of
        EY when EX == EY ->
            ukeysort_1(I, X, EX, L);
	EY when EX < EY ->
	    ukeysplit_1(I, X, EX, Y, EY, L, [], []);
	EY ->
	    ukeysplit_2(I, Y, EY, L, [X])
    end;
ukeysort_1(_I, X, _EX, []) ->
    [X].

-doc """
Returns the sorted list formed by merging `TupleList1` and `TupleList2`
based on the `N`th element of each tuple.

Both `TupleList1` and `TupleList2` must be key-sorted without
duplicates before evaluating this function.

When the `N`th elements of two tuples compare equal, the tuple
from `TupleList1` is picked and the one from `TupleList2` is removed.

## Examples

```erlang
1> lists:ukeymerge(1, [{a, 33}, {c, 15}], [{a, 59}, {d, 39}]).
[{a,33},{c,15},{d,39}]
```
""".
-spec ukeymerge(N, TupleList1, TupleList2) -> TupleList3 when
      N :: pos_integer(),
      TupleList1 :: [T1],
      TupleList2 :: [T2],
      TupleList3 :: [(T1 | T2)],
      T1 :: Tuple,
      T2 :: Tuple,
      Tuple :: tuple().

ukeymerge(Index, L1, L2) when is_integer(Index), Index > 0 ->
    ukeymerge_1(Index, L1, L2).

ukeymerge_1(Index, [H1 | T1], [_|_]=T2) ->
    E1 = element(Index, H1),
    M = ukeymerge2_2(Index, T1, E1, H1, T2, []),
    lists:reverse(M, []);
ukeymerge_1(_Index, [_|_]=L1, []) ->
    L1;
ukeymerge_1(_Index, [], [_|_]=L2) ->
    L2;
ukeymerge_1(_Index, [], []) ->
    [].

%% reverse(rukeymerge(I,reverse(A),reverse(B))) is equal to ukeymerge(I,A,B).

-doc false.
-spec rukeymerge(pos_integer(), [X], [Y]) ->
	[(X | Y)] when X :: tuple(), Y :: tuple().

rukeymerge(Index, L1, L2) when is_integer(Index), Index > 0 ->
    rukeymerge_1(Index, L1, L2).

rukeymerge_1(Index, [_|_]=T1, [H2 | T2]) ->
    E2 = element(Index, H2),
    M = rukeymerge2_1(Index, T1, E2, T2, [], H2),
    lists:reverse(M, []);
rukeymerge_1(_Index, [_|_]=L1, []) ->
    L1;
rukeymerge_1(_Index, [], [_|_]=L2) ->
    L2;
rukeymerge_1(_Index, [], []) ->
    [].

-doc """
Returns a list of tuples where, for each tuple in `TupleList1`, the `N`th
element `Term1` of the tuple has been replaced with the result of calling
`Fun(Term1)`.

## Examples

```erlang
1> Fun = fun(Atom) -> atom_to_list(Atom) end.
2> lists:keymap(Fun, 2, [{name,jane,22},{name,lizzie,20},{name,lydia,15}]).
[{name,"jane",22},{name,"lizzie",20},{name,"lydia",15}]
```
""".
-spec keymap(Fun, N, TupleList1) -> TupleList2 when
      Fun :: fun((Term1 :: term()) -> Term2 :: term()),
      N :: pos_integer(),
      TupleList1 :: [Tuple],
      TupleList2 :: [Tuple],
      Tuple :: tuple().

keymap(Fun, Index, [Tup|Tail]) ->
   [setelement(Index, Tup, Fun(element(Index, Tup)))|keymap(Fun, Index, Tail)];
keymap(Fun, Index, []) when is_integer(Index), Index >= 1, 
                            is_function(Fun, 1) -> [].

-doc(#{equiv => enumerate(1, 1, List1)}).
-doc(#{since => <<"OTP 25.0">>}).
-spec enumerate(List1) -> List2 when
      List1 :: [T],
      List2 :: [{Index, T}],
      Index :: integer(),
      T :: term().
enumerate(List1) ->
    enumerate(1, 1, List1).

-doc(#{equiv => enumerate(Index, 1, List1)}).
-doc(#{since => <<"OTP 25.0">>}).
-spec enumerate(Index, List1) -> List2 when
      List1 :: [T],
      List2 :: [{Index, T}],
      Index :: integer(),
      T :: term().
enumerate(Index, List1) ->
    enumerate(Index, 1, List1).

-doc """
Returns `List1` with each element `H` replaced by a tuple of form `{I, H}`, where
`I` is the position of `H` in `List1`.

The enumeration starts with `Index` and increases by `Step` in each
step.

That is, [`enumerate/3`](`enumerate/3`) behaves as if it were defined as
follows:

```erlang
enumerate(I, S, List) ->
  {List1, _ } = lists:mapfoldl(fun(T, Acc) -> {{Acc, T}, Acc+S} end, I, List),
  List1.
```

The default values for `Index` and `Step` are both `1`.

## Examples

```erlang
1> lists:enumerate([a,b,c]).
[{1,a},{2,b},{3,c}]
2> lists:enumerate(10, [a,b,c]).
[{10,a},{11,b},{12,c}]
3> lists:enumerate(0, -2, [a,b,c]).
[{0,a},{-2,b},{-4,c}]
```
""".
-doc(#{since => <<"OTP 26.0">>}).
-spec enumerate(Index, Step, List1) -> List2 when
      List1 :: [T],
      List2 :: [{Index, T}],
      Index :: integer(),
      Step :: integer(),
      T :: term().
enumerate(Index, Step, List1) when is_integer(Index), is_integer(Step) ->
    enumerate_1(Index, Step, List1).

enumerate_1(Index, Step, [H|T]) ->
    [{Index, H}|enumerate_1(Index + Step, Step, T)];
enumerate_1(_Index, _Step, []) ->
    [].

-doc """
Returns a list of the elements in `List1`, sorted according to the
[ordering function](`m:lists#ordering_function`) `Fun`, where `Fun(A,
B)` returns `true` if `A` compares less than or equal to `B` in the
ordering; otherwise, it returns `false`.

## Examples

```erlang
1> F = fun(A, B) -> tuple_size(A) =< tuple_size(B) end.
2> lists:sort(F, [{a, b, c}, {x, y}, {q, w}]).
[{x,y},{q,w},{a,b,c}]
```
""".
-spec sort(Fun, List1) -> List2 when
      Fun :: fun((A :: T, B :: T) -> boolean()),
      List1 :: [T],
      List2 :: [T],
      T :: term().

sort(Fun, []) when is_function(Fun, 2) ->
    [];
sort(Fun, [_] = L) when is_function(Fun, 2) ->
    L;
sort(Fun, [X, Y | T]) ->
    case Fun(X, Y) of
	true ->
	    fsplit_1(Y, X, Fun, T, [], []);
	false ->
	    fsplit_2(Y, X, Fun, T, [], [])
    end.

-doc """
Returns a sorted list formed by merging `List1` and `List2` based on `Fun`.

Both `List1` and `List2` must be sorted according to the
[ordering function](`m:lists#ordering_function`) `Fun` before evaluating this
function.

`Fun(A, B)` is to return `true` if `A` compares less than or equal to
`B` in the ordering, otherwise `false`. When two elements compare equal, the
element from `List1` is picked before the element from `List2`.

## Examples

```erlang
1> F = fun(A, B) -> tuple_size(A) =< tuple_size(B) end.
2> lists:merge(F, [{x, y}, {a, b, c}], [{q, w}]).
[{x,y},{q,w},{a,b,c}]
```
""".
-spec merge(Fun, List1, List2) -> List3 when
      Fun :: fun((A, B) -> boolean()),
      List1 :: [A],
      List2 :: [B],
      List3 :: [(A | B)],
      A :: term(),
      B :: term().

merge(Fun, L1, L2) when is_function(Fun, 2) ->
    merge_1(Fun, L1, L2).

merge_1(Fun, [_|_]=T1, [H2 | T2]) ->
    lists:reverse(fmerge2_1(T1, H2, Fun, T2, []), []);
merge_1(_Fun, [_|_]=L1, []) ->
    L1;
merge_1(_Fun, [], [_|_]=L2) ->
    L2;
merge_1(_Fun, [], []) ->
    [].

%% reverse(rmerge(F,reverse(A),reverse(B))) is equal to merge(F,A,B).

-doc false.
-spec rmerge(fun((X, Y) -> boolean()), [X], [Y]) -> [(X | Y)].

rmerge(Fun, L1, L2) when is_function(Fun, 2) ->
    rmerge_1(Fun, L1, L2).

rmerge_1(Fun, [_|_]=T1, [H2 | T2]) ->
    lists:reverse(rfmerge2_1(T1, H2, Fun, T2, []), []);
rmerge_1(_Fun, [_|_]=L1, []) ->
    L1;
rmerge_1(_Fun, [], [_|_]=L2) ->
    L2;
rmerge_1(_Fun, [], []) ->
    [].

-doc """
Returns a list containing the sorted elements of `List1` where all except the
first element of the elements comparing equal according to the
[ordering function](`m:lists#ordering_function`) `Fun` have been removed.

`Fun(A, B)` is to return `true` if `A` compares less than or equal to `B` in the
ordering, otherwise `false`.

## Examples

```erlang
1> F = fun(A, B) -> tuple_size(A) =< tuple_size(B) end.
2> lists:usort(F, [{a, b, c}, {x, y}, {q, w}]).
[{x,y},{a,b,c}]
```
""".
-spec usort(Fun, List1) -> List2 when
      Fun :: fun((T, T) -> boolean()),
      List1 :: [T],
      List2 :: [T],
      T :: term().

usort(Fun, [_] = L) when is_function(Fun, 2) ->
    L;
usort(Fun, [] = L) when is_function(Fun, 2) ->
    L;
usort(Fun, [X | L]) when is_function(Fun, 2) ->
    usort_1(Fun, X, L).

usort_1(Fun, X, [Y | L]) ->
    case Fun(X, Y) of
        true ->
            case Fun(Y, X) of
                true -> % X equal to Y
                    case L of
                        [] ->
                            [X];
                        _ ->
                            usort_1(Fun, X, L)
                    end;
                false ->
                    ufsplit_1(Y, X, Fun, L, [], [])
            end;
        false  ->
	    ufsplit_2(Y, 
