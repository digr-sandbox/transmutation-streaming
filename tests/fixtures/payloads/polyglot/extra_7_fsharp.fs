module internal Fantomas.Core.CodePrinter

open System
open System.Text.RegularExpressions
open FSharp.Compiler.Text
open FSharp.Compiler.Syntax
open FSharp.Compiler.SyntaxTrivia
open FSharp.Compiler.Xml
open Fantomas.Core.AstExtensions
open Fantomas.Core.FormatConfig
open Fantomas.Core.SourceParser
open Fantomas.Core.SourceTransformer
open Fantomas.Core.Context
open Fantomas.Core.TriviaTypes

/// This type consists of contextual information which is important for formatting
/// Please avoid using this record as it can be the cause of unexpected behavior when used incorrectly
type ASTContext =
    {
        /// This pattern matters for formatting extern declarations
        IsCStylePattern: bool
        /// A field is rendered as union field or not
        IsUnionField: bool
        /// First type param might need extra spaces to avoid parsing errors on `<^`, `<'`, etc.
        IsFirstTypeParam: bool
    }

    static member Default =
        { IsCStylePattern = false
          IsUnionField = false
          IsFirstTypeParam = false }

let rec addSpaceBeforeParensInFunCall functionOrMethod arg (ctx: Context) =
    match functionOrMethod, arg with
    | SynExpr.TypeApp (e, _, _, _, _, _, _), _ -> addSpaceBeforeParensInFunCall e arg ctx
    | SynExpr.Paren _, _ -> true
    | SynExpr.Const _, _ -> true
    | UppercaseSynExpr, ConstUnitExpr -> ctx.Config.SpaceBeforeUppercaseInvocation
    | LowercaseSynExpr, ConstUnitExpr -> ctx.Config.SpaceBeforeLowercaseInvocation
    | SynExpr.Ident _, SynExpr.Ident _ -> true
    | UppercaseSynExpr, Paren _ -> ctx.Config.SpaceBeforeUppercaseInvocation
    | LowercaseSynExpr, Paren _ -> ctx.Config.SpaceBeforeLowercaseInvocation
    | _ -> true

let addSpaceBeforeParensInFunDef (spaceBeforeSetting: bool) (functionOrMethod: SynLongIdent) args =
    match functionOrMethod, args with
    | SynLongIdent(id = [ newIdent ]), _ when newIdent.idText = "new" -> false
    | _, PatParen _ -> spaceBeforeSetting
    | _, PatNamed _
    | _, SynPat.Wild _ -> true
    | SynLongIdent (id = lid), _ ->
        match List.tryLast lid with
        | None -> false
        | Some ident -> not (Char.IsUpper ident.idText.[0])
    | _ -> true

let rec genParsedInput astContext ast =
    let genParsedInput =
        match ast with
        | ImplFile im -> genImpFile astContext im
        | SigFile si -> genSigFile astContext si

    genTriviaFor ParsedInput_ ast.FullRange genParsedInput +> addFinalNewline

/// Respect insert_final_newline setting
and addFinalNewline ctx =
    let lastEvent = ctx.WriterEvents.TryHead

    match lastEvent with
    | Some WriteLineBecauseOfTrivia ->
        if ctx.Config.InsertFinalNewline then
            ctx
        else
            // Due to trivia the last event is a newline, if insert_final_newline is false, we need to remove it.
            { ctx with
                WriterEvents = ctx.WriterEvents.Tail
                WriterModel = { ctx.WriterModel with Lines = List.tail ctx.WriterModel.Lines } }
    | _ -> onlyIf ctx.Config.InsertFinalNewline sepNln ctx

(*
    See https://github.com/fsharp/FSharp.Compiler.Service/blob/master/src/fsharp/ast.fs#L1518
    hs = hashDirectives : ParsedHashDirective list
    mns = modules : SynModuleOrNamespace list
*)
and genImpFile astContext (ParsedImplFileInput (hs, mns, _, _)) =
    col sepNln hs genParsedHashDirective
    +> (if hs.IsEmpty then sepNone else sepNln)
    +> col sepNln mns (genModuleOrNamespace astContext)

and genSigFile astContext (ParsedSigFileInput (hs, mns, _, _)) =
    col sepNone hs genParsedHashDirective
    +> (if hs.IsEmpty then sepNone else sepNln)
    +> col sepNln mns (genSigModuleOrNamespace astContext)

and genParsedHashDirective (ParsedHashDirective (h, args, r)) =
    let genArg (arg: ParsedHashDirectiveArgument) =
        match arg with
        | ParsedHashDirectiveArgument.String (value, stringKind, range) ->
            genConstString stringKind value
            |> genTriviaFor ParsedHashDirectiveArgument_String range
        | ParsedHashDirectiveArgument.SourceIdentifier (identifier, _, range) ->
            !-identifier |> genTriviaFor ParsedHashDirectiveArgument_String range

    !- "#" +> !-h +> sepSpace +> col sepSpace args genArg
    |> genTriviaFor ParsedHashDirective_ r

and genModuleOrNamespaceKind
    (moduleRange: range option)
    (namespaceRange: range option)
    (kind: SynModuleOrNamespaceKind)
    =
    match kind with
    | SynModuleOrNamespaceKind.DeclaredNamespace ->
        genTriviaForOption SynModuleOrNamespace_Namespace namespaceRange !- "namespace "
    | SynModuleOrNamespaceKind.NamedModule -> genTriviaForOption SynModuleOrNamespace_Module moduleRange !- "module "
    | SynModuleOrNamespaceKind.GlobalNamespace ->
        genTriviaForOption SynModuleOrNamespace_Namespace namespaceRange !- "namespace"
        +> !- " global"
    | SynModuleOrNamespaceKind.AnonModule -> sepNone

and genModuleOrNamespace
    astContext
    (ModuleOrNamespace (ats, px, moduleRange, namespaceRange, ao, lids, mds, isRecursive, moduleKind, range))
    =
    let sepModuleAndFirstDecl =
        let firstDecl = List.tryHead mds

        match firstDecl with
        | None -> sepNone
        | Some mdl ->
            sepNln
            +> sepNlnConsideringTriviaContentBeforeFor (synModuleDeclToFsAstType mdl) mdl.Range

    let moduleOrNamespace =
        genModuleOrNamespaceKind moduleRange namespaceRange moduleKind
        +> opt sepSpace ao genAccess
        +> ifElse isRecursive (!- "rec ") sepNone
        +> genLongIdent lids

    // Anonymous module do have a single (fixed) ident in the LongIdent
    // We don't print the ident but it could have trivia assigned to it.
    let genTriviaForAnonModuleIdent =
        match lids with
        | [ ident ] ->
            genTriviaFor Ident_ ident.idRange sepNone
            |> genTriviaFor LongIdent_ ident.idRange
        | _ -> sepNone

    genPreXmlDoc px
    +> genAttributes astContext ats
    +> ifElse
        (moduleKind = SynModuleOrNamespaceKind.AnonModule)
        genTriviaForAnonModuleIdent
        (moduleOrNamespace +> sepModuleAndFirstDecl)
    +> genModuleDeclList astContext mds
    |> (match moduleKind with
        | SynModuleOrNamespaceKind.AnonModule -> genTriviaFor SynModuleOrNamespace_AnonModule range
        | SynModuleOrNamespaceKind.DeclaredNamespace -> genTriviaFor SynModuleOrNamespace_DeclaredNamespace range
        | SynModuleOrNamespaceKind.GlobalNamespace -> genTriviaFor SynModuleOrNamespace_GlobalNamespace range
        | SynModuleOrNamespaceKind.NamedModule -> genTriviaFor SynModuleOrNamespace_NamedModule range)

and genSigModuleOrNamespace
    astContext
    (SigModuleOrNamespace (ats, px, moduleRange, namespaceRange, ao, lids, mds, isRecursive, moduleKind, range))
    =
    let sepModuleAndFirstDecl =
        let firstDecl = List.tryHead mds

        match firstDecl with
        | None -> sepNone
        | Some mdl ->
            sepNln
            +> sepNlnConsideringTriviaContentBeforeFor (synModuleSigDeclToFsAstType mdl) mdl.Range

    let moduleOrNamespace =
        genModuleOrNamespaceKind moduleRange namespaceRange moduleKind
        +> opt sepSpace ao genAccess
        +> ifElse isRecursive (!- "rec ") sepNone
        +> genLongIdent lids

    genPreXmlDoc px
    +> genAttributes astContext ats
    +> ifElse (moduleKind = SynModuleOrNamespaceKind.AnonModule) sepNone (moduleOrNamespace +> sepModuleAndFirstDecl)
    +> genSigModuleDeclList astContext mds
    |> (match moduleKind with
        | SynModuleOrNamespaceKind.AnonModule -> genTriviaFor SynModuleOrNamespaceSig_AnonModule range
        | SynModuleOrNamespaceKind.DeclaredNamespace -> genTriviaFor SynModuleOrNamespaceSig_DeclaredNamespace range
        | SynModuleOrNamespaceKind.GlobalNamespace -> genTriviaFor SynModuleOrNamespaceSig_GlobalNamespace range
        | SynModuleOrNamespaceKind.NamedModule -> genTriviaFor SynModuleOrNamespaceSig_NamedModule range)

and genModuleDeclList astContext e =
    let rec collectItems
        (e: SynModuleDecl list)
        (finalContinuation: ColMultilineItem list -> ColMultilineItem list)
        : ColMultilineItem list =
        match e with
        | [] -> finalContinuation []
        | OpenL (xs, ys) ->
            let expr = col sepNln xs (genModuleDecl astContext)

            let r, triviaType =
                List.head xs |> fun mdl -> mdl.Range, synModuleDeclToFsAstType mdl
            // SynModuleDecl.Open cannot have attributes
            let sepNln = sepNlnConsideringTriviaContentBeforeFor triviaType r

            collectItems ys (fun ysItems -> ColMultilineItem(expr, sepNln) :: ysItems |> finalContinuation)

        | HashDirectiveL (xs, ys) ->
            let expr = col sepNln xs (genModuleDecl astContext)

            let r = List.head xs |> fun mdl -> mdl.Range
            // SynModuleDecl.HashDirective cannot have attributes
            let sepNln = sepNlnConsideringTriviaContentBeforeFor SynModuleDecl_HashDirective r

            collectItems ys (fun ysItems -> ColMultilineItem(expr, sepNln) :: ysItems |> finalContinuation)

        | AttributesL (xs, y :: rest) ->
            let expr =
                col sepNln xs (genModuleDecl astContext)
                +> sepNlnConsideringTriviaContentBeforeFor (synModuleDeclToFsAstType y) y.Range
                +> genModuleDecl astContext y

            let r = List.head xs |> fun mdl -> mdl.Range

            let sepNln = sepNlnConsideringTriviaContentBeforeFor SynModuleDecl_Attributes r

            collectItems rest (fun restItems -> ColMultilineItem(expr, sepNln) :: restItems |> finalContinuation)

        | m :: rest ->
            let sepNln =
                sepNlnConsideringTriviaContentBeforeFor (synModuleDeclToFsAstType m) m.Range

            let expr = genModuleDecl astContext m

            collectItems rest (fun restItems -> ColMultilineItem(expr, sepNln) :: restItems |> finalContinuation)

    collectItems e id |> colWithNlnWhenItemIsMultiline

and genSigModuleDeclList astContext (e: SynModuleSigDecl list) =
    let rec collectItems
        (e: SynModuleSigDecl list)
        (finalContinuation: ColMultilineItem list -> ColMultilineItem list)
        : ColMultilineItem list =
        match e with
        | [] -> finalContinuation []
        | SigOpenL (xs, ys) ->
            let expr = col sepNln xs (genSigModuleDecl astContext)

            let r, triviaType =
                List.head xs |> fun mdl -> mdl.Range, synModuleSigDeclToFsAstType mdl
            // SynModuleSigDecl.Open cannot have attributes
            let sepNln = sepNlnConsideringTriviaContentBeforeFor triviaType r

            collectItems ys (fun ysItems -> ColMultilineItem(expr, sepNln) :: ysItems |> finalContinuation)

        | SigHashDirectiveL (xs, ys) ->
            let expr = col sepNln xs (genSigModuleDecl astContext)

            let r = List.head xs |> fun mdl -> mdl.Range

            let sepNln =
                sepNlnConsideringTriviaContentBeforeFor SynModuleSigDecl_HashDirective r

            collectItems ys (fun ysItems -> ColMultilineItem(expr, sepNln) :: ysItems |> finalContinuation)

        | s :: rest ->
            let sepNln =
                sepNlnConsideringTriviaContentBeforeFor (synModuleSigDeclToFsAstType s) s.Range

            let expr = genSigModuleDecl astContext s

            collectItems rest (fun restItems -> ColMultilineItem(expr, sepNln) :: restItems |> finalContinuation)

    collectItems e id |> colWithNlnWhenItemIsMultiline

