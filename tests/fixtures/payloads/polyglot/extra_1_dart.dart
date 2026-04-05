// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// @docImport 'dart:ui';
/// @docImport 'package:flutter/cupertino.dart';
/// @docImport 'package:flutter/material.dart';
/// @docImport 'package:flutter/widgets.dart';
library;

import 'dart:math' as math;
import 'dart:ui'
    as ui
    show Image, ImageFilter, SemanticsHitTestBehavior, SemanticsInputType, TextHeightBehavior;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'binding.dart';
import 'debug.dart';
import 'framework.dart';
import 'localizations.dart';
import 'visibility.dart';
import 'widget_span.dart';

export 'package:flutter/animation.dart';
export 'package:flutter/foundation.dart'
    show ChangeNotifier, FlutterErrorDetails, Listenable, TargetPlatform, ValueNotifier;
export 'package:flutter/painting.dart';
export 'package:flutter/rendering.dart'
    show
        AlignmentGeometryTween,
        AlignmentTween,
        Axis,
        BackdropKey,
        BoxConstraints,
        BoxConstraintsTransform,
        CrossAxisAlignment,
        CustomClipper,
        CustomPainter,
        CustomPainterSemantics,
        DecorationPosition,
        FlexFit,
        FlowDelegate,
        FlowPaintingContext,
        FractionalOffsetTween,
        HitTestBehavior,
        ImageFilterConfig,
        LayerLink,
        MainAxisAlignment,
        MainAxisSize,
        MouseCursor,
        MultiChildLayoutDelegate,
        PaintingContext,
        PointerCancelEvent,
        PointerCancelEventListener,
        PointerDownEvent,
        PointerDownEventListener,
        PointerEvent,
        PointerMoveEvent,
        PointerMoveEventListener,
        PointerUpEvent,
        PointerUpEventListener,
        RelativeRect,
        SemanticsBuilderCallback,
        ShaderCallback,
        ShapeBorderClipper,
        SingleChildLayoutDelegate,
        StackFit,
        SystemMouseCursors,
        TextOverflow,
        ValueChanged,
        ValueGetter,
        WrapAlignment,
        WrapCrossAlignment;
export 'package:flutter/services.dart' show AssetBundle;

// Examples can assume:
// class TestWidget extends StatelessWidget { const TestWidget({super.key}); @override Widget build(BuildContext context) => const Placeholder(); }
// late WidgetTester tester;
// late bool _visible;
// class Sky extends CustomPainter { @override void paint(Canvas c, Size s) {} @override bool shouldRepaint(Sky s) => false; }
// late BuildContext context;
// String userAvatarUrl = '';

// BIDIRECTIONAL TEXT SUPPORT

/// An [InheritedElement] that has hundreds of dependencies but will
/// infrequently change. This provides a performance tradeoff where building
/// the [Widget]s is faster but performing updates is slower.
///
/// |                     | _UbiquitousInheritedElement | InheritedElement |
/// |---------------------|------------------------------|------------------|
/// | insert (best case)  | O(1)                         | O(1)             |
/// | insert (worst case) | O(1)                         | O(n)             |
/// | search (best case)  | O(n)                         | O(1)             |
/// | search (worst case) | O(n)                         | O(n)             |
///
/// Insert happens when building the [Widget] tree, search happens when updating
/// [Widget]s.
class _UbiquitousInheritedElement extends InheritedElement {
  /// Creates an element that uses the given widget as its configuration.
  _UbiquitousInheritedElement(super.widget);

  @override
  void setDependencies(Element dependent, Object? value) {
    // This is where the cost of [InheritedElement] is incurred during build
    // time of the widget tree. Omitting this bookkeeping is where the
    // performance savings come from.
    assert(value == null);
  }

  @override
  Object? getDependencies(Element dependent) {
    return null;
  }

  @override
  void notifyClients(InheritedWidget oldWidget) {
    _recurseChildren(this, (Element element) {
      if (element.doesDependOnInheritedElement(this)) {
        notifyDependent(oldWidget, element);
      }
    });
  }

  static void _recurseChildren(Element element, ElementVisitor visitor) {
    element.visitChildren((Element child) {
      _recurseChildren(child, visitor);
    });
    visitor(element);
  }
}

/// See also:
///
///  * [_UbiquitousInheritedElement], the [Element] for [_UbiquitousInheritedWidget].
abstract class _UbiquitousInheritedWidget extends InheritedWidget {
  const _UbiquitousInheritedWidget({super.key, required super.child});

  @override
  InheritedElement createElement() => _UbiquitousInheritedElement(this);
}

/// A widget that determines the ambient directionality of text and
/// text-direction-sensitive render objects.
///
/// For example, [Padding] depends on the [Directionality] to resolve
/// [EdgeInsetsDirectional] objects into absolute [EdgeInsets] objects.
///
/// {@tool snippet}
///
/// This example uses a right-to-left [TextDirection] and draws a blue box with
/// a right margin of 8 pixels.
///
/// ```dart
/// Directionality(
///   textDirection: TextDirection.rtl,
///   child: Container(
///     margin: const EdgeInsetsDirectional.only(start: 8),
///     color: Colors.blue,
///   ),
/// )
/// ```
/// {@end-tool}
class Directionality extends _UbiquitousInheritedWidget {
  /// Creates a widget that determines the directionality of text and
  /// text-direction-sensitive render objects.
  const Directionality({super.key, required this.textDirection, required super.child});

  /// The text direction for this subtree.
  final TextDirection textDirection;

  /// The text direction from the closest instance of this class that encloses
  /// the given context.
  ///
  /// If there is no [Directionality] ancestor widget in the tree at the given
  /// context, then this will throw a descriptive [FlutterError] in debug mode
  /// and an exception in release mode.
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// TextDirection textDirection = Directionality.of(context);
  /// ```
  ///
  /// See also:
  ///
  ///  * [maybeOf], which will return null if no [Directionality] ancestor
  ///    widget is in the tree.
  static TextDirection of(BuildContext context) {
    assert(debugCheckHasDirectionality(context));
    final Directionality widget = context.dependOnInheritedWidgetOfExactType<Directionality>()!;
    return widget.textDirection;
  }

  /// The text direction from the closest instance of this class that encloses
  /// the given context.
  ///
  /// If there is no [Directionality] ancestor widget in the tree at the given
  /// context, then this will return null.
  ///
  /// Typical usage is as follows:
  ///
  /// ```dart
  /// TextDirection? textDirection = Directionality.maybeOf(context);
  /// ```
  ///
  /// See also:
  ///
  ///  * [of], which will throw if no [Directionality] ancestor widget is in the
  ///    tree.
  static TextDirection? maybeOf(BuildContext context) {
    final Directionality? widget = context.dependOnInheritedWidgetOfExactType<Directionality>();
    return widget?.textDirection;
  }

  @override
  bool updateShouldNotify(Directionality oldWidget) => textDirection != oldWidget.textDirection;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<TextDirection>('textDirection', textDirection));
  }
}

// PAINTING NODES

/// A widget that makes its child partially transparent.
///
/// This class paints its child into an intermediate buffer and then blends the
/// child back into the scene partially transparent.
///
/// For values of opacity other than 0.0 and 1.0, this class is relatively
/// expensive because it requires painting the child into an intermediate
/// buffer. For the value 0.0, the child is not painted at all. For the
/// value 1.0, the child is painted immediately without an intermediate buffer.
///
/// The presence of the intermediate buffer which has a transparent background
/// by default may cause some child widgets to behave differently. For example
/// a [BackdropFilter] child will only be able to apply its filter to the content
/// between this widget and the backdrop child and may require adjusting the
/// [BackdropFilter.blendMode] property to produce the desired results.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=9hltevOHQBw}
///
/// {@tool snippet}
///
/// This example shows some [Text] when the `_visible` member field is true, and
/// hides it when it is false:
///
/// ```dart
/// Opacity(
///   opacity: _visible ? 1.0 : 0.0,
///   child: const Text("Now you see me, now you don't!"),
/// )
/// ```
/// {@end-tool}
///
/// This is more efficient than adding and removing the child widget from the
/// tree on demand.
///
/// ## Performance considerations for opacity animation
///
/// Animating an [Opacity] widget directly causes the widget (and possibly its
/// subtree) to rebuild each frame, which is not very efficient. Consider using
/// one of these alternative widgets instead:
///
///  * [AnimatedOpacity], which uses an animation internally to efficiently
///    animate opacity.
///  * [FadeTransition], which uses a provided animation to efficiently animate
///    opacity.
///
/// ## Transparent image
///
/// If only a single [Image] or [Color] needs to be composited with an opacity
/// between 0.0 and 1.0, it's much faster to directly use them without [Opacity]
/// widgets.
///
/// For example, `Container(color: Color.fromRGBO(255, 0, 0, 0.5))` is much
/// faster than `Opacity(opacity: 0.5, child: Container(color: Colors.red))`.
///
/// {@tool snippet}
///
/// The following example draws an [Image] with 0.5 opacity without using
/// [Opacity]:
///
/// ```dart
/// Image.network(
///   'https://raw.githubusercontent.com/flutter/assets-for-api-docs/main/packages/diagrams/assets/blend_mode_destination.jpeg',
///   color: const Color.fromRGBO(255, 255, 255, 0.5),
///   colorBlendMode: BlendMode.modulate
/// )
/// ```
/// {@end-tool}
///
/// Directly drawing an [Image] or [Color] with opacity is faster than using
/// [Opacity] on top of them because [Opacity] could apply the opacity to a
/// group of widgets and therefore a costly offscreen buffer will be used.
/// Drawing content into the offscreen buffer may also trigger render target
/// switches and such switching is particularly slow in older GPUs.
///
/// ## Hit testing
///
/// Setting the [opacity] to zero does not prevent hit testing from being applied
/// to the descendants of the [Opacity] widget. This can be confusing for the
/// user, who may not see anything, and may believe the area of the interface
/// where the [Opacity] is hiding a widget to be non-interactive.
///
/// With certain widgets, such as [Flow], that compute their positions only when
/// they are painted, this can actually lead to bugs (from unexpected geometry
/// to exceptions), because those widgets are not painted by the [Opacity]
/// widget at all when the [opacity] is zero.
///
/// To avoid such problems, it is generally a good idea to use an
/// [IgnorePointer] widget when setting the [opacity] to zero. This prevents
/// interactions with any children in the subtree.
///
/// See also:
///
///  * [Visibility], which can hide a child more efficiently (albeit less
///    subtly, because it is either visible or hidden, rather than allowing
///    fractional opacity values). Specifically, the [Visibility.maintain]
///    constructor is equivalent to using an opacity widget with values of
///    `0.0` or `1.0`.
///  * [ShaderMask], which can apply more elaborate effects to its child.
///  * [Transform], which applies an arbitrary transform to its child widget at
///    paint time.
///  * [SliverOpacity], the sliver version of this widget.
class Opacity extends SingleChildRenderObjectWidget {
  /// Creates a widget that makes its child partially transparent.
  ///
  /// The [opacity] argument must be between zero and one, inclusive.
  const Opacity({
    super.key,
    required this.opacity,
    this.alwaysIncludeSemantics = false,
    super.child,
  }) : assert(opacity >= 0.0 && opacity <= 1.0);

  /// The fraction to scale the child's alpha value.
  ///
  /// An opacity of one is fully opaque. An opacity of zero is fully transparent
  /// (i.e., invisible).
  ///
  /// Values one and zero are painted with a fast path. Other values require
  /// painting the child into an intermediate buffer, which is expensive.
  final double opacity;

