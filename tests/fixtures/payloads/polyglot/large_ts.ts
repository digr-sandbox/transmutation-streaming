import {
    __String,
    AccessExpression,
    AccessorDeclaration,
    addEmitFlags,
    addRange,
    affectsDeclarationPathOptionDeclarations,
    affectsEmitOptionDeclarations,
    AllAccessorDeclarations,
    AmbientModuleDeclaration,
    AmpersandAmpersandEqualsToken,
    AnyImportOrBareOrAccessedRequire,
    AnyImportOrReExport,
    type AnyImportOrRequireStatement,
    AnyImportSyntax,
    AnyValidImportOrReExport,
    append,
    arrayFrom,
    ArrayLiteralExpression,
    ArrayTypeNode,
    ArrowFunction,
    AsExpression,
    AssertionExpression,
    assertType,
    AssignmentDeclarationKind,
    AssignmentExpression,
    AssignmentOperatorToken,
    BarBarEqualsToken,
    BinaryExpression,
    binarySearch,
    BindableObjectDefinePropertyCall,
    BindableStaticAccessExpression,
    BindableStaticElementAccessExpression,
    BindableStaticNameExpression,
    BindingElement,
    BindingElementOfBareOrAccessedRequire,
    Block,
    CallExpression,
    CallLikeExpression,
    CallSignatureDeclaration,
    canHaveDecorators,
    canHaveLocals,
    canHaveModifiers,
    CanHaveModuleSpecifier,
    CanonicalDiagnostic,
    CaseBlock,
    CaseClause,
    CaseOrDefaultClause,
    CatchClause,
    changeAnyExtension,
    CharacterCodes,
    CheckFlags,
    ClassDeclaration,
    ClassElement,
    ClassExpression,
    classHasDeclaredOrExplicitlyAssignedName,
    ClassLikeDeclaration,
    ClassStaticBlockDeclaration,
    combinePaths,
    CommaListExpression,
    CommandLineOption,
    CommentDirective,
    CommentDirectivesMap,
    CommentDirectiveType,
    CommentRange,
    comparePaths,
    compareStringsCaseSensitive,
    compareValues,
    Comparison,
    CompilerOptions,
    CompilerOptionsValue,
    ComputedPropertyName,
    computeLineAndCharacterOfPosition,
    computeLineOfPosition,
    computeLineStarts,
    concatenate,
    ConditionalExpression,
    ConstructorDeclaration,
    ConstructSignatureDeclaration,
    ContainerFlags,
    contains,
    containsPath,
    createGetCanonicalFileName,
    createMultiMap,
    createScanner,
    createTextSpan,
    createTextSpanFromBounds,
    Debug,
    Declaration,
    DeclarationName,
    DeclarationWithTypeParameterChildren,
    DeclarationWithTypeParameters,
    Decorator,
    DefaultClause,
    DestructuringAssignment,
    Diagnostic,
    DiagnosticArguments,
    DiagnosticCollection,
    DiagnosticMessage,
    DiagnosticMessageChain,
    DiagnosticRelatedInformation,
    Diagnostics,
    DiagnosticWithDetachedLocation,
    DiagnosticWithLocation,
    directorySeparator,
    DoStatement,
    DynamicNamedBinaryExpression,
    DynamicNamedDeclaration,
    ElementAccessExpression,
    EmitFlags,
    EmitHost,
    EmitResolver,
    EmitTextWriter,
    emptyArray,
    endsWith,
    ensurePathIsNonModuleName,
    ensureTrailingDirectorySeparator,
    EntityName,
    EntityNameExpression,
    EntityNameOrEntityNameExpression,
    EnumDeclaration,
    EqualityComparer,
    equalOwnProperties,
    EqualsToken,
    equateValues,
    escapeLeadingUnderscores,
    EvaluationResolver,
    EvaluatorResult,
    every,
    ExportAssignment,
    ExportDeclaration,
    ExportSpecifier,
    Expression,
    ExpressionStatement,
    ExpressionWithTypeArguments,
    Extension,
    ExternalModuleReference,
    factory,
    FileExtensionInfo,
    fileExtensionIs,
    fileExtensionIsOneOf,
    FileReference,
    FileWatcher,
    filter,
    find,
    findAncestor,
    findBestPatternMatch,
    findIndex,
    findLast,
    firstDefined,
    firstOrUndefined,
    flatMap,
    flatMapToMutable,
    flatten,
    forEach,
    forEachChild,
    forEachChildRecursively,
    ForInOrOfStatement,
    ForInStatement,
    ForOfStatement,
    ForStatement,
    FunctionBody,
    FunctionDeclaration,
    FunctionExpression,
    FunctionLikeDeclaration,
    GetAccessorDeclaration,
    getAllJSDocTags,
    getBaseFileName,
    GetCanonicalFileName,
    getCombinedModifierFlags,
    getCombinedNodeFlags,
    getCommonSourceDirectory,
    getContainerFlags,
    getDirectoryPath,
    getImpliedNodeFormatForEmitWorker,
    getJSDocAugmentsTag,
    getJSDocDeprecatedTagNoCache,
    getJSDocImplementsTags,
    getJSDocOverrideTagNoCache,
    getJSDocParameterTags,
    getJSDocParameterTagsNoCache,
    getJSDocPrivateTagNoCache,
    getJSDocProtectedTagNoCache,
    getJSDocPublicTagNoCache,
    getJSDocReadonlyTagNoCache,
    getJSDocReturnType,
    getJSDocSatisfiesTag,
    getJSDocTags,
    getJSDocType,
    getJSDocTypeParameterTags,
    getJSDocTypeParameterTagsNoCache,
    getJSDocTypeTag,
    getLeadingCommentRanges,
    getLineAndCharacterOfPosition,
    getLinesBetweenPositions,
    getLineStarts,
    getModeForUsageLocation,
    getNameOfDeclaration,
    getNodeChildren,
    getNormalizedAbsolutePath,
    getNormalizedPathComponents,
    getOwnKeys,
    getParseTreeNode,
    getPathComponents,
    getPathFromPathComponents,
    getRelativePathFromDirectory,
    getRelativePathToDirectoryOrUrl,
    getResolutionModeOverride,
    getRootLength,
    getSnippetElement,
    getStringComparer,
    getSymbolId,
    getTrailingCommentRanges,
    HasExpressionInitializer,
    hasExtension,
    HasFlowNode,
    HasInferredType,
    HasInitializer,
    hasInitializer,
    HasJSDoc,
    hasJSDocNodes,
    HasModifiers,
    hasProperty,
    HasType,
    HasTypeArguments,
    HeritageClause,
    Identifier,
    identifierToKeywordKind,
    IdentifierTypePredicate,
    identity,
    idText,
    IfStatement,
    ignoredPaths,
    ImportAttribute,
    ImportCall,
    ImportClause,
    ImportDeclaration,
    ImportEqualsDeclaration,
    ImportMetaProperty,
    ImportSpecifier,
    ImportTypeNode,
    IndexInfo,
    indexOfAnyCharCode,
    IndexSignatureDeclaration,
    InferTypeNode,
    InitializedVariableDeclaration,
    insertSorted,
    InstanceofExpression,
    InterfaceDeclaration,
    InternalEmitFlags,
    InternalSymbolName,
    IntroducesNewScopeNode,
    isAccessor,
    isAnyDirectorySeparator,
    isArray,
    isArrayLiteralExpression,
    isArrowFunction,
    isAssertionExpression,
    isAutoAccessorPropertyDeclaration,
    isBigIntLiteral,
    isBinaryExpression,
    isBindingElement,
    isBindingPattern,
    isBlock,
    isCallExpression,
    isCaseClause,
    isClassDeclaration,
    isClassElement,
    isClassExpression,
    isClassLike,
    isClassStaticBlockDeclaration,
    isCommaListExpression,
    isComputedPropertyName,
    isConstructorDeclaration,
    isConstTypeReference,
    isDeclaration,
    isDeclarationFileName,
    isDecorator,
    isDefaultClause,
    isElementAccessExpression,
    isEnumDeclaration,
    isEnumMember,
    isExportAssignment,
    isExportDeclaration,
    isExpressionStatement,
    isExpressionWithTypeArguments,
    isExternalModule,
    isExternalModuleReference,
    isFileProbablyExternalModule,
    isForStatement,
    isFunctionDeclaration,
    isFunctionExpression,
    isFunctionLike,
    isFunctionLikeDeclaration,
    isFunctionLikeOrClassStaticBlockDeclaration,
    isGetAccessorDeclaration,
    isHeritageClause,
    isIdentifier,
    isIdentifierStart,
    isIdentifierText,
    isImportDeclaration,
    isImportTypeNode,
    isInterfaceDeclaration,
    isJSDoc,
    isJSDocAugmentsTag,
    isJSDocFunctionType,
    isJSDocImplementsTag,
    isJSDocImportTag,
    isJSDocLinkLike,
    isJSDocMemberName,
    isJSDocNameReference,
    isJSDocNode,
    isJSDocOverloadTag,
    isJSDocParameterTag,
    isJSDocPropertyLikeTag,
    isJSDocReturnTag,
    isJSDocSatisfiesTag,
    isJSDocSignature,
    isJSDocTag,
    isJSDocTemplateTag,
    isJSDocTypeExpression,
    isJSDocTypeLiteral,
    isJSDocTypeTag,
    isJsxChild,
    isJsxFragment,
    isJsxNamespacedName,
    isJsxOpeningLikeElement,
    isJsxText,
    isLeftHandSideExpression,
    isLineBreak,
    isLiteralTypeNode,
    isMappedTypeNode,
    isMemberName,
    isMetaProperty,
    isMethodDeclaration,
    isMethodOrAccessor,
    isModifierLike,
    isModuleBlock,
    isModuleDeclaration,
    isModuleOrEnumDeclaration,
    isNamedDeclaration,
    isNamespaceExport,
    isNamespaceExportDeclaration,
    isNamespaceImport,
    isNonNullExpression,
    isNoSubstitutionTemplateLiteral,
    isNullishCoalesce,
    isNumericLiteral,
    isObjectBindingPattern,
    isObjectLiteralExpression,
    isOmittedExpression,
    isOptionalChain,
    isParameter,
    isParameterPropertyDeclaration,
    isParenthesizedExpression,
    isParenthesizedTypeNode,
    isPrefixUnaryExpression,
    isPrivateIdentifier,
    isPropertyAccessExpression,
    isPropertyAssignment,
    isPropertyDeclaration,
    isPropertyName,
    isPropertySignature,
    isQualifiedName,
    isRootedDiskPath,
    isSetAccessorDeclaration,
    isShiftOperatorOrHigher,
    isShorthandPropertyAssignment,
    isSourceFile,
    isString,
    isStringLiteral,
    isStringLiteralLike,
    isTypeAliasDeclaration,
    isTypeElement,
    isTypeLiteralNode,
    isTypeNode,
    isTypeParameterDeclaration,
    isTypeQueryNode,
    isTypeReferenceNode,
    isVariableDeclaration,
    isVariableStatement,
    isVoidExpression,
    isWhiteSpaceLike,
    isWhiteSpaceSingleLine,
    JSDoc,
    JSDocArray,
    JSDocCallbackTag,
    JSDocEnumTag,
    JSDocImportTag,
    JSDocMemberName,
    JSDocOverloadTag,
    JSDocParameterTag,
    JSDocSatisfiesExpression,
    JSDocSatisfiesTag,
    JSDocSignature,
    JSDocTag,
    JSDocTemplateTag,
    JSDocTypedefTag,
    JsonSourceFile,
    JsxAttributeName,
    JsxChild,
    JsxElement,
    JsxEmit,
    JsxFragment,
    JsxNamespacedName,
    JsxOpeningElement,
    JsxOpeningLikeElement,
    JsxSelfClosingElement,
    JsxTagNameExpression,
    KeywordSyntaxKind,
    LabeledStatement,
    LanguageVariant,
    last,
    lastOrUndefined,
    LateVisibilityPaintedStatement,
    length,
    libMap,
    LiteralImportTypeNode,
    LiteralLikeElementAccessExpression,
    LiteralLikeNode,
    LogicalOperator,
    LogicalOrCoalescingAssignmentOperator,
    mangleScopedPackageName,
    map,
    mapDefined,
    MapLike,
    MemberName,
    memoize,
    MetaProperty,
    MethodDeclaration,
    MethodSignature,
    ModeAwareCache,
    ModifierFlags,
    ModifierLike,
    ModuleBlock,
    ModuleDeclaration,
    ModuleDetectionKind,
    ModuleExportName,
    ModuleKind,
    ModuleResolutionKind,
    moduleResolutionOptionDeclarations,
    MultiMap,
    NamedDeclaration,
    NamedExports,
    NamedImports,
    NamedImportsOrExports,
    NamespaceExport,
    NamespaceImport,
    NewExpression,
    NewLineKind,
    Node,
    NodeArray,
    NodeFlags,
    nodeModulesPathPart,
    NonNullExpression,
    noop,
    normalizePath,
    NoSubstitutionTemplateLiteral,
    NumberLiteralType,
    NumericLiteral,
    ObjectFlags,
    ObjectFlagsType,
    ObjectLiteralElement,
    ObjectLiteralExpression,
    ObjectLiteralExpressionBase,
    ObjectTypeDeclaration,
    optionsAffectingProgramStructure,
    or,
    OuterExpressionKinds,
    PackageId,
    ParameterDeclaration,
    ParenthesizedExpression,
    ParenthesizedTypeNode,
    parseConfigFileTextToJson,
    PartiallyEmittedExpression,
    Path,
    pathIsRelative,
    Pattern,
    PostfixUnaryExpression,
    PrefixUnaryExpression,
    PrimitiveLiteral,
    PrinterOptions,
    PrintHandlers,
    PrivateIdentifier,
    ProjectReference,
    PrologueDirective,
    PropertyAccessEntityNameExpression,
    PropertyAccessExpression,
    PropertyAssignment,
    PropertyDeclaration,
    PropertyName,
    PropertyNameLiteral,
    PropertySignature,
    PseudoBigInt,
    PunctuationOrKeywordSyntaxKind,
    PunctuationSyntaxKind,
    QualifiedName,
    QuestionQuestionEqualsToken,
    ReadonlyCollection,
    ReadonlyTextRange,
    removeTrailingDirectorySeparator,
    RequireOrImportCall,
    RequireVariableStatement,
    ResolutionMode,
    ResolvedModuleFull,
    ResolvedModuleWithFailedLookupLocations,
    ResolvedProjectReference,
    ResolvedTypeReferenceDirective,
    ResolvedTypeReferenceDirectiveWithFailedLookupLocations,
    resolvePath,
    returnFalse,
    ReturnStatement,
    returnUndefined,
    SatisfiesExpression,
    ScriptKind,
    ScriptTarget,
    semanticDiagnosticsOptionDeclarations,
    SetAccessorDeclaration,
    setOriginalNode,
    setTextRange,
    ShorthandPropertyAssignment,
    shouldAllowImportingTsExtension,
    Signature,
    SignatureDeclaration,
    SignatureFlags,
    singleElementArray,
    singleOrUndefined,
    skipOuterExpressions,
    skipTrivia,
    SnippetKind,
    some,
    SortedArray,
    SourceFile,
    SourceFileLike,
    SourceFileMayBeEmittedHost,
    SourceMapSource,
    startsWith,
    startsWithUseStrict,
    Statement,
    StringLiteral,
    StringLiteralLike,
    StringLiteralType,
    stringToToken,
    SuperCall,
    SuperProperty,
    SwitchStatement,
    Symbol,
    SymbolFlags,
    SymbolTable,
    SyntaxKind,
    TaggedTemplateExpression,
    targetOptionDeclaration,
    TemplateExpression,
    TemplateLiteral,
    TemplateLiteralLikeNode,
    TemplateLiteralToken,
    TemplateLiteralTypeSpan,
    TemplateSpan,
    TextRange,
    TextSpan,
    ThisTypePredicate,
    toFileNameLowerCase,
    Token,
    TokenFlags,
    tokenToString,
    toPath,
    toSorted,
    tracing,
    TransformFlags,
    TransientSymbol,
    TriviaSyntaxKind,
    tryCast,
    tryRemovePrefix,
    TryStatement,
    TsConfigSourceFile,
    TupleTypeNode,
    Type,
    TypeAliasDeclaration,
    TypeAssertion,
    TypeChecker,
    TypeCheckerHost,
    TypeElement,
    TypeFlags,
    TypeLiteralNode,
    TypeNode,
    TypeNodeSyntaxKind,
    TypeParameter,
    TypeParameterDeclaration,
    TypePredicate,
    TypePredicateKind,
    TypeReferenceNode,
    unescapeLeadingUnderscores,
    UnionOrIntersectionTypeNode,
    UniqueESSymbolType,
    UserPreferences,
    ValidImportTypeNode,
    VariableDeclaration,
    VariableDeclarationInitializedTo,
    VariableDeclarationList,
    VariableLikeDeclaration,
    VariableStatement,
    visitEachChild,
    WhileStatement,
    WithStatement,
    WrappedExpression,
    WriteFileCallback,
    WriteFileCallbackData,
    YieldExpression,
} from "./_namespaces/ts.js";

