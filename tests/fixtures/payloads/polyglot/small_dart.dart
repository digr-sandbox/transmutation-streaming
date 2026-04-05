// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'package:flutter/material.dart';
/// @docImport 'package:flutter/rendering.dart';
/// @docImport 'package:flutter/scheduler.dart';
///
/// @docImport 'binding.dart';
/// @docImport 'widget_inspector.dart';
library;

import 'dart:collection';
import 'dart:developer' show Timeline; // to disambiguate reference in dartdocs below

import 'package:flutter/foundation.dart';

import 'basic.dart';
import 'framework.dart';
import 'localizations.dart';
import 'lookup_boundary.dart';
import 'media_query.dart';
import 'overlay.dart';
import 'table.dart';

// Examples can assume:
// late BuildContext context;
// List<Widget> children = <Widget>[];
// List<Widget> items = <Widget>[];

// Any changes to this file should be reflected in the debugAssertAllWidgetVarsUnset()
// function below.

/// Log the dirty widgets that ar