  /// Whether the semantic information of the children is always included.
  ///
  /// Defaults to false.
  ///
  /// When true, regardless of the opacity settings the child semantic
  /// information is exposed as if the widget were fully visible. This is
  /// useful in cases where labels may be hidden during animations that
  /// would otherwise contribute relevant semantics.
  final bool alwaysIncludeSemantics;

  @override
  RenderOpacity createRenderObject(BuildContext context) {
    return RenderOpacity(opacity: opacity, alwaysIncludeSemantics: alwaysIncludeSemantics);
  }

  @override
  void updateRenderObject(BuildContext context, RenderOpacity renderObject) {
    renderObject
      ..opacity = opacity
      ..alwaysIncludeSemantics = alwaysIncludeSemantics;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('opacity', opacity));
    properties.add(
      FlagProperty(
        'alwaysIncludeSemantics',
        value: alwaysIncludeSemantics,
        ifTrue: 'alwaysIncludeSemantics',
      ),
    );
  }
}

/// A widget that applies a mask generated by a [Shader] to its child.
///
/// For example, [ShaderMask] can be used to gradually fade out the edge
/// of a child by using a [RadialGradient] mask.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=7sUL66pTQ7Q}
///
/// {@tool snippet}
///
/// This example makes the text look like it is on fire:
///
/// ```dart
/// ShaderMask(
///   shaderCallback: (Rect bounds) {
///     return RadialGradient(
///       center: Alignment.topLeft,
///       radius: 1.0,
///       colors: <Color>[Colors.yellow, Colors.deepOrange.shade900],
///       tileMode: TileMode.mirror,
///     ).createShader(bounds);
///   },
///   child: const Text(
///     "I'm burning the memories",
///     style: TextStyle(color: Colors.white),
///   ),
/// )
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [Opacity], which can apply a uniform alpha effect to its child.
///  * [CustomPaint], which lets you draw directly on the canvas.
///  * [DecoratedBox], for another approach at decorating child widgets.
///  * [BackdropFilter], which applies an image filter to the background.
class ShaderMask extends SingleChildRenderObjectWidget {
  /// Creates a widget that applies a mask generated by a [Shader] to its child.
  const ShaderMask({
    super.key,
    required this.shaderCallback,
    this.blendMode = BlendMode.modulate,
    super.child,
  });

  /// Called to create the [dart:ui.Shader] that generates the mask.
  ///
  /// The shader callback is called with the current size of the child so that
  /// it can customize the shader to the size and location of the child.
  ///
  /// Typically this will use a [LinearGradient], [RadialGradient], or
  /// [SweepGradient] to create the [dart:ui.Shader], though the
  /// [dart:ui.ImageShader] class could also be used.
  final ShaderCallback shaderCallback;

  /// The [BlendMode] to use when applying the shader to the child.
  ///
  /// The default, [BlendMode.modulate], is useful for applying an alpha blend
  /// to the child. Other blend modes can be used to create other effects.
  final BlendMode blendMode;

  @override
  RenderShaderMask createRenderObject(BuildContext context) {
    return RenderShaderMask(shaderCallback: shaderCallback, blendMode: blendMode);
  }

  @override
  void updateRenderObject(BuildContext context, RenderShaderMask renderObject) {
    renderObject
      ..shaderCallback = shaderCallback
      ..blendMode = blendMode;
  }
}

/// A widget that establishes a shared backdrop layer for all child [BackdropFilter]
/// widgets that opt into using it.
///
/// Sharing a backdrop filter layer will improve the performance of multiple
/// backdrop filters. To opt into using a shared [BackdropGroup], the special
/// [BackdropFilter.grouped] constructor must be used.
class BackdropGroup extends InheritedWidget {
  /// Create a new [BackdropGroup] widget.
  BackdropGroup({super.key, required super.child, BackdropKey? backdropKey})
    : backdropKey = backdropKey ?? BackdropKey();

  /// The backdrop key this backdrop group will use with shared child layers.
  final BackdropKey backdropKey;

  @override
  bool updateShouldNotify(covariant BackdropGroup oldWidget) {
    return oldWidget.backdropKey != backdropKey;
  }

  /// Look up the nearest [BackdropGroup], or `null` if there is not one.
  static BackdropGroup? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BackdropGroup>();
  }
}

/// A widget that applies a filter to the existing painted content and then
/// paints [child].
///
/// The filter will be applied to all the area within its parent or ancestor
/// widget's clip. If there's no clip, the filter will be applied to the full
/// screen.
///
/// The results of the filter will be blended back into the background using
/// the [blendMode] parameter.
/// {@template flutter.widgets.BackdropFilter.blendMode}
/// The only value for [blendMode] that is supported on all platforms is
/// [BlendMode.srcOver] which works well for most scenes. But that value may
/// produce surprising results when a parent of the [BackdropFilter] uses a
/// temporary buffer, or save layer, as does an [Opacity] widget. In that
/// situation, a value of [BlendMode.src] can produce more pleasing results.
/// {@endtemplate}
///
/// Multiple backdrop filters can be combined into a single rendering operation
/// by the Flutter engine if these backdrop filters widgets all share a common
/// [BackdropKey]. The backdrop key uniquely identifies the input for a backdrop
/// filter, and when shared, indicates the filtering can be performed once. This
/// can significantly reduce the overhead of using multiple backdrop filters in
/// a scene. The key can either be provided manually via the `backdropKey`
/// constructor parameter or looked up from a [BackdropGroup] inherited widget
/// via the `.grouped` constructor.
///
/// Backdrop filters that overlap with each other should not use the same
/// backdrop key, otherwise the results may look as if only one filter is
/// applied in the overlapping regions.
///
/// The following snippet demonstrates how to use the backdrop key to allow each
/// list item to have an efficient blur. The engine will perform only one
/// backdrop blur but the results will be visually identical to multiple blurs.
///
/// ```dart
///  Widget build(BuildContext context) {
///    return BackdropGroup(
///      child: ListView.builder(
///        itemCount: 60,
///        itemBuilder: (BuildContext context, int index) {
///          return ClipRect(
///            child: BackdropFilter.grouped(
///              filter: ui.ImageFilter.blur(
///                sigmaX: 40,
///                sigmaY: 40,
///              ),
///              child: Container(
///                color: Colors.black.withValues(alpha: 0.2),
///                height: 200,
///                child: const Text('Blur item'),
///              ),
///            ),
///          );
///       }
///     ),
///   );
/// }
/// ```
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=dYRs7Q1vfYI}
///
/// {@tool snippet}
///
/// If the [BackdropFilter] needs to be applied to an area that exactly matches
/// its child, wraps the [BackdropFilter] with a clip widget that clips exactly
/// to that child.
///
/// ```dart
/// Stack(
///   fit: StackFit.expand,
///   children: <Widget>[
///     Text('0' * 10000),
///     Center(
///       child: ClipRect(  // <-- clips to the 200x200 [Container] below
///         child: BackdropFilter(
///           filter: ui.ImageFilter.blur(
///             sigmaX: 5.0,
///             sigmaY: 5.0,
///           ),
///           child: Container(
///             alignment: Alignment.center,
///             width: 200.0,
///             height: 200.0,
///             child: const Text('Hello World'),
///           ),
///         ),
///       ),
///     ),
///   ],
/// )
/// ```
/// {@end-tool}
///
/// This effect is relatively expensive, especially if the filter is non-local,
/// such as a blur.
///
/// If all you want to do is apply an [ImageFilter] to a single widget
/// (as opposed to applying the filter to everything _beneath_ a widget), use
/// [ImageFiltered] instead. For that scenario, [ImageFiltered] is both
/// easier to use and less expensive than [BackdropFilter].
///
/// {@tool snippet}
///
/// This example shows how the common case of applying a [BackdropFilter] blur
/// to a single sibling can be replaced with an [ImageFiltered] widget. This code
/// is generally simpler and the performance will be improved dramatically for
/// complex filters like blurs.
///
/// The implementation below is unnecessarily expensive.
///
/// ```dart
///  Widget buildBackdrop() {
///    return Stack(
///      children: <Widget>[
///        Positioned.fill(child: Image.asset('image.png')),
///        Positioned.fill(
///          child: BackdropFilter(
///            filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
///          ),
///        ),
///      ],
///    );
///  }
/// ```
/// {@end-tool}
/// {@tool snippet}
///
/// Instead consider the following approach which directly applies a blur
/// to the child widget.
///
/// ```dart
///  Widget buildFilter() {
///    return ImageFiltered(
///      imageFilter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
///      child: Image.asset('image.png'),
///    );
///  }
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [ImageFiltered], which applies an [ImageFilter] to its child.
///  * [DecoratedBox], which draws a background under (or over) a widget.
///  * [Opacity], which changes the opacity of the widget itself.
///  * https://flutter.dev/go/ios-platformview-backdrop-filter-blur for details and restrictions when an iOS PlatformView needs to be blurred.
class BackdropFilter extends SingleChildRenderObjectWidget {
  /// Creates a backdrop filter.
  ///
  /// The [blendMode] argument will default to [BlendMode.srcOver] and must not be
  /// null if provided.
  ///
  /// Exactly one of [filter] or [filterConfig] must be provided.
  /// Providing both or neither will result in an assertion error.
  const BackdropFilter({
    super.key,
    this.filter,
    this.filterConfig,
    super.child,
    this.blendMode = BlendMode.srcOver,
    this.enabled = true,
    this.backdropGroupKey,
  }) : assert(
         filter != null || filterConfig != null,
         'Either filter or filterConfig must be provided.',
       ),
       assert(
         filter == null || filterConfig == null,
         'Cannot provide both a filter and a filterConfig.',
       ),
       _useSharedKey = false;

  /// Creates a backdrop filter that groups itself with the nearest parent
  /// [BackdropGroup].
  ///
  /// The [blendMode] argument will default to [BlendMode.srcOver] and must not be
  /// null if provided.
  ///
  /// This constructor will automatically look up the nearest [BackdropGroup]
  /// and will share the backdrop input with sibling and child [BackdropFilter]
  /// widgets.
  ///
  /// Exactly one of [filter] or [filterConfig] must be provided.
  /// Providing both or neither will result in an assertion error.
  const BackdropFilter.grouped({
    super.key,
    this.filter,
    this.filterConfig,
    super.child,
    this.blendMode = BlendMode.srcOver,
    this.enabled = true,
  }) : assert(
         filter != null || filterConfig != null,
         'Either filter or filterConfig must be provided.',
       ),
       assert(
         filter == null || filterConfig == null,
         'Cannot provide both a filter and a filterConfig.',
       ),
       backdropGroupKey = null,
       _useSharedKey = true;

  /// The image filter to apply to the existing painted content before painting the child.
  ///
  /// For example, consider using [ImageFilter.blur] to create a backdrop
  /// blur effect.
  ///
  /// The [filter] parameter is equivalent to [filterConfig] (with the help of
  /// the [ImageFilterConfig.new] constructor), except for features only
  /// supported by [ImageFilterConfig] (such as the `bounds` parameter in
  /// [ImageFilterConfig.blur]).
  final ui.ImageFilter? filter;

