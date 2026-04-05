--                                                              -*-haskell-*-
-- ---------------------------------------------------------------------------
-- (c) The University of Glasgow 1997-2003
---
-- The GHC grammar.
--
-- Author(s): Simon Marlow, Sven Panne 1997, 1998, 1999
-- ---------------------------------------------------------------------------
{
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MonadComprehensions #-}

-- | This module provides the generated Happy parser for Haskell. It exports
-- a number of parsers which may be used in any library that uses the GHC API.
-- A common usage pattern is to initialize the parser state with a given string
-- and then parse that string:
--
-- @
--     runParser :: ParserOpts -> String -> P a -> ParseResult a
--     runParser opts str parser = unP parser parseState
--     where
--       filename = "\<interactive\>"
--       location = mkRealSrcLoc (mkFastString filename) 1 1
--       buffer = stringToStringBuffer str
--       parseState = initParserState opts buffer location
-- @
module GHC.Parser
   ( parseModule, parseSignature, parseImport, parseStatement, parseBackpack
   , parseDeclaration, parseExpression, parsePattern
   , parseTypeSignature
   , parseStmt, parseIdentifier
   , parseType, parseHeader
   , parseModuleNoHaddock
   )
where

-- base
import Control.Monad      ( unless, liftM, when, (<=<) )
import GHC.Exts
import Data.Maybe         ( maybeToList )
import Data.List.NonEmpty ( NonEmpty(..), head, init, last, tail )
import qualified Data.List.NonEmpty as NE
import qualified Prelude -- for happy-generated code

import GHC.Hs
import GHC.Hs.Decls.Overlap ( OverlapMode(..) )

import GHC.Driver.Backpack.Syntax

import GHC.Unit.Info
import GHC.Unit.Module
import GHC.Unit.Module.Warnings

import GHC.Data.OrdList
import GHC.Data.BooleanFormula ( BooleanFormula(..), LBooleanFormula, mkTrue )
import GHC.Data.FastString
import GHC.Data.Maybe          ( orElse )

import GHC.Utils.Outputable
import GHC.Utils.Error
import GHC.Utils.Misc          ( looksLikePackageName, fstOf3, sndOf3, thdOf3 )
import GHC.Utils.Panic
import GHC.Prelude hiding ( head, init, last, tail )
import qualified GHC.Data.Strict as Strict

import GHC.Types.Name.Reader
import GHC.Types.Name.Occurrence ( varName, dataName, tcClsName, tvName, occNameFS, mkVarOccFS)
import GHC.Types.SrcLoc
import GHC.Types.Basic
import GHC.Types.Error ( GhcHint(..) )
import GHC.Types.Fixity
import GHC.Types.ForeignCall
import GHC.Types.InlinePragma
import GHC.Types.SourceFile
import GHC.Types.SourceText
import GHC.Types.PkgQual

import GHC.Core.Type    ( Specificity(..) )
import GHC.Core.Class   ( FunDep )
import GHC.Core.DataCon ( DataCon, dataConName )

import GHC.Parser.PostProcess
import GHC.Parser.PostProcess.Haddock
import GHC.Parser.Lexer
import GHC.Parser.HaddockLex
import GHC.Parser.Annotation
import GHC.Parser.Errors.Types
import GHC.Parser.Errors.Ppr ()
import GHC.Parser.String

import GHC.Builtin.Types ( unitTyCon, unitDataCon, sumTyCon,
                           tupleTyCon, tupleDataCon, nilDataCon,
                           unboxedUnitTyCon, unboxedUnitDataCon,
                           listTyCon_RDR, consDataCon_RDR,
                           unrestrictedFunTyCon )

import Language.Haskell.Syntax.Basic (FieldLabelString(..))

import qualified Data.Semigroup as Semi
}

%expect 0 -- shift/reduce conflicts

{- Note [shift/reduce conflicts]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The 'happy' tool turns this grammar into an efficient parser that follows the
shift-reduce parsing model. There's a parse stack that contains items parsed so
far (both terminals and non-terminals). Every next token produced by the lexer
results in one of two actions:

  SHIFT:    push the token onto the parse stack

  REDUCE:   pop a few items off the parse stack and combine them
            with a function (reduction rule)

However, sometimes it's unclear which of the two actions to take.
Consider this code example:

    if x then y else f z

There are two ways to parse it:

    (if x then y else f) z
    if x then y else (f z)

How is this determined? At some point, the parser gets to the following state:

  parse stack:  'if' exp 'then' exp 'else' "f"
  next token:   "z"

Scenario A (simplified):

  1. REDUCE, parse stack: 'if' exp 'then' exp 'else' exp
             next token:  "z"
        (Note that "f" reduced to exp here)

  2. REDUCE, parse stack: exp
             next token:  "z"

  3. SHIFT,  parse stack: exp "z"
             next token:  ...

  4. REDUCE, parse stack: exp
             next token:  ...

  This way we get:  (if x then y else f) z

Scenario B (simplified):

  1. SHIFT,  parse stack: 'if' exp 'then' exp 'else' "f" "z"
             next token:  ...

  2. REDUCE, parse stack: 'if' exp 'then' exp 'else' exp
             next token:  ...

  3. REDUCE, parse stack: exp
             next token:  ...

  This way we get:  if x then y else (f z)

The end result is determined by the chosen action. When Happy detects this, it
reports a shift/reduce conflict. At the top of the file, we have the following
directive:

  %expect 0

It means that we expect no unresolved shift/reduce conflicts in this grammar.
If you modify the grammar and get shift/reduce conflicts, follow the steps
below to resolve them.

STEP ONE
  is to figure out what causes the conflict.
  That's where the -i flag comes in handy:

      happy -agc --strict compiler/GHC/Parser.y -idetailed-info

  By analysing the output of this command, in a new file `detailed-info`, you
  can figure out which reduction rule causes the issue. At the top of the
  generated report, you will see a line like this:

      state 147 contains 67 shift/reduce conflicts.

  Scroll down to section State 147 (in your case it could be a different
  state). The start of the section lists the reduction rules that can fire
  and shows their context:

        exp10 -> fexp .                 (rule 492)
        fexp -> fexp . aexp             (rule 498)
        fexp -> fexp . PREFIX_AT atype  (rule 499)

  And then, for every token, it tells you the parsing action:

        ']'            reduce using rule 492
        '::'           reduce using rule 492
        '('            shift, and enter state 178
        QVARID         shift, and enter state 44
        DO             shift, and enter state 182
        ...

  But if you look closer, some of these tokens also have another parsing action
  in parentheses:

        QVARID    shift, and enter state 44
                   (reduce using rule 492)

  That's how you know rule 492 is causing trouble.
  Scroll back to the top to see what this rule is:

        ----------------------------------
        Grammar
        ----------------------------------
        ...
        ...
        exp10 -> fexp                (492)
        optSemi -> ';'               (493)
        ...
        ...

  Hence the shift/reduce conflict is caused by this parser production:

        exp10 :: { ECP }
                : '-' fexp    { ... }
                | fexp        { ... }    -- problematic rule

STEP TWO
  is to mark the problematic rule with the %shift pragma. This signals to
  'happy' that any shift/reduce conflicts involving this rule must be resolved
  in favor of a shift. There's currently no dedicated pragma to resolve in
  favor of the reduce.

STEP THREE
  is to add a dedicated Note for this specific conflict, as is done for all
  other conflicts below.
-}

{- Note [%shift: rule_activation -> {- empty -}]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    rule -> STRING . rule_activation rule_foralls infixexp '=' exp

Example:
    {-# RULES "name" [0] f = rhs #-}

Ambiguity:
    If we reduced, then we'd get an empty activation rule, and [0] would be
    parsed as part of the left-hand side expression.

    We shift, so [0] is parsed as an activation rule.
-}

{- Note [%shift: rule_foralls -> {- empty -}]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    rule -> STRING rule_activation . rule_foralls infixexp '=' exp

Example:
    {-# RULES "name" forall a1. lhs = rhs #-}

Ambiguity:
    If we reduced, then we would get an empty rule_foralls; the 'forall', being
    a valid term-level identifier, would be parsed as part of the left-hand
    side expression.

    We shift, so the 'forall' is parsed as part of rule_foralls.
-}

{- Note [%shift: type -> btype]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    context -> btype .
    type -> btype .
    type -> btype . '->' ctype
    type -> btype . '->.' ctype

Example:
    a :: Maybe Integer -> Bool

Ambiguity:
    If we reduced, we would get:   (a :: Maybe Integer) -> Bool
    We shift to get this instead:  a :: (Maybe Integer -> Bool)
-}

{- Note [%shift: infixtype -> ftype]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    infixtype -> ftype .
    infixtype -> ftype . tyop infixtype
    ftype -> ftype . tyarg
    ftype -> ftype . PREFIX_AT tyarg

Example:
    a :: Maybe Integer

Ambiguity:
    If we reduced, we would get:    (a :: Maybe) Integer
    We shift to get this instead:   a :: (Maybe Integer)
-}

{- Note [%shift: atype -> tyvar]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    atype -> tyvar .
    tv_bndr_no_braces -> '(' tyvar . '::' kind ')'

Example:
    class C a where type D a = (a :: Type ...

Ambiguity:
    If we reduced, we could specify a default for an associated type like this:

      class C a where type D a
                      type D a = (a :: Type)

    But we shift in order to allow injectivity signatures like this:

      class C a where type D a = (r :: Type) | r -> a
-}

{- Note [%shift: exp -> infixexp]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    exp -> infixexp . '::' sigtype
    exp -> infixexp . '-<' exp
    exp -> infixexp . '>-' exp
    exp -> infixexp . '-<<' exp
    exp -> infixexp . '>>-' exp
    exp -> infixexp .
    infixexp -> infixexp . qop exp10p

Examples:
    1) if x then y else z -< e
    2) if x then y else z :: T
    3) if x then y else z + 1   -- (NB: '+' is in VARSYM)

Ambiguity:
    If we reduced, we would get:

      1) (if x then y else z) -< e
      2) (if x then y else z) :: T
      3) (if x then y else z) + 1

    We shift to get this instead:

      1) if x then y else (z -< e)
      2) if x then y else (z :: T)
      3) if x then y else (z + 1)
-}

{- Note [%shift: exp10 -> '-' fexp]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    exp10 -> '-' fexp .
    fexp -> fexp . aexp
    fexp -> fexp . PREFIX_AT atype

Examples & Ambiguity:
    Same as in Note [%shift: exp10 -> fexp],
    but with a '-' in front.
-}

{- Note [%shift: exp10 -> fexp]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    exp10 -> fexp .
    fexp -> fexp . aexp
    fexp -> fexp . PREFIX_AT atype

Examples:
    1) if x then y else f z
    2) if x then y else f @z

Ambiguity:
    If we reduced, we would get:

      1) (if x then y else f) z
      2) (if x then y else f) @z

    We shift to get this instead:

      1) if x then y else (f z)
      2) if x then y else (f @z)
-}

{- Note [%shift: aexp2 -> ipvar]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    aexp2 -> ipvar .
    dbind -> ipvar . '=' exp

Example:
    let ?x = ...

Ambiguity:
    If we reduced, ?x would be parsed as the LHS of a normal binding,
    eventually producing an error.

    We shift, so it is parsed as the LHS of an implicit binding.
-}

{- Note [%shift: aexp2 -> TH_TY_QUOTE]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    aexp2 -> TH_TY_QUOTE . tyvar
    aexp2 -> TH_TY_QUOTE . gtycon
    aexp2 -> TH_TY_QUOTE .

Examples:
    1) x = ''
    2) x = ''a
    3) x = ''T

Ambiguity:
    If we reduced, the '' would result in reportEmptyDoubleQuotes even when
    followed by a type variable or a type constructor. But the only reason
    this reduction rule exists is to improve error messages.

    Naturally, we shift instead, so that ''a and ''T work as expected.
-}

{- Note [%shift: tup_tail -> {- empty -}]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    tup_exprs -> commas . tup_tail
    sysdcon_nolist -> '(' commas . ')'
    sysdcon_nolist -> '(#' commas . '#)'
    commas -> commas . ','

Example:
    (,,)

Ambiguity:
    A tuple section with no components is indistinguishable from the Haskell98
    data constructor for a tuple.

    If we reduced, (,,) would be parsed as a tuple section.
    We shift, so (,,) is parsed as a data constructor.

    This is preferable because we want to accept (,,) without -XTupleSections.
    See also Note [ExplicitTuple] in GHC.Hs.Expr.
-}

{- Note [%shift: qtyconop -> qtyconsym]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    oqtycon -> '(' qtyconsym . ')'
    qtyconop -> qtyconsym .

Example:
    foo :: (:%)

Ambiguity:
    If we reduced, (:%) would be parsed as a parenthesized infix type
    expression without arguments, resulting in the 'failOpFewArgs' error.

    We shift, so it is parsed as a type constructor.
-}