/** @internal */
export const resolvingEmptyArray: never[] = [];

/** @internal */
export const externalHelpersModuleNameText = "tslib";

/** @internal */
export const defaultMaximumTruncationLength = 160;
/** @internal */
export const noTruncationMaximumTruncationLength = 1_000_000;
/** @internal */
export const defaultHoverMaximumTruncationLength = 500;

/** @internal */
export function getDeclarationOfKind<T extends Declaration>(symbol: Symbol, kind: T["kind"]): T | undefined {
    const declarations = symbol.declarations;
    if (declarations) {
        for (const declaration of declarations) {
            if (declaration.kind === kind) {
                return declaration as T;
            }
        }
    }

    return undefined;
}

/** @internal */
export function getDeclarationsOfKind<T extends Declaration>(symbol: Symbol, kind: T["kind"]): T[] {
    return filter(symbol.declarations || emptyArray, d => d.kind === kind) as T[];
}

/** @internal */
export function createSymbolTable(symbols?: readonly Symbol[]): SymbolTable {
    const result = new Map<__String, Symbol>();
    if (symbols) {
        for (const symbol of symbols) {
            result.set(symbol.escapedName, symbol);
        }
    }
    return result;
}

/** @internal */
export function isTransientSymbol(symbol: Symbol): symbol is TransientSymbol {
    return (symbol.flags & SymbolFlags.Transient) !== 0;
}

