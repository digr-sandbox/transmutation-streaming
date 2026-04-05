=head1 NAME
X<function>

perlfunc - Perl builtin functions

=head1 DESCRIPTION

The functions in this section can serve as terms in an expression.
They fall into two major categories: list operators and named unary
operators.  These differ in their precedence relationship with a
following comma.  (See the precedence table in L<perlop>.)  List
operators take more than one argument, while unary operators can never
take more than one argument.  Thus, a comma terminates the argument of
a unary operator, but merely separates the arguments of a list
operator.  A unary operator generally provides scalar context to its
argument, while a list operator may provide either scalar or list
contexts for its arguments.  If it does both, scalar arguments
come first and list argument follow, and there can only ever
be one such list argument.  For instance,
L<C<splice>|/splice ARRAY,OFFSET,LENGTH,LIST> has three scalar arguments
followed by a list, whereas L<C<gethostbyname>|/gethostbyname NAME> has
four scalar arguments.

In the syntax descriptions that follow, list operators that expect a
list (and provide list context for elements of the list) are shown
with LIST as an argument.  Such a list may consist of any combination
of scalar arguments or list values; the list values will be included
in the list as if each individual element were interpolated at that
point in the list, forming a longer single-dimensional list value.
Commas should separate literal elements of the LIST.

Any function in the list below may be used either with or without
parentheses around its arguments.  (The syntax descriptions omit the
parentheses.)  If you use parentheses, the simple but occasionally
surprising rule is this: It I<looks> like a function, therefore it I<is> a
function, and precedence doesn't matter.  Otherwise it's a list
operator or unary operator, and precedence does matter.  Whitespace
between the function and left parenthesis doesn't count, so sometimes
you need to be careful:

    print 1+2+4;      # Prints 7.
    print(1+2) + 4;   # Prints 3.
    print (1+2)+4;    # Also prints 3!
    print +(1+2)+4;   # Prints 7.
    print ((1+2)+4);  # Prints 7.

If you run Perl with the L<C<use warnings>|warnings> pragma, it can warn
you about this.  For example, the third line above produces:

    print (...) interpreted as function at - line 1.
    Useless use of integer addition in void context at - line 1.

A few functions take no arguments at all, and therefore work as neither
unary nor list operators.  These include such functions as
L<C<time>|/time> and L<C<endpwent>|/endpwent>.  For example,
C<time+86_400> always means C<time() + 86_400>.

For functions that can be used in either a scalar or list context,
nonabortive failure is generally indicated in scalar context by
returning the undefined value, and in list context by returning the
empty list.

Remember the following important rule: There is B<no rule> that relates
the behavior of an expression in list context to its behavior in scalar
context, or vice versa.  It might do two totally different things.
Each operator and function decides which sort of value would be most
appropriate to return in scalar context.  Some operators return the
length of the list that would have been returned in list context.  Some
operators return the first value in the list.  Some operators return the
last value in the list.  Some operators return a count of successful
operations.  In general, they do what you want, unless you want
consistency.
X<context>

A named array in scalar context is quite different from what would at
first glance appear to be a list in scalar context.  You can't get a list
like C<(1,2,3)> into being in scalar context, because the compiler knows
the context at compile time.  It would generate the scalar comma operator
there, not the list concatenation version of the comma.  That means it
was never a list to start with.

In general, functions in Perl that serve as wrappers for system calls
("syscalls") of the same name (like L<chown(2)>, L<fork(2)>,
L<closedir(2)>, etc.) return true when they succeed and
L<C<undef>|/undef EXPR> otherwise, as is usually mentioned in the
descriptions below.  This is different from the C interfaces, which
return C<-1> on failure.  Exceptions to this rule include
L<C<wait>|/wait>, L<C<waitpid>|/waitpid PID,FLAGS>, and
L<C<syscall>|/syscall NUMBER, LIST>.  System calls also set the special
L<C<$!>|perlvar/$!> variable on failure.  Other functions do not, except
accidentally.

Extension modules can also hook into the Perl parser to define new
kinds of keyword-headed expression.  These may look like functions, but
may also look completely different.  The syntax following the keyword
is defined entirely by the extension.  If you are an implementor, see
L<perlapi/PL_keyword_plugin> for the mechanism.  If you are using such
a module, see the module's documentation for details of the syntax that
it defines.

=head2 Perl Functions by Category
X<function>

Here are Perl's functions (including things that look like
functions, like some keywords and named operators)
arranged by category.  Some functions appear in more
than one place.  Any warnings, including those produced by
keywords, are described in L<perldiag> and L<warnings>.

=over 4

=item Functions for SCALARs or strings
X<scalar> X<string> X<character>

=for Pod::Functions =String

L<C<chomp>|/chomp VARIABLE>, L<C<chop>|/chop VARIABLE>,
L<C<chr>|/chr NUMBER>, L<C<crypt>|/crypt PLAINTEXT,SALT>,
L<C<fc>|/fc EXPR>, L<C<hex>|/hex EXPR>,
L<C<index>|/index STR,SUBSTR,POSITION>, L<C<lc>|/lc EXPR>,
L<C<lcfirst>|/lcfirst EXPR>, L<C<length>|/length EXPR>,
L<C<oct>|/oct EXPR>, L<C<ord>|/ord EXPR>,
L<C<pack>|/pack TEMPLATE,LIST>,
L<C<qE<sol>E<sol>>|/qE<sol>STRINGE<sol>>,
L<C<qqE<sol>E<sol>>|/qqE<sol>STRINGE<sol>>, L<C<reverse>|/reverse LIST>,
L<C<rindex>|/rindex STR,SUBSTR,POSITION>,
L<C<sprintf>|/sprintf FORMAT, LIST>,
L<C<substr>|/substr EXPR,OFFSET,LENGTH,REPLACEMENT>,
L<C<trE<sol>E<sol>E<sol>>|/trE<sol>E<sol>E<sol>>, L<C<uc>|/uc EXPR>,
L<C<ucfirst>|/ucfirst EXPR>,
L<C<yE<sol>E<sol>E<sol>>|/yE<sol>E<sol>E<sol>>

L<C<fc>|/fc EXPR> is available only if the
L<C<"fc"> feature|feature/The 'fc' feature> is enabled or if it is
prefixed with C<CORE::>.  The
L<C<"fc"> feature|feature/The 'fc' feature> is enabled automatically
with a C<use v5.16> (or higher) declaration in the current scope.

=item Regular expressions and pattern matching
X<regular expression> X<regex> X<regexp>

=for Pod::Functions =Regexp

L<C<mE<sol>E<sol>>|/mE<sol>E<sol>>, L<C<pos>|/pos SCALAR>,
L<C<qrE<sol>E<sol>>|/qrE<sol>STRINGE<sol>>,
L<C<quotemeta>|/quotemeta EXPR>,
L<C<sE<sol>E<sol>E<sol>>|/sE<sol>E<sol>E<sol>>,
L<C<split>|/split E<sol>PATTERNE<sol>,EXPR,LIMIT>,
L<C<study>|/study SCALAR>

=item Numeric functions
X<numeric> X<number> X<trigonometric> X<trigonometry>

=for Pod::Functions =Math

L<C<abs>|/abs VALUE>, L<C<atan2>|/atan2 Y,X>, L<C<cos>|/cos EXPR>,
L<C<exp>|/exp EXPR>, L<C<hex>|/hex EXPR>, L<C<int>|/int EXPR>,
L<C<log>|/log EXPR>, L<C<oct>|/oct EXPR>, L<C<rand>|/rand EXPR>,
L<C<sin>|/sin EXPR>, L<C<sqrt>|/sqrt EXPR>, L<C<srand>|/srand EXPR>

=item Functions for real @ARRAYs
X<array>

=for Pod::Functions =ARRAY

L<C<each>|/each HASH>, L<C<keys>|/keys HASH>, L<C<pop>|/pop ARRAY>,
L<C<push>|/push ARRAY,LIST>, L<C<shift>|/shift ARRAY>,
L<C<splice>|/splice ARRAY,OFFSET,LENGTH,LIST>,
L<C<unshift>|/unshift ARRAY,LIST>, L<C<values>|/values HASH>

=item Functions for list data
X<list>

=for Pod::Functions =LIST

L<C<all>|/all BLOCK LIST>, L<C<any>|/any BLOCK LIST>,
L<C<grep>|/grep BLOCK LIST>, L<C<join>|/join EXPR,LIST>,
L<C<map>|/map BLOCK LIST>, L<C<qwE<sol>E<sol>>|/qwE<sol>STRINGE<sol>>,
L<C<reverse>|/reverse LIST>, L<C<sort>|/sort SUBNAME LIST>,
L<C<unpack>|/unpack TEMPLATE,EXPR>

=item Functions for real %HASHes
X<hash>

=for Pod::Functions =HASH

L<C<delete>|/delete EXPR>, L<C<each>|/each HASH>,
L<C<exists>|/exists EXPR>, L<C<keys>|/keys HASH>,
L<C<values>|/values HASH>

=item Input and output functions
X<I/O> X<input> X<output> X<dbm>

=for Pod::Functions =I/O

L<C<binmode>|/binmode FILEHANDLE, LAYER>, L<C<close>|/close FILEHANDLE>,
L<C<closedir>|/closedir DIRHANDLE>, L<C<dbmclose>|/dbmclose HASH>,
L<C<dbmopen>|/dbmopen HASH,DBNAME,MASK>, L<C<die>|/die LIST>,
L<C<eof>|/eof FILEHANDLE>, L<C<fileno>|/fileno FILEHANDLE>,
L<C<flock>|/flock FILEHANDLE,OPERATION>, L<C<format>|/format>,
L<C<getc>|/getc FILEHANDLE>, L<C<print>|/print FILEHANDLE LIST>,
L<C<printf>|/printf FILEHANDLE FORMAT, LIST>,
L<C<read>|/read FILEHANDLE,SCALAR,LENGTH,OFFSET>,
L<C<readdir>|/readdir DIRHANDLE>, L<C<readline>|/readline EXPR>,
L<C<rewinddir>|/rewinddir DIRHANDLE>, L<C<say>|/say FILEHANDLE LIST>,
L<C<seek>|/seek FILEHANDLE,POSITION,WHENCE>,
L<C<seekdir>|/seekdir DIRHANDLE,POS>,
L<C<select>|/select RBITS,WBITS,EBITS,TIMEOUT>,
L<C<syscall>|/syscall NUMBER, LIST>,
L<C<sysread>|/sysread FILEHANDLE,SCALAR,LENGTH,OFFSET>,
L<C<sysseek>|/sysseek FILEHANDLE,POSITION,WHENCE>,
L<C<syswrite>|/syswrite FILEHANDLE,SCALAR,LENGTH,OFFSET>,
L<C<tell>|/tell FILEHANDLE>, L<C<telldir>|/telldir DIRHANDLE>,
L<C<truncate>|/truncate FILEHANDLE,LENGTH>, L<C<warn>|/warn LIST>,
L<C<write>|/write FILEHANDLE>

L<C<say>|/say FILEHANDLE LIST> is available only if the
L<C<"say"> feature|feature/The 'say' feature> is enabled or if it is
prefixed with C<CORE::>.  The
L<C<"say"> feature|feature/The 'say' feature> is enabled automatically
with a C<use v5.10> (or higher) declaration in the current scope.

=item Functions for fixed-length data or records

=for Pod::Functions =Binary

L<C<pack>|/pack TEMPLATE,LIST>,
L<C<read>|/read FILEHANDLE,SCALAR,LENGTH,OFFSET>,
L<C<syscall>|/syscall NUMBER, LIST>,
L<C<sysread>|/sysread FILEHANDLE,SCALAR,LENGTH,OFFSET>,
L<C<sysseek>|/sysseek FILEHANDLE,POSITION,WHENCE>,
L<C<syswrite>|/syswrite FILEHANDLE,SCALAR,LENGTH,OFFSET>,
L<C<unpack>|/unpack TEMPLATE,EXPR>, L<C<vec>|/vec EXPR,OFFSET,BITS>

=item Functions for filehandles, files, or directories
X<file> X<filehandle> X<directory> X<pipe> X<link> X<symlink>

=for Pod::Functions =File

L<C<-I<X>>|/-X FILEHANDLE>, L<C<chdir>|/chdir EXPR>,
L<C<chmod>|/chmod LIST>, L<C<chown>|/chown LIST>,
L<C<chroot>|/chroot FILENAME>,
L<C<fcntl>|/fcntl FILEHANDLE,FUNCTION,SCALAR>, L<C<glob>|/glob EXPR>,
L<C<ioctl>|/ioctl FILEHANDLE,FUNCTION,SCALAR>,
L<C<link>|/link OLDFILE,NEWFILE>, L<C<lstat>|/lstat FILEHANDLE>,
L<C<mkdir>|/mkdir FILENAME,MODE>, L<C<open>|/open FILEHANDLE,MODE,EXPR>,
L<C<opendir>|/opendir DIRHANDLE,EXPR>, L<C<readlink>|/readlink EXPR>,
L<C<rename>|/rename OLDNAME,NEWNAME>, L<C<rmdir>|/rmdir FILENAME>,
L<C<select>|/select FILEHANDLE>, L<C<stat>|/stat FILEHANDLE>,
L<C<symlink>|/symlink OLDFILE,NEWFILE>,
L<C<sysopen>|/sysopen FILEHANDLE,FILENAME,MODE>,
L<C<umask>|/umask EXPR>, L<C<unlink>|/unlink LIST>,
L<C<utime>|/utime LIST>