  /// The configuration for the image filter to apply to the existing painted content.
  ///
  /// For example, consider using [ImageFilterConfig.blur] to create a backdrop
  /// blur effect.
  ///
  /// The [filterConfig] parameter is equivalent to [filter] (with the help of
  /// the [ImageFilterConfig.new] constructor), except for features only
  /// supported by [ImageFilterConfig] (such as the `bounds` parameter in
  /// [ImageFilterConfig.blur]).
  final ImageFilterConfig? filterConfig;

  /// The blend mode to use to apply the filtered background content onto the background
  /// surface.
  ///
  /// {@macro flutter.widgets.BackdropFilter.blendMode}
  final BlendMode blendMode;

  /// Whether or not to apply the backdrop filter operation to the child of this
  /// widget.
  ///
  /// Prefer setting enabled to `false` instead of creating a "no-op" filter
  /// type for performance reasons.
  final bool enabled;

  /// The [BackdropKey] that identifies the backdrop this filter will apply to.
  ///
  /// The default value for the backdrop key is `null`.
  final BackdropKey? backdropGroupKey;

  // Whether to look up the [backdropKey] from a parent [BackdropGroup].
  final bool _useSharedKey;

  BackdropKey? _getBackdropGroupKey(BuildContext context) {
    if (_useSharedKey) {
      return BackdropGroup.of(context)?.backdropKey;
    }
    return backdropGroupKey;
  }

  ImageFilterConfig get _effectiveFilterConfig {
    return filterConfig ?? ImageFilterConfig(filter!);
  }

  @override
  RenderBackdropFilter createRenderObject(BuildContext context) {
    return RenderBackdropFilter(
      filterConfig: _effectiveFilterConfig,
      blendMode: blendMode,
      enabled: enabled,
      backdropKey: _getBackdropGroupKey(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderBackdropFilter renderObject) {
    renderObject
      ..filterConfig = _effectiveFilterConfig
      ..enabled = enabled
      ..blendMode = blendMode
      ..backdropKey = _getBackdropGroupKey(context);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<ui.ImageFilter>('filter', filter, defaultValue: null));
    properties.add(
      DiagnosticsProperty<ImageFilterConfig>('filterConfig', filterConfig, defaultValue: null),
    );
    properties.add(EnumProperty<BlendMode>('blendMode', blendMode));
    properties.add(FlagProperty('enabled', value: enabled, ifTrue: 'enabled'));
  }
}

/// A widget that provides a canvas on which to draw during the paint phase.
///
/// When asked to paint, [CustomPaint] first asks its [painter] to paint on the
/// current canvas, then it paints its child, and then, after painting its
/// child, it asks its [foregroundPainter] to paint. The coordinate system of the
/// canvas matches the coordinate system of the [CustomPaint] object. The
/// painters are expected to paint within a rectangle starting at the origin and
/// encompassing a region of the given size. (If the painters paint outside
/// those bounds, there might be insufficient memory allocated to rasterize the
/// painting commands and the resulting behavior is undefined.) To enforce
/// painting within those bounds, consider wrapping this [CustomPaint] with a
/// [ClipRect] widget.
///
/// Painters are implemented by subclassing [CustomPainter].
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=kp14Y4uHpHs}
///
/// Because custom paint calls its painters during paint, you cannot call
/// `setState` or `markNeedsLayout` during the callback (the layout for this
/// frame has already happened).
///
/// Custom painters normally size themselves to their [child]. If they do not
/// have a child, they attempt to size themselves to the specified [size], which
/// defaults to [Size.zero]. The parent [may enforce constraints on this
/// size](https://docs.flutter.dev/ui/layout/constraints).
///
/// The [isComplex] and [willChange] properties are hints to the compositor's
/// raster cache.
///
/// {@tool snippet}
///
/// This example shows how the sample custom painter shown at [CustomPainter]
/// could be used in a [CustomPaint] widget to display a background to some
/// text.
///
/// ```dart
/// CustomPaint(
///   painter: Sky(),
///   child: const Center(
///     child: Text(
///       'Once upon a time...',
///       style: TextStyle(
///         fontSize: 40.0,
///         fontWeight: FontWeight.w900,
///         color: Color(0xFFFFFFFF),
///       ),
///     ),
///   ),
/// )
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [CustomPainter], the class to extend when creating custom painters.
///  * [Canvas], the class that a custom painter uses to paint.
class CustomPaint extends SingleChildRenderObjectWidget {
  /// Creates a widget that delegates its painting.
  const CustomPaint({
    super.key,
    this.painter,
    this.foregroundPainter,
    this.size = Size.zero,
    this.isComplex = false,
    this.willChange = false,
    super.child,
  }) : assert(painter != null || foregroundPainter != null || (!isComplex && !willChange));

  /// The painter that paints before the children.
  final CustomPainter? painter;

  /// The painter that paints after the children.
  final CustomPainter? foregroundPainter;

  /// The size that this [CustomPaint] should aim for, given the layout
  /// constraints, if there is no child.
  ///
  /// Defaults to [Size.zero].
  ///
  /// If there's a child, this is ignored, and the size of the child is used
  /// instead.
  final Size size;

  /// Whether the painting is complex enough to benefit from caching.
  ///
  /// The compositor contains a raster cache that holds bitmaps of layers in
  /// order to avoid the cost of repeatedly rendering those layers on each
  /// frame. If this flag is not set, then the compositor will apply its own
  /// heuristics to decide whether the layer containing this widget is complex
  /// enough to benefit from caching.
  ///
  /// This flag can't be set to true if both [painter] and [foregroundPainter]
  /// are null because this flag will be ignored in such case.
  final bool isComplex;

  /// Whether the raster cache should be told that this painting is likely
  /// to change in the next frame.
  ///
  /// This hint tells the compositor not to cache the layer containing this
  /// widget because the cache will not be used in the future. If this hint is
  /// not set, the compositor will apply its own heuristics to decide whether
  /// the layer is likely to be reused in the future.
  ///
  /// This flag can't be set to true if both [painter] and [foregroundPainter]
  /// are null because this flag will be ignored in such case.
  final bool willChange;

  @override
  RenderCustomPaint createRenderObject(BuildContext context) {
    return RenderCustomPaint(
      painter: painter,
      foregroundPainter: foregroundPainter,
      preferredSize: size,
      isComplex: isComplex,
      willChange: willChange,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderCustomPaint renderObject) {
    renderObject
      ..painter = painter
      ..foregroundPainter = foregroundPainter
      ..preferredSize = size
      ..isComplex = isComplex
      ..willChange = willChange;
  }

  @override
  void didUnmountRenderObject(RenderCustomPaint renderObject) {
    renderObject
      ..painter = null
      ..foregroundPainter = null;
  }
}

/// A widget that clips its child using a rectangle.
///
/// By default, [ClipRect] prevents its child from painting outside its
/// bounds, but the size and location of the clip rect can be customized using a
/// custom [clipper].
///
/// [ClipRect] is commonly used with these widgets, which commonly paint outside
/// their bounds:
///
///  * [CustomPaint]
///  * [CustomSingleChildLayout]
///  * [CustomMultiChildLayout]
///  * [Align] and [Center] (e.g., if [Align.widthFactor] or
///    [Align.heightFactor] is less than 1.0).
///  * [OverflowBox]
///  * [SizedOverflowBox]
///
/// {@tool snippet}
///
/// For example, by combining a [ClipRect] with an [Align], one can show just
/// the top half of an [Image]:
///
/// ```dart
/// ClipRect(
///   child: Align(
///     alignment: Alignment.topCenter,
///     heightFactor: 0.5,
///     child: Image.network(userAvatarUrl),
///   ),
/// )
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [CustomClipper], for information about creating custom clips.
///  * [ClipRRect], for a clip with rounded corners.
///  * [ClipOval], for an elliptical clip.
///  * [ClipPath], for an arbitrarily shaped clip.
class ClipRect extends SingleChildRenderObjectWidget {
  /// Creates a rectangular clip.
  ///
  /// If [clipper] is null, the clip will match the layout size and position of
  /// the child.
  ///
  /// If [clipBehavior] is [Clip.none], no clipping will be applied.
  const ClipRect({super.key, this.clipper, this.clipBehavior = Clip.hardEdge, super.child});

  /// If non-null, determines which clip to use.
  final CustomClipper<Rect>? clipper;

  /// {@macro flutter.rendering.ClipRectLayer.clipBehavior}
  ///
  /// Defaults to [Clip.hardEdge].
  final Clip clipBehavior;

  @override
  RenderClipRect createRenderObject(BuildContext context) {
    return RenderClipRect(clipper: clipper, clipBehavior: clipBehavior);
  }

  @override
  void updateRenderObject(BuildContext context, RenderClipRect renderObject) {
    renderObject
      ..clipper = clipper
      ..clipBehavior = clipBehavior;
  }

  @override
  void didUnmountRenderObject(RenderClipRect renderObject) {
    renderObject.clipper = null;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<CustomClipper<Rect>>('clipper', clipper, defaultValue: null),
    );
  }
}

/// A widget that clips its child using a rounded rectangle.
///
/// By default, [ClipRRect] uses its own bounds as the base rectangle for the
/// clip, but the size and location of the clip can be customized using a custom
/// [clipper].
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=eI43jkQkrvs}
///
/// {@tool dartpad}
/// This example shows various [ClipRRect]s applied to containers.
///
/// ** See code in examples/api/lib/widgets/basic/clip_rrect.0.dart **
/// {@end-tool}
///
/// ## Troubleshooting
///
/// ### Why doesn't my [ClipRRect] child have rounded corners?
///
/// When a [ClipRRect] is bigger than the child it contains, its rounded corners
/// could be drawn in unexpected positions. Make sure that [ClipRRect] and its child
/// have the same bounds (by shrinking the [ClipRRect] with a [FittedBox] or by
/// growing the child).
///
/// {@tool dartpad}
/// This example shows a [ClipRRect] that adds round corners to an image.
///
/// ** See code in examples/api/lib/widgets/basic/clip_rrect.1.dart **
/// {@end-tool}
///
/// See also:
///
///  * [CustomClipper], for information about creating custom clips.
///  * [ClipRect], for more efficient clips without rounded corners.
///  * [ClipRSuperellipse], for a similar clipping shape with smoother
///    transitions between the straight sides and the rounded corners. This
///    shape closely matches the rounded rectangles commonly used in Appleâ€™s
///    design language, resembling the `RoundedRectangle` shape in SwiftUI with
///    the `.continuous` corner style.
///  * [ClipOval], for an elliptical clip.
///  * [ClipPath], for an arbitrarily shaped clip.
class ClipRRect extends SingleChildRenderObjectWidget {
  /// Creates a rounded-rectangular clip.
  ///
  /// The [borderRadius] defaults to [BorderRadius.zero], i.e. a rectangle with
  /// right-angled corners.
  ///
  /// If [clipper] is non-null, then [borderRadius] is ignored.
  ///
  /// If [clipBehavior] is [Clip.none], no clipping will be applied.
  const ClipRRect({
    super.key,
    this.borderRadius = BorderRadius.zero,
    this.clipper,
    this.clipBehavior = Clip.antiAlias,
    super.child,
  });

  /// The border radius of the rounded corners.
  ///
  /// Values are clamped so that horizontal and vertical radii sums do not
  /// exceed width/height.
  ///
  /// This value is ignored if [clipper] is non-null.
  final BorderRadiusGeometry borderRadius;

  /// If non-null, determines which clip to use.
  final CustomClipper<RRect>? clipper;