/**
 * True if the symbol is for an external module, as opposed to a namespace.
 *
 * @internal
 */
export function isExternalModuleSymbol(moduleSymbol: Symbol): boolean {
    return !!(moduleSymbol.flags & SymbolFlags.Module) && (moduleSymbol.escapedName as string).charCodeAt(0) === CharacterCodes.doubleQuote;
}

const stringWriter = createSingleLineStringWriter();

function createSingleLineStringWriter(): EmitTextWriter {
    // Why var? It avoids TDZ checks in the runtime which can be costly.
    // See: https://github.com/microsoft/TypeScript/issues/52924
    /* eslint-disable no-var */
    var str = "";
    /* eslint-enable no-var */
    const writeText: (text: string) => void = text => str += text;
    return {
        getText: () => str,
        write: writeText,
        rawWrite: writeText,
        writeKeyword: writeText,
        writeOperator: writeText,
        writePunctuation: writeText,
        writeSpace: writeText,
        writeStringLiteral: writeText,
        writeLiteral: writeText,
        writeParameter: writeText,
        writeProperty: writeText,
        writeSymbol: (s, _) => writeText(s),
        writeTrailingSemicolon: writeText,
        writeComment: writeText,
        getTextPos: () => str.length,
        getLine: () => 0,
        getColumn: () => 0,
        getIndent: () => 0,
        isAtStartOfLine: () => false,
        hasTrailingComment: () => false,
        hasTrailingWhitespace: () => !!str.length && isWhiteSpaceLike(str.charCodeAt(str.length - 1)),

        // Completely ignore indentation for string writers.  And map newlines to
        // a single space.
        writeLine: () => str += " ",
        increaseIndent: noop,
        decreaseIndent: noop,
        clear: () => str = "",
    };
}