=item Keywords related to the control flow of your Perl program
X<control flow>

=for Pod::Functions =Flow

L<C<break>|/break>, L<C<caller>|/caller EXPR>,
L<C<continue>|/continue BLOCK>, L<C<die>|/die LIST>, L<C<do>|/do BLOCK>,
L<C<dump>|/dump LABEL>, L<C<eval>|/eval EXPR>,
L<C<evalbytes>|/evalbytes EXPR>, L<C<exit>|/exit EXPR>,
L<C<__FILE__>|/__FILE__>, L<C<goto>|/goto LABEL>,
L<C<last>|/last LABEL>, L<C<__LINE__>|/__LINE__>,
L<C<method>|/method NAME BLOCK>,
L<C<next>|/next LABEL>, L<C<__PACKAGE__>|/__PACKAGE__>,
L<C<redo>|/redo LABEL>, L<C<return>|/return EXPR>,
L<C<sub>|/sub NAME BLOCK>, L<C<__SUB__>|/__SUB__>,
L<C<wantarray>|/wantarray>

L<C<break>|/break> is available only if you enable the experimental
L<C<"switch"> feature|feature/The 'switch' feature> or use the C<CORE::>
prefix.  The L<C<"switch"> feature|feature/The 'switch' feature> also
enables the C<default>, C<given> and C<when> statements, which are
documented in L<perlsyn/"Switch Statements">.
The L<C<"switch"> feature|feature/The 'switch' feature> is enabled
automatically with a C<use v5.10> (or higher) declaration in the current
scope.  In Perl v5.14 and earlier, L<C<continue>|/continue BLOCK>
required the L<C<"switch"> feature|feature/The 'switch' feature>, like
the other keywords.

L<C<evalbytes>|/evalbytes EXPR> is only available with the
L<C<"evalbytes"> feature|feature/The 'unicode_eval' and 'evalbytes' features>
(see L<feature>) or if prefixed with C<CORE::>.  L<C<__SUB__>|/__SUB__>
is only available with the
L<C<"current_sub"> feature|feature/The 'current_sub' feature> or if
prefixed with C<CORE::>.  Both the
L<C<"evalbytes">|feature/The 'unicode_eval' and 'evalbytes' features>
and L<C<"current_sub">|feature/The 'current_sub' feature> features are
enabled automatically with a C<use v5.16> (or higher) declaration in the
current scope.

=item Keywords related to scoping

=for Pod::Functions =Namespace

L<C<caller>|/caller EXPR>,
L<C<class>|/class NAMESPACE>, 
L<C<field>|/field VARNAME>,
L<C<import>|/import LIST>,
L<C<local>|/local EXPR>,
L<C<my>|/my VARLIST>,
L<C<our>|/our VARLIST>,
L<C<package>|/package NAMESPACE>,
L<C<state>|/state VARLIST>,
L<C<use>|/use Module VERSION LIST>

L<C<state>|/state VARLIST> is available only if the
L<C<"state"> feature|feature/The 'state' feature> is enabled or if it is
prefixed with C<CORE::>.  The
L<C<"state"> feature|feature/The 'state' feature> is enabled
automatically with a C<use v5.10> (or higher) declaration in the current
scope.

=item Miscellaneous functions

=for Pod::Functions =Misc

L<C<defined>|/defined EXPR>, L<C<formline>|/formline PICTURE,LIST>,
L<C<lock>|/lock THING>, L<C<prototype>|/prototype FUNCTION>,
L<C<reset>|/reset EXPR>, L<C<scalar>|/scalar EXPR>,
L<C<undef>|/undef EXPR>

=item Functions for processes and process groups
X<process> X<pid> X<process id>

=for Pod::Functions =Process

L<C<alarm>|/alarm SECONDS>, L<C<exec>|/exec LIST>, L<C<fork>|/fork>,
L<C<getpgrp>|/getpgrp PID>, L<C<getppid>|/getppid>,
L<C<getpriority>|/getpriority WHICH,WHO>, L<C<kill>|/kill SIGNAL, LIST>,
L<C<pipe>|/pipe READHANDLE,WRITEHANDLE>,
L<C<qxE<sol>E<sol>>|/qxE<sol>STRINGE<sol>>,
L<C<readpipe>|/readpipe EXPR>, L<C<setpgrp>|/setpgrp PID,PGRP>,
L<C<setpriority>|/setpriority WHICH,WHO,PRIORITY>,
L<C<sleep>|/sleep EXPR>, L<C<system>|/system LIST>, L<C<times>|/times>,
L<C<wait>|/wait>, L<C<waitpid>|/waitpid PID,FLAGS>

=item Keywords related to Perl modules
X<module>

=for Pod::Functions =Modules

L<C<do>|/do EXPR>, L<C<import>|/import LIST>,
L<C<no>|/no MODULE VERSION LIST>, L<C<package>|/package NAMESPACE>,
L<C<require>|/require VERSION>, L<C<use>|/use Module VERSION LIST>

=item Keywords related to classes and object-orientation
X<object> X<class> X<package>

=for Pod::Functions =Objects

L<C<bless>|/bless REF,CLASSNAME>,
L<C<class>|/class NAMESPACE>,
L<C<__CLASS__>|/__CLASS__>,
L<C<dbmclose>|/dbmclose HASH>,
L<C<dbmopen>|/dbmopen HASH,DBNAME,MASK>,
L<C<field>|/field VARNAME>,
L<C<method>|/method NAME BLOCK>,
L<C<package>|/package NAMESPACE>,
L<C<ref>|/ref EXPR>,
L<C<tie>|/tie VARIABLE,CLASSNAME,LIST>,
L<C<tied>|/tied VARIABLE>,
L<C<untie>|/untie VARIABLE>,
L<C<use>|/use Module VERSION LIST>

=item Low-level socket functions
X<socket> X<sock>

=for Pod::Functions =Socket

L<C<accept>|/accept NEWSOCKET,GENERICSOCKET>,
L<C<bind>|/bind SOCKET,NAME>, L<C<connect>|/connect SOCKET,NAME>,
L<C<getpeername>|/getpeername SOCKET>,
L<C<getsockname>|/getsockname SOCKET>,
L<C<getsockopt>|/getsockopt SOCKET,LEVEL,OPTNAME>,
L<C<listen>|/listen SOCKET,QUEUESIZE>,
L<C<recv>|/recv SOCKET,SCALAR,LENGTH,FLAGS>,
L<C<send>|/send SOCKET,MSG,FLAGS,TO>,
L<C<setsockopt>|/setsockopt SOCKET,LEVEL,OPTNAME,OPTVAL>,
L<C<shutdown>|/shutdown SOCKET,HOW>,
L<C<socket>|/socket SOCKET,DOMAIN,TYPE,PROTOCOL>,
L<C<socketpair>|/socketpair SOCKET1,SOCKET2,DOMAIN,TYPE,PROTOCOL>

=item System V interprocess communication functions
X<IPC> X<System V> X<semaphore> X<shared memory> X<memory> X<message>

=for Pod::Functions =SysV

L<C<msgctl>|/msgctl ID,CMD,ARG>, L<C<msgget>|/msgget KEY,FLAGS>,
L<C<msgrcv>|/msgrcv ID,VAR,SIZE,TYPE,FLAGS>,
L<C<msgsnd>|/msgsnd ID,MSG,FLAGS>,
L<C<semctl>|/semctl ID,SEMNUM,CMD,ARG>,
L<C<semget>|/semget KEY,NSEMS,FLAGS>, L<C<semop>|/semop KEY,OPSTRING>,
L<C<shmctl>|/shmctl ID,CMD,ARG>, L<C<shmget>|/shmget KEY,SIZE,FLAGS>,
L<C<shmread>|/shmread ID,VAR,POS,SIZE>,
L<C<shmwrite>|/shmwrite ID,STRING,POS,SIZE>

=item Fetching user and group info
X<user> X<group> X<password> X<uid> X<gid>  X<passwd> X</etc/passwd>

=for Pod::Functions =User

L<C<endgrent>|/endgrent>, L<C<endhostent>|/endhostent>,
L<C<endnetent>|/endnetent>, L<C<endpwent>|/endpwent>,
L<C<getgrent>|/getgrent>, L<C<getgrgid>|/getgrgid GID>,
L<C<getgrnam>|/getgrnam NAME>, L<C<getlogin>|/getlogin>,
L<C<getpwent>|/getpwent>, L<C<getpwnam>|/getpwnam NAME>,
L<C<getpwuid>|/getpwuid UID>, L<C<setgrent>|/setgrent>,
L<C<setpwent>|/setpwent>

=item Fetching network info
X<network> X<protocol> X<host> X<hostname> X<IP> X<address> X<service>

=for Pod::Functions =Network

L<C<endprotoent>|/endprotoent>, L<C<endservent>|/endservent>,
L<C<gethostbyaddr>|/gethostbyaddr ADDR,ADDRTYPE>,
L<C<gethostbyname>|/gethostbyname NAME>, L<C<gethostent>|/gethostent>,
L<C<getnetbyaddr>|/getnetbyaddr ADDR,ADDRTYPE>,
L<C<getnetbyname>|/getnetbyname NAME>, L<C<getnetent>|/getnetent>,
L<C<getprotobyname>|/getprotobyname NAME>,
L<C<getprotobynumber>|/getprotobynumber NUMBER>,
L<C<getprotoent>|/getprotoent>,
L<C<getservbyname>|/getservbyname NAME,PROTO>,
L<C<getservbyport>|/getservbyport PORT,PROTO>,
L<C<getservent>|/getservent>, L<C<sethostent>|/sethostent STAYOPEN>,
L<C<setnetent>|/setnetent STAYOPEN>,
L<C<setprotoent>|/setprotoent STAYOPEN>,
L<C<setservent>|/setservent STAYOPEN>

=item Time-related functions
X<time> X<date>

=for Pod::Functions =Time

L<C<gmtime>|/gmtime EXPR>, L<C<localtime>|/localtime EXPR>,
L<C<time>|/time>, L<C<times>|/times>

=item Non-function keywords

=for Pod::Functions =!Non-functions

C<ADJUST>,
C<and>,
C<AUTOLOAD>,
C<BEGIN>,
C<catch>,
C<CHECK>,
C<cmp>,
C<CORE>,
C<__DATA__>,
C<default>,
C<defer>,
C<DESTROY>,
C<else>,
C<elseif>,
C<elsif>,
C<END>,
C<__END__>,
C<eq>,
C<finally>,
C<for>,
C<foreach>,
C<ge>,
C<given>,
C<gt>,
C<if>,
C<INIT>,
C<isa>,
C<le>,
C<lt>,
C<ne>,
C<not>,
C<or>,
C<try>,
C<UNITCHECK>,
C<unless>,
C<until>,
C<when>,
C<while>,
C<x>,
C<xor>

=back

=head2 Portability
X<portability> X<Unix> X<portable>

Perl was born in Unix and can therefore access all common Unix
system calls.  In non-Unix environments, the functionality of some
Unix system calls may not be available or details of the available
functionality may differ slightly.  The Perl functions affected
by this are:

L<C<-I<X>>|/-X FILEHANDLE>, L<C<binmode>|/binmode FILEHANDLE, LAYER>,
L<C<chmod>|/chmod LIST>, L<C<chown>|/chown LIST>,
L<C<chroot>|/chroot FILENAME>, L<C<crypt>|/crypt PLAINTEXT,SALT>,
L<C<dbmclose>|/dbmclose HASH>, L<C<dbmopen>|/dbmopen HASH,DBNAME,MASK>,
L<C<dump>|/dump LABEL>, L<C<endgrent>|/endgrent>,
L<C<endhostent>|/endhostent>, L<C<endnetent>|/endnetent>,
L<C<endprotoent>|/endprotoent>, L<C<endpwent>|/endpwent>,
L<C<endservent>|/endservent>, L<C<exec>|/exec LIST>,
L<C<fcntl>|/fcntl FILEHANDLE,FUNCTION,SCALAR>,
L<C<flock>|/flock FILEHANDLE,OPERATION>, L<C<fork>|/fork>,
L<C<getgrent>|/getgrent>, L<C<getgrgid>|/getgrgid GID>,
L<C<gethostbyname>|/gethostbyname NAME>, L<C<gethostent>|/gethostent>,
L<C<getlogin>|/getlogin>,
L<C<getnetbyaddr>|/getnetbyaddr ADDR,ADDRTYPE>,
L<C<getnetbyname>|/getnetbyname NAME>, L<C<getnetent>|/getnetent>,
L<C<getppid>|/getppid>, L<C<getpgrp>|/getpgrp PID>,
L<C<getpriority>|/getpriority WHICH,WHO>,
L<C<getprotobynumber>|/getprotobynumber NUMBER>,
L<C<getprotoent>|/getprotoent>, L<C<getpwent>|/getpwent>,
L<C<getpwnam>|/getpwnam NAME>, L<C<getpwuid>|/getpwuid UID>,
L<C<getservbyport>|/getservbyport PORT,PROTO>,
L<C<getservent>|/getservent>,
L<C<getsockopt>|/getsockopt SOCKET,LEVEL,OPTNAME>,
L<C<glob>|/glob EXPR>, L<C<ioctl>|/ioctl FILEHANDLE,FUNCTION,SCALAR>,
L<C<kill>|/kill SIGNAL, LIST>, L<C<link>|/link OLDFILE,NEWFILE>,
L<C<lstat>|/lstat FILEHANDLE>, L<C<msgctl>|/msgctl ID,CMD,ARG>,
L<C<msgget>|/msgget KEY,FLAGS>,
L<C<msgrcv>|/msgrcv ID,VAR,SIZE,TYPE,FLAGS>,
L<C<msgsnd>|/msgsnd ID,MSG,FLAGS>, L<C<open>|/open FILEHANDLE,MODE,EXPR>,
L<C<pipe>|/pipe READHANDLE,WRITEHANDLE>, L<C<readlink>|/readlink EXPR>,
L<C<rename>|/rename OLDNAME,NEWNAME>,
L<C<select>|/select RBITS,WBITS,EBITS,TIMEOUT>,
L<C<semctl>|/semctl ID,SEMNUM,CMD,ARG>,
L<C<semget>|/semget KEY,NSEMS,FLAGS>, L<C<semop>|/semop KEY,OPSTRING>,
L<C<setgrent>|/setgrent>, L<C<sethostent>|/sethostent STAYOPEN>,
L<C<setnetent>|/setnetent STAYOPEN>, L<C<setpgrp>|/setpgrp PID,PGRP>,
L<C<setpriority>|/setpriority WHICH,WHO,PRIORITY>,
L<C<setprotoent>|/setprotoent STAYOPEN>, L<C<setpwent>|/setpwent>,
L<C<setservent>|/setservent STAYOPEN>,
L<C<setsockopt>|/setsockopt SOCKET,LEVEL,OPTNAME,OPTVAL>,
L<C<shmctl>|/shmctl ID,CMD,ARG>, L<C<shmget>|/shmget KEY,SIZE,FLAGS>,
L<C<shmread>|/shmread ID,VAR,POS,SIZE>,
L<C<shmwrite>|/shmwrite ID,STRING,POS,SIZE>,
L<C<socket>|/socket SOCKET,DOMAIN,TYPE,PROTOCOL>,
L<C<socketpair>|/socketpair SOCKET1,SOCKET2,DOMAIN,TYPE,PROTOCOL>,
L<C<stat>|/stat FILEHANDLE>, L<C<symlink>|/symlink OLDFILE,NEWFILE>,
L<C<syscall>|/syscall NUMBER, LIST>,
L<C<sysopen>|/sysopen FILEHANDLE,FILENAME,MODE>,
L<C<system>|/system LIST>, L<C<times>|/times>,
L<C<truncate>|/truncate FILEHANDLE,LENGTH>, L<C<umask>|/umask EXPR>,
L<C<unlink>|/unlink LIST>, L<C<utime>|/utime LIST>, L<C<wait>|/wait>,
L<C<waitpid>|/waitpid PID,FLAGS>

For more information about the portability of these functions, see
L<perlport> and other available platform-specific documentation.

=head2 Alphabetical Listing of Perl Functions

=over

=item -X FILEHANDLE
X<-r>X<-w>X<-x>X<-o>X<-R>X<-W>X<-X>X<-O>X<-e>X<-z>X<-s>X<-f>X<-d>X<-l>X<-p>
X<-S>X<-b>X<-c>X<-t>X<-u>X<-g>X<-k>X<-T>X<-B>X<-M>X<-A>X<-C>

=item -X EXPR

=item -X DIRHANDLE

=item -X

=for Pod::Functions a file test (-r, -x, etc)

A file test, where X is one of the letters listed below.  This unary
operator takes one argument, either a filename, a filehandle, or a dirhandle,
and tests the associated file to see if something is true about it.  If the
argument is omitted, tests L<C<$_>|perlvar/$_>, except for C<-t>, which
tests STDIN.  Unless otherwise documented, it returns C<1> for true and
C<''> for false.  If the file doesn't exist or can't be examined, it
returns L<C<undef>|/undef EXPR> and sets L<C<$!>|perlvar/$!> (errno).
With the exception of the C<-l> test they all follow symbolic links
because they use C<stat()> and not C<lstat()> (so dangling symlinks can't
be examined and will therefore report failure).

Despite the funny names, precedence is the same as any other named unary
operator.  The operator may be any of:

    -r  File is readable by effective uid/gid.
    -w  File is writable by effective uid/gid.
    -x  File is executable by effective uid/gid.
    -o  File is owned by effective uid.

    -R  File is readable by real uid/gid.
    -W  File is writable by real uid/gid.
    -X  File is executable by real uid/gid.
    -O  File is owned by real uid.

    -e  File exists.
    -z  File has zero size (is empty).
    -s  File has nonzero size (returns size in bytes).

    -f  File is a plain file.
    -d  File is a directory.
    -l  File is a symbolic link (false if symlinks aren't
        supported by the file system).
    -p  File is a named pipe (FIFO), or Filehandle is a pipe.
    -S  File is a socket.
    -b  File is a block special file.
    -c  File is a character special file.
    -t  Filehandle is opened to a tty.

    -u  File has setuid bit set.
    -g  File has setgid bit set.
    -k  File has sticky bit set.

    -T  File is an ASCII or UTF-8 text file (heuristic guess).
    -B  File is a "binary" file (opposite of -T).

    -M  Script start time minus file modification time, in days.
    -A  Same for access time.
    -C  Same for inode change time (Unix, may differ for other
	platforms)

Example:

    while (<>) {
        chomp;
        next unless -f $_;  # ignore specials
        #...
    }

Note that C<-s/a/b/> does not do a negated substitution.  Saying
C<-exp($foo)> still works as expected, however: only single letters
following a minus are interpreted as file tests.

These operators are exempt from the "looks like a function rule" described
above.  That is, an opening parenthesis after the operator does not affect
how much of the following code constitutes the argument.  Put the opening
parentheses before the operator to separate it from code that follows (this
applies only to operators with higher precedence than unary operators, of
course):

    -s($file) + 1024   # probably wrong; same as -s($file + 1024)
    (-s $file) + 1024  # correct

The interpretation of the file permission operators C<-r>, C<-R>,
C<-w>, C<-W>, C<-x>, and C<-X> is by default based solely on the mode
of the file and the uids and gids of the user.  There may be other
reasons you can't actually read, write, or execute the file: for
example network filesystem access controls, ACLs (access control lists),
read-only filesystems, and unrecognized executable formats.  Note
that the use of these six specific operators to verify if some operation
is possible is usually a mistake, because it may be open to race
conditions.

Also note that, for the superuser on the local filesystems, the C<-r>,
C<-R>, C<-w>, and C<-W> tests always return 1, and C<-x> and C<-X> return 1
if any execute bit is set in the mode.  Scripts run by the superuser
may thus need to do a L<C<stat>|/stat FILEHANDLE> to determine the
actual mode of the file, or temporarily set their effective uid to
something else.

If you are using ACLs, there is a pragma called L<C<filetest>|filetest>
that may produce more accurate results than the bare
L<C<stat>|/stat FILEHANDLE> mode bits.
When under C<use filetest 'access'>, the above-mentioned filetests
test whether the permission can(not) be granted using the L<access(2)>
family of system calls.  Also note that the C<-x> and C<-X> tests may
under this pragma return true even if there are no execute permission
bits set (nor any extra execute permission ACLs).  This strangeness is
due to the underlying system calls' definitions.  Note also that, due to
the implementation of C<use filetest 'access'>, the C<_> special
filehandle won't cache the results of the file tests when this pragma is
in effect.  Read the documentation for the L<C<filetest>|filetest>
pragma for more information.

