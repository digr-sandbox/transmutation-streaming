=encoding utf8

=head1 NAME
X<operator>

perlop - Perl expressions: operators, precedence, string literals

=head1 DESCRIPTION

In Perl, the operator determines what operation is performed,
independent of the type of the operands.  For example S<C<$x + $y>>
is always a numeric addition, and if C<$x> or C<$y> do not contain
numbers, an attempt is made to convert them to numbers first.

This is in contrast to many other dynamic languages, where the
operation is determined by the type of the first argument.  It also
means that Perl has two versions of some operators, one for numeric
and one for string comparison.  For example S<C<$x == $y>> compares
two numbers for equality, and S<C<$x eq $y>> compares two strings.

There are a few exceptions though: The operator C<x> can be either string
repetition or list repetition, depending on the type of the left
operand, and C<&>, C<|>, C<^> and C<~> can be either string or numeric bit
operations (unless C<use v5.28> or later, or L<feature/"The 'bitwise' feature">
is in effect, in which case a different version of each operator exists
for manipulating strings).

=head2 Operator Precedence and Associativity
X<operator, precedence> X<precedence> X<associativity>

Operator precedence and associativity work in Perl more or less like
they do in mathematics.

I<Operator precedence> means some operators group more tightly than others.
For example, in C<2 + 4 * 5>, the multiplication has higher precedence, so C<4
* 5> is grouped together as the right-hand operand of the addition, rather
than C<2 + 4> being grouped together as the left-hand operand of the
multiplication. It is as if the expression were written C<2 + (4 * 5)>, not
C<(2 + 4) * 5>. So the expression yields C<2 + 20 == 22>, rather than
C<6 * 5 == 30>.

I<Operator associativity> defines what happens if a sequence of the same
operators is used one after another:
usually that they will be grouped at the left
or the right. For example, in C<9 - 3 - 2>, subtraction is left associative,
so C<9 - 3> is grouped together as the left-hand operand of the second
subtraction, rather than C<3 - 2> being grouped together as the right-hand
operand of the first subtraction. It is as if the expression were written
C<(9 - 3) - 2>, not C<9 - (3 - 2)>. So the expression yields C<6 - 2 == 4>,
rather than C<9 - 1 == 8>.

For simple operators that evaluate all their operands and then combine the
values in some way, precedence and associativity (and parentheses) imply some
ordering requirements on those combining operations. For example, in C<2 + 4 *
5>, the grouping implied by precedence means that the multiplication of 4 and
5 must be performed before the addition of 2 and 20, simply because the result
of that multiplication is required as one of the operands of the addition. But
the order of operations is not fully determined by this: in C<2 * 2 + 4 * 5>
both multiplications must be performed before the addition, but the grouping
does not say anything about the order in which the two multiplications are
performed. In fact Perl has a general rule that the operands of an operator
are evaluated in left-to-right order. A few operators such as C<&&=> have
special evaluation rules that can result in an operand not being evaluated at
all; in general, the top-level operator in an expression has control of
operand evaluation.

Some comparison operators, as their associativity, I<chain> with some
operators of the same precedence (but never with operators of different
precedence).  This chaining means that each comparison is performed
on the two arguments surrounding it, with each interior argument taking
part in two comparisons, and the comparison results are implicitly ANDed.
Thus S<C<"$x E<lt> $y E<lt>= $z">> behaves exactly like S<C<"$x E<lt>
$y && $y E<lt>= $z">>, assuming that C<"$y"> is as simple a scalar as
it looks.  The ANDing short-circuits just like C<"&&"> does, stopping
the sequence of comparisons as soon as one yields false.

