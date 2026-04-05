// Copyright (c) Microsoft Corporation.  All Rights Reserved.  See License.txt in the project root for license information.

namespace FSharp.Compiler.Symbols

open System
open System.IO

open Internal.Utilities.Library
open Internal.Utilities.Library.Extras
open FSharp.Core.Printf
open FSharp.Compiler
open FSharp.Compiler.AbstractIL.Diagnostics
open FSharp.Compiler.DiagnosticsLogger
open FSharp.Compiler.InfoReader
open FSharp.Compiler.Infos
open FSharp.Compiler.IO
open FSharp.Compiler.NameResolution
open FSharp.Compiler.Syntax.PrettyNaming
open FSharp.Compiler.Text
open FSharp.Compiler.Text.Range
open FSharp.Compiler.Text.Layout
open FSharp.Compiler.Text.TaggedText
open FSharp.Compiler.Xml
open FSharp.Compiler.TypedTree
open FSharp.Compiler.TypedTreeBasics
open FSharp.Compiler.TypedTreeOps
open FSharp.Compiler.TypeHierarchy
open FSharp.Compiler.TcGlobals

/// Describe a comment as either a block of text or a file+signature reference into an intellidoc file.
[<RequireQualifiedAccess>]