The C<-T> and C<-B> tests work as follows.  The first block or so of
the file is examined to see if it is valid UTF-8 that includes non-ASCII
characters.  If so, it's a C<-T> file.  Otherwise, that same portion of
the file is examined for odd characters such as strange control codes or
characters with the high bit set.  If more than a third of the
characters are strange, it's a C<-B> file; otherwise it's a C<-T> file.
Also, any file containing a zero byte in the examined portion is
considered a binary file.  (If executed within the scope of a L<S<use
locale>|perllocale> which includes C<LC_CTYPE>, odd characters are
anything that isn't a printable nor space in the current locale.)  If
C<-T> or C<-B> is used on a filehandle, the current IO buffer is
examined
rather than the first block.  Both C<-T> and C<-B> return true on an empty
file, or a file at EOF when testing a filehandle.  Because you have to
read a file to do the C<-T> test, on most occasions you want to use a C<-f>
against the file first, as in C<next unless -f $file && -T $file>.

If any of the file tests (or either the L<C<stat>|/stat FILEHANDLE> or
L<C<lstat>|/lstat FILEHANDLE> operator) is given the special filehandle
consisting of a solitary underline, then the stat structure of the
previous file test (or L<C<stat>|/stat FILEHANDLE> operator) is used,
saving a system call.  (This doesn't work with C<-t>, and you need to
remember that L<C<lstat>|/lstat FILEHANDLE> and C<-l> leave values in
the stat structure for the symbolic link, not the real file.)  (Also, if
the stat buffer was filled by an L<C<lstat>|/lstat FILEHANDLE> call,
C<-T> and C<-B> will reset it with the results of C<stat _>).
Example:

    print "Can do.\n" if -r $x || -w _ || -x _;

    stat($filename);
    print "Readable\n" if -r _;
    print "Writable\n" if -w _;
    print "Executable\n" if -x _;
    print "Setuid\n" if -u _;
    print "Setgid\n" if -g _;
    print "Sticky\n" if -k _;
    print "Text\n" if -T _;
    print "Binary\n" if -B _;

As of Perl 5.10.0, as a form of purely syntactic sugar, you can stack file
test operators, in a way that C<-f -w -x $file> is equivalent to
C<-x $file && -w _ && -f _>.  (This is only fancy syntax: if you use
the return value of C<-f $file> as an argument to another filetest
operator, no special magic will happen.)

Portability issues: L<perlport/-X>.

To avoid confusing would-be users of your code with mysterious
syntax errors, put something like this at the top of your script:

    use v5.10;  # so filetest ops can stack

=item abs VALUE
X<abs> X<absolute>

=item abs

=for Pod::Functions absolute value function

Returns the absolute value of its argument.
If VALUE is omitted, uses L<C<$_>|perlvar/$_>.

=item accept NEWSOCKET,GENERICSOCKET
X<accept>

=for Pod::Functions accept an incoming socket connect

Accepts an incoming socket connect, just as L<accept(2)>
does.  Returns the packed address if it succeeded, false otherwise.
See the example in L<perlipc/"Sockets: Client/Server Communication">.

On systems that support a close-on-exec flag on files, the flag will
be set for the newly opened file descriptor, as determined by the
value of L<C<$^F>|perlvar/$^F>.  See L<perlvar/$^F>.

=item alarm SECONDS
X<alarm>
X<SIGALRM>
X<timer>

=item alarm

=for Pod::Functions schedule a SIGALRM

Arranges to have a SIGALRM delivered to this process after the
specified number of wallclock seconds has elapsed.  If SECONDS is not
specified, the value stored in L<C<$_>|perlvar/$_> is used.  (On some
machines, unfortunately, the elapsed time may be up to one second less
or more than you specified because of how seconds are counted, and
process scheduling may delay the delivery of the signal even further.)

Only one timer may be counting at once.  Each call disables the
previous timer, and an argument of C<0> may be supplied to cancel the
previous timer without starting a new one.  The returned value is the
amount of time remaining on the previous timer.

For delays of finer granularity than one second, the L<Time::HiRes> module
(from CPAN, and starting from Perl 5.8 part of the standard
distribution) provides
L<C<ualarm>|Time::HiRes/ualarm ( $useconds [, $interval_useconds ] )>.
You may also use Perl's four-argument version of
L<C<select>|/select RBITS,WBITS,EBITS,TIMEOUT> leaving the first three
arguments undefined, or you might be able to use the
L<C<syscall>|/syscall NUMBER, LIST> interface to access L<setitimer(2)>
if your system supports it.  See L<perlfaq8> for details.

It is usually a mistake to intermix C<alarm> and
L<C<sleep>|/sleep EXPR> calls, because L<C<sleep>|/sleep EXPR> may be
internally implemented on your system with C<alarm>.

If you want to use C<alarm> to time out a system call
you need to use an L<C<eval>|/eval EXPR>/L<C<die>|/die LIST> pair.  You
can't rely on the alarm causing the system call to fail with
L<C<$!>|perlvar/$!> set to C<EINTR> because Perl sets up signal handlers
to restart system calls on some systems.  Using
L<C<eval>|/eval EXPR>/L<C<die>|/die LIST> always works, modulo the
caveats given in L<perlipc/"Signals">.

    eval {
        local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
        alarm $timeout;
        my $nread = sysread $socket, $buffer, $size;
        alarm 0;
    };
    if ($@) {
        die unless $@ eq "alarm\n";   # propagate unexpected errors
        # timed out
    }
    else {
        # didn't
    }

For more information see L<perlipc>.

Portability issues: L<perlport/alarm>.

=item all BLOCK LIST

=for Pod::Functions test if every value in a list satisfies the given condition

Evaluates the BLOCK for each element of the LIST (locally setting
L<C<$_>|perlvar/$_> to each element) and checks the truth of the result of
that block.  Returns true if every element makes the block yield true, or
returns false if at least one element makes the block false.

As soon as any element makes the block yield false, then the result of this
operator is determined.  It will short-circuit in that case and not consider
any further elements.

When used as a condition, this is similar to using L<C<grep>|/grep BLOCK LIST>
to count that every value satisfies the condition, except for this
short-circuit behaviour.

    if( all { length $_ } @strings ) {
        say "Every string is non-empty";
    }

is roughly equivalent to

    if( @strings == grep { length $_ } @strings ) ...

This operator is only available if the
L<C<keyword_all> feature|feature/"The 'keyword_all' feature"> is enabled.

It is currently considered B<experimental>, and will issue a compile-time
warning in the category C<experimental::all> unless that category is silenced.

=item any BLOCK LIST

=for Pod::Functions test if at least one value in a list satisfies the given condition

Evaluates the BLOCK for each element of the LIST (locally setting
L<C<$_>|perlvar/$_> to each element) and checks the truth of the result of
that block.  Returns true if at least one element makes the block yield
true, or returns false if no element is found to make it true.

As soon as any element makes the block yield true, then the result of this
operator is determined.  It will short-circuit in that case and not consider
any further elements.

When used as a condition, this is similar to L<C<grep>|/grep BLOCK LIST>,
except for this short-circuit behaviour.

    if( any { length $_ } @strings ) {
        say "At least one string is non-empty";
    }

is roughly equivalent to

    if( grep { length $_ } @strings ) ...

This operator is only available if the
L<C<keyword_any> feature|feature/"The 'keyword_any' feature"> is enabled.

It is currently considered B<experimental>, and will issue a compile-time
warning in the category C<experimental::any> unless that category is silenced.

=item atan2 Y,X
X<atan2> X<arctangent> X<tan> X<tangent>

=for Pod::Functions arctangent of Y/X in the range -PI to PI

Returns the arctangent of Y/X in the range -PI to PI.

For the tangent operation, you may use the
L<C<Math::Trig::tan>|Math::Trig/B<tan>> function, or use the familiar
relation:

    sub tan { sin($_[0]) / cos($_[0])  }

The return value for C<atan2(0,0)> is implementation-defined; consult
your L<atan2(3)> manpage for more information.

Portability issues: L<perlport/atan2>.

=item bind SOCKET,NAME
X<bind>

=for Pod::Functions binds an address to a socket

Binds a network address to a socket, just as L<bind(2)>
does.  Returns true if it succeeded, false otherwise.  NAME should be a
packed address of the appropriate type for the socket.  See the examples in
L<perlipc/"Sockets: Client/Server Communication">.

=item binmode FILEHANDLE, LAYER
X<binmode> X<binary> X<text> X<DOS> X<Windows>

=item binmode FILEHANDLE

=for Pod::Functions prepare binary files for I/O

Arranges for FILEHANDLE to be read or written in "binary" or "text"
mode on systems where the run-time libraries distinguish between
binary and text files.  If FILEHANDLE is an expression, the value is
taken as the name of the filehandle.  Returns true on success,
otherwise it returns L<C<undef>|/undef EXPR> and sets
L<C<$!>|perlvar/$!> (errno).

On some systems (in general, DOS- and Windows-based systems)
C<binmode> is necessary when you're not
working with a text file.  For the sake of portability it is a good idea
always to use it when appropriate, and never to use it when it isn't
appropriate.  Also, people can set their I/O to be by default
UTF8-encoded Unicode, not bytes.

In other words: regardless of platform, use
C<binmode> on binary data, like images,
for example.

If LAYER is present it is a single string, but may contain multiple
directives.  The directives alter the behaviour of the filehandle.
When LAYER is present, using binmode on a text file makes sense.

If LAYER is omitted or specified as C<:raw> the filehandle is made
suitable for passing binary data.  This includes turning off possible CRLF
translation and marking it as bytes (as opposed to Unicode characters).
Note that, despite what may be implied in I<"Programming Perl"> (the
Camel, 3rd edition) or elsewhere, C<:raw> is I<not> simply the inverse of C<:crlf>.
Other layers that would affect the binary nature of the stream are
I<also> disabled.  See L<PerlIO>, and the discussion about the PERLIO
environment variable in L<perlrun|perlrun/PERLIO>.

The C<:bytes>, C<:crlf>, C<:utf8>, and any other directives of the
form C<:...>, are called I/O I<layers>.  The L<open> pragma can be used to
establish default I/O layers.

I<The LAYER parameter of the C<binmode>
function is described as "DISCIPLINE" in "Programming Perl, 3rd
Edition".  However, since the publishing of this book, by many known as
"Camel III", the consensus of the naming of this functionality has moved
from "discipline" to "layer".  All documentation of this version of Perl
therefore refers to "layers" rather than to "disciplines".  Now back to
the regularly scheduled documentation...>

To mark FILEHANDLE as UTF-8, use C<:utf8> or C<:encoding(UTF-8)>.
C<:utf8> just marks the data as UTF-8 without further checking,
while C<:encoding(UTF-8)> checks the data for actually being valid
UTF-8.  More details can be found in L<PerlIO::encoding>.

In general, C<binmode> should be called
after L<C<open>|/open FILEHANDLE,MODE,EXPR> but before any I/O is done on the
filehandle.  Calling C<binmode> normally
flushes any pending buffered output data (and perhaps pending input
data) on the handle.  An exception to this is the C<:encoding> layer
that changes the default character encoding of the handle.
The C<:encoding> layer sometimes needs to be called in
mid-stream, and it doesn't flush the stream.  C<:encoding>
also implicitly pushes on top of itself the C<:utf8> layer because
internally Perl operates on UTF8-encoded Unicode characters.

The operating system, device drivers, C libraries, and Perl run-time
system all conspire to let the programmer treat a single
character (C<\n>) as the line terminator, irrespective of external
representation.  On many operating systems, the native text file
representation matches the internal representation, but on some
platforms the external representation of C<\n> is made up of more than
one character.

All variants of Unix, Mac OS (old and new), and Stream_LF files on VMS use
a single character to end each line in the external representation of text
(even though that single character is CARRIAGE RETURN on old, pre-Darwin
flavors of Mac OS, and is LINE FEED on Unix and most VMS files).  In other
systems like OS/2, DOS, and the various flavors of MS-Windows, your program
sees a C<\n> as a simple C<\cJ>, but what's stored in text files are the
two characters C<\cM\cJ>.  That means that if you don't use
C<binmode> on these systems, C<\cM\cJ>
sequences on disk will be converted to C<\n> on input, and any C<\n> in
your program will be converted back to C<\cM\cJ> on output.  This is
what you want for text files, but it can be disastrous for binary files.

Another consequence of using C<binmode>
(on some systems) is that special end-of-file markers will be seen as
part of the data stream.  For systems from the Microsoft family this
means that, if your binary data contain C<\cZ>, the I/O subsystem will
regard it as the end of the file, unless you use
C<binmode>.

C<binmode> is important not only for
L<C<readline>|/readline EXPR> and L<C<print>|/print FILEHANDLE LIST>
operations, but also when using
L<C<read>|/read FILEHANDLE,SCALAR,LENGTH,OFFSET>,
L<C<seek>|/seek FILEHANDLE,POSITION,WHENCE>,
L<C<sysread>|/sysread FILEHANDLE,SCALAR,LENGTH,OFFSET>,
L<C<syswrite>|/syswrite FILEHANDLE,SCALAR,LENGTH,OFFSET> and
L<C<tell>|/tell FILEHANDLE> (see L<perlport> for more details).  See the
L<C<$E<sol>>|perlvar/$E<sol>> and L<C<$\>|perlvar/$\> variables in
L<perlvar> for how to manually set your input and output
line-termination sequences.

Portability issues: L<perlport/binmode>.

=item bless REF,CLASSNAME
X<bless>

=item bless REF

=for Pod::Functions create an object

C<bless> tells Perl to mark the item referred to by C<REF> as an
object in a package.  The two-argument version of C<bless> is
always preferable unless there is a specific reason to I<not>
use it.

=over

=item * Bless the referred-to item into a specific package
(recommended form):

    bless $ref, $package;

The two-argument form adds the object to the package specified
as the second argument.

=item * Bless the referred-to item into package C<main>:

    bless $ref, "";

If the second argument is an empty string, C<bless> adds the
object to package C<main>.

=item * Bless the referred-to item into the current package (not
inheritable):

    bless $ref;

If C<bless> is used without its second argument, the object is
created in the current package. The second argument should
always be supplied if a derived class might inherit a method
executing C<bless>. Because it is a potential source of bugs,
one-argument C<bless> is discouraged.

=back

See L<perlobj> for more about the blessing (and blessings) of
objects.

C<bless> returns its first argument, the
supplied reference, as the value of the function; since C<bless>
is commonly the last thing executed in constructors, this means
that the reference to the object is returned as the
constructor's value and allows the caller to immediately use
this returned object in method calls.

C<CLASSNAME> should always be a mixed-case name, as
all-uppercase and all-lowercase names are meant to be used only
for Perl builtin types and pragmas, respectively. Avoid creating
all-uppercase or all-lowercase package names to prevent
confusion.

Also avoid C<bless>ing things into the class name C<0>; this
will cause code which (erroneously) checks the result of
C<ref> to see if a reference is C<bless>ed to fail,
as "0", a false value, is returned.

See L<perlmod/"Perl Modules"> for more details.

=item break

=for Pod::Functions +switch break out of a C<given> block

Break out of a C<given> block.

C<break> is available only if the
L<C<"switch"> feature|feature/The 'switch' feature> is enabled or if it
is prefixed with C<CORE::>. The
L<C<"switch"> feature|feature/The 'switch' feature> is enabled
automatically with a C<use v5.10> (or higher) declaration in the current
scope.

=item caller EXPR
X<caller> X<call stack> X<stack> X<stack trace>

=item caller

=for Pod::Functions get context of the current subroutine call

Returns the context of the current pure perl subroutine call.  In scalar
context, returns the caller's package name if there I<is> a caller (that is, if
we're in a subroutine or L<C<eval>|/eval EXPR> or
L<C<require>|/require VERSION>) and the undefined value otherwise.
C<caller> never returns XS subs and they are skipped.  The next pure perl
sub will appear instead of the XS sub in caller's return values.  In
list context, caller returns

       # 0         1          2
    my ($package, $filename, $line) = caller;

Like L<C<__FILE__>|/__FILE__> and L<C<__LINE__>|/__LINE__>, the filename and
line number returned here may be altered by the mechanism described at
L<perlsyn/"Plain Old Comments (Not!)">.

With EXPR, it returns some extra information that the debugger uses to
print a stack trace.  The value of EXPR indicates how many call frames
to go back before the current one.

    #  0         1          2      3            4
 my ($package, $filename, $line, $subroutine, $hasargs,

    #  5          6          7            8       9         10
    $wantarray, $evaltext, $is_require, $hints, $bitmask, $hinthash)
  = caller($i);

Here, $subroutine is the function that the caller called (rather than the
function containing the caller).  Note that $subroutine may be C<(eval)> if
the frame is not a subroutine call, but an L<C<eval>|/eval EXPR>.  In
such a case additional elements $evaltext and C<$is_require> are set:
C<$is_require> is true if the frame is created by a
L<C<require>|/require VERSION> or L<C<use>|/use Module VERSION LIST>
statement, $evaltext contains the text of the C<eval EXPR> statement.
In particular, for an C<eval BLOCK> statement, $subroutine is C<(eval)>,
but $evaltext is undefined.  (Note also that each
L<C<use>|/use Module VERSION LIST> statement creates a
L<C<require>|/require VERSION> frame inside an C<eval EXPR> frame.)
$subroutine may also be C<(unknown)> if this particular subroutine
happens to have been deleted from the symbol table.  C<$hasargs> is true
if a new instance of L<C<@_>|perlvar/@_> was set up for the frame.
C<$hints> and C<$bitmask> contain pragmatic hints that the caller was
compiled with.  C<$hints> corresponds to L<C<$^H>|perlvar/$^H>, and
C<$bitmask> corresponds to
L<C<${^WARNING_BITS}>|perlvar/${^WARNING_BITS}>.  The C<$hints> and
C<$bitmask> values are subject to change between versions of Perl, and
are not meant for external use.