and genModuleDecl astContext (node: SynModuleDecl) =
    match node with
    | Attributes ats ->
        fun (ctx: Context) ->
            let attributesExpr =
                // attributes can have trivia content before or after
                // we do extra detection to ensure no additional newline is introduced
                // first attribute should not have a newline anyway
                List.fold
                    (fun (prevContentAfterPresent, prevExpr) (a: SynAttributeList) ->
                        let expr =
                            ifElse
                                prevContentAfterPresent
                                sepNone
                                (sepNlnConsideringTriviaContentBeforeFor SynModuleDecl_Attributes a.Range)
                            +> ((col sepNln a.Attributes (genAttribute astContext))
                                |> genTriviaFor SynAttributeList_ a.Range)

                        let hasContentAfter = ctx.HasContentAfter(SynAttributeList_, a.Range)
                        (hasContentAfter, prevExpr +> expr))
                    (true, sepNone)
                    ats
                |> snd

            attributesExpr ctx
    | DeclExpr e -> genExpr astContext e
    | Exception ex -> genException astContext ex
    | HashDirective p -> genParsedHashDirective p
    | Extern (ats, px, ao, t, sli, ps) ->
        genPreXmlDoc px
        +> genAttributes astContext ats
        +> !- "extern "
        +> genType { astContext with IsCStylePattern = true } false t
        +> sepSpace
        +> opt sepSpace ao genAccess
        +> genSynLongIdent false sli
        +> sepOpenT
        +> col sepComma ps (genPat { astContext with IsCStylePattern = true })
        +> sepCloseT
    // Add a new line after module-level let bindings
    | Let b -> genLetBinding astContext "let " b
    | LetRec (b :: bs) ->
        let sepBAndBs =
            match List.tryHead bs with
            | Some b' ->
                let r = b'.RangeOfBindingWithRhs

                sepNln +> sepNlnConsideringTriviaContentBeforeFor (synBindingToFsAstType b) r
            | None -> sepNone

        genLetBinding astContext "let rec " b
        +> sepBAndBs
        +> colEx
            (fun (b': SynBinding) ->
                let r = b'.RangeOfBindingWithRhs

                sepNln +> sepNlnConsideringTriviaContentBeforeFor (synBindingToFsAstType b) r)
            bs
            (fun andBinding ->
                enterNodeFor (synBindingToFsAstType b) andBinding.RangeOfBindingWithRhs
                +> genLetBinding astContext "and " andBinding)

    | ModuleAbbrev (ident, lid) -> !- "module " +> genIdent ident +> sepEq +> sepSpace +> genLongIdent lid
    | NamespaceFragment m -> failwithf "NamespaceFragment hasn't been implemented yet: %O" m
    | NestedModule (ats, px, moduleKeyword, ao, lid, isRecursive, equalsRange, mds) ->
        genPreXmlDoc px
        +> genAttributes astContext ats
        +> genTriviaForOption SynModuleDecl_NestedModule_Module moduleKeyword (!- "module ")
        +> opt sepSpace ao genAccess
        +> ifElse isRecursive (!- "rec ") sepNone
        +> genLongIdent lid
        +> genEq SynModuleDecl_NestedModule_Equals equalsRange
        +> indent
        +> sepNln
        +> genModuleDeclList astContext mds
        +> unindent

    | Open lid -> !- "open " +> genSynLongIdent false lid
    | OpenType lid -> !- "open type " +> genSynLongIdent false lid
    // There is no nested types and they are recursive if there are more than one definition
    | Types (t :: ts) ->
        let items =
            ColMultilineItem(genTypeDefn astContext true t, sepNone)
            :: (List.map
                    (fun t ->
                        ColMultilineItem(
                            genTypeDefn astContext false t,
                            sepNlnConsideringTriviaContentBeforeFor SynTypeDefn_ t.Range
                        ))
                    ts)

        colWithNlnWhenItemIsMultilineUsingConfig items
    | md -> failwithf "Unexpected module declaration: %O" md
    |> genTriviaFor (synModuleDeclToFsAstType node) node.Range

and genSigModuleDecl astContext node =
    match node with
    | SigException ex -> genSigException astContext ex
    | SigHashDirective p -> genParsedHashDirective p
    | SigVal v -> genVal astContext v
    | SigModuleAbbrev (ident, lid) -> !- "module " +> genIdent ident +> sepEq +> sepSpace +> genLongIdent lid
    | SigNamespaceFragment m -> failwithf "NamespaceFragment is not supported yet: %O" m
    | SigNestedModule (ats, px, moduleKeyword, ao, lid, equalsRange, mds) ->
        genPreXmlDoc px
        +> genAttributes astContext ats
        +> genTriviaForOption SynModuleSigDecl_NestedModule_Module moduleKeyword !- "module "
        +> opt sepSpace ao genAccess
        +> genLongIdent lid
        +> genEq SynModuleSigDecl_NestedModule_Equals equalsRange
        +> indent
        +> sepNln
        +> genSigModuleDeclList astContext mds
        +> unindent

    | SigOpen lid -> !- "open " +> genSynLongIdent false lid
    | SigOpenType sli -> !- "open type " +> genSynLongIdent false sli
    | SigTypes (t :: ts) ->
        let items =
            ColMultilineItem(genSigTypeDefn astContext true t, sepNone)
            :: (List.map
                    (fun (t: SynTypeDefnSig) ->
                        let sepNln = sepNlnConsideringTriviaContentBeforeFor SynTypeDefnSig_ t.Range

                        ColMultilineItem(genSigTypeDefn astContext false t, sepNln))
                    ts)

        colWithNlnWhenItemIsMultilineUsingConfig items
    | md -> failwithf "Unexpected module signature declaration: %O" md
    |> genTriviaFor (synModuleSigDeclToFsAstType node) node.Range

and genIdent (ident: Ident) =
    let width = ident.idRange.EndColumn - ident.idRange.StartColumn

    let genIdent =
        if ident.idText.Length + 4 = width then
            // add backticks
            !- $"``{ident.idText}``"
        else
            !-ident.idText

    genTriviaFor Ident_ ident.idRange genIdent

and genLongIdent (lid: LongIdent) =
    col sepDot lid genIdent |> genTriviaFor LongIdent_ (longIdentFullRange lid)

and genSynIdent (addDot: bool) (synIdent: SynIdent) =
    let (SynIdent (ident, trivia)) = synIdent

    match trivia with
    | Some (IdentTrivia.OriginalNotation text) -> !-text
    | Some (IdentTrivia.OriginalNotationWithParen (_, text, _)) -> !- $"({text})"
    | Some (IdentTrivia.HasParenthesis _) -> !- $"({ident.idText})"
    | None -> genIdent ident

    |> fun genSy -> genTriviaFor SynIdent_ synIdent.FullRange (onlyIf addDot sepDot +> genSy)

and genSynLongIdent (addLeadingDot: bool) (longIdent: SynLongIdent) =
    let lastIndex = longIdent.IdentsWithTrivia.Length - 1

    coli sepNone longIdent.IdentsWithTrivia (fun idx si ->
        genSynIdent (addLeadingDot || idx > 0) si
        +> onlyIf (idx < lastIndex) (sepNlnWhenWriteBeforeNewlineNotEmpty sepNone))
    |> genTriviaFor SynLongIdent_ longIdent.FullRange

and genSynLongIdentMultiline (addLeadingDot: bool) (longIdent: SynLongIdent) =
    coli sepNln longIdent.IdentsWithTrivia (fun idx -> genSynIdent (idx > 0 || addLeadingDot))
    |> genTriviaFor SynLongIdent_ longIdent.FullRange

and genAccess (vis: SynAccess) =
    match vis with
    | SynAccess.Public r -> genTriviaFor SynAccess_Public r !- "public"
    | SynAccess.Internal r -> genTriviaFor SynAccess_Internal r !- "internal"
    | SynAccess.Private r -> genTriviaFor SynAccess_Private r !- "private"

and genAttribute astContext (Attribute (sli, e, target)) =
    match e with
    // Special treatment for function application on attributes
    | ConstUnitExpr -> !- "[<" +> opt sepColon target genIdent +> genSynLongIdent false sli +> !- ">]"
    | e ->
        let argSpacing = if hasParenthesis e then sepNone else sepSpace

        !- "[<"
        +> opt sepColon target genIdent
        +> genSynLongIdent false sli
        +> argSpacing
        +> genExpr astContext e
        +> !- ">]"

and genAttributesCore astContext (ats: SynAttribute seq) =
    let genAttributeExpr astContext (Attribute (sli, e, target) as attr) =
        match e with
        | ConstUnitExpr -> opt sepColon target genIdent +> genSynLongIdent false sli
        | e ->
            let argSpacing = if hasParenthesis e then sepNone else sepSpace

            opt sepColon target genIdent
            +> genSynLongIdent false sli
            +> argSpacing
            +> genExpr astContext e
        |> genTriviaFor SynAttribute_ attr.Range

    let shortExpression =
        !- "[<"
        +> atCurrentColumn (col sepSemi ats (genAttributeExpr astContext))
        +> !- ">]"

    let longExpression =
        !- "[<"
        +> atCurrentColumn (col (sepSemi +> sepNln) ats (genAttributeExpr astContext))
        +> !- ">]"

    ifElse (Seq.isEmpty ats) sepNone (expressionFitsOnRestOfLine shortExpression longExpression)

and genOnelinerAttributes astContext ats =
    let ats = List.collect (fun (a: SynAttributeList) -> a.Attributes) ats
    ifElse (Seq.isEmpty ats) sepNone (genAttributesCore astContext ats +> sepSpace)

/// Try to group attributes if they are on the same line
/// Separate same-line attributes by ';'
/// Each bucket is printed in a different line
and genAttributes astContext (ats: SynAttributes) =
    colPost sepNlnUnlessLastEventIsNewline sepNln ats (fun a ->
        (genAttributesCore astContext a.Attributes
         |> genTriviaFor SynAttributeList_ a.Range)
        +> sepNlnWhenWriteBeforeNewlineNotEmpty sepNone)

and genPreXmlDoc (PreXmlDoc (lines, _)) =
    colPost sepNln sepNln lines (sprintf "///%s" >> (!-))

and genExprSepEqPrependType
    (astContext: ASTContext)
    (equalsAstType: FsAstType)
    (equalsRange: range option)
    (e: SynExpr)
    =
    match e with
    | TypedExpr (Typed, e, t) ->
        sepColon
        +> genType astContext false t
        +> genEq equalsAstType equalsRange
        +> sepSpaceOrIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e)
    | _ ->
        genEq equalsAstType equalsRange
        +> sepSpaceOrIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e)

and genTyparList astContext tps =
    colSurr sepOpenT sepCloseT wordOr tps (genTypar astContext)

and genTypeSupportMember astContext st =
    match st with
    | SynType.Var (td, _) -> genTypar astContext td
    | TLongIdent sli -> genSynLongIdent false sli
    | _ -> !- ""

and genTypeSupportMemberList astContext tps =
    colSurr sepOpenT sepCloseT wordOr tps (genTypeSupportMember astContext)

and genTypeAndParam astContext (typeName: Context -> Context) (tds: SynTyparDecls option) tcs =
    let types openSep tds tcs closeSep =
        (openSep
         +> coli sepComma tds (fun i -> genTyparDecl { astContext with IsFirstTypeParam = i = 0 })
         +> genSynTypeConstraintList astContext tcs
         +> closeSep)

    match tds with
    | None -> typeName
    | Some (PostfixList (gt, tds, tcs, lt, _)) ->
        typeName
        +> types
            (genTriviaFor SynTyparDecls_PostfixList_Greater gt !- "<")
            tds
            tcs
            (genTriviaFor SynTyparDecls_PostfixList_Lesser lt !- ">")
    | Some (SynTyparDecls.PostfixList _) -> sepNone // captured above
    | Some (SynTyparDecls.PrefixList (tds, _range)) -> types (!- "(") tds [] (!- ")") +> !- " " +> typeName
    | Some (SynTyparDecls.SinglePrefix (td, _range)) ->
        genTyparDecl { astContext with IsFirstTypeParam = true } td
        +> sepSpace
        +> typeName
    +> colPre (!- " when ") wordAnd tcs (genTypeConstraint astContext)