  /// {@macro flutter.rendering.ClipRectLayer.clipBehavior}
  ///
  /// Defaults to [Clip.antiAlias].
  final Clip clipBehavior;

  @override
  RenderClipRRect createRenderObject(BuildContext context) {
    return RenderClipRRect(
      borderRadius: borderRadius,
      clipper: clipper,
      clipBehavior: clipBehavior,
      textDirection: Directionality.maybeOf(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderClipRRect renderObject) {
    renderObject
      ..borderRadius = borderRadius
      ..clipBehavior = clipBehavior
      ..clipper = clipper
      ..textDirection = Directionality.maybeOf(context);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<BorderRadiusGeometry>(
        'borderRadius',
        borderRadius,
        showName: false,
        defaultValue: null,
      ),
    );
    properties.add(
      DiagnosticsProperty<CustomClipper<RRect>>('clipper', clipper, defaultValue: null),
    );
  }
}

/// A widget that clips its child using a rounded superellipse.
///
/// A rounded superellipse is a shape similar to a typical rounded rectangle
/// ([ClipRRect]), but with smoother transitions between the straight sides and
/// the rounded corners. It resembles the `RoundedRectangle` shape in SwiftUI
/// with the `.continuous` corner style. Technically, it is created by replacing
/// the four corners of a superellipse (also known as a LamÃ© curve) with
/// circular arcs.
///
/// By default, [ClipRSuperellipse] uses its own bounds as the base rectangle
/// for the clip, but the size and location of the clip can be customized using
/// a custom [clipper].
///
/// See also:
///
///  * [CustomClipper], for information about creating custom clips.
///  * [ClipRect], for more efficient clips without rounded corners.
///  * [ClipRRect], for a typical rounded rectangle, which is created by
///    replacing the four corners of a rectangle with circular arcs.
///  * [ClipOval], for an elliptical clip.
///  * [ClipPath], for an arbitrarily shaped clip.
class ClipRSuperellipse extends SingleChildRenderObjectWidget {
  /// Creates a rounded-superellipse clip.
  ///
  /// The [borderRadius] defaults to [BorderRadius.zero], i.e. a rectangle with
  /// right-angled corners.
  ///
  /// If [clipBehavior] is [Clip.none], no clipping will be applied.
  const ClipRSuperellipse({
    super.key,
    this.borderRadius = BorderRadius.zero,
    this.clipper,
    this.clipBehavior = Clip.antiAlias,
    super.child,
  });

  /// The border radius of the rounded corners.
  ///
  /// Values are clamped so that horizontal and vertical radii sums do not
  /// exceed width/height.
  ///
  /// This value is ignored if [clipper] is non-null.
  final BorderRadiusGeometry borderRadius;

  /// If non-null, determines which clip to use.
  final CustomClipper<RSuperellipse>? clipper;

  /// {@macro flutter.rendering.ClipRectLayer.clipBehavior}
  ///
  /// Defaults to [Clip.antiAlias].
  final Clip clipBehavior;

  @override
  RenderClipRSuperellipse createRenderObject(BuildContext context) {
    return RenderClipRSuperellipse(
      borderRadius: borderRadius,
      clipBehavior: clipBehavior,
      clipper: clipper,
      textDirection: Directionality.maybeOf(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderClipRSuperellipse renderObject) {
    renderObject
      ..borderRadius = borderRadius
      ..clipBehavior = clipBehavior
      ..clipper = clipper
      ..textDirection = Directionality.maybeOf(context);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<BorderRadiusGeometry>(
        'borderRadius',
        borderRadius,
        showName: false,
        defaultValue: null,
      ),
    );
    properties.add(
      DiagnosticsProperty<CustomClipper<RSuperellipse>>('clipper', clipper, defaultValue: null),
    );
  }
}

/// A widget that clips its child using an oval.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=vzWWDO6whIM}
///
/// By default, inscribes an axis-aligned oval into its layout dimensions and
/// prevents its child from painting outside that oval, but the size and
/// location of the clip oval can be customized using a custom [clipper].
///
/// {@tool snippet}
///
/// This example clips an image of a cat using an oval.
///
/// ```dart
/// ClipOval(
///   child: Image.asset('images/cat.png'),
/// )
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [CustomClipper], for information about creating custom clips.
///  * [ClipRect], for more efficient clips without rounded corners.
///  * [ClipRRect], for a clip with rounded corners.
///  * [ClipPath], for an arbitrarily shaped clip.
class ClipOval extends SingleChildRenderObjectWidget {
  /// Creates an oval-shaped clip.
  ///
  /// If [clipper] is null, the oval will be inscribed into the layout size and
  /// position of the child.
  ///
  /// If [clipBehavior] is [Clip.none], no clipping will be applied.
  const ClipOval({super.key, this.clipper, this.clipBehavior = Clip.antiAlias, super.child});

  /// If non-null, determines which clip to use.
  ///
  /// The delegate returns a rectangle that describes the axis-aligned
  /// bounding box of the oval. The oval's axes will themselves also
  /// be axis-aligned.
  ///
  /// If the [clipper] delegate is null, then the oval uses the
  /// widget's bounding box (the layout dimensions of the render
  /// object) instead.
  final CustomClipper<Rect>? clipper;

  /// {@macro flutter.rendering.ClipRectLayer.clipBehavior}
  ///
  /// Defaults to [Clip.antiAlias].
  final Clip clipBehavior;

  @override
  RenderClipOval createRenderObject(BuildContext context) {
    return RenderClipOval(clipper: clipper, clipBehavior: clipBehavior);
  }

  @override
  void updateRenderObject(BuildContext context, RenderClipOval renderObject) {
    renderObject
      ..clipper = clipper
      ..clipBehavior = clipBehavior;
  }

  @override
  void didUnmountRenderObject(RenderClipOval renderObject) {
    renderObject.clipper = null;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<CustomClipper<Rect>>('clipper', clipper, defaultValue: null),
    );
  }
}

/// A widget that clips its child using a path.
///
/// Calls a callback on a delegate whenever the widget is to be
/// painted. The callback returns a path and the widget prevents the
/// child from painting outside the path.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=oAUebVIb-7s}
///
/// Clipping to a path is expensive. Certain shapes have more
/// optimized widgets:
///
///  * To clip to a rectangle, consider [ClipRect].
///  * To clip to an oval or circle, consider [ClipOval].
///  * To clip to a rounded rectangle, consider [ClipRRect].
///
/// To clip to a particular [ShapeBorder], consider using either the
/// [ClipPath.shape] static method or the [ShapeBorderClipper] custom clipper
/// class.
class ClipPath extends SingleChildRenderObjectWidget {
  /// Creates a path clip.
  ///
  /// If [clipper] is null, the clip will be a rectangle that matches the layout
  /// size and location of the child. However, rather than use this default,
  /// consider using a [ClipRect], which can achieve the same effect more
  /// efficiently.
  ///
  /// If [clipBehavior] is [Clip.none], no clipping will be applied.
  const ClipPath({super.key, this.clipper, this.clipBehavior = Clip.antiAlias, super.child});

  /// Creates a shape clip.
  ///
  /// Uses a [ShapeBorderClipper] to configure the [ClipPath] to clip to the
  /// given [ShapeBorder].
  static Widget shape({
    Key? key,
    required ShapeBorder shape,
    Clip clipBehavior = Clip.antiAlias,
    Widget? child,
  }) {
    return Builder(
      key: key,
      builder: (BuildContext context) {
        return ClipPath(
          clipper: ShapeBorderClipper(shape: shape, textDirection: Directionality.maybeOf(context)),
          clipBehavior: clipBehavior,
          child: child,
        );
      },
    );
  }

  /// If non-null, determines which clip to use.
  ///
  /// The default clip, which is used if this property is null, is the
  /// bounding box rectangle of the widget. [ClipRect] is a more
  /// efficient way of obtaining that effect.
  final CustomClipper<Path>? clipper;

  /// {@macro flutter.rendering.ClipRectLayer.clipBehavior}
  ///
  /// Defaults to [Clip.antiAlias].
  final Clip clipBehavior;

  @override
  RenderClipPath createRenderObject(BuildContext context) {
    return RenderClipPath(clipper: clipper, clipBehavior: clipBehavior);
  }

  @override
  void updateRenderObject(BuildContext context, RenderClipPath renderObject) {
    renderObject
      ..clipper = clipper
      ..clipBehavior = clipBehavior;
  }

  @override
  void didUnmountRenderObject(RenderClipPath renderObject) {
    renderObject.clipper = null;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      DiagnosticsProperty<CustomClipper<Path>>('clipper', clipper, defaultValue: null),
    );
  }
}

/// A widget representing a physical layer that clips its children to a shape.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=XgUOSS30OQk}
///
/// Physical layers cast shadows based on an [elevation] which is nominally in
/// logical pixels, coming vertically out of the rendering surface.
///
/// For shapes that cannot be expressed as a rectangle with rounded corners use
/// [PhysicalShape].
///
/// See also:
///
///  * [AnimatedPhysicalModel], which animates property changes smoothly over
///    a given duration.
///  * [DecoratedBox], which can apply more arbitrary shadow effects.
///  * [ClipRect], which applies a clip to its child.
class PhysicalModel extends SingleChildRenderObjectWidget {
  /// Creates a physical model with a rounded-rectangular clip.
  ///
  /// The [color] is required; physical things have a color.
  ///
  /// The [shape], [elevation], [color], [clipBehavior], and [shadowColor] must
  /// not be null. Additionally, the [elevation] must be non-negative.
  const PhysicalModel({
    super.key,
    this.shape = BoxShape.rectangle,
    this.clipBehavior = Clip.none,
    this.borderRadius,
    this.elevation = 0.0,
    required this.color,
    this.shadowColor = const Color(0xFF000000),
    super.child,
  }) : assert(elevation >= 0.0);

  /// The type of shape.
  final BoxShape shape;

  /// {@macro flutter.material.Material.clipBehavior}
  ///
  /// Defaults to [Clip.none].
  final Clip clipBehavior;

  /// The border radius of the rounded corners.
  ///
  /// Values are clamped so that horizontal and vertical radii sums do not
  /// exceed width/height.
  ///
  /// This is ignored if the [shape] is not [BoxShape.rectangle].
  final BorderRadius? borderRadius;

  /// The z-coordinate relative to the parent at which to place this physical
  /// object.
  ///
  /// The value is non-negative.
  final double elevation;

  /// The background color.
  final Color color;

  /// The shadow color.
  final Color shadowColor;

  @override
  RenderPhysicalModel createRenderObject(BuildContext context) {
    return RenderPhysicalModel(
      shape: shape,
      clipBehavior: clipBehavior,
      borderRadius: borderRadius,
      elevation: elevation,
      color: color,
      shadowColor: shadowColor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderPhysicalModel renderObject) {
    renderObject
      ..shape = shape
      ..clipBehavior = clipBehavior
      ..borderRadius = borderRadius
      ..elevation = elevation
      ..color = color
      ..shadowColor = shadowColor;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<BoxShape>('shape', shape));
    properties.add(DiagnosticsProperty<BorderRadius>('borderRadius', borderRadius));
    properties.add(DoubleProperty('elevation', elevation));
    properties.add(ColorProperty('color', color));
    properties.add(ColorProperty('shadowColor', shadowColor));
  }
}

