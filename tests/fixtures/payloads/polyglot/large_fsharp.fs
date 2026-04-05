// Copyright (c) Microsoft Corporation.  All Rights Reserved.  See License.txt in the project root for license information.

namespace rec FSharp.Compiler.Symbols

open System
open System.Collections.Generic
open Internal.Utilities.Collections
open Internal.Utilities.Library
open FSharp.Compiler
open FSharp.Compiler.AbstractIL.IL
open FSharp.Compiler.AttributeChecking
open FSharp.Compiler.AccessibilityLogic
open FSharp.Compiler.CheckDeclarations
open FSharp.Compiler.CompilerImports
open FSharp.Compiler.Infos
open FSharp.Compiler.InfoReader
open FSharp.Compiler.NameResolution
open FSharp.Compiler.Syntax
open FSharp.Compiler.Syntax.PrettyNaming
open FSharp.Compiler.SyntaxTreeOps
open FSharp.Compiler.Text
open FSharp.Compiler.Text.Range
open FSharp.Compiler.Xml
open FSharp.Compiler.TcGlobals
open FSharp.Compiler.TypedTree
open FSharp.Compiler.TypedTreeBasics
open FSharp.Compiler.TypedTreeOps
open FSharp.Compiler.TypeHierarchy
open FSharp.Compiler.CheckExpressionsOps

type FSharpAccessibility(a:Accessibility, ?isProtected) = 
    let isProtected = defaultArg isProtected  false

    let isInternalCompPath x = 
        match x with 
        | CompPath(ILScopeRef.Local, _, []) -> true 
        | _ -> false

    let (|Public|Internal|Private|) (TAccess p) = 
        match p with 
        | [] -> Public 
        | _ when List.forall isInternalCompPath p -> Internal 
        | _ -> Private

    member _.IsPublic = not isProtected && (match a with TAccess [] -> true | _ -> false)

    member _.IsPrivate = not isProtected && (match a with Private -> true | _ -> false)

    member _.IsInternal = not isProtected && (match a with Internal -> true | _ -> false)

    member _.IsProtected = isProtected

    member internal _.Contents = a

    override _.ToString() = 
        let (TAccess paths) = a
        let mangledTextOfCompPath (CompPath(scoref, _, path)) = getNameOfScopeRef scoref + "/" + textOfPath (List.map fst path)  
        String.concat ";" (List.map mangledTextOfCompPath paths)

type SymbolEnv(g: TcGlobals, thisCcu: CcuThunk, thisCcuTyp: ModuleOrNamespaceType option, tcImports: TcImports, amap: Import.ImportMap, infoReader: InfoReader) = 

    let tcVal = LightweightTcValForUsingInBuildMethodCall g

    new(g: TcGlobals, thisCcu: CcuThunk, thisCcuTyp: ModuleOrNamespaceType option, tcImports: TcImports) =
        let amap = tcImports.GetImportMap()
        let infoReader = InfoReader(g, amap)
        SymbolEnv(g, thisCcu, thisCcuTyp, tcImports, amap, infoReader)

    member _.g = g
    member _.amap = amap
    member _.thisCcu = thisCcu
    member _.thisCcuTy = thisCcuTyp
    member _.infoReader = infoReader
    member _.tcImports = tcImports
    member _.tcValF = tcVal