/** @internal */
export function changesAffectModuleResolution(oldOptions: CompilerOptions, newOptions: CompilerOptions): boolean {
    return oldOptions.configFilePath !== newOptions.configFilePath ||
        optionsHaveModuleResolutionChanges(oldOptions, newOptions);
}

function optionsHaveModuleResolutionChanges(oldOptions: CompilerOptions, newOptions: CompilerOptions) {
    return optionsHaveChanges(oldOptions, newOptions, moduleResolutionOptionDeclarations);
}

/** @internal */
export function changesAffectingProgramStructure(oldOptions: CompilerOptions, newOptions: CompilerOptions): boolean {
    return optionsHaveChanges(oldOptions, newOptions, optionsAffectingProgramStructure);
}

/** @internal */
export function optionsHaveChanges(oldOptions: CompilerOptions, newOptions: CompilerOptions, optionDeclarations: readonly CommandLineOption[]): boolean {
    return oldOptions !== newOptions && optionDeclarations.some(o => !isJsonEqual(getCompilerOptionValue(oldOptions, o), getCompilerOptionValue(newOptions, o)));
}

/** @internal */
export function forEachAncestor<T>(node: Node, callback: (n: Node) => T | undefined | "quit"): T | undefined {
    while (true) {
        const res = callback(node);
        if (res === "quit") return undefined;
        if (res !== undefined) return res;
        if (isSourceFile(node)) return undefined;
        node = node.parent;
    }
}

/**
 * Calls `callback` for each entry in the map, returning the first truthy result.
 * Use `map.forEach` instead for normal iteration.
 *
 * @internal
 */
export function forEachEntry<K, V, U>(map: ReadonlyMap<K, V>, callback: (value: V, key: K) => U | undefined): U | undefined {
    const iterator = map.entries();
    for (const [key, value] of iterator) {
        const result = callback(value, key);
        if (result) {
            return result;
        }
    }
    return undefined;
}

/**
 * `forEachEntry` for just keys.
 *
 * @internal
 */
export function forEachKey<K, T>(map: ReadonlyCollection<K>, callback: (key: K) => T | undefined): T | undefined {
    const iterator = map.keys();
    for (const key of iterator) {
        const result = callback(key);
        if (result) {
            return result;
        }
    }
    return undefined;
}

/**
 * Copy entries from `source` to `target`.
 *
 * @internal
 */
export function copyEntries<K, V>(source: ReadonlyMap<K, V>, target: Map<K, V>): void {
    source.forEach((value, key) => {
        target.set(key, value);
    });
}

/** @internal */
export function usingSingleLineStringWriter(action: (writer: EmitTextWriter) => void): string {
    const oldString = stringWriter.getText();
    try {
        action(stringWriter);
        return stringWriter.getText();
    }
    finally {
        stringWriter.clear();
        stringWriter.writeKeyword(oldString);
    }
}

/** @internal */
export function getFullWidth(node: Node): number {
    return node.end - node.pos;
}

/** @internal */
export function projectReferenceIsEqualTo(oldRef: ProjectReference, newRef: ProjectReference): boolean {
    return oldRef.path === newRef.path &&
        !oldRef.prepend === !newRef.prepend &&
        !oldRef.circular === !newRef.circular;
}

/** @internal */
export function moduleResolutionIsEqualTo(oldResolution: ResolvedModuleWithFailedLookupLocations, newResolution: ResolvedModuleWithFailedLookupLocations): boolean {
    return oldResolution === newResolution ||
        oldResolution.resolvedModule === newResolution.resolvedModule ||
        !!oldResolution.resolvedModule &&
            !!newResolution.resolvedModule &&
            oldResolution.resolvedModule.isExternalLibraryImport === newResolution.resolvedModule.isExternalLibraryImport &&
            oldResolution.resolvedModule.extension === newResolution.resolvedModule.extension &&
            oldResolution.resolvedModule.resolvedFileName === newResolution.resolvedModule.resolvedFileName &&
            oldResolution.resolvedModule.originalPath === newResolution.resolvedModule.originalPath &&
            packageIdIsEqual(oldResolution.resolvedModule.packageId, newResolution.resolvedModule.packageId) &&
            oldResolution.alternateResult === newResolution.alternateResult;
}

/** @internal */
export function getResolvedModuleFromResolution(resolution: ResolvedModuleWithFailedLookupLocations): ResolvedModuleFull | undefined {
    return resolution.resolvedModule;
}

/** @internal */
export function getResolvedTypeReferenceDirectiveFromResolution(resolution: ResolvedTypeReferenceDirectiveWithFailedLookupLocations): ResolvedTypeReferenceDirective | undefined {
    return resolution.resolvedTypeReferenceDirective;
}