In a chained comparison, each argument expression is evaluated at most
once, even if it takes part in two comparisons, but the result of the
evaluation is fetched for each comparison.  (It is not evaluated
at all if the short-circuiting means that it's not required for any
comparisons.)  This matters if the computation of an interior argument
is expensive or non-deterministic.  For example,

    if ($x < expensive_sub() <= $z) { ...

is not entirely like

    if ($x < expensive_sub() && expensive_sub() <= $z) { ...

but instead closer to

    my $tmp = expensive_sub();
    if ($x < $tmp && $tmp <= $z) { ...

in that the subroutine is only called once.  However, it's not exactly
like this latter code either, because the chained comparison doesn't
actually involve any temporary variable (named or otherwise): there is
no assignment.  This doesn't make much difference where the expression
is a call to an ordinary subroutine, but matters more with an lvalue
subroutine, or if the argument expression yields some unusual kind of
scalar by other means.  For example, if the argument expression yields
a tied scalar, then the expression is evaluated to produce that scalar
at most once, but the value of that scalar may be fetched up to twice,
once for each comparison in which it is actually used.

In this example, the expression is evaluated only once, and the tied
scalar (the result of the expression) is fetched for each comparison that
uses it.

    if ($x < $tied_scalar < $z) { ...

In the next example, the expression is evaluated only once, and the tied
scalar is fetched once as part of the operation within the expression.
The result of that operation is fetched for each comparison, which
normally doesn't matter unless that expression result is also magical due
to operator overloading.

    if ($x < $tied_scalar + 42 < $z) { ...

Some operators are instead non-associative, meaning that it is a syntax
error to use a sequence of those operators of the same precedence.
For example, S<C<"$x .. $y .. $z">> is an error.

Perl operators have the following associativity and precedence,
listed from highest precedence to lowest.  Operators borrowed from
C keep the same precedence relationship with each other, even where
C's precedence is slightly screwy.  (This makes learning Perl easier
for C folks.)  With very few exceptions, these all operate on scalar
values only, not array values.

    left        terms and list operators (leftward)
    left        ->
    nonassoc    ++ --
    right       **
    right       ! ~ ~. \ and unary + and -
    left        =~ !~
    left        * / % x
    left        + - .
    left        << >>
    nonassoc    named unary operators
    nonassoc    isa
    chained     < > <= >= lt gt le ge
    chain/na    == != eq ne <=> cmp ~~
    left        & &.
    left        | |. ^ ^.
    left        &&
    left        || ^^ //
    nonassoc    ..  ...
    right       ?:
    right       = += -= *= etc. goto last next redo dump
    left        , =>
    nonassoc    list operators (rightward)
    right       not
    left        and
    left        or xor

The following sections cover these operators in detail.  Each section
covers all the operators for a single precedence level.  The sections
are ordered highest precedence first, same as in the table above.

Many operators can be overloaded for objects.  See L<overload>.

=head2 Terms and List Operators (Leftward)
X<list operator> X<operator, list> X<term>

A TERM has the highest precedence in Perl.  They include variables,
quote and quote-like operators, any expression in parentheses,
and any function whose arguments are parenthesized.  Actually, there
aren't really functions in this sense, just list operators and unary
operators behaving as functions because you put parentheses around
the arguments.  These are all documented in L<perlfunc>.

If any list operator (C<print()>, etc.) or any unary operator (C<chdir()>, etc.)
is followed by a left parenthesis as the next token, the operator and
arguments within parentheses are taken to be of highest precedence,
just like a normal function call.

In the absence of parentheses, the precedence of list operators such as
C<print>, C<sort>, or C<chmod> is either very high or very low depending on
whether you are looking at the left side or the right side of the operator.
For example, in

    @ary = (1, 3, sort 4, 2);
    print @ary;         # prints 1324

the commas on the right of the C<sort> are evaluated before the C<sort>,
but the commas on the left are evaluated after.  In other words,
list operators tend to gobble up all arguments that follow, and
then act like a simple TERM with regard to the preceding expression.
Be careful with parentheses:

    # These evaluate exit before doing the print:
    print($foo, exit);  # Obviously not what you want.
    print $foo, exit;   # Nor is this.

    # These do the print before evaluating exit:
    (print $foo), exit; # This is what you want.
    print($foo), exit;  # Or this.
    print ($foo), exit; # Or even this.

Also note that

    print ($foo & 255) + 1, "\n";

probably doesn't do what you expect at first glance.  The parentheses
enclose the argument list for C<print> which is evaluated (printing
the result of S<C<$foo & 255>>).  Then one is added to the return value
of C<print> (usually 1).  The result is something like this:

    1 + 1, "\n";    # Obviously not what you meant.

To do what you meant properly, you must write:

    print(($foo & 255) + 1, "\n");

See L</Named Unary Operators> for more discussion of this.

Also parsed as terms are the S<C<do {}>> and S<C<eval {}>> constructs, as
well as subroutine and method calls, and the anonymous
constructors C<[]> and C<{}>.

See also L</Quote and Quote-like Operators> below,
as well as L</"I/O Operators">.

=head2 The Arrow Operator
X<arrow> X<dereference> X<< -> >>

"C<< -> >>" is an infix dereference operator, just as it is in C
and C++.  If the right side is one of a C<[...]>, C<{...}>, or a
C<(...)> subscript, then the left side must be either a hard or
symbolic reference to an array, a hash, or a subroutine respectively.
(Or technically speaking, a location capable of holding a hard
reference, if it's an array or hash reference being used for
assignment.)  See L<perlreftut> and L<perlref>.

Otherwise, the right side is a method name or a simple scalar
variable containing either the method name or a subroutine reference,
and (if it is a method name) the left side must be either an object (a
blessed reference) or a class name (that is, a package name).  See
L<perlobj>.

The right side may also be the name of a subroutine, prefixed with the C<&>
sigil.  This creates what looks like a lexical method invocation, where the
method subroutine is resolved lexically instead of by name by a search within
the packages of the object's class.  This resolution happens entirely at
compile-time, and performs the same as a regular subroutine call at runtime.

The dereferencing cases (as opposed to method-calling cases) are
somewhat extended by the C<postderef> feature.  For the
details of that feature, consult L<perlref/Postfix Dereference Syntax>.

=head2 Auto-increment and Auto-decrement
X<increment> X<auto-increment> X<++> X<decrement> X<auto-decrement> X<-->

C<"++"> and C<"--"> work as in C.  That is, if placed before a variable,
they increment or decrement the variable by one before returning the
value, and if placed after, increment or decrement after returning the
value.

    $i = 0;  $j = 0;
    print $i++;  # prints 0
    print ++$j;  # prints 1

Note that just as in C, Perl doesn't define B<when> the variable is
incremented or decremented.  You just know it will be done sometime
before or after the value is returned.  This also means that modifying
a variable twice in the same statement will lead to undefined behavior.
Avoid statements like:

    $i = $i ++;
    print ++ $i + $i ++;

Perl will not guarantee what the result of the above statements is.

The auto-increment operator has a little extra builtin magic to it.  If
you increment a variable that is numeric, or that has ever been used in
a numeric context, you get a normal increment.  If, however, the
variable has been used in only string contexts since it was set, and
has a value that is not the empty string and matches the pattern
C</^[a-zA-Z]*[0-9]*\z/>, the increment is done as a string, preserving each
character within its range, with carry:

    print ++($foo = "99");      # prints "100"
    print ++($foo = "a0");      # prints "a1"
    print ++($foo = "Az");      # prints "Ba"
    print ++($foo = "zz");      # prints "aaa"

C<undef> is always treated as numeric, and in particular is changed
to C<0> before incrementing (so that a post-increment of an undef value
will return C<0> rather than C<undef>).

The auto-decrement operator is not magical.

=head2 Exponentiation
X<**> X<exponentiation> X<power>

Binary C<"**"> is the exponentiation operator.  It binds even more
tightly than unary minus, so C<-2**4> is C<-(2**4)>, not C<(-2)**4>.
(This is
implemented using C's C<pow(3)> function, which actually works on doubles
internally.)

Note that certain exponentiation expressions are ill-defined:
these include C<0**0>, C<1**Inf>, and C<Inf**0>.  Do not expect
any particular results from these special cases, the results
are platform-dependent.

=head2 Symbolic Unary Operators
X<unary operator> X<operator, unary>

Unary C<"!"> performs logical negation, that is, "not".  See also
L<C<not>|/Logical Not> for a lower precedence version of this.
X<!>

Unary C<"-"> performs arithmetic negation if the operand is numeric,
including any string that looks like a number.  If the operand is
an identifier, a string consisting of a minus sign concatenated
with the identifier is returned.  Otherwise, if the string starts
with a plus or minus, a string starting with the opposite sign is
returned.  One effect of these rules is that C<-bareword> is equivalent
to the string C<"-bareword">.  If, however, the string begins with a
non-alphabetic character (excluding C<"+"> or C<"-">), Perl will attempt
to convert
the string to a numeric, and the arithmetic negation is performed.  If the
string cannot be cleanly converted to a numeric, Perl will give the warning
B<Argument "the string" isn't numeric in negation (-) at ...>.
X<-> X<negation, arithmetic>

Unary C<"~"> performs bitwise negation, that is, 1's complement.  For
example, S<C<0666 & ~027>> is 0640.  (See also L</Integer Arithmetic> and
L</Bitwise String Operators>.)  Note that the width of the result is
platform-dependent: C<~0> is 32 bits wide on a 32-bit platform, but 64
bits wide on a 64-bit platform, so if you are expecting a certain bit
width, remember to use the C<"&"> operator to mask off the excess bits.
X<~> X<negation, binary>

Starting in Perl 5.28, it is a fatal error to try to complement a string
containing a character with an ordinal value above 255.

If the "bitwise" feature is enabled via S<C<use
feature 'bitwise'>> or C<use v5.28>, then unary
C<"~"> always treats its argument as a number, and an
alternate form of the operator, C<"~.">, always treats its argument as a
string.  So C<~0> and C<~"0"> will both give 2**32-1 on 32-bit platforms,
whereas C<~.0> and C<~."0"> will both yield C<"\xff">.  Until Perl 5.28,
this feature produced a warning in the C<"experimental::bitwise"> category.

Unary C<"+"> has no effect whatsoever, even on strings.  It is useful
syntactically for separating a function name from a parenthesized expression
that would otherwise be interpreted as the complete list of function
arguments.  (See examples above under L</Terms and List Operators (Leftward)>.)
X<+>

Unary C<"\"> creates references.  If its operand is a single sigilled
thing, it creates a reference to that object.  If its operand is a
parenthesised list, then it creates references to the things mentioned
in the list.  Otherwise it puts its operand in list context, and creates
a list of references to the scalars in the list provided by the operand.
See L<perlreftut>
and L<perlref>.  Do not confuse this behavior with the behavior of
backslash within a string, although both forms do convey the notion
of protecting the next thing from interpolation.
X<\> X<reference> X<backslash>

=head2 Binding Operators
X<binding> X<operator, binding> X<=~> X<!~>

Binary C<"=~"> binds a scalar expression to a pattern match.  Certain operations
search or modify the string C<$_> by default.  This operator makes that kind
of operation work on some other string.  The right argument is a search
pattern, substitution, or transliteration.  The left argument is what is
supposed to be searched, substituted, or transliterated instead of the default
C<$_>.  When used in scalar context, the return value generally indicates the
success of the operation.  The exceptions are substitution (C<s///>)
and transliteration (C<y///>) with the C</r> (non-destructive) option,
which cause the B<r>eturn value to be the result of the substitution.
Behavior in list context depends on the particular operator.
See L</"Regexp Quote-Like Operators"> for details and L<perlretut> for
examples using these operators.

If the right argument is an expression rather than a search pattern,
substitution, or transliteration, it is interpreted as a search pattern at run
time.  Note that this means that its
contents will be interpolated twice, so

    '\\' =~ q'\\';

is not ok, as the regex engine will end up trying to compile the
pattern C<\>, which it will consider a syntax error.

Binary C<"!~"> is just like C<"=~"> except the return value is negated in
the logical sense.

Binary C<"!~"> with a non-destructive substitution (C<s///r>) or transliteration
(C<y///r>) is a syntax error.

=head2 Multiplicative Operators
X<operator, multiplicative>

Binary C<"*"> multiplies two numbers.
X<*>

Binary C<"/"> divides two numbers.
X</> X<slash>

Binary C<"%"> is the modulo operator, which computes the division
remainder of its first argument with respect to its second argument.
Given integer
operands C<$m> and C<$n>: If C<$n> is positive, then S<C<$m % $n>> is
C<$m> minus the largest multiple of C<$n> less than or equal to
C<$m>.  If C<$n> is negative, then S<C<$m % $n>> is C<$m> minus the
smallest multiple of C<$n> that is not less than C<$m> (that is, the
result will be less than or equal to zero).  If the operands
C<$m> and C<$n> are floating point values and the absolute value of
C<$n> (that is C<abs($n)>) is less than S<C<(UV_MAX + 1)>>, only
the integer portion of C<$m> and C<$n> will be used in the operation
(Note: here C<UV_MAX> means the maximum of the unsigned integer type).
If the absolute value of the right operand (C<abs($n)>) is greater than
or equal to S<C<(UV_MAX + 1)>>, C<"%"> computes the floating-point remainder
C<$r> in the equation S<C<($r = $m - $i*$n)>> where C<$i> is a certain
integer that makes C<$r> have the same sign as the right operand
C<$n> (B<not> as the left operand C<$m> like C function C<fmod()>)
and the absolute value less than that of C<$n>.
Note that when S<C<use integer>> is in scope, C<"%"> gives you direct access
to the modulo operator as implemented by your C compiler.  This
operator is not as well defined for negative operands, but it will
execute faster.
X<%> X<remainder> X<modulo> X<mod>

Binary C<x> is the repetition operator.  In scalar context, or if the
left operand is neither enclosed in parentheses nor a C<qw//> list,
it performs a string repetition.  In that case it supplies scalar
context to the left operand, and returns a string consisting of the
left operand string repeated the number of times specified by the right
operand.  If the C<x> is in list context, and the left operand is either
enclosed in parentheses or a C<qw//> list, it performs a list repetition.
In that case it supplies list context to the left operand, and returns
a list consisting of the left operand list repeated the number of times
specified by the right operand.
If the right operand is zero or negative (raising a warning on
negative), it returns an empty string
or an empty list, depending on the context.
X<x>

    print '-' x 80;             # print row of dashes

    print "\t" x ($tab/8), ' ' x ($tab%8);      # tab over

    @ones = (1) x 80;           # a list of 80 1's
    @ones = (5) x @ones;        # set all elements to 5


=head2 Additive Operators
X<operator, additive>

Binary C<"+"> returns the sum of two numbers.
X<+>

Binary C<"-"> returns the difference of two numbers.
X<->

Binary C<"."> concatenates two strings.
X<string, concatenation> X<concatenation>
X<cat> X<concat> X<concatenate> X<.>

=head2 Shift Operators
X<shift operator> X<operator, shift> X<<< << >>>
X<<< >> >>> X<right shift> X<left shift> X<bitwise shift>
X<shl> X<shr> X<shift, right> X<shift, left>

Binary C<<< "<<" >>> returns the value of its left argument shifted left by the
number of bits specified by the right argument.  Arguments should be
integers.  (See also L</Integer Arithmetic>.)

Binary C<<< ">>" >>> returns the value of its left argument shifted right by
the number of bits specified by the right argument.  Arguments should
be integers.  (See also L</Integer Arithmetic>.)

If S<C<use integer>> (see L</Integer Arithmetic>) is in force then
signed C integers are used (I<arithmetic shift>), otherwise unsigned C
integers are used (I<logical shift>), even for negative shiftees.
In arithmetic right shift the sign bit is replicated on the left,
in logical shift zero bits come in from the left.

Either way, the implementation isn't going to generate results larger
than the size of the integer type Perl was built with (32 bits or 64 bits).

Shifting by a negative number of bits means the reverse shift: left
shift becomes right shift, right shift becomes left shift.  This is
unlike in C, where negative shift is undefined.

Shifting by a value greater than or equal to integer size (in bits)
results in zero (all bits fall off), except that under S<C<use integer>>
right shifting a negative value by such an amount results in -1.
This is unlike in C, where shifting by too many bits is undefined.

If you get tired of being subject to your platform's native integers,
the S<C<use bigint>> pragma neatly sidesteps the issue altogether:

    print 20 << 20;  # 20971520
    print 20 << 32;  # 0 with 32-bit integer,
                     # 85899345920 with 64-bit integer
    use bigint;
    print 20 << 100; # 25353012004564588029934064107520

=head2 Named Unary Operators
X<operator, named unary>

The various named unary operators are treated as functions with one
argument, with optional parentheses.

If any list operator (C<print()>, etc.) or any unary operator (C<chdir()>, etc.)
is followed by a left parenthesis as the next token, the operator and
arguments within parentheses are taken to be of highest precedence,
just like a normal function call.  For example,
because named unary operators are higher precedence than C<||>:

    chdir $foo    || die;       # (chdir $foo) || die
    chdir($foo)   || die;       # (chdir $foo) || die
    chdir ($foo)  || die;       # (chdir $foo) || die
    chdir +($foo) || die;       # (chdir $foo) || die

but, because C<"*"> is higher precedence than named operators:

    chdir $foo * 20;    # chdir ($foo * 20)
    chdir($foo) * 20;   # (chdir $foo) * 20
    chdir ($foo) * 20;  # (chdir $foo) * 20
    chdir +($foo) * 20; # chdir ($foo * 20)

    rand 10 * 20;       # rand (10 * 20)
    rand(10) * 20;      # (rand 10) * 20
    rand (10) * 20;     # (rand 10) * 20
    rand +(10) * 20;    # rand (10 * 20)

Regarding precedence, the filetest operators, like C<-f>, C<-M>, etc. are
treated like named unary operators, but they don't follow this functional
parenthesis rule.  That means, for example, that C<-f($file).".bak"> is
equivalent to S<C<-f "$file.bak">>.
X<-X> X<filetest> X<operator, filetest>

See also L</"Terms and List Operators (Leftward)">.

=head2 Class Instance Operator
X<isa operator>

Binary C<isa> evaluates to true when the left argument is an object instance of
the class (or a subclass derived from that class) given by the right argument.
If the left argument is not defined, not a blessed object instance, and does
not derive from the class given by the right argument, the operator evaluates
as false. The right argument may give the class either as a bareword or a
scalar expression that yields a string class name:

    if ( $obj isa Some::Class ) { ... }

    if ( $obj isa "Different::Class" ) { ... }
    if ( $obj isa $name_of_class ) { ... }

This feature is available from Perl 5.31.6 onwards when enabled by
C<use feature 'isa'>. This feature is enabled automatically by a
C<use v5.36> (or higher) declaration in the current scope.

=head2 Relational Operators
X<relational operator> X<operator, relational>

Perl operators that return true or false generally return values
that can be safely used as numbers.  For example, the relational
operators in this section and the equality operators in the next
one return C<1> for true and a special version of the defined empty
string, C<"">, which counts as a zero but is exempt from warnings
about improper numeric conversions, just as S<C<"0 but true">> is.

Binary C<< "<" >> returns true if the left argument is numerically less than
the right argument.
X<< < >>

Binary C<< ">" >> returns true if the left argument is numerically greater
than the right argument.
X<< > >>

Binary C<< "<=" >> returns true if the left argument is numerically less than
or equal to the right argument.
X<< <= >>

Binary C<< ">=" >> returns true if the left argument is numerically greater
than or equal to the right argument.
X<< >= >>

Binary C<"lt"> returns true if the left argument is stringwise less than
the right argument.
X<< lt >>

Binary C<"gt"> returns true if the left argument is stringwise greater
than the right argument.
X<< gt >>

Binary C<"le"> returns true if the left argument is stringwise less than
or equal to the right argument.
X<< le >>

Binary C<"ge"> returns true if the left argument is stringwise greater
than or equal to the right argument.
X<< ge >>

A sequence of relational operators, such as S<C<"$x E<lt> $y E<lt>=
$z">>, performs chained comparisons, in the manner described above in
the section L</"Operator Precedence and Associativity">.
Beware that they do not chain with equality operators, which have lower
precedence.

C<"lt">, C<"le">, C<"ge">, C<"gt">, and C<"cmp"> (this last is described
in the L<next section|/Equality Operators>) use the collation (sort)
order specified by the current C<LC_COLLATE> locale if a S<C<use
locale>> form that includes collation is in effect.  See L<perllocale>.
Depending on the capabilities of the platform, these can give reasonable
results with Unicode, but the standard C<L<Unicode::Collate>> and
C<L<Unicode::Collate::Locale>> modules offer much more powerful
solutions to collation issues.

For case-insensitive comparisons, look at the L<perlfunc/fc> case-folding
function, available in Perl v5.16 or later:

    if ( fc($x) eq fc($y) ) { ... }

=head2 Equality Operators
X<equality> X<equal> X<equals> X<operator, equality>

Binary C<< "==" >> returns true if the left argument is numerically equal to
the right argument.
X<==>

Binary C<< "!=" >> returns true if the left argument is numerically not equal
to the right argument.
X<!=>

Binary C<"eq"> returns true if the left argument is stringwise equal to
the right argument.
X<eq>

Binary C<"ne"> returns true if the left argument is stringwise not equal
to the right argument.
X<ne>

A sequence of the above equality operators, such as S<C<"$x == $y ==
$z">>, performs chained comparisons, in the manner described above in
the section L</"Operator Precedence and Associativity">.
Beware that they do not chain with relational operators, which have
higher precedence.

Binary C<< "<=>" >> returns -1, 0, or 1 depending on whether the left
argument is numerically less than, equal to, or greater than the right
argument.  If your platform supports C<NaN>'s (not-a-numbers) as numeric
values, using them with C<< "<=>" >> returns undef.  C<NaN> is not
C<< "<" >>, C<< "==" >>, C<< ">" >>, C<< "<=" >> or C<< ">=" >> anything
(even C<NaN>), so those 5 return false.  S<C<< NaN != NaN >>> returns
true, as does S<C<NaN !=> I<anything else>>.  If your platform doesn't
support C<NaN>'s then C<NaN> is just a string with numeric value 0.
X<< <=> >>
X<spaceship>

    $ perl -le '$x = "NaN"; print "No NaN support here" if $x == $x'
    $ perl -le '$x = "NaN"; print "NaN support here" if $x != $x'

(Note that the L<bigint>, L<bigrat>, and L<bignum> pragmas all
support C<"NaN">.)

Binary C<"cmp"> returns -1, 0, or 1 depending on whether the left
argument is stringwise less than, equal to, or greater than the right
argument.

Here we can see the difference between C<< <=> >> and C<cmp>,

    print 10 <=> 2 #prints 1
    print 10 cmp 2 #prints -1

X<cmp>
(likewise between the relational operators that were described in the
L<previous section|/Relational Operators>: C<gt> and C<< > >>, C<lt> and
C<< < >>, I<etc>.)

Binary C<"~~"> does a smartmatch between its arguments.  Smart matching
is complicated enough to warrant
L<two subsections|/Smartmatch Operator>, starting just below.
X<~~>

The two-sided ordering operators C<"E<lt>=E<gt>"> and C<"cmp">, and the
smartmatch operator C<"~~">, are non-associative with respect to each
other and with respect to the equality operators of the same precedence.

=head3 Smartmatch Operator

The C<smartmatch> feature is discouraged for new code and retained for
backward compatibility.

The smartmatch operator was introduced in 5.10.0 had significant
changes in 5.10.1.  It is enabled by default and in all feature
bundles up to 5.40.  To use smartmatch with a later feature bundle you
will need enable it explicitly:

  use v5.42;
  use feature "smartmatch";

Binary C<~~> does a "smartmatch" between its arguments.  This is mostly
used implicitly in the C<when> construct described in L<perlsyn>, although
not all C<when> clauses call the smartmatch operator.  Unique among all of
Perl's operators, the smartmatch operator can recurse.

It is also unique in that all other Perl operators impose a context
(usually string or numeric context) on their operands, autoconverting
those operands to those imposed contexts.  In contrast, smartmatch
I<infers> contexts from the actual types of its operands and uses that
type information to select a suitable comparison mechanism.

The C<~~> operator compares its operands "polymorphically", determining how
to compare them according to their actual types (numeric, string, array,
hash, etc.).  Like the equality operators with which it shares the same
precedence, C<~~> returns 1 for true and C<""> for false.  It is often best
read aloud as "in", "inside of", or "is contained in", because the left
operand is often looked for I<inside> the right operand.  That makes the
order of the operands to the smartmatch operand often opposite that of
the regular match operator.  In other words, the "smaller" thing is usually
placed in the left operand and the larger one in the right.

The behavior of a smartmatch depends on what type of things its arguments
are, as determined by the following table.  The first row of the table
whose types apply determines the smartmatch behavior.  Because what
actually happens is mostly determined by the type of the second operand,
the table is sorted on the right operand instead of on the left.

 Left      Right      Description and pseudocode
 ===============================================================
 Any       undef      check whether Any is undefined
                like: !defined Any

 Any       Object     invoke ~~ overloading on Object, or die

 Right operand is an ARRAY:

 Left      Right      Description and pseudocode
 ===============================================================
 ARRAY1    ARRAY2     recurse on paired elements of ARRAY1 and ARRAY2[2]
                like: (ARRAY1[0] ~~ ARRAY2[0])
                        && (ARRAY1[1] ~~ ARRAY2[1]) && ...
 HASH      ARRAY      any ARRAY elements exist as HASH keys
                like: grep { exists HASH->{$_} } ARRAY
 Regexp    ARRAY      any ARRAY elements pattern match Regexp
                like: grep { /Regexp/ } ARRAY
 undef     ARRAY      undef in ARRAY
                like: grep { !defined } ARRAY
 Any       ARRAY      smartmatch each ARRAY element[3]
                like: grep { Any ~~ $_ } ARRAY

 Right operand is a HASH:

 Left      Right      Description and pseudocode
 ===============================================================
 HASH1     HASH2      all same keys in both HASHes
                like: keys HASH1 ==
                         grep { exists HASH2->{$_} } keys HASH1
 ARRAY     HASH       any ARRAY elements exist as HASH keys
                like: grep { exists HASH->{$_} } ARRAY
 Regexp    HASH       any HASH keys pattern match Regexp
                like: grep { /Regexp/ } keys HASH
 undef     HASH       always false (undef cannot be a key)
                like: 0 == 1
 Any       HASH       HASH key existence
                like: exists HASH->{Any}

 Right operand is CODE:

 Left      Right      Description and pseudocode
 ===============================================================
 ARRAY     CODE       sub returns true on all ARRAY elements[1]
                like: !grep { !CODE->($_) } ARRAY
 HASH      CODE       sub returns true on all HASH keys[1]
                like: !grep { !CODE->($_) } keys HASH
 Any       CODE       sub passed Any returns true
                like: CODE->(Any)

 Right operand is a Regexp:

 Left      Right      Description and pseudocode
 ===============================================================
 ARRAY     Regexp     any ARRAY elements match Regexp
                like: grep { /Regexp/ } ARRAY
 HASH      Regexp     any HASH keys match Regexp
                like: grep { /Regexp/ } keys HASH
 Any       Regexp     pattern match
                like: Any =~ /Regexp/

 Other:

 Left      Right      Description and pseudocode
 ===============================================================
 Object    Any        invoke ~~ overloading on Object,
                      or fall back to...

 Any       Num        numeric equality
                 like: Any == Num
 Num       nummy[4]    numeric equality
                 like: Num == nummy
 undef     Any        check whether undefined
                 like: !defined(Any)
 Any       Any        string equality
                 like: Any eq Any


Notes:

=over

=item 1.
Empty hashes or arrays match.

=item 2.
That is, each element smartmatches the element of the same index in the other array.[3]

=item 3.
If a circular reference is found, fall back to referential equality.

=item 4.
Either an actual number, or a string that looks like one.

=back

The smartmatch implicitly dereferences any non-blessed hash or array
reference, so the C<I<HASH>> and C<I<ARRAY>> entries apply in those cases.
For blessed references, the C<I<Object>> entries apply.  Smartmatches
involving hashes only consider hash keys, never hash values.

The "like" code entry is not always an exact rendition.  For example, the
smartmatch operator short-circuits whenever possible, but C<grep> does
not.  Also, C<grep> in scalar context returns the number of matches, but
C<~~> returns only true or false.

Unlike most operators, the smartmatch operator knows to treat C<undef>
specially:

    use v5.10.1;
    @array = (1, 2, 3, undef, 4, 5);
    say "some elements undefined" if undef ~~ @array;

Each operand is considered in a modified scalar context, the modification
being that array and hash variables are passed by reference to the
operator, which implicitly dereferences them.  Both elements
of each pair are the same:

    use v5.10.1;

    my %hash = (red    => 1, blue   => 2, green  => 3,
                orange => 4, yellow => 5, purple => 6,
                black  => 7, grey   => 8, white  => 9);

    my @array = qw(red blue green);

    say "some array elements in hash keys" if  @array ~~  %hash;
    say "some array elements in hash keys" if \@array ~~ \%hash;

    say "red in array" if "red" ~~  @array;
    say "red in array" if "red" ~~ \@array;

    say "some keys end in e" if /e$/ ~~  %hash;
    say "some keys end in e" if /e$/ ~~ \%hash;

Two arrays smartmatch if each element in the first array smartmatches
(that is, is "in") the corresponding element in the second array,
recursively.

    use v5.10.1;
    my @little = qw(red blue green);
    my @bigger = ("red", "blue", [ "orange", "green" ] );
    if (@little ~~ @bigger) {  # true!
        say "little is contained in bigger";
    }

Because the smartmatch operator recurses on nested arrays, this
will still report that "red" is in the array.

    use v5.10.1;
    my @array = qw(red blue green);
    my $nested_array = [[[[[[[ @array ]]]]]]];
    say "red in array" if "red" ~~ $nested_array;

If two arrays smartmatch each other, then they are deep
copies of each others' values, as this example reports:

    use v5.12.0;
    my @a = (0, 1, 2, [3, [4, 5], 6], 7);
    my @b = (0, 1, 2, [3, [4, 5], 6], 7);

    if (@a ~~ @b && @b ~~ @a) {
        say "a and b are deep copies of each other";
    }
    elsif (@a ~~ @b) {
        say "a smartmatches in b";
    }
    elsif (@b ~~ @a) {
        say "b smartmatches in a";
    }
    else {
        say "a and b don't smartmatch each other at all";
    }


If you were to set S<C<$b[3] = 4>>, then instead of reporting that "a and b
are deep copies of each other", it now reports that C<"b smartmatches in a">.
That's because the corresponding position in C<@a> contains an array that
(eventually) has a 4 in it.

Smartmatching one hash against another reports whether both contain the
same keys, no more and no less.  This could be used to see whether two
records have the same field names, without caring what values those fields
might have.  For example:

    use v5.10.1;
    sub make_dogtag {
        state $REQUIRED_FIELDS = { name=>1, rank=>1, serial_num=>1 };

        my ($class, $init_fields) = @_;

        die "Must supply (only) name, rank, and serial number"
            unless $init_fields ~~ $REQUIRED_FIELDS;

        ...
    }

However, this only does what you mean if C<$init_fields> is indeed a hash
reference. The condition C<$init_fields ~~ $REQUIRED_FIELDS> also allows the
strings C<"name">, C<"rank">, C<"serial_num"> as well as any array reference
that contains C<"name"> or C<"rank"> or C<"serial_num"> anywhere to pass
through.

The smartmatch operator is most often used as the implicit operator of a
C<when> clause.  See the section on "Switch Statements" in L<perlsyn>.

=head3 Smartmatching of Objects

To avoid relying on an object's underlying representation, if the
smartmatch's right operand is an object that doesn't overload C<~~>,
it raises the exception "C<Smartmatching a non-overloaded object
breaks encapsulation>".  That's because one has no business digging
around to see whether something is "in" an object.  These are all
illegal on objects without a C<~~> overload:

    %hash ~~ $object
       42 ~~ $object
   "fred" ~~ $object

However, you can change the way an object is smartmatched by overloading
the C<~~> operator.  This is allowed to
extend the usual smartmatch semantics.
For objects that do have an C<~~> overload, see L<overload>.

Using an object as the left operand is allowed, although not very useful.
Smartmatching rules take precedence over overloading, so even if the
object in the left operand has smartmatch overloading, this will be
ignored.  A left operand that is a non-overloaded object falls back on a
string or numeric comparison of whatever the C<ref> operator returns.  That
means that

    $object ~~ X

does I<not> invoke the overload method with C<I<X>> as an argument.
Instead the above table is consulted as normal, and based on the type of
C<I<X>>, overloading may or may not be invoked.  For simple strings or
numbers, "in" becomes equivalent to this:

    $object ~~ $number          ref($object) == $number
    $object ~~ $string          ref($object) eq $string

For example, this reports that the handle smells IOish
(but please don't really do this!):

    use IO::Handle;
    my $fh = IO::Handle->new();
    if ($fh ~~ /\bIO\b/) {
        say "handle smells IOish";
    }

That's because it treats C<$fh> as a string like
C<"IO::Handle=GLOB(0x8039e0)">, then pattern matches against that.

=head2 Bitwise And
X<operator, bitwise, and> X<bitwise and> X<&>

Binary C<"&"> returns its operands ANDed together bit by bit.  Although no
warning is currently raised, the result is not well defined when this operation
is performed on operands that aren't either numbers (see
L</Integer Arithmetic>) nor bitstrings (see L</Bitwise String Operators>).

Note that C<"&"> has lower priority than relational operators, so for example
the parentheses are essential in a test like

    print "Even\n" if ($x & 1) == 0;

If the "bitwise" feature is enabled via S<C<use feature 'bitwise'>> or
C<use v5.28>, then this operator always treats its operands as numbers.
Before Perl 5.28 this feature produced a warning in the
C<"experimental::bitwise"> category.

=head2 Bitwise Or and Exclusive Or
X<operator, bitwise, or> X<bitwise or> X<|> X<operator, bitwise, xor>
X<bitwise xor> X<^>

Binary C<"|"> returns its operands ORed together bit by bit.  If both
corresponding bits are 0, the resulting bit is 0; if either is 1, the result is
1.

Binary C<"^"> returns its operands XORed together bit by bit.  If both
corresponding bits are 0 or both are 1, the resulting bit is 0; if just
one is 1, the result is 1.

Although no warning is currently raised, the results are not well
defined when these operations are performed on operands that aren't either
numbers (see L</Integer Arithmetic>) nor bitstrings (see L</Bitwise String
Operators>).

Note that C<"|"> and C<"^"> have lower priority than relational operators, so
for example the parentheses are essential in a test like

    print "false\n" if (8 | 2) != 10;

If the "bitwise" feature is enabled via S<C<use feature 'bitwise'>> or
C<use v5.28>, then this operator always treats its operands as numbers.
Before Perl 5.28. this feature produced a warning in the
C<"experimental::bitwise"> category.

=head2 C-style Logical And
X<&&> X<logical and> X<operator, logical, and>

Binary C<"&&"> performs a short-circuit logical AND operation.  That is,
if the left operand is false, the right operand is not even evaluated.
Scalar or list context propagates down to the right operand if it
is evaluated.

C<&&> returns the last value evaluated (unlike C's C<&&>, which returns
0 or 1).

As an alternative to C<&&> when used for control flow, Perl provides the
C<and> operator (see L<below|/Logical And>).
The short-circuit behavior is identical.  The precedence of C<"and"> is
much lower, however, so that you can safely use it after a list operator
without the need for parentheses.

=head2 C-style Logical Or, Xor, and Defined Or
X<||> X<operator, logical, or>
X<^^> X<operator, logical, xor>
X<//> X<operator, logical, defined-or>
X<//> X<operator, logical, dor>

Binary C<"||"> performs a short-circuit logical OR operation.  That is,
if the left operand is true, the right operand is not even evaluated.
Scalar or list context propagates down to the right operand if it
does get evaluated.

As an alternative to C<||> when used for control flow, Perl provides the
C<or> operator (L<see below|/Logical or and Exclusive Or>).
The short-circuit behavior is identical.  The precedence of C<"or"> is
much lower, however, so that you can safely use it after a list operator
without the need for parentheses:

    unlink "alpha", "beta", "gamma"
            or gripe(), next LINE;

With the C-style operator that would have been written like this:

    unlink("alpha", "beta", "gamma")
            || (gripe(), next LINE);

It would be even more readable to write that this way:

    unless(unlink("alpha", "beta", "gamma")) {
        gripe();
        next LINE;
    }

Using C<"or"> for assignment is unlikely to do what you want; see below.

Binary C<"^^"> performs a logical XOR operation.  Both operands are
evaluated and the result is true only if exactly one of the operands is true.
Scalar or list context propagates down to the right operand.

Although it has no direct equivalent in C, Perl's C<//> operator is related
to its C-style "or".  In fact, it's exactly the same as C<||>, except that it
tests the left hand side's definedness instead of its truth.  Thus,
S<C<< EXPR1 // EXPR2 >>> returns the value of C<< EXPR1 >> if it's defined,
otherwise, the value of C<< EXPR2 >> is returned.
(C<< EXPR1 >> is evaluated in scalar context, C<< EXPR2 >>
in the context of C<< // >> itself).  Usually,
this is the same result as S<C<< defined(EXPR1) ? EXPR1 : EXPR2 >>> (except that
the ternary-operator form can be used as a lvalue, while S<C<< EXPR1 // EXPR2 >>>
cannot).  This is very useful for
providing default values for variables.  If you actually want to test if
at least one of C<$x> and C<$y> is defined, use S<C<defined($x // $y)>>.

The C<||> and C<//> operators return the last value evaluated
(unlike C's C<||> which returns 0 or 1).  Thus, a reasonably
portable way to find out the home directory might be:

    $home =  $ENV{HOME}
          // $ENV{LOGDIR}
          // (getpwuid($<))[7]
          // die "You're homeless!\n";

In particular, this means that you shouldn't use this
for selecting between two aggregates for assignment:

    @a = @b || @c;            # This doesn't do the right thing
    @a = scalar(@b) || @c;    # because it really means this.
    @a = @b ? @b : @c;        # This works fine, though.

=head2 Range Operators
X<operator, range> X<range> X<..> X<...>

Binary C<".."> is the range operator, which is really two different
operators depending on the context.  In list context, it returns a
list of values counting (up by ones) from the left value to the right
value.  If the left value is greater than the right value then it
returns the empty list.  The range operator is useful for writing
S<C<foreach (1..10)>> loops and for doing slice operations on arrays.
No temporary array is created when the range operator is used as the
expression in C<foreach> loops.

The range operator also works on strings, using the magical
auto-increment, see below.

In scalar context, C<".."> returns a boolean value.  The operator is
bistable, like a flip-flop, and emulates the line-range (comma)
operator of B<sed>, B<awk>, and various editors.  Each C<".."> operator
maintains its own boolean state, even across calls to a subroutine
that contains it.  It is false as long as its left operand is false.
Once the left operand is true, the range operator stays true until the
right operand is true, I<AFTER> which the range operator becomes false
again.  It doesn't become false till the next time the range operator
is evaluated.  It can test the right operand and become false on the
same evaluation it became true (as in B<awk>), but it still returns
true once.  If you don't want it to test the right operand until the
next evaluation, as in B<sed>, just use three dots (C<"...">) instead of
two.  In all other regards, C<"..."> behaves just like C<".."> does.

The right operand is not evaluated while the operator is in the
"false" state, and the left operand is not evaluated while the
operator is in the "true" state.  The precedence is a little lower
than || and &&.  The value returned is either the empty string for
false, or a sequence number (beginning with 1) for true.  The sequence
number is reset for each range encountered.  The final sequence number
in a range has the string C<"E0"> appended to it, which doesn't affect
its numeric value, but gives you something to search for if you want
to exclude the endpoint.  You can exclude the beginning point by
waiting for the sequence number to be greater than 1.

If either operand of scalar C<".."> is a constant expression,
that operand is considered true if it is equal (C<==>) to the current
input line number (the C<$.> variable).

To be pedantic, the comparison is actually S<C<int(EXPR) == int(EXPR)>>,
but that is only an issue if you use a floating point expression; when
implicitly using C<$.> as described in the previous paragraph, the
comparison is S<C<int(EXPR) == int($.)>> which is only an issue when C<$.>
is set to a floating point value and you are not reading from a file.
Furthermore, S<C<"span" .. "spat">> or S<C<2.18 .. 3.14>> will not do what
you want in scalar context because each of the operands are evaluated
using their integer representation.

Examples:

As a scalar operator:

    if (101 .. 200) { print; } # print 2nd hundred lines, short for
                               #  if ($. == 101 .. $. == 200) { print; }

    next LINE if 1 .. /^$/;    # skip header lines, short for
                               #   next LINE if $. == 1 .. /^$/;
                               # (typically in a loop labeled LINE)

    s/^/> / if /^$/ .. eof();  # quote body

    # parse mail messages
    while (<>) {
        $in_header =   1  .. /^$/;
        $in_body   = /^$/ .. eof;
        if ($in_header) {
            # do something
        } else { # in body
            # do something else
        }
    } continue {
        close ARGV if eof;             # reset $. each file
    }

Here's a simple example to illustrate the difference between
the two range operators:

    @lines = ("   - Foo",
              "01 - Bar",
              "1  - Baz",
              "   - Quux");

    foreach (@lines) {
        if (/0/ .. /1/) {
            print "$_\n";
        }
    }

This program will print only the line containing "Bar".  If
the range operator is changed to C<...>, it will also print the
"Baz" line.

And now some examples as a list operator:

    for (101 .. 200) { print }      # print $_ 100 times
    @foo = @foo[0 .. $#foo];        # an expensive no-op
    @foo = @foo[$#foo-4 .. $#foo];  # slice last 5 items

Because each operand is evaluated in integer form, S<C<2.18 .. 3.14>> will
return two elements in list context.

    @list = (2.18 .. 3.14); # same as @list = (2 .. 3);

The range operator in list context can make use of the magical
auto-increment algorithm if both operands are strings, subject to the
following rules:

=over

=item *

With one exception (below), if both strings look like numbers to Perl,
the magic increment will not be applied, and the strings will be treated
as numbers (more specifically, integers) instead.

For example, C<"-2".."2"> is the same as C<-2..2>, and
C<"2.18".."3.14"> produces C<2, 3>.

=item *

The exception to the above rule is when the left-hand string begins with
C<0> and is longer than one character, in this case the magic increment
I<will> be applied, even though strings like C<"01"> would normally look
like a number to Perl.

For example, C<"01".."04"> produces C<"01", "02", "03", "04">, and
C<"00".."-1"> produces C<"00"> through C<"99"> - this may seem
surprising, but see the following rules for why it works this way.
To get dates with leading zeros, you can say:

    @z2 = ("01" .. "31");
    print $z2[$mday];

If you want to force strings to be interpreted as numbers, you could say

    @numbers = ( 0+$first .. 0+$last );

B<Note:> In Perl versions 5.30 and below, I<any> string on the left-hand
side beginning with C<"0">, including the string C<"0"> itself, would
cause the magic string increment behavior. This means that on these Perl
versions, C<"0".."-1"> would produce C<"0"> through C<"99">, which was
inconsistent with C<0..-1>, which produces the empty list. This also means
that C<"0".."9"> now produces a list of integers instead of a list of
strings.

=item *

If the initial value specified isn't part of a magical increment
sequence (that is, a non-empty string matching C</^[a-zA-Z]*[0-9]*\z/>),
only the initial value will be returned.

For example, C<"ax".."az"> produces C<"ax", "ay", "az">, but
C<"*x".."az"> produces only C<"*x">.

=item *

For other initial values that are strings that do follow the rules of the
magical increment, the corresponding sequence will be returned.

For example, you can say

    @alphabet = ("A" .. "Z");

to get all normal letters of the English alphabet, or

    $hexdigit = (0 .. 9, "a" .. "f")[$num & 15];

to get a hexadecimal digit.

=item *

If the final value specified is not in the sequence that the magical
increment would produce, the sequence goes until the next value would
be longer than the final value specified. If the length of the final
string is shorter than the first, the empty list is returned.

For example, C<"a".."--"> is the same as C<"a".."zz">, C<"0".."xx">
produces C<"0"> through C<"99">, and C<"aaa".."--"> returns the empty
list.

=back

As of Perl 5.26, the list-context range operator on strings works as expected
in the scope of L<< S<C<"use feature 'unicode_strings'">>|feature/The
'unicode_strings' feature >>. In previous versions, and outside the scope of
that feature, it exhibits L<perlunicode/The "Unicode Bug">: its behavior
depends on the internal encoding of the range endpoint.

Because the magical increment only works on non-empty strings matching
C</^[a-zA-Z]*[0-9]*\z/>, the following will only return an alpha:

    use charnames "greek";
    my @greek_small =  ("\N{alpha}" .. "\N{omega}");

To get the 25 traditional lowercase Greek letters, including both sigmas,
you could use this instead:

    use charnames "greek";
    my @greek_small =  map { chr } ( ord("\N{alpha}")
                                        ..
                                     ord("\N{omega}")
                                   );

However, because there are I<many> other lowercase Greek characters than
just those, to match lowercase Greek characters in a regular expression,
you could use the pattern C</(?:(?=\p{Greek})\p{Lower})+/> (or the
L<experimental feature|perlrecharclass/Extended Bracketed Character
Classes> C<S</(?[ \p{Greek} & \p{Lower} ])+/>>).

=head2 Conditional Operator
X<operator, conditional> X<operator, ternary> X<ternary> X<?:>

Ternary C<"?:"> is the conditional operator, just as in C.  It works much
like an if-then-else.  If the argument before the C<?> is true, the
argument before the C<:> is returned, otherwise the argument after the
C<:> is returned.  For example:

    printf "I have %d dog%s.\n", $n,
            ($n == 1) ? "" : "s";

Scalar or list context propagates downward into the 2nd
or 3rd argument, whichever is selected.

    $x = $ok ? $y : $z;  # get a scalar
    @x = $ok ? @y : @z;  # get an array
    $x = $ok ? @y : @z;  # oops, that's just a count!

The operator may be assigned to if both the 2nd and 3rd arguments are
legal lvalues (meaning that you can assign to them):

    ($x_or_y ? $x : $y) = $z;

Because this operator produces an assignable result, using assignments
without parentheses will get you in trouble.  For example, this:

    $x % 2 ? $x += 10 : $x += 2

Really means this:

    (($x % 2) ? ($x += 10) : $x) += 2

Rather than this:

    ($x % 2) ? ($x += 10) : ($x += 2)

That should probably be written more simply as:

    $x += ($x % 2) ? 10 : 2;

=head2 Assignment Operators
X<assignment> X<operator, assignment> X<=> X<**=> X<+=> X<*=> X<&=>
X<<< <<= >>> X<&&=> X<-=> X</=> X<|=> X<<< >>= >>> X<||=> X<//=> X<.=>
X<%=> X<^=> X<x=> X<&.=> X<|.=> X<^.=> X<^^=>

C<"="> is the ordinary assignment operator.

Assignment operators work as in C.  That is,

    $x += 2;

is equivalent to

    $x = $x + 2;

although without duplicating any side effects that dereferencing the lvalue
might trigger, such as from C<tie()>.  Other assignment operators work similarly.
The following are recognized:

    **=    +=    *=    &=    &.=    <<=    &&=
           -=    /=    |=    |.=    >>=    ||=
           .=    %=    ^=    ^.=           //=
                 x=                        ^^=

Although these are grouped by family, they all have the precedence
of assignment.  These combined assignment operators can only operate on
scalars, whereas the ordinary assignment operator can assign to arrays,
hashes, lists and even references.  (See L<"Context"|perldata/Context>
and L<perldata/List value constructors>, and L<perlref/Assigning to
References>.)

The scalar assignment operator returns its left operand, i.e. the scalar
assigned to.  Unlike in C, it produces a valid lvalue.
Modifying an assignment is equivalent to doing the assignment and
then modifying the variable that was assigned to.  This is useful
for modifying a copy of something, like this:

    ($tmp = $global) =~ tr/13579/24680/;

Although as of 5.14, that can be also be accomplished this way:

    use v5.14;
    $tmp = ($global =~  tr/13579/24680/r);

Likewise,

    ($x += 2) *= 3;

is equivalent to

    $x += 2;
    $x *= 3;

Similarly, a list assignment in list context produces the list of
lvalues assigned to, and a list assignment in scalar context returns
the number of elements produced by the expression on the right hand
side of the assignment.

The three dotted bitwise assignment operators (C<&.=> C<|.=> C<^.=>) are new in
Perl 5.22.  See L</Bitwise String Operators>.

=head2 Comma Operator
X<comma> X<operator, comma> X<,>

Binary C<","> is the comma operator.  In scalar context it evaluates
its left argument, throws that value away, then evaluates its right
argument and returns that value.  This is just like C's comma operator.

In list context, it's just the list argument separator, and inserts
both its arguments into the list.  These arguments are also evaluated
from left to right.

The C<< => >> operator (sometimes pronounced "fat comma") is a synonym
for the comma except that it causes a
word on its left to be interpreted as a string if it begins with a letter
or underscore and is composed only of letters, digits and underscores.
This includes operands that might otherwise be interpreted as operators,
constants, single number v-strings or function calls.  If in doubt about
this behavior, the left operand can be quoted explicitly.

Otherwise, the C<< => >> operator behaves exactly as the comma operator
or list argument separator, according to context.

For example:

    use constant FOO => "something";

    my %h = ( FOO => 23 );

is equivalent to:

    my %h = ("FOO", 23);

It is I<NOT>:

    my %h = ("something", 23);

The C<< => >> operator is helpful in documenting the correspondence
between keys and values in hashes, and other paired elements in lists.

    %hash = ( $key => $value );
    login( $username => $password );

The special quoting behavior ignores precedence, and hence may apply to
I<part> of the left operand:

    print time.shift => "bbb";

That example prints something like C<"1314363215shiftbbb">, because the
C<< => >> implicitly quotes the C<shift> immediately on its left, ignoring
the fact that C<time.shift> is the entire left operand.

=head2 List Operators (Rightward)
X<operator, list, rightward> X<list operator>

On the right side of a list operator, the comma has very low precedence,
such that it controls all comma-separated expressions found there.
The only operators with lower precedence are the logical operators
C<"and">, C<"or">, and C<"not">, which may be used to evaluate calls to list
operators without the need for parentheses:

    open HANDLE, "< :encoding(UTF-8)", "filename"
        or die "Can't open: $!\n";

However, some people find that code harder to read than writing
it with parentheses:

    open(HANDLE, "< :encoding(UTF-8)", "filename")
        or die "Can't open: $!\n";

in which case you might as well just use the more customary C<"||"> operator:

    open(HANDLE, "< :encoding(UTF-8)", "filename")
        || die "Can't open: $!\n";

See also discussion of list operators in L</Terms and List Operators (Leftward)>.

=head2 Logical Not
X<operator, logical, not> X<not>

Unary C<"not"> returns the logical negation of the expression to its right.
It's the equivalent of C<"!"> except for the very low precedence.

=head2 Logical And
X<operator, logical, and> X<and>

Binary C<"and"> returns the logical conjunction of the two surrounding
expressions.  It's equivalent to C<&&> except for the very low
precedence.  This means that it short-circuits: the right
expression is evaluated only if the left expression is true.

=head2 Logical or and Exclusive Or
X<operator, logical, or> X<or>
X<operator, logical, xor> X<operator, logical, exclusive or> X<xor>

There is no low precedence operator for defined-OR.

Binary C<"or"> returns the logical inclusive disjunction of the two
surrounding expressions.  It's equivalent to C<||> except for it having
very low precedence.  This makes it useful for control flow:

    print FH $data              or die "Can't write to FH: $!";

This means that it short-circuits: the right expression is evaluated
only if the left expression is false.  Due to its precedence, you must
be careful to avoid using it as replacement for the C<||> operator.
It usually works out better for flow control than in assignments:

    $x = $y or $z;              # bug: this is wrong
    ($x = $y) or $z;            # really means this
    $x = $y || $z;              # better written this way

However, when it's a list-context assignment and you're trying to use
C<||> for control flow, you probably need C<"or"> so that the assignment
takes higher precedence.

    @info = stat($file) || die;     # oops, scalar sense of stat!
    @info = stat($file) or die;     # better, now @info gets its due

Then again, you could always use parentheses.

Binary C<"xor"> returns the logical exclusive disjunction of the two
surrounding expressions.  That means it returns C<true> if either, but
not both, are true.  It's equivalent to C<^^> except for it having very
low precedence.  It cannot short-circuit (of course).  It tends to be
used to verify that two mutually-exclusive conditions are actually
mutually exclusive.  For example, in Perl's test suite, we might want to
test that a regular expression pattern can't both match and not match,
for otherwise it would be a bug in our pattern matching code.

 ($x =~ qr/$pat/ xor $x !~ qr/$pat/) or die;

=head2 C Operators Missing From Perl
X<operator, missing from perl> X<&> X<*>
X<typecasting> X<(TYPE)>

Here is what C has that Perl doesn't:

=over 8

=item unary &

Address-of operator.  (But see the C<"\"> operator for taking a reference.)

=item unary *

Dereference-address operator.  (Perl's prefix dereferencing
operators are typed: C<$>, C<@>, C<%>, and C<&>.)

=item (TYPE)

Type-casting operator.

=back

=head2 Quote and Quote-like Operators
X<operator, quote> X<operator, quote-like> X<q> X<qq> X<qx> X<qw> X<m>
X<qr> X<s> X<tr> X<'> X<''> X<"> X<""> X<//> X<`> X<``> X<<< << >>>
X<escape sequence> X<escape>

While we usually think of quotes as literal values, in Perl they
function as operators, providing various kinds of interpolating and
pattern matching capabilities.  Perl provides customary quote characters
for these behaviors, but also provides a way for you to choose your
quote character for any of them.  In the following table, a C<{}> represents
any pair of delimiters you choose.

    Customary  Generic        Meaning        Interpolates
        ''       q{}          Literal             no
        ""      qq{}          Literal             yes
        ``      qx{}          Command             yes*
                qw{}         Word list            no
        //       m{}       Pattern match          yes*
                qr{}          Pattern             yes*
                 s{}{}      Substitution          yes*
                tr{}{}    Transliteration         no (but see below)
                 y{}{}    Transliteration         no (but see below)
        <<EOF                 here-doc            yes*

        * unless the delimiter is ''.

Non-bracketing delimiters use the same character fore and aft, but the four
sorts of ASCII brackets (round, angle, square, curly) all nest, which means
that

    q{foo{bar}baz}

is the same as

    'foo{bar}baz'

Note, however, that this does not always work for quoting Perl code:

    $s = q{ if ($x eq "}") ... }; # WRONG

is a syntax error.  The C<L<Text::Balanced>> module (standard as of v5.8,
and from CPAN before then) is able to do this properly.

If the C<extra_paired_delimiters> feature is enabled, then Perl will
additionally recognise a variety of Unicode characters as being paired. For
a full list, see the L</List of Extra Paired Delimiters> at the end of this
document.

There can (and in some cases, must) be whitespace between the operator
and the quoting
characters, except when C<#> is being used as the quoting character.
C<q#foo#> is parsed as the string C<foo>, while S<C<q #foo#>> is the
operator C<q> followed by a comment.  Its argument will be taken
from the next line.  This allows you to write:

    s {foo}  # Replace foo
      {bar}  # with bar.

The cases where whitespace must be used are when the quoting character
is a word character (meaning it matches C</\w/>):

    q XfooX # Works: means the string 'foo'
    qXfooX  # WRONG!

The following escape sequences are available in constructs that interpolate,
and in transliterations whose delimiters aren't single quotes (C<"'">).
In all the ones with braces, any number of blanks and/or tabs adjoining
and within the braces are allowed (and ignored).
X<\t> X<\n> X<\r> X<\f> X<\b> X<\a> X<\e> X<\x> X<\0> X<\c> X<\N> X<\N{}>
X<\o{}>

    Sequence     Note  Description
    \t                  tab               (HT, TAB)
    \n                  newline           (NL)
    \r                  return            (CR)
    \f                  form feed         (FF)
    \b                  backspace         (BS)
    \a                  alarm (bell)      (BEL)
    \e                  escape            (ESC)
    \x{263A}     [1,8]  hex char          (example shown: SMILEY)
    \x{ 263A }          Same, but shows optional blanks inside and
                        adjoining the braces
    \x1b         [2,8]  restricted range hex char (example: ESC)
    \N{name}     [3]    named Unicode character or character sequence
    \N{U+263D}   [4,8]  Unicode character (example: FIRST QUARTER MOON)
    \c[          [5]    control char      (example: chr(27))
    \o{23072}    [6,8]  octal char        (example: SMILEY)
    \033         [7,8]  restricted range octal char  (example: ESC)

Note that any escape sequence using braces inside interpolated
constructs may have optional blanks (tab or space characters) adjoining
with and inside of the braces, as illustrated above by the second
S<C<\x{ }>> example.

=over 4

=item [1]

The result is the character specified by the hexadecimal number between
the braces.  See L</[8]> below for details on which character.

Blanks (tab or space characters) may separate the number from either or
both of the braces.

Otherwise, only hexadecimal digits are valid between the braces.  If an
invalid character is encountered, a warning will be issued and the
invalid character and all subsequent characters (valid or invalid)
within the braces will be discarded.

If there are no valid digits between the braces, the generated character is
the NULL character (C<\x{00}>).  However, an explicit empty brace (C<\x{}>)
will not cause a warning (currently).

=item [2]

The result is the character specified by the hexadecimal number in the range
0x00 to 0xFF.  See L</[8]> below for details on which character.

Only hexadecimal digits are valid following C<\x>.  When C<\x> is followed
by fewer than two valid digits, any valid digits will be zero-padded.  This
means that C<\x7> will be interpreted as C<\x07>, and a lone C<"\x"> will be
interpreted as C<\x00>.  Except at the end of a string, having fewer than
two valid digits will result in a warning.  Note that although the warning
says the illegal character is ignored, it is only ignored as part of the
escape and will still be used as the subsequent character in the string.
For example:

    Original    Result    Warns?
    "\x7"       "\x07"    no
    "\x"        "\x00"    no
    "\x7q"      "\x07q"   yes
    "\xq"       "\x00q"   yes

=item [3]

The result is the Unicode character or character sequence given by I<name>.
See L<charnames>.

=item [4]

S<C<\N{U+I<hexadecimal number>}>> means the Unicode character whose Unicode code
point is I<hexadecimal number>.

=item [5]

The character following C<\c> is mapped to some other character as shown in the
table:

    Sequence   Value
      \c@      chr(0)
      \cA      chr(1)
      \ca      chr(1)
      \cB      chr(2)
      \cb      chr(2)
      ...
      \cZ      chr(26)
      \cz      chr(26)
      \c[      chr(27)
                        # See below for chr(28)
      \c]      chr(29)
      \c^      chr(30)
      \c_      chr(31)
      \c?      chr(127) # (on ASCII platforms; see below for link to
                        #  EBCDIC discussion)

In other words, it's the character whose code point has had 64 xor'd with
its uppercase.  C<\c?> is DELETE on ASCII platforms because
S<C<ord("?") ^ 64>> is 127, and
C<\c@> is NULL because the ord of C<"@"> is 64, so xor'ing 64 itself produces 0.

Also, C<\c\I<X>> yields S<C< chr(28) . "I<X>">> for any I<X>, but cannot come at the
end of a string, because the backslash would be parsed as escaping the end
quote.

On ASCII platforms, the resulting characters from the list above are the
complete set of ASCII controls.  This isn't the case on EBCDIC platforms; see
L<perlebcdic/OPERATOR DIFFERENCES> for a full discussion of the
differences between these for ASCII versus EBCDIC platforms.

Use of any other character following the C<"c"> besides those listed above is
discouraged, and as of Perl v5.20, the only characters actually allowed
are the printable ASCII ones, minus the left brace C<"{">.  What happens
for any of the allowed other characters is that the value is derived by
xor'ing with the seventh bit, which is 64, and a warning raised if
enabled.  Using the non-allowed characters generates a fatal error.

To get platform independent controls, you can use C<\N{...}>.

=item [6]

The result is the character specified by the octal number between the braces.
See L</[8]> below for details on which character.

Blanks (tab or space characters) may separate the number from either or
both of the braces.

Otherwise, if a character that isn't an octal digit is encountered, a
warning is raised, and the value is based on the octal digits before it,
discarding it and all following characters up to the closing brace.  It
is a fatal error if there are no octal digits at all.

=item [7]

The result is the character specified by the three-digit octal number in the
range 000 to 777 (but best to not use above 077, see next paragraph).  See
L</[8]> below for details on which character.

Some contexts allow 2 or even 1 digit, but any usage without exactly
three digits, the first being a zero, may give unintended results.  (For
example, in a regular expression it may be confused with a backreference;
see L<perlrebackslash/Octal escapes>.)  Starting in Perl 5.14, you may
use C<\o{}> instead, which avoids all these problems.  Otherwise, it is best to
use this construct only for ordinals C<\077> and below, remembering to pad to
the left with zeros to make three digits.  For larger ordinals, either use
C<\o{}>, or convert to something else, such as to hex and use C<\N{U+}>
(which is portable between platforms with different character sets) or
C<\x{}> instead.

=item [8]

Several constructs above specify a character by a number.  That number
gives the character's position in the character set encoding (indexed from 0).
This is called synonymously its ordinal, code position, or code point.  Perl
works on platforms that have a native encoding currently of either ASCII/Latin1
or EBCDIC, each of which allow specification of 256 characters.  In general, if
the number is 255 (0xFF, 0377) or below, Perl interprets this in the platform's
native encoding.  If the number is 256 (0x100, 0400) or above, Perl interprets
it as a Unicode code point and the result is the corresponding Unicode
character.  For example C<\x{50}> and C<\o{120}> both are the number 80 in
decimal, which is less than 256, so the number is interpreted in the native
character set encoding.  In ASCII the character in the 80th position (indexed
from 0) is the letter C<"P">, and in EBCDIC it is the ampersand symbol C<"&">.
C<\x{100}> and C<\o{400}> are both 256 in decimal, so the number is interpreted
as a Unicode code point no matter what the native encoding is.  The name of the
character in the 256th position (indexed by 0) in Unicode is
C<LATIN CAPITAL LETTER A WITH MACRON>.

An exception to the above rule is that S<C<\N{U+I<hex number>}>> is
always interpreted as a Unicode code point, so that C<\N{U+0050}> is C<"P"> even
on EBCDIC platforms.

=back

B<NOTE>: Unlike C and other languages, Perl has no C<\v> escape sequence for
the vertical tab (VT, which is 11 in both ASCII and EBCDIC), but you may
use C<\N{VT}>, C<\ck>, C<\N{U+0b}>, or C<\x0b>.  (C<\v>
does have meaning in regular expression patterns in Perl, see L<perlre>.)

The following escape sequences are available in constructs that interpolate,
but not in transliterations.
X<\l> X<\u> X<\L> X<\U> X<\E> X<\Q> X<\F>

    \l          lowercase next character only
    \u          titlecase (not uppercase!) next character only
    \L          lowercase all characters till \E or end of string
    \U          uppercase all characters till \E or end of string
    \F          foldcase all characters till \E or end of string
    \Q          quote (disable) pattern metacharacters till \E or
                end of string
    \E          end either case modification or quoted section
                (whichever was last seen)

See L<perlfunc/quotemeta> for the exact definition of characters that
are quoted by C<\Q>.

C<\L>, C<\U>, C<\F>, and C<\Q> can stack, in which case you need one
C<\E> for each.  For example:

    say "This \Qquoting \ubusiness \Uhere isn't\E done yet,\E is it?";
    This quoting Business HERE ISN'T done yet, is it?

If a S<C<use locale>> form that includes C<LC_CTYPE> is in effect (see
L<perllocale>), the case map used by C<\l>, C<\L>, C<\u>, and C<\U> is
taken from the current locale.  If Unicode (for example, C<\N{}> or code
points of 0x100 or beyond) is being used, the case map used by C<\l>,
C<\L>, C<\u>, and C<\U> is as defined by Unicode.  That means that
case-mapping a single character can sometimes produce a sequence of
several characters.
Under S<C<use locale>>, C<\F> produces the same results as C<\L>
for all locales but a UTF-8 one, where it instead uses the Unicode
definition.

All systems use the virtual C<"\n"> to represent a line terminator,
called a "newline".  There is no such thing as an unvarying, physical
newline character.  It is only an illusion that the operating system,
device drivers, C libraries, and Perl all conspire to preserve.  Not all
systems read C<"\r"> as ASCII CR and C<"\n"> as ASCII LF.  For example,
on the ancient Macs (pre-MacOS X) of yesteryear, these used to be reversed,
and on systems without a line terminator,
printing C<"\n"> might emit no actual data.  In general, use C<"\n"> when
you mean a "newline" for your system, but use the literal ASCII when you
need an exact character.  For example, most networking protocols expect
and prefer a CR+LF (C<"\015\012"> or C<"\cM\cJ">) for line terminators,
and although they often accept just C<"\012">, they seldom tolerate just
C<"\015">.  If you get in the habit of using C<"\n"> for networking,
you may be burned some day.
X<newline> X<line terminator> X<eol> X<end of line>
X<\n> X<\r> X<\r\n>

For constructs that do interpolate, variables beginning with "C<$>"
or "C<@>" are interpolated.  Subscripted variables such as C<$a[3]> or
C<< $href->{key}[0] >> are also interpolated, as are array and hash slices.
But method calls such as C<< $obj->meth >> are not.

Interpolating an array or slice interpolates the elements in order,
separated by the value of C<$">, so is equivalent to interpolating
S<C<join $", @array>>.  "Punctuation" arrays such as C<@*> are usually
interpolated only if the name is enclosed in braces C<@{*}>, but the
arrays C<@_>, C<@+>, and C<@-> are interpolated even without braces.

For double-quoted strings, the quoting from C<\Q> is applied after
interpolation and escapes are processed.

    "abc\Qfoo\tbar$s\Exyz"

is equivalent to

    "abc" . quotemeta("foo\tbar$s") . "xyz"

For the pattern of regex operators (C<qr//>, C<m//> and C<s///>),
the quoting from C<\Q> is applied after interpolation is processed,
but before escapes are processed.  This allows the pattern to match
literally (except for C<$> and C<@>).  For example, the following matches:

    '\s\t' =~ /\Q\s\t/

Because C<$> or C<@> trigger interpolation, you'll need to use something
like C</\Quser\E\@\Qhost/> to match them literally.

Patterns are subject to an additional level of interpretation as a
regular expression.  This is done as a second pass, after variables are
interpolated, so that regular expressions may be incorporated into the
pattern from the variables.  If this is not what you want, use C<\Q> to
interpolate a variable literally.

Apart from the behavior described above, Perl does not expand
multiple levels of interpolation.  In particular, contrary to the
expectations of shell programmers, back-quotes do I<NOT> interpolate
within double quotes, nor do single quotes impede evaluation of
variables when used within double quotes.

=head3 Simpler Quote-Like Operators
X<operator, quote-like>

=over 4

=item C<q/I<STRING>/>
X<q> X<quote, single> X<'> X<''>

=item C<'I<STRING>'>

A single-quoted, literal string.  A backslash represents a backslash
unless followed by the delimiter or another backslash, in which case
the delimiter or backslash is interpolated.

    $foo = q!I said, "You said, 'She said it.'"!;
    $bar = q('This is it.');
    $baz = '\n';                # a two-character string

=item C<qq/I<STRING>/>
X<qq> X<quote, double> X<"> X<"">

=item C<"I<STRING>">

A double-quoted, interpolated string.

    $_ .= qq
     (*** The previous line contains the naughty word "$1".\n)
                if /\b(tcl|java|python)\b/i;      # :-)
    $baz = "\n";                # a one-character string

=item C<qx/I<STRING>/>
X<qx> X<`> X<``> X<backtick>

=item C<`I<STRING>`>

A string which is (possibly) interpolated and then executed as a
system command, via F</bin/sh> or its equivalent if required.  Shell
wildcards, pipes, and redirections will be honored.  Similarly to
C<system>, if the string contains no shell metacharacters then it will
be executed directly.  The collected standard output of the command is
returned; standard error is unaffected.  In scalar context, it comes
back as a single (potentially multi-line) string, or C<undef> if the
shell (or command) could not be started.  In list context, returns a
list of lines (however you've defined lines with C<$/> or
C<$INPUT_RECORD_SEPARATOR>), or an empty list if the shell (or command)
could not be started.

    print qx/date/; # prints "Sun Jan 28 06:16:19 CST 2024"

Because backticks do not affect standard error, use shell file descriptor
syntax (assuming the shell supports this) if you care to address this.
To capture a command's STDERR and STDOUT together:

    $output = `cmd 2>&1`;

To capture a command's STDOUT but discard its STDERR:

    $output = `cmd 2>/dev/null`;

To capture a command's STDERR but discard its STDOUT (ordering is
important here):

    $output = `cmd 2>&1 1>/dev/null`;

To exchange a command's STDOUT and STDERR in order to capture the STDERR
but leave its STDOUT to come out the old STDERR:

    $output = `cmd 3>&1 1>&2 2>&3 3>&-`;

To read both a command's STDOUT and its STDERR separately, it's easiest
to redirect them separately to files, and then read from those files
when the program is done:

    system("program args 1>program.stdout 2>program.stderr");

The STDIN filehandle used by the command is inherited from Perl's STDIN.
For example:

    open(SPLAT, "stuff")   || die "can't open stuff: $!";
    open(STDIN, "<&SPLAT") || die "can't dupe SPLAT: $!";
    print STDOUT `sort`;

will print the sorted contents of the file named F<"stuff">.

Using single-quote as a delimiter protects the command from Perl's
double-quote interpolation, passing it on to the shell instead:

    $perl_info  = qx(ps $$);            # that's Perl's $$
    $shell_info = qx'ps $$';            # that's the new shell's $$

How that string gets evaluated is entirely subject to the command
interpreter on your system.  On most platforms, you will have to protect
shell metacharacters if you want them treated literally.  This is in
practice difficult to do, as it's unclear how to escape which characters.
See L<perlsec> for a clean and safe example of a manual C<fork()> and C<exec()>
to emulate backticks safely.

On some platforms (notably DOS-like ones), the shell may not be
capable of dealing with multiline commands, so putting newlines in
the string may not get you what you want.  You may be able to evaluate
multiple commands in a single line by separating them with the command
separator character, if your shell supports that (for example, C<;> on
many Unix shells and C<&> on the Windows NT C<cmd> shell).

Perl will attempt to flush all files opened for
output before starting the child process, but this may not be supported
on some platforms (see L<perlport>).  To be safe, you may need to set
C<$|> (C<$AUTOFLUSH> in C<L<English>>) or call the C<autoflush()> method of
C<L<IO::Handle>> on any open handles.

Beware that some command shells may place restrictions on the length
of the command line.  You must ensure your strings don't exceed this
limit after any necessary interpolations.  See the platform-specific
release notes for more details about your particular environment.

Using this operator can lead to programs that are difficult to port,
because the shell commands called vary between systems, and may in
fact not be present at all.  As one example, the C<type> command under
the POSIX shell is very different from the C<type> command under DOS.
That doesn't mean you should go out of your way to avoid backticks
when they're the right way to get something done.  Perl was made to be
a glue language, and one of the things it glues together is commands.
Just understand what you're getting yourself into.

Like C<system>, backticks put the child process exit code in C<$?>.
If you'd like to manually inspect failure, you can check all possible
failure modes by inspecting C<$?> like this:

    if ($? == -1) {
        print "failed to execute: $!\n";
    }
    elsif ($? & 127) {
        printf "child died with signal %d, %s coredump\n",
            ($? & 127),  ($? & 128) ? 'with' : 'without';
    }
    else {
        printf "child exited with value %d\n", $? >> 8;
    }

Use the L<open> pragma to control the I/O layers used when reading the
output of the command, for example:

    use open IN => ":encoding(UTF-8)";
    my $x = `cmd-producing-utf-8`;

C<qx//> can also be called like a function with L<perlfunc/readpipe>.

See L</"I/O Operators"> for more discussion.

=item C<qw/I<STRING>/>
X<qw> X<quote, list> X<quote, words>

Evaluates to a list of the words extracted out of I<STRING>, using embedded
whitespace as the word delimiters.  It can be understood as being roughly
equivalent to:

    split(" ", q/STRING/);

the differences being that it only splits on ASCII whitespace,
generates a real list at compile time, and
in scalar context it returns the last element in the list.  So
this expression:

    qw(foo bar baz)

is semantically equivalent to the list:

    "foo", "bar", "baz"

Some frequently seen examples:

    use POSIX qw( setlocale localeconv )
    @EXPORT = qw( foo bar baz );

Common mistakes are trying to separate the words with commas, trying to
put comments into a multi-line C<qw>-string, or trying to C<\>-escape
the space between words. For this reason, the S<C<use warnings>> pragma
and the B<-w> switch (that is, the C<$^W> variable) produce warnings if
the I<STRING> contains the C<",">, C<"#">, or C<"\"> characters.

=back

=head3 Regexp Quote-Like Operators
X<operator, regexp>

Here are the quote-like operators that apply to pattern
matching and related activities.

=over 8

=item C<qr/I<STRING>/msixpodualn>
X<qr> X</i> X</m> X</o> X</s> X</x> X</p>

This operator quotes (and possibly compiles) its I<STRING> as a regular
expression.  I<STRING> is interpolated the same way as I<PATTERN>
in C<m/I<PATTERN>/>.  If C<"'"> is used as the delimiter, no variable
interpolation is done.  Returns a Perl value which may be used instead of the
corresponding C</I<STRING>/msixpodualn> expression.  The returned value is a
normalized version of the original pattern.  It magically differs from
a string containing the same characters: C<ref(qr/x/)> returns "Regexp";
however, dereferencing it is not well defined (you currently get the
normalized version of the original pattern, but this may change).


For example,

    $rex = qr/my.STRING/is;
    print $rex;                 # prints (?si-xm:my.STRING)
    s/$rex/foo/;

is equivalent to

    s/my.STRING/foo/is;

The result may be used as a subpattern in a match:

    $re = qr/$pattern/;
    $string =~ /foo${re}bar/;   # can be interpolated in other
                                # patterns
    $string =~ $re;             # or used standalone
    $string =~ /$re/;           # or this way

Since Perl may compile the pattern at the moment of execution of the C<qr()>
operator, using C<qr()> may have speed advantages in some situations,
notably if the result of C<qr()> is used standalone:

    sub match {
        my $patterns = shift;
        my @compiled = map qr/$_/i, @$patterns;
        grep {
            my $success = 0;
            foreach my $pat (@compiled) {
                $success = 1, last if /$pat/;
            }
            $success;
        } @_;
    }

Precompilation of the pattern into an internal representation at
the moment of C<qr()> avoids the need to recompile the pattern every
time a match C</$pat/> is attempted.  (Perl has many other internal
optimizations, but none would be triggered in the above example if
we did not use C<qr()> operator.)

Options (specified by the following modifiers) are:

    m   Treat string as multiple lines.
    s   Treat string as single line. (Make . match a newline)
    i   Do case-insensitive pattern matching.
    x   Use extended regular expressions; specifying two
        x's means \t and the SPACE character are ignored within
        square-bracketed character classes
    p   When matching preserve a copy of the matched string so
        that ${^PREMATCH}, ${^MATCH}, ${^POSTMATCH} will be
        defined (ignored starting in v5.20 as these are always
        defined starting in that release)
    o   Compile pattern only once.
    a   ASCII-restrict: Use ASCII for \d, \s, \w and [[:posix:]]
        character classes; specifying two a's adds the further
        restriction that no ASCII character will match a
        non-ASCII one under /i.
    l   Use the current run-time locale's rules.
    u   Use Unicode rules.
    d   Use Unicode or native charset, as in 5.12 and earlier.
    n   Non-capture mode. Don't let () fill in $1, $2, etc...

If a precompiled pattern is embedded in a larger pattern then the effect
of C<"msixpluadn"> will be propagated appropriately.  The effect that the
C</o> modifier has is not propagated, being restricted to those patterns
explicitly using it.

The C</a>, C</d>, C</l>, and C</u> modifiers (added in Perl 5.14)
control the character set rules, but C</a> is the only one you are likely
to want to specify explicitly; the other three are selected
automatically by various pragmas.

See L<perlre> for additional information on valid syntax for I<STRING>, and
for a detailed look at the semantics of regular expressions.  In
particular, all modifiers except the largely obsolete C</o> are further
explained in L<perlre/Modifiers>.  C</o> is described in the next section.

=item C<m/I<PATTERN>/msixpodualngc>
X<m> X<operator, match>
X<regexp, options> X<regexp> X<regex, options> X<regex>
X</m> X</s> X</i> X</x> X</p> X</o> X</g> X</c>

=item C</I<PATTERN>/msixpodualngc>

Searches a string for a pattern match, and in scalar context returns
true if it succeeds, false if it fails.  If no string is specified
via the C<=~> or C<!~> operator, the C<$_> string is searched.  (The
string specified with C<=~> need not be an lvalue--it may be the
result of an expression evaluation, but remember the C<=~> binds
rather tightly.)  See also L<perlre>.

Options are as described in C<qr//> above; in addition, the following match
process modifiers are available:

    g  Match globally, i.e., find all occurrences.
    c  Do not reset search position on a failed match when /g is
       in effect.

If C<"/"> is the delimiter then the initial C<m> is optional.  With the C<m>
you can use any pair of non-whitespace (ASCII) characters
as delimiters.  This is particularly useful for matching path names
that contain C<"/">, to avoid LTS (leaning toothpick syndrome).  If C<"?"> is
the delimiter, then a match-only-once rule applies,
described in C<m?I<PATTERN>?> below.  If C<"'"> (single quote) is the delimiter,
no variable interpolation is performed on the I<PATTERN>.
When using a delimiter character valid in an identifier, whitespace is required
after the C<m>.

I<PATTERN> may contain variables, which will be interpolated
every time the pattern search is evaluated, except
for when the delimiter is a single quote.  (Note that C<$(>, C<$)>, and
C<$|> are not interpolated because they look like end-of-string tests.)
Perl will not recompile the pattern unless an interpolated
variable that it contains changes.  You can force Perl to skip the
test and never recompile by adding a C</o> (which stands for "once")
after the trailing delimiter.
Once upon a time, Perl would recompile regular expressions
unnecessarily, and this modifier was useful to tell it not to do so, in the
interests of speed.  But now, the only reasons to use C</o> are one of:

=over

=item 1

The variables are thousands of characters long and you know that they
don't change, and you need to wring out the last little bit of speed by
having Perl skip testing for that.  (There is a maintenance penalty for
doing this, as mentioning C</o> constitutes a promise that you won't
change the variables in the pattern.  If you do change them, Perl won't
even notice.)

=item 2

you want the pattern to use the initial values of the variables
regardless of whether they change or not.  (But there are saner ways
of accomplishing this than using C</o>.)

=item 3

If the pattern contains embedded code, such as

    use re 'eval';
    $code = 'foo(?{ $x })';
    /$code/

then perl will recompile each time, even though the pattern string hasn't
changed, to ensure that the current value of C<$x> is seen each time.
Use C</o> if you want to avoid this.

=back

The bottom line is that using C</o> is almost never a good idea.

=item The empty pattern C<//>

(This subsection applies to C<//>, C<m//>, and C<s///>, but not to
C<qr//>.)

If the I<PATTERN> evaluates to the empty string, the last
I<successfully> matched regular expression in the current dynamic
scope is used instead (see also L<perlvar/Scoping Rules of Regex Variables>).
In this case, only the C<g> and C<c> flags on the empty pattern are
honored; the other flags are taken from the original pattern. If no
match has previously succeeded, this will (silently) act instead as a
genuine empty pattern (which will always match). Using a user supplied
string as a pattern has the risk that if the string is empty that it
triggers the "last successful match" behavior, which can be very
confusing. In such cases you are recommended to replace C<m/$pattern/>
with C<m/(?:$pattern)/> to avoid this behavior.

The last successful pattern may be accessed as a variable via
C<${^LAST_SUCCESSFUL_PATTERN}>. Matching against it, or the empty
pattern should have the same effect, with the exception that when there
is no last successful pattern the empty pattern will silently match,
whereas using the C<${^LAST_SUCCESSFUL_PATTERN}> variable will produce
undefined warnings (if warnings are enabled). You can check
C<defined(${^LAST_SUCCESSFUL_PATTERN})> to test if there is a "last
successful match" in the current scope.

Note that it's possible to confuse Perl into thinking C<//> (the empty
regex) is really C<//> (the defined-or operator).  Perl is usually pretty
good about this, but some pathological cases might trigger this, such as
C<$x///> (is that S<C<($x) / (//)>> or S<C<$x // />>?) and S<C<print $fh //>>
(S<C<print $fh(//>> or S<C<print($fh //>>?).  In all of these examples, Perl
will assume you meant defined-or.  If you meant the empty regex, just
use parentheses or spaces to disambiguate, or even prefix the empty
regex with an C<m> (so C<//> becomes C<m//>).

=item Matching in list context

If the C</g> option is not used, C<m//> in list context returns a
list consisting of the subexpressions matched by the parentheses in the
pattern, that is, (C<$1>, C<$2>, C<$3>...)  (Note that here C<$1> etc. are
also set).  When there are no parentheses in the pattern, the return
value is the list C<(1)> for success.
With or without parentheses, an empty list is returned upon failure.

Examples:

    open(TTY, "+</dev/tty")
       || die "can't access /dev/tty: $!";

    <TTY> =~ /^y/i && foo();       # do foo if desired

    if (/Version: *([0-9.]*)/) { $version = $1; }

    next if m#^/usr/spool/uucp#;

    # poor man's grep
    $arg = shift;
    while (<>) {
       print if /$arg/;
    }
    if (($F1, $F2, $Etc) = ($foo =~ /^(\S+)\s+(\S+)\s*(.*)/))

This last example splits C<$foo> into the first two words and the
remainder of the line, and assigns those three fields to C<$F1>, C<$F2>, and
C<$Etc>.  The conditional is true if any variables were assigned; that is,
if the pattern matched.

The C</g> modifier specifies global pattern matching--that is,
matching as many times as possible within the string.  How it behaves
depends on the context.  In list context, it returns a list of the
substrings matched by any capturing parentheses in the regular
expression.  If there are no parentheses, it returns a list of all
the matched strings, as if there were parentheses around the whole
pattern.

In scalar context, each execution of C<m//g> finds the next match,
returning true if it matches, and false if there is no further match.
The position after the last match can be read or set using the C<pos()>
function; see L<perlfunc/pos>.  A failed match normally resets the
search position to the beginning of the string, but you can avoid that
by adding the C</c> modifier (for example, C<m//gc>).  Modifying the target
string also resets the search position.

=item C<\G I<assertion>>

You can intermix C<m//g> matches with C<m/\G.../g>, where C<\G> is a
zero-width assertion that matches the exact position where the
previous C<m//g>, if any, left off.  Without the C</g> modifier, the
C<\G> assertion still anchors at C<pos()> as it was at the start of
the operation (see L<perlfunc/pos>), but the match is of course only
attempted once.  Using C<\G> without C</g> on a target string that has
not previously had a C</g> match applied to it is the same as using
the C<\A> assertion to match the beginning of the string.  Note also
that, currently, C<\G> is only properly supported when anchored at the
very beginning of the pattern.

Examples:

    # list context
    ($one,$five,$fifteen) = (`uptime` =~ /(\d+\.\d+)/g);

    # scalar context
    local $/ = "";
    while ($paragraph = <>) {
        while ($paragraph =~ /\p{Ll}['")]*[.!?]+['")]*\s/g) {
            $sentences++;
        }
    }
    say $sentences;

Here's another way to check for sentences in a paragraph:

    my $sentence_rx = qr{
        (?: (?<= ^ ) | (?<= \s ) )  # after start-of-string or
                                    # whitespace
        \p{Lu}                      # capital letter
        .*?                         # a bunch of anything
        (?<= \S )                   # that ends in non-
                                    # whitespace
        (?<! \b [DMS]r  )           # but isn't a common abbr.
        (?<! \b Mrs )
        (?<! \b Sra )
        (?<! \b St  )
        [.?!]                       # followed by a sentence
                                    # ender
        (?= $ | \s )                # in front of end-of-string
                                    # or whitespace
    }sx;
    local $/ = "";
    while (my $paragraph = <>) {
        say "NEW PARAGRAPH";
        my $count = 0;
        while ($paragraph =~ /($sentence_rx)/g) {
            printf "\tgot sentence %d: <%s>\n", ++$count, $1;
        }
    }

Here's how to use C<m//gc> with C<\G>:

    $_ = "ppooqppqq";
    while ($i++ < 2) {
        print "1: '";
        print $1 while /(o)/gc; print "', pos=", pos, "\n";
        print "2: '";
        print $1 if /\G(q)/gc;  print "', pos=", pos, "\n";
        print "3: '";
        print $1 while /(p)/gc; print "', pos=", pos, "\n";
    }
    print "Final: '$1', pos=",pos,"\n" if /\G(.)/;

The last example should print:

    1: 'oo', pos=4
    2: 'q', pos=5
    3: 'pp', pos=7
    1: '', pos=7
    2: 'q', pos=8
    3: '', pos=8
    Final: 'q', pos=8

Notice that the final match matched C<q> instead of C<p>, which a match
without the C<\G> anchor would have done.  Also note that the final match
did not update C<pos>.  C<pos> is only updated on a C</g> match.  If the
final match did indeed match C<p>, it's a good bet that you're running an
ancient (pre-5.6.0) version of Perl.

A useful idiom for C<lex>-like scanners is C</\G.../gc>.  You can
combine several regexps like this to process a string part-by-part,
doing different actions depending on which regexp matched.  Each
regexp tries to match where the previous one leaves off.

    $_ = <<'EOL';
        $url = URI::URL->new( "http://example.com/" );
        die if $url eq "xXx";
    EOL

    LOOP: {
        print(" digits"),       redo LOOP if /\G\d+\b[,.;]?\s*/gc;
        print(" lowercase"),    redo LOOP
                                      if /\G\p{Ll}+\b[,.;]?\s*/gc;
        print(" UPPERCASE"),    redo LOOP
                                      if /\G\p{Lu}+\b[,.;]?\s*/gc;
        print(" Capitalized"),  redo LOOP
                                if /\G\p{Lu}\p{Ll}+\b[,.;]?\s*/gc;
        print(" MiXeD"),        redo LOOP
                                         if /\G\pL+\b[,.;]?\s*/gc;
        print(" alphanumeric"), redo LOOP
                              if /\G[\p{Alpha}\pN]+\b[,.;]?\s*/gc;
        print(" line-noise"),   redo LOOP if /\G\W+/gc;
        print ". That's all!\n";
    }

Here is the output (split into several lines):

    line-noise lowercase line-noise UPPERCASE line-noise UPPERCASE
    line-noise lowercase line-noise lowercase line-noise lowercase
    lowercase line-noise lowercase lowercase line-noise lowercase
    lowercase line-noise MiXeD line-noise. That's all!

=item C<m?I<PATTERN>?msixpodualngc>
X<?> X<operator, match-once>

This is just like the C<m/I<PATTERN>/> search, except that it matches
only once between calls to the C<reset()> operator.  This is a useful
optimization when you want to see only the first occurrence of
something in each file of a set of files, for instance.  Only C<m??>
patterns local to the current package are reset.

    while (<>) {
        if (m?^$?) {
                            # blank line between header and body
        }
    } continue {
        reset if eof;       # clear m?? status for next file
    }

Anoth