and genTypeParamPostfix astContext tds =
    match tds with
    | Some (PostfixList (gt, tds, tcs, lt, _range)) ->
        (genTriviaFor SynTyparDecls_PostfixList_Greater gt !- "<")
        +> coli sepComma tds (fun i -> genTyparDecl { astContext with IsFirstTypeParam = i = 0 })
        +> genSynTypeConstraintList astContext tcs
        +> (genTriviaFor SynTyparDecls_PostfixList_Lesser lt !- ">")
    | _ -> sepNone

and genSynTypeConstraintList astContext tcs =
    match tcs with
    | [] -> sepNone
    | _ ->
        let short =
            colPre (sepSpace +> !- "when ") wordAnd tcs (genTypeConstraint astContext)

        let long =
            colPre (!- "when ") (sepNln +> wordAndFixed +> sepSpace) tcs (genTypeConstraint astContext)

        autoIndentAndNlnIfExpressionExceedsPageWidth (expressionFitsOnRestOfLine short long)

and genLetBinding astContext pref b =
    let genPref letKeyword =
        genTriviaForOption SynBinding_Let letKeyword !-pref

    let isRecursiveLetOrUseFunction = (pref = "and ")

    match b with
    | LetBinding (ats, px, letKeyword, ao, isInline, isMutable, p, equalsRange, e, valInfo) ->
        match e, p with
        | TypedExpr (Typed, e, t), PatLongIdent (ao, sli, ps, tpso) when (List.isNotEmpty ps) ->
            genSynBindingFunctionWithReturnType
                astContext
                false
                isRecursiveLetOrUseFunction
                px
                ats
                (genPref letKeyword)
                ao
                isInline
                isMutable
                sli
                p.Range
                ps
                tpso
                t
                valInfo
                equalsRange
                e
        | e, PatLongIdent (ao, sli, ps, tpso) when (List.isNotEmpty ps) ->
            genSynBindingFunction
                astContext
                false
                isRecursiveLetOrUseFunction
                px
                ats
                (genPref letKeyword)
                ao
                isInline
                isMutable
                sli
                p.Range
                ps
                tpso
                equalsRange
                e
        | TypedExpr (Typed, e, t), pat ->
            genSynBindingValue
                astContext
                isRecursiveLetOrUseFunction
                px
                ats
                (genPref letKeyword)
                ao
                isInline
                isMutable
                pat
                (Some t)
                equalsRange
                e
        | _, PatTuple _ ->
            genLetBindingDestructedTuple
                astContext
                isRecursiveLetOrUseFunction
                px
                ats
                pref
                ao
                isInline
                isMutable
                p
                equalsRange
                e
        | _, pat ->
            genSynBindingValue
                astContext
                isRecursiveLetOrUseFunction
                px
                ats
                (genPref letKeyword)
                ao
                isInline
                isMutable
                pat
                None
                equalsRange
                e
        | _ -> sepNone
    | DoBinding (ats, px, e) ->
        let prefix =
            if pref.Contains("let") then
                pref.Replace("let", "do")
            else
                "do "

        genPreXmlDoc px
        +> genAttributes astContext ats
        +> !-prefix
        +> autoIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e)

    | b -> failwithf "%O isn't a let binding" b
    +> leaveNodeFor (synBindingToFsAstType b) b.RangeOfBindingWithRhs

and genProperty astContext (getOrSetType: FsAstType, getOrSetRange: range, binding: SynBinding) =
    let genGetOrSet =
        let getOrSetText =
            match getOrSetType with
            | SynMemberDefn_GetSetMember_Get -> "get"
            | SynMemberDefn_GetSetMember_Set -> "set"
            | _ -> failwith "expected \"get\" or \"set\""

        genTriviaFor getOrSetType getOrSetRange !-getOrSetText +> sepSpace

    match binding with
    | SynBinding (headPat = PatLongIdent (ao, _, ps, _); expr = e; trivia = { EqualsRange = equalsRange }) ->
        let tuplerize ps =
            let rec loop acc =
                function
                | [ p ] -> (List.rev acc, p)
                | p1 :: ps -> loop (p1 :: acc) ps
                | [] -> invalidArg "p" "Patterns should not be empty"

            loop [] ps

        match ps with
        | [ _, PatTuple ps ] ->
            let ps, p = tuplerize ps

            opt sepSpace ao genAccess
            +> genGetOrSet
            +> ifElse
                (List.atMostOne ps)
                (col sepComma ps (genPat astContext) +> sepSpace)
                (sepOpenT +> col sepComma ps (genPat astContext) +> sepCloseT +> sepSpace)
            +> genPat astContext p
            +> genExprSepEqPrependType astContext SynBinding_Equals equalsRange e

        | ps ->
            opt sepSpace ao genAccess
            +> genGetOrSet
            +> col sepSpace ps (fun (_, pat) -> genPat astContext pat)
            +> genExprSepEqPrependType astContext SynBinding_Equals equalsRange e
    | _ -> sepNone

and genMemberBindingList astContext ms =
    ms
    |> List.map (fun (mb: SynBinding) ->
        let expr = genMemberBinding astContext mb
        let r = mb.RangeOfBindingWithRhs

        let sepNln = sepNlnConsideringTriviaContentBeforeFor (synBindingToFsAstType mb) r

        ColMultilineItem(expr, sepNln))
    |> colWithNlnWhenItemIsMultiline

and genMemberBinding astContext b =
    match b with
    | MemberBinding (ats, px, ao, isInline, mf, p, equalsRange, e, synValInfo) ->
        let prefix = genMemberFlags mf
        genMemberBindingImpl astContext prefix ats px ao isInline p equalsRange e synValInfo

    | ExplicitCtor (ats, px, ao, p, equalsRange, e, io) ->
        let prefix =
            let genPat ctx =
                match p with
                | PatExplicitCtor (ao, pat) ->
                    (opt sepSpace ao genAccess
                     +> !- "new"
                     +> sepSpaceBeforeClassConstructor
                     +> genPat astContext pat)
                        ctx
                | _ -> genPat astContext p ctx

            genPreXmlDoc px
            +> genAttributes astContext ats
            +> opt sepSpace ao genAccess
            +> genPat
            +> optSingle (fun ident -> !- " as " +> genIdent ident) io

        match e with
        // Handle special "then" block i.e. fake sequential expressions in constructors
        | Sequential (e1, e2, false) ->
            prefix
            +> genEq SynBinding_Equals equalsRange
            +> indent
            +> sepNln
            +> genExpr astContext e1
            +> sepNln
            +> !- "then "
            +> autoIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e2)
            +> unindent

        | e ->
            prefix
            +> genEq SynBinding_Equals equalsRange
            +> sepSpaceOrIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e)

    | b -> failwithf "%O isn't a member binding" b
    |> genTriviaFor (synBindingToFsAstType b) b.RangeOfBindingWithRhs

and genMemberBindingImpl
    (astContext: ASTContext)
    (prefix: Context -> Context)
    (ats: SynAttributes)
    (px: PreXmlDoc)
    (ao: SynAccess option)
    (isInline: bool)
    (p: SynPat)
    (equalsRange: range option)
    (e: SynExpr)
    (synValInfo: SynValInfo)
    =
    match e, p with
    | TypedExpr (Typed, e, t), PatLongIdent (ao, s, ps, tpso) when (List.isNotEmpty ps) ->
        genSynBindingFunctionWithReturnType
            astContext
            true
            false
            px
            ats
            prefix
            ao
            isInline
            false
            s
            p.Range
            ps
            tpso
            t
            synValInfo
            equalsRange
            e
    | e, PatLongIdent (ao, s, ps, tpso) when (List.isNotEmpty ps) ->
        genSynBindingFunction astContext true false px ats prefix ao isInline false s p.Range ps tpso equalsRange e
    | TypedExpr (Typed, e, t), pat ->
        genSynBindingValue astContext false px ats prefix ao isInline false pat (Some t) equalsRange e
    | _, pat -> genSynBindingValue astContext false px ats prefix ao isInline false pat None equalsRange e

and genMemberFlags (mf: SynMemberFlags) =
    match mf.Trivia with
    | { StaticRange = Some s
        MemberRange = Some _m } -> genTriviaFor SynMemberFlags_Static s !- "static" +> sepSpace +> !- "member "
    | { OverrideRange = Some _o } -> !- "override "
    | { DefaultRange = Some _d } -> !- "default "
    | { AbstractRange = Some a
        MemberRange = Some m } ->
        genTriviaFor SynMemberFlags_Abstract a !- "abstract"
        +> sepSpace
        +> genTriviaFor SynMemberFlags_Member m !- "member "
    | { MemberRange = Some m } -> genTriviaFor SynMemberFlags_Member m !- "member "
    | { AbstractRange = Some a } -> genTriviaFor SynMemberFlags_Abstract a !- "abstract "
    | _ -> sepNone

and genVal astContext (Val (ats, px, valKeyword, ao, si, t, vi, isInline, isMutable, tds, eo, range)) =
    let typeName = genTypeAndParam astContext (genSynIdent false si) tds []

    let (FunType namedArgs) = (t, vi)
    let hasGenerics = Option.isSome tds

    genPreXmlDoc px
    +> genAttributes astContext ats
    +> (genTriviaForOption SynValSig_Val valKeyword !- "val "
        +> onlyIf isInline (!- "inline ")
        +> onlyIf isMutable (!- "mutable ")
        +> opt sepSpace ao genAccess
        +> typeName)
    +> ifElse hasGenerics sepColonWithSpacesFixed sepColon
    +> ifElse
        (List.isNotEmpty namedArgs)
        (autoIndentAndNlnIfExpressionExceedsPageWidth (genTypeList astContext namedArgs))
        (genConstraints astContext t vi)
    +> optSingle (fun e -> sepEq +> sepSpace +> genExpr astContext e) eo
    |> genTriviaFor SynValSig_ range

and genRecordFieldName astContext (SynExprRecordField ((rfn, _), equalsRange, eo, _blockSeparator) as rf) =
    opt sepNone eo (fun e ->
        let expr = sepSpaceOrIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e)

        genSynLongIdent false rfn +> genEq SynExprRecordField_Equals equalsRange +> expr)
    |> genTriviaFor SynExprRecordField_ rf.FullRange

and genAnonRecordFieldName astContext (AnonRecordFieldName (ident, equalsRange, e, range)) =
    let expr = sepSpaceOrIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e)

    genIdent ident +> genEq SynExpr_AnonRecd_Field_Equals equalsRange +> expr
    |> genTriviaFor SynExpr_AnonRecd_Field range

and genTuple astContext es =
    let genShortExpr astContext e =
        addParenForTupleWhen (genExpr astContext) e

    let shortExpression = col sepComma es (genShortExpr astContext)

    let longExpression = genTupleMultiline astContext es

    atCurrentColumn (expressionFitsOnRestOfLine shortExpression longExpression)

and genTupleMultiline astContext es =
    let containsLambdaOrMatchExpr =
        es
        |> List.pairwise
        |> List.exists (function
            | SynExpr.Match _, _
            | SynExpr.Lambda _, _
            | InfixApp (_, _, _, SynExpr.Lambda _, _), _ -> true
            | _ -> false)

    let sep =
        if containsLambdaOrMatchExpr then
            (sepNln +> sepComma)
        else
            (sepCommaFixed +> sepNln)

    let lastIndex = List.length es - 1

    let genExpr astContext idx e =
        match e with
        | SynExpr.IfThenElse _ when (idx < lastIndex) ->
            autoParenthesisIfExpressionExceedsPageWidth (genExpr astContext e)
        | InfixApp (equal, operatorSli, e1, e2, range) when (equal = "=") ->
            genNamedArgumentExpr astContext operatorSli e1 e2 range
        | _ -> genExpr astContext e

    coli sep es (genExpr astContext)

and genNamedArgumentExpr (astContext: ASTContext) (operatorSli: SynLongIdent) e1 e2 appRange =
    let short =
        genExpr astContext e1
        +> sepSpace
        +> genSynLongIdent false operatorSli
        +> sepSpace
        +> genExpr astContext e2

    let long =
        genExpr astContext e1
        +> sepSpace
        +> genSynLongIdent false operatorSli
        +> autoIndentAndNlnExpressUnlessStroustrup (fun e -> sepSpace +> genExpr astContext e) e2

    expressionFitsOnRestOfLine short long |> genTriviaFor SynExpr_App appRange