/** @internal */
export function createModuleNotFoundChain(sourceFile: SourceFile, host: TypeCheckerHost, moduleReference: string, mode: ResolutionMode, packageName: string): DiagnosticMessageChain {
    const alternateResult = host.getResolvedModule(sourceFile, moduleReference, mode)?.alternateResult;
    const alternateResultMessage = alternateResult && (getEmitModuleResolutionKind(host.getCompilerOptions()) === ModuleResolutionKind.Node10
        ? [Diagnostics.There_are_types_at_0_but_this_result_could_not_be_resolved_under_your_current_moduleResolution_setting_Consider_updating_to_node16_nodenext_or_bundler, [alternateResult]] as const
        : [
            Diagnostics.There_are_types_at_0_but_this_result_could_not_be_resolved_when_respecting_package_json_exports_The_1_library_may_need_to_update_its_package_json_or_typings,
            [alternateResult, alternateResult.includes(nodeModulesPathPart + "@types/") ? `@types/${mangleScopedPackageName(packageName)}` : packageName],
        ] as const);
    const result = alternateResultMessage
        ? chainDiagnosticMessages(
            /*details*/ undefined,
            alternateResultMessage[0],
            ...alternateResultMessage[1],
        )
        : host.typesPackageExists(packageName)
        ? chainDiagnosticMessages(
            /*details*/ undefined,
            Diagnostics.If_the_0_package_actually_exposes_this_module_consider_sending_a_pull_request_to_amend_https_Colon_Slash_Slashgithub_com_SlashDefinitelyTyped_SlashDefinitelyTyped_Slashtree_Slashmaster_Slashtypes_Slash_1,
            packageName,
            mangleScopedPackageName(packageName),
        )
        : host.packageBundlesTypes(packageName)
        ? chainDiagnosticMessages(
            /*details*/ undefined,
            Diagnostics.If_the_0_package_actually_exposes_this_module_try_adding_a_new_declaration_d_ts_file_containing_declare_module_1,
            packageName,
            moduleReference,
        )
        : chainDiagnosticMessages(
            /*details*/ undefined,
            Diagnostics.Try_npm_i_save_dev_types_Slash_1_if_it_exists_or_add_a_new_declaration_d_ts_file_containing_declare_module_0,
            moduleReference,
            mangleScopedPackageName(packageName),
        );
    if (result) result.repopulateInfo = () => ({ moduleReference, mode, packageName: packageName === moduleReference ? undefined : packageName });
    return result;
}

/** @internal */
export function createModeMismatchDetails(currentSourceFile: SourceFile): DiagnosticMessageChain {
    const ext = tryGetExtensionFromPath(currentSourceFile.fileName);
    const scope = currentSourceFile.packageJsonScope;
    const targetExt = ext === Extension.Ts ? Extension.Mts : ext === Extension.Js ? Extension.Mjs : undefined;
    const result = scope && !scope.contents.packageJsonContent.type ?
        targetExt ?
            chainDiagnosticMessages(
                /*details*/ undefined,
                Diagnostics.To_convert_this_file_to_an_ECMAScript_module_change_its_file_extension_to_0_or_add_the_field_type_Colon_module_to_1,
                targetExt,
                combinePaths(scope.packageDirectory, "package.json"),
            ) :
            chainDiagnosticMessages(
                /*details*/ undefined,
                Diagnostics.To_convert_this_file_to_an_ECMAScript_module_add_the_field_type_Colon_module_to_0,
                combinePaths(scope.packageDirectory, "package.json"),
            ) :
        targetExt ?
        chainDiagnosticMessages(
            /*details*/ undefined,
            Diagnostics.To_convert_this_file_to_an_ECMAScript_module_change_its_file_extension_to_0_or_create_a_local_package_json_file_with_type_Colon_module,
            targetExt,
        ) :
        chainDiagnosticMessages(
            /*details*/ undefined,
            Diagnostics.To_convert_this_file_to_an_ECMAScript_module_create_a_local_package_json_file_with_type_Colon_module,
        );
    result.repopulateInfo = () => true;
    return result;
}

function packageIdIsEqual(a: PackageId | undefined, b: PackageId | undefined): boolean {
    return a === b || !!a && !!b && a.name === b.name && a.subModuleName === b.subModuleName && a.version === b.version && a.peerDependencies === b.peerDependencies;
}

/** @internal */
export function packageIdToPackageName({ name, subModuleName }: PackageId): string {
    return subModuleName ? `${name}/${subModuleName}` : name;
}

/** @internal */
export function packageIdToString(packageId: PackageId): string {
    return `${packageIdToPackageName(packageId)}@${packageId.version}${packageId.peerDependencies ?? ""}`;
}

/** @internal */
export function typeDirectiveIsEqualTo(oldResolution: ResolvedTypeReferenceDirectiveWithFailedLookupLocations, newResolution: ResolvedTypeReferenceDirectiveWithFailedLookupLocations): boolean {
    return oldResolution === newResolution ||
        oldResolution.resolvedTypeReferenceDirective === newResolution.resolvedTypeReferenceDirective ||
        !!oldResolution.resolvedTypeReferenceDirective &&
            !!newResolution.resolvedTypeReferenceDirective &&
            oldResolution.resolvedTypeReferenceDirective.resolvedFileName === newResolution.resolvedTypeReferenceDirective.resolvedFileName &&
            !!oldResolution.resolvedTypeReferenceDirective.primary === !!newResolution.resolvedTypeReferenceDirective.primary &&
            oldResolution.resolvedTypeReferenceDirective.originalPath === newResolution.resolvedTypeReferenceDirective.originalPath;
}

/** @internal */
export function hasChangesInResolutions<K, V>(
    names: readonly K[],
    newResolutions: readonly V[],
    getOldResolution: (name: K) => V | undefined,
    comparer: (oldResolution: V, newResolution: V) => boolean,
): boolean {
    Debug.assert(names.length === newResolutions.length);

    for (let i = 0; i < names.length; i++) {
        const newResolution = newResolutions[i];
        const entry = names[i];
        const oldResolution = getOldResolution(entry);
        const changed = oldResolution
            ? !newResolution || !comparer(oldResolution, newResolution)
            : newResolution;
        if (changed) {
            return true;
        }
    }
    return false;
}

// Returns true if this node contains a parse error anywhere underneath it.
/** @internal */
export function containsParseError(node: Node): boolean {
    aggregateChildData(node);
    return (node.flags & NodeFlags.ThisNodeOrAnySubNodesHasError) !== 0;
}