/// A widget representing a physical layer that clips its children to a path.
///
/// Physical layers cast shadows based on an [elevation] which is nominally in
/// logical pixels, coming vertically out of the rendering surface.
///
/// [PhysicalModel] does the same but only supports shapes that can be expressed
/// as rectangles with rounded corners.
///
/// {@tool dartpad}
/// This example shows how to use a [PhysicalShape] on a centered [SizedBox]
/// to clip it to a rounded rectangle using a [ShapeBorderClipper] and give it
/// an orange color along with a shadow.
///
/// ** See code in examples/api/lib/widgets/basic/physical_shape.0.dart **
/// {@end-tool}
///
/// See also:
///
///  * [ShapeBorderClipper], which converts a [ShapeBorder] to a [CustomClipper], as
///    needed by this widget.
class PhysicalShape extends SingleChildRenderObjectWidget {
  /// Creates a physical model with an arbitrary shape clip.
  ///
  /// The [color] is required; physical things have a color.
  ///
  /// The [elevation] must be non-negative.
  const PhysicalShape({
    super.key,
    required this.clipper,
    this.clipBehavior = Clip.none,
    this.elevation = 0.0,
    required this.color,
    this.shadowColor = const Color(0xFF000000),
    super.child,
  }) : assert(elevation >= 0.0);

  /// Determines which clip to use.
  ///
  /// If the path in question is expressed as a [ShapeBorder] subclass,
  /// consider using the [ShapeBorderClipper] delegate class to adapt the
  /// shape for use with this widget.
  final CustomClipper<Path> clipper;

  /// {@macro flutter.material.Material.clipBehavior}
  ///
  /// Defaults to [Clip.none].
  final Clip clipBehavior;

  /// The z-coordinate relative to the parent at which to place this physical
  /// object.
  ///
  /// The value is non-negative.
  final double elevation;

  /// The background color.
  final Color color;

  /// When elevation is non zero the color to use for the shadow color.
  final Color shadowColor;

  @override
  RenderPhysicalShape createRenderObject(BuildContext context) {
    return RenderPhysicalShape(
      clipper: clipper,
      clipBehavior: clipBehavior,
      elevation: elevation,
      color: color,
      shadowColor: shadowColor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderPhysicalShape renderObject) {
    renderObject
      ..clipper = clipper
      ..clipBehavior = clipBehavior
      ..elevation = elevation
      ..color = color
      ..shadowColor = shadowColor;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CustomClipper<Path>>('clipper', clipper));
    properties.add(DoubleProperty('elevation', elevation));
    properties.add(ColorProperty('color', color));
    properties.add(ColorProperty('shadowColor', shadowColor));
  }
}

// POSITIONING AND SIZING NODES

/// A widget that applies a transformation before painting its child.
///
/// Unlike [RotatedBox], which applies a rotation prior to layout, this object
/// applies its transformation just prior to painting, which means the
/// transformation is not taken into account when calculating how much space
/// this widget's child (and thus this widget) consumes.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=9z_YNlRlWfA}
///
/// {@tool snippet}
///
/// This example rotates and skews an orange box containing text, keeping the
/// top right corner pinned to its original position.
///
/// ```dart
/// ColoredBox(
///   color: Colors.black,
///   child: Transform(
///     alignment: Alignment.topRight,
///     transform: Matrix4.skewY(0.3)..rotateZ(-math.pi / 12.0),
///     child: Container(
///       padding: const EdgeInsets.all(8.0),
///       color: const Color(0xFFE8581C),
///       child: const Text('Apartment for rent!'),
///     ),
///   ),
/// )
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [RotatedBox], which rotates the child widget during layout, not just
///    during painting.
///  * [FractionalTranslation], which applies a translation to the child
///    that is relative to the child's size.
///  * [FittedBox], which sizes and positions its child widget to fit the parent
///    according to a given [BoxFit] discipline.
///  * The [catalog of layout widgets](https://flutter.dev/widgets/layout/).
class Transform extends SingleChildRenderObjectWidget {
  /// Creates a widget that transforms its child.
  const Transform({
    super.key,
    required this.transform,
    this.origin,
    this.alignment,
    this.transformHitTests = true,
    this.filterQuality,
    super.child,
  });

  /// Creates a widget that transforms its child using a rotation around the
  /// center.
  ///
  /// The `angle` argument gives the rotation in clockwise radians.
  ///
  /// {@tool snippet}
  ///
  /// This example rotates an orange box containing text around its center by
  /// fifteen degrees.
  ///
  /// ```dart
  /// Transform.rotate(
  ///   angle: -math.pi / 12.0,
  ///   child: Container(
  ///     padding: const EdgeInsets.all(8.0),
  ///     color: const Color(0xFFE8581C),
  ///     child: const Text('Apartment for rent!'),
  ///   ),
  /// )
  /// ```
  /// {@end-tool}
  ///
  /// See also:
  ///
  ///  * [RotationTransition], which animates changes in rotation smoothly
  ///    over a given duration.
  Transform.rotate({
    super.key,
    required double angle,
    this.origin,
    this.alignment = Alignment.center,
    this.transformHitTests = true,
    this.filterQuality,
    super.child,
  }) : transform = _computeRotation(angle);

  /// Creates a widget that transforms its child using a translation.
  ///
  /// The `offset` argument specifies the translation.
  ///
  /// {@tool snippet}
  ///
  /// This example shifts the silver-colored child down by fifteen pixels.
  ///
  /// ```dart
  /// Transform.translate(
  ///   offset: const Offset(0.0, 15.0),
  ///   child: Container(
  ///     padding: const EdgeInsets.all(8.0),
  ///     color: const Color(0xFF7F7F7F),
  ///     child: const Text('Quarter'),
  ///   ),
  /// )
  /// ```
  /// {@end-tool}
  Transform.translate({
    super.key,
    required Offset offset,
    this.transformHitTests = true,
    this.filterQuality,
    super.child,
  }) : transform = Matrix4.translationValues(offset.dx, offset.dy, 0.0),
       origin = null,
       alignment = null;

  /// Creates a widget that scales its child along the 2D plane.
  ///
  /// The `scaleX` argument provides the scalar by which to multiply the `x`
  /// axis, and the `scaleY` argument provides the scalar by which to multiply
  /// the `y` axis. Either may be omitted, in which case the scaling factor for
  /// that axis defaults to 1.0.
  ///
  /// For convenience, to scale the child uniformly, instead of providing
  /// `scaleX` and `scaleY`, the `scale` parameter may be used.
  ///
  /// At least one of `scale`, `scaleX`, and `scaleY` must be non-null. If
  /// `scale` is provided, the other two must be null; similarly, if it is not
  /// provided, one of the other two must be provided.
  ///
  /// The [alignment] controls the origin of the scale; by default, this is the
  /// center of the box.
  ///
  /// {@tool snippet}
  ///
  /// This example shrinks an orange box containing text such that each
  /// dimension is half the size it would otherwise be.
  ///
  /// ```dart
  /// Transform.scale(
  ///   scale: 0.5,
  ///   child: Container(
  ///     padding: const EdgeInsets.all(8.0),
  ///     color: const Color(0xFFE8581C),
  ///     child: const Text('Bad Idea Bears'),
  ///   ),
  /// )
  /// ```
  /// {@end-tool}
  ///
  /// See also:
  ///
  /// * [ScaleTransition], which animates changes in scale smoothly over a given
  ///   duration.
  Transform.scale({
    super.key,
    double? scale,
    double? scaleX,
    double? scaleY,
    this.origin,
    this.alignment = Alignment.center,
    this.transformHitTests = true,
    this.filterQuality,
    super.child,
  }) : assert(
         !(scale == null && scaleX == null && scaleY == null),
         "At least one of 'scale', 'scaleX' and 'scaleY' is required to be non-null",
       ),
       assert(
         scale == null || (scaleX == null && scaleY == null),
         "If 'scale' is non-null then 'scaleX' and 'scaleY' must be left null",
       ),
       transform = Matrix4.diagonal3Values(scale ?? scaleX ?? 1.0, scale ?? scaleY ?? 1.0, 1.0);

  /// Creates a widget that mirrors its child about the widget's center point.
  ///
  /// If `flipX` is true, the child widget will be flipped horizontally. Defaults to false.
  ///
  /// If `flipY` is true, the child widget will be flipped vertically. Defaults to false.
  ///
  /// If both are true, the child widget will be flipped both vertically and horizontally, equivalent to a 180 degree rotation.
  ///
  /// {@tool snippet}
  ///
  /// This example flips the text horizontally.
  ///
  /// ```dart
  /// Transform.flip(
  ///   flipX: true,
  ///   child: const Text('Horizontal Flip'),
  /// )
  /// ```
  /// {@end-tool}
  Transform.flip({
    super.key,
    bool flipX = false,
    bool flipY = false,
    this.origin,
    this.transformHitTests = true,
    this.filterQuality,
    super.child,
  }) : alignment = Alignment.center,
       transform = Matrix4.diagonal3Values(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0, 1.0);

  // Computes a rotation matrix for an angle in radians, attempting to keep rotations
  // at integral values for angles of 0, Ï€/2, Ï€, 3Ï€/2.
  static Matrix4 _computeRotation(double radians) {
    assert(radians.isFinite, 'Cannot compute the rotation matrix for a non-finite angle: $radians');
    if (radians == 0.0) {
      return Matrix4.identity();
    }
    final double sin = math.sin(radians);
    if (sin == 1.0) {
      return _createZRotation(1.0, 0.0);
    }
    if (sin == -1.0) {
      return _createZRotation(-1.0, 0.0);
    }
    final double cos = math.cos(radians);
    if (cos == -1.0) {
      return _createZRotation(0.0, -1.0);
    }
    return _createZRotation(sin, cos);
  }

  static Matrix4 _createZRotation(double sin, double cos) {
    final result = Matrix4.zero();
    result.storage[0] = cos;
    result.storage[1] = sin;
    result.storage[4] = -sin;
    result.storage[5] = cos;
    result.storage[10] = 1.0;
    result.storage[15] = 1.0;
    return result;
  }

  /// The matrix to transform the child by during painting.
  final Matrix4 transform;

  /// The origin of the coordinate system in which to apply the matrix,
  /// described relative to the point given by [alignment].
  ///
  /// Setting an origin is equivalent to conjugating the transform matrix by a
  /// translation. This property is provided just for convenience.
  ///
  /// This offset is applied in addition to any [alignment] transformation, so in this
  /// example, the child is rotated about its center, since [alignment]
  /// in [Transform.rotate] defaults to [Alignment.center]:
  ///
  /// ```dart
  /// Transform.rotate(
  ///   angle: math.pi,
  ///   child: Container(
  ///    width: 150.0,
  ///    height: 150.0,
  ///    color: Colors.blue,
  ///  ),
  /// )
  /// ```
  ///
  /// However, in this example the [origin] offset is applied after the
  /// `alignment`, so the child rotates about its bottom-right corner:
  ///
  /// ```dart
  /// Transform.rotate(
  ///   angle: math.pi,
  ///   origin: const Offset(75.0, 75.0),
  ///   child: Container(
  ///    width: 150.0,
  ///    height: 150.0,
  ///    color: Colors.blue,
  ///  ),
  /// )
  /// ```
  final Offset? origin;