and genExpr astContext synExpr ctx =
    let expr =
        match synExpr with
        | LazyExpr (lazyKeyword, e) ->
            let isInfixExpr =
                match e with
                | InfixApp _ -> true
                | _ -> false

            let genInfixExpr (ctx: Context) =
                isShortExpression
                    ctx.Config.MaxInfixOperatorExpression
                    // if this fits on the rest of line right after the lazy keyword, it should be wrapped in parenthesis.
                    (sepOpenT +> genExpr astContext e +> sepCloseT)
                    // if it is multiline there is no need for parenthesis, because of the indentation
                    (indent +> sepNln +> genExpr astContext e +> unindent)
                    ctx

            let genNonInfixExpr =
                autoIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e)

            genTriviaFor SynExpr_Lazy_Lazy lazyKeyword !- "lazy "
            +> ifElse isInfixExpr genInfixExpr genNonInfixExpr

        | SingleExpr (kind, e) ->
            let mapping =
                (match kind with
                 | YieldFrom _
                 | Yield _
                 | Return _
                 | ReturnFrom _
                 | Do _
                 | DoBang _ -> autoIndentAndNlnIfExpressionExceedsPageWidthUnlessStroustrup (genExpr astContext) e
                 | _ -> autoIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e))

            match kind with
            | InferredDowncast downcastKeyword ->
                genTriviaFor SynExpr_InferredDowncast_Downcast downcastKeyword !- "downcast "
            | InferredUpcast upcastKeyword -> genTriviaFor SynExpr_InferredUpcast_Upcast upcastKeyword !- "upcast "
            | Assert assertKeyword -> genTriviaFor SynExpr_Assert_Assert assertKeyword !- "assert "
            | AddressOfSingle ampersandToken -> genTriviaFor SynExpr_AddressOf_SingleAmpersand ampersandToken !- "&"
            | AddressOfDouble ampersandToken -> genTriviaFor SynExpr_AddressOf_DoubleAmpersand ampersandToken !- "&&"
            | Yield yieldKeyword -> genTriviaFor SynExpr_YieldOrReturn_Yield yieldKeyword !- "yield "
            | Return returnKeyword -> genTriviaFor SynExpr_YieldOrReturn_Return returnKeyword !- "return "
            | YieldFrom yieldBangKeyword ->
                genTriviaFor SynExpr_YieldOrReturnFrom_YieldBang yieldBangKeyword !- "yield! "
            | ReturnFrom returnBangKeyword ->
                genTriviaFor SynExpr_YieldOrReturnFrom_ReturnBang returnBangKeyword !- "return! "
            | Do doKeyword -> genTriviaFor SynExpr_Do_Do doKeyword !- "do "
            | DoBang doBangKeyword -> genTriviaFor SynExpr_DoBang_DoBang doBangKeyword !- "do! "
            | Fixed fixedKeyword -> genTriviaFor SynExpr_Fixed_Fixed fixedKeyword !- "fixed "
            +> mapping

        | ConstExpr (c, r) -> genConst c r
        | NullExpr -> !- "null"
        // Not sure about the role of e1
        | Quote (_, e2, isRaw) ->
            let e =
                expressionFitsOnRestOfLine
                    (genExpr astContext e2)
                    (indent +> sepNln +> genExpr astContext e2 +> unindent +> sepNln)

            ifElse
                isRaw
                (!- "<@@" +> sepSpace +> e +> sepSpace +> !- "@@>")
                (!- "<@" +> sepSpace +> e +> sepSpace +> !- "@>")
        | TypedExpr (TypeTest, e, t) -> genExpr astContext e +> !- " :? " +> genType astContext false t
        | TypedExpr (Downcast, e, t) ->
            let shortExpr = genExpr astContext e +> !- " :?> " +> genType astContext false t

            let longExpr =
                genExpr astContext e +> sepNln +> !- ":?> " +> genType astContext false t

            expressionFitsOnRestOfLine shortExpr longExpr
        | TypedExpr (Upcast, e, t) ->
            let shortExpr = genExpr astContext e +> !- " :> " +> genType astContext false t

            let longExpr =
                genExpr astContext e +> sepNln +> !- ":> " +> genType astContext false t

            expressionFitsOnRestOfLine shortExpr longExpr
        | TypedExpr (Typed, e, t) -> genExpr astContext e +> sepColon +> genType astContext false t
        | NewTuple (t, px) ->
            let sepSpace (ctx: Context) =
                match t with
                | UppercaseSynType -> onlyIf ctx.Config.SpaceBeforeUppercaseInvocation sepSpace ctx
                | LowercaseSynType -> onlyIf ctx.Config.SpaceBeforeLowercaseInvocation sepSpace ctx

            let short =
                !- "new " +> genType astContext false t +> sepSpace +> genExpr astContext px

            let long =
                !- "new "
                +> genType astContext false t
                +> sepSpace
                +> genMultilineFunctionApplicationArguments astContext px

            expressionFitsOnRestOfLine short long
        | SynExpr.New (_, t, e, _) -> !- "new " +> genType astContext false t +> sepSpace +> genExpr astContext e
        | Tuple (es, _) -> genTuple astContext es
        | StructTuple es -> !- "struct " +> sepOpenT +> genTuple astContext es +> sepCloseT
        | ArrayOrList (sr, isArray, [], er, _) ->
            ifElse
                isArray
                (genTriviaFor SynExpr_ArrayOrList_OpeningDelimiter sr sepOpenAFixed
                 +> genTriviaFor SynExpr_ArrayOrList_ClosingDelimiter er sepCloseAFixed)
                (genTriviaFor SynExpr_ArrayOrList_OpeningDelimiter sr sepOpenLFixed
                 +> genTriviaFor SynExpr_ArrayOrList_ClosingDelimiter er sepCloseLFixed)
        | ArrayOrList (openingTokenRange, isArray, xs, closingTokenRange, _) ->
            let smallExpression =
                ifElse
                    isArray
                    (genTriviaFor SynExpr_ArrayOrList_OpeningDelimiter openingTokenRange sepOpenA)
                    (genTriviaFor SynExpr_ArrayOrList_OpeningDelimiter openingTokenRange sepOpenL)
                +> col sepSemi xs (genExpr astContext)
                +> ifElse
                    isArray
                    (genTriviaFor SynExpr_ArrayOrList_ClosingDelimiter closingTokenRange sepCloseA)
                    (genTriviaFor SynExpr_ArrayOrList_ClosingDelimiter closingTokenRange sepCloseL)

            let multilineExpression =
                ifAlignBrackets
                    (genMultiLineArrayOrListAlignBrackets isArray xs openingTokenRange closingTokenRange astContext)
                    (genMultiLineArrayOrList isArray xs openingTokenRange closingTokenRange astContext)

            fun ctx ->
                if
                    List.exists isIfThenElseWithYieldReturn xs
                    || List.forall isSynExprLambdaOrIfThenElse xs
                then
                    multilineExpression ctx
                else
                    let size = getListOrArrayExprSize ctx ctx.Config.MaxArrayOrListWidth xs

                    isSmallExpression size smallExpression multilineExpression ctx

        | Record (openingBrace, inheritOpt, xs, eo, closingBrace) ->
            let smallRecordExpr =
                genTriviaFor SynExpr_Record_OpeningBrace openingBrace sepOpenS
                +> optSingle
                    (fun (inheritType, inheritExpr) ->
                        !- "inherit "
                        +> genType astContext false inheritType
                        +> addSpaceBeforeClassConstructor inheritExpr
                        +> genExpr astContext inheritExpr
                        +> onlyIf (List.isNotEmpty xs) sepSemi)
                    inheritOpt
                +> optSingle (fun e -> genExpr astContext e +> !- " with ") eo
                +> col sepSemi xs (genRecordFieldName astContext)
                +> genTriviaFor SynExpr_Record_ClosingBrace closingBrace sepCloseS

            let multilineRecordExpr =
                ifAlignBrackets
                    (genMultilineRecordInstanceAlignBrackets astContext openingBrace inheritOpt xs eo closingBrace)
                    (genMultilineRecordInstance astContext openingBrace inheritOpt xs eo closingBrace)

            fun ctx ->
                let size = getRecordSize ctx xs
                isSmallExpression size smallRecordExpr multilineRecordExpr ctx

        | AnonRecord (isStruct, fields, copyInfo) ->
            let smallExpression =
                onlyIf isStruct !- "struct "
                +> sepOpenAnonRecd
                +> optSingle (fun e -> genExpr astContext e +> !- " with ") copyInfo
                +> col sepSemi fields (genAnonRecordFieldName astContext)
                +> sepCloseAnonRecd

            let longExpression =
                ifAlignBrackets
                    (genMultilineAnonRecordAlignBrackets isStruct fields copyInfo astContext)
                    (genMultilineAnonRecord isStruct fields copyInfo astContext)

            fun (ctx: Context) ->
                let size = getRecordSize ctx fields
                isSmallExpression size smallExpression longExpression ctx

        | ObjExpr (t, eio, withKeyword, bd, members, ims, range) ->
            if List.isEmpty bd && List.isEmpty members then
                // Check the role of the second part of eio
                let param = opt sepNone (Option.map fst eio) (genExpr astContext)

                // See https://devblogs.microsoft.com/dotnet/announcing-f-5/#default-interface-member-consumption
                sepOpenS +> !- "new " +> genType astContext false t +> param +> sepCloseS
            else
                ifAlignBrackets
                    (genObjExprAlignBrackets t eio withKeyword bd members ims range astContext)
                    (genObjExpr t eio withKeyword bd members ims range astContext)

        | While (e1, e2) ->
            atCurrentColumn (
                !- "while "
                +> genExpr astContext e1
                +> !- " do"
                +> indent
                +> sepNln
                +> genExpr astContext e2
                +> unindent
            )

        | For (ident, equalsRange, e1, e2, e3, isUp) ->
            atCurrentColumn (
                !- "for "
                +> genIdent ident
                +> genEq SynExpr_For_Equals equalsRange
                +> sepSpace
                +> genExpr astContext e1
                +> ifElse isUp (!- " to ") (!- " downto ")
                +> genExpr astContext e2
                +> !- " do"
                +> indent
                +> sepNln
                +> genExpr astContext e3
                +> unindent
            )

        // Handle the form 'for i in e1 -> e2'
        | ForEach (p, e1, e2, isArrow) ->
            atCurrentColumn (
                !- "for "
                +> genPat astContext p
                +> !- " in "
                +> autoIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e1)
                +> ifElse
                    isArrow
                    (sepArrow +> autoIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e2))
                    (!- " do" +> indent +> sepNln +> genExpr astContext e2 +> unindent)
            )

        | NamedComputationExpr (nameExpr, openingBrace, bodyExpr, closingBrace, computationExprRange) ->
            fun ctx ->
                let short =
                    genExpr astContext nameExpr
                    +> sepSpace
                    +> (genTriviaFor SynExpr_ComputationExpr_OpeningBrace openingBrace sepOpenS
                        +> genExpr astContext bodyExpr
                        +> genTriviaFor SynExpr_ComputationExpr_ClosingBrace closingBrace sepCloseS
                        |> genTriviaFor SynExpr_ComputationExpr computationExprRange)

                let long =
                    genExpr astContext nameExpr
                    +> sepSpace
                    +> (genTriviaFor SynExpr_ComputationExpr_OpeningBrace openingBrace sepOpenS
                        +> indent
                        +> sepNln
                        +> genExpr astContext bodyExpr
                        +> unindent
                        +> sepNln
                        +> genTriviaFor SynExpr_ComputationExpr_ClosingBrace closingBrace sepCloseSFixed
                        |> genTriviaFor SynExpr_ComputationExpr computationExprRange)

                expressionFitsOnRestOfLine short long ctx
        | ComputationExpr (openingBrace, e, closingBrace) ->
            expressionFitsOnRestOfLine
                (genTriviaFor SynExpr_ComputationExpr_OpeningBrace openingBrace sepOpenS
                 +> genExpr astContext e
                 +> genTriviaFor SynExpr_ComputationExpr_ClosingBrace closingBrace sepCloseS)
                (genTriviaFor SynExpr_ComputationExpr_OpeningBrace openingBrace sepOpenS
                 +> genExpr astContext e
                 +> unindent
                 +> genTriviaFor
                     SynExpr_ComputationExpr_ClosingBrace
                     closingBrace
                     (sepNlnUnlessLastEventIsNewline +> sepCloseSFixed))

        | CompExprBody statements ->
            let genCompExprStatement astContext ces =
                match ces with
                | LetOrUseStatement (prefix, binding, inKeyword) ->
                    enterNodeFor (synBindingToFsAstType binding) binding.RangeOfBindingWithRhs
                    +> genLetBinding astContext prefix binding
                    +> genTriviaForOption SynExpr_LetOrUse_In inKeyword !- " in "
                | LetOrUseBangStatement (isUse, pat, equalsRange, expr, r) ->
                    enterNodeFor SynExpr_LetOrUseBang r // print Trivia before entire LetBang expression
                    +> ifElse isUse (!- "use! ") (!- "let! ")
                    +> genPat astContext pat
                    +> genEq SynExpr_LetOrUseBang_Equals equalsRange
                    +> sepSpace
                    +> autoIndentAndNlnIfExpressionExceedsPageWidthUnlessStroustrup (genExpr astContext) expr
                | AndBangStatement (pat, equalsRange, expr, range) ->
                    !- "and! "
                    +> genPat astContext pat
                    +> genEq SynExprAndBang_Equals (Some equalsRange)
                    +> sepSpace
                    +> autoIndentAndNlnIfExpressionExceedsPageWidthUnlessStroustrup (genExpr astContext) expr
                    |> genTriviaFor SynExprAndBang_ range
                | OtherStatement expr -> genExpr astContext expr

            let getRangeOfCompExprStatement ces =
                match ces with
                | LetOrUseStatement (_, binding, _) -> binding.RangeOfBindingWithRhs
                | LetOrUseBangStatement (range = r) -> r
                | AndBangStatement (range = r) -> r
                | OtherStatement expr -> expr.Range

            let getSepNln ces r =
                match ces with
                | LetOrUseStatement (_, b, _) -> sepNlnConsideringTriviaContentBeforeFor (synBindingToFsAstType b) r
                | LetOrUseBangStatement _ -> sepNlnConsideringTriviaContentBeforeFor SynExpr_LetOrUseBang r
                | AndBangStatement (_, _, _, r) -> sepNlnConsideringTriviaContentBeforeFor SynExprAndBang_ r
                | OtherStatement e ->
                    let t, r = synExprToFsAstType e
                    sepNlnConsideringTriviaContentBeforeFor t r

            statements
            |> List.map (fun ces ->
                let expr = genCompExprStatement astContext ces
                let r = getRangeOfCompExprStatement ces
                let sepNln = getSepNln ces r
                ColMultilineItem(expr, sepNln))
            |> colWithNlnWhenItemIsMultilineUsingConfig

        | JoinIn (e1, e2) -> genExpr astContext e1 +> !- " in " +> genExpr astContext e2
        | Paren (lpr, Lambda (pats, arrowRange, expr, lambdaRange), rpr, pr) ->
            fun (ctx: Context) ->
                let body = genExpr astContext

                let expr =
                    let triviaOfLambda f before (ctx: Context) =
                        (Map.tryFindOrEmptyList SynExpr_Lambda (if before then ctx.TriviaBefore else ctx.TriviaAfter)
                         |> List.filter (fun tn -> RangeHelpers.rangeEq tn.Range lambdaRange)
                         |> f)
                            ctx

                    sepOpenTFor lpr
                    +> triviaOfLambda printTriviaInstructions true
                    +> !- "fun "
                    +> col sepSpace pats (genPat astContext)
                    +> (fun ctx ->
                        if not ctx.Config.MultiLineLambdaClosingNewline then
                            genLambdaArrowWithTrivia
                                (fun e ->
                                    body e
                                    +> triviaOfLambda printTriviaInstructions false
                                    +> sepNlnWhenWriteBeforeNewlineNotEmpty id
                                    +> sepCloseTFor rpr)
                                expr
                                arrowRange
                                ctx
                        else
                            leadingExpressionIsMultiline
                                (genLambdaArrowWithTrivia
                                    (fun e ->
                                        body e
                                        +> triviaOfLambda printTriviaInstructions false
                                        +> sepNlnWhenWriteBeforeNewlineNotEmpty id)
                                    expr
                                    arrowRange)
                                (fun isMultiline -> onlyIf isMultiline sepNln +> sepCloseTFor rpr)
                                ctx)

                expr ctx

        // When there are parentheses, most likely lambda will appear in function application
        | Lambda (pats, arrowRange, expr, _range) ->
            atCurrentColumn (
                !- "fun "
                +> col sepSpace pats (genPat astContext)
                +> optSingle (fun arrowRange -> sepArrow |> genTriviaFor SynExpr_Lambda_Arrow arrowRange) arrowRange
                +> autoIndentAndNlnIfExpressionExceedsPageWidthUnlessStroustrup (genExpr astContext) expr
            )
        | MatchLambda (keywordRange, cs) ->
            (!- "function " |> genTriviaFor SynExpr_MatchLambda_Function keywordRange)
            +> sepNln
            +> genClauses astContext cs
        | Match (matchRange, e, withRange, cs) ->
            let genMatchExpr = genMatchWith astContext matchRange e withRange
            atCurrentColumn (genMatchExpr +> sepNln +> genClauses astContext cs)
        | MatchBang (matchRange, e, withRange, cs) ->
            let genMatchExpr = genMatchBangWith astContext matchRange e withRange
            atCurrentColumn (genMatchExpr +> sepNln +> genClauses astContext cs)
        | TraitCall (tps, msg, e) ->
            genTyparList astContext tps
            +> sepColon
            +> sepOpenT
            +> genMemberSig astContext msg
            +> sepCloseT
            +> sepSpace
            +> genExpr astContext e
        | Paren (_, ILEmbedded r, rpr, _) ->
            fun ctx ->
                let expr =
                    match ctx.FromSourceText r with
                    | None -> sepNone
                    | Some eil -> !-eil

                (expr +> optSingle (leaveNodeFor SynExpr_Paren_ClosingParenthesis) rpr) ctx
        | ParenFunctionNameWithStar (lpr, originalNotation, rpr) ->
            sepOpenTFor lpr +> !- $" {originalNotation} " +> sepCloseTFor (Some rpr)
        | Paren (lpr, e, rpr, _pr) ->
            match e with
            | LetOrUses _
            | Sequential _ -> sepOpenTFor lpr +> atCurrentColumn (genExpr astContext e) +> sepCloseTFor rpr
            | _ -> sepOpenTFor lpr +> genExpr astContext e +> sepCloseTFor rpr

        | DynamicExpr (func, arg) -> genExpr astContext func +> !- "?" +> genExpr astContext arg

        // Separate two prefix ops by spaces
        | PrefixApp (s1, PrefixApp (s2, e)) -> !-(sprintf "%s %s" s1 s2) +> genExpr astContext e
        | PrefixApp (s, App (e, [ Paren _ as p ]))
        | PrefixApp (s, App (e, [ ConstExpr (SynConst.Unit _, _) as p ])) ->
            !-s +> sepSpace +> genExpr astContext e +> genExpr astContext p
        | PrefixApp (s, e) ->
            let extraSpaceBeforeString =
                match e with
                | SynExpr.Const _
                | SynExpr.InterpolatedString _ -> sepSpace
                | _ -> sepNone

            !-s +> extraSpaceBeforeString +> genExpr astContext e

        | NewlineInfixApp (operatorText, operatorExpr, (Lambda _ as e1), e2)
        | NewlineInfixApp (operatorText, operatorExpr, (IfThenElse _ as e1), e2) ->
            genMultilineInfixExpr astContext e1 operatorText operatorExpr e2

        | NewlineInfixApps (e, es) ->
            let shortExpr =
                onlyIf (isSynExprLambdaOrIfThenElse e) sepOpenT
                +> genExpr astContext e
                +> onlyIf (isSynExprLambdaOrIfThenElse e) sepCloseT
                +> sepSpace
                +> col sepSpace es (fun (_s, oe, e) ->
                    genSynLongIdent false oe
                    +> sepSpace
                    +> onlyIf (isSynExprLambdaOrIfThenElse e) sepOpenT
                    +> genExpr astContext e
                    +> onlyIf (isSynExprLambdaOrIfThenElse e) sepCloseT)

            let multilineExpr =
                match es with
                | [] -> genExpr astContext e
                | (s, oe, e2) :: es ->
                    genMultilineInfixExpr astContext e s oe e2
                    +> sepNln
                    +> col sepNln es (fun (_s, oe, e) ->
                        genSynLongIdent false oe +> sepSpace +> genExprInMultilineInfixExpr astContext e)

            fun ctx ->
                atCurrentColumn (isShortExpression ctx.Config.MaxInfixOperatorExpression shortExpr multilineExpr) ctx

        | SameInfixApps (e, es) ->
            let shortExpr =
                onlyIf (isSynExprLambdaOrIfThenElse e) sepOpenT
                +> genExpr astContext e
                +> onlyIf (isSynExprLambdaOrIfThenElse e) sepCloseT
                +> sepSpace
                +> col sepSpace es (fun (_s, oe, e) ->
                    genSynLongIdent false oe
                    +> sepSpace
                    +> onlyIf (isSynExprLambdaOrIfThenElse e) sepOpenT
                    +> genExpr astContext e
                    +> onlyIf (isSynExprLambdaOrIfThenElse e) sepCloseT)

            let multilineExpr =
                genExpr astContext e
                +> sepNln
                +> col sepNln es (fun (_s, oe, e) ->
                    genSynLongIdent false oe +> sepSpace +> genExprInMultilineInfixExpr astContext e)

            fun ctx ->
                atCurrentColumn (isShortExpression ctx.Config.MaxInfixOperatorExpression shortExpr multilineExpr) ctx

        | InfixApp (operatorText, operatorSli, e1, e2, _) ->
            fun ctx ->
                isShortExpression
                    ctx.Config.MaxInfixOperatorExpression
                    (genOnelinerInfixExpr astContext e1 operatorSli e2)
                    (ifElse
                        (noBreakInfixOps.Contains(operatorText))
                        (genOnelinerInfixExpr astContext e1 operatorSli e2)
                        (genMultilineInfixExpr astContext e1 operatorText operatorSli e2))
                    ctx

        | TernaryApp (e1, e2, e3) ->
            atCurrentColumn (
                genExpr astContext e1
                +> !- "?"
                +> genExpr astContext e2
                +> sepSpace
                +> !- "<-"
                +> sepSpace
                +> genExpr astContext e3
            )

        | IndexWithoutDotExpr (identifierExpr, indexExpr) ->
            let genIndexExpr = genExpr astContext indexExpr

            genExpr astContext identifierExpr
            +> sepOpenLFixed
            +> expressionFitsOnRestOfLine genIndexExpr (atCurrentColumnIndent genIndexExpr)
            +> sepCloseLFixed

        // Result<int, string>.Ok 42
        | App (DotGet (TypeApp (e, lt, ts, gt), sli), es) ->
            genExpr astContext e
            +> genGenericTypeParameters astContext lt ts gt
            +> genSynLongIdent true sli
            +> sepSpaceOrIndentAndNlnIfExpressionExceedsPageWidth (col sepSpace es (genExpr astContext))

        // Foo(fun x -> x).Bar().Meh
        | DotGetAppDotGetAppParenLambda (e, px, appLids, es, lids) ->
            let short =
                genExpr astContext e
                +> genExpr astContext px
                +> genSynLongIdent true appLids
                +> col sepComma es (genExpr astContext)
                +> genSynLongIdent true lids

            let long =
                let functionName =
                    match e with
                    | LongIdentExprWithMoreThanOneIdent lids -> genFunctionNameWithMultilineLids id lids
                    | TypeApp (LongIdentExprWithMoreThanOneIdent lids, lt, ts, gt) ->
                        genFunctionNameWithMultilineLids (genGenericTypeParameters astContext lt ts gt) lids
                    | _ -> genExpr astContext e

                functionName
                +> indent
                +> genExpr astContext px
                +> sepNln
                +> genSynLongIdentMultiline true appLids
                +> col sepComma es (genExpr astContext)
                +> sepNln
                +> genSynLongIdentMultiline true lids
                +> unindent

            fun ctx -> isShortExpression ctx.Config.MaxDotGetExpressionWidth short long ctx

        // Foo().Bar
        | DotGetAppParen (e, px, lids) ->
            let shortAppExpr = genExpr astContext e +> genExpr astContext px

            let longAppExpr =
                let functionName argFn =
                    match e with
                    | LongIdentExprWithMoreThanOneIdent lids -> genFunctionNameWithMultilineLids argFn lids
                    | TypeApp (LongIdentExprWithMoreThanOneIdent lids, lt, ts, gt) ->
                        genFunctionNameWithMultilineLids (genGenericTypeParameters astContext lt ts gt +> argFn) lids
                    | DotGetAppDotGetAppParenLambda _ ->
                        leadingExpressionIsMultiline (genExpr astContext e) (fun isMultiline ->
                            if isMultiline then indent +> argFn +> unindent else argFn)
                    | _ -> genExpr astContext e +> argFn

                let arguments = genMultilineFunctionApplicationArguments astContext px

                functionName arguments

            let shortDotGetExpr = genSynLongIdent true lids

            let longDotGetExpr =
                indent +> sepNln +> genSynLongIdentMultiline true lids +> unindent

            fun ctx ->
                isShortExpression
                    ctx.Config.MaxDotGetExpressionWidth
                    (shortAppExpr +> shortDotGetExpr)
                    (longAppExpr +> longDotGetExpr)
                    ctx

        // Foo(fun x -> x).Bar()
        | DotGetApp (App (e, [ Paren (_, Lambda _, _, _) as px ]), es) ->
            let genLongFunctionName f =
                match e with
                | LongIdentExprWithMoreThanOneIdent lids -> genFunctionNameWithMultilineLids f lids
                | TypeApp (LongIdentExprWithMoreThanOneIdent lids, lt, ts, gt) ->
                    genFunctionNameWithMultilineLids (genGenericTypeParameters astContext lt ts gt +> f) lids
                | _ -> genExpr astContext e +> f

            let lastEsIndex = es.Length - 1

            let genApp (idx: int) (lids, e, t) : Context -> Context =
                let short =
                    genSynLongIdent true lids
                    +> optSingle (fun (lt, ts, gt) -> genGenericTypeParameters astContext lt ts gt) t
                    +> genSpaceBeforeLids idx lastEsIndex lids e
                    +> genExpr astContext e

                let long =
                    genSynLongIdentMultiline true lids
                    +> optSingle (fun (lt, ts, gt) -> genGenericTypeParameters astContext lt ts gt) t
                    +> genSpaceBeforeLids idx lastEsIndex lids e
                    +> genMultilineFunctionApplicationArguments astContext e

                expressionFitsOnRestOfLine short long

            let short =
                genExpr astContext e
                +> genExpr astContext px
                +> coli sepNone es (fun idx (lids, e, t) ->
                    genSynLongIdent true lids
                    +> optSingle (fun (lt, ts, gt) -> genGenericTypeParameters astContext lt ts gt) t
                    +> genSpaceBeforeLids idx lastEsIndex lids e
                    +> genExpr astContext e)

            let long =
                genLongFunctionName (genExpr astContext px)
                +> indent
                +> sepNln
                +> coli sepNln es genApp
                +> unindent

            fun ctx -> isShortExpression ctx.Config.MaxDotGetExpressionWidth short long ctx

        // Foo().Bar().Meh()
        | DotGetApp (e, es) ->
            let genLongFunctionName =
                match e with
                | AppOrTypeApp (LongIdentExprWithMoreThanOneIdent lids, t, [ Paren _ as px ]) ->
                    genFunctionNameWithMultilineLids
                        (optSingle (fun (lt, ts, gt) -> genGenericTypeParameters astContext lt ts gt) t
                         +> expressionFitsOnRestOfLine
                             (genExpr astContext px)
                             (genMultilineFunctionApplicationArguments astContext px))
                        lids
                | AppOrTypeApp (LongIdentExprWithMoreThanOneIdent lids, t, [ e2 ]) ->
                    genFunctionNameWithMultilineLids
                        (optSingle (fun (lt, ts, gt) -> genGenericTypeParameters astContext lt ts gt) t
                         +> genExpr astContext e2)
                        lids
                | AppOrTypeApp (SimpleExpr e, t, [ ConstExpr (SynConst.Unit, r) ]) ->
                    genExpr astContext e
                    +> optSingle (fun (lt, ts, gt) -> genGenericTypeParameters astContext lt ts gt) t
                    +> genTriviaFor SynExpr_Const r (genConst SynConst.Unit r)
                | AppOrTypeApp (SimpleExpr e, t, [ Paren _ as px ]) ->
                    let short =
                        genExpr astContext e
                        +> optSingle (fun (lt, ts, gt) -> genGenericTypeParameters astContext lt ts gt) t
                        +> genExpr astContext px

                    let long =
                        genExpr astContext e
                        +> optSingle (fun (lt, ts, gt) -> genGenericTypeParameters astContext lt ts gt) t
                        +> genMultilineFunctionApplicationArguments astContext px

                    expressionFitsOnRestOfLine short long
                | _ -> genExpr astContext e

            let lastEsIndex = es.Length - 1

            let genApp (idx: int) (lids, e, t) : Context -> Context =
                let short =
                    genSynLongIdent true lids
                    +> optSingle (fun (lt, ts, gt) -> genGenericTypeParameters astContext lt ts gt) t
                    +> genSpaceBeforeLids idx lastEsIndex lids e
                    +> genExpr astContext e

                let long =
                    genSynLongIdentMultiline true lids
                    +> optSingle (fun (lt, ts, gt) -> genGenericTypeParameters astContext lt ts gt) t
                    +> genSpaceBeforeLids idx lastEsIndex lids e
                    +> genMultilineFunctionApplicationArguments astContext e

                expressionFitsOnRestOfLine short long

            let short =
                match e with
                | App (e, [ px ]) when (hasParenthesis px || isArrayOrList px) ->
                    genExpr astContext e +> genExpr astContext px
                | _ -> genExpr astContext e
                +> coli sepNone es genApp

            let long =
                genLongFunctionName +> indent +> sepNln +> coli sepNln es genApp +> unindent

            fun ctx -> isShortExpression ctx.Config.MaxDotGetExpressionWidth short long ctx

        // (*) (60. * 1.1515 * 1.609344)
        // function is wrapped in parenthesis
        | AppParenArg (Choice1Of2 (Paren _, _, _, _, _, _) as app)
        | AppParenArg (Choice2Of2 (Paren _, _, _, _, _) as app) ->
            let short = genAppWithParenthesis app astContext

            let long = genAlternativeAppWithParenthesis app astContext

            expressionFitsOnRestOfLine short long

        // path.Replace("../../../", "....")
        | AppSingleParenArg (LongIdentExpr lids as functionOrMethod, px) ->
            let addSpace =
                onlyIfCtx (addSpaceBeforeParensInFunCall functionOrMethod px) sepSpace

            let shortLids = genSynLongIdent false lids

            let short = shortLids +> addSpace +> genExpr astContext px

            let long =
                let args =
                    addSpace
                    +> expressionFitsOnRestOfLine
                        (genExpr astContext px)
                        (genMultilineFunctionApplicationArguments astContext px)

                ifElseCtx (futureNlnCheck shortLids) (genFunctionNameWithMultilineLids args lids) (shortLids +> args)

            expressionFitsOnRestOfLine short long

        | AppSingleParenArg (e, px) ->
            let sepSpace (ctx: Context) =
                match e with
                | Paren _ -> sepSpace ctx
                | UppercaseSynExpr -> onlyIf ctx.Config.SpaceBeforeUppercaseInvocation sepSpace ctx
                | LowercaseSynExpr -> onlyIf ctx.Config.SpaceBeforeLowercaseInvocation sepSpace ctx

            let short = genExpr astContext e +> sepSpace +> genExpr astContext px

            let long =
                genExpr astContext e
                +> sepSpace
                +> genMultilineFunctionApplicationArguments astContext px

            expressionFitsOnRestOfLine short long

        | DotGetAppWithLambda ((e, es, lpr, lambda, rpr, pr), lids) ->
            leadingExpressionIsMultiline
                (genAppWithLambda astContext sepNone (e, es, lpr, lambda, rpr, pr))
                (fun isMultiline ->
                    if isMultiline then
                        (indent +> sepNln +> genSynLongIdent true lids +> unindent)
                    else
                        genSynLongIdent true lids)

        // functionName arg1 arg2 (fun x y z -> ...)
        | AppWithLambda (e, es, lpr, lambda, rpr, pr) ->
            let sepSpaceAfterFunctionName =
                let sepSpaceBasedOnSetting e =
                    match e with
                    | Paren _ -> sepSpace
                    | UppercaseSynExpr -> (fun ctx -> onlyIf ctx.Config.SpaceBeforeUppercaseInvocation sepSpace ctx)
                    | LowercaseSynExpr -> (fun ctx -> onlyIf ctx.Config.SpaceBeforeLowercaseInvocation sepSpace ctx)

                match es with
                | [] -> sepSpaceBasedOnSetting e
                | _ -> sepSpace

            genAppWithLambda astContext sepSpaceAfterFunctionName (e, es, lpr, lambda, rpr, pr)

        | NestedIndexWithoutDotExpr (identifierExpr, indexExpr, argExpr) ->
            genExpr astContext identifierExpr
            +> sepOpenLFixed
            +> genExpr astContext indexExpr
            +> sepCloseLFixed
            +> genExpr astContext argExpr
        | EndsWithDualListAppExpr ctx.Config.ExperimentalStroustrupStyle (e, es, props, children) ->
            // check if everything else beside the last array/list fits on one line
            let singleLineTestExpr =
                genExpr astContext e
                +> sepSpace
                +> col sepSpace es (genExpr astContext)
                +> sepSpace
                +> genExpr astContext props

            let short =
                genExpr astContext e
                +> sepSpace
                +> col sepSpace es (genExpr astContext)
                +> onlyIfNot es.IsEmpty sepSpace
                +> genExpr astContext props
                +> sepSpace
                +> genExpr astContext children

            let long =
                // check if everything besides both lists fits on one line
                let singleLineTestExpr =
                    genExpr astContext e +> sepSpace +> col sepSpace es (genExpr astContext)

                if futureNlnCheck singleLineTestExpr ctx then
                    genExpr astContext e
                    +> indent
                    +> sepNln
                    +> col sepNln es (genExpr astContext)
                    +> sepSpace
                    +> genExpr astContext props
                    +> sepSpace
                    +> genExpr astContext children
                    +> unindent
                else
                    genExpr astContext e
                    +> sepSpace
                    +> col sepSpace es (genExpr astContext)
                    +> genExpr astContext props
                    +> sepSpace
                    +> genExpr astContext children

            if futureNlnCheck singleLineTestExpr ctx then
                long
            else
                short

        | EndsWithSingleListAppExpr ctx.Config.ExperimentalStroustrupStyle (e, es, a) ->
            // check if everything else beside the last array/list fits on one line
            let singleLineTestExpr =
                genExpr astContext e +> sepSpace +> col sepSpace es (genExpr astContext)

            let short =
                genExpr astContext e
                +> sepSpace
                +> col sepSpace es (genExpr astContext)
                +> onlyIfNot es.IsEmpty sepSpace
                +> genExpr astContext a

            let long =
                genExpr astContext e
                +> indent
                +> sepNln
                +> col sepNln es (genExpr astContext)
                +> onlyIfNot es.IsEmpty sepNln
                +> genExpr astContext a
                +> unindent

            if futureNlnCheck singleLineTestExpr ctx then
                long
            else
                short

        // Always spacing in multiple arguments
        | App (e, es) -> genApp astContext e es
        | TypeApp (e, lt, ts, gt) -> genExpr astContext e +> genGenericTypeParameters astContext lt ts gt
        | LetOrUses (bs, e) ->
            let items =
                collectMultilineItemForLetOrUses astContext bs (collectMultilineItemForSynExpr astContext e)

            atCurrentColumn (colWithNlnWhenItemIsMultilineUsingConfig items)

        | TryWithSingleClause (tryKeyword, e, withKeyword, barRange, p, eo, arrowRange, catchExpr, clauseRange) ->
            let genClause =
                leadingExpressionResult
                    (enterNodeFor SynMatchClause_ clauseRange
                     +> genTriviaForOption SynMatchClause_Bar barRange sepNone)
                    (fun ((linesBefore, _), (linesAfter, _)) ->
                        onlyIfCtx (fun ctx -> linesAfter > linesBefore || hasWriteBeforeNewlineContent ctx) sepBar)
                +> genPatInClause astContext p
                +> optSingle
                    (fun e ->
                        !- " when"
                        +> sepSpaceOrIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e))
                    eo
                +> genTriviaForOption SynMatchClause_Arrow arrowRange sepArrow
                +> autoIndentAndNlnExpressUnlessStroustrup (genExpr astContext) catchExpr
                +> leaveNodeFor SynMatchClause_ clauseRange

            atCurrentColumn (
                genTriviaFor SynExpr_TryWith_Try tryKeyword !- "try"
                +> indent
                +> sepNln
                +> genExpr astContext e
                +> unindent
                +> sepNln
                +> genTriviaFor SynExpr_TryWith_With withKeyword (!- "with")
                +> sepSpace
                +> genClause
            )

        | TryWith (tryKeyword, e, withKeyword, cs) ->
            atCurrentColumn (
                genTriviaFor SynExpr_TryWith_Try tryKeyword !- "try"
                +> indent
                +> sepNln
                +> genExpr astContext e
                +> unindent
                +> sepNln // unless trivia?
                +> genTriviaFor SynExpr_TryWith_With withKeyword (!- "with")
                +> sepNln
                +> (fun ctx ->
                    let hasMultipleClausesWhereOneHasStroustrup =
                        hasMultipleClausesWhereOneHasStroustrup ctx.Config.ExperimentalStroustrupStyle cs

                    col sepNln cs (genClause astContext false hasMultipleClausesWhereOneHasStroustrup) ctx)
            )

        | TryFinally (tryKeyword, e1, finallyKeyword, e2) ->
            atCurrentColumn (
                genTriviaFor SynExpr_TryFinally_Try tryKeyword !- "try "
                +> indent
                +> sepNln
                +> genExpr astContext e1
                +> unindent
                +> genTriviaFor SynExpr_TryFinally_Finally finallyKeyword !+~ "finally"
                +> indent
                +> sepNln
                +> genExpr astContext e2
                +> unindent
            )

        | Sequentials es ->
            let items = List.collect (collectMultilineItemForSynExpr astContext) es
            atCurrentColumn (colWithNlnWhenItemIsMultilineUsingConfig items)

        // if condExpr then thenExpr
        | ElIf ([ None, ifKw, false, ifExpr, thenKw, thenExpr ], None, _) ->
            leadingExpressionResult
                (genIfThen astContext ifKw ifExpr thenKw)
                (fun ((lineCountBefore, columnBefore), (lineCountAfter, columnAfter)) ctx ->
                    // Check if the `if expr then` is already multiline or cross the max_line_length.
                    let isMultiline =
                        lineCountAfter > lineCountBefore || columnAfter > ctx.Config.MaxLineLength

                    if isMultiline then
                        indentSepNlnUnindent (genExpr astContext thenExpr) ctx
                    else
                        // Check if the entire expression is will still fit on one line, respecting MaxIfThenShortWidth
                        let remainingMaxLength =
                            ctx.Config.MaxIfThenShortWidth - (columnAfter - columnBefore)

                        isShortExpression
                            remainingMaxLength
                            (sepSpace +> genExpr astContext thenExpr)
                            (indentSepNlnUnindent (genExpr astContext thenExpr))
                            ctx)
            |> atCurrentColumnIndent

        // if condExpr then thenExpr else elseExpr
        | ElIf ([ None, ifKw, false, ifExpr, thenKw, thenExpr ], Some (elseKw, elseExpr), _) ->
            let genElse = genTriviaFor SynExpr_IfThenElse_Else elseKw !- "else"

            leadingExpressionResult
                (genIfThen astContext ifKw ifExpr thenKw)
                (fun ((lineCountBefore, columnBefore), (lineCountAfter, columnAfter)) ctx ->
                    let long =
                        indentSepNlnUnindent (genExpr astContext thenExpr)
                        +> sepNln
                        +> genElse
                        +> genKeepIdent elseKw elseExpr
                        +> sepNln
                        +> genExpr astContext elseExpr
                        +> unindent

                    // Check if the `if expr then` is already multiline or cross the max_line_length.
                    let isMultiline =
                        lineCountAfter > lineCountBefore || columnAfter > ctx.Config.MaxLineLength

                    // If the `thenExpr` is also an SynExpr.IfThenElse, it will not be valid code if put on one line.
                    // ex: if cond then if a then b else c else e2
                    let thenExprIsIfThenElse =
                        match thenExpr with
                        | IfThenElse _ -> true
                        | _ -> false

                    if isMultiline || thenExprIsIfThenElse then
                        long ctx
                    else
                        // Check if the entire expression is will still fit on one line, respecting MaxIfThenShortWidth
                        let remainingMaxLength =
                            ctx.Config.MaxIfThenElseShortWidth - (columnAfter - columnBefore)

                        isShortExpression
                            remainingMaxLength
                            (sepSpace
                             +> genExpr astContext thenExpr
                             +> sepSpace
                             +> genElse
                             +> sepSpace
                             +> genExpr astContext elseExpr)
                            long
                            ctx)
            |> atCurrentColumnIndent

        // At least one `elif` or `else if` is present
        // Optional else branch
        | ElIf (branches, elseInfo, _) ->
            // multiple branches but no else expr
            // use the same threshold check as for if-then
            // Everything should fit on one line
            let areAllShort ctx =
                let anyThenExprIsIfThenElse =
                    branches
                    |> List.exists (fun (_, _, _, _, _, thenExpr) ->
                        match thenExpr with
                        | IfThenElse _ -> true
                        | _ -> false)

                let checkIfLine (elseKwOpt, ifKw, isElif, condExpr, thenKw, thenExpr) =
                    genIfOrElseIfOrElifThen astContext elseKwOpt ifKw isElif condExpr thenKw
                    +> sepSpace
                    +> genExpr astContext thenExpr

                let linesToCheck =
                    match elseInfo with
                    | None -> List.map checkIfLine branches
                    | Some (elseKw, elseExpr) ->
                        // This may appear a bit odd that we are adding the `else elseExpr` before the `if expr then expr` lines but purely for this check this doesn't matter.
                        // Each lines needs to fit on one line in order for us to format the short way
                        (genTriviaFor SynExpr_IfThenElse_Else elseKw !- "else"
                         +> sepSpace
                         +> genExpr astContext elseExpr)
                        :: (List.map checkIfLine branches)

                let lineCheck () =
                    linesToCheck
                    |> List.forall (fun lineCheck ->
                        let maxWidth =
                            if elseInfo.IsSome then
                                ctx.Config.MaxIfThenElseShortWidth
                            else
                                ctx.Config.MaxIfThenShortWidth

                        not (exceedsWidth maxWidth lineCheck ctx))

                not anyThenExprIsIfThenElse && lineCheck ()

            let shortExpr =
                col sepNln branches (fun (elseKwOpt, ifKw, isElif, condExpr, thenKw, thenExpr) ->
                    genIfOrElseIfOrElifThen astContext elseKwOpt ifKw isElif condExpr thenKw
                    +> sepSpace
                    +> genExpr astContext thenExpr)
                +> optSingle
                    (fun (elseKw, elseExpr) ->
                        sepNln
                        +> genTriviaFor SynExpr_IfThenElse_Else elseKw !- "else"
                        +> sepSpace
                        +> genExpr astContext elseExpr)
                    elseInfo

            let longExpr =
                col sepNln branches (fun (elseKwOpt, ifKw, isElif, condExpr, thenKw, thenExpr) ->
                    genIfOrElseIfOrElifThen astContext elseKwOpt ifKw isElif condExpr thenKw
                    +> indentSepNlnUnindent (genExpr astContext thenExpr))
                +> optSingle
                    (fun (elseKw, elseExpr) ->
                        sepNln
                        +> genTriviaFor SynExpr_IfThenElse_Else elseKw !- "else"
                        +> genKeepIdent elseKw elseExpr
                        +> sepNln
                        +> genExpr astContext elseExpr
                        +> unindent)
                    elseInfo

            ifElseCtx areAllShort shortExpr longExpr |> atCurrentColumnIndent

        | IdentExpr ident -> genIdent ident

        // At this stage, all symbolic operators have been handled.
        | OptVar (isOpt, sli, _) -> ifElse isOpt (!- "?") sepNone +> genSynLongIdent false sli
        | LongIdentSet (sli, e, _) ->
            genSynLongIdent false sli
            +> !- " <- "
            +> autoIndentAndNlnIfExpressionExceedsPageWidthUnlessStroustrup (genExpr astContext) e
        | DotIndexedGet (App (e, [ ConstExpr (SynConst.Unit, _) as ux ]), indexArgs) ->
            genExpr astContext e
            +> genExpr astContext ux
            +> !- "."
            +> sepOpenLFixed
            +> genExpr astContext indexArgs
            +> sepCloseLFixed
        | DotIndexedGet (AppSingleParenArg (e, px), indexArgs) ->
            let short = genExpr astContext e +> genExpr astContext px

            let long =
                genExpr astContext e +> genMultilineFunctionApplicationArguments astContext px

            let idx = !- "." +> sepOpenLFixed +> genExpr astContext indexArgs +> sepCloseLFixed

            expressionFitsOnRestOfLine (short +> idx) (long +> idx)
        | DotIndexedGet (objectExpr, indexArgs) ->
            let isParen =
                match objectExpr with
                | Paren _ -> true
                | _ -> false

            ifElse isParen (genExpr astContext objectExpr) (addParenIfAutoNln objectExpr (genExpr astContext))
            +> !- "."
            +> sepOpenLFixed
            +> genExpr astContext indexArgs
            +> sepCloseLFixed
        | DotIndexedSet (App (e, [ ConstExpr (SynConst.Unit, _) as ux ]), indexArgs, valueExpr) ->
            let appExpr = genExpr astContext e +> genExpr astContext ux

            let idx =
                !- "."
                +> sepOpenLFixed
                +> genExpr astContext indexArgs
                +> sepCloseLFixed
                +> sepArrowRev

            expressionFitsOnRestOfLine
                (appExpr +> idx +> genExpr astContext valueExpr)
                (appExpr
                 +> idx
                 +> autoIndentAndNlnIfExpressionExceedsPageWidthUnlessStroustrup (genExpr astContext) valueExpr)
        | DotIndexedSet (AppSingleParenArg (a, px), indexArgs, valueExpr) ->
            let short = genExpr astContext a +> genExpr astContext px

            let long =
                genExpr astContext a +> genMultilineFunctionApplicationArguments astContext px

            let idx =
                !- "."
                +> sepOpenLFixed
                +> genExpr astContext indexArgs
                +> sepCloseLFixed
                +> sepArrowRev

            expressionFitsOnRestOfLine
                (short +> idx +> genExpr astContext valueExpr)
                (long
                 +> idx
                 +> autoIndentAndNlnIfExpressionExceedsPageWidthUnlessStroustrup (genExpr astContext) valueExpr)

        | DotIndexedSet (objectExpr, indexArgs, valueExpr) ->
            addParenIfAutoNln objectExpr (genExpr astContext)
            +> !- ".["
            +> genExpr astContext indexArgs
            +> !- "] <- "
            +> autoIndentAndNlnIfExpressionExceedsPageWidthUnlessStroustrup (genExpr astContext) valueExpr
        | NamedIndexedPropertySet (sli, e1, e2) ->
            let sep =
                match e1 with
                | SynExpr.Const _
                | SynExpr.Ident _ -> sepSpace
                | _ -> sepNone

            genSynLongIdent false sli
            +> sep
            +> genExpr astContext e1
            +> !- " <- "
            +> autoIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e2)
        | DotNamedIndexedPropertySet (e, sli, e1, e2) ->
            genExpr astContext e
            +> sepDot
            +> genSynLongIdent false sli
            +> genExpr astContext e1
            +> !- " <- "
            +> autoIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e2)

        // typeof<System.Collections.IEnumerable>.FullName
        | DotGet (e, sli) ->
            let shortExpr = genExpr astContext e +> genSynLongIdent true sli

            let longExpr =
                //genLongIdentWithMultipleFragmentsMultiline astContext e
                genExpr astContext e +> indentSepNlnUnindent (genSynLongIdentMultiline true sli)

            fun ctx -> isShortExpression ctx.Config.MaxDotGetExpressionWidth shortExpr longExpr ctx
        | DotSet (e1, sli, e2) ->
            addParenIfAutoNln e1 (genExpr astContext)
            +> sepDot
            +> genSynLongIdent false sli
            +> !- " <- "
            +> autoIndentAndNlnIfExpressionExceedsPageWidthUnlessStroustrup (genExpr astContext) e2

        | SynExpr.Set (e1, e2, _) ->
            addParenIfAutoNln e1 (genExpr astContext)
            +> !- " <- "
            +> autoIndentAndNlnIfExpressionExceedsPageWidthUnlessStroustrup (genExpr astContext) e2

        | ParsingError r ->
            raise
            <| FormatException
                $"Parsing error(s) between line %i{r.StartLine} column %i{r.StartColumn + 1} and line %i{r.EndLine} column %i{r.EndColumn + 1}"

        | LibraryOnlyStaticOptimization (optExpr, constraints, e) ->
            genExpr astContext optExpr
            +> genSynStaticOptimizationConstraint astContext constraints
            +> sepEq
            +> sepSpaceOrIndentAndNlnIfExpressionExceedsPageWidth (genExpr astContext e)

        | UnsupportedExpr r ->
            raise
            <| FormatException(
                sprintf
                    "Unsupported construct(s) between line %i column %i and line %i column %i"
                    r.StartLine
                    (r.StartColumn + 1)
                    r.EndLine
                    (r.EndColumn + 1)
            )
        | InterpolatedStringExpr (parts, _stringKind) ->
            let genInterpolatedFillExpr expr =
                fun ctx ->
                    let currentConfig = ctx.Config

                    let interpolatedConfig =
                        { currentConfig with
                            // override the max line length for the interpolated expression.
                            // this is to avoid scenarios where the long / multiline format of the expresion will be used
                            // where the construct is this short
                            // see unit test ``construct url with Fable``
                            MaxLineLength = ctx.WriterModel.Column + ctx.Config.MaxLineLength }

                    genExpr astContext expr { ctx with Config = interpolatedConfig }
                    // Restore the existing configuration after printing the interpolated expression
                    |> fun ctx -> { ctx with Config = currentConfig }
                |> atCurrentColumnIndent

            let withoutSourceText s ctx =
                match ctx.SourceText with
                | Some _ -> ctx
                | None -> !- s ctx

            withoutSourceText "$\""
            +> col sepNone parts (fun part ->
                match part with
                | SynInterpolatedStringPart.String (s, r) ->
                    fun ctx ->
                        let expr =
                            match ctx.FromSourceText r with
                            | None -> !-s
                            | Some s -> !-s

                        genTriviaFor SynInterpolatedStringPart_String r expr ctx
                | SynInterpolatedStringPart.FillExpr (expr, ident) ->
                    fun ctx ->
                        let genFill =
                            genInterpolatedFillExpr expr
                            +> optSingle (fun format -> sepColonFixed +> genIdent format) ident

                        if ctx.Config.StrictMode then
                            (!- "{" +> genFill +> !- "}") ctx
                        else
                            genFill ctx)
            +> withoutSourceText "\""

        | IndexRangeExpr (None, None) -> !- "*"
        | IndexRangeExpr (Some (IndexRangeExpr (Some (ConstNumberExpr e1), Some (ConstNumberExpr e2))),
                          Some (ConstNumberExpr e3)) ->
            let hasOmittedTrailingZero (fromSourceText: range -> string option) r =
                match fromSourceText r with
                | None -> false
                | Some sourceText -> sourceText.EndsWith(".")

            let dots (ctx: Context) =
                if
                    hasOmittedTrailingZero ctx.FromSourceText e1.Range
                    || hasOmittedTrailingZero ctx.FromSourceText e2.Range
                then
                    !- " .. " ctx
                else
                    !- ".." ctx

            genExpr astContext e1
            +> dots
            +> genExpr astContext e2
            +> dots
            +> genExpr astContext e3
        | IndexRangeExpr (e1, e2) ->
            let hasSpaces =
                let rec (|AtomicExpr|_|) e =
                    match e with
                    | NegativeNumber _ -> None
                    | SynExpr.Ident _
                    | SynExpr.Const (SynConst.Int32 _, _)
                    | IndexRangeExpr (Some (AtomicExpr _), Some (AtomicExpr _))
                    | IndexFromEndExpr (AtomicExpr _) -> Some e
                    | _ -> None

                match e1, e2 with
                | Some (AtomicExpr _), None
                | None, Some (AtomicExpr _)
                | Some (AtomicExpr _), Some (AtomicExpr _) -> false
                | _ -> true

            optSingle (fun e -> genExpr astContext e +> onlyIf hasSpaces sepSpace) e1
            +> !- ".."
            +> optSingle (fun e -> onlyIf hasSpaces sepSpace +> genExpr astContext e) e2
        | IndexFromEndExpr e -> !- "^" +> genExpr astContext e
        | e -> failwithf "Unexpected expression: %O" e
        |> (match synExpr with
            | SynExpr.App _ -> genTriviaFor SynExpr_App synExpr.Range
            | SynExpr.AnonRecd _ -> genTriviaFor SynExpr_AnonRecd synExpr.Range
            | SynExpr.Record _ -> genTriviaFor SynExpr_Record synExpr.Range
            | SynExpr.Ident _ -> genTriviaFor SynExpr_Ident synExpr.Range
            | SynExpr.IfThenElse _ -> genTriviaFor SynExpr_IfThenElse synExpr.Range
            | SynExpr.Lambda _ -> genTriviaFor SynExpr_Lambda synExpr.Range
            | SynExpr.ForEach _ -> genTriviaFor SynExpr_ForEach synExpr.Range
            | SynExpr.For _ -> genTriviaFor SynExpr_For synExpr.Range
            | SynExpr.Match _ -> genTriviaFor SynExpr_Match synExpr.Range
            | SynExpr.MatchBang _ -> genTriviaFor SynExpr_MatchBang synExpr.Range
            | SynExpr.YieldOrReturn _ -> genTriviaFor SynExpr_YieldOrReturn synExpr.Range
            | SynExpr.YieldOrReturnFrom _ -> genTriviaFor SynExpr_YieldOrReturnFrom synExpr.Range
            | SynExpr.TryFinally _ -> genTriviaFor SynExpr_TryFinally synExpr.Range
            | SynExpr.LongIdentSet _ -> genTriviaFor SynExpr_LongIdentSet synExpr.Range
            | SynExpr.ArrayOrList _ -> genTriviaFor SynExpr_ArrayOrList synExpr.Range
            | SynExpr.ArrayOrListComputed _ -> genTriviaFor SynExpr_ArrayOrList synExpr.Range
            | SynExpr.Paren _ -> genTriviaFor SynExpr_Paren synExpr.Range
            | SynExpr.InterpolatedString _ -> genTriviaFor SynExpr_InterpolatedString synExpr.Range
            | SynExpr.Tuple _ -> genTriviaFor SynExpr_Tuple synExpr.Range
            | SynExpr.DoBang _ -> genTriviaFor SynExpr_DoBang synExpr.Range
            | SynExpr.TryWith _ -> genTriviaFor SynExpr_TryWith synExpr.Range
            | SynExpr.New _ -> genTriviaFor SynExpr_New synExpr.Range
            | SynExpr.Assert _ -> genTriviaFor SynExpr_Assert synExpr.Range
            | SynExpr.While _ -> genTriviaFor SynExpr_While synExpr.Range
            | SynExpr.MatchLambda _ -> genTriviaFor SynExpr_MatchLambda synExpr.Range
            | SynExpr.LongIdent _ -> genTriviaFor SynExpr_LongIdent synExpr.Range
            | SynExpr.DotGet _ -> genTriviaFor SynExpr_DotGet synExpr.Range
            | SynExpr.Upcast _ -> genTriviaFor SynExpr_Upcast synExpr.Range
            | SynExpr.Downcast _ -> genTriviaFor SynExpr_Downcast synExpr.Range
            | SynExpr.DotIndexedGet _ -> genTriviaFor SynExpr_DotIndexedGet synExpr.Range
            | SynExpr.DotIndexedSet _ -> genTriviaFor SynExpr_DotIndexedSet synExpr.Range
            | SynExpr.ObjExpr _ -> genTriviaFor SynExpr_ObjExpr synExpr.Range
            | SynExpr.JoinIn _ -> genTriviaFor SynExpr_JoinIn synExpr.Range
            | SynExpr.Do _ -> genTriviaFor SynExpr_Do synExpr.Range
            | SynExpr.TypeApp _ -> genTriviaFor SynExpr_TypeApp synExpr.Range
            | SynExpr.Lazy _ -> genTriviaFor SynExpr_Lazy synExpr.Range
            | SynExpr.InferredUpcast _ -> genTriviaFor SynExpr_InferredUpcast synExpr.Range
            | SynExpr.InferredDowncast _ -> genTriviaFor SynExpr_InferredDowncast synExpr.Range
            | SynExpr.AddressOf _ -> genTriviaFor SynExpr_AddressOf synExpr.Range
            | SynExpr.Null _ -> genTriviaFor SynExpr_Null synExpr.Range
            | SynExpr.TraitCall _ -> genTriviaFor SynExpr_TraitCall synExpr.Range
            | SynExpr.DotNamedIndexedPropertySet _ -> genTriviaFor SynExpr_DotNamedIndexedPropertySet synExpr.Range
            | SynExpr.NamedIndexedPropertySet _ -> genTriviaFor SynExpr_NamedIndexedPropertySet synExpr.Range
            | SynExpr.Set _ -> genTriviaFor SynExpr_Set synExpr.Range
            | SynExpr.Quote _ -> genTriviaFor SynExpr_Quote synExpr.Range
            | SynExpr.ArbitraryAfterError _ -> genTriviaFor SynExpr_ArbitraryAfterError synExpr.Range
            | SynExpr.DiscardAfterMissingQualificationAfterDot _ ->
                genTriviaFor SynExpr_DiscardAfterMissingQualificationAfterDot synExpr.Range
            | SynExpr.DotSet _ -> genTriviaFor SynExpr_DotSet synExpr.Range
            | SynExpr.Fixed _ -> genTriviaFor SynExpr_Fixed synExpr.Range
            | SynExpr.FromParseError _ -> genTriviaFor SynExpr_FromParseError synExpr.Range
            | SynExpr.ImplicitZero _ -> genTriviaFor SynExpr_ImplicitZero synExpr.Range
            | SynExpr.LibraryOnlyStaticOptimization _ ->
                genTriviaFor SynExpr_LibraryOnlyStaticOptimization synExpr.Range
            | SynExpr.LibraryOnlyILAssembly _ -> genTriviaFor SynExpr_LibraryOnlyILAssembly synExpr.Range
            | SynExpr.LibraryOnlyUnionCaseFieldGet _ -> genTriviaFor SynExpr_LibraryOnlyUnionCaseFieldGet synExpr.Range
            | SynExpr.LibraryOnlyUnionCaseFieldSet _ -> genTriviaFor SynExpr_LibraryOnlyUnionCaseFieldSet synExpr.Range
            | SynExpr.SequentialOrImplicitYield _ -> genTriviaFor SynExpr_SequentialOrImplicitYield synExpr.Range
            | SynExpr.TypeTest _ -> genTriviaFor SynExpr_TypeTest synExpr.Range
            | SynExpr.IndexRange _ -> genTriviaFor SynExpr_IndexRange synExpr.Range
            | SynExpr.IndexFromEnd _ -> genTriviaFor SynExpr_IndexFromEnd synExpr.Range
            | SynExpr.Dynamic _ -> genTriviaFor SynExpr_Dynamic synExpr.Range
            | SynExpr.Const _ -> genTriviaFor SynExpr_Const synExpr.Range
            | SynExpr.LetOrUse _
            | SynExpr.Sequential _
            | SynExpr.ComputationExpr _ ->
                // first and last nested node has trivia attached to it
                id
            | SynExpr.LetOrUseBang _ ->
                // printed as part of CompBody
                id
            | SynExpr.Typed _ ->
                // child nodes contain trivia
                id
            | SynExpr.DebugPoint _ ->
                // I don't believe the parser will ever return this node
                id)

    expr ctx

and genOnelinerInfixExpr astContext e1 operatorSli e2 =
    let genExpr astContext e =
        match e with
        | Record _
        | AnonRecord _ -> atCurrentColumnIndent (genExpr astContext e)
        | _ -> genExpr astContext e

 