function aggregateChildData(node: Node): void {
    if (!(node.flags & NodeFlags.HasAggregatedChildData)) {
        // A node is considered to contain a parse error if:
        //  a) the parser explicitly marked that it had an error
        //  b) any of it's children reported that it had an error.
        const thisNodeOrAnySubNodesHasError = ((node.flags & NodeFlags.ThisNodeHasError) !== 0) ||
            forEachChild(node, containsParseError);

        // If so, mark ourselves accordingly.
        if (thisNodeOrAnySubNodesHasError) {
            (node as Mutable<Node>).flags |= NodeFlags.ThisNodeOrAnySubNodesHasError;
        }

        // Also mark that we've propagated the child information to this node.  This way we can
        // always consult the bit directly on this node without needing to check its children
        // again.
        (node as Mutable<Node>).flags |= NodeFlags.HasAggregatedChildData;
    }
}

/** @internal */
export function getSourceFileOfNode(node: Node): SourceFile;
/** @internal */
export function getSourceFileOfNode(node: Node | undefined): SourceFile | undefined;
/** @internal */
export function getSourceFileOfNode(node: Node | undefined): SourceFile | undefined {
    while (node && node.kind !== SyntaxKind.SourceFile) {
        node = node.parent;
    }
    return node as SourceFile;
}

/** @internal */
export function getSourceFileOfModule(module: Symbol): SourceFile | undefined {
    return getSourceFileOfNode(module.valueDeclaration || getNonAugmentationDeclaration(module));
}

/** @internal */
export function isPlainJsFile(file: SourceFile | undefined, checkJs: boolean | undefined): boolean {
    return !!file && (file.scriptKind === ScriptKind.JS || file.scriptKind === ScriptKind.JSX) && !file.checkJsDirective && checkJs === undefined;
}

/** @internal */
export function isStatementWithLocals(node: Node): boolean {
    switch (node.kind) {
        case SyntaxKind.Block:
        case SyntaxKind.CaseBlock:
        case SyntaxKind.ForStatement:
        case SyntaxKind.ForInStatement:
        case SyntaxKind.ForOfStatement:
            return true;
    }
    return false;
}

/** @internal */
export function getStartPositionOfLine(line: number, sourceFile: SourceFileLike): number {
    Debug.assert(line >= 0);
    return getLineStarts(sourceFile)[line];
}

// This is a useful function for debugging purposes.
/** @internal @knipignore */
export function nodePosToString(node: Node): string {
    const file = getSourceFileOfNode(node);
    const loc = getLineAndCharacterOfPosition(file, node.pos);
    return `${file.fileName}(${loc.line + 1},${loc.character + 1})`;
}

/** @internal */
export function getEndLinePosition(line: number, sourceFile: SourceFileLike): number {
    Debug.assert(line >= 0);
    const lineStarts = getLineStarts(sourceFile);

    const lineIndex = line;
    const sourceText = sourceFile.text;
    if (lineIndex + 1 === lineStarts.length) {
        // last line - return EOF
        return sourceText.length - 1;
    }
    else {
        // current line start
        const start = lineStarts[lineIndex];
        // take the start position of the next line - 1 = it should be some line break
        let pos = lineStarts[lineIndex + 1] - 1;
        Debug.assert(isLineBreak(sourceText.charCodeAt(pos)));
        // walk backwards skipping line breaks, stop the the beginning of current line.
        // i.e:
        // <some text>
        // $ <- end of line for this position should match the start position
        while (start <= pos && isLineBreak(sourceText.charCodeAt(pos))) {
            pos--;
        }
        return pos;
    }
}

/**
 * Returns a value indicating whether a name is unique globally or within the current file.
 * Note: This does not consider whether a name appears as a free identifier or not, so at the expression `x.y` this includes both `x` and `y`.
 *
 * @internal
 */
export function isFileLevelUniqueName(sourceFile: SourceFile, name: string, hasGlobalName?: PrintHandlers["hasGlobalName"]): boolean {
    return !(hasGlobalName && hasGlobalName(name)) && !sourceFile.identifiers.has(name);
}

// Returns true if this node is missing from the actual source code. A 'missing' node is different
// from 'undefined/defined'. When a node is undefined (which can happen for optional nodes
// in the tree), it is definitely missing. However, a node may be defined, but still be
// missing.  This happens whenever the parser knows it needs to parse something, but can't
// get anything in the source code that it expects at that location. For example:
//
//          let a: ;
//
// Here, the Type in the Type-Annotation is not-optional (as there is a colon in the source
// code). So the parser will attempt to parse out a type, and will create an actual node.
// However, this node will be 'missing' in the sense that no actual source-code/tokens are
// contained within it.
/** @internal */
export function nodeIsMissing(node: Node | undefined): boolean {
    if (node === undefined) {
        return true;
    }

    return node.pos === node.end && node.pos >= 0 && node.kind !== SyntaxKind.EndOfFileToken;
}

/** @internal */
export function nodeIsPresent(node: Node | undefined): boolean {
    return !nodeIsMissing(node);
}

/**
 * Tests whether `child` is a grammar error on `parent`.
 * @internal
 */
export function isGrammarError(parent: Node, child: Node | NodeArray<Node>): boolean {
    if (isTypeParameterDeclaration(parent)) return child === parent.expression;
    if (isClassStaticBlockDeclaration(parent)) return child === parent.modifiers;
    if (isPropertySignature(parent)) return child === parent.initializer;
    if (isPropertyDeclaration(parent)) return child === parent.questionToken && isAutoAccessorPropertyDeclaration(parent);
    if (isPropertyAssignment(parent)) return child === parent.modifiers || child === parent.questionToken || child === parent.exclamationToken || isGrammarErrorElement(parent.modifiers, child, isModifierLike);
    if (isShorthandPropertyAssignment(parent)) return child === parent.equalsToken || child === parent.modifiers || child === parent.questionToken || child === parent.exclamationToken || isGrammarErrorElement(parent.modifiers, child, isModifierLike);
    if (isMethodDeclaration(parent)) return child === parent.exclamationToken;
    if (isConstructorDeclaration(parent)) return child === parent.typeParameters || child === parent.type || isGrammarErrorElement(parent.typeParameters, child, isTypeParameterDeclaration);
    if (isGetAccessorDeclaration(parent)) return child === parent.typeParameters || isGrammarErrorElement(parent.typeParameters, child, isTypeParameterDeclaration);
    if (isSetAccessorDeclaration(parent)) return child === parent.typeParameters || child === parent.type || isGrammarErrorElement(parent.typeParameters, child, isTypeParameterDeclaration);
    if (isNamespaceExportDeclaration(parent)) return child === parent.modifiers || isGrammarErrorElement(parent.modifiers, child, isModifierLike);
    return false;
}