  /// The alignment of the origin, relative to the size of the box.
  ///
  /// When this and [origin] are both null, the origin is the upper-left corner
  /// of this render object.
  /// The default for this field is null for some constructors,
  /// and [Alignment.center] for others.
  ///
  /// This is equivalent to setting an origin based on the size of the box.
  /// If it is specified at the same time as the [origin], both are applied.
  ///
  /// An [AlignmentDirectional.centerStart] value is the same as an [Alignment]
  /// whose [Alignment.x] value is `-1.0` if [Directionality.of] returns
  /// [TextDirection.ltr], and `1.0` if [Directionality.of] returns
  /// [TextDirection.rtl].	 Similarly [AlignmentDirectional.centerEnd] is the
  /// same as an [Alignment] whose [Alignment.x] value is `1.0` if
  /// [Directionality.of] returns	 [TextDirection.ltr], and `-1.0` if
  /// [Directionality.of] returns [TextDirection.rtl].
  final AlignmentGeometry? alignment;

  /// Whether to transform registered hits into the child's resulting coordinate system.
  ///
  /// When `true`, hit coordinates within the parent's bounds are transformed to match
  /// where the child appears visually after any transformation such as translation,
  /// rotation, scaling, or skewing.
  ///
  /// When `false`, hit coordinates are not transformed, potentially causing taps to
  /// register in a different location relative to the child's visual position.
  ///
  /// **Important:** Even when [transformHitTests] is true, children cannot
  /// receive events outside the parent's bounds. Hit testing always starts
  /// with the parent's own bounds check in [RenderBox.hitTest]. If the pointer
  /// is outside the parent's bounds, [RenderBox.hitTestChildren] is not
  /// invoked and the children are not considered for hit testing.
  ///
  /// For interactive elements that need to be tappable outside their parent's
  /// original bounds, consider:
  /// - Expanding the parent widget's bounds to encompass the transformed child.
  /// - Using an [OverlayEntry] or [OverlayPortal] to place the widget in an
  ///   [Overlay].
  /// - Restructuring the widget hierarchy.
  ///
  /// {@tool snippet}
  /// This example shows a `Container` that is scaled up. Even though it appears
  /// larger, taps are only registered within the original 100x100 area of the
  /// parent `SizedBox`.
  ///
  /// ```dart
  /// Center(
  ///   child: SizedBox(
  ///     width: 100.0,
  ///     height: 100.0,
  ///     child: Transform.scale(
  ///       scale: 2.0,
  ///       child: GestureDetector(
  ///         onTap: () => debugPrint('Tapped!'),
  ///         child: const ColoredBox(
  ///           color: Colors.purple,
  ///         ),
  ///       ),
  ///     ),
  ///   ),
  /// )
  /// ```
  /// {@end-tool}
  ///
  /// Defaults to true.
  final bool transformHitTests;

  /// The filter quality with which to apply the transform as a bitmap operation.
  ///
  /// {@template flutter.widgets.Transform.optional.FilterQuality}
  /// The transform will be applied by re-rendering the child if [filterQuality] is null,
  /// otherwise it controls the quality of an [ImageFilter.matrix] applied to a bitmap
  /// rendering of the child.
  /// {@endtemplate}
  final FilterQuality? filterQuality;

  @override
  RenderTransform createRenderObject(BuildContext context) {
    return RenderTransform(
      transform: transform,
      origin: origin,
      alignment: alignment,
      textDirection: Directionality.maybeOf(context),
      transformHitTests: transformHitTests,
      filterQuality: filterQuality,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderTransform renderObject) {
    renderObject
      ..transform = transform
      ..origin = origin
      ..alignment = alignment
      ..textDirection = Directionality.maybeOf(context)
      ..transformHitTests = transformHitTests
      ..filterQuality = filterQuality;
  }
}

/// A widget that can be targeted by a [CompositedTransformFollower].
///
/// When this widget is composited during the compositing phase (which comes
/// after the paint phase, as described in [WidgetsBinding.drawFrame]), it
/// updates the [link] object so that any [CompositedTransformFollower] widgets
/// that are subsequently composited in the same frame and were given the same
/// [LayerLink] can position themselves at the same screen location.
///
/// A single [CompositedTransformTarget] can be followed by multiple
/// [CompositedTransformFollower] widgets.
///
/// The [CompositedTransformTarget] must come earlier in the paint order than
/// any linked [CompositedTransformFollower]s.
///
/// See also:
///
///  * [CompositedTransformFollower], the widget that can target this one.
///  * [LeaderLayer], the layer that implements this widget's logic.
class CompositedTransformTarget extends SingleChildRenderObjectWidget {
  /// Creates a composited transform target widget.
  ///
  /// The [link] property must not be currently used by any other
  /// [CompositedTransformTarget] object that is in the tree.
  const CompositedTransformTarget({super.key, required this.link, super.child});

  /// The link object that connects this [CompositedTransformTarget] with one or
  /// more [CompositedTransformFollower]s.
  ///
  /// The link must not be associated with another [CompositedTransformTarget]
  /// that is also being painted.
  final LayerLink link;

  @override
  RenderLeaderLayer createRenderObject(BuildContext context) {
    return RenderLeaderLayer(link: link);
  }

  @override
  void updateRenderObject(BuildContext context, RenderLeaderLayer renderObject) {
    renderObject.link = link;
  }
}

/// A widget that follows a [CompositedTransformTarget].
///
/// When this widget is composited during the compositing phase (which comes
/// after the paint phase, as described in [WidgetsBinding.drawFrame]), it
/// applies a transformation that brings [targetAnchor] of the linked
/// [CompositedTransformTarget] and [followerAnchor] of this widget together.
/// The two anchor points will have the same global coordinates, unless [offset]
/// is not [Offset.zero], in which case [followerAnchor] will be offset by
/// [offset] in the linked [CompositedTransformTarget]'s coordinate space.
///
/// The [LayerLink] object used as the [link] must be the same object as that
/// provided to the matching [CompositedTransformTarget].
///
/// The [CompositedTransformTarget] must come earlier in the paint order than
/// this [CompositedTransformFollower].
///
/// Hit testing on descendants of this widget will only work if the target
/// position is within the box that this widget's parent considers to be
/// hittable. If the parent covers the screen, this is trivially achievable, so
/// this widget is usually used as the root of an [OverlayEntry] in an app-wide
/// [Overlay] (e.g. as created by the [MaterialApp] widget's [Navigator]).
///
/// See also:
///
///  * [CompositedTransformTarget], the widget that this widget can target.
///  * [FollowerLayer], the layer that implements this widget's logic.
///  * [Transform], which applies an arbitrary transform to a child.
class CompositedTransformFollower extends SingleChildRenderObjectWidget {
  /// Creates a composited transform target widget.
  ///
  /// If the [link] property was also provided to a [CompositedTransformTarget],
  /// that widget must come earlier in the paint order.
  ///
  /// The [showWhenUnlinked] and [offset] properties must also not be null.
  const CompositedTransformFollower({
    super.key,
    required this.link,
    this.showWhenUnlinked = true,
    this.offset = Offset.zero,
    this.targetAnchor = Alignment.topLeft,
    this.followerAnchor = Alignment.topLeft,
    super.child,
  });

  /// The link object that connects this [CompositedTransformFollower] with a
  /// [CompositedTransformTarget].
  final LayerLink link;

  /// Whether to show the widget's contents when there is no corresponding
  /// [CompositedTransformTarget] with the same [link].
  ///
  /// When the widget is linked, the child is positioned such that it has the
  /// same global position as the linked [CompositedTransformTarget].
  ///
  /// When the widget is not linked, then: if [showWhenUnlinked] is true, the
  /// child is visible and not repositioned; if it is false, then child is
  /// hidden.
  final bool showWhenUnlinked;

  /// The anchor point on the linked [CompositedTransformTarget] that
  /// [followerAnchor] will line up with.
  ///
  /// {@template flutter.widgets.CompositedTransformFollower.targetAnchor}
  /// For example, when [targetAnchor] and [followerAnchor] are both
  /// [Alignment.topLeft], this widget will be top left aligned with the linked
  /// [CompositedTransformTarget]. When [targetAnchor] is
  /// [Alignment.bottomLeft] and [followerAnchor] is [Alignment.topLeft], this
  /// widget will be left aligned with the linked [CompositedTransformTarget],
  /// and its top edge will line up with the [CompositedTransformTarget]'s
  /// bottom edge.
  /// {@endtemplate}
  ///
  /// Defaults to [Alignment.topLeft].
  final Alignment targetAnchor;

  /// The anchor point on this widget that will line up with [targetAnchor] on
  /// the linked [CompositedTransformTarget].
  ///
  /// {@macro flutter.widgets.CompositedTransformFollower.targetAnchor}
  ///
  /// Defaults to [Alignment.topLeft].
  final Alignment followerAnchor;

  /// The additional offset to apply to the [targetAnchor] of the linked
  /// [CompositedTransformTarget] to obtain this widget's [followerAnchor]
  /// position.
  final Offset offset;

  @override
  RenderFollowerLayer createRenderObject(BuildContext context) {
    return RenderFollowerLayer(
      link: link,
      showWhenUnlinked: showWhenUnlinked,
      offset: offset,
      leaderAnchor: targetAnchor,
      followerAnchor: followerAnchor,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderFollowerLayer renderObject) {
    renderObject
      ..link = link
      ..showWhenUnlinked = showWhenUnlinked
      ..offset = offset
      ..leaderAnchor = targetAnchor
      ..followerAnchor = followerAnchor;
  }
}

/// Scales and positions its child within itself according to [fit].
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=T4Uehk3_wlY}
///
/// {@tool dartpad}
/// In this example, the [Placeholder] is stretched to fill the entire
/// [Container]. Try changing the fit types to see the effect on the layout of
/// the [Placeholder].
///
/// ** See code in examples/api/lib/widgets/basic/fitted_box.0.dart **
/// {@end-tool}
///
/// See also:
///
/// * [Transform], which applies an arbitrary transform to its child widget at
///   paint time.
/// * The [catalog of layout widgets](https://flutter.dev/widgets/layout/).
class FittedBox extends SingleChildRenderObjectWidget {
  /// Creates a widget that scales and positions its child within itself according to [fit].
  const FittedBox({
    super.key,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.clipBehavior = Clip.none,
    super.child,
  });

  /// How to inscribe the child into the space allocated during layout.
  final BoxFit fit;

  /// How to align the child within its parent's bounds.
  ///
  /// An alignment of (-1.0, -1.0) aligns the child to the top-left corner of its
  /// parent's bounds. An alignment of (1.0, 0.0) aligns the child to the middle
  /// of the right edge of its parent's bounds.
  ///
  /// Defaults to [Alignment.center].
  ///
  /// See also:
  ///
  ///  * [Alignment], a class with convenient constants typically used to
  ///    specify an [AlignmentGeometry].
  ///  * [AlignmentDirectional], like [Alignment] for specifying alignments
  ///    relative to text direction.
  final AlignmentGeometry alignment;

  /// {@macro flutter.material.Material.clipBehavior}
  ///
  /// Defaults to [Clip.none].
  final Clip clipBehavior;