C<$hinthash> is a reference to a hash containing the value of
L<C<%^H>|perlvar/%^H> when the caller was compiled, or
L<C<undef>|/undef EXPR> if L<C<%^H>|perlvar/%^H> was empty.  Do not
modify the values of this hash, as they are the actual values stored in
the optree.

Note that the only types of call frames that are visible are subroutine
calls and C<eval>. Other forms of context, such as C<while> or C<foreach>
loops or C<try> blocks are not considered interesting to C<caller>, as they
do not alter the behaviour of the C<return> expression.

Furthermore, when called from within the DB package in
list context, and with an argument, caller returns more
detailed information: it sets the list variable C<@DB::args> to be the
arguments with which the subroutine was invoked.

Be aware that the optimizer might have optimized call frames away before
C<caller> had a chance to get the information.  That
means that C<caller(N)> might not return information about the call
frame you expect it to, for C<< N > 1 >>.  In particular, C<@DB::args>
might have information from the previous time C<caller>
was called.

Be aware that setting C<@DB::args> is I<best effort>, intended for
debugging or generating backtraces, and should not be relied upon.  In
particular, as L<C<@_>|perlvar/@_> contains aliases to the caller's
arguments, Perl does not take a copy of L<C<@_>|perlvar/@_>, so
C<@DB::args> will contain modifications the subroutine makes to
L<C<@_>|perlvar/@_> or its contents, not the original values at call
time.  C<@DB::args>, like L<C<@_>|perlvar/@_>, does not hold explicit
references to its elements, so under certain cases its elements may have
become freed and reallocated for other variables or temporary values.
Finally, a side effect of the current implementation is that the effects
of C<shift @_> can I<normally> be undone (but not C<pop @_> or other
splicing, I<and> not if a reference to L<C<@_>|perlvar/@_> has been
taken, I<and> subject to the caveat about reallocated elements), so
C<@DB::args> is actually a hybrid of the current state and initial state
of L<C<@_>|perlvar/@_>.  Buyer beware.

=item chdir EXPR
X<chdir>
X<cd>
X<directory, change>

=item chdir FILEHANDLE

=item chdir DIRHANDLE

=item chdir

=for Pod::Functions change your current working directory

Changes the working directory to EXPR, if possible.  If EXPR is omitted,
changes to the directory specified by C<$ENV{HOME}>, if set; if not,
changes to the directory specified by C<$ENV{LOGDIR}>.  (Under VMS, the
variable C<$ENV{'SYS$LOGIN'}> is also checked, and used if it is set.)  If
neither is set, C<chdir> does nothing and fails.  It
returns true on success, false otherwise.  See the example under
L<C<die>|/die LIST>.

On systems that support L<fchdir(2)>, you may pass a filehandle or
directory handle as the argument.  On systems that don't support L<fchdir(2)>,
passing handles raises an exception.

=item chmod LIST
X<chmod> X<permission> X<mode>

=for Pod::Functions changes the permissions on a list of files

Changes the permissions of a list of files.  The first element of the
list must be the numeric mode, which should probably be an octal
number, and which definitely should I<not> be a string of octal digits:
C<0644> is okay, but C<"0644"> is not.  Returns the number of files
successfully changed.  See also L<C<oct>|/oct EXPR> if all you have is a
string.

    my $cnt = chmod 0755, "foo", "bar";
    chmod 0755, @executables;
    my $mode = "0644"; chmod $mode, "foo";      # !!! sets mode to
                                                # --w----r-T
    my $mode = "0644"; chmod oct($mode), "foo"; # this is better
    my $mode = 0644;   chmod $mode, "foo";      # this is best

On systems that support L<fchmod(2)>, you may pass filehandles among the
files.  On systems that don't support L<fchmod(2)>, passing filehandles raises
an exception.  Filehandles must be passed as globs or glob references to be
recognized; barewords are considered filenames.

    open(my $fh, "<", "foo");
    my $perm = (stat $fh)[2] & 07777;
    chmod($perm | 0600, $fh);

You can also import the symbolic C<S_I*> constants from the
L<C<Fcntl>|Fcntl> module:

    use Fcntl qw( :mode );
    chmod S_IRWXU|S_IRGRP|S_IXGRP|S_IROTH|S_IXOTH, @executables;
    # Identical to the chmod 0755 of the example above.

Portability issues: L<perlport/chmod>.

=item chomp VARIABLE
X<chomp> X<INPUT_RECORD_SEPARATOR> X<$/> X<newline> X<eol>

=item chomp( LIST )

=item chomp

=for Pod::Functions remove a trailing record separator from a string

This safer version of L<C<chop>|/chop VARIABLE> removes any trailing
string that corresponds to the current value of
L<C<$E<sol>>|perlvar/$E<sol>> (also known as C<$INPUT_RECORD_SEPARATOR>
in the L<C<English>|English> module).  It returns the total
number of characters removed from all its arguments.  It's often used to
remove the newline from the end of an input record when you're worried
that the final record may be missing its newline.  When in paragraph
mode (C<$/ = ''>), it removes all trailing newlines from the string.
When in slurp mode (C<$/ = undef>) or fixed-length record mode
(L<C<$E<sol>>|perlvar/$E<sol>> is a reference to an integer or the like;
see L<perlvar>), C<chomp> won't remove anything.
If VARIABLE is omitted, it chomps L<C<$_>|perlvar/$_>.  Example:

    while (<>) {
        chomp;  # avoid \n on last field
        my @array = split(/:/);
        # ...
    }

If VARIABLE is a hash, it chomps the hash's values, but not its keys,
resetting the L<C<each>|/each HASH> iterator in the process.

You can actually chomp anything that's an lvalue, including an assignment:

    chomp(my $cwd = `pwd`);
    chomp(my $answer = <STDIN>);

If you chomp a list, each element is chomped, and the total number of
characters removed is returned.

Note that parentheses are necessary when you're chomping anything
that is not a simple variable.  This is because C<chomp $cwd = `pwd`;>
is interpreted as C<(chomp $cwd) = `pwd`;>, rather than as
C<chomp( $cwd = `pwd` )> which you might expect.  Similarly,
C<chomp $x, $y> is interpreted as C<chomp($x), $y> rather than
as C<chomp($x, $y)>.

=item chop VARIABLE
X<chop>

=item chop( LIST )

=item chop

=for Pod::Functions remove the last character from a string

Chops off the last character of a string and returns the character
chopped.  It is much more efficient than C<s/.$//s> because it neither
scans nor copies the string.  If VARIABLE is omitted, chops
L<C<$_>|perlvar/$_>.
If VARIABLE is a hash, it chops the hash's values, but not its keys,
resetting the L<C<each>|/each HASH> iterator in the process.

You can actually chop anything that's an lvalue, including an assignment.

If you chop a list, each element is chopped.  Only the value of the
last C<chop> is returned.

Note that C<chop> returns the last character.  To
return all but the last character, use C<substr($string, 0, -1)>.

See also L<C<chomp>|/chomp VARIABLE>.

=item chown LIST
X<chown> X<owner> X<user> X<group>

=for Pod::Functions change the ownership on a list of files

Changes the owner (and group) of a list of files.  The first two
elements of the list must be the I<numeric> uid and gid, in that
order.  A value of -1 in either position is interpreted by most
systems to leave that value unchanged.  Returns the number of files
successfully changed.

    my $cnt = chown $uid, $gid, 'foo', 'bar';
    chown $uid, $gid, @filenames;

On systems that support L<fchown(2)>, you may pass filehandles among the
files.  On systems that don't support L<fchown(2)>, passing filehandles raises
an exception.  Filehandles must be passed as globs or glob references to be
recognized; barewords are considered filenames.

Here's an example that looks up nonnumeric uids in the passwd file:

    print "User: ";
    chomp(my $user = <STDIN>);
    print "Files: ";
    chomp(my $pattern = <STDIN>);

    my ($login,$pass,$uid,$gid) = getpwnam($user)
        or die "$user not in passwd file";

    my @ary = glob($pattern);  # expand filenames
    chown $uid, $gid, @ary;

On most systems, you are not allowed to change the ownership of the
file unless you're the superuser, although you should be able to change
the group to any of your secondary groups.  On insecure systems, these
restrictions may be relaxed, but this is not a portable assumption.
On POSIX systems, you can detect this condition this way:

    use POSIX qw(pathconf _PC_CHOWN_RESTRICTED);
    my $can_chown_giveaway =
        ! pathconf($path_of_interest, _PC_CHOWN_RESTRICTED);

Portability issues: L<perlport/chown>.

=item chr NUMBER
X<chr> X<character> X<ASCII> X<Unicode>

=item chr

=for Pod::Functions get character this number represents

Returns the character represented by that NUMBER in the character set.
For example, C<chr(65)> is C<"A"> in either ASCII or Unicode, and
C<chr(0x263a)> is a Unicode smiley face.

Negative values give the Unicode replacement character (C<chr(0xfffd)>),
except under the L<bytes> pragma, where the low eight bits of the value
(truncated to an integer) are used.

If NUMBER is omitted, uses L<C<$_>|perlvar/$_>.

For the reverse, use L<C<ord>|/ord EXPR>.

Note that characters from 128 to 255 (inclusive) are by default
internally not encoded as UTF-8 for backward compatibility reasons.

See L<perlunicode> for more about Unicode.

=item chroot FILENAME
X<chroot> X<root>

=item chroot

=for Pod::Functions make directory new root for path lookups

This function works like the system call by the same name: it makes the
named directory the new root directory for all further pathnames that
begin with a C</> by your process and all its children.  (It doesn't
change your current working directory, which is unaffected.)  For security
reasons, this call is restricted to the superuser.  If FILENAME is
omitted, does a C<chroot> to L<C<$_>|perlvar/$_>.

B<NOTE:>  It is mandatory for security to C<chdir("/")>
(L<C<chdir>|/chdir EXPR> to the root directory) immediately after a
C<chroot>, otherwise the current working directory
may be outside of the new root.

Portability issues: L<perlport/chroot>.

=item class NAMESPACE

=item class NAMESPACE VERSION

=item class NAMESPACE BLOCK

=item class NAMESPACE VERSION BLOCK

=for Pod::Functions declare a separate global namespace that is an object class

Declares the BLOCK or the rest of the compilation unit as being in the given
namespace, which implements an object class (see L<perlclass>).  This
behaves similarly to L<C<package>|/package NAMESPACE>, except that the
newly-created package behaves as a class.

=item close FILEHANDLE
X<close>

=item close

=for Pod::Functions close file (or pipe or socket) handle

Closes the file or pipe associated with the filehandle, flushes the IO
buffers, and closes the system file descriptor.  Returns true if those
operations succeed, and if no error was reported by any PerlIO layer,
and there was no existing error on the filehandle.

If there was an existing error on the filehandle, close will return
false and L<C<$!>|perlvar/$!> will be set to the error from the
failing operation, so you can safely use its value when reporting the
error.

Closes the currently selected filehandle if the argument is
omitted.

You don't have to close FILEHANDLE if you are immediately going to do
another L<C<open>|/open FILEHANDLE,MODE,EXPR> on it, because
L<C<open>|/open FILEHANDLE,MODE,EXPR> closes it for you.  (See
L<C<open>|/open FILEHANDLE,MODE,EXPR>.) However, an explicit
C<close> on an input file resets the line counter
(L<C<$.>|perlvar/$.>), while the implicit close done by
L<C<open>|/open FILEHANDLE,MODE,EXPR> does not.

If the filehandle came from a piped open, C<close>
returns false if one of the other syscalls involved fails or if its
program exits with non-zero status.  If the only problem was that the
program exited non-zero, L<C<$!>|perlvar/$!> will be set to C<0>.
Closing a pipe also waits for the process executing on the pipe to
exit--in case you wish to look at the output of the pipe afterwards--and
implicitly puts the exit status value of that command into
L<C<$?>|perlvar/$?> and
L<C<${^CHILD_ERROR_NATIVE}>|perlvar/${^CHILD_ERROR_NATIVE}>.

If there are multiple threads running, C<close> on
a filehandle from a piped open returns true without waiting for the
child process to terminate, if the filehandle is still open in another
thread.

Closing the read end of a pipe before the process writing to it at the
other end is done writing results in the writer receiving a SIGPIPE.  If
the other end can't handle that, be sure to read all the data before
closing the pipe.

Example:

    open(OUTPUT, '|sort >foo')  # pipe to sort
        or die "Can't start sort: $!";
    #...                        # print stuff to output
    close OUTPUT                # wait for sort to finish
        or warn $! ? "Error closing sort pipe: $!"
                   : "Exit status $? from sort";
    open(INPUT, 'foo')          # get sort's results
        or die "Can't open 'foo' for input: $!";

FILEHANDLE may be an expression whose value can be used as an indirect
filehandle, usually the real filehandle name or an autovivified handle.

If an error occurs when perl implicitly closes a handle, perl will
produce a L<warning|perldiag/"Warning: unable to close filehandle %s
properly: %s">.  Explicitly calling close on the handle prevents that
warning.

=item closedir DIRHANDLE
X<closedir>

=for Pod::Functions close directory handle

Closes a directory opened by L<C<opendir>|/opendir DIRHANDLE,EXPR> and
returns the success of that system call.