function isGrammarErrorElement<T extends Node>(nodeArray: NodeArray<T> | undefined, child: Node | NodeArray<Node>, isElement: (node: Node) => node is T) {
    if (!nodeArray || isArray(child) || !isElement(child)) return false;
    return contains(nodeArray, child);
}

function insertStatementsAfterPrologue<T extends Statement>(to: T[], from: readonly T[] | undefined, isPrologueDirective: (node: Node) => boolean): T[] {
    if (from === undefined || from.length === 0) return to;
    let statementIndex = 0;
    // skip all prologue directives to insert at the correct position
    for (; statementIndex < to.length; ++statementIndex) {
        if (!isPrologueDirective(to[statementIndex])) {
            break;
        }
    }
    to.splice(statementIndex, 0, ...from);
    return to;
}

function insertStatementAfterPrologue<T extends Statement>(to: T[], statement: T | undefined, isPrologueDirective: (node: Node) => boolean): T[] {
    if (statement === undefined) return to;
    let statementIndex = 0;
    // skip all prologue directives to insert at the correct position
    for (; statementIndex < to.length; ++statementIndex) {
        if (!isPrologueDirective(to[statementIndex])) {
            break;
        }
    }
    to.splice(statementIndex, 0, statement);
    return to;
}

function isAnyPrologueDirective(node: Node) {
    return isPrologueDirective(node) || !!(getEmitFlags(node) & EmitFlags.CustomPrologue);
}

/**
 * Prepends statements to an array while taking care of prologue directives.
 *
 * @internal
 */
export function insertStatementsAfterStandardPrologue<T extends Statement>(to: T[], from: readonly T[] | undefined): T[] {
    return insertStatementsAfterPrologue(to, from, isPrologueDirective);
}

/** @internal */
export function insertStatementsAfterCustomPrologue<T extends Statement>(to: T[], from: readonly T[] | undefined): T[] {
    return insertStatementsAfterPrologue(to, from, isAnyPrologueDirective);
}

/**
 * Prepends statements to an array while taking care of prologue directives.
 *
 * @internal
 * @knipignore
 */
export function insertStatementAfterStandardPrologue<T extends Statement>(to: T[], statement: T | undefined): T[] {
    return insertStatementAfterPrologue(to, statement, isPrologueDirective);
}

/** @internal */
export function insertStatementAfterCustomPrologue<T extends Statement>(to: T[], statement: T | undefined): T[] {
    return insertStatementAfterPrologue(to, statement, isAnyPrologueDirective);
}

/**
 * Determine if the given comment is a triple-slash
 *
 * @return true if the comment is a triple-slash comment else false
 *
 * @internal
 */
export function isRecognizedTripleSlashComment(text: string, commentPos: number, commentEnd: number): boolean {
    // Verify this is /// comment, but do the regexp match only when we first can find /// in the comment text
    // so that we don't end up computing comment string and doing match for all // comments
    if (
        text.charCodeAt(commentPos + 1) === CharacterCodes.slash &&
        commentPos + 2 < commentEnd &&
        text.charCodeAt(commentPos + 2) === CharacterCodes.slash
    ) {
        const textSubStr = text.substring(commentPos, commentEnd);
        return fullTripleSlashReferencePathRegEx.test(textSubStr) ||
                fullTripleSlashAMDReferencePathRegEx.test(textSubStr) ||
                fullTripleSlashAMDModuleRegEx.test(textSubStr) ||
                fullTripleSlashReferenceTypeReferenceDirectiveRegEx.test(textSubStr) ||
                fullTripleSlashLibReferenceRegEx.test(textSubStr) ||
                defaultLibReferenceRegEx.test(textSubStr) ?
            true : false;
    }
    return false;
}

/** @internal */
export function isPinnedComment(text: string, start: number): boolean {
    return text.charCodeAt(start + 1) === CharacterCodes.asterisk &&
        text.charCodeAt(start + 2) === CharacterCodes.exclamation;
}

/** @internal */
export function createCommentDirectivesMap(sourceFile: SourceFile, commentDirectives: CommentDirective[]): CommentDirectivesMap {
    const directivesByLine = new Map(
        commentDirectives.map(commentDirective => [
            `${getLineAndCharacterOfPosition(sourceFile, commentDirective.range.end).line}`,
            commentDirective,
        ]),
    );

    const usedLines = new Map<string, boolean>();

    return { getUnusedExpectations, markUsed };

    function getUnusedExpectations() {
        return arrayFrom(directivesByLine.entries())
            .filter(([line, directive]) => directive.type === CommentDirectiveType.ExpectError && !usedLines.get(line))
            .map(([_, directive]) => directive);
    }

    function markUsed(line: number) {
        if (!directivesByLine.has(`${line}`)) {
            return false;
        }

        usedLines.set(`${line}`, true);
        return true;
    }
}

/** @internal */
export function getTokenPosOfNode(node: Node, sourceFile?: SourceFileLike, includeJsDoc?: boolean): number {
    // With nodes that have no width (i.e. 'Missing' nodes), we actually *don't*
    // want to skip trivia because this will launch us forward to the next token.
    if (nodeIsMissing(node)) {
        return node.pos;
    }

    if (isJSDocNode(node) || node.kind === SyntaxKind.JsxText) {
        // JsxText cannot actually contain comments, even though the scanner will think it sees comments
        return skipTrivia((sourceFile ?? getSourceFileOfNode(node)).text, node.pos, /*stopAfterLineBreak*/ false, /*stopAtComments*/ true);
    }

    if (includeJsDoc && hasJSDocNodes(node)) {
        return getTokenPosOfNode(node.jsDoc![0], sourceFile);
    }

    // For a syntax list, it is possible that one of its children has JSDocComment nodes, while
    // the syntax list itself considers them as normal trivia. Therefore if we simply skip
    // trivia for the list, we may have skipped the JSDocComment as well. So we should process its
    // first child to determine the actual position of its first token.
    if (node.kind === SyntaxKind.SyntaxList) {
        sourceFile ??= getSourceFileOfNode(node);
        const first = firstOrUndefined(getNodeChildren(node, sourceFile));
        if (first) {
            return getTokenPosOfNode(first, sourceFile, includeJsDoc);
        }
    }

    return skipTrivia(
        (sourceFile ?? getSourceFileOfNode(node)).text,
        node.pos,
        /*stopAfterLineBreak*/ false,
        /*stopAtComments*/ false,
        isInJSDoc(node),
    );
}

