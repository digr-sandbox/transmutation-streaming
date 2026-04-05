import {
    combinePaths,
    ConditionalType,
    Debug,
    EvolvingArrayType,
    getLineAndCharacterOfPosition,
    getSourceFileOfNode,
    IndexedAccessType,
    IndexType,
    IntersectionType,
    LineAndCharacter,
    Node,
    ObjectFlags,
    Path,
    ReverseMappedType,
    SubstitutionType,
    timestamp,
    Type,
    TypeFlags,
    TypeReference,
    unescapeLeadingUnderscores,
    UnionType,
} from "./_namespaces/ts.js";
import * as performance from "./_namespaces/ts.performance.js";

/* Tracing events for the compiler. */

// should be used as tracing?.___
/** @internal */
export let tracing: typeof tracingEnabled | undefined;
// enable the above using startTracing()

/**
 * Do not use this directly; instead @see {tracing}.
 * @internal
 */
export namespace tracingEnabled {
    type Mode = "project" | "build" | "server";

    let fs: typeof import("fs");

    let traceCount = 0;
    let traceFd = 0;

    let mode: Mode;

 