[<AutoOpen>]
module Impl = 
    let protect f = 
       DiagnosticsLogger.protectAssemblyExplorationF  
         (fun (asmName, path) -> invalidOp (sprintf "The entity or value '%s' does not exist or is in an unresolved assembly. You may need to add a reference to assembly '%s'" path asmName))
         f

    let makeReadOnlyCollection (arr: seq<'T>) = 
        System.Collections.ObjectModel.ReadOnlyCollection<_>(Seq.toArray arr) :> IList<_>
        
    let makeXmlDoc (doc: XmlDoc) =
        FSharpXmlDoc.FromXmlText doc
    
    let makeElaboratedXmlDoc (doc: XmlDoc) =
        makeReadOnlyCollection (doc.GetElaboratedXmlLines())
    
    let rescopeEntity optViewedCcu (entity: Entity) = 
        match optViewedCcu with 
        | None -> mkLocalEntityRef entity
        | Some viewedCcu -> 
        match tryRescopeEntity viewedCcu entity with
        | ValueNone -> mkLocalEntityRef entity
        | ValueSome eref -> eref

    let entityIsUnresolved(entity:EntityRef) = 
        match entity with
        | ERefNonLocal(NonLocalEntityRef(ccu, _)) -> 
            ccu.IsUnresolvedReference && entity.TryDeref.IsNone
        | _ -> false

    let checkEntityIsResolved(entity:EntityRef) = 
        if entityIsUnresolved entity then 
            let poorQualifiedName =
                if entity.nlr.AssemblyName = "mscorlib" then 
                    entity.nlr.DisplayName + ", mscorlib"
                else 
                    entity.nlr.DisplayName + ", " + entity.nlr.Ccu.AssemblyName
            invalidOp (sprintf "The entity '%s' does not exist or is in an unresolved assembly." poorQualifiedName)

    /// Checking accessibility that arise from different compilations needs more care - this is a duplicate of the F# compiler code for this case
    let checkForCrossProjectAccessibility (ilg: ILGlobals) (thisCcu2:CcuThunk, ad2) (thisCcu1, taccess1) = 
        match ad2 with 
        | AccessibleFrom(cpaths2, _) ->
            let nameOfScoRef (thisCcu:CcuThunk) scoref = 
                match scoref with 
                | ILScopeRef.Local -> thisCcu.AssemblyName 
                | ILScopeRef.Assembly aref -> aref.Name 
                | ILScopeRef.Module mref -> mref.Name
                | ILScopeRef.PrimaryAssembly -> ilg.primaryAssemblyName
            let canAccessCompPathFromCrossProject (CompPath(scoref1, _, cpath1)) (CompPath(scoref2, _, cpath2)) =
                let rec loop p1 p2  = 
                    match p1, p2 with 
                    | (a1, k1) :: rest1, (a2, k2) :: rest2 -> (a1=a2) && (k1=k2) && loop rest1 rest2
                    | [], _ -> true 
                    | _ -> false // cpath1 is longer
                loop cpath1 cpath2 &&
                nameOfScoRef thisCcu1 scoref1 = nameOfScoRef thisCcu2 scoref2
            let canAccessFromCrossProject (TAccess x1) cpath2 = x1 |> List.forall (fun cpath1 -> canAccessCompPathFromCrossProject cpath1 cpath2)
            cpaths2 |> List.exists (canAccessFromCrossProject taccess1) 
        | _ -> true // otherwise use the normal check


    /// Convert an IL member accessibility into an F# accessibility
    let getApproxFSharpAccessibilityOfMember (declaringEntity: EntityRef) (ilAccess: ILMemberAccess) = 
        match ilAccess with 
        | ILMemberAccess.CompilerControlled
        | ILMemberAccess.FamilyAndAssembly 
        | ILMemberAccess.Assembly -> 
            taccessPrivate  (CompPath(declaringEntity.CompilationPath.ILScopeRef, SyntaxAccess.Unknown, []))

        | ILMemberAccess.Private ->
            taccessPrivate  declaringEntity.CompilationPath

        // This is an approximation - the thing may actually be nested in a private class, in which case it is not actually "public"
        | ILMemberAccess.Public
        // This is an approximation - the thing is actually "protected", but F# accessibilities can't express "protected", so we report it as "public"
        | ILMemberAccess.FamilyOrAssembly
        | ILMemberAccess.Family ->
            taccessPublic 

    /// Convert an IL type definition accessibility into an F# accessibility
    let getApproxFSharpAccessibilityOfEntity (entity: EntityRef) = 
        match metadataOfTycon entity.Deref with 
#if !NO_TYPEPROVIDERS
        | ProvidedTypeMetadata _info -> 
            // This is an approximation - for generative type providers some type definitions can be private.
            taccessPublic
#endif

        | ILTypeMetadata (TILObjectReprData(_, _, td)) -> 
            match td.Access with 
            | ILTypeDefAccess.Public 
            | ILTypeDefAccess.Nested ILMemberAccess.Public -> taccessPublic 
            | ILTypeDefAccess.Private  -> taccessPrivate  (CompPath(entity.CompilationPath.ILScopeRef, SyntaxAccess.Unknown, []))
            | ILTypeDefAccess.Nested nested -> getApproxFSharpAccessibilityOfMember entity nested

        | FSharpOrArrayOrByrefOrTupleOrExnTypeMetadata -> 
            entity.Accessibility

    let getLiteralValue = function
        | Some lv  ->
            match lv with
            | Const.Bool    v -> Some(box v)
            | Const.SByte   v -> Some(box v)
            | Const.Byte    v -> Some(box v)
            | Const.Int16   v -> Some(box v)
            | Const.UInt16  v -> Some(box v)
            | Const.Int32   v -> Some(box v)
            | Const.UInt32  v -> Some(box v)
            | Const.Int64   v -> Some(box v)
            | Const.UInt64  v -> Some(box v)
            | Const.IntPtr  v -> Some(box v)
            | Const.UIntPtr v -> Some(box v)
            | Const.Single  v -> Some(box v)
            | Const.Double  v -> Some(box v)
            | Const.Char    v -> Some(box v)
            | Const.String  v -> Some(box v)
            | Const.Decimal v -> Some(box v)
            | Const.Unit
            | Const.Zero      -> None
        | None -> None
            

    let getXmlDocSigForEntity (cenv: SymbolEnv) (ent:EntityRef)=
        match GetXmlDocSigOfEntityRef cenv.infoReader ent.Range ent with
        | Some (_, docsig) -> docsig
        | _ -> ""

type FSharpDisplayContext(denv: TcGlobals -> DisplayEnv) = 
    member _.Contents g = denv g

    static member Empty = FSharpDisplayContext DisplayEnv.Empty 

    member _.WithShortTypeNames shortNames =
         FSharpDisplayContext(fun g -> { denv g with shortTypeNames = shortNames })

    member _.WithPrefixGenericParameters () =
        FSharpDisplayContext(fun g -> { denv g with genericParameterStyle = GenericParameterStyle.Prefix }  )

    member _.WithSuffixGenericParameters () =
        FSharpDisplayContext(fun g -> { denv g with genericParameterStyle = GenericParameterStyle.Suffix }  )

    member x.WithTopLevelPrefixGenericParameters () =
        FSharpDisplayContext(fun g -> (denv g).UseTopLevelPrefixGenericParameterStyle())

// delay the realization of 'item' in case it is unresolved
type FSharpSymbol(cenv: SymbolEnv, item: unit -> Item, access: FSharpSymbol -> CcuThunk -> AccessorDomain -> bool) =

    member x.Assembly = 
        let ccu = defaultArg (SymbolHelpers.ccuOfItem cenv.g x.Item) cenv.thisCcu 
        FSharpAssembly(cenv, ccu)

    member x.IsAccessible(rights: FSharpAccessibilityRights) = access x rights.ThisCcu rights.Contents

    member x.IsExplicitlySuppressed = SymbolHelpers.IsExplicitlySuppressed cenv.g x.Item

    member x.FullName = SymbolHelpers.FullNameOfItem cenv.g x.Item 

    member x.DeclarationLocation = SymbolHelpers.rangeOfItem cenv.g None x.Item

    member x.ImplementationLocation = SymbolHelpers.rangeOfItem cenv.g (Some false) x.Item

    member x.SignatureLocation = SymbolHelpers.rangeOfItem cenv.g (Some true) x.Item

    member x.IsEffectivelySameAs(other:FSharpSymbol) = 
        x.Equals other || ItemsAreEffectivelyEqual cenv.g x.Item other.Item

    member x.GetEffectivelySameAsHash() = ItemsAreEffectivelyEqualHash cenv.g x.Item

    member internal _.SymbolEnv = cenv

    member internal _.Item = item()

    member _.DisplayNameCore = item().DisplayNameCore

    member _.DisplayName = item().DisplayName

    // This is actually overridden in all cases below. However some symbols are still just of type FSharpSymbol, 
    // see 'FSharpSymbol.Create' further below.
    override x.Equals(other: obj) =
        box x === other ||
        match other with
        |   :? FSharpSymbol as otherSymbol -> ItemsAreEffectivelyEqual cenv.g x.Item otherSymbol.Item
        |   _ -> false

    override x.GetHashCode() = hash x.ImplementationLocation  

    override x.ToString() = "symbol " + (try item().DisplayNameCore with _ -> "?")

    // TODO: there are several cases where we may need to report more interesting
    // symbol information below. By default we return a vanilla symbol.
    static member Create(g, thisCcu, thisCcuTyp, tcImports, item): FSharpSymbol = 
        FSharpSymbol.Create(SymbolEnv(g, thisCcu, Some thisCcuTyp, tcImports), item)

    static member Create(cenv, item): FSharpSymbol = 
        let dflt() = FSharpSymbol(cenv, (fun () -> item), (fun _ _ _ -> true)) 
        match item with
        | Item.Value v when v.Deref.IsClassConstructor ->
            FSharpMemberOrFunctionOrValue(cenv, C (FSMeth(cenv.g, generalizeTyconRef cenv.g v.DeclaringEntity |> snd, v, None)), item) :> _

        | Item.Value v -> FSharpMemberOrFunctionOrValue(cenv, V v, item) :> _
        | Item.UnionCase (uinfo, _) -> FSharpUnionCase(cenv, uinfo.UnionCaseRef) :> _
        | Item.ExnCase tcref -> FSharpEntity(cenv, tcref) :>_
        | Item.RecdField rfinfo -> FSharpField(cenv, RecdOrClass rfinfo.RecdFieldRef) :> _
        | Item.UnionCaseField (UnionCaseInfo (_, ucref), index) -> FSharpField (cenv, Union (ucref, index)) :> _

        | Item.ILField finfo -> FSharpField(cenv, ILField finfo) :> _

        | Item.AnonRecdField (anonInfo, tinst, n, m) -> FSharpField(cenv,  AnonField (anonInfo, tinst, n, m)) :> _
        
        | Item.Event einfo -> 
            FSharpMemberOrFunctionOrValue(cenv, E einfo, item) :> _
            
        | Item.Property(info = pinfo :: _) -> 
            FSharpMemberOrFunctionOrValue(cenv, P pinfo, item) :> _
            
        | Item.MethodGroup(_, minfo :: _, _) -> 
            FSharpMemberOrFunctionOrValue(cenv, M minfo, item) :> _

        | Item.CtorGroup(_, cinfo :: _) -> 
            FSharpMemberOrFunctionOrValue(cenv, C cinfo, item) :> _

        | Item.DelegateCtor (AbbrevOrAppTy(tcref, tyargs)) 
        | Item.Types(_, AbbrevOrAppTy(tcref, tyargs) :: _) -> 
            FSharpEntity(cenv, tcref, tyargs) :>_  

        | Item.UnqualifiedType(tcref :: _) ->
            FSharpEntity(cenv, tcref) :> _

        | Item.ModuleOrNamespaces(modref :: _) ->  
            FSharpEntity(cenv, modref) :> _

        | Item.SetterArg (_id, item) -> FSharpSymbol.Create(cenv, item)

        | Item.CustomOperation (_customOpName, _, Some minfo) -> 
            FSharpMemberOrFunctionOrValue(cenv, M minfo, item) :> _

        | Item.CustomBuilder (_, vref) -> 
            FSharpMemberOrFunctionOrValue(cenv, V vref, item) :> _

        | Item.TypeVar (_, tp) ->
             FSharpGenericParameter(cenv, tp) :> _

        | Item.Trait traitInfo ->
            FSharpGenericParameterMemberConstraint(cenv, traitInfo) :> _

        | Item.ActivePatternCase apref -> 
             FSharpActivePatternCase(cenv, apref.ActivePatternInfo, apref.ActivePatternVal.Type, apref.CaseIndex, Some apref.ActivePatternVal, item) :> _

        | Item.ActivePatternResult (apinfo, ty, n, _) ->
             FSharpActivePatternCase(cenv, apinfo, ty, n, None, item) :> _

        | Item.OtherName(id, ty, _, argOwner, m) ->
            FSharpParameter(cenv, id, ty, argOwner, m) :> _

        | Item.ImplicitOp(_, { contents = Some(TraitConstraintSln.FSMethSln(vref=vref)) }) ->
            FSharpMemberOrFunctionOrValue(cenv, V vref, item) :> _

        // TODO: the following don't currently return any interesting subtype
        | Item.ImplicitOp _
        | Item.ILField _ 
        | Item.NewDef _ -> dflt()
        // These cases cover unreachable cases
        | Item.CustomOperation (_, _, None) 
        | Item.UnqualifiedType []
        | Item.ModuleOrNamespaces []
        | Item.Property (info = [])
        | Item.MethodGroup (_, [], _)
        | Item.CtorGroup (_, [])
        // These cases cover misc. corned cases (non-symbol types)
        | Item.Types _
        | Item.DelegateCtor _  -> dflt()

    abstract Accessibility: FSharpAccessibility
    default _.Accessibility = FSharpAccessibility(taccessPublic)
        
    abstract Attributes: IList<FSharpAttribute>
    default _.Attributes = makeReadOnlyCollection []

    member sym.HasAttribute<'T> () =
        sym.Attributes |> Seq.exists (fun attr -> attr.IsAttribute<'T>())

    member sym.TryGetAttribute<'T>() =
        sym.Attributes |> Seq.tryFind (fun attr -> attr.IsAttribute<'T>())

type FSharpEntity(cenv: SymbolEnv, entity: EntityRef, tyargs: TType list) = 
    inherit FSharpSymbol(cenv, 
                         (fun () -> 
                              checkEntityIsResolved entity
                              if entity.IsModuleOrNamespace then Item.ModuleOrNamespaces [entity]
                              elif entity.IsFSharpException then Item.ExnCase entity
                              else Item.UnqualifiedType [entity]), 
                         (fun _this thisCcu2 ad -> 
                             checkForCrossProjectAccessibility cenv.g.ilg (thisCcu2, ad) (cenv.thisCcu, getApproxFSharpAccessibilityOfEntity entity)) 
                             // && AccessibilityLogic.IsEntityAccessible cenv.amap range0 ad entity)
                             )

    // If an entity is in an assembly not available to us in the resolution set, 
    // we generally return "false" from predicates like IsClass, since we know
    // nothing about that type.
    let isResolvedAndFSharp() = 
        match entity with
        | ERefNonLocal(NonLocalEntityRef(ccu, _)) -> not ccu.IsUnresolvedReference && ccu.IsFSharp
        | _ -> cenv.thisCcu.IsFSharp

    let isUnresolved() = entityIsUnresolved entity
    let isResolved() = not (isUnresolved())
    let checkIsResolved() = checkEntityIsResolved entity

    let isDefinedInFSharpCore() =
        match ccuOfTyconRef entity with
        | None -> false
        | Some ccu -> ccuEq ccu cenv.g.fslibCcu

    new(cenv: SymbolEnv, tcref: TyconRef) =
        let _, _, tyargs = FreshenTypeInst cenv.g range0 (tcref.Typars range0)
        FSharpEntity(cenv, tcref, tyargs)

    member _.Entity = entity
        
    member _.LogicalName = 
        checkIsResolved()
        entity.LogicalName 

    member _.CompiledName = 
        checkIsResolved()
        entity.CompiledName 

    member _.DisplayNameCore = 
        checkIsResolved()
        entity.DisplayNameCore

    member _.DisplayName = 
        checkIsResolved()
        entity.DisplayName

    member _.AccessPath  = 
        checkIsResolved()
        match entity.CompilationPathOpt with 
        | None -> "global" 
        | Some (CompPath(_, _, [])) -> "global" 
        | Some cp -> buildAccessPath (Some cp)
    
    member x.DeclaringEntity = 
        match entity.CompilationPathOpt with 
        | None -> None
        | Some (CompPath(_, _, [])) -> None
        | Some cp -> 
            match x.Assembly.Contents.FindEntityByPath cp.MangledPath with
            | Some res -> Some res
            | None -> 
            // The declaring entity may be in this assembly, including a type possibly hidden by a signature.
            match cenv.thisCcuTy with 
            | Some t -> 
                let s = FSharpAssemblySignature(cenv, None, None, t)
                s.FindEntityByPath cp.MangledPath 
            | None -> None

    member _.Namespace  = 
        checkIsResolved()
        match entity.CompilationPathOpt with 
        | None -> None
        | Some (CompPath(_, _, [])) -> None
        | Some cp when cp.AccessPath |> List.forall (function _, ModuleOrNamespaceKind.Namespace _ -> true | _  -> false) -> 
            Some (buildAccessPath (Some cp))
        | Some _ -> None

    member x.CompiledRepresentation =
        if isUnresolved () then None else

#if !NO_TYPEPROVIDERS
        if entity.IsTypeAbbrev || entity.IsProvidedErasedTycon || entity.IsNamespace then None else
#else
        if entity.IsTypeAbbrev || entity.IsNamespace then None else
#endif
        match entity.CompiledRepresentation with
        | CompiledTypeRepr.ILAsmNamed(tref, _, _) -> Some tref
        | CompiledTypeRepr.ILAsmOpen _ -> None

    member x.QualifiedName =
         x.CompiledRepresentation |> Option.map _.QualifiedName

    member x.BasicQualifiedName =
        x.CompiledRepresentation |> Option.map _.BasicQualifiedName

    member x.FullName = 
        checkIsResolved()
        match x.TryFullName with 
        | None -> invalidOp (sprintf "the type '%s' does not have a qualified name" x.LogicalName)
        | Some nm -> nm
    
    member _.TryFullName = 
        if isUnresolved() then None
#if !NO_TYPEPROVIDERS
        elif entity.IsTypeAbbrev || entity.IsProvidedErasedTycon then None
        #else
        elif entity.IsTypeAbbrev then None
#endif
        elif entity.IsNamespace  then Some entity.DemangledModuleOrNamespaceName
        else
            match entity.CompiledRepresentation with 
            | CompiledTypeRepr.ILAsmNamed(tref, _, _) -> Some tref.FullName
            | CompiledTypeRepr.ILAsmOpen _ -> None   

    member _.DeclarationLocation = 
        checkIsResolved()
        entity.Range

    member _.GenericParameters = 
        checkIsResolved()
        entity.TyparsNoRange |> List.map (fun tp -> FSharpGenericParameter(cenv, tp)) |> makeReadOnlyCollection

    member _.GenericArguments =
        checkIsResolved()
        tyargs |> List.map (fun ty -> FSharpType(cenv, ty)) |> makeReadOnlyCollection

    member _.IsMeasure = 
        isResolvedAndFSharp() && (entity.TypeOrMeasureKind = TyparKind.Measure)

    member _.IsAbstractClass = 
        isResolved() && isAbstractTycon entity.Deref

    member _.IsFSharpModule = 
        isResolvedAndFSharp() && entity.IsModule

    member _.HasFSharpModuleSuffix = 
        isResolvedAndFSharp() && 
        entity.IsModule && 
        (entity.ModuleOrNamespaceType.ModuleOrNamespaceKind = ModuleOrNamespaceKind.FSharpModuleWithSuffix)

    member _.IsValueType  = 
        isResolved() &&
        entity.IsStructOrEnumTycon 

    member _.IsArrayType  = 
        isResolved() &&
        isArrayTyconRef cenv.g entity

    member _.ArrayRank  = 
        checkIsResolved()
        if isArrayTyconRef cenv.g entity then
            rankOfArrayTyconRef cenv.g entity
        else
            0

#if !NO_TYPEPROVIDERS
    member _.IsProvided  = 
        isResolved() &&
        entity.IsProvided

    member _.IsProvidedAndErased  = 
        isResolved() &&
        entity.IsProvidedErasedTycon

    member _.IsStaticInstantiation  = 
        isResolved() &&
        entity.IsStaticInstantiationTycon

    member _.IsProvidedAndGenerated  = 
        isResolved() &&
        entity.IsProvidedGeneratedTycon
#endif
    member _.IsClass = 
        isResolved() &&
        match metadataOfTycon entity.Deref with
#if !NO_TYPEPROVIDERS 
        | ProvidedTypeMetadata info -> info.IsClass
#endif
        | ILTypeMetadata (TILObjectReprData(_, _, td)) -> td.IsClass
        | FSharpOrArrayOrByrefOrTupleOrExnTypeMetadata -> entity.Deref.IsFSharpClassTycon

    member _.IsByRef = 
        isResolved() &&
        isByrefTyconRef cenv.g entity

    member _.IsOpaque = 
        isResolved() &&
        entity.IsHiddenReprTycon

    member _.IsInterface = 
        isResolved() &&
        isInterfaceTyconRef entity

    member _.IsDelegate = 
        isResolved() &&
        match metadataOfTycon entity.Deref with 
#if !NO_TYPEPROVIDERS
        | ProvidedTypeMetadata info -> info.IsDelegate ()
#endif
        | ILTypeMetadata (TILObjectReprData(_, _, td)) -> td.IsDelegate
        | FSharpOrArrayOrByrefOrTupleOrExnTypeMetadata -> entity.IsFSharpDelegateTycon

    member _.IsEnum = 
        isResolved() &&
        entity.IsEnumTycon
    
    member _.IsFSharpExceptionDeclaration = 
        isResolvedAndFSharp() && entity.IsFSharpException

    member _.IsUnresolved = 
        isUnresolved()

    member _.IsFSharp = 
        isResolvedAndFSharp()

    member _.IsFSharpAbbreviation = 
        isResolvedAndFSharp() && entity.IsTypeAbbrev 

    member _.IsFSharpRecord = 
        isResolvedAndFSharp() && entity.IsRecordTycon

    member _.IsFSharpUnion = 
        isResolvedAndFSharp() && entity.IsUnionTycon

    member _.HasAssemblyCodeRepresentation = 
        isResolvedAndFSharp() && (entity.IsAsmReprTycon || entity.IsMeasureableReprTycon)

    member _.FSharpDelegateSignature =
        checkIsResolved()
        match entity.TypeReprInfo with 
        | TFSharpTyconRepr r when entity.IsFSharpDelegateTycon -> 
            match r.fsobjmodel_kind with 
            | TFSharpDelegate ss -> FSharpDelegateSignature(cenv, ss)
            | _ -> invalidOp "not a delegate type"
        | _ -> invalidOp "not a delegate type"

    override _.Accessibility = 
        if isUnresolved() then FSharpAccessibility taccessPublic else
        FSharpAccessibility(getApproxFSharpAccessibilityOfEntity entity) 

    member _.RepresentationAccessibility = 
        if isUnresolved() then FSharpAccessibility taccessPublic else
        FSharpAccessibility(entity.TypeReprAccessibility)

    member _.DeclaredInterfaces = 
        if isUnresolved() then makeReadOnlyCollection [] else
        let ty = generalizedTyconRef cenv.g entity
        DiagnosticsLogger.protectAssemblyExploration [] (fun () -> 
            [ for intfTy in GetImmediateInterfacesOfType SkipUnrefInterfaces.Yes cenv.g cenv.amap range0 ty do 
                 yield FSharpType(cenv, intfTy) ])
        |> makeReadOnlyCollection

    member _.AllInterfaces = 
        if isUnresolved() then makeReadOnlyCollection [] else
        let ty = generalizedTyconRef cenv.g entity
        DiagnosticsLogger.protectAssemblyExploration [] (fun () -> 
            [ for ity in AllInterfacesOfType  cenv.g cenv.amap range0 AllowMultiIntfInstantiations.Yes ty do 
                 yield FSharpType(cenv, ity) ])
        |> makeReadOnlyCollection
    
    member _.IsAttributeType =
        if isUnresolved() then false else
        let ty = generalizedTyconRef cenv.g entity
        DiagnosticsLogger.protectAssemblyExploration false <| fun () -> 
        ExistsHeadTypeInEntireHierarchy cenv.g cenv.amap range0 ty cenv.g.tcref_System_Attribute
        
    member _.IsDisposableType =
        if isUnresolved() then false else
        let ty = generalizedTyconRef cenv.g entity
        DiagnosticsLogger.protectAssemblyExploration false <| fun () -> 
        ExistsHeadTypeInEntireHierarchy cenv.g cenv.amap range0 ty cenv.g.tcref_System_IDisposable

    member _.BaseType = 
        checkIsResolved()        
        let ty = generalizedTyconRef cenv.g entity
        GetSuperTypeOfType cenv.g cenv.amap range0 ty
        |> Option.map (fun ty -> FSharpType(cenv, ty)) 
        
    member _.UsesPrefixDisplay = 
        if isUnresolved() then true else
        not (isResolvedAndFSharp()) || entity.Deref.IsPrefixDisplay

    member _.IsNamespace =  entity.IsNamespace

    member x.MembersFunctionsAndValues = 
      if isUnresolved() then makeReadOnlyCollection [] else
      protect <| fun () -> 
        ([ let entityTy = generalizedTyconRef cenv.g entity
           let createMember (minfo: MethInfo) =
               if minfo.IsConstructor || minfo.IsClassConstructor then
                   FSharpMemberOrFunctionOrValue(cenv, C minfo, Item.CtorGroup (minfo.DisplayName, [minfo]))
               else
                   FSharpMemberOrFunctionOrValue(cenv, M minfo, Item.MethodGroup (minfo.DisplayName, [minfo], None))
           if x.IsFSharpAbbreviation then 
               ()
           elif x.IsFSharp then 
               // For F# code we emit methods members in declaration order
               for v in entity.MembersOfFSharpTyconSorted do 
                 // Ignore members representing the generated .cctor
                 if not v.Deref.IsClassConstructor then 
                     yield createMember (FSMeth(cenv.g, entityTy, v, None))
           else
               for minfo in GetImmediateIntrinsicMethInfosOfType (None, AccessibleFromSomeFSharpCode) cenv.g cenv.amap range0 entityTy do
                    yield createMember minfo

           let props = GetImmediateIntrinsicPropInfosOfType (None, AccessibleFromSomeFSharpCode) cenv.g cenv.amap range0 entityTy
           let events = cenv.infoReader.GetImmediateIntrinsicEventsOfType (None, AccessibleFromSomeFSharpCode, range0, entityTy)

           for pinfo in props do
                yield FSharpMemberOrFunctionOrValue(cenv, P pinfo, Item.Property (pinfo.PropertyName, [pinfo], None))

           for einfo in events do
                yield FSharpMemberOrFunctionOrValue(cenv, E einfo, Item.Event einfo)

           // Emit the values, functions and F#-declared extension members in a module
           for v in entity.ModuleOrNamespaceType.AllValsAndMembers do
               if v.IsExtensionMember then

                   // For F#-declared extension members, yield a value-backed member and a property info if possible
                   let vref = mkNestedValRef entity v
                   yield FSharpMemberOrFunctionOrValue(cenv, V vref, Item.Value vref) 
                   match v.MemberInfo.Value.MemberFlags.MemberKind, v.ApparentEnclosingEntity with
                   | SynMemberKind.PropertyGet, Parent tcref -> 
                        let pinfo = FSProp(cenv.g, generalizedTyconRef cenv.g tcref, Some vref, None)
                        yield FSharpMemberOrFunctionOrValue(cenv, P pinfo, Item.Property (pinfo.PropertyName, [pinfo], None))
                   | SynMemberKind.PropertySet, Parent p -> 
                        let pinfo = FSProp(cenv.g, generalizedTyconRef cenv.g p, None, Some vref)
                        yield FSharpMemberOrFunctionOrValue(cenv, P pinfo, Item.Property (pinfo.PropertyName, [pinfo], None))
                   | _ -> ()

               elif not v.IsMember then
                   let vref = mkNestedValRef entity v
                   yield FSharpMemberOrFunctionOrValue(cenv, V vref, Item.Value vref) ]  
         |> makeReadOnlyCollection)
 
    member _.XmlDocSig = 
        checkIsResolved()
        getXmlDocSigForEntity cenv entity
 
    member _.XmlDoc = 
        if isUnresolved() then XmlDoc.Empty  |> makeXmlDoc else
        entity.XmlDoc |> makeXmlDoc

    member _.ElaboratedXmlDoc = 
        if isUnresolved() then XmlDoc.Empty  |> makeElaboratedXmlDoc else
        entity.XmlDoc |> makeElaboratedXmlDoc

    member x.StaticParameters = 
        match entity.TypeReprInfo with 
#if !NO_TYPEPROVIDERS
        | TProvidedTypeRepr info -> 
            let m = x.DeclarationLocation
            let typeBeforeArguments = info.ProvidedType 
            let staticParameters = typeBeforeArguments.PApplyWithProvider((fun (typeBeforeArguments, provider) -> typeBeforeArguments.GetStaticParameters provider), range=m) 
            let staticParameters = staticParameters.PApplyArray(id, "GetStaticParameters", m)
            [| for p in staticParameters -> FSharpStaticParameter(cenv, p, m) |]
#endif
        | _ -> [| |]
      |> makeReadOnlyCollection

    member _.NestedEntities = 
        if isUnresolved() then makeReadOnlyCollection [] else
        entity.ModuleOrNamespaceType.AllEntities 
        |> QueueList.toList
        |> List.map (fun x -> FSharpEntity(cenv, entity.NestedTyconRef x, tyargs))
        |> makeReadOnlyCollection

    member _.UnionCases = 
        if isUnresolved() then makeReadOnlyCollection [] else
        entity.UnionCasesAsRefList
        |> List.map (fun x -> FSharpUnionCase(cenv, x)) 
        |> makeReadOnlyCollection

    member _.FSharpFields =
        if isUnresolved() then makeReadOnlyCollection [] else
    
        if entity.IsILEnumTycon then
            let (TILObjectReprData(_scoref, _enc, tdef)) = entity.ILTyconInfo
            let formalTypars = entity.Typars range0
            let formalTypeInst = generalizeTypars formalTypars
            let ty = TType_app(entity, formalTypeInst, cenv.g.knownWithoutNull)
            let formalTypeInfo = ILTypeInfo.FromType cenv.g ty
            tdef.Fields.AsList()
            |> List.map (fun tdef ->
                let ilFieldInfo = ILFieldInfo(formalTypeInfo, tdef)
                FSharpField(cenv, FSharpFieldData.ILField ilFieldInfo ))
            |> makeReadOnlyCollection

        else
            entity.AllFieldsAsList
            |> List.map (fun x -> FSharpField(cenv, mkRecdFieldRef entity x.LogicalName))
            |> makeReadOnlyCollection

    member _.AbbreviatedType   = 
        checkIsResolved()

        match entity.TypeAbbrev with
        | None -> invalidOp "not a type abbreviation"
        | Some ty -> FSharpType(cenv, ty)

    member _.AsType() =
        let ty = generalizedTyconRef cenv.g entity
        FSharpType(cenv, ty)

    override _.Attributes = 
        if isUnresolved() then makeReadOnlyCollection [] else
        GetAttribInfosOfEntity cenv.g cenv.amap range0 entity
        |> List.map (fun a -> FSharpAttribute(cenv, a))
        |> makeReadOnlyCollection

    member _.AllCompilationPaths =
        checkIsResolved()
        let (CompPath(_, _, parts)) = entity.CompilationPath
        let partsList =
            [ yield parts
              match parts with
              | ("Microsoft", ModuleOrNamespaceKind.Namespace _) :: rest when isDefinedInFSharpCore() -> yield rest
              | _ -> ()]

        let mapEachCurrentPath (paths: string list list) path =
            match paths with
            | [] -> [[path]]
            | _ -> paths |> List.map (fun x -> path :: x)

        let walkParts (parts: (string * ModuleOrNamespaceKind) list) =
            let rec loop (currentPaths: string list list) parts =
                match parts with
                | [] -> currentPaths
                | (name: string, kind) :: rest ->
                    match kind with
                    | ModuleOrNamespaceKind.FSharpModuleWithSuffix ->
                        [ yield! loop (mapEachCurrentPath currentPaths name) rest
                          yield! loop (mapEachCurrentPath currentPaths name[..name.Length - 7]) rest ]
                    | _ -> 
                       loop (mapEachCurrentPath currentPaths name) rest
            loop [] parts |> List.map (List.rev >> String.concat ".")
            
        let res =
            [ for parts in partsList do
                yield! walkParts parts ]
        res

    member x.ActivePatternCases =
        protect <| fun () -> 
            ActivePatternElemsOfModuleOrNamespace cenv.g x.Entity
            |> Map.toList
            |> List.map (fun (_, apref) ->
                let item = Item.ActivePatternCase apref
                FSharpActivePatternCase(cenv, apref.ActivePatternInfo, apref.ActivePatternVal.Type, apref.CaseIndex, Some apref.ActivePatternVal, item))

    member x.TryGetFullName() =
        try x.TryFullName 
        with _ -> 
            try Some(String.Join(".", x.AccessPath, x.DisplayName))
            with _ -> None

    member x.TryGetFullDisplayName() =
        let fullName = x.TryGetFullName() |> Option.map (fun fullName -> fullName.Split '.')
        let res = 
            match fullName with
            | Some fullName ->
                match Option.attempt (fun _ -> x.DisplayName) with
                | Some shortDisplayName when not (shortDisplayName.Contains ".") ->
                    Some (fullName |> Array.replace (fullName.Length - 1) shortDisplayName)
                | _ -> Some fullName
            | None -> None 
            |> Option.map (fun fullDisplayName -> String.Join (".", fullDisplayName))
        //debug "GetFullDisplayName: FullName = %A, Result = %A" fullName res
        res

    member x.TryGetFullCompiledName() =
        let fullName = x.TryGetFullName() |> Option.map (fun fullName -> fullName.Split '.')
        let res = 
            match fullName with
            | Some fullName ->
                match Option.attempt (fun _ -> x.CompiledName) with
                | Some shortCompiledName when not (shortCompiledName.Contains ".") ->
                    Some (fullName |> Array.replace (fullName.Length - 1) shortCompiledName)
                | _ -> Some fullName
            | None -> None 
            |> Option.map (fun fullDisplayName -> String.Join (".", fullDisplayName))
        //debug "GetFullCompiledName: FullName = %A, Result = %A" fullName res
        res

    member x.GetPublicNestedEntities() =
        x.NestedEntities |> Seq.filter (fun entity -> entity.Accessibility.IsPublic)

    member x.TryGetMembersFunctionsAndValues() = 
        try x.MembersFunctionsAndValues with _ -> [||] :> _

    member this.TryGetMetadataText() =
        match entity.TryDeref with
        | ValueSome _ ->
            if entity.IsNamespace then None
            else

            let denv = DisplayEnv.InitialForSigFileGeneration cenv.g

            let extraOpenPath =
                match entity.CompilationPathOpt with
                | Some cpath ->
                    let rec getOpenPath accessPath acc =
                        match accessPath with
                        | [] -> acc
                        | (name, ModuleOrNamespaceKind.ModuleOrType) :: accessPath ->
                            getOpenPath accessPath (name :: acc)
                        | (name, ModuleOrNamespaceKind.Namespace _) :: accessPath ->
                            getOpenPath accessPath (name :: acc)
                        | (name, ModuleOrNamespaceKind.FSharpModuleWithSuffix) :: accessPath ->
                            getOpenPath accessPath (name :: acc)

                    getOpenPath cpath.AccessPath []
                | _ -> 
                    []
                |> List.rev

            let needOpenType =
                match entity.CompilationPathOpt with
                | Some cpath ->
                    match cpath.AccessPath with
                    | (_, ModuleOrNamespaceKind.ModuleOrType) :: _ ->
                        match this.DeclaringEntity with
                        | Some (declaringEntity: FSharpEntity) -> not declaringEntity.IsFSharpModule
                        | _ -> false
                    | _ -> false
                | _ ->
                    false

            let denv = denv.AddOpenPath extraOpenPath

            let infoReader = cenv.infoReader

            let assemblyInfoL =
                Layout.aboveListL
                    [
                        (Layout.(^^)
                            (Layout.wordL (TaggedText.tagUnknownEntity "// "))
                            (Layout.wordL (TaggedText.tagUnknownEntity this.Assembly.QualifiedName)))
                        match this.Assembly.FileName with
                        | Some fn ->
                            (Layout.(^^)
                                (Layout.wordL (TaggedText.tagUnknownEntity "// "))
                                (Layout.wordL (TaggedText.tagUnknownEntity fn)))
                        | None -> Layout.emptyL
                    ]

            let openPathL =
                extraOpenPath
                |> List.map (fun x -> Layout.wordL (TaggedText.tagUnknownEntity x))

            let pathL =
                if List.isEmpty extraOpenPath then
                    Layout.emptyL
                else
                    Layout.sepListL (Layout.sepL TaggedText.dot) openPathL
                    
            let headerL =
                if List.isEmpty extraOpenPath then
                    Layout.emptyL
                else
                    Layout.(^^)
                        (Layout.wordL (TaggedText.tagKeyword "namespace"))
                        pathL

            let openL = 
                if List.isEmpty openPathL then Layout.emptyL
                else
                    let openKeywordL =
                        if needOpenType then
                            Layout.(^^)
                                (Layout.wordL (TaggedText.tagKeyword "open"))
                                (Layout.wordL TaggedText.keywordType)
                        else
                            Layout.wordL (TaggedText.tagKeyword "open")                            
                    Layout.(^^)
                        openKeywordL
                        pathL

            Layout.aboveListL
                [   
                    (Layout.(^^) assemblyInfoL (Layout.sepL TaggedText.lineBreak))
                    (Layout.(^^) headerL (Layout.sepL TaggedText.lineBreak))
                    (Layout.(^^) openL (Layout.sepL TaggedText.lineBreak))
                    (NicePrint.layoutEntityDefn denv infoReader AccessibleFromSomewhere range0 entity)
                ]
            |> LayoutRender.showL
            |> SourceText.ofString
            |> Some
        | _ ->
            None

    override x.Equals(other: obj) =
        box x === other ||
        match other with
        |   :? FSharpEntity as otherEntity -> tyconRefEq cenv.g entity otherEntity.Entity
        |   _ -> false

    override x.GetHashCode() =
        checkIsResolved()
        ((hash entity.Stamp) <<< 1) + 1

    override x.ToString() = x.CompiledName

type FSharpUnionCase(cenv, v: UnionCaseRef) =
    inherit FSharpSymbol (cenv,  
                          (fun () -> 
                               checkEntityIsResolved v.TyconRef
                               Item.UnionCase(UnionCaseInfo(generalizeTypars v.TyconRef.TyparsNoRange, v), false)), 
                          (fun _this thisCcu2 ad -> 
                               checkForCrossProjectAccessibility cenv.g.ilg (thisCcu2, ad) (cenv.thisCcu, v.UnionCase.Accessibility)) 
                               //&& AccessibilityLogic.IsUnionCaseAccessible cenv.amap range0 ad v)
                               )


    let isUnresolved() =
        entityIsUnresolved v.TyconRef || v.TryUnionCase.IsNone 
        
    let checkIsResolved() = 
        checkEntityIsResolved v.TyconRef
        if v.TryUnionCase.IsNone then 
            invalidOp (sprintf "The union case '%s' could not be found in the target type" v.CaseName)

    member _.IsUnresolved = 
        isUnresolved()

    member _.Name = 
        checkIsResolved()
        v.UnionCase.LogicalName

    member _.DeclarationLocation = 
        checkIsResolved()
        v.Range

    member _.DeclaringEntity =
        checkIsResolved()
        FSharpEntity(cenv, v.TyconRef)

    member _.HasFields =
        if isUnresolved() then false else
        v.UnionCase.RecdFieldsArray.Length <> 0

    member _.Fields = 
        if isUnresolved() then makeReadOnlyCollection [] else
        v.UnionCase.RecdFieldsArray |> Array.mapi (fun i _ ->  FSharpField(cenv, FSharpFieldData.Union (v, i))) |> makeReadOnlyCollection

    member _.ReturnType = 
        checkIsResolved()
        FSharpType(cenv, v.ReturnType)

    member _.CompiledName =
        checkIsResolved()
        v.UnionCase.CompiledName

    member _.XmlDocSig = 
        checkIsResolved()
        let unionCase = UnionCaseInfo(generalizeTypars v.TyconRef.TyparsNoRange, v)
        match GetXmlDocSigOfUnionCaseRef unionCase.UnionCaseRef with
        | Some (_, docsig) -> docsig
        | _ -> ""

    member _.XmlDoc = 
        if isUnresolved() then XmlDoc.Empty  |> makeXmlDoc else
        v.UnionCase.XmlDoc |> makeXmlDoc

    member _.ElaboratedXmlDoc = 
        if isUnresolved() then XmlDoc.Empty  |> makeElaboratedXmlDoc else
        v.UnionCase.XmlDoc |> makeElaboratedXmlDoc

    override _.Attributes = 
        if isUnresolved() then makeReadOnlyCollection [] else
        v.Attribs |> List.map (fun a -> FSharpAttribute(cenv, AttribInfo.FSAttribInfo(cenv.g, a))) |> makeReadOnlyCollection

    override _.Accessibility =  
        if isUnresolved() then FSharpAccessibility taccessPublic else
        FSharpAccessibility(v.UnionCase.Accessibility)

    member private x.V = v
    override x.Equals(other: obj) =
        box x === other ||
        match other with
        |   :? FSharpUnionCase as uc -> v === uc.V
        |   _ -> false

    override x.GetHashCode() = hash v.CaseName

    override x.ToString() = x.CompiledName

type FSharpFieldData = 
    | AnonField of AnonRecdTypeInfo * TTypes * int * range
    | ILField of ILFieldInfo
    | RecdOrClass of RecdFieldRef
    | Union of UnionCaseRef * int

    member x.TryRecdField =
        match x with 
        | AnonField (anonInfo, tinst, n, m) -> (anonInfo, tinst, n, m) |> Choice3Of3
        | RecdOrClass v -> v.RecdField |> Choice1Of3
        | Union (v, n) -> v.FieldByIndex n |> Choice1Of3
        | ILField f -> f |> Choice2Of3

    member x.TryDeclaringTyconRef =
        match x with 
        | RecdOrClass v -> Some v.TyconRef
        | ILField f -> Some f.DeclaringTyconRef
        | _ -> None

type FSharpAnonRecordTypeDetails(cenv: SymbolEnv, anonInfo: AnonRecdTypeInfo)  =
    member _.Assembly = FSharpAssembly (cenv, anonInfo.Assembly)

    /// Names of any enclosing types of the compiled form of the anonymous type (if the anonymous type was defined as a nested type)
    member _.EnclosingCompiledTypeNames = anonInfo.ILTypeRef.Enclosing

    /// The name of the compiled form of the anonymous type
    member _.CompiledName = anonInfo.ILTypeRef.Name

    /// The sorted labels of the anonymous type
    member _.SortedFieldNames = anonInfo.SortedNames

type FSharpField(cenv: SymbolEnv, d: FSharpFieldData)  =
    inherit FSharpSymbol (cenv, 
                          (fun () -> 
                                match d with 
                                | AnonField (anonInfo, tinst, n, m) -> 
                                    Item.AnonRecdField(anonInfo, tinst, n, m)
                                | RecdOrClass v -> 
                                    checkEntityIsResolved v.TyconRef
                                    Item.RecdField(RecdFieldInfo(generalizeTypars v.TyconRef.TyparsNoRange, v))
                                | Union (v, fieldIndex) ->
                                    checkEntityIsResolved v.TyconRef
                                    Item.UnionCaseField (UnionCaseInfo (generalizeTypars v.TyconRef.TyparsNoRange, v), fieldIndex)
                                | ILField f -> 
                                    Item.ILField f), 
                          (fun this thisCcu2 ad -> 
                                checkForCrossProjectAccessibility cenv.g.ilg (thisCcu2, ad) (cenv.thisCcu, (this :?> FSharpField).Accessibility.Contents)) 
                                //&&
                                //match d with 
                                //| Recd v -> AccessibilityLogic.IsRecdFieldAccessible cenv.amap range0 ad v
                                //| Union (v, _) -> AccessibilityLogic.IsUnionCaseAccessible cenv.amap range0 ad v)
                                )

    let isUnresolved() = 
        d.TryDeclaringTyconRef |> Option.exists entityIsUnresolved ||
        match d with
        | AnonField _ -> false
        | RecdOrClass v -> v.TryRecdField.IsNone 
        | Union (v, _) -> v.TryUnionCase.IsNone 
        | ILField _ -> false

    let checkIsResolved() = 
        d.TryDeclaringTyconRef |> Option.iter checkEntityIsResolved 
        match d with 
        | AnonField _ -> ()
        | RecdOrClass v -> 
            if v.TryRecdField.IsNone then 
                invalidOp (sprintf "The record field '%s' could not be found in the target type" v.FieldName)
        | Union (v, _) -> 
            if v.TryUnionCase.IsNone then 
                invalidOp (sprintf "The union case '%s' could not be found in the target type" v.CaseName)
        | ILField _ -> ()

    new (cenv, ucref: UnionCaseRef, n) = FSharpField(cenv, FSharpFieldData.Union(ucref, n))

    new (cenv, rfref: RecdFieldRef) = FSharpField(cenv, FSharpFieldData.RecdOrClass rfref)

    member _.DeclaringEntity = 
        d.TryDeclaringTyconRef |> Option.map (fun tcref -> FSharpEntity(cenv, tcref))

    member _.IsUnresolved = 
        isUnresolved()

    member _.IsMutable = 
        if isUnresolved() then false else 
        match d.TryRecdField with 
        | Choice1Of3 r -> r.IsMutable
        | Choice2Of3 f -> not f.IsInitOnly && f.LiteralValue.IsNone
        | Choice3Of3 _ -> false

    member _.IsLiteral = 
        if isUnresolved() then false else 
        match d.TryRecdField with 
        | Choice1Of3 r -> r.LiteralValue.IsSome
        | Choice2Of3 f -> f.LiteralValue.IsSome
        | Choice3Of3 _ -> false

    member _.LiteralValue = 
        if isUnresolved() then None else 
        match d.TryRecdField with 
        | Choice1Of3 r -> getLiteralValue r.LiteralValue
        | Choice2Of3 f -> f.LiteralValue |> Option.map (fun v -> v.AsObject())
        | Choice3Of3 _ -> None

    member _.IsVolatile = 
        if isUnresolved() then false else 
        match d.TryRecdField with 
        | Choice1Of3 r -> r.IsVolatile
        | Choice2Of3 _ -> false // F# doesn't actually respect "volatile" from other assemblies in any case
        | Choice3Of3 _ -> false

    member _.IsDefaultValue = 
        if isUnresolved() then false else 
        match d.TryRecdField with 
        | Choice1Of3 r -> r.IsZeroInit
        | Choice2Of3 _ -> false 
        | Choice3Of3 _ -> false

    member _.IsAnonRecordField = 
        match d with 
        | AnonField _ -> true
        | _ -> false

    member _.AnonRecordFieldDetails = 
        match d with 
        | AnonField (anonInfo, types, n, _) -> FSharpAnonRecordTypeDetails(cenv, anonInfo), [| for ty in types -> FSharpType(cenv, ty) |], n
        | _ -> invalidOp "not an anonymous record field"

    member _.IsUnionCaseField = 
        match d with 
        | Union _ -> true
        | _ -> false

    member _.DeclaringUnionCase =
        match d with
        | Union (v, _) -> Some (FSharpUnionCase (cenv, v))
        | _ -> None

    member _.XmlDocSig = 
        checkIsResolved()
        let xmlsig =
            match d with 
            | RecdOrClass v -> 
                let recd = RecdFieldInfo(generalizeTypars v.TyconRef.TyparsNoRange, v)
                GetXmlDocSigOfRecdFieldRef recd.RecdFieldRef
            | Union (v, _) -> 
                let unionCase = UnionCaseInfo(generalizeTypars v.TyconRef.TyparsNoRange, v)
                GetXmlDocSigOfUnionCaseRef unionCase.UnionCaseRef
            | ILField f -> 
                GetXmlDocSigOfILFieldInfo cenv.infoReader range0 f
            | AnonField _ -> None
        match xmlsig with
        | Some (_, docsig) -> docsig
        | _ -> ""

    member _.XmlDoc = 
        if isUnresolved() then XmlDoc.Empty  |> makeXmlDoc else
        match d.TryRecdField with 
        | Choice1Of3 r -> r.XmlDoc 
        | Choice2Of3 _ -> XmlDoc.Empty
        | Choice3Of3 _ -> XmlDoc.Empty
        |> makeXmlDoc

    member _.ElaboratedXmlDoc = 
        if isUnresolved() then XmlDoc.Empty  |> makeElaboratedXmlDoc else
        match d.TryRecdField with 
        | Choice1Of3 r -> r.XmlDoc 
        | Choice2Of3 _ -> XmlDoc.Empty
        | Choice3Of3 _ -> XmlDo