/** @internal */
export function getNonDecoratorTokenPosOfNode(node: Node, sourceFile?: SourceFileLike): number {
    const lastDecorator = !nodeIsMissing(node) && canHaveModifiers(node) ? findLast(node.modifiers, isDecorator) : undefined;
    if (!lastDecorator) {
        return getTokenPosOfNode(node, sourceFile);
    }

    return skipTrivia((sourceFile || getSourceFileOfNode(node)).text, lastDecorator.end);
}

/** @internal */
export function getSourceTextOfNodeFromSourceFile(sourceFile: SourceFile, node: Node, includeTrivia = false): string {
    return getTextOfNodeFromSourceText(sourceFile.text, node, includeTrivia);
}

function isJSDocTypeExpressionOrChild(node: Node): boolean {
    return !!findAncestor(node, isJSDocTypeExpression);
}

/** @internal */
export function isExportNamespaceAsDefaultDeclaration(node: Node): boolean {
    return !!(isExportDeclaration(node) && node.exportClause && isNamespaceExport(node.exportClause) && moduleExportNameIsDefault(node.exportClause.name));
}

/** @internal */
export function moduleExportNameTextUnescaped(node: ModuleExportName): string {
    return node.kind === SyntaxKind.StringLiteral ? node.text : unescapeLeadingUnderscores(node.escapedText);
}

/** @internal */
export function moduleExportNameTextEscaped(node: ModuleExportName): __String {
    return node.kind === SyntaxKind.StringLiteral ? escapeLeadingUnderscores(node.text) : node.escapedText;
}

/**
 * Equality checks against a keyword without underscores don't need to bother
 * to turn "__" into "___" or vice versa, since they will never be equal in
 * either case. So we can ignore those cases to improve performance.
 *
 * @internal
 */
export function moduleExportNameIsDefault(node: ModuleExportName): boolean {
    return (node.kind === SyntaxKind.StringLiteral ? node.text : node.escapedText) === InternalSymbolName.Default;
}

/** @internal */
export function getTextOfNodeFromSourceText(sourceText: string, node: Node, includeTrivia = false): string {
    if (nodeIsMissing(node)) {
        return "";
    }

    let text = sourceText.substring(includeTrivia ? node.pos : skipTrivia(sourceText, node.pos), node.end);

    if (isJSDocTypeExpressionOrChild(node)) {
        // strip space + asterisk at line start
        text = text.split(/\r\n|\n|\r/).map(line => line.replace(/^\s*\*/, "").trimStart()).join("\n");
    }

    return text;
}

/** @internal */
export function getTextOfNode(node: Node, includeTrivia = false): string {
    return getSourceTextOfNodeFromSourceFile(getSourceFileOfNode(node), node, includeTrivia);
}

function getPos(range: Node) {
    return range.pos;
}

/**
 * Note: it is expected that the `nodeArray` and the `node` are within the same file.
 * For example, searching for a `SourceFile` in a `SourceFile[]` wouldn't work.
 *
 * @internal
 */
export function indexOfNode(nodeArray: readonly Node[], node: Node): number {
    return binarySearch(nodeArray, node, getPos, compareValues);
}

/**
 * Gets flags that control emit behavior of a node.
 *
 * @internal
 */
export function getEmitFlags(node: Node): EmitFlags {
    const emitNode = node.emitNode;
    return emitNode && emitNode.flags || 0;
}

/**
 * Gets flags that control emit behavior of a node.
 *
 * @internal
 */
export function getInternalEmitFlags(node: Node): InternalEmitFlags {
    const emitNode = node.emitNode;
    return emitNode && emitNode.internalFlags || 0;
}

// Map from a type name, to a map of targets to array of features introduced to the type at that target.
/** @internal */
export type ScriptTargetFeatures = ReadonlyMap<string, ReadonlyMap<string, string[]>>;

// NOTE: We must reevaluate the target for upcoming features when each successive TC39 edition is ratified in
//       June of each year. This includes changes to `LanguageFeatureMinimumTarget`, `ScriptTarget`,
//       `ScriptTargetFeatures`, `CommandLineOptionOfCustomType`, transformers/esnext.ts, compiler/commandLineParser.ts,
//       compiler/utilitiesPublic.ts, and the contents of each lib/esnext.*.d.ts file.
/** @internal */
export const getScriptTargetFeatures: () => ScriptTargetFeatures = /* @__PURE__ */ memoize((): ScriptTargetFeatures =>
    new Map(Object.entries({
        Array: new Map(Object.entries({
            es2015: [
                "find",
                "findIndex",
                "fill",
                "copyWithin",
                "entries",
                "keys",
                "values",
            ],
            es2016: [
                "includes",
            ],
            es2019: [
                "flat",
                "flatMap",
            ],
            es2022: [
                "at",
            ],
            es2023: [
                "findLastIndex",
                "findLast",
                "toReversed",
                "toSorted",
                "toSpliced",
                "with",
            ],
        })),
        Iterator: new Map(Object.entries({
            es2015: emptyArray,
        })),
        AsyncIterator: new Map(Object.entries({
            es2015: emptyArray,
        })),
        ArrayBuffer: new Map(Object.entries({
            es2024: [
                "maxByteLength",
                "resizable",
                "resize",
                "detached",
                "transfer",
                "transferToFixedLength",
            ],
        })),
        Atomics: new Map(Object.entries({
            es2017: [
                "add",
                "and",
                "compareExchange",
                "exchange",
                "isLockFree",
                "load",
                "or",
                "store",
                "sub",
                "wait",
                "notify",
                "xor",
            ],
            es2024: [
                "waitAsync",
            ],
            esnext: [
                "pause",
            ],
        })),
        SharedArrayBuffer: new Map(Object.entries({
            es2017: [
                "byteLength",
                "slice",
            ],
            es2024: [
                "growable",
                "maxByteLength",
                "grow",
            ],
        })),
        AsyncIterable: new Map(Object.entries({
            es2018: emptyArray,
        })),
        AsyncIterableIterator: new Map(Object.entries({
            es2018: emptyArray,
        })),
        AsyncGenerator: new Map(Object.entries({
            es2018: emptyArray,
        })),
        AsyncGeneratorFunction: new 