  @override
  RenderFittedBox createRenderObject(BuildContext context) {
    return RenderFittedBox(
      fit: fit,
      alignment: alignment,
      textDirection: Directionality.maybeOf(context),
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderFittedBox renderObject) {
    renderObject
      ..fit = fit
      ..alignment = alignment
      ..textDirection = Directionality.maybeOf(context)
      ..clipBehavior = clipBehavior;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<BoxFit>('fit', fit));
    properties.add(DiagnosticsProperty<AlignmentGeometry>('alignment', alignment));
  }
}

/// Applies a translation transformation before painting its child.
///
/// The translation is expressed as a [Offset] scaled to the child's size. For
/// example, an [Offset] with a `dx` of 0.25 will result in a horizontal
/// translation of one quarter the width of the child.
///
/// Hit tests will only be detected inside the bounds of the
/// [FractionalTranslation], even if the contents are offset such that
/// they overflow.
///
/// See also:
///
///  * [Transform], which applies an arbitrary transform to its child widget at
///    paint time.
///  * [Transform.translate], which applies an absolute offset translation
///    transformation instead of an offset scaled to the child.
///  * The [catalog of layout widgets](https://flutter.dev/widgets/layout/).
class FractionalTranslation extends SingleChildRenderObjectWidget {
  /// Creates a widget that translates its child's painting.
  const FractionalTranslation({
    super.key,
    required this.translation,
    this.transformHitTests = true,
    super.child,
  });

  /// The translation to apply to the child, scaled to the child's size.
  ///
  /// For example, an [Offset] with a `dx` of 0.25 will result in a horizontal
  /// translation of one quarter the width of the child.
  final Offset translation;

  /// Whether to apply the translation when performing hit tests.
  final bool transformHitTests;

  @override
  RenderFractionalTranslation createRenderObject(BuildContext context) {
    return RenderFractionalTranslation(
      translation: translation,
      transformHitTests: transformHitTests,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderFractionalTranslation renderObject) {
    renderObject
      ..translation = translation
      ..transformHitTests = transformHitTests;
  }
}

/// A widget that rotates its child by a integral number of quarter turns.
///
/// Unlike [Transform], which applies a transform just prior to painting,
/// this object applies its rotation prior to layout, which means the entire
/// rotated box consumes only as much space as required by the rotated child.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=BFE6_UglLfQ}
///
/// {@tool snippet}
///
/// This snippet rotates the child (some [Text]) so that it renders from bottom
/// to top, like an axis label on a graph:
///
/// ```dart
/// const RotatedBox(
///   quarterTurns: 3,
///   child: Text('Hello World!'),
/// )
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [Transform], which is a paint effect that allows you to apply an
///    arbitrary transform to a child.
///  * [Transform.rotate], which applies a rotation paint effect.
///  * The [catalog of layout widgets](https://flutter.dev/widgets/layout/).
class RotatedBox extends SingleChildRenderObjectWidget {
  /// A widget that rotates its child.
  const RotatedBox({super.key, required this.quarterTurns, super.child});

  /// The number of clockwise quarter turns the child should be rotated.
  final int quarterTurns;

  @override
  RenderRotatedBox createRenderObject(BuildContext context) =>
      RenderRotatedBox(quarterTurns: quarterTurns);

  @override
  void updateRenderObject(BuildContext context, RenderRotatedBox renderObject) {
    renderObject.quarterTurns = quarterTurns;
  }
}

/// A widget that insets its child by the given padding.
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=oD5RtLhhubg}
///
/// When passing layout constraints to its child, padding shrinks the
/// constraints by the given padding, causing the child to layout at a smaller
/// size. Padding then sizes itself to its child's size, inflated by the
/// padding, effectively creating empty space around the child.
///
/// {@tool snippet}
///
/// This snippet creates "Hello World!" [Text] inside a [Card] that is indented
/// by sixteen pixels in each direction.
///
/// ![](https://flutter.github.io/assets-for-api-docs/assets/widgets/padding.png)
///
/// ```dart
/// const Card(
///   child: Padding(
///     padding: EdgeInsets.all(16.0),
///     child: Text('Hello World!'),
///   ),
/// )
/// ```
/// {@end-tool}
///
/// ## Design discussion
///
/// ### Why use a [Padding] widget rather than a [Container] with a [Container.padding] property?
///
/// There isn't really any difference between the two. If you supply a
/// [Container.padding] argument, [Container] builds a [Padding] widget
/// for you.
///
/// [Container] doesn't implement its properties directly. Instead, [Container]
/// combines a number of simpler widgets together into a convenient package. For
/// example, the [Container.padding] property causes the container to build a
/// [Padding] widget and the [Container.decoration] property causes the
/// container to build a [DecoratedBox] widget. If you find [Container]
/// convenient, feel free to use it. If not, feel free to build these simpler
/// widgets in whatever combination meets your needs.
///
/// In fact, the majority of widgets in Flutter are combinations of other
/// simpler widgets. Composition, rather than inheritance, is the primary
/// mechanism for building up widgets.
///
/// See also:
///
///  * [EdgeInsets], the class that is used to describe the padding dimensions.
///  * [AnimatedPadding], which animates changes in [padding] over a given
///    duration.
///  * [SliverPadding], the sliver equivalent of this widget.
///  * The [catalog of layout widgets](https://flutter.dev/widgets/layout/).
class Padding extends SingleChildRenderObjectWidget {
  /// Creates a widget that insets its child.
  const Padding({super.key, required this.padding, super.child});

  /// The amount of space by which to inset the child.
  final EdgeInsetsGeometry padding;

  @override
  RenderPadding createRenderObject(BuildContext context) {
    return RenderPadding(padding: padding, textDirection: Directionality.maybeOf(context));
  }

  @override
  void updateRenderObject(BuildContext context, RenderPadding renderObject) {
    renderObject
      ..padding = padding
      ..textDirection = Directionality.maybeOf(context);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<EdgeInsetsGeometry>('padding', padding));
  }
}

/// A widget that aligns its child within itself and optionally sizes itself
/// based on the child's size.
///
/// For example, to align a box at the bottom right, you would pass this box a
/// tight constraint that is bigger than the child's natural size,
/// with an alignment of [Alignment.bottomRight].
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=g2E7yl3MwMk}
///
/// This widget will be as big as possible if its dimensions are constrained and
/// [widthFactor] and [heightFactor] are null. If a dimension is unconstrained
/// and the corresponding size factor is null then the widget will match its
/// child's size in that dimension. If a size factor is non-null then the
/// corresponding dimension of this widget will be the product of the child's
/// dimension and the size factor. For example if widthFactor is 2.0 then
/// the width of this widget will always be twice its child's width.
///
/// {@tool snippet}
///
/// The [Align] widget in this example uses one of the defined constants from
/// [Alignment], [Alignment.topRight]. This places the [FlutterLogo] in the top
/// right corner of the parent blue [Container].
///
/// ![A blue square container with the Flutter logo in the top right corner.](https://flutter.github.io/assets-for-api-docs/assets/widgets/align_constant.png)
///
/// ```dart
/// Center(
///   child: Container(
///     height: 120.0,
///     width: 120.0,
///     color: Colors.blue[50],
///     child: const Align(
///       alignment: Alignment.topRight,
///       child: FlutterLogo(
///         size: 60,
///       ),
///     ),
///   ),
/// )
/// ```
/// {@end-tool}
///
/// ## How it works
///
/// The [alignment] property describes a point in the `child`'s coordinate system
/// and a different point in the coordinate system of this widget. The [Align]
/// widget positions the `child` such that both points are lined up on top of
/// each other.
///
/// {@tool snippet}
///
/// The [Alignment] used in the following example defines two points:
///
///   * (0.2 * width of [FlutterLogo]/2 + width of [FlutterLogo]/2, 0.6 * height
///     of [FlutterLogo]/2 + height of [FlutterLogo]/2) = (36.0, 48.0) in the
///     coordinate system of the [FlutterLogo].
///   * (0.2 * width of [Align]/2 + width of [Align]/2, 0.6 * height
///     of [Align]/2 + height of [Align]/2) = (72.0, 96.0) in the
///     coordinate system of the [Align] widget (blue area).
///
/// The [Align] widget positions the [FlutterLogo] such that the two points are on
/// top of each other. In this example, the top left of the [FlutterLogo] will
/// be placed at (72.0, 96.0) - (36.0, 48.0) = (36.0, 48.0) from the top left of
/// the [Align] widget.
///
/// ![A blue square container with the Flutter logo positioned according to the
/// Alignment specified above. A point is marked at the center of the container
/// for the origin of the Alignment coordinate system.](https://flutter.github.io/assets-for-api-docs/assets/widgets/align_alignment.png)
///
/// ```dart
/// Center(
///   child: Container(
///     height: 120.0,
///     width: 120.0,
///     color: Colors.blue[50],
///     child: const Align(
///       alignment: Alignment(0.2, 0.6),
///       child: FlutterLogo(
///         size: 60,
///       ),
///     ),
///   ),
/// )
/// ```
/// {@end-tool}
///
/// {@tool snippet}
///
/// The [FractionalOffset] used in the following example defines two points:
///
///   * (0.2 * width of [FlutterLogo], 0.6 * height of [FlutterLogo]) = (12.0, 36.0)
///     in the coordinate system of the [FlutterLogo].
///   * (0.2 * width of [Align], 0.6 * height of [Align]) = (24.0, 72.0) in the
///     coordinate system of the [Align] widget (blue area).
///
/// The [Align] widget positions the [FlutterLogo] such that the two points are on
/// top of each other. In this example, the top left of the [FlutterLogo] will
/// be placed at (24.0, 72.0) - (12.0, 36.0) = (12.0, 36.0) from the top left of
/// the [Align] widget.
///
/// The [FractionalOffset] class uses a coordinate system with an origin in the top-left
/// corner of the [Container] in difference to the center-oriented system used in
/// the example above with [Alignment].
///
/// ![A blue square container with the Flutter logo positioned according to the
/// FractionalOffset specified above. A point is marked at the top left corner
/// of the container for the origin of the FractionalOffset coordinate system.](https://flutter.github.io/assets-for-api-docs/assets/widgets/align_fractional_offset.png)
///
/// ```dart
/// Center(
///   child: Container(
///     height: 120.0,
///     width: 120.0,
///     color: Colors.blue[50],
///     child: const Align(
///       alignment: FractionalOffset(0.2, 0.6),
///       child: FlutterLogo(
///         size: 60,
///       ),
///     ),
///   ),
/// )
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [AnimatedAlign], which animates changes in [alignment] smoothly over a
///    given duration.
///  * [CustomSingleChildLayout], which uses a delegate to control the layout of
///    a single child.
///  * [Center], which is the same as [Align] but with the [alignment] always
///    set to [Alignment.center].
///  * [FractionallySizedBox], which sizes its child based on a fraction of its
///    own size and positions the child according to an [Alignment] value.
///  * The [catalog of layout widgets](https://flutter.dev/widgets/layout/).
class Align extends SingleChildRenderObjectWidget {
  /// Creates an alignment widget.
  ///
  /// The alignment defaults to [Alignment.center].
  const Align({
    super.key,
    this.alignment = Alignment.center,
    this.widthFactor,
    this.heightFactor,
    super.child,
  }) : assert(widthFactor == null || widthFactor >= 0.0),
       assert(heightFactor == null || heightFactor >= 0.0);

  /// How to align the child.
  ///
  /// The x and y values of the [Alignment] control the horizontal and vertical
  /// alignment, respectively. An x value of -1.0 means that the left edge of
  /// the child is aligned with the left edge of the parent whereas an x value
  /// of 1.0 means that the right edge of the child is aligned with the right
  /// edge of the parent. Other values interpolate (and extrapolate) linearly.
  /// For example, a value of 0.0 means that the center of the child is aligned
  /// with the center of the parent.
  ///
  /// See also:
  ///
  ///  * [Alignment], which has more details and some convenience constants for
  ///    common positions.
  ///  * [AlignmentDirectional], which has a horizontal coordinate orientation
  ///    that depends on the [TextDirection].
  final AlignmentGeometry alignment;