=item connect SOCKET,NAME
X<connect>

=for Pod::Functions connect to a remote socket

Attempts to connect to a remote socket, just like L<connect(2)>.
Returns true if it succeeded, false otherwise.  NAME should be a
packed address of the appropriate type for the socket.  See the examples in
L<perlipc/"Sockets: Client/Server Communication">.

=item continue BLOCK
X<continue>

=item continue

=for Pod::Functions optional trailing block in a while or foreach

When followed by a BLOCK, C<continue> is actually a
flow control statement rather than a function.  If there is a
C<continue> BLOCK attached to a BLOCK (typically in a
C<while> or C<foreach>), it is always executed just before the
conditional is about to be evaluated again, just like the third part of
a C<for> loop in C.  Thus it can be used to increment a loop variable,
even when the loop has been continued via the L<C<next>|/next LABEL>
statement (which is similar to the C C<continue>
statement).

L<C<last>|/last LABEL>, L<C<next>|/next LABEL>, or
L<C<redo>|/redo LABEL> may appear within a
C<continue> block; L<C<last>|/last LABEL> and
L<C<redo>|/redo LABEL> behave as if they had been executed within the
main block.  So will L<C<next>|/next LABEL>, but since it will execute a
C<continue> block, it may be more entertaining.

    while (EXPR) {
        ### redo always comes here
        do_something;
    } continue {
        ### next always comes here
        do_something_else;
        # then back to the top to re-check EXPR
    }
    ### last always comes here

Omitting the C<continue> section is equivalent to
using an empty one, logically enough, so L<C<next>|/next LABEL> goes
directly back to check the condition at the top of the loop.

When there is no BLOCK, C<continue> is a function
that falls through the current C<when> or C<default> block instead of
iterating a dynamically enclosing C<foreach> or exiting a lexically
enclosing C<given>.  In Perl 5.14 and earlier, this form of
C<continue> was only available when the
L<C<"switch"> feature|feature/The 'switch' feature> was enabled.  See
L<feature> and L<perlsyn/"Switch Statements"> for more information.

=item cos EXPR
X<cos> X<cosine> X<acos> X<arccosine>

=item cos

=for Pod::Functions cosine function

Returns the cosine of EXPR (expressed in radians).  If EXPR is omitted,
takes the cosine of L<C<$_>|perlvar/$_>.

For the inverse cosine operation, you may use the
L<C<Math::Trig::acos>|Math::Trig> function, or use this relation:

    sub acos { atan2( sqrt(1 - $_[0] * $_[0]), $_[0] ) }

=item crypt PLAINTEXT,SALT
X<crypt> X<digest> X<hash> X<salt> X<plaintext> X<password>
X<decrypt> X<cryptography> X<passwd> X<encrypt>

=for Pod::Functions one-way passwd-style encryption

Creates a digest string exactly like the L<crypt(3)> function in the C
library (assuming that you actually have a version there that has not
been extirpated as a potential munition).

C<crypt> is a one-way hash function.  The
PLAINTEXT and SALT are turned
into a short string, called a digest, which is returned.  The same
PLAINTEXT and SALT will always return the same string, but there is no
(known) way to get the original PLAINTEXT from the hash.  Small
changes in the PLAINTEXT or SALT will result in large changes in the
digest.

There is no decrypt function.  This function isn't all that useful for
cryptography (for that, look for F<Crypt> modules on your nearby CPAN
mirror) and the name "crypt" is a bit of a misnomer.  Instead it is
primarily used to check if two pieces of text are the same without
having to transmit or store the text itself.  An example is checking
if a correct password is given.  The digest of the password is stored,
not the password itself.  The user types in a password that is
C<crypt>'d with the same salt as the stored
digest.  If the two digests match, the password is correct.

When verifying an existing digest string you should use the digest as
the salt (like C<crypt($plain, $digest) eq $digest>).  The SALT used
to create the digest is visible as part of the digest.  This ensures
C<crypt> will hash the new string with the same
salt as the digest.  This allows your code to work with the standard
C<crypt> and with more exotic implementations.
In other words, assume nothing about the returned string itself nor
about how many bytes of SALT may matter.

Traditionally the result is a string of 13 bytes: two first bytes of
the salt, followed by 11 bytes from the set C<[./0-9A-Za-z]>, and only
the first eight bytes of PLAINTEXT mattered.  But alternative
hashing schemes (like MD5), higher level security schemes (like C2),
and implementations on non-Unix platforms may produce different
strings.

When choosing a new salt create a random two character string whose
characters come from the set C<[./0-9A-Za-z]> (like C<join '', ('.',
'/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64]>).  This set of
characters is just a recommendation; the characters allowed in
the salt depend solely on your system's crypt library, and Perl can't
restrict what salts C<crypt> accepts.

Here's an example that makes sure that whoever runs this program knows
their password:

    my $pwd = (getpwuid($<))[1];

    system "stty -echo";
    print "Password: ";
    chomp(my $word = <STDIN>);
    print "\n";
    system "stty echo";

    if (crypt($word, $pwd) ne $pwd) {
        die "Sorry...\n";
    } else {
        print "ok\n";
    }

Of course, typing in your own password to whoever asks you
for it is unwise.

The C<crypt> function is unsuitable for hashing
large quantities of data, not least of all because you can't get the
information back.  Look at the L<Digest> module for more robust
algorithms.

If using C<crypt> on a Unicode string (which
I<potentially> has characters with codepoints above 255), Perl tries to
make sense of the situation by trying to downgrade (a copy of) the
string back to an eight-bit byte string before calling
C<crypt> (on that copy).  If that works, good.
If not, C<crypt> dies with
L<C<Wide character in crypt>|perldiag/Wide character in %s>.

Portability issues: L<perlport/crypt>.

=item dbmclose HASH
X<dbmclose>

=for Pod::Functions breaks binding on a tied dbm file

[This function has been largely superseded by the
L<C<untie>|/untie VARIABLE> function.]

Breaks the binding between a DBM file and a hash.

Portability issues: L<perlport/dbmclose>.

=item dbmopen HASH,DBNAME,MASK
X<dbmopen> X<dbm> X<ndbm> X<sdbm> X<gdbm>

=for Pod::Functions create binding on a tied dbm file

[This function has been largely superseded by the
L<C<tie>|/tie VARIABLE,CLASSNAME,LIST> function.]

This binds a L<dbm(3)>, L<ndbm(3)>, L<sdbm(3)>, L<gdbm(3)>, or Berkeley
DB file to a hash.  HASH is the name of the hash.  (Unlike normal
L<C<open>|/open FILEHANDLE,MODE,EXPR>, the first argument is I<not> a
filehandle, even though it looks like one).  DBNAME is the name of the
database (without the F<.dir> or F<.pag> extension if any).  If the
database does not exist, it is created with protection specified by MASK
(as modified by the L<C<umask>|/umask EXPR>).  To prevent creation of
the database if it doesn't exist, you may specify a MASK of 0, and the
function will return a false value if it can't find an existing
database.  If your system supports only the older DBM functions, you may
make only one C<dbmopen> call in your
program.  In older versions of Perl, if your system had neither DBM nor
ndbm, calling C<dbmopen> produced a fatal
error; it now falls back to L<sdbm(3)>.

If you don't have write access to the DBM file, you can only read hash
variables, not set them.  If you want to test whether you can write,
either use file tests or try setting a dummy hash entry inside an
L<C<eval>|/eval EXPR> to trap the error.

Note that functions such as L<C<keys>|/keys HASH> and
L<C<values>|/values HASH> may return huge lists when used on large DBM
files.  You may prefer to use the L<C<each>|/each HASH> function to
iterate over large DBM files.  Example:

    # print out history file offsets
    dbmopen(%HIST,'/usr/lib/news/history',0666);
    while (($key,$val) = each %HIST) {
        print $key, ' = ', unpack('L',$val), "\n";
    }
    dbmclose(%HIST);

See also L<AnyDBM_File> for a more general description of the pros and
cons of the various dbm approaches, as well as L<DB_File> for a particularly
rich implementation.

You can control which DBM library you use by loading that library
before you call C<dbmopen>:

    use DB_File;
    dbmopen(%NS_Hist, "$ENV{HOME}/.netscape/history.db")
        or die "Can't open netscape history file: $!";

Portability issues: L<perlport/dbmopen>.

=item defined EXPR
X<defined> X<undef> X<undefined>

=item defined

=for Pod::Functions test whether a value, variable, or function is defined

Returns a Boolean value telling whether EXPR has a value other than the
undefined value L<C<undef>|/undef EXPR>.  If EXPR is not present,
L<C<$_>|perlvar/$_> is checked.

Many operations return L<C<undef>|/undef EXPR> to indicate failure, end
of file, system error, uninitialized variable, and other exceptional
conditions.  This function allows you to distinguish
L<C<undef>|/undef EXPR> from other values.  (A simple Boolean test will
not distinguish among L<C<undef>|/undef EXPR>, zero, the empty string,
and C<"0">, which are all equally false.)  Note that since
L<C<undef>|/undef EXPR> is a valid scalar, its presence doesn't
I<necessarily> indicate an exceptional condition: L<C<pop>|/pop ARRAY>
returns L<C<undef>|/undef EXPR> when its argument is an empty array,
I<or> when the element to return happens to be L<C<undef>|/undef EXPR>.

You may also use C<defined(&func)> to check whether subroutine C<func>
has ever been defined.  The return value is unaffected by any forward
declarations of C<func>.  A subroutine that is not defined
may still be callable: its package may have an C<AUTOLOAD> method that
makes it spring into existence the first time that it is called; see
L<perlsub>.

Use of C<defined> on aggregates (hashes and arrays) is
no longer supported. It used to report whether memory for that
aggregate had ever been allocated.  You should instead use a simple
test for size:

    if (@an_array) { print "has array elements\n" }
    if (%a_hash)   { print "has hash members\n"   }

When used on a hash element, it tells you whether the value is defined,
not whether the key exists in the hash.  Use L<C<exists>|/exists EXPR>
for the latter purpose.

Examples:

    print if defined $switch{D};
    print "$val\n" while defined($val = pop(@ary));
    die "Can't readlink $sym: $!"
        unless defined($value = readlink $sym);
    sub foo { defined &$bar ? $bar->(@_) : die "No bar"; }
    $debugging = 0 unless defined $debugging;

Note:  Many folks tend to overuse C<defined> and are
then surprised to discover that the number C<0> and C<""> (the
zero-length string) are, in fact, defined values.  For example, if you
say

    "ab" =~ /a(.*)b/;

The pattern match succeeds and C<$1> is defined, although it
matched "nothing".  It didn't really fail to match anything.  Rather, it
matched something that happened to be zero characters long.  This is all
very above-board and honest.  When a function returns an undefined value,
it's an admission that it couldn't give you an honest answer.  So you
should use C<defined> only when questioning the
integrity of what you're trying to do.  At other times, a simple
comparison to C<0> or C<""> is what you want.

See also L<C<undef>|/undef EXPR>, L<C<exists>|/exists EXPR>,
L<C<ref>|/ref EXPR>.

=item delete EXPR
X<delete>

=for Pod::Functions deletes a value from a hash

Given an expression that specifies an element or slice of a hash,
C<delete> deletes the specified elements from that hash
so that L<C<exists>|/exists EXPR> on that element no longer returns
true.  Setting a hash element to the undefined value does not remove its
key, but deleting it does; see L<C<exists>|/exists EXPR>.

In list context, usually returns the value or values deleted, or the last such
element in scalar context.  The return list's length corresponds to that of
the argument list: deleting non-existent elements returns the undefined value
in their corresponding positions. Since Perl 5.28, a
L<keyE<sol>value hash slice|perldata/KeyE<sol>Value Hash Slices> can be passed
to C<delete>, and the return value is a list of key/value pairs (two elements
for each item deleted from the hash).

C<delete> may also be used on arrays and array slices,
but its behavior is less straightforward.  Although
L<C<exists>|/exists EXPR> will return false for deleted entries,
deleting array elements never changes indices of existing values; use
L<C<shift>|/shift ARRAY> or L<C<splice>|/splice
ARRAY,OFFSET,LENGTH,LIST> for that.  However, if any deleted elements
fall at the end of an array, the array's size shrinks to the position of
the highest element that still tests true for L<C<exists>|/exists EXPR>,
or to 0 if none do.  In other words, an array won't have trailing
nonexistent elements after a delete.

B<WARNING:> Calling C<delete> on array values is
strongly discouraged.  The
notion of deleting or checking the existence of Perl array elements is not
conceptually coherent, and can lead to surprising behavior.

Deleting from L<C<%ENV>|perlvar/%ENV> modifies the environment.
Deleting from a hash tied to a DBM file deletes the entry from the DBM
file.  Deleting from a L<C<tied>|/tied VARIABLE> hash or array may not
necessarily return anything; it depends on the implementation of the
L<C<tied>|/tied VARIABLE> package's DELETE method, which may do whatever
it pleases.

The C<delete local EXPR> construct localizes the deletion to the current
block at run time.  Until the block exits, elements locally deleted
temporarily no longer exist.  See L<perlsub/"Localized deletion of elements
of composite types">.

    my %hash = (foo => 11, bar => 22, baz => 33);
    my $scalar = delete $hash{foo};         # $scalar is 11
    $scalar = delete @hash{qw(foo bar)}; # $scalar is 22
    my @array  = delete @hash{qw(foo baz)}; # @array  is (undef,33)

The following (inefficiently) deletes all the values of %HASH and @ARRAY:

    foreach my $key (keys %HASH) {
        delete $HASH{$key};
    }

    foreach my $index (0 .. $#ARRAY) {
        delete $ARRAY[$index];
    }

And so do these:

    delete @HASH{keys %HASH};

    delete @ARRAY[0 .. $#ARRAY];

But both are slower than assigning the empty list
or undefining %HASH or @ARRAY, which is the customary
way to empty out an aggregate:

    %HASH = ();     # completely empty %HASH
    undef %HASH;    # forget %HASH ever existed

    @ARRAY = ();    # completely empty @ARRAY
    undef @ARRAY;   # forget @ARRAY ever existed

The EXPR can be arbitrarily complicated provided its
final operation is an element or slice of an aggregate:

    delete $ref->[$x][$y]{$key};
    delete $ref->[$x][$y]->@{$key1, $key2, @morekeys};

    delete $ref->[$x][$y][$index];
    delete $ref->[$x][$y]->@[$index1, $index2, @moreindices];

=item die LIST
X<die> X<throw> X<exception> X<raise> X<$@> X<abort>

=for Pod::Functions raise an exception or bail out

C<die> raises an exception.  Inside an L<C<eval>|/eval EXPR>
the exception is stuffed into L<C<$@>|perlvar/$@> and the L<C<eval>|/eval
EXPR> is terminated with the undefined value.  If the exception is
outside of all enclosing L<C<eval>|/eval EXPR>s, then the uncaught
exception is printed to C<STDERR> and perl exits with an exit code
indicating failure.  If you need to exit the process with a specific
exit code, see L<C<exit>|/exit EXPR>.

Equivalent examples:

    die "Can't cd to spool: $!\n" unless chdir '/usr/spool/news';
    chdir '/usr/spool/news' or die "Can't cd to spool: $!\n"

Most of the time, C<die> is called with a string to use as the exception.
You may either give a single non-reference operand to serve as the
exception, or a list of two or more items, which will be stringified
and concatenated to make the exception.

If the string exception does not end in a newline, the current
script line number and input line number (if any) and a newline
are appended to it.  Note that the "input line number" (also
known as "chunk") is subject to whatever notion of "line" happens to
be currently in effect, and is also available as the special variable
L<C<$.>|perlvar/$.>.  See L<perlvar/"$/"> and L<perlvar/"$.">.

Hint: sometimes appending C<", stopped"> to your message will cause it
to make better sense when the string C<"at foo line 123"> is appended.
Suppose you are running script "canasta".

    die "/etc/games is no good";
    die "/etc/games is no good, stopped";

produce, respectively

    /etc/games is no good at canasta line 123.
    /etc/games is no good, stopped at canasta line 123.

If LIST was empty or made an empty string, and L<C<$@>|perlvar/$@>
already contains an exception value (typically from a previous
L<C<eval>|/eval EXPR>), then that value is reused after
appending C<"\t...propagated">.  This is useful for propagating exceptions:

    eval { ... };
    die unless $@ =~ /Expected exception/;

If LIST was empty or made an empty string,
and L<C<$@>|perlvar/$@> contains an object
reference that has a C<PROPAGATE> method, that method will be called
with additional file and line number parameters.  The return value
replaces the value in L<C<$@>|perlvar/$@>;  i.e., as if
C<< $@ = eval { $@->PROPAGATE(__FILE__, __LINE__) }; >> were called.

If LIST was empty or made an empty string, and L<C<$@>|perlvar/$@>
is also empty, then the string C<"Died"> is used.

You can also call C<die> with a reference argument, and if
this is trapped within an L<C<eval>|/eval EXPR>, L<C<$@>|perlvar/$@>
contains that reference.  This permits more elaborate exception handling
using objects that maintain arbitrary state about the exception.  Such a
scheme is sometimes preferable to matching particular string values of
L<C<$@>|perlvar/$@> with regular expressions.

Because Perl stringifies uncaught exception messages before display,
you'll probably want to overload stringification operations on
exception objects.  See L<overload> for details about that.
The stringified message should be non-empty, and should end in a newline,
in order to fit in with the treatment of string exceptions.
Also, because an exception object reference cannot be stringified
without destroying it, Perl doesn't attempt to append location or other
information to a reference exception.  If you want location information
with a complex exception object, you'll have to arrange to put the
location information into the object yourself.

Because L<C<$@>|perlvar/$@> is a global variable, be careful that
analyzing an exception caught by C<eval> doesn't replace the reference
in the global variable.  It's
easiest to make a local copy of the reference before any manipulations.
Here's an example:

    use Scalar::Util "blessed";

    eval { ... ; die Some::Module::Exception->new( FOO => "bar" ) };
    if (my $ev_err = $@) {
        if (blessed($ev_err)
            && $ev_err->isa("Some::Module::Exception")) {
            # handle Some::Module::Exception
        }
        else {
            # handle all other possible exceptions
        }
    }

If an uncaught exception results in interpreter exit, the exit code is
determined from the values of L<C<$!>|perlvar/$!> and
L<C<$?>|perlvar/$?> with this pseudocode:

    exit $! if $!;              # errno
    exit $? >> 8 if $? >> 8;    # child exit status
    exit 255;                   # last resort

As with L<C<exit>|/exit EXPR>, L<C<$?>|perlvar/$?> is set prior to
unwinding the call stack; any C<DESTROY> or C<END> handlers can then
alter this value, and thus Perl's exit code.

The intent is to squeeze as much possible information about the likely cause
into the limited space of the system exit code.  However, as
L<C<$!>|perlvar/$!> is the value of C's C<errno>, which can be set by
any system call, this means that the value of the exit code used by
C<die> can be non-predictable, so should not be relied
upon, other than to be non-zero.

You can arrange for a callback to be run just before the
C<die> does its deed, by setting the
L<C<$SIG{__DIE__}>|perlvar/%SIG> hook.  The associated handler is called
with the exception as an argument, and can change the exception,
if it sees fit, by
calling C<die> again.  See L<perlvar/%SIG> for details on
setting L<C<%SIG>|perlvar/%SIG> entries, and L<C<eval>|/eval EXPR> for some
examples.  Although this feature was to be run only right before your
program was to exit, this is not currently so: the
L<C<$SIG{__DIE__}>|perlvar/%SIG> hook is currently called even inside
L<C<eval>|/eval EXPR>ed blocks/strings!  If one wants the hook to do
nothing in such situations, put

    die @_ if $^S;

as the first line of the handler (see L<perlvar/$^S>).  Because
this promotes strange action at a distance, this counterintuitive
behavior may be fixed in a future release.

See also L<C<exit>|/exit EXPR>, L<C<warn>|/warn LIST>, and the L<Carp>
module.

=item do BLOCK
X<do> X<block>

=for Pod::Functions turn a BLOCK into a TERM

Not really a function.  Returns the value of the last command in the
sequence of commands indicated by BLOCK.  When modified by the C<while> or
C<until> loop modifier, executes the BLOCK once before testing the loop
condition.  (On other statements the loop modifiers test the conditional
first.)

C<do BLOCK> does I<not> count as a loop, so the loop control statements
L<C<next>|/next LABEL>, L<C<last>|/last LABEL>, or
L<C<redo>|/redo LABEL> cannot be used to leave or restart the block.
See L<perlsyn/Statement Modifiers> for alternative strategies.

=item do EXPR
X<do>

Uses the value of EXPR as a filename and executes the contents of the
file as a Perl script:

    # load the exact specified file (./ and ../ special-cased)
    do '/foo/stat.pl';
    do './stat.pl';
    do '../foo/stat.pl';

    # search for the named file within @INC
    do 'stat.pl';
    do 'foo/stat.pl';

C<do './stat.pl'> is largely like

    eval `cat stat.pl`;

except that it's more concise, runs no external processes, and keeps
track of the current filename for error messages. It also differs in that
code evaluated with C<do FILE> cannot see lexicals in the enclosing
scope; C<eval STRING> does.  It's the same, however, in that it does
reparse the file every time you call it, so you probably don't want
to do this inside a loop.

Using C<do> with a relative path (except for F<./> and F<../>), like

    do 'foo/stat.pl';

will search the L<C<@INC>|perlvar/@INC> directories, and update
L<C<%INC>|perlvar/%INC> if the file is found.  See L<perlvar/@INC>
and L<perlvar/%INC> for these variables. In particular, note that
whilst historically L<C<@INC>|perlvar/@INC> contained '.' (the
current directory) making these two cases equivalent, that is no
longer necessarily the case, as '.' is not included in C<@INC> by default
in perl versions 5.26.0 onwards. Instead, perl will now warn:

    do "stat.pl" failed, '.' is no longer in @INC;
    did you mean do "./stat.pl"?

If C<do> can read the file but cannot compile it, it
returns L<C<undef>|/undef EXPR> and sets an error message in
L<C<$@>|perlvar/$@>.  If C<do> cannot read the file, it
returns undef and sets L<C<$!>|perlvar/$!> to the error.  Always check
L<C<$@>|perlvar/$@> first, as compilation could fail in a way that also
sets L<C<$!>|perlvar/$!>.  If the file is successfully compiled,
C<do> returns the value of the last expression evaluated.

Inclusion of library modules is better done with the
L<C<use>|/use Module VERSION LIST> and L<C<require>|/require VERSION>
operators, which also do automatic error checking and raise an exception
if there's a problem.

You might like to use C<do> to read in a program
configuration file.  Manual error checking can be done this way:

    # Read in config files: system first, then user.
    # Beware of using relative pathnames here.
    for $file ("/share/prog/defaults.rc",
               "$ENV{HOME}/.someprogrc")
    {
        unless ($return = do $file) {
            warn "couldn't parse $file: $@" if $@;
            warn "couldn't do $file: $!"    unless defined $return;
            warn "couldn't run $file"       unless $return;
        }
    }

=item dump LABEL
X<dump> X<core> X<undump>

=item dump EXPR

=item dump

=for Pod::Functions create an immediate core dump

This function causes an immediate core dump.  See also the B<-u>
command-line switch in L<perlrun|perlrun/-u>, which does the same thing.
Primarily this is so that you can use the B<undump> program (not
supplied) to turn your core dump into an executable binary after
having initialized all your variables at the beginning of the
program.  When the new binary is executed it will begin by executing
a C<goto LABEL> (with all the restrictions that L<C<goto>|/goto LABEL>
suffers).
Think of it as a goto with an intervening core dump and reincarnation.
If C<LABEL> is omitted, restarts the program from the top.  The
C<dump EXPR> form, available starting in Perl 5.18.0, allows a name to be
computed at run time, being otherwise identical to C<dump LABEL>.

B<WARNING>: Any files opened at the time of the dump will I<not>
be open any more when the program is reincarnated, with possible
resulting confusion by Perl.

This function is now largely obsolete, mostly because it's very hard to
convert a core file into an executable.  As of Perl 5.30, it must be invoked
as C<CORE::dump()>.

Unlike most named operators, this has the same precedence as assignment.
It is also exempt from the looks-like-a-function rule, so
C<dump ("foo")."bar"> will cause "bar" to be part of the argument to
C<dump>.

Portability issues: L<perlport/dump>.

=item each HASH
X<each> X<hash, iterator>

=item each ARRAY
X<array, iterator>

=for Pod::Functions retrieve the next key/value pair from a hash or index/value from an array

When called on a hash in list context, returns a 2-element list
consisting of the key and value for the next element of a hash.
When called in scalar context, returns only the key (not the value).

When called on an array in list context, in Perl 5.12 and later, it
returns a 2-element list consisting of the index and value for the next
element of the array so that you can iterate over it; older Perls
consider this a syntax error.  When called in scalar context, returns
only the index in the array.

Hash entries are returned in an apparently random order.  The actual random
order is specific to a given hash; the exact same series of operations
on two hashes may result in a different order for each hash.  Any insertion
into the hash may change the order, as will any deletion, with the exception
that the most recent key returned by C<each> or
L<C<keys>|/keys HASH> may be deleted without changing the order.  So
long as a given hash is unmodified you may rely on
L<C<keys>|/keys HASH>, L<C<values>|/values HASH> and
C<each> to repeatedly return the same order
as each other.  See L<perlsec/"Algorithmic Complexity Attacks"> for
details on why hash order is randomized.  Aside from the guarantees
provided here, the exact details of Perl's hash algorithm and the hash
traversal order are subject to change in any release of Perl.

Array entries are returned lowest index first.

 my @colors = (qw(red, green, blue));
 while (my ($index, $value) = each @colors) {
     print "[$index] = $value\n";
 }

 [0] = red
 [1] = green
 [2] = blue

After C<each> has returned all entries from the hash or
array, the next call to C<each> returns the empty list in
list context and L<C<undef>|/undef EXPR> in scalar context; the next
call following I<that> one restarts iteration.  Each hash or array has
its own internal iterator, accessed by C<each>,
L<C<keys>|/keys HASH>, and L<C<values>|/values HASH>.  The iterator is
implicitly reset when C<each> has reached the end as just
described; it can be explicitly reset by calling L<C<keys>|/keys HASH>
or L<C<values>|/values HASH> on the hash or array, or by referencing
the hash (but not array) in list context.  If you add or delete
a hash's elements while iterating over it, the effect on the iterator is
unspecified; for example, entries may be skipped or duplicated--so don't
do that.  Exception: It is always safe to delete the item most recently
returned by C<each>, so the following code works properly:

    while (my ($key, $value) = each %hash) {
        print $key, "\n";
        delete $hash{$key};   # This is safe
    }

Tied hashes may have a different ordering behaviour to perl's hash
implementation.

The iterator used by C<each> is attached to the hash or array, and is
shared between all iteration operations applied to the same hash or array.
Thus all uses of C<each> on a particular hash or array advance the same
iterator location.  All uses of C<each> are also subject to having the
iterator reset by any use of C<keys> or C<values> on the same hash or
array, or by the hash (but not array) being referenced in list context.
This makes C<each>-based loops quite fragile: it is easy to arrive at
such a loop with the iterator already part way through the object, or to
accidentally clobber the iterator state during execution of the loop body.
It's easy enough to explicitly reset the iterator before starting a loop,
but there is no way to insulate the iterator state used by a loop from
the iterator state used by anything else that might execute during the
loop body.

This extends to using C<each> on the result of an anonymous hash or
array constructor.  A new underlying array or hash is created each
time so each will always start iterating from scratch, eg:

  # loops forever
  while (my ($key, $value) = each %{ +{ a => 1 } }) {
      print "$key=$value\n";
  }

To avoid these problems resulting from the hash-embedded iterator, use a
L<C<foreach>|perlsyn/"Foreach Loops"> loop rather than C<while>-C<each>.
As of Perl 5.36, you can iterate over both keys and values directly with
a multiple-value C<foreach> loop.

  # retrieves the keys one time for iteration
  # iteration is unaffected by any operations on %hash within
  foreach my $key (keys %hash) {
      my $value = $hash{$key};
      $hash{$key} = {keys => scalar keys %hash, outer => [%hash]};
      some_function_that_may_mess_with(\%hash, $key, $value);
      $hash{"new$key"} = delete $hash{$key};
  }

  # Perl 5.36+
  foreach my ($key, $value) (%{ +{ a => 1 } }) {
      print "$key=$value\n";
  }

This prints out your environment like the L<printenv(1)> program,
but in a different order:

    while (my ($key,$value) = each %ENV) {
        print "$key=$value\n";
    }

Starting with Perl 5.14, an experimental feature allowed
C<each> to take a scalar expression. This experiment has
been deemed unsuccessful, and was removed as of Perl 5.24.

As of Perl 5.18 you can use a bare C<each> in a C<while>
loop, which will set L<C<$_>|perlvar/$_> on every iteration.
If either an C<each> expression or an explicit assignment of an C<each>
expression to a scalar is used as a C<while>/C<for> condition, then
the condition actually tests for definedness of the expression's value,
not for its regular truth value.

    while (each %ENV) {
	print "$_=$ENV{$_}\n";
    }

To avoid confusing would-be users of your code who are running earlier
versions of Perl with mysterious syntax errors, put this sort of thing at
the top of your file to signal that your code will work I<only> on Perls of
a recent vintage:

    use v5.12;	# so keys/values/each work on arrays
    use v5.18;	# so each assigns to $_ in a lone while test

See also L<C<keys>|/keys HASH>, L<C<values>|/values HASH>, and
L<C<sort>|/sort SUBNAME LIST>.

=item eof FILEHANDLE
X<eof>
X<end of file>
X<end-of-file>

=item eof ()

=item eof

=for Pod::Functions test a filehandle for its end

Returns 1 if the next read on FILEHANDLE will return end of file I<or> if
FILEHANDLE is not open.  FILEHANDLE may be an expression whose value
gives the real filehandle.  (Note that this function actually
reads a character and then C<ungetc>s it, so isn't useful in an
interactive context.)  Do not read from a terminal file (or call
C<eof(FILEHANDLE)> on it) after end-of-file is reached.  File types such
as terminals may lose the end-of-file condition if you do.

An C<eof> without an argument uses the last file
read.  Using C<eof()> with empty parentheses is
different.  It refers to the pseudo file formed from the files listed on
the command line and accessed via the C<< <> >> operator.  Since
C<< <> >> isn't explicitly opened, as a normal filehandle is, an
C<eof()> before C<< <> >> has been used will cause
L<C<@ARGV>|perlvar/@ARGV> to be examined to determine if input is
available.   Similarly, an C<eof()> after C<< <> >>
has returned end-of-file will assume you are processing another
L<C<@ARGV>|perlvar/@ARGV> list, and if you haven't set
L<C<@ARGV>|perlvar/@ARGV>, will read input from C<STDIN>; see
L<perlop/"I/O Operators">.

In a C<< while (<>) >> loop, C<eof> or C<eof(ARGV)>
can be used to detect the end of each file, whereas
C<eof()> will detect the end of the very last file
only.  Examples:

    # reset line numbering on each input file
    while (<>) {
        next if /^\s*#/;  # skip comments
        print "$.\t$_";
    } continue {
        close ARGV if eof;  # Not eof()!
    }

    # insert dashes just before last line of last file
    while (<>) {
        if (eof()) {  # check for end of last file
            print "--------------\n";
        }
        print;
        last if eof();     # needed if we're reading from a terminal
    }

Practical hint: you almost never need to use C<eof>
in Perl, because the input operators typically return L<C<undef>|/undef
EXPR> when they run out of data or encounter an error.

=item eval EXPR
X<eval> X<try> X<catch> X<evaluate> X<parse> X<execute>
X<error, handling> X<exception, handling>

=item eval BLOCK

=item eval

=for Pod::Functions catch exceptions or compile and run code

C<eval> in all its forms is used to execute a little Perl program,
trapping any errors encountered so they don't crash the calling program.

Plain C<eval> with no argument is just C<eval EXPR>, where the
expression is understood to be contained in L<C<$_>|perlvar/$_>.  Thus
there are only two real C<eval> forms; the one with an EXPR is often
called "string eval".  In a string eval, the value of the expression
(which is itself determined within scalar context) is first parsed, and
if there were no errors, executed as a block within the lexical context
of the current Perl program.  This form is typically used to delay
parsing and subsequent execution of the text of EXPR until run time.
Note that the value is parsed every time the C<eval> executes.

The other form is called "block eval".  It is less general than string
eval, but the code within the BLOCK is parsed only once (at the same
time the code surrounding the C<eval> itself was parsed) and executed
within the context of the current Perl program.  This form is typically
used to trap exceptions more efficiently than the first, while also
providing the benefit of checking the code within BLOCK at compile time.
BLOCK is parsed and compiled just once.  Since errors are trapped, it
often is used to check if a given feature is available.

In both forms, the value returned is the value of the last expression
evaluated inside the mini-program; a return statement may also be used, just
as with subroutines.  The expression providing the return value is evaluated
in void, scalar, or list context, depending on the context of the
C<eval> itself.  See L<C<wantarray>|/wantarray> for more
on how the evaluation context can be determined.

If there is a syntax error or runtime error, or a L<C<die>|/die LIST>
statement is executed, C<eval> returns
L<C<undef>|/undef EXPR> in scalar context, or an empty list in list
context, and L<C<$@>|perlvar/$@> is set to the error message.  (Prior to
5.16, a bug caused L<C<undef>|/undef EXPR> to be returned in list
context for syntax errors, but not for runtime errors.) If there was no
error, L<C<$@>|perlvar/$@> is set to the empty string.  A control flow
operator like L<C<last>|/last LABEL> or L<C<goto>|/goto LABEL> can
bypass the setting of L<C<$@>|perlvar/$@>.  Beware that using
C<eval> neither silences Perl from printing warnings to
STDERR, nor does it stuff the text of warning messages into
L<C<$@>|perlvar/$@>.  To do either of those, you have to use the
L<C<$SIG{__WARN__}>|perlvar/%SIG> facility, or turn off warnings inside
the BLOCK or EXPR using S<C<no warnings 'all'>>.  See
L<C<warn>|/warn LIST>, L<perlvar>, and L<warnings>.

Note that, because C<eval> traps otherwise-fatal errors,
it is useful for determining whether a particular feature (such as
L<C<socket>|/socket SOCKET,DOMAIN,TYPE,PROTOCOL> or
L<C<symlink>|/symlink OLDFILE,NEWFILE>) is implemented.  It is also
Perl's exception-trapping mechanism, where the L<C<die>|/die LIST>
operator is used to raise exceptions.

Before Perl 5.14, the assignment to L<C<$@>|perlvar/$@> occurred before
restoration
of localized variables, which means that for your code to run on older
versions, a temporary is required if you want to mask some, but not all
errors:

 # alter $@ on nefarious repugnancy only
 {
    my $e;
    {
      local $@; # protect existing $@
      eval { test_repugnancy() };
      # $@ =~ /nefarious/ and die $@; # Perl 5.14 and higher only
      $@ =~ /nefarious/ and $e = $@;
    }
    die $e if defined $e
 }

There are some different considerations for each form:

=over 4

=item String eval

Since the return value of EXPR is executed as a block within the lexical
context of the current Perl program, any outer lexical variables are
visible to it, and any package variable settings or subroutine and
format definitions remain afterwards.

Note that when C<BEGIN {}> blocks are embedded inside of an eval block
the contents of the block will be executed immediately and before the rest
of the eval code is executed. You can disable this entirely by

   local ${^MAX_NESTED_EVAL_BEGIN_BLOCKS} = 0;
   eval $string;

which will cause any embedded C<BEGIN> blocks in C<$string> to throw an
exception.

=over 4

=item Under the L<C<"unicode_eval"> feature|feature/The 'unicode_eval' and 'evalbytes' features>

If this feature is enabled (which is the default under a C<use 5.16> or
higher declaration), Perl assumes that EXPR is a character string.
Any S<C<use utf8>> or S<C<no utf8>> declarations within
the string thus have no effect. Source filters are forbidden as well.
(C<unicode_strings>, however, can appear within the string.)

See also the L<C<evalbytes>|/evalbytes EXPR> operator, which works properly
with source filters.

=item Outside the C<"unicode_eval"> feature

In this case, the behavior is problematic and is not so easily
described.  Here are two bugs that cannot easily be fixed without
breaking existing programs:

=over 4

=item *

Perl's internal storage of EXPR affects the behavior of the executed code.
For example:

    my $v = eval "use utf8; '$expr'";

If $expr is C<"\xc4\x80"> (U+0100 in UTF-8), then the value stored in C<$v>
will depend on whether Perl stores $expr "upgraded" (cf. L<utf8>) or
not:

=over

=item * If upgraded, C<$v> will be C<"\xc4\x80"> (i.e., the
C<use utf8> has no effect.)

=item * If non-upgraded, C<$v> will be C<"\x{100}">.

=back

This is undesirable since being
upgraded or not should not affect a string's behavior.

=item *

Source filters activated within C<eval> leak out into whichever file
scope is currently being compiled.  To give an example with the CPAN module
L<Semi::Semicolons>:

 BEGIN { eval "use Semi::Semicolons; # not filtered" }
 # filtered here!

L<C<evalbytes>|/evalbytes EXPR> fixes that to work the way one would
expect:

 use feature "evalbytes";
 BEGIN { evalbytes "use Semi::Semicolons; # filtered" }
 # not filtered

=back

=back

Problems can arise if the string expands a scalar containing a floating
point number.  That scalar can expand to letters, such as C<"NaN"> or
C<"Infinity">; or, within the scope of a L<C<use locale>|locale>, the
decimal point character may be something other than a dot (such as a
comma).  None of these are likely to parse as you are likely expecting.

You should be especially careful to remember what's being looked at
when:

    eval $x;        # CASE 1
    eval "$x";      # CASE 2

    eval '$x';      # CASE 3
    eval { $x };    # CASE 4

    eval "\$$x++";  # CASE 5
    $$x++;          # CASE 6

Cases 1 and 2 above behave identically: they run the code contained in
the variable $x.  (Although case 2 has misleading double quotes making
the reader wonder what else might be happening (nothing is).)  Cases 3
and 4 likewise behave in the same way: they run the code C<'$x'>, which
does nothing but return the value of $x.  (Case 4 is preferred for
purely visual reasons, but it also has the advantage of compiling at
compile-time instead of at run-time.)  Case 5 is a place where
normally you I<would> like to use double quotes, except that in this
particular situation, you can just use symbolic references instead, as
in case 6.

An C<eval ''> executed within a subroutine defined
in the C<DB> package doesn't see the usual
surrounding lexical scope, but rather the scope of the first non-DB piece
of code that called it.  You don't normally need to worry about this unless
you are writing a Perl debugger.

The final se