{- Note [%shift: special_id -> 'group']
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    transformqual -> 'then' 'group' . 'using' exp
    transformqual -> 'then' 'group' . 'by' exp 'using' exp
    special_id -> 'group' .

Example:
    [ ... | then group by dept using groupWith
          , then take 5 ]

Ambiguity:
    If we reduced, 'group' would be parsed as a term-level identifier, just as
    'take' in the other clause.

    We shift, so it is parsed as part of the 'group by' clause introduced by
    the -XTransformListComp extension.
-}

{- Note [%shift: activation -> {- empty -}]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:
    sigdecl -> '{-# INLINE' . activation qvarcon '#-}'
    activation -> {- empty -}
    activation -> explicit_activation

Example:

    {-# INLINE [0] Something #-}

Ambiguity:
    We don't know whether the '[' is the start of the activation or the beginning
    of the [] data constructor.
    We parse this as having '[0]' activation for inlining 'Something', rather than
    empty activation and inlining '[0] Something'.
-}

{- Note [%shift: orpats -> exp]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Context:

    texp -> exp .
    orpats -> exp .
    texp -> exp . '->' texp
    orpats -> exp . ';' orpats

    in Lookahead ')': reduce/reduce conflict between the two first productions

Example:

    f (True) = 3
       ----^

Ambiguity:
    We don't know whether the ')' encloses a parenthesized pat (reduce with
    first production) or a unary Or pattern (reduce with second production).
    We want to parse it as a parenthesized pat, because
      * That is the status quo
      * Parsing it as a unary Or patterns prompts the user to activate -XOrPatterns.
    Thus, we add a %shift pragma to `orpats -> exp` to lower its precedence,
    which has the effect of letting `texp -> exp` win (!).

An alternative to resolve this ambiguity would be to accept only OrPatterns
with at least two patterns in `orpats`, just as in `tup_exprs`.
But the present code seems simpler, because it just needs one non-terminal,
at the expense of using a small pragma.
-}

{- Note [Parser API Annotations]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
A lot of the productions are now cluttered with calls to
aa,am,acs,acsA etc.

These are helper functions to make sure that the locations of the
various keywords such as do / let / in are captured for use by tools
that want to do source to source conversions, such as refactorers or
structured editors.

The helper functions are defined at the bottom of this file.

See
  https://gitlab.haskell.org/ghc/ghc/wikis/api-annotations and
  https://gitlab.haskell.org/ghc/ghc/wikis/ghc-ast-annotations
for some background.

-}

{- Note [Parsing lists]
~~~~~~~~~~~~~~~~~~~~~~~
You might be wondering why we spend so much effort encoding our lists this
way:

importdecls
        : importdecls ';' importdecl
        | importdecls ';'
        | importdecl
        | {- empty -}

This might seem like an awfully roundabout way to declare a list; plus, to add
insult to injury you have to reverse the results at the end.  The answer is that
left recursion prevents us from running out of stack space when parsing long
sequences. See:
https://haskell-happy.readthedocs.io/en/latest/using.html#parsing-sequences
for more guidance.

By adding/removing branches, you can affect what lists are accepted.  Here
are the most common patterns, rewritten as regular expressions for clarity:

    -- Equivalent to: ';'* (x ';'+)* x?  (can be empty, permits leading/trailing semis)
    xs : xs ';' x
       | xs ';'
       | x
       | {- empty -}

    -- Equivalent to x (';' x)* ';'*  (non-empty, permits trailing semis)
    xs : xs ';' x
       | xs ';'
       | x

    -- Equivalent to ';'* alts (';' alts)* ';'* (non-empty, permits leading/trailing semis)
    alts : alts1
         | ';' alts
    alts1 : alts1 ';' alt
          | alts1 ';'
          | alt

    -- Equivalent to x (',' x)+ (non-empty, no trailing semis)
    xs : x
       | x ',' xs
-}

%token
 '_'            { L _ ITunderscore }            -- Haskell keywords
 'as'           { L _ ITas }
 'case'         { L _ ITcase }
 'class'        { L _ ITclass }
 'data'         { L _ ITdata }
 'default'      { L _ ITdefault }
 'deriving'     { L _ ITderiving }
 'else'         { L _ ITelse }
 'hiding'       { L _ IThiding }
 'if'           { L _ ITif }
 'import'       { L _ ITimport }
 'in'           { L _ ITin }
 'infix'        { L _ ITinfix }
 'infixl'       { L _ ITinfixl }
 'infixr'       { L _ ITinfixr }
 'instance'     { L _ ITinstance }
 'let'          { L _ ITlet }
 'module'       { L _ ITmodule }
 'newtype'      { L _ ITnewtype }
 'of'           { L _ ITof }
 'qualified'    { L _ ITqualified }
 'then'         { L _ ITthen }
 'type'         { L _ ITtype }
 'where'        { L _ ITwhere }

 'forall'       { L _ (ITforall _) }                -- GHC extension keywords
 'foreign'      { L _ ITforeign }
 'export'       { L _ ITexport }
 'label'        { L _ ITlabel }
 'dynamic'      { L _ ITdynamic }
 'safe'         { L _ ITsafe }
 'interruptible' { L _ ITinterruptible }
 'unsafe'       { L _ ITunsafe }
 'family'       { L _ ITfamily }
 'role'         { L _ ITrole }
 'stdcall'      { L _ ITstdcallconv }
 'ccall'        { L _ ITccallconv }
 'capi'         { L _ ITcapiconv }
 'prim'         { L _ ITprimcallconv }
 'javascript'   { L _ ITjavascriptcallconv }
 'proc'         { L _ ITproc }          -- for arrow notation extension
 'rec'          { L _ ITrec }           -- for arrow notation extension
 'group'    { L _ ITgroup }     -- for list transform extension
 'by'       { L _ ITby }        -- for list transform extension
 'using'    { L _ ITusing }     -- for list transform extension
 'pattern'      { L _ ITpattern } -- for pattern synonyms
 'static'       { L _ ITstatic }  -- for static pointers extension
 'stock'        { L _ ITstock }    -- for DerivingStrategies extension
 'anyclass'     { L _ ITanyclass } -- for DerivingStrategies extension
 'via'          { L _ ITvia }      -- for DerivingStrategies extension
 'splice'       { L _ ITsplice }   -- For StagedImports extension
 'quote'        { L _ ITquote }    -- For StagedImports extension

 'unit'         { L _ ITunit }
 'signature'    { L _ ITsignature }
 'dependency'   { L _ ITdependency }

 '{-# INLINE'             { L _ (ITinline_prag _ _ _) } -- INLINE or INLINABLE
 '{-# OPAQUE'             { L _ (ITopaque_prag _) }
 '{-# SPECIALISE'         { L _ (ITspec_prag _) }
 '{-# SPECIALISE_INLINE'  { L _ (ITspec_inline_prag _ _) }
 '{-# SOURCE'             { L _ (ITsource_prag _) }
 '{-# RULES'              { L _ (ITrules_prag _) }
 '{-# SCC'                { L _ (ITscc_prag _)}
 '{-# DEPRECATED'         { L _ (ITdeprecated_prag _) }
 '{-# WARNING'            { L _ (ITwarning_prag _) }
 '{-# UNPACK'             { L _ (ITunpack_prag _) }
 '{-# NOUNPACK'           { L _ (ITnounpack_prag _) }
 '{-# ANN'                { L _ (ITann_prag _) }
 '{-# MINIMAL'            { L _ (ITminimal_prag _) }
 '{-# CTYPE'              { L _ (ITctype _) }
 '{-# OVERLAPPING'        { L _ (IToverlapping_prag _) }
 '{-# OVERLAPPABLE'       { L _ (IToverlappable_prag _) }
 '{-# OVERLAPS'           { L _ (IToverlaps_prag _) }
 '{-# INCOHERENT'         { L _ (ITincoherent_prag _) }
 '{-# COMPLETE'           { L _ (ITcomplete_prag _)   }
 '#-}'                    { L _ ITclose_prag }

 '..'           { L _ ITdotdot }                        -- reserved symbols
 ':'            { L _ ITcolon }
 '::'           { L _ (ITdcolon _) }
 '='            { L _ ITequal }
 '\\'           { L _ ITlam }
 'lcase'        { L _ ITlcase }
 'lcases'       { L _ ITlcases }
 '|'            { L _ ITvbar }
 '<-'           { L _ (ITlarrow _) }
 '->'           { L _ (ITrarrow _) }
 '->.'          { L _ ITlolly }
 TIGHT_INFIX_AT { L _ ITat }
 '=>'           { L _ (ITdarrow _) }
 '-'            { L _ ITminus }
 PREFIX_TILDE   { L _ ITtilde }
 PREFIX_BANG    { L _ ITbang }
 PREFIX_MINUS   { L _ ITprefixminus }
 '*'            { L _ (ITstar _) }
 '-<'           { L _ (ITlarrowtail _) }            -- for arrow notation
 '>-'           { L _ (ITrarrowtail _) }            -- for arrow notation
 '-<<'          { L _ (ITLarrowtail _) }            -- for arrow notation
 '>>-'          { L _ (ITRarrowtail _) }            -- for arrow notation
 '.'            { L _ ITdot }
 PREFIX_PROJ    { L _ (ITproj True) }               -- RecordDotSyntax
 TIGHT_INFIX_PROJ { L _ (ITproj False) }            -- RecordDotSyntax
 PREFIX_AT      { L _ ITtypeApp }
 PREFIX_PERCENT { L _ ITpercent }                   -- for linear types

 '{'            { L _ ITocurly }                        -- special symbols
 '}'            { L _ ITccurly }
 vocurly        { L _ ITvocurly } -- virtual open curly (from layout)
 vccurly        { L _ ITvccurly } -- virtual close curly (from layout)
 '['            { L _ ITobrack }
 ']'            { L _ ITcbrack }
 '('            { L _ IToparen }
 ')'            { L _ ITcparen }
 '(#'           { L _ IToubxparen }
 '#)'           { L _ ITcubxparen }
 '(|'           { L _ (IToparenbar _) }
 '|)'           { L _ (ITcparenbar _) }
 ';'            { L _ ITsemi }
 ','            { L _ ITcomma }
 '`'            { L _ ITbackquote }
 SIMPLEQUOTE    { L _ ITsimpleQuote      }     -- 'x

 VARID          { L _ (ITvarid    _) }          -- identifiers
 CONID          { L _ (ITconid    _) }
 VARSYM         { L _ (ITvarsym   _) }
 CONSYM         { L _ (ITconsym   _) }
 QVARID         { L _ (ITqvarid   _) }
 QCONID         { L _ (ITqconid   _) }
 QVARSYM        { L _ (ITqvarsym  _) }
 QCONSYM        { L _ (ITqconsym  _) }


 -- QualifiedDo
 DO             { L _ (ITdo  _) }
 MDO            { L _ (ITmdo _) }

 IPDUPVARID     { L _ (ITdupipvarid   _) }              -- GHC extension
 LABELVARID     { L _ (ITlabelvarid _ _) }

 CHAR           { L _ (ITchar   _ _) }
 QUALSTRING     { L _ (ITstring _ StringMeta{strMetaQualified = Just _} _) }
 STRING         { L _ (ITstring _ _ _) }
 INTEGER        { L _ (ITinteger _) }
 RATIONAL       { L _ (ITrational _) }

 PRIMCHAR       { L _ (ITprimchar   _ _) }
 PRIMSTRING     { L _ (ITprimstring _ _) }
 PRIMINTEGER    { L _ (ITprimint    _ _) }
 PRIMWORD       { L _ (ITprimword   _ _) }
 PRIMINTEGER8   { L _ (ITprimint8   _ _) }
 PRIMINTEGER16  { L _ (ITprimint16  _ _) }
 PRIMINTEGER32  { L _ (ITprimint32  _ _) }
 PRIMINTEGER64  { L _ (ITprimint64  _ _) }
 PRIMWORD8      { L _ (ITprimword8  _ _) }
 PRIMWORD16     { L _ (ITprimword16 _ _) }
 PRIMWORD32     { L _ (ITprimword32 _ _) }
 PRIMWORD64     { L _ (ITprimword64 _ _) }
 PRIMFLOAT      { L _ (ITprimfloat  _) }
 PRIMDOUBLE     { L _ (ITprimdouble _) }

-- Template Haskell
'[|'            { L _ (ITopenExpQuote _ _) }
'[p|'           { L _ ITopenPatQuote  }
'[t|'           { L _ ITopenTypQuote  }
'[d|'           { L _ ITopenDecQuote  }
'|]'            { L _ (ITcloseQuote _) }
'[||'           { L _ (ITopenTExpQuote _) }
'||]'           { L _ ITcloseTExpQuote  }
PREFIX_DOLLAR   { L _ ITdollar }
PREFIX_DOLLAR_DOLLAR { L _ ITdollardollar }
TH_TY_QUOTE     { L _ ITtyQuote       }      -- ''T
TH_QUASIQUOTE   { L _ (ITquasiQuote _) }
TH_QQUASIQUOTE  { L _ (ITqQuasiQuote _) }

%monad { P } { >>= } { return }
%lexer { (lexer True) } { L _ ITeof }
  -- Replace 'lexer' above with 'lexerDbg'
  -- to dump the tokens fed to the parser.
%tokentype { (Located Token) }

-- Exported parsers
%name parseModuleNoHaddock module
%name parseSignatureNoHaddock signature
%name parseImport importdecl
%name parseStatement e_stmt
%name parseDeclaration topdecl
%name parseExpression exp
%name parsePattern pat
%name parseTypeSignature sigdecl
%name parseStmt   maybe_stmt
%name parseIdentifier  identifier
%name parseType ktype
%name parseBackpack backpack
%partial parseHeader header
%%

-----------------------------------------------------------------------------
-- Identifiers; one of the entry points
identifier :: { LocatedN RdrName }
        : qvar                          { $1 }
        | qcon                          { $1 }
        | qvarop                        { $1 }
        | qconop                        { $1 }
    | '->'              {% amsr (sLL $1 $> $ getRdrName unrestrictedFunTyCon)
                                (NameAnnRArrow  Nothing (epUniTok $1) Nothing []) }

-----------------------------------------------------------------------------
-- Backpack stuff

backpack :: { [LHsUnit PackageName] }
         : implicit_top units close { fromOL $2 }
         | '{' units '}'            { fromOL $2 }

units :: { OrdList (LHsUnit PackageName) }
         : units ';' unit { $1 `appOL` unitOL $3 }
         | units ';'      { $1 }
         | unit           { unitOL $1 }

unit :: { LHsUnit PackageName }
        : 'unit' pkgname 'where' unitbody
            { sL1 $1 $ HsUnit { hsunitName = $2
                              , hsunitBody = fromOL $4 } }

unitid :: { LHsUnitId PackageName }
        : pkgname                  { sL1 $1 $ HsUnitId $1 [] }
        | pkgname '[' msubsts ']'  { sLL $1 $> $ HsUnitId $1 (fromOL $3) }

msubsts :: { OrdList (LHsModuleSubst PackageName) }
        : msubsts ',' msubst { $1 `appOL` unitOL $3 }
        | msubsts ','        { $1 }
        | msubst             { unitOL $1 }

msubst :: { LHsModuleSubst PackageName }
        : modid '=' moduleid { sLL $1 $> $ (reLoc $1, $3) }
        | modid VARSYM modid VARSYM { sLL $1 $> $ (reLoc $1, sLL $2 $> $ HsModuleVar (reLoc $3)) }

moduleid :: { LHsModuleId PackageName }
          : VARSYM modid VARSYM { sLL $1 $> $ HsModuleVar (reLoc $2) }
          | unitid ':' modid    { sLL $1 $> $ HsModuleId $1 (reLoc $3) }

pkgname :: { Located PackageName }
        : STRING     { sL1 $1 $ PackageName (getSTRING $1) }
        | litpkgname { sL1 $1 $ PackageName (unLoc $1) }

litpkgname_segment :: { Located FastString }
        : VARID  { sL1 $1 $ getVARID $1 }
        | CONID  { sL1 $1 $ getCONID $1 }
        | special_id { $1 }

-- Parse a minus sign regardless of whether -XLexicalNegation is turned on or off.
-- See Note [Minus tokens] in GHC.Parser.Lexer
HYPHEN :: { () }
      : '-'          { () }
      | PREFIX_MINUS { () }
      | VARSYM       { () }

litpkgname :: { Located FastString }
        : litpkgname_segment { $1 }
        -- a bit of a hack, means p - b is parsed same as p-b, enough for now.
        | litpkgname_segment HYPHEN litpkgname  { sLL $1 $> $ concatFS [unLoc $1, fsLit "-", (unLoc $3)] }

mayberns :: { Maybe [LRenaming] }
        : {- empty -} { Nothing }
        | '(' rns ')' { Just (fromOL $2) }

rns :: { OrdList LRenaming }
        : rns ',' rn { $1 `appOL` unitOL $3 }
        | rns ','    { $1 }
        | rn         { unitOL $1 }

rn :: { LRenaming }
        : modid 'as' modid { sLL $1 $> $ Renaming (reLoc $1) (Just (reLoc $3)) }
        | modid            { sL1 $1    $ Renaming (reLoc $1) Nothing }

unitbody :: { OrdList (LHsUnitDecl PackageName) }
        : '{'     unitdecls '}'   { $2 }
        | vocurly unitdecls close { $2 }

unitdecls :: { OrdList (LHsUnitDecl PackageName) }
        : unitdecls ';' unitdecl { $1 `appOL` unitOL $3 }
        | unitdecls ';'         { $1 }
        | unitdecl              { unitOL $1 }

unitdecl :: { LHsUnitDecl PackageName }
        : 'module' maybe_src modid maybe_warning_pragma maybeexports 'where' body
             -- XXX not accurate
             { sL1 $1 $ DeclD
                 (case snd $2 of
                   NotBoot -> HsSrcFile
                   IsBoot  -> HsBootFile)
                 (reLoc $3)
                 (sL1 $1 (HsModule (XModulePs noAnn (thdOf3 $7) $4 Nothing) (Just $3) $5 (fst $ sndOf3 $7) (snd $ sndOf3 $7))) }
        | 'signature' modid maybe_warning_pragma maybeexports 'where' body
             { sL1 $1 $ DeclD
                 HsigFile
                 (reLoc $2)
                 (sL1 $1 (HsModule (XModulePs noAnn (thdOf3 $6) $3 Nothing) (Just $2) $4 (fst $ sndOf3 $6) (snd $ sndOf3 $6))) }
        | 'dependency' unitid mayberns
             { sL1 $1 $ IncludeD (IncludeDecl { idUnitId = $2
                                              , idModRenaming = $3
                                              , idSignatureInclude = False }) }
        | 'dependency' 'signature' unitid
             { sL1 $1 $ IncludeD (IncludeDecl { idUnitId = $3
                                              , idModRenaming = Nothing
                                              , idSignatureInclude = True }) }

-----------------------------------------------------------------------------
-- Module Header

-- The place for module deprecation is really too restrictive, but if it
-- was allowed at its natural place just before 'module', we get an ugly
-- s/r conflict with the second alternative. Another solution would be the
-- introduction of a new pragma DEPRECATED_MODULE, but this is not very nice,
-- either, and DEPRECATED is only expected to be used by people who really
-- know what they are doing. :-)

signature :: { Located (HsModule GhcPs) }
       : 'signature' modid maybe_warning_pragma maybeexports 'where' body
             {% fileSrcSpan >>= \ loc ->
                acs loc (\loc cs-> (L loc (HsModule (XModulePs
                                               (EpAnn (spanAsAnchor loc) (AnnsModule (epTok $1) NoEpTok (epTok $5) (fstOf3 $6) [] Nothing) cs)
                                               (thdOf3 $6) $3 Nothing)
                                            (Just $2) $4 (fst $ sndOf3 $6)
                                            (snd $ sndOf3 $6)))
                    ) }

module :: { Located (HsModule GhcPs) }
       : 'module' modid maybe_warning_pragma maybeexports 'where' body
             {% fileSrcSpan >>= \ loc ->
                acsFinal (\cs eof -> (L loc (HsModule (XModulePs
                                                     (EpAnn (spanAsAnchor loc) (AnnsModule NoEpTok (epTok $1) (epTok $5) (fstOf3 $6) [] eof) cs)
                                                     (thdOf3 $6) $3 Nothing)
                                                  (Just $2) $4 (fst $ sndOf3 $6)
                                                  (snd $ sndOf3 $6))
                    )) }
        | body2
                {% fileSrcSpan >>= \ loc ->
                   acsFinal (\cs eof -> (L loc (HsModule (XModulePs
                                                        (EpAnn (spanAsAnchor loc) (AnnsModule NoEpTok NoEpTok NoEpTok (fstOf3 $1) [] eof) cs)
                                                        (thdOf3 $1) Nothing Nothing)
                                                     Nothing Nothing
                                                     (fst $ sndOf3 $1) (snd $ sndOf3 $1)))) }

missing_module_keyword :: { () }
        : {- empty -}                           {% pushModuleContext }

implicit_top :: { () }
        : {- empty -}                           {% pushModuleContext }

body    :: { ([TrailingAnn]
             ,([LImportDecl GhcPs], [LHsDecl GhcPs])
             ,EpLayout) }
        :  '{'            top '}'      { (fst $2, snd $2, epExplicitBraces $1 $3) }
        |      vocurly    top close    { (fst $2, snd $2, EpVirtualBraces (getVOCURLY $1)) }

body2   :: { ([TrailingAnn]
             ,([LImportDecl GhcPs], [LHsDecl GhcPs])
             ,EpLayout) }
        :  '{' top '}'                          { (fst $2, snd $2, epExplicitBraces $1 $3) }
        |  missing_module_keyword top close     { ([], snd $2, EpVirtualBraces leftmostColumn) }


top     :: { ([TrailingAnn]
             ,([LImportDecl GhcPs], [LHsDecl GhcPs])) }
        : semis top1                            { (reverse $1, $2) }

top1    :: { ([LImportDecl GhcPs], [LHsDecl GhcPs]) }
        : importdecls_semi topdecls_cs_semi        { (reverse $1, cvTopDecls $2) }
        | importdecls_semi topdecls_cs             { (reverse $1, cvTopDecls $2) }
        | importdecls                              { (reverse $1, []) }

-----------------------------------------------------------------------------
-- Module declaration & imports only

header  :: { Located (HsModule GhcPs) }
        : 'module' modid maybe_warning_pragma maybeexports 'where' header_body
                {% fileSrcSpan >>= \ loc ->
                   acs loc (\loc cs -> (L loc (HsModule (XModulePs
                                                   (EpAnn (spanAsAnchor loc) (AnnsModule NoEpTok (epTok  $1) (epTok $5) [] [] Nothing) cs)
                                                   EpNoLayout $3 Nothing)
                                                (Just $2) $4 $6 []
                          ))) }
        | 'signature' modid maybe_warning_pragma maybeexports 'where' header_body
                {% fileSrcSpan >>= \ loc ->
                   acs loc (\loc cs -> (L loc (HsModule (XModulePs
                                                   (EpAnn (spanAsAnchor loc) (AnnsModule NoEpTok (epTok $1) (epTok $5) [] [] Nothing) cs)
                                                   EpNoLayout $3 Nothing)
                                                (Just $2) $4 $6 []
                          ))) }
        | header_body2
                {% fileSrcSpan >>= \ loc ->
                   return (L loc (HsModule (XModulePs noAnn EpNoLayout Nothing Nothing) Nothing Nothing $1 [])) }

header_body :: { [LImportDecl GhcPs] }
        :  '{'            header_top            { $2 }
        |      vocurly    header_top            { $2 }

header_body2 :: { [LImportDecl GhcPs] }
        :  '{' header_top                       { $2 }
        |  missing_module_keyword header_top    { $2 }

header_top :: { [LImportDecl GhcPs] }
        :  semis header_top_importdecls         { $2 }

header_top_importdecls :: { [LImportDecl GhcPs] }
        :  importdecls_semi                     { $1 }
        |  importdecls                          { $1 }

-----------------------------------------------------------------------------
-- The Export List

maybeexports :: { (Maybe (LocatedLI [LIE GhcPs])) }
        :  '(' exportlist ')'       {% fmap Just $ amsr (sLL $1 $> (fromOL $ snd $2))
                                        (AnnList Nothing (ListParens (epTok $1) (epTok $3)) [] (noAnn,fst $2) []) }
        |  {- empty -}              { Nothing }

exportlist :: { ([EpToken ","], OrdList (LIE GhcPs)) }
        : exportlist1     { ([], $1) }
        | {- empty -}     { ([], nilOL) }

        -- trailing comma:
        | exportlist1 ',' {% case $1 of
                               SnocOL hs t -> do
                                 t' <- addTrailingCommaA t (epTok $2)
                                 return ([], snocOL hs t')}
        | ','             { ([epTok $1], nilOL) }

exportlist1 :: { OrdList (LIE GhcPs) }
        : exportlist1 ',' export_cs
                          {% let ls = $1
                             in if isNilOL ls
                                  then return (ls `appOL` $3)
                                  else case ls of
                                         SnocOL hs t -> do
                                           t' <- addTrailingCommaA t (epTok $2)
                                           return (snocOL hs t' `appOL` $3)}
        | export_cs       { $1 }


export_cs :: { OrdList (LIE GhcPs) }
export_cs : export {% return (unitOL $1) }

   -- No longer allow things like [] and (,,,) to be exported
   -- They are built in syntax, always available
export  :: { LIE GhcPs }
        : maybe_warning_pragma qcname_ext export_subspec {% do { let { span = (maybe comb2 comb3 $1) $2 $> }
                                                          ; impExp <- mkModuleExp $1 (fst $ unLoc $3) $2 (snd $ unLoc $3)
                                                          ; return $ reLoc $ sL span $ impExp } }
        | maybe_warning_pragma 'module' modid            {% do { let { span = (maybe comb2 comb3 $1) $2 $>
                                                                     ; anchor = (maybe glR (\loc -> spanAsAnchor . comb2 loc) $1) $2 }
                                                          ; locImpExp <- return (sL span (IEModuleContents ($1, (epTok $2)) $3))
                                                          ; return $ reLoc $ locImpExp } }
        | maybe_warning_pragma 'pattern' qcon            {% do { warnPatternNamespaceSpecifier (getLoc $2)
                                                               ; let span = (maybe comb2 comb3 $1) $2 $>
                                                               ; return $ reLoc $ sL span $ IEVar $1 (sLLa $2 $> (IEPattern (epTok $2) $3)) Nothing } }
        | maybe_warning_pragma 'default' qtycon          {% do { let { span = (maybe comb2 comb3 $1) $2 $> }
                                                          ; locImpExp <- return (sL span (IEThingAbs $1 (sLLa $2 $> (IEDefault (epTok $2) $3)) Nothing))
                                                          ; return $ reLoc $ locImpExp } }
        | maybe_warning_pragma 'type' '..'               {% do { let { span = (maybe comb2 comb3 $1) $2 $> }
                                                          ; locImpExp <- mkWholeTypeWcImpExp span $1 (epTok $2) (epTok $3)
                                                          ; return $ reLoc locImpExp } }
        | maybe_warning_pragma 'data' '..'               {% do { let { span = (maybe comb2 comb3 $1) $2 $> }
                                                          ; locImpExp <- mkWholeDataWcImpExp span $1 (epTok $2) (epTok $3)
                                                          ; return $ reLoc locImpExp } }
        | maybe_warning_pragma '..'                      {% do { let { span = (maybe comb2 comb3 $1) $2 $> }
                                                          ; addError $ mkPlainErrorMsgEnvelope (comb2 $1 $2) PsErrPlainWildcardExport
                                                          ; locImpExp <- mkPlainWcImpExp $1 (epTok $2)
                                                          ; return $ reLoc locImpExp } }


export_subspec :: { Located ((EpToken "(", EpToken ")"), ImpExpSubSpec) }
        : {- empty -}             { sL0 (noAnn,ImpExpAbs) }
        | '(' qcnames ')'         {% mkImpExpSubSpec (reverse $2)
                                      >>= \ie -> return $ sLL $1 $>
                                            ((epTok $1, epTok $3), ie) }

qcnames :: { [LocatedA ImpExpQcSpec] }
  : {- empty -}                   { [] }
  | qcnames1                      { $1 }

qcnames1 :: { [LocatedA ImpExpQcSpec] }     -- A reversed list
        :  qcnames1 ',' qcname_ext_w_wildcard  {% case $1 of
                                                    ((L la (ImpExpQcWildcard m_kw tok _)):t) ->
                                                       do { return ($3 : L la (ImpExpQcWildcard m_kw tok (epTok $2)) : t) }
                                                    (l:t) ->
                                                       do { l' <- addTrailingCommaA l (epTok $2)
                                                          ; return ($3 : l' : t)} }

        -- Annotations re-added in mkImpExpSubSpec
        |  qcname_ext_w_wildcard                   { [$1] }

-- Variable, data constructor or wildcard
-- or tagged type constructor
qcname_ext_w_wildcard :: { LocatedA ImpExpQcSpec }
        :  qcname_ext               { $1 }
        |  '..'                     { sL1a $1 (ImpExpQcWildcard Nothing (epTok $1) NoEpTok)  }
        |  'type' '..'              {% mkTypeWcImpExp (comb2 $1 $>) (epTok $1) (epTok $2) }
        |  'data' '..'              {% mkDataWcImpExp (comb2 $1 $>) (epTok $1) (epTok $2) }

qcname_ext :: { LocatedA ImpExpQcSpec }
        :  qcname                   { sL1a $1 (mkPlainImpExp $1) }
        |  'type' oqtycon           {% do { imp_exp <- mkTypeImpExp (epTok $1) $2
                                          ; return $ sLLa $1 $> imp_exp }}
        |  'data' qvarcon           {% do { imp_exp <- mkDataImpExp (epTok $1) $2
                                          ; return $ sLLa $1 $> imp_exp }}

qcname  :: { LocatedN RdrName }  -- Variable or type constructor
        :  qvar                 { $1 } -- Things which look like functions
                                       -- Note: This includes record selectors but
                                       -- also (-.->), see #11432
        |  oqtycon_no_varcon    { $1 } -- see Note [Type constructors in export list]

-----------------------------------------------------------------------------
-- Import Declarations

-- importdecls and topdecls must contain at least one declaration;
-- top handles the fact that these may be optional.

-- One or more semicolons
semis1  :: { Located [TrailingAnn] }
semis1  : semis1 ';'  { if isZeroWidthSpan (gl $2) then (sL1 $1 $ unLoc $1) else (sLL $1 $> $ AddSemiAnn (epTok $2) : (unLoc $1)) }
        | ';'         { case msemi $1 of
                          [] -> noLoc []
                          ms -> sL1 $1 $ ms }

-- Zero or more semicolons
semis   :: { [TrailingAnn] }
semis   : semis ';'   { if isZeroWidthSpan (gl $2) then $1 else (AddSemiAnn (epTok $2) : $1) }
        | {- empty -} { [] }

-- No trailing semicolons, non-empty
importdecls :: { [LImportDecl GhcPs] }
importdecls
        : importdecls_semi importdecl
                                { $2 : $1 }

-- May have trailing semicolons, can be empty
importdecls_semi :: { [LImportDecl GhcPs] }
importdecls_semi
        : importdecls_semi importdecl semis1
                                {% do { i <- amsAl $2 (comb2 $2 $3) (reverse $ unLoc $3)
                                      ; return (i : $1)} }
        | {- empty -}           { [] }

importdecl :: { LImportDecl GhcPs }
        : 'import' maybe_src maybe_level maybe_safe optqualified maybe_pkg modid maybe_level optqualified maybeas maybeimpspec
                {% do {
                  ; let { ; mPreQual = $5
                          ; mPostQual = $9
                          ; mPreLevel = $3
                          ; mPostLevel = $8 }
                  ; (qualSpec, levelSpec) <- checkImportDecl mPreQual mPostQual mPreLevel mPostLevel
                  ; let anns
                         = EpAnnImportDecl
                             { importDeclAnnImport    = epTok $1
                             , importDeclAnnPragma    = fst $ fst $2
                             , importDeclAnnLevel     = fst $ levelSpec
                             , importDeclAnnSafe      = fst $4
                             , importDeclAnnQualified = fst $ qualSpec
                             , importDeclAnnPackage   = fst $6
                             , importDeclAnnAs        = fst $10
                             }
                  ; let loc = (comb6 $1 $7 $8 $9 (snd $10) $11);
                  ; fmap reLoc $ acs loc (\loc cs -> L loc $
                      ImportDecl { ideclExt = XImportDeclPass (EpAnn (spanAsAnchor loc) anns cs) (snd $ fst $2) False
                                  , ideclName = $7, ideclPkgQual = snd $6
                                  , ideclSource = snd $2
                                  , ideclLevelSpec = snd $ levelSpec
                                  , ideclSafe = snd $4
                                  , ideclQualified = snd $ qualSpec
                                  , ideclAs = unLoc (snd $10)
                                  , ideclImportList = unLoc $11 })
                  }
                }


maybe_src :: { ((Maybe (EpaLocation,EpToken "#-}"),SourceText),IsBootInterface) }
        : '{-# SOURCE' '#-}'        { ((Just (glR $1,epTok $2),getSOURCE_PRAGs $1)
                                      , IsBoot) }
        | {- empty -}               { ((Nothing,NoSourceText),NotBoot) }

maybe_safe :: { (Maybe (EpToken "safe"),Bool) }
        : 'safe'                                { (Just (epTok $1),True) }
        | {- empty -}                           { (Nothing,      False) }

maybe_level :: { (Maybe EpAnnLevel) }
        : 'splice'                              { (Just (EpAnnLevelSplice (epTok $1))) }
        | 'quote'                               { (Just (EpAnnLevelQuote (epTok $1))) }
        | {- empty -}                           { (Nothing) }

maybe_pkg :: { (Maybe EpaLocation, RawPkgQual) }
        : STRING  {% do { let { pkgFS = getSTRING $1 }
                        ; unless (looksLikePackageName (unpackFS pkgFS)) $
                             addError $ mkPlainErrorMsgEnvelope (getLoc $1) $
                               (PsErrInvalidPackageName pkgFS)
                        ; return (Just (glR $1), RawPkgQual (StringLiteral (getSTRINGs $1) pkgFS Nothing)) } }
        | {- empty -}                           { (Nothing,NoRawPkgQual) }

optqualified :: { Maybe (EpToken "qualified") }
        : 'qualified'                           { Just (epTok $1) }
        | {- empty -}                           { Nothing }

maybeas :: { (Maybe (EpToken "as"),Located (Maybe (LocatedA ModuleName))) }
        : 'as' modid                           { (Just (epTok $1)
                                                 ,sLL $1 $> (Just $2)) }
        | {- empty -}                          { (Nothing,noLoc Nothing) }

maybeimpspec :: { Located (Maybe (ImportListInterpretation, LocatedLI [LIE GhcPs])) }
        : impspec                  { fmap Just $1 }
        | {- empty -}              { noLoc Nothing }

impspec :: { Located (ImportListInterpretation, LocatedLI [LIE GhcPs]) }
        :  '(' importlist ')'               {% do { es <- amsr (sLL $1 $> $ fromOL $ snd $2)
                                                               (AnnList Nothing (ListParens (epTok $1) (epTok $3)) [] (noAnn,fst $2) [])
                                                  ; return $ sLL $1 $> (Exactly, es)} }
        |  'hiding' '(' importlist ')'      {% do { es <- amsr (sLL $1 $> $ fromOL $ snd $3)
                                                               (AnnList Nothing (ListParens (epTok $2) (epTok $4)) [] (epTok $1,fst $3) [])
                                                  ; return $ sLL $1 $> (EverythingBut, es)} }

importlist :: { ([EpToken ","], OrdList (LIE GhcPs)) }
        : importlist1     { ([], $1) }
        | {- empty -}     { ([], nilOL) }

        -- trailing comma:
        | importlist1 ',' {% case $1 of
                               SnocOL hs t -> do
                                 t' <- addTrailingCommaA t (epTok $2)
                                 return ([], snocOL hs t')}
        | ','             { ([epTok $1], nilOL) }

importlist1 :: { OrdList (LIE GhcPs) }
        : importlist1 ',' import
                          {% let ls = $1
                             in if isNilOL ls
                                  then return (ls `appOL` $3)
                                  else case ls of
                                         SnocOL hs t -> do
                                           t' <- addTrailingCommaA t (epTok $2)
                                           return (snocOL hs t' `appOL` $3)}
        | import          { $1 }

import  :: { OrdList (LIE GhcPs) }
        : qcname_ext export_subspec {% fmap (unitOL . reLoc . (sLL $1 $>)) $ mkModuleImp Nothing (fst $ unLoc $2) $1 (snd $ unLoc $2) }
        | 'module' modid            {% fmap (unitOL . reLoc) $ return (sLL $1 $> (IEModuleContents (Nothing, (epTok $1)) $2)) }
        | 'pattern' qcon            {% do { warnPatternNamespaceSpecifier (getLoc $1)
                                          ; return $ unitOL $ reLoc $ sLL $1 $> $ IEVar Nothing (sLLa $1 $> (IEPattern (epTok $1) $2)) Nothing } }
        | 'type' '..'               {% fmap (unitOL . reLoc) $ mkWholeTypeWcImpExp (comb2 $1 $>) Nothing (epTok $1) (epTok $2) }
        | 'data' '..'               {% fmap (unitOL . reLoc) $ mkWholeDataWcImpExp (comb2 $1 $>) Nothing (epTok $1) (epTok $2) }
        | '..'                      {% do { addError $ mkPlainErrorMsgEnvelope (gl $1) PsErrPlainWildcardImport
                                          ; lie <- mkPlainWcImpExp Nothing (epTok $1)
                                          ; return $ unitOL (reLoc lie) } }

-----------------------------------------------------------------------------
-- Fixity Declarations

prec    :: { Maybe (Located (SourceText,Int)) }
        : {- empty -}           { Nothing }
        | INTEGER
                 { Just (sL1 $1 (getINTEGERs $1,fromInteger (il_value (getINTEGER $1)))) }

infix   :: { Located FixityDirection }
        : 'infix'                               { sL1 $1 InfixN  }
        | 'infixl'                              { sL1 $1 InfixL  }
        | 'infixr'                              { sL1 $1 InfixR }

ops     :: { Located (OrdList (LocatedN RdrName)) }
        : ops ',' op       {% case (unLoc $1) of
                                SnocOL hs t -> do
                                  t' <- addTrailingCommaN t (gl $2)
                                  return (sLL $1 $> (snocOL hs t' `appOL` unitOL $3)) }
        | op               { sL1 $1 (unitOL $1) }

-----------------------------------------------------------------------------
-- Top-Level Declarations

-- No trailing semicolons, non-empty
topdecls :: { OrdList (LHsDecl GhcPs) }
        : topdecls_semi topdecl        { $1 `snocOL` $2 }

-- May have trailing semicolons, can be empty
topdecls_semi :: { OrdList (LHsDecl GhcPs) }
        : topdecls_semi topdecl semis1 {% do { t <- amsAl $2 (comb2 $2 $3) (reverse $ unLoc $3)
                                             ; return ($1 `snocOL` t) }}
        | {- empty -}                  { nilOL }


-----------------------------------------------------------------------------
-- Each topdecl accumulates prior comments
-- No trailing semicolons, non-empty
topdecls_cs :: { OrdList (LHsDecl GhcPs) }
        : topdecls_cs_semi topdecl_cs        { $1 `snocOL` $2 }

-- May have trailing semicolons, can be empty
topdecls_cs_semi :: { OrdList (LHsDecl GhcPs) }
        : topdecls_cs_semi topdecl_cs semis1 {% do { t <- amsAl $2 (comb2 $2 $3) (reverse $ unLoc $3)
                                                   ; return ($1 `snocOL` t) }}
        | {- empty -}                  { nilOL }

-- Each topdecl accumulates prior comments
topdecl_cs :: { LHsDecl GhcPs }
topdecl_cs : topdecl {% commentsPA $1 }

-----------------------------------------------------------------------------
topdecl :: { LHsDecl GhcPs }
        : cl_decl                               { L (getLoc $1) (TyClD noExtField (unLoc $1)) }
        | ty_decl                               { L (getLoc $1) (TyClD noExtField (unLoc $1)) }
        | standalone_kind_sig                   { L (getLoc $1) (KindSigD noExtField (unLoc $1)) }
        | inst_decl                             { L (getLoc $1) (InstD noExtField (unLoc $1)) }
        | stand_alone_deriving                  { L (getLoc $1) (DerivD noExtField (unLoc $1)) }
        | role_annot                            { L (getLoc $1) (RoleAnnotD noExtField (unLoc $1)) }
        | default_decl                          { L (getLoc $1) (DefD noExtField (unLoc $1)) }
        | 'foreign' fdecl                       {% amsA' (sLL $1 $> ((unLoc $2) (epTok $1))) }
        | '{-# DEPRECATED' deprecations '#-}'   {% amsA' (sLL $1 $> $ WarningD noExtField (Warnings ((glR $1,epTok $3), (getDEPRECATED_PRAGs $1)) (fromOL $2))) }
        | '{-# WARNING' warnings '#-}'          {% amsA' (sLL $1 $> $ WarningD noExtField (Warnings ((glR $1,epTok $3), (getWARNING_PRAGs $1)) (fromOL $2))) }
        | '{-# RULES' rules '#-}'               {% amsA' (sLL $1 $> $ RuleD noExtField (HsRules ((glR $1,epTok $3), (getRULES_PRAGs $1)) (reverse $2))) }
        | annotation { $1 }
        | decl_no_th                            { $1 }

        -- Template Haskell Extension
        -- The $(..) form is one possible form of infixexp
        -- but we treat an arbitrary expression just as if
        -- it had a $(..) wrapped around it
        | infixexp                              {% runPV (unECP $1) >>= \ $1 ->
                                                       commentsPA $ mkSpliceDecl $1 }

-- Type classes
--
cl_decl :: { LTyClDecl GhcPs }
        : 'class' tycl_hdr fds where_cls
                {% do { let {(wtok, (oc,semis,cc)) = fstOf3 $ unLoc $4}
                      ; mkClassDecl (comb4 $1 $2 $3 $4) $2 $3 (sndOf3 $ unLoc $4) (thdOf3 $ unLoc $4)
                        (AnnClassDecl (epTok $1) [] [] (fst $ unLoc $3) wtok oc cc semis) }}

-- Default declarations (toplevel)
--
default_decl :: { LDefaultDecl GhcPs }
             : 'default' opt_class '(' comma_types0 ')'
               {% amsA' (sLL $1 $> (DefaultDecl (epTok $1,epTok $3,epTok $5) $2 $4)) }


-- Type declarations (toplevel)
--
ty_decl :: { LTyClDecl GhcPs }
           -- ordinary type synonyms
        : 'type' type '=' ktype
                -- Note ktype, not sigtype, on the right of '='
                -- We allow an explicit for-all but we don't insert one
                -- in   type Foo a = (b,b)
                -- Instead we just say b is out of scope
                --
                -- Note the use of type for the head; this allows
                -- infix type constructors to be declared
                {% mkTySynonym (comb2 $1 $4) $2 $4 (epTok $1) (epTok $3) }

           -- type family declarations
        | 'type' 'family' type opt_tyfam_kind_sig opt_injective_info
                          where_type_family
                -- Note the use of type for the head; this allows
                -- infix type constructors to be declared
             {% do { let { (tdcolon, tequal) = fst $ unLoc $4 }
                   ; let { tvbar = fst $ unLoc $5 }
                   ; let { (twhere, (toc, tdd, tcc)) = fst $ unLoc $6  }
                   ; mkFamDecl (comb5 $1 $3 $4 $5 $6) (snd $ unLoc $6) TopLevel $3
                                   (snd $ unLoc $4) (snd $ unLoc $5)
                           (AnnFamilyDecl [] [] (epTok $1) noAnn (epTok $2) tdcolon tequal tvbar twhere toc tdd tcc) }}

          -- ordinary data type or newtype declaration
        | type_data_or_newtype capi_ctype tycl_hdr constrs maybe_derivings
            {% do { let { (tdata, tnewtype, ttype) = fstOf3 $ unLoc $1}
                  ; let { tequal = fst $ unLoc $4 }
                  ; mkTyData (comb4 $1 $3 $4 $5) (sndOf3 $ unLoc $1) (thdOf3 $ unLoc $1) $2 $3
                           Nothing (reverse (snd $ unLoc $4))
                                   (fmap reverse $5)
                           (AnnDataDefn [] [] ttype tnewtype tdata NoEpTok NoEpUniTok NoEpTok NoEpTok NoEpTok tequal)
                             }}
                                   -- We need the location on tycl_hdr in case
                                   -- constrs and deriving are both empty

          -- ordinary GADT declaration
        | type_data_or_newtype capi_ctype tycl_hdr opt_kind_sig
                 gadt_constrlist
                 maybe_derivings
            {% do { let { (tdata, tnewtype, ttype) = fstOf3 $ unLoc $1}
                  ; let { tdcolon = fst $ unLoc $4 }
                  ; let { (twhere, oc, cc) = fst $ unLoc $5 }
                  ; mkTyData (comb5 $1 $3 $4 $5 $6) (sndOf3 $ unLoc $1) (thdOf3 $ unLoc $1) $2 $3
                            (snd $ unLoc $4) (snd $ unLoc $5)
                            (fmap reverse $6)
                            (AnnDataDefn [] [] ttype tnewtype tdata NoEpTok tdcolon twhere oc cc NoEpTok)}}
                                   -- We need the location on tycl_hdr in case
                                   -- constrs and deriving are both empty

          -- data/newtype family
        | 'data' 'family' type opt_datafam_kind_sig
             {% do { let { tdcolon = fst $ unLoc $4 }
                   ; mkFamDecl (comb4 $1 $2 $3 $4) DataFamily TopLevel $3
                                   (snd $ unLoc $4) Nothing
                           (AnnFamilyDecl [] [] noAnn (epTok $1) (epTok $2) tdcolon noAnn noAnn noAnn noAnn noAnn noAnn) }}

-- standalone kind signature
standalone_kind_sig :: { LStandaloneKindSig GhcPs }
  : 'type' sks_vars '::' sigktype
      {% mkStandaloneKindSig (comb2 $1 $4) (L (gl $2) $ unLoc $2) $4
               (epTok $1,epUniTok $3)}

-- See also: sig_vars
sks_vars :: { Located [LocatedN RdrName] }  -- Returned in reverse order
  : sks_vars ',' oqtycon
      {% case unLoc $1 of
           (h:t) -> do
             h' <- addTrailingCommaN h (gl $2)
             return (sLL $1 $> ($3 : h' : t)) }
  | oqtycon { sL1 $1 [$1] }

inst_decl :: { LInstDecl GhcPs }
        : 'instance' maybe_warning_pragma overlap_pragma inst_type where_inst
       {% do { (binds, sigs, _, ats, adts, _) <- cvBindsAndSigs (snd $ unLoc $5)
             ; let (twhere, (openc, closec, semis)) = fst $ unLoc $5
             ; let anns = AnnClsInstDecl (epTok $1) twhere openc semis closec
             ; let cid = ClsInstDecl
                                  { cid_ext = ($2, anns, NoAnnSortKey)
                                  , cid_poly_ty = $4, cid_binds = binds
                                  , cid_sigs = mkClassOpSigs sigs
                                  , cid_tyfam_insts = ats
                                  , cid_overlap_mode = $3
                                  , cid_datafam_insts = adts }
             ; amsA' (L (comb3 $1 $4 $5)
                             (ClsInstD { cid_d_ext = noExtField, cid_inst = cid }))
                   } }

           -- type instance declarations
        | 'type' 'instance' ty_fam_inst_eqn
                {% mkTyFamInst (comb2 $1 $3) (unLoc $3)
                        (epTok $1) (epTok $2) }

          -- data/newtype instance declaration
        | data_or_newtype 'instance' capi_ctype datafam_inst_hdr constrs
                          maybe_derivings
            {% do { let { (tdata, tnewtype) = fst $ unLoc $1 }
                  ; let { tequal = fst $ unLoc $5 }
                  ; mkDataFamInst (comb4 $1 $4 $5 $6) (snd $ unLoc $1) $3 (unLoc $4)
                                      Nothing (reverse (snd  $ unLoc $5))
                                              (fmap reverse $6)
                            (AnnDataDefn [] [] NoEpTok tnewtype tdata (epTok $2) NoEpUniTok NoEpTok NoEpTok NoEpTok tequal)}}

          -- GADT instance declaration
        | data_or_newtype 'instance' capi_ctype datafam_inst_hdr opt_kind_sig
                 gadt_constrlist
                 maybe_derivings
            {% do { let { (tdata, tnewtype) = fst $ unLoc $1 }
                  ; let { dcolon = fst $ unLoc $5 }
                  ; let { (twhere, oc, cc) = fst $ unLoc $6 }
                  ; mkDataFamInst (comb4 $1 $4 $6 $7) (snd $ unLoc $1) $3 (unLoc $4)
                                   (snd $ unLoc $5) (snd $ unLoc $6)
                                   (fmap reverse $7)
                            (AnnDataDefn [] [] NoEpTok tnewtype tdata (epTok $2) dcolon twhere oc cc NoEpTok)}}

overlap_pragma :: { Maybe (LocatedP (OverlapMode GhcPs)) }
  : '{-# OVERLAPPABLE'    '#-}' {% fmap Just $ amsr (sLL $1 $> (Overlappable (getOVERLAPPABLE_PRAGs $1)))
                                       (AnnPragma (glR $1) (epTok $2) noAnn noAnn noAnn noAnn noAnn) }
  | '{-# OVERLAPPING'     '#-}' {% fmap Just $ amsr (sLL $1 $> (Overlapping (getOVERLAPPING_PRAGs $1)))
                                       (AnnPragma (glR $1) (epTok $2) noAnn noAnn noAnn noAnn noAnn) }
  | '{-# OVERLAPS'        '#-}' {% fmap Just $ amsr (sLL $1 $> (Overlaps (getOVERLAPS_PRAGs $1)))
                                       (AnnPragma (glR $1) (epTok $2) noAnn noAnn noAnn noAnn noAnn) }
  | '{-# INCOHERENT'      '#-}' {% fmap Just $ amsr (sLL $1 $> (Incoherent (getINCOHERENT_PRAGs $1)))
                                       (AnnPragma (glR $1) (epTok $2) noAnn noAnn noAnn noAnn noAnn) }
  | {- empty -}                 { Nothing }

deriv_strategy_no_via :: { LDerivStrategy GhcPs }
  : 'stock'                     {% amsA' (sL1 $1 (StockStrategy (epTok $1))) }
  | 'anyclass'                  {% amsA' (sL1 $1 (AnyclassStrategy (epTok $1))) }
  | 'newtype'                   {% amsA' (sL1 $1 (NewtypeStrategy (epTok $1))) }

deriv_strategy_via :: { LDerivStrategy GhcPs }
  : 'via' sigktype          {% amsA' (sLL $1 $> (ViaStrategy (XViaStrategyPs (epTok $1) $2))) }

deriv_standalone_strategy :: { Maybe (LDerivStrategy GhcPs) }
  : 'stock'                     {% fmap Just $ amsA' (sL1 $1 (StockStrategy (epTok $1))) }
  | 'anyclass'                  {% fmap Just $ amsA' (sL1 $1 (AnyclassStrategy (epTok $1))) }
  | 'newtype'                   {% fmap Just $ amsA' (sL1 $1 (NewtypeStrategy (epTok $1))) }
  | deriv_strategy_via          { Just $1 }
  | {- empty -}                 { Nothing }

-- Optional class reference for default declarations
opt_class :: { Maybe (LIdP GhcPs) }
          : {- empty -}         { Nothing }
          | qtycon              {% fmap Just $ amsA' (reLoc $1) }

-- Injective type families

opt_injective_info :: { Located (EpToken "|", Maybe (LInjectivityAnn GhcPs)) }
        : {- empty -}               { noLoc (noAnn, Nothing) }
        | '|' injectivity_cond      { sLL $1 $> ((epTok $1)
                                                , Just ($2)) }

injectivity_cond :: { LInjectivityAnn GhcPs }
        : tyvarid '->' inj_varids
           {% amsA' (sLL $1 $> (InjectivityAnn (epUniTok $2) $1 (reverse (unLoc $3)))) }

inj_varids :: { Located [LocatedN RdrName] }
        : inj_varids tyvarid  { sLL $1 $> ($2 : unLoc $1) }
        | tyvarid             { sL1  $1 [$1]               }

-- Closed type families

where_type_family :: { Located ((EpToken "where", (EpToken "{", EpToken "..", EpToken "}")),FamilyInfo GhcPs) }
        : {- empty -}                      { noLoc (noAnn,OpenTypeFamily) }
        | 'where' ty_fam_inst_eqn_list
               { sLL $1 $> ((epTok $1,(fst $ unLoc $2))
                    ,ClosedTypeFamily (fmap reverse $ snd $ unLoc $2)) }

ty_fam_inst_eqn_list :: { Located ((EpToken "{", EpToken "..", EpToken "}"),Maybe [LTyFamInstEqn GhcPs]) }
        :     '{' ty_fam_inst_eqns '}'     { sLL $1 $> ((epTok $1,noAnn, epTok $3)
                                                ,Just (unLoc $2)) }
        | vocurly ty_fam_inst_eqns close   { let (L loc _) = $2 in
                                             L loc (noAnn,Just (unLoc $2)) }
        |     '{' '..' '}'                 { sLL $1 $> ((epTok $1,epTok $2 ,epTok $3),Nothing) }
        | vocurly '..' close               { let (L loc _) = $2 in
                                             L loc ((noAnn,epTok $2, noAnn),Nothing) }

ty_fam_inst_eqns :: { Located [LTyFamInstEqn GhcPs] }
        : ty_fam_inst_eqns ';' ty_fam_inst_eqn
                                      {% let (L loc eqn) = $3 in
                                         case unLoc $1 of
                                           [] -> return (sLL $1 $> (L loc eqn : unLoc $1))
                                           (h:t) -> do
                                             h' <- addTrailingSemiA h (epTok $2)
                                             return (sLL $1 $> ($3 : h' : t)) }
        | ty_fam_inst_eqns ';'        {% case unLoc $1 of
                                           [] -> return (sLZ $1 $> (unLoc $1))
                                           (h:t) -> do
                                             h' <- addTrailingSemiA h (epTok $2)
                                             return (sLZ $1 $>  (h':t)) }
        | ty_fam_inst_eqn             { sLL $1 $> [$1] }
        | {- empty -}                 { noLoc [] }

ty_fam_inst_eqn :: { LTyFamInstEqn GhcPs }
        : 'forall' tv_bndrs '.' type '=' ktype
              {% do { hintExplicitForall $1
                    ; tvbs <- fromSpecTyVarBndrs $2
                    ; let loc = comb2 $1 $>
                    ; !cs <- getCommentsFor loc
                    ; mkTyFamInstEqn loc (mkHsOuterExplicit (EpAnn (glEE $1 $3) (epUniTok $1, epTok $3) cs) tvbs) $4 $6 (epTok $5) }}
        | type '=' ktype
              {% mkTyFamInstEqn (comb2 $1 $>) mkHsOuterImplicit $1 $3 (epTok $2) }
              -- Note the use of type for the head; this allows
              -- infix type constructors and type patterns

-- Associated type family declarations
--
-- * They have a different syntax than on the toplevel (no family special
--   identifier).
--
-- * They also need to be separate from instances; otherwise, data family
--   declarations without a kind signature cause parsing conflicts with empty
--   data declarations.
--
at_decl_cls :: { LHsDecl GhcPs }
        :  -- data family declarations, with optional 'family' keyword
          'data' opt_family type opt_datafam_kind_sig
             {% do { let { tdcolon = fst $ unLoc $4 }
                   ; liftM mkTyClD (mkFamDecl (comb3 $1 $3 $4) DataFamily NotTopLevel $3
                                                  (snd $ unLoc $4) Nothing
                           (AnnFamilyDecl [] [] noAnn (epTok $1) $2 tdcolon noAnn noAnn noAnn noAnn noAnn noAnn)) }}

           -- type family declarations, with optional 'family' keyword
           -- (can't use opt_instance because you get shift/reduce errors
        | 'type' type opt_at_kind_inj_sig
            {% do { let { (tdcolon, tequal, tvbar) = fst $ unLoc $3 }
                  ; liftM mkTyClD
                        (mkFamDecl (comb3 $1 $2 $3) OpenTypeFamily NotTopLevel $2
                                   (fst . snd $ unLoc $3)
                                   (snd . snd $ unLoc $3)
                         (AnnFamilyDecl [] [] (epTok $1) noAnn noAnn tdcolon tequal tvbar noAnn noAnn noAnn noAnn)) }}
        | 'type' 'family' type opt_at_kind_inj_sig
            {% do { let { (tdcolon, tequal, tvbar) = fst $ unLoc $4 }
                  ; liftM mkTyClD
                        (mkFamDecl (comb3 $1 $3 $4) OpenTypeFamily NotTopLevel $3
                                   (fst . snd $ unLoc $4)
                                   (snd . snd $ unLoc $4)
                           (AnnFamilyDecl [] [] (epTok $1) noAnn (epTok $2) tdcolon tequal tvbar noAnn noAnn noAnn noAnn)) }}
           -- default type instances, with optional 'instance' keyword
        | 'type' ty_fam_inst_eqn
                {% liftM mkInstD (mkTyFamInst (comb2 $1 $2) (unLoc $2)
                          (epTok $1) NoEpTok) }
        | 'type' 'instance' ty_fam_inst_eqn
                {% liftM mkInstD (mkTyFamInst (comb2 $1 $3) (unLoc $3)
                              (epTok $1) (epTok $2) )}

opt_family   :: { EpToken "family" }
              : {- empty -}   { noAnn }
              | 'family'      { (epTok $1) }

opt_instance :: { EpToken "instance" }
              : {- empty -} { NoEpTok }
              | 'instance'  { epTok $1 }

-- Associated type instances
--
at_decl_inst :: { LInstDecl GhcPs }
           -- type instance declarations, with optional 'instance' keyword
        : 'type' opt_instance ty_fam_inst_eqn
                -- Note the use of type for the head; this allows
                -- infix type constructors and type patterns
                {% mkTyFamInst (comb2 $1 $3) (unLoc $3)
                          (epTok $1) $2 }

        -- data/newtype instance declaration, with optional 'instance' keyword
        | data_or_newtype opt_instance capi_ctype datafam_inst_hdr constrs maybe_derivings
            {% do { let { (tdata, tnewtype) = fst $ unLoc $1 }
                  ; let { tequal = fst $ unLoc $5 }
                  ; mkDataFamInst (comb4 $1 $4 $5 $6) (snd $ unLoc $1) $3 (unLoc $4)
                                    Nothing (reverse (snd $ unLoc $5))
                                             (fmap reverse $6)
                            (AnnDataDefn [] [] NoEpTok tnewtype tdata $2 NoEpUniTok NoEpTok NoEpTok NoEpTok tequal)}}

        -- GADT instance declaration, with optional 'instance' keyword
        | data_or_newtype opt_instance capi_ctype datafam_inst_hdr opt_kind_sig
                 gadt_constrlist
                 maybe_derivings
             {% do { let { (tdata, tnewtype) = fst $ unLoc $1 }
                   ; let { dcolon = fst $ unLoc $5 }
                   ; let { (twhere, oc, cc) = fst $ unLoc $6 }
                   ; mkDataFamInst (comb4 $1 $4 $6 $7) (snd $ unLoc $1) $3
                                (unLoc $4) (snd $ unLoc $5) (snd $ unLoc $6)
                                (fmap reverse $7)
                            (AnnDataDefn [] [] NoEpTok tnewtype tdata $2 dcolon twhere oc cc NoEpTok)}}

type_data_or_newtype :: { Located ((EpToken "data", EpToken "newtype", EpToken "type")
                                   , Bool, NewOrData) }
        : 'data'        { sL1 $1 ((epTok $1, NoEpTok,  NoEpTok),  False,DataType) }
        | 'newtype'     { sL1 $1 ((NoEpTok,  epTok $1, NoEpTok),  False,NewType) }
        | 'type' 'data' { sL1 $1 ((epTok $2, NoEpTok,  epTok $1), True ,DataType) }

data_or_newtype :: { Located ((EpToken "data", EpToken "newtype"), NewOrData) }
        : 'data'        { sL1 $1 ((epTok $1, NoEpTok), DataType) }
        | 'newtype'     { sL1 $1 ((NoEpTok,  epTok $1),NewType) }

-- Family result/return kind signatures

opt_kind_sig :: { Located (TokDcolon, Maybe (LHsKind GhcPs)) }
        :               { noLoc     (NoEpUniTok , Nothing) }
        | '::' kind     { sLL $1 $> (epUniTok $1, Just $2) }

opt_datafam_kind_sig :: { Located (TokDcolon, LFamilyResultSig GhcPs) }
        :               { noLoc     (noAnn,       noLocA (NoSig noExtField)         )}
        | '::' kind     { sLL $1 $> (epUniTok $1, sLLa $1 $> (KindSig noExtField $2))}

opt_tyfam_kind_sig :: { Located ((TokDcolon, EpToken "="), LFamilyResultSig GhcPs) }
        :              { noLoc     (noAnn               , noLocA     (NoSig    noExtField)   )}
        | '::' kind    { sLL $1 $> ((epUniTok $1, noAnn), sLLa $1 $> (KindSig  noExtField $2))}
        | '='  tv_bndr {% do { tvb <- fromSpecTyVarBndr $2
                             ; return $ sLL $1 $> ((noAnn, epTok $1), sLLa $1 $> (TyVarSig noExtField tvb))} }

opt_at_kind_inj_sig :: { Located ((TokDcolon, EpToken "=", EpToken "|"), ( LFamilyResultSig GhcPs
                                            , Maybe (LInjectivityAnn GhcPs)))}
        :            { noLoc (noAnn, (noLocA (NoSig noExtField), Nothing)) }
        | '::' kind  { sLL $1 $> ( (epUniTok $1, noAnn, noAnn)
                                 , (sL1a $> (KindSig noExtField $2), Nothing)) }
        | '='  tv_bndr_no_braces '|' injectivity_cond
                {% do { tvb <- fromSpecTyVarBndr $2
                      ; return $ sLL $1 $> ((noAnn, epTok $1, epTok $3)
                                           , (sLLa $1 $2 (TyVarSig noExtField tvb), Just $4))} }

-- tycl_hdr parses the header of a class or data type decl,
-- which takes the form
--      T a b
--      Eq a => T a
--      (Eq a, Ord b) => T a b
--      T Int [a]                       -- for associated types
-- Rather a lot of inlining here, else we get reduce/reduce errors
tycl_hdr :: { Located (Maybe (LHsContext GhcPs), LHsType GhcPs) }
        : context '=>' type         {% acs (comb2 $1 $>) (\loc cs -> (L loc (Just (addTrailingDarrowC $1 $2 cs), $3))) }
        | type                      { sL1 $1 (Nothing, $1) }

datafam_inst_hdr :: { Located (Maybe (LHsContext GhcPs), HsOuterFamEqnTyVarBndrs GhcPs, LHsType GhcPs) }
        : 'forall' tv_bndrs '.' context '=>' type   {% hintExplicitForall $1
                                                       >> fromSpecTyVarBndrs $2
                                                         >>= \tvbs ->
                                                             (acs (comb2 $1 $>) (\loc cs -> (L loc
                                                                                  (Just ( addTrailingDarrowC $4 $5 cs)
                                                                                        , mkHsOuterExplicit (EpAnn (glEE $1 $3) (epUniTok $1, epTok $3) emptyComments) tvbs, $6))))
                                                    }
        | 'forall' tv_bndrs '.' type   {% do { hintExplicitForall $1
                                             ; tvbs <- fromSpecTyVarBndrs $2
                                             ; let loc = comb2 $1 $>
                                             ; !cs <- getCommentsFor loc
                                             ; return (sL loc (Nothing, mkHsOuterExplicit (EpAnn (glEE $1 $3) (epUniTok $1, epTok $3) cs) tvbs, $4))
                                       } }
        | context '=>' type         {% acs (comb2 $1 $>) (\loc cs -> (L loc (Just (addTrailingDarrowC $1 $2 cs), mkHsOuterImplicit, $3))) }
        | type                      { sL1 $1 (Nothing, mkHsOuterImplicit, $1) }


capi_ctype :: { Maybe (LocatedP (CType GhcPs)) }
capi_ctype : '{-# CTYPE' STRING STRING '#-}'
                       {% fmap Just $ amsr (sLL $1 $> (mkCType (getCTYPEs $1) (getSTRINGs $3) (Just (Header (getSTRINGs $2) (getSTRING $2)))
                                        (getSTRING $3)))
                              (AnnPragma (glR $1) (epTok $4) noAnn (glR $2) (glR $3) noAnn noAnn) }

           | '{-# CTYPE'        STRING '#-}'
                       {% fmap Just $ amsr (sLL $1 $> (mkCType (getCTYPEs $1) (getSTRINGs $2) Nothing (getSTRING $2)))
                              (AnnPragma (glR $1) (epTok $3) noAnn noAnn (glR $2) noAnn noAnn) }

           |           { Nothing }

-----------------------------------------------------------------------------
-- Stand-alone deriving

-- Glasgow extension: stand-alone deriving declarations
stand_alone_deriving :: { LDerivDecl GhcPs }
  : 'deriving' deriv_standalone_strategy 'instance' maybe_warning_pragma overlap_pragma inst_type
                {% do { let { err = text "in the stand-alone deriving instance"
                                    <> colon <+> quotes (ppr $6) }
                      ; amsA' (sLL $1 $>
                                 (DerivDecl ($4, (epTok $1, epTok $3)) (mkHsWildCardBndrs $6) $2 $5)) }}

-----------------------------------------------------------------------------
-- Role annotations

role_annot :: { LRoleAnnotDecl GhcPs }
role_annot : 'type' 'role' oqtycon maybe_roles
          {% mkRoleAnnotDecl (comb3 $1 $4 $3) $3 (reverse (unLoc $4))
                   (epTok $1,epTok $2) }

-- Reversed!
maybe_roles :: { Located [Located (Maybe FastString)] }
maybe_roles : {- empty -}    { noLoc [] }
            | roles          { $1 }

roles :: { Located [Located (Maybe FastString)] }
roles : role             { sLL $1 $> [$1] }
      | roles role       { sLL $1 $> $ $2 : unLoc $1 }

-- read it in as a varid for better error messages
role :: { Located (Maybe FastString) }
role : VARID             { sL1 $1 $ Just $ getVARID $1 }
     | '_'               { sL1 $1 Nothing }

-- Pattern synonyms

-- Glasgow extension: pattern synonyms
pattern_synonym_decl :: { LHsDecl GhcPs }
        : 'pattern' pattern_synonym_lhs '=' pat_syn_pat
         {%      let (name, args, (mo, mc) ) = $2 in
                 amsA' (sLL $1 $> . ValD noExtField $ mkPatSynBind name args $4
                                                    ImplicitBidirectional
                      (AnnPSB (epTok $1) mo mc Nothing (Just (epTok $3)))) }

        | 'pattern' pattern_synonym_lhs '<-' pat_syn_pat
         {%    let (name, args, (mo,mc)) = $2 in
               amsA' (sLL $1 $> . ValD noExtField $ mkPatSynBind name args $4 Unidirectional
                       (AnnPSB (epTok $1) mo mc (Just (epUniTok $3)) Nothing)) }

        | 'pattern' pattern_synonym_lhs '<-' pat_syn_pat where_decls
            {% do { let (name, args, (mo,mc)) = $2
                  ; mg <- mkPatSynMatchGroup name $5
                  ; amsA' (sLL $1 $> . ValD noExtField $
                           mkPatSynBind name args $4 (ExplicitBidirectional mg)
                            (AnnPSB (epTok $1) mo mc (Just (epUniTok $3)) Nothing))
                   }}

pattern_synonym_lhs :: { (LocatedN RdrName, HsPatSynDetails GhcPs, (Maybe (EpToken "{"), Maybe (EpToken "}"))) }
        : con vars0 { ($1, PrefixCon $2, noAnn) }
        | varid conop varid { ($2, InfixCon $1 $3, noAnn) }
        | con '{' cvars1 '}' { ($1, RecCon $3, (Just (epTok $2), Just (epTok $4))) }

vars0 :: { [LocatedN RdrName] }
        : {- empty -}                 { [] }
        | varid vars0                 { $1 : $2 }

cvars1 :: { [RecordPatSynField GhcPs] }
       : var                          { [RecordPatSynField (mkFieldOcc $1) $1] }
       | var ',' cvars1               {% do { h <- addTrailingCommaN $1 (gl $2)
                                            ; return ((RecordPatSynField (mkFieldOcc h) h) : $3 )}}

where_decls :: { LocatedLW (OrdList (LHsDecl GhcPs)) }
        : 'where' '{' decls '}'       {% amsr (sLL $1 $> (thdOf3 $ unLoc $3))
                                              (AnnList (Just (fstOf3 $ unLoc $3)) (ListBraces (epTok $2) (epTok $4)) (sndOf3 $ unLoc $3) (epTok $1) []) }
        | 'where' vocurly decls close {% amsr (sLL $1 $3 (thdOf3 $ unLoc $3))
                                              (AnnList (Just (fstOf3 $ unLoc $3)) ListNone (sndOf3 $ unLoc $3) (epTok $1) []) }

pattern_synonym_sig :: { LSig GhcPs }
        : 'pattern' con_list '::' sigtype
                   {% amsA' (sLL $1 $>
                                $ PatSynSig (AnnSig (epUniTok $3) (Just (epTok $1)) Nothing)
                                  (toList $ unLoc $2) $4) }

qvarcon :: { LocatedN RdrName }
        : qvar                          { $1 }
        | qcon                          { $1 }

-----------------------------------------------------------------------------
-- Nested declarations

-- Declaration in class bodies
--
decl_cls  :: { LHsDecl GhcPs }
decl_cls  : at_decl_cls                 { $1 }
          | decl                        { $1 }

          -- A 'default' signature used with the generic-programming extension
          | 'default' infixexp '::' sigtype
                    {% runPV (unECP $2) >>= \ $2 ->
                       do { v <- checkValSigLhs $2
                          ; let err = text "in default signature" <> colon <+>
                                      quotes (ppr $2)
                          ; amsA' (sLL $1 $> $ SigD noExtField $ ClassOpSig (AnnSig (epUniTok $3) Nothing (Just (epTok $1))) True [v] $4) }}

decls_cls :: { Located ([EpToken ";"],OrdList (LHsDecl GhcPs)) }  -- Reversed
          : decls_cls ';' decl_cls      {% if isNilOL (snd $ unLoc $1)
                                             then return (sLL $1 $> ((fst $ unLoc $1) ++ [mzEpTok $2]
                                                                    , unitOL $3))
                                            else case (snd $ unLoc $1) of
                                              SnocOL hs t -> do
                                                 t' <- addTrailingSemiA t (epTok $2)
                                                 return (sLL $1 $> (fst $ unLoc $1
                                                                , snocOL hs t' `appOL` unitOL $3)) }
          | decls_cls ';'               {% if isNilOL (snd $ unLoc $1)
                                             then return (sLZ $1 $> ( (fst $ unLoc $1) ++ [mzEpTok $2]
                                                                                   ,snd $ unLoc $1))
                                             else case (snd $ unLoc $1) of
                                               SnocOL hs t -> do
                                                  t' <- addTrailingSemiA t (epTok $2)
                                                  return (sLZ $1 $> (fst $ unLoc $1
                                                                 , snocOL hs t')) }
          | decl_cls                    { sL1 $1 ([], unitOL $1) }
          | {- empty -}                 { noLoc ([],nilOL) }

decllist_cls
        :: { Located ((EpToken "{", [EpToken ";"], EpToken "}")
                     , OrdList (LHsDecl GhcPs)
                     , EpLayout) }      -- Reversed
        : '{'         decls_cls '}'     { sLL $1 $> ((epTok $1, fst $ unLoc $2, epTok $3)
                                             ,snd $ unLoc $2, epExplicitBraces $1 $3) }
        |     vocurly decls_cls close   { let { L l (anns, decls) = $2 }
                                           in L l ((NoEpTok, anns, NoEpTok), decls, EpVirtualBraces (getVOCURLY $1)) }

-- Class body
--
where_cls :: { Located ((EpToken "where", (EpToken "{", [EpToken ";"], EpToken "}"))
                       ,(OrdList (LHsDecl GhcPs))    -- Reversed
                       ,EpLayout) }
                                -- No implicit parameters
                                -- May have type declarations
        : 'where' decllist_cls          { sLL $1 $> ((epTok $1,fstOf3 $ unLoc $2)
                                             ,sndOf3 $ unLoc $2,thdOf3 $ unLoc $2) }
        | {- empty -}                   { noLoc ((noAnn, noAnn),nilOL,EpNoLayout) }

-- Declarations in instance bodies
--
decl_inst  :: { Located (OrdList (LHsDecl GhcPs)) }
decl_inst  : at_decl_inst               { sL1 $1 (unitOL (sL1a $1 (InstD noExtField (unLoc $1)))) }
           | decl                       { sL1 $1 (unitOL $1) }

decls_inst :: { Located ([EpToken ";"],OrdList (LHsDecl GhcPs)) }   -- Reversed
           : decls_inst ';' decl_inst   {% if isNilOL (snd $ unLoc $1)
                                             then return (sLL $1 $> ((fst $ unLoc $1) ++ [mzEpTok $2]
                                                                    , unLoc $3))
                                             else case (snd $ unLoc $1) of
                                               SnocOL hs t -> do
                                                  t' <- addTrailingSemiA t (epTok $2)
                                                  return (sLL $1 $> (fst $ unLoc $1
                                                                 , snocOL hs t' `appOL` unLoc $3)) }
           | decls_inst ';'             {% if isNilOL (snd $ unLoc $1)
                                             then return (sLZ $1 $> ((fst $ unLoc $1) ++ [mzEpTok $2]
                                                                                   ,snd $ unLoc $1))
                                             else case (snd $ unLoc $1) of
                                               SnocOL hs t -> do
                                                  t' <- addTrailingSemiA t (epTok $2)
                                                  return (sLZ $1 $> (fst $ unLoc $1
                                                                 , snocOL hs t')) }
           | decl_inst                  { sL1 $1 ([],unLoc $1) }
           | {- empty -}                { noLoc ([],nilOL) }

decllist_inst
        :: { Located ((EpToken "{", EpToken "}", [EpToken ";"])
                     , OrdList (LHsDecl GhcPs)) }      -- Reversed
        : '{'         decls_inst '}'    { sLL $1 $> ((epTok $1,epTok $3,fst $ unLoc $2),snd $ unLoc $2) }
        |     vocurly decls_inst close  { L (gl $2) ((noAnn,noAnn,fst $ unLoc $2),snd $ unLoc $2) }

-- Instance body
--
where_inst :: { Located ((EpToken "where", (EpToken "{", EpToken "}", [EpToken ";"]))
                        , OrdList (LHsDecl GhcPs)) }   -- Reversed
                                -- No implicit parameters
                                -- May have type declarations
        : 'where' decllist_inst         { sLL $1 $> ((epTok $1,(fst $ unLoc $2))
                                             ,snd $ unLoc $2) }
        | {- empty -}                   { noLoc (noAnn,nilOL) }

-- Declarations in binding groups other than classes and instances
--
decls   :: { Located (EpaLocation, [EpToken ";"], OrdList (LHsDecl GhcPs)) }
        : decls ';' decl    {% if isNilOL (thdOf3 $ unLoc $1)
                                 then return (sLL $2 $> (glR $3, (sndOf3 $ unLoc $1) ++ (msemiA $2)
                                                        , unitOL $3))
                                 else case (thdOf3 $ unLoc $1) of
                                   SnocOL hs t -> do
                                      t' <- addTrailingSemiA t (epTok $2)
                                      let { this = unitOL $3;
                                            rest = snocOL hs t';
                                            these = rest `appOL` this }
                                      return (rest `seq` this `seq` these `seq`
                                                 (sLL $1 $> (glEE (fstOf3 $ unLoc $1) $3, sndOf3 $ unLoc $1, these))) }
        | decls ';'          {% if isNilOL (thdOf3 $ unLoc $1)
                                  then return (sLZ $1 $> (glR $2, (sndOf3 $ unLoc $1) ++ (msemiA $2)
                                                          ,thdOf3 $ unLoc $1))
                                  else case (thdOf3 $ unLoc $1) of
                                    SnocOL hs t -> do
                                       t' <- addTrailingSemiA t (epTok $2)
                                       return (sLZ $1 $> (glEEz $1 $2, sndOf3 $ unLoc $1, snocOL hs t')) }
        | decl                          { sL1 $1 (glR $1,  [], unitOL $1) }
        | {- empty -}                   { noLoc (noAnn, [],nilOL) }

decllist :: { Located (AnnList (),Located (OrdList (LHsDecl GhcPs))) }
        : '{'            decls '}'     { sLL $1 $> (AnnList (Just (fstOf3 $ unLoc $2)) (ListBraces (epTok $1) (epTok $3)) (sndOf3 $ unLoc $2) noAnn []
                                                   ,sL1 $2 $ thdOf3 $ unLoc $2) }
        |     vocurly    decls close   { sL1 $2    (AnnList (Just (fstOf3 $ unLoc $2)) ListNone (sndOf3 $ unLoc $2) noAnn []
                                                   ,sL1 $2 $ thdOf3 $ unLoc $2) }

-- Binding groups other than those of class and instance declarations
--
binds   ::  { Located (HsLocalBinds GhcPs) }
                                         -- May have implicit parameters
                                                -- No type declarations
        : decllist          {% do { let { (AnnList anc p s _ t, decls) = unLoc $1 }
                                  ; val_binds <- cvBindGroup (unLoc $ decls)
                                  ; !cs <- getCommentsFor (gl $1)
                                  ; return (sL1 $1 $ HsValBinds (EpAnn (glR $1) (AnnList anc p s noAnn t) cs) val_binds)} }

        | '{'            dbinds '}'     {% acs (comb3 $1 $2 $3) (\loc cs -> (L loc
                                             $ HsIPBinds (EpAnn (spanAsAnchor (comb3 $1 $2 $3)) (AnnList (Just$ glR $2) (ListBraces (epTok $1) (epTok $3)) [] noAnn []) cs) (IPBinds noExtField (reverse $ unLoc $2)))) }

        |     vocurly    dbinds close   {% acs (gl $2) (\loc cs -> (L loc
                                             $ HsIPBinds (EpAnn (glR $1) (AnnList (Just $ glR $2) ListNone [] noAnn []) cs) (IPBinds noExtField (reverse $ unLoc $2)))) }


wherebinds :: { Maybe (Located (HsLocalBinds GhcPs, Maybe EpAnnComments )) }
                                                -- May have implicit parameters
                                                -- No type declarations
        : 'where' binds                 {% do { r <- acs (comb2 $1 $>) (\loc cs ->
                                                (L loc (annBinds (epTok $1) cs (unLoc $2))))
                                              ; return $ Just r} }
        | {- empty -}                   { Nothing }

-----------------------------------------------------------------------------
-- Transformation Rules

rules   :: { [LRuleDecl GhcPs] } -- Reversed
        :  rules ';' rule              {% case $1 of
                                            [] -> return ($3:$1)
                                            (h:t) -> do
                                              h' <- addTrailingSemiA h (epTok $2)
                                              return ($3:h':t) }
        |  rules ';'                   {% case $1 of
                                            [] -> return $1
                                            (h:t) -> do
                                              h' <- addTrailingSemiA h (epTok $2)
                                              return (h':t) }
        |  rule                        { [$1] }
        |  {- empty -}                 { [] }

rule    :: { LRuleDecl GhcPs }
        : STRING rule_activation rule_foralls infixexp '=' exp
         {%runPV (unECP $4) >>= \ $4 ->
           runPV (unECP $6) >>= \ $6 ->
           amsA' (sLL $1 $> $ HsRule
                                   { rd_ext =((fst $2, epTok $5), getSTRINGs $1)
                                   , rd_name = L (noAnnSrcSpan $ gl $1) (getSTRING $1)
                                   , rd_act = snd $2 `orElse` AlwaysActive
                                   , rd_bndrs = ruleBndrsOrDef $3
                                   , rd_lhs = $4, rd_rhs = $6 }) }

-- Rules can be specified to be never active, unlike inline/specialize pragmas
rule_activation :: { (ActivationAnn, Maybe ActivationGhc) }
        -- See Note [%shift: rule_activation -> {- empty -}]
        : {- empty -} %shift                    { (noAnn, Nothing) }
        | rule_explicit_activation              { (fst $1,Just (snd $1)) }

-- This production is used to parse the tilde syntax in pragmas such as
--   * {-# INLINE[~2] ... #-}
--   * {-# SPECIALISE [~ 001] ... #-}
--   * {-# RULES ... [~0] ... g #-}
-- Note that it can be written either
--   without a space [~1]  (the PREFIX_TILDE case), or
--   with    a space [~ 1] (the VARSYM case).
-- See Note [Whitespace-sensitive operator parsing] in GHC.Parser.Lexer
rule_activation_marker :: { (Maybe (EpToken "~")) }
      : PREFIX_TILDE { (Just (epTok $1)) }
      | VARSYM  {% if (getVARSYM $1 == fsLit "~")
                   then return (Just (epTok $1))
                   else do { addError $ mkPlainErrorMsgEnvelope (getLoc $1) $
                               PsErrInvalidRuleActivationMarker
                           ; return Nothing } }

rule_explicit_activation :: { ( ActivationAnn
                              , ActivationGhc) }  -- In brackets
        : '[' INTEGER ']'       { ( ActivationAnn (epTok $1) (getINTEGERs $2) (epTok $3) Nothing (Just (glR $2))
                                  , ActiveAfter (fromInteger (il_value (getINTEGER $2)))) }
        | '[' rule_activation_marker INTEGER ']'
                                { ( ActivationAnn (epTok $1) (getINTEGERs $3) (epTok $4) $2 (Just (glR $3))
                                  , ActiveBefore (fromInteger (il_value (getINTEGER $3)))) }
        | '[' rule_activation_marker ']'
                                { ( ActivationAnn (epTok $1) NoSourceText (epTok $3) $2 Nothing
                                  , NeverActive ) }

rule_foralls :: { Maybe (RuleBndrs GhcPs) }
        : 'forall' rule_vars '.' 'forall' rule_vars '.'
              {% hintExplicitForall $1
                 >> checkRuleTyVarBndrNames $2
                 >> let ann = HsRuleBndrsAnn
                                (Just (epUniTok $1,epTok $3))
                                (Just (epUniTok $4,epTok $6))
                     in return (Just (mkRuleBndrs ann  (Just $2) $5)) }

        | 'forall' rule_vars '.'
           { Just (mkRuleBndrs (HsRuleBndrsAnn Nothing (Just (epUniTok $1,epTok $3)))
                               Nothing $2) }

        -- See Note [%shift: rule_foralls -> {- empty -}]
        | {- empty -}            %shift
           { Nothing }

rule_vars :: { [LRuleTyTmVar] }
        : rule_var rule_vars                    { $1 : $2 }
        | {- empty -}                           { [] }

rule_var :: { LRuleTyTmVar }
        : varid                         { sL1a $1 (RuleTyTmVar noAnn $1 Nothing) }
        | '(' varid '::' ctype ')'      {% amsA' (sLL $1 $> (RuleTyTmVar (AnnTyVarBndr [glR $1] [glR $5] noAnn (epUniTok $3)) $2 (Just $4))) }

{- Note [Parsing explicit foralls in Rules]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We really want the above definition of rule_foralls to be:

  rule_foralls : 'forall' tv_bndrs '.' 'forall' rule_vars '.'
               | 'forall' rule_vars '.'
               | {- empty -}

where rule_vars (term variables) can be named "family" or "role",
but tv_vars (type variables) cannot be. However, such a definition results
in a reduce/reduce conflict. For example, when parsing:
> {-# RULE "name" forall a ... #-}
before the '...' it is impossible to determine whether we should be in the
first or second case of the above.

This is resolved by using rule_vars (which is more general) for both, and
ensuring that type-level quantified variables do not have the names "forall",
"family", or "role" in the function 'checkRuleTyVarBndrNames' in
GHC.Parser.PostProcess.
Thus, whenever the definition of tyvarid (used for tv_bndrs) is changed relative
to varid (used for rule_vars), 'checkRuleTyVarBndrNames' must be updated.
-}

-----------------------------------------------------------------------------
-- Warnings and deprecations (c.f. rules)

maybe_warning_pragma :: { Maybe (LWarningTxt GhcPs) }
        : '{-# DEPRECATED' strings '#-}'
                            {% fmap Just $ amsr (sLL $1 $> $ DeprecatedTxt (getDEPRECATED_PRAGs $1) (map stringLiteralToHsDocWst $ snd $ unLoc $2))
                                (AnnPragma (glR $1) (epTok $3) (fst $ unLoc $2) noAnn noAnn noAnn noAnn) }
        | '{-# WARNING' warning_category strings '#-}'
                            {% fmap Just $ amsr (sLL $1 $> $ WarningTxt (getWARNING_PRAGs $1) $2 (map stringLiteralToHsDocWst $ snd $ unLoc $3))
                                (AnnPragma (glR $1) (epTok $4) (fst $ unLoc $3) noAnn noAnn noAnn noAnn)}
        |  {- empty -}      { Nothing }

warning_category :: { Maybe (LocatedE (InWarningCategory GhcPs)) }
        : 'in' STRING                  { Just (reLoc $ sLL $1 $> $ InWarningCategory (epTok $1, getSTRINGs $2)
                                                                    (reLoc $ sL1 $2 $ mkWarningCategory (getSTRING $2))) }
        | {- empty -}                  { Nothing }

warnings :: { OrdList (LWarnDecl GhcPs) }
        : warnings ';' warning         {% if isNilOL $1
                                           then return ($1 `appOL` $3)
                                           else case $1 of
                                             SnocOL hs t -> do
                                              t' <- addTrailingSemiA t (epTok $2)
                                              return (snocOL hs t' `appOL` $3) }
        | warnings ';'                 {% if isNilOL $1
                                           then return $1
                                           else case $1 of
                                             SnocOL hs t -> do
                                              t' <- addTrailingSemiA t (epTok $2)
                                              return (snocOL hs t') }
        | warning                      { $1 }
        | {- empty -}                  { nilOL }

-- SUP: TEMPORARY HACK, not checking for `module Foo'
warning :: { OrdList (LWarnDecl GhcPs) }
        : warning_category namespace_spec namelist strings
                {% fmap unitOL $ amsA' (L (comb4 $1 $2 $3 $4)
                     (Warning (unLoc $2, fst $ unLoc $4) (unLoc $3)
                              (WarningTxt NoSourceText $1 (map stringLiteralToHsDocWst $ snd $ unLoc $4)))) }

namespace_spec :: { Located NamespaceSpecifier }
  : 'type'      { sL1 $1 $ TypeNamespaceSpecifier (epTok $1) }
  | 'data'      { sL1 $1 $ DataNamespaceSpecifier (epTok $1) }
  | {- empty -} { sL0    $ NoNamespaceSpecifier }

deprecations :: { OrdList (LWarnDecl GhcPs) }
        : deprecations ';' deprecation
                                       {% if isNilOL $1
                                           then return ($1 `appOL` $3)
                                           else case $1 of
                                             SnocOL hs t -> do
                                              t' <- addTrailingSemiA t (epTok $2)
                                              return (snocOL hs t' `appOL` $3) }
        | deprecations ';'             {% if isNilOL $1
                                           then return $1
                                           else case $1 of
                                             SnocOL hs t -> do
                                              t' <- addTrailingSemiA t (epTok $2)
                                              return (snocOL hs t') }
        | deprecation                  { $1 }
        | {- empty -}                  { nilOL }

-- SUP: TEMPORARY HACK, not checking for `module Foo'
deprecation :: { OrdList (LWarnDecl GhcPs) }
        : namespace_spec namelist strings
             {% fmap unitOL $ amsA' (sL (comb3 $1 $2 $>) $ (Warning (unLoc $1, fst $ unLoc $3) (unLoc $2)
                                          (DeprecatedTxt NoSourceText $ map stringLiteralToHsDocWst $ snd $ unLoc $3))) }

strings :: { Located ((EpToken "[", EpToken "]"),[Located StringLiteral]) }
    : STRING             { sL1 $1 (noAnn,[L (gl $1) (getStringLiteral $1)]) }
    | '[' stringlist ']' { sLL $1 $> $ ((epTok $1,epTok $3),fromOL (unLoc $2)) }

stringlist :: { Located (OrdList (Located StringLiteral)) }
    : stringlist ',' STRING {% if isNilOL (unLoc $1)
                                then return (sLL $1 $> (unLoc $1 `snocOL`
                                                  (L (gl $3) (getStringLiteral $3))))
                                else case (unLoc $1) of
                                   SnocOL hs t -> do
                                     let { t' = addTrailingCommaS t (glR $2) }
                                     return (sLL $1 $> (snocOL hs t' `snocOL`
                                                  (L (gl $3) (getStringLiteral $3))))

}
    | STRING                { sLL $1 $> (unitOL (L (gl $1) (getStringLiteral $1))) }
    | {- empty -}           { noLoc nilOL }

-----------------------------------------------------------------------------
-- Annotations
annotation :: { LHsDecl GhcPs }
    : '{-# ANN' name_var aexp '#-}'      {% runPV (unECP $3) >>= \ $3 ->
                                            amsA' (sLL $1 $> (AnnD noExtField $ HsAnnotation
                                            (AnnPragma (glR $1) (epTok $4) noAnn noAnn noAnn noAnn noAnn,
                                            (getANN_PRAGs $1))
                                            (ValueAnnProvenance $2) $3)) }

    | '{-# ANN' 'type' otycon aexp '#-}' {% runPV (unECP $4) >>= \ $4 ->
                                            amsA' (sLL $1 $> (AnnD noExtField $ HsAnnotation
                                            (AnnPragma (glR $1) (epTok $5) noAnn noAnn noAnn (epTok $2) noAnn,
                                            (getANN_PRAGs $1))
                                            (TypeAnnProvenance $3) $4)) }

    | '{-# ANN' 'module' aexp '#-}'      {% runPV (unECP $3) >>= \ $3 ->
                                            amsA' (sLL $1 $> (AnnD noExtField $ Hs