  /// If non-null, sets its width to the child's width multiplied by this factor.
  ///
  /// Can be both greater and less than 1.0 but must be non-negative.
  final double? widthFactor;

  /// If non-null, sets its height to the child's height multiplied by this factor.
  ///
  /// Can be both greater and less than 1.0 but must be non-negative.
  final double? heightFactor;

  @override
  RenderPositionedBox createRenderObject(BuildContext context) {
    return RenderPositionedBox(
      alignment: alignment,
      widthFactor: widthFactor,
      heightFactor: heightFactor,
      textDirection: Directionality.maybeOf(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderPositionedBox renderObject) {
    renderObject
      ..alignment = alignment
      ..widthFactor = widthFactor
      ..heightFactor = heightFactor
      ..textDirection = Directionality.maybeOf(context);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<AlignmentGeometry>('alignment', alignment));
    properties.add(DoubleProperty('widthFactor', widthFactor, defaultValue: null));
    properties.add(DoubleProperty('heightFactor', heightFactor, defaultValue: null));
  }
}

/// A widget that centers its child within itself.
///
/// This widget will be as big as possible if its dimensions are constrained and
/// [widthFactor] and [heightFactor] are null. If a dimension is unconstrained
/// and the corresponding size factor is null then the widget will match its
/// child's size in that dimension. If a size factor is non-null then the
/// corresponding dimension of this widget will be the product of the child's
/// dimension and the size factor. For example if widthFactor is 2.0 then
/// the width of this widget will always be twice its child's width.
///
/// See also:
///
///  * [Align], which lets you arbitrarily position a child within itself,
///    rather than just centering it.
///  * [Row], a widget that displays its children in a horizontal array.
///  * [Column], a widget that displays its children in a vertical array.
///  * [Container], a convenience widget that combines common painting,
///    positioning, and sizing widgets.
///  * The [catalog of layout widgets](https://flutter.dev/widgets/layout/).
class Center extends Align {
  /// Creates a widget that centers its child.
  const Center({super.key, super.widthFactor, super.heightFactor, super.child});
}

/// A widget that defers the layout of its single child to a delegate.
///
/// The delegate can determine the layout constraints for the child and can
/// decide where to position the child. The delegate can also determine the size
/// of the parent, but the size of the parent cannot depend on the size of the
/// child.
///
/// See also:
///
///  * [SingleChildLayoutDelegate], which controls the layout of the child.
///  * [Align], which sizes itself based on its child's size and positions
///    the child according to an [Alignment] value.
///  * [FractionallySizedBox], which sizes its child based on a fraction of its own
///    size and positions the child according to an [Alignment] value.
///  * [CustomMultiChildLayout], which uses a delegate to position multiple
///    children.
///  * The [catalog of layout widgets](https://flutter.dev/widgets/layout/).
class CustomSingleChildLayout extends SingleChildRenderObjectWidget {
  /// Creates a custom single child layout.
  const CustomSingleChildLayout({super.key, required this.delegate, super.child});

  /// The delegate that controls the layout of the child.
  final SingleChildLayoutDelegate delegate;

  @override
  RenderCustomSingleChildLayoutBox createRenderObject(BuildContext context) {
    return RenderCustomSingleChildLayoutBox(delegate: delegate);
  }

  @override
  void updateRenderObject(BuildContext context, RenderCustomSingleChildLayoutBox renderObject) {
    renderObject.delegate = delegate;
  }
}

/// Metadata for identifying children in a [CustomMultiChildLayout].
///
/// The [MultiChildLayoutDelegate.hasChild],
/// [MultiChildLayoutDelegate.layoutChild], and
/// [MultiChildLayoutDelegate.positionChild] methods use these identifiers.
class LayoutId extends ParentDataWidget<MultiChildLayoutParentData> {
  /// Marks a child with a layout identifier.
  LayoutId({Key? key, required this.id, required super.child})
    : super(key: key ?? ValueKey<Object>(id));

  /// An object representing the identity of this child.
  ///
  /// The [id] needs to be unique among the children that the
  /// [CustomMultiChildLayout] manages.
  final Object id;

  @override
  void applyParentData(RenderObject renderObject) {
    assert(renderObject.parentData is MultiChildLayoutParentData);
    final parentData = renderObject.parentData! as MultiChildLayoutParentData;
    if (parentData.id != id) {
      parentData.id = id;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => CustomMultiChildLayout;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Object>('id', id));
  }
}

/// A widget that uses a delegate to size and position multiple children.
///
/// The delegate can determine the layout constraints for each child and can
/// decide where to position each child. The delegate can also determine the
/// size of the parent, but the size of the parent cannot depend on the sizes of
/// the children.
///
/// [CustomMultiChildLayout] is appropriate when there are complex relationships
/// between the size and positioning of multiple widgets. To control the
/// layout of a single child, [CustomSingleChildLayout] is more appropriate. For
/// simple cases, such as aligning a widget to one or another edge, the [Stack]
/// widget is more appropriate.
///
/// Each child must be wrapped in a [LayoutId] widget to identify the widget for
/// the delegate.
///
/// {@tool dartpad}
/// This example shows a [CustomMultiChildLayout] widget being used to lay out
/// colored blocks from start to finish in a cascade that has some overlap.
///
/// It responds to changes in [Directionality] by re-laying out its children.
///
/// ** See code in examples/api/lib/widgets/basic/custom_multi_child_layout.0.dart **
/// {@end-tool}
///
/// See also:
///
///  * [MultiChildLayoutDelegate], for details about how to control the layout of
///    the children.
///  * [CustomSingleChildLayout], which uses a delegate to control the layout of
///    a single child.
///  * [Stack], which arranges children relative to the edges of the container.
///  * [Flow], which provides paint-time control of its children using transform
///    matrices.
///  * The [catalog of layout widgets](https://flutter.dev/widgets/layout/).
class CustomMultiChildLayout extends MultiChildRenderObjectWidget {
  /// Creates a custom multi-child layout.
  const CustomMultiChildLayout({super.key, required this.delegate, super.children});

  /// The delegate that controls the layout of the children.
  final MultiChildLayoutDelegate delegate;

  @override
  RenderCustomMultiChildLayoutBox createRenderObject(BuildContext context) {
    return RenderCustomMultiChildLayoutBox(delegate: delegate);
  }

  @override
  void updateRenderObject(BuildContext context, RenderCustomMultiChildLayoutBox renderObject) {
    renderObject.delegate = delegate;
  }
}

/// A box with a specified size.
///
/// If given a child, this widget forces it to have a specific width and/or height.
/// These values will be ignored if this widget's parent does not permit them.
/// For example, this happens if the parent is the screen (forces the child to
/// be the same size as the parent), or another [SizedBox] (forces its child to
/// have a specific width and/or height). This can be remedied by wrapping the
/// child [SizedBox] in a widget that does permit it to be any size up to the
/// size of the parent, such as [Center] or [Align].
///
/// If either the width or height is null, this widget will try to size itself to
/// match the child's size in that dimension. If the child's size depends on the
/// size of its parent, the height and width must be provided.
///
/// If not given a child, [SizedBox] will try to size itself as close to the
/// specified height and width as possible given the parent's constraints. If
/// [height] or [width] is null or unspecified, it will be treated as zero.
///
/// The [SizedBox.expand] constructor can be used to make a [SizedBox] that
/// sizes itself to fit the parent. It is equivalent to setting [width] and
/// [height] to [double.infinity].
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=EHPu_DzRfqA}
///
/// {@tool snippet}
///
/// This snippet makes the child widget (a [Card] with some [Text]) have the
/// exact size 200x300, parental constraints permitting:
///
/// ```dart
/// const SizedBox(
///   width: 200.0,
///   height: 300.0,
///   child: Card(child: Text('Hello World!')),
/// )
/// ```
/// {@end-tool}
///
/// See also:
///
///  * [ConstrainedBox], a more generic version of this class that takes
///    arbitrary [BoxConstraints] instead of an explicit width and height.
///  * [UnconstrainedBox], a container that tries to let its child draw without
///    constraints.
///  * [FractionallySizedBox], a widget that sizes its child to a fraction of
///    the total available space.
///  * [AspectRatio], a widget that attempts to fit within the parent's
///    constraints while also sizing its child to match a given aspect ratio.
///  * [FittedBox], which sizes and positions its child widget to fit the parent
///    according to a given [BoxFit] discipline.
///  * The [catalog of layout widgets](https://flutter.dev/widgets/layout/).
///  * [Understanding constraints](https://docs.flutter.dev/ui/layout/constraints),
///    an in-depth article about layout in Flutter.
class SizedBox extends SingleChildRenderObjectWidget {
  /// Creates a fixed size box. The [width] and [height] parameters can be null
  /// to indicate that the size of the box should not be constrained in
  /// the corresponding dimension.
  const SizedBox({super.key, this.width, this.height, super.child});

  /// Creates a box that will become as large as its parent allows.
  const SizedBox.expand({super.key, super.child})
    : width = double.infinity,
      height = double.infinity;

  /// Creates a box that will become as small as its parent allows.
  const SizedBox.shrink({super.key, super.child}) : width = 0.0, height = 0.0;

  /// Creates a box with the specified size.
  SizedBox.fromSize({super.key, super.child, Size? size})
    : width = size?.width,
      height = size?.height;

  /// Creates a box whose [width] and [height] are equal.
  const SizedBox.square({super.key, super.child, double? dimension})
    : width = dimension,
      height = dimension;

  /// If non-null, requires the child to have exactly this width.
  final double? width;

  /// If non-null, requires the child to have exactly this height.
  final double? height;

  @override
  RenderConstrainedBox createRenderObject(BuildContext context) {
    return RenderConstrainedBox(additionalConstraints: _additionalConstraints);
  }

  BoxConstraints get _additionalConstraints {
    return BoxConstraints.tightFor(width: width, height: height);
  }

  @override
  void updateRenderObject(BuildContext context, RenderConstrainedBox renderObject) {
    renderObject.additionalConstraints = _additionalConstraints;
  }

  @override
  String toStringShort() {
    final String type = switch ((width, height)) {
      (double.infinity, double.infinity) => '${objectRuntimeType(this, 'SizedBox')}.expand',
      (0.0, 0.0) => '${objectRuntimeType(this, 'SizedBox')}.shrink',
      _ => objectRuntimeType(this, 'SizedBox'),
    };
    return key == null ? type : '$type-$key';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    final DiagnosticLevel level;
    if ((width == double.infinity && height == double.infinity) ||
        (width == 0.0 && height == 0.0)) {
      level = DiagnosticLevel.hidden;
    } else {
      level = DiagnosticLevel.info;
    }
    properties.add(DoubleProperty('width', width, defaultValue: null, level: level));
    properties.add(DoubleProperty('height', height, defaultValue: null, level: level));
  }
}

/// A widget that imposes additional constraints on its child.
///
/// For example, if you wanted [child] to have a minimum height of 50.0 logical
/// pixels, you could use `const BoxConstraints(minHeight: 50.0)` as the
/// [constraints].
///
/// {@youtube 560 315 https://www.youtube.com/watch?v=o2KveVr7adg}
///
/// {@tool snippet}
///
/// This snippet makes the child widget (a [Card] with some [Text]) fill the
/// parent, by applying [BoxConstraints.expand] constraints:

