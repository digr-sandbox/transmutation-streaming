// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// DO NOT EDIT - unless you are editing documentation as per:
// https://code.google.com/p/dart/wiki/ContributingHTMLDocumentation
// Auto-generated dart:html library.

/// HTML elements and other resources for web-based applications that need to
/// interact with the browser and the DOM (Document Object Model).
///
/// > [!Note]
/// > This core library is deprecated, and scheduled for removal in late 2025.
/// > It has been replaced by [package:web](https://pub.dev/packages/web).
/// > The [migration guide](https://dart.dev/go/package-web) has more details.
///
/// This library includes DOM element types, CSS styling, local storage,
/// media, speech, events, and more.
/// To get started,
/// check out the [Element] class, the base class for many of the HTML
/// DOM types.
///
/// For information on writing web apps with Dart, see https://dart.dev/web.
///
/// {@category Web (Legacy)}
/// {@canonicalFor dart:_internal.HttpStatus}
@Deprecated('Use package:web and dart:js_interop instead.')
library dart.dom.html;

import 'dart:async';
import 'dart:collection' hide LinkedList, LinkedListEntry;
import 'dart:_internal' hide Symbol;
import 'dart:html_common';
import 'dart:indexed_db';
import "dart:convert";
import 'dart:math';
import 'dart:_native_typed_data';
import 'dart:typed_data';
import 'dart:svg' as svg;
import 'dart:svg' show Matrix;
import 'dart:svg' show SvgSvgElement;
import 'dart:web_audio' as web_audio;
import 'dart:web_audio' show AudioBuffer, AudioTrack, AudioTrackList;
import 'dart:web_gl' as gl;
import 'dart:web_gl' show RenderingContext, RenderingContext2;
import 'dart:_foreign_helper' show JS, JS_INTERCEPTOR_CONSTANT;
import 'dart:js_util' as js_util;

export 'dart:_native_typed_data' show SharedArrayBuffer;
// Not actually used, but imported since dart:html can generate these objects.
import 'dart:_js_helper'
    show
        convertDartClosureToJS,
        Creates,
        JavaScriptIndexingBehavior,
        JSName,
        Native,
        Returns,
        findDispatchTagForInterceptorClass,
        setNativeSubclassDispatchRecord,
        makeLeafDispatchRecord,
        registerGlobalObject,
        applyExtension;
import 'dart:_interceptors'
    show
        JavaScriptObject,
        JavaScriptFunction,
        JSExtendableArray,
        JSUInt31,
        findInterceptorConstructorForType,
        findConstructorForNativeSubclassType,
        getNativeInterceptor,
        setDispatchProperty;

export 'dart:_internal' show HttpStatus;
export 'dart:html_common' show promiseToFuture;
export 'dart:math' show Rectangle, Point;

/**
 * Top-level container for a web page, which is usually a browser tab or window.
 *
 * Each web page loaded in the browser has its own [Window], which is a
 * container for the web page.
 *
 * If the web page has any `<iframe>` elements, then each `<iframe>` has its own
 * [Window] object, which is accessible only to that `<iframe>`.
 *
 * See also:
 *
 *   * [Window](https://developer.mozilla.org/en-US/docs/Web/API/window) from MDN.
 */
Window get window => JS('Window', 'window');

/**
 * Root node for all content in a web page.
 */
HtmlDocument get document =>
    JS('returns:HtmlDocument;depends:none;effects:none;gvn:true', 'document');

/// Convert a JS Promise to a Future<Map<String, dynamic>>.
///
/// On a successful result the native JS result will be converted to a Dart Map.
/// See [convertNativeToDart_Dictionary]. On a rejected promise the error is
/// forwarded without change.
Future<Map<String, dynamic>?> promiseToFutureAsMap(jsPromise) =>
    promiseToFuture(jsPromise).then(convertNativeToDart_Dictionary);

// Workaround for tags like <cite> that lack their own Element subclass --
// Dart issue 1990.
@Native("HTMLElement")
class HtmlElement extends Element implements NoncedElement {
  factory HtmlElement() {
    throw new UnsupportedError("Not supported");
  }

  // From NoncedElement
  String? get nonce native;
  set nonce(String? value) native;
}

/**
 * Emitted for any setlike IDL entry needs a callback signature.
 * Today there is only one.
 */
typedef void FontFaceSetForEachCallback(
  FontFace fontFace,
  FontFace fontFaceAgain,
  FontFaceSet set,
);

WorkerGlobalScope get _workerSelf => JS('WorkerGlobalScope', 'self');
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AbortPaymentEvent")
class AbortPaymentEvent extends ExtendableEvent {
  // To suppress missing implicit constructor warnings.
  factory AbortPaymentEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory AbortPaymentEvent(String type, Map eventInitDict) {
    var eventInitDict_1 = convertDartToNative_Dictionary(eventInitDict);
    return AbortPaymentEvent._create_1(type, eventInitDict_1);
  }
  static AbortPaymentEvent _create_1(type, eventInitDict) => JS(
    'AbortPaymentEvent',
    'new AbortPaymentEvent(#,#)',
    type,
    eventInitDict,
  );

  void respondWith(Future paymentAbortedResponse) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AbsoluteOrientationSensor")
class AbsoluteOrientationSensor extends OrientationSensor {
  // To suppress missing implicit constructor warnings.
  factory AbsoluteOrientationSensor._() {
    throw new UnsupportedError("Not supported");
  }

  factory AbsoluteOrientationSensor([Map? sensorOptions]) {
    if (sensorOptions != null) {
      var sensorOptions_1 = convertDartToNative_Dictionary(sensorOptions);
      return AbsoluteOrientationSensor._create_1(sensorOptions_1);
    }
    return AbsoluteOrientationSensor._create_2();
  }
  static AbsoluteOrientationSensor _create_1(sensorOptions) => JS(
    'AbsoluteOrientationSensor',
    'new AbsoluteOrientationSensor(#)',
    sensorOptions,
  );
  static AbsoluteOrientationSensor _create_2() =>
      JS('AbsoluteOrientationSensor', 'new AbsoluteOrientationSensor()');
}
// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

abstract class AbstractWorker extends JavaScriptObject implements EventTarget {
  // To suppress missing implicit constructor warnings.
  factory AbstractWorker._() {
    throw new UnsupportedError("Not supported");
  }

  /**
   * Static factory designed to expose `error` events to event
   * handlers that are not necessarily instances of [AbstractWorker].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> errorEvent =
      const EventStreamProvider<Event>('error');

  /// Stream of `error` events handled by this [AbstractWorker].
  Stream<Event> get onError => errorEvent.forTarget(this);
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("Accelerometer")
class Accelerometer extends Sensor {
  // To suppress missing implicit constructor warnings.
  factory Accelerometer._() {
    throw new UnsupportedError("Not supported");
  }

  factory Accelerometer([Map? sensorOptions]) {
    if (sensorOptions != null) {
      var sensorOptions_1 = convertDartToNative_Dictionary(sensorOptions);
      return Accelerometer._create_1(sensorOptions_1);
    }
    return Accelerometer._create_2();
  }
  static Accelerometer _create_1(sensorOptions) =>
      JS('Accelerometer', 'new Accelerometer(#)', sensorOptions);
  static Accelerometer _create_2() =>
      JS('Accelerometer', 'new Accelerometer()');

  num? get x native;

  num? get y native;

  num? get z native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AccessibleNode")
class AccessibleNode extends EventTarget {
  // To suppress missing implicit constructor warnings.
  factory AccessibleNode._() {
    throw new UnsupportedError("Not supported");
  }

  static const EventStreamProvider<Event> accessibleClickEvent =
      const EventStreamProvider<Event>('accessibleclick');

  static const EventStreamProvider<Event> accessibleContextMenuEvent =
      const EventStreamProvider<Event>('accessiblecontextmenu');

  static const EventStreamProvider<Event> accessibleDecrementEvent =
      const EventStreamProvider<Event>('accessibledecrement');

  static const EventStreamProvider<Event> accessibleFocusEvent =
      const EventStreamProvider<Event>('accessiblefocus');

  static const EventStreamProvider<Event> accessibleIncrementEvent =
      const EventStreamProvider<Event>('accessibleincrement');

  static const EventStreamProvider<Event> accessibleScrollIntoViewEvent =
      const EventStreamProvider<Event>('accessiblescrollintoview');

  factory AccessibleNode() {
    return AccessibleNode._create_1();
  }
  static AccessibleNode _create_1() =>
      JS('AccessibleNode', 'new AccessibleNode()');

  AccessibleNode? get activeDescendant native;

  set activeDescendant(AccessibleNode? value) native;

  bool? get atomic native;

  set atomic(bool? value) native;

  String? get autocomplete native;

  set autocomplete(String? value) native;

  bool? get busy native;

  set busy(bool? value) native;

  String? get checked native;

  set checked(String? value) native;

  int? get colCount native;

  set colCount(int? value) native;

  int? get colIndex native;

  set colIndex(int? value) native;

  int? get colSpan native;

  set colSpan(int? value) native;

  AccessibleNodeList? get controls native;

  set controls(AccessibleNodeList? value) native;

  String? get current native;

  set current(String? value) native;

  AccessibleNodeList? get describedBy native;

  set describedBy(AccessibleNodeList? value) native;

  AccessibleNode? get details native;

  set details(AccessibleNode? value) native;

  bool? get disabled native;

  set disabled(bool? value) native;

  AccessibleNode? get errorMessage native;

  set errorMessage(AccessibleNode? value) native;

  bool? get expanded native;

  set expanded(bool? value) native;

  AccessibleNodeList? get flowTo native;

  set flowTo(AccessibleNodeList? value) native;

  String? get hasPopUp native;

  set hasPopUp(String? value) native;

  bool? get hidden native;

  set hidden(bool? value) native;

  String? get invalid native;

  set invalid(String? value) native;

  String? get keyShortcuts native;

  set keyShortcuts(String? value) native;

  String? get label native;

  set label(String? value) native;

  AccessibleNodeList? get labeledBy native;

  set labeledBy(AccessibleNodeList? value) native;

  int? get level native;

  set level(int? value) native;

  String? get live native;

  set live(String? value) native;

  bool? get modal native;

  set modal(bool? value) native;

  bool? get multiline native;

  set multiline(bool? value) native;

  bool? get multiselectable native;

  set multiselectable(bool? value) native;

  String? get orientation native;

  set orientation(String? value) native;

  AccessibleNodeList? get owns native;

  set owns(AccessibleNodeList? value) native;

  String? get placeholder native;

  set placeholder(String? value) native;

  int? get posInSet native;

  set posInSet(int? value) native;

  String? get pressed native;

  set pressed(String? value) native;

  bool? get readOnly native;

  set readOnly(bool? value) native;

  String? get relevant native;

  set relevant(String? value) native;

  bool? get required native;

  set required(bool? value) native;

  String? get role native;

  set role(String? value) native;

  String? get roleDescription native;

  set roleDescription(String? value) native;

  int? get rowCount native;

  set rowCount(int? value) native;

  int? get rowIndex native;

  set rowIndex(int? value) native;

  int? get rowSpan native;

  set rowSpan(int? value) native;

  bool? get selected native;

  set selected(bool? value) native;

  int? get setSize native;

  set setSize(int? value) native;

  String? get sort native;

  set sort(String? value) native;

  num? get valueMax native;

  set valueMax(num? value) native;

  num? get valueMin native;

  set valueMin(num? value) native;

  num? get valueNow native;

  set valueNow(num? value) native;

  String? get valueText native;

  set valueText(String? value) native;

  void appendChild(AccessibleNode child) native;

  Stream<Event> get onAccessibleClick => accessibleClickEvent.forTarget(this);

  Stream<Event> get onAccessibleContextMenu =>
      accessibleContextMenuEvent.forTarget(this);

  Stream<Event> get onAccessibleDecrement =>
      accessibleDecrementEvent.forTarget(this);

  Stream<Event> get onAccessibleFocus => accessibleFocusEvent.forTarget(this);

  Stream<Event> get onAccessibleIncrement =>
      accessibleIncrementEvent.forTarget(this);

  Stream<Event> get onAccessibleScrollIntoView =>
      accessibleScrollIntoViewEvent.forTarget(this);
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AccessibleNodeList")
class AccessibleNodeList extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory AccessibleNodeList._() {
    throw new UnsupportedError("Not supported");
  }

  factory AccessibleNodeList([List<AccessibleNode>? nodes]) {
    if (nodes != null) {
      return AccessibleNodeList._create_1(nodes);
    }
    return AccessibleNodeList._create_2();
  }
  static AccessibleNodeList _create_1(nodes) =>
      JS('AccessibleNodeList', 'new AccessibleNodeList(#)', nodes);
  static AccessibleNodeList _create_2() =>
      JS('AccessibleNodeList', 'new AccessibleNodeList()');

  int? get length native;

  set length(int? value) native;

  void __setter__(int index, AccessibleNode node) native;

  void add(AccessibleNode node, AccessibleNode? before) native;

  AccessibleNode? item(int index) native;

  void remove(int index) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AmbientLightSensor")
class AmbientLightSensor extends Sensor {
  // To suppress missing implicit constructor warnings.
  factory AmbientLightSensor._() {
    throw new UnsupportedError("Not supported");
  }

  factory AmbientLightSensor([Map? sensorOptions]) {
    if (sensorOptions != null) {
      var sensorOptions_1 = convertDartToNative_Dictionary(sensorOptions);
      return AmbientLightSensor._create_1(sensorOptions_1);
    }
    return AmbientLightSensor._create_2();
  }
  static AmbientLightSensor _create_1(sensorOptions) =>
      JS('AmbientLightSensor', 'new AmbientLightSensor(#)', sensorOptions);
  static AmbientLightSensor _create_2() =>
      JS('AmbientLightSensor', 'new AmbientLightSensor()');

  num? get illuminance native;
}
// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("HTMLAnchorElement")
class AnchorElement extends HtmlElement implements HtmlHyperlinkElementUtils {
  // To suppress missing implicit constructor warnings.
  factory AnchorElement._() {
    throw new UnsupportedError("Not supported");
  }

  factory AnchorElement({String? href}) {
    AnchorElement e = JS<AnchorElement>(
      'returns:AnchorElement;creates:AnchorElement;new:true',
      '#.createElement(#)',
      document,
      "a",
    );
    if (href != null) e.href = href;
    return e;
  }

  String? get download native;

  set download(String? value) native;

  String get hreflang native;

  set hreflang(String value) native;

  String? get referrerPolicy native;

  set referrerPolicy(String? value) native;

  String get rel native;

  set rel(String value) native;

  String get target native;

  set target(String value) native;

  String get type native;

  set type(String value) native;

  // From HTMLHyperlinkElementUtils

  String? get hash native;

  set hash(String? value) native;

  String? get host native;

  set host(String? value) native;

  String? get hostname native;

  set hostname(String? value) native;

  String? get href native;

  set href(String? value) native;

  String? get origin native;

  String? get password native;

  set password(String? value) native;

  String? get pathname native;

  set pathname(String? value) native;

  String? get port native;

  set port(String? value) native;

  String? get protocol native;

  set protocol(String? value) native;

  String? get search native;

  set search(String? value) native;

  String? get username native;

  set username(String? value) native;

  String toString() => JS('String', 'String(#)', this);
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("Animation")
class Animation extends EventTarget {
  // To suppress missing implicit constructor warnings.
  factory Animation._() {
    throw new UnsupportedError("Not supported");
  }

  static const EventStreamProvider<Event> cancelEvent =
      const EventStreamProvider<Event>('cancel');

  static const EventStreamProvider<Event> finishEvent =
      const EventStreamProvider<Event>('finish');

  factory Animation([
    AnimationEffectReadOnly? effect,
    AnimationTimeline? timeline,
  ]) {
    if (timeline != null) {
      return Animation._create_1(effect, timeline);
    }
    if (effect != null) {
      return Animation._create_2(effect);
    }
    return Animation._create_3();
  }
  static Animation _create_1(effect, timeline) =>
      JS('Animation', 'new Animation(#,#)', effect, timeline);
  static Animation _create_2(effect) =>
      JS('Animation', 'new Animation(#)', effect);
  static Animation _create_3() => JS('Animation', 'new Animation()');

  /// Checks if this type is supported on the current platform.
  static bool get supported => JS('bool', '!!(document.body.animate)');

  num? get currentTime native;

  set currentTime(num? value) native;

  AnimationEffectReadOnly? get effect native;

  set effect(AnimationEffectReadOnly? value) native;

  Future<Animation> get finished =>
      promiseToFuture<Animation>(JS("creates:Animation;", "#.finished", this));

  String? get id native;

  set id(String? value) native;

  String? get playState native;

  num? get playbackRate native;

  set playbackRate(num? value) native;

  Future<Animation> get ready =>
      promiseToFuture<Animation>(JS("creates:Animation;", "#.ready", this));

  num? get startTime native;

  set startTime(num? value) native;

  AnimationTimeline? get timeline native;

  void cancel() native;

  void finish() native;

  void pause() native;

  void play() native;

  void reverse() native;

  Stream<Event> get onCancel => cancelEvent.forTarget(this);

  Stream<Event> get onFinish => finishEvent.forTarget(this);
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AnimationEffectReadOnly")
class AnimationEffectReadOnly extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory AnimationEffectReadOnly._() {
    throw new UnsupportedError("Not supported");
  }

  AnimationEffectTimingReadOnly? get timing native;

  Map getComputedTiming() {
    return convertNativeToDart_Dictionary(_getComputedTiming_1())!;
  }

  @JSName('getComputedTiming')
  _getComputedTiming_1() native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AnimationEffectTiming")
class AnimationEffectTiming extends AnimationEffectTimingReadOnly {
  // To suppress missing implicit constructor warnings.
  factory AnimationEffectTiming._() {
    throw new UnsupportedError("Not supported");
  }

  // Shadowing definition.

  num? get delay native;

  set delay(num? value) native;

  // Shadowing definition.

  String? get direction native;

  set direction(String? value) native;

  // Shadowing definition.

  @Returns('num|String|Null')
  Object? get duration native;

  set duration(Object? value) native;

  // Shadowing definition.

  String? get easing native;

  set easing(String? value) native;

  // Shadowing definition.

  num? get endDelay native;

  set endDelay(num? value) native;

  // Shadowing definition.

  String? get fill native;

  set fill(String? value) native;

  // Shadowing definition.

  num? get iterationStart native;

  set iterationStart(num? value) native;

  // Shadowing definition.

  num? get iterations native;

  set iterations(num? value) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AnimationEffectTimingReadOnly")
class AnimationEffectTimingReadOnly extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory AnimationEffectTimingReadOnly._() {
    throw new UnsupportedError("Not supported");
  }

  num? get delay native;

  String? get direction native;

  Object? get duration native;

  String? get easing native;

  num? get endDelay native;

  String? get fill native;

  num? get iterationStart native;

  num? get iterations native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AnimationEvent")
class AnimationEvent extends Event {
  // To suppress missing implicit constructor warnings.
  factory AnimationEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory AnimationEvent(String type, [Map? eventInitDict]) {
    if (eventInitDict != null) {
      var eventInitDict_1 = convertDartToNative_Dictionary(eventInitDict);
      return AnimationEvent._create_1(type, eventInitDict_1);
    }
    return AnimationEvent._create_2(type);
  }
  static AnimationEvent _create_1(type, eventInitDict) =>
      JS('AnimationEvent', 'new AnimationEvent(#,#)', type, eventInitDict);
  static AnimationEvent _create_2(type) =>
      JS('AnimationEvent', 'new AnimationEvent(#)', type);

  String? get animationName native;

  num? get elapsedTime native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AnimationPlaybackEvent")
class AnimationPlaybackEvent extends Event {
  // To suppress missing implicit constructor warnings.
  factory AnimationPlaybackEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory AnimationPlaybackEvent(String type, [Map? eventInitDict]) {
    if (eventInitDict != null) {
      var eventInitDict_1 = convertDartToNative_Dictionary(eventInitDict);
      return AnimationPlaybackEvent._create_1(type, eventInitDict_1);
    }
    return AnimationPlaybackEvent._create_2(type);
  }
  static AnimationPlaybackEvent _create_1(type, eventInitDict) => JS(
    'AnimationPlaybackEvent',
    'new AnimationPlaybackEvent(#,#)',
    type,
    eventInitDict,
  );
  static AnimationPlaybackEvent _create_2(type) =>
      JS('AnimationPlaybackEvent', 'new AnimationPlaybackEvent(#)', type);

  num? get currentTime native;

  num? get timelineTime native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AnimationTimeline")
class AnimationTimeline extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory AnimationTimeline._() {
    throw new UnsupportedError("Not supported");
  }

  num? get currentTime native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AnimationWorkletGlobalScope")
class AnimationWorkletGlobalScope extends WorkletGlobalScope {
  // To suppress missing implicit constructor warnings.
  factory AnimationWorkletGlobalScope._() {
    throw new UnsupportedError("Not supported");
  }

  void registerAnimator(String name, Object animatorConstructor) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * ApplicationCache is accessed via [Window.applicationCache].
 */
@SupportedBrowser(SupportedBrowser.CHROME)
@SupportedBrowser(SupportedBrowser.FIREFOX)
@SupportedBrowser(SupportedBrowser.IE, '10')
@SupportedBrowser(SupportedBrowser.OPERA)
@SupportedBrowser(SupportedBrowser.SAFARI)
@Unstable()
@Native("ApplicationCache,DOMApplicationCache,OfflineResourceList")
class ApplicationCache extends EventTarget {
  // To suppress missing implicit constructor warnings.
  factory ApplicationCache._() {
    throw new UnsupportedError("Not supported");
  }

  /**
   * Static factory designed to expose `cached` events to event
   * handlers that are not necessarily instances of [ApplicationCache].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> cachedEvent =
      const EventStreamProvider<Event>('cached');

  /**
   * Static factory designed to expose `checking` events to event
   * handlers that are not necessarily instances of [ApplicationCache].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> checkingEvent =
      const EventStreamProvider<Event>('checking');

  /**
   * Static factory designed to expose `downloading` events to event
   * handlers that are not necessarily instances of [ApplicationCache].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> downloadingEvent =
      const EventStreamProvider<Event>('downloading');

  /**
   * Static factory designed to expose `error` events to event
   * handlers that are not necessarily instances of [ApplicationCache].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> errorEvent =
      const EventStreamProvider<Event>('error');

  /**
   * Static factory designed to expose `noupdate` events to event
   * handlers that are not necessarily instances of [ApplicationCache].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> noUpdateEvent =
      const EventStreamProvider<Event>('noupdate');

  /**
   * Static factory designed to expose `obsolete` events to event
   * handlers that are not necessarily instances of [ApplicationCache].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> obsoleteEvent =
      const EventStreamProvider<Event>('obsolete');

  /**
   * Static factory designed to expose `progress` events to event
   * handlers that are not necessarily instances of [ApplicationCache].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<ProgressEvent> progressEvent =
      const EventStreamProvider<ProgressEvent>('progress');

  /**
   * Static factory designed to expose `updateready` events to event
   * handlers that are not necessarily instances of [ApplicationCache].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> updateReadyEvent =
      const EventStreamProvider<Event>('updateready');

  /// Checks if this type is supported on the current platform.
  static bool get supported => JS('bool', '!!(window.applicationCache)');

  static const int CHECKING = 2;

  static const int DOWNLOADING = 3;

  static const int IDLE = 1;

  static const int OBSOLETE = 5;

  static const int UNCACHED = 0;

  static const int UPDATEREADY = 4;

  int? get status native;

  void abort() native;

  void swapCache() native;

  void update() native;

  /// Stream of `cached` events handled by this [ApplicationCache].
  Stream<Event> get onCached => cachedEvent.forTarget(this);

  /// Stream of `checking` events handled by this [ApplicationCache].
  Stream<Event> get onChecking => checkingEvent.forTarget(this);

  /// Stream of `downloading` events handled by this [ApplicationCache].
  Stream<Event> get onDownloading => downloadingEvent.forTarget(this);

  /// Stream of `error` events handled by this [ApplicationCache].
  Stream<Event> get onError => errorEvent.forTarget(this);

  /// Stream of `noupdate` events handled by this [ApplicationCache].
  Stream<Event> get onNoUpdate => noUpdateEvent.forTarget(this);

  /// Stream of `obsolete` events handled by this [ApplicationCache].
  Stream<Event> get onObsolete => obsoleteEvent.forTarget(this);

  /// Stream of `progress` events handled by this [ApplicationCache].
  Stream<ProgressEvent> get onProgress => progressEvent.forTarget(this);

  /// Stream of `updateready` events handled by this [ApplicationCache].
  Stream<Event> get onUpdateReady => updateReadyEvent.forTarget(this);
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("ApplicationCacheErrorEvent")
class ApplicationCacheErrorEvent extends Event {
  // To suppress missing implicit constructor warnings.
  factory ApplicationCacheErrorEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory ApplicationCacheErrorEvent(String type, [Map? eventInitDict]) {
    if (eventInitDict != null) {
      var eventInitDict_1 = convertDartToNative_Dictionary(eventInitDict);
      return ApplicationCacheErrorEvent._create_1(type, eventInitDict_1);
    }
    return ApplicationCacheErrorEvent._create_2(type);
  }
  static ApplicationCacheErrorEvent _create_1(type, eventInitDict) => JS(
    'ApplicationCacheErrorEvent',
    'new ApplicationCacheErrorEvent(#,#)',
    type,
    eventInitDict,
  );
  static ApplicationCacheErrorEvent _create_2(type) => JS(
    'ApplicationCacheErrorEvent',
    'new ApplicationCacheErrorEvent(#)',
    type,
  );

  String? get message native;

  String? get reason native;

  int? get status native;

  String? get url native;
}
// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * DOM Area Element, which links regions of an image map with a hyperlink.
 *
 * The element can also define an uninteractive region of the map.
 *
 * See also:
 *
 * * [`<area>`](https://developer.mozilla.org/en-US/docs/HTML/Element/area)
 * on MDN.
 */
@Native("HTMLAreaElement")
class AreaElement extends HtmlElement implements HtmlHyperlinkElementUtils {
  // To suppress missing implicit constructor warnings.
  factory AreaElement._() {
    throw new UnsupportedError("Not supported");
  }

  factory AreaElement() => JS<AreaElement>(
    'returns:AreaElement;creates:AreaElement;new:true',
    '#.createElement(#)',
    document,
    "area",
  );

  String get alt native;

  set alt(String value) native;

  String get coords native;

  set coords(String value) native;

  String? get download native;

  set download(String? value) native;

  String? get referrerPolicy native;

  set referrerPolicy(String? value) native;

  String get rel native;

  set rel(String value) native;

  String get shape native;

  set shape(String value) native;

  String get target native;

  set target(String value) native;

  // From HTMLHyperlinkElementUtils

  String? get hash native;

  set hash(String? value) native;

  String? get host native;

  set host(String? value) native;

  String? get hostname native;

  set hostname(String? value) native;

  String? get href native;

  set href(String? value) native;

  String? get origin native;

  String? get password native;

  set password(String? value) native;

  String? get pathname native;

  set pathname(String? value) native;

  String? get port native;

  set port(String? value) native;

  String? get protocol native;

  set protocol(String? value) native;

  String? get search native;

  set search(String? value) native;

  String? get username native;

  set username(String? value) native;

  String toString() => JS('String', 'String(#)', this);
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("HTMLAudioElement")
class AudioElement extends MediaElement {
  factory AudioElement._([String? src]) {
    if (src != null) {
      return AudioElement._create_1(src);
    }
    return AudioElement._create_2();
  }
  static AudioElement _create_1(src) => JS('AudioElement', 'new Audio(#)', src);
  static AudioElement _create_2() => JS('AudioElement', 'new Audio()');

  factory AudioElement([String? src]) => new AudioElement._(src);
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AuthenticatorAssertionResponse")
class AuthenticatorAssertionResponse extends AuthenticatorResponse {
  // To suppress missing implicit constructor warnings.
  factory AuthenticatorAssertionResponse._() {
    throw new UnsupportedError("Not supported");
  }

  ByteBuffer? get authenticatorData native;

  ByteBuffer? get signature native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AuthenticatorAttestationResponse")
class AuthenticatorAttestationResponse extends AuthenticatorResponse {
  // To suppress missing implicit constructor warnings.
  factory AuthenticatorAttestationResponse._() {
    throw new UnsupportedError("Not supported");
  }

  ByteBuffer? get attestationObject native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("AuthenticatorResponse")
class AuthenticatorResponse extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory AuthenticatorResponse._() {
    throw new UnsupportedError("Not supported");
  }

  @JSName('clientDataJSON')
  ByteBuffer? get clientDataJson native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("HTMLBRElement")
class BRElement extends HtmlElement {
  // To suppress missing implicit constructor warnings.
  factory BRElement._() {
    throw new UnsupportedError("Not supported");
  }

  factory BRElement() => JS<BRElement>(
    'returns:BRElement;creates:BRElement;new:true',
    '#.createElement(#)',
    document,
    "br",
  );
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BackgroundFetchClickEvent")
class BackgroundFetchClickEvent extends BackgroundFetchEvent {
  // To suppress missing implicit constructor warnings.
  factory BackgroundFetchClickEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory BackgroundFetchClickEvent(String type, Map init) {
    var init_1 = convertDartToNative_Dictionary(init);
    return BackgroundFetchClickEvent._create_1(type, init_1);
  }
  static BackgroundFetchClickEvent _create_1(type, init) => JS(
    'BackgroundFetchClickEvent',
    'new BackgroundFetchClickEvent(#,#)',
    type,
    init,
  );

  String? get state native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BackgroundFetchEvent")
class BackgroundFetchEvent extends ExtendableEvent {
  // To suppress missing implicit constructor warnings.
  factory BackgroundFetchEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory BackgroundFetchEvent(String type, Map init) {
    var init_1 = convertDartToNative_Dictionary(init);
    return BackgroundFetchEvent._create_1(type, init_1);
  }
  static BackgroundFetchEvent _create_1(type, init) =>
      JS('BackgroundFetchEvent', 'new BackgroundFetchEvent(#,#)', type, init);

  String? get id native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BackgroundFetchFailEvent")
class BackgroundFetchFailEvent extends BackgroundFetchEvent {
  // To suppress missing implicit constructor warnings.
  factory BackgroundFetchFailEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory BackgroundFetchFailEvent(String type, Map init) {
    var init_1 = convertDartToNative_Dictionary(init);
    return BackgroundFetchFailEvent._create_1(type, init_1);
  }
  static BackgroundFetchFailEvent _create_1(type, init) => JS(
    'BackgroundFetchFailEvent',
    'new BackgroundFetchFailEvent(#,#)',
    type,
    init,
  );

  List<BackgroundFetchSettledFetch>? get fetches native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BackgroundFetchFetch")
class BackgroundFetchFetch extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory BackgroundFetchFetch._() {
    throw new UnsupportedError("Not supported");
  }

  _Request? get request native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BackgroundFetchManager")
class BackgroundFetchManager extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory BackgroundFetchManager._() {
    throw new UnsupportedError("Not supported");
  }

  Future<BackgroundFetchRegistration> fetch(
    String id,
    Object requests, [
    Map? options,
  ]) {
    var options_dict = null;
    if (options != null) {
      options_dict = convertDartToNative_Dictionary(options);
    }
    return promiseToFuture<BackgroundFetchRegistration>(
      JS(
        "creates:BackgroundFetchRegistration;",
        "#.fetch(#, #, #)",
        this,
        id,
        requests,
        options_dict,
      ),
    );
  }

  Future<BackgroundFetchRegistration> get(String id) =>
      promiseToFuture<BackgroundFetchRegistration>(
        JS("creates:BackgroundFetchRegistration;", "#.get(#)", this, id),
      );

  Future<List<dynamic>> getIds() =>
      promiseToFuture<List<dynamic>>(JS("", "#.getIds()", this));
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BackgroundFetchRegistration")
class BackgroundFetchRegistration extends EventTarget {
  // To suppress missing implicit constructor warnings.
  factory BackgroundFetchRegistration._() {
    throw new UnsupportedError("Not supported");
  }

  int? get downloadTotal native;

  int? get downloaded native;

  String? get id native;

  String? get title native;

  int? get totalDownloadSize native;

  int? get uploadTotal native;

  int? get uploaded native;

  Future<bool> abort() => promiseToFuture<bool>(JS("", "#.abort()", this));
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BackgroundFetchSettledFetch")
class BackgroundFetchSettledFetch extends BackgroundFetchFetch {
  // To suppress missing implicit constructor warnings.
  factory BackgroundFetchSettledFetch._() {
    throw new UnsupportedError("Not supported");
  }

  factory BackgroundFetchSettledFetch(_Request request, _Response response) {
    return BackgroundFetchSettledFetch._create_1(request, response);
  }
  static BackgroundFetchSettledFetch _create_1(request, response) => JS(
    'BackgroundFetchSettledFetch',
    'new BackgroundFetchSettledFetch(#,#)',
    request,
    response,
  );

  _Response? get response native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BackgroundFetchedEvent")
class BackgroundFetchedEvent extends BackgroundFetchEvent {
  // To suppress missing implicit constructor warnings.
  factory BackgroundFetchedEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory BackgroundFetchedEvent(String type, Map init) {
    var init_1 = convertDartToNative_Dictionary(init);
    return BackgroundFetchedEvent._create_1(type, init_1);
  }
  static BackgroundFetchedEvent _create_1(type, init) => JS(
    'BackgroundFetchedEvent',
    'new BackgroundFetchedEvent(#,#)',
    type,
    init,
  );

  List<BackgroundFetchSettledFetch>? get fetches native;

  Future updateUI(String title) =>
      promiseToFuture(JS("", "#.updateUI(#)", this, title));
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// http://www.whatwg.org/specs/web-apps/current-work/multipage/browsers.html#barprop
@deprecated // standard
@Native("BarProp")
class BarProp extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory BarProp._() {
    throw new UnsupportedError("Not supported");
  }

  bool? get visible native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BarcodeDetector")
class BarcodeDetector extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory BarcodeDetector._() {
    throw new UnsupportedError("Not supported");
  }

  factory BarcodeDetector() {
    return BarcodeDetector._create_1();
  }
  static BarcodeDetector _create_1() =>
      JS('BarcodeDetector', 'new BarcodeDetector()');

  Future<List<dynamic>> detect(/*ImageBitmapSource*/ image) =>
      promiseToFuture<List<dynamic>>(JS("", "#.detect(#)", this, image));
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("HTMLBaseElement")
class BaseElement extends HtmlElement {
  // To suppress missing implicit constructor warnings.
  factory BaseElement._() {
    throw new UnsupportedError("Not supported");
  }

  factory BaseElement() => JS<BaseElement>(
    'returns:BaseElement;creates:BaseElement;new:true',
    '#.createElement(#)',
    document,
    "base",
  );

  String get href native;

  set href(String value) native;

  String get target native;

  set target(String value) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BatteryManager")
class BatteryManager extends EventTarget {
  // To suppress missing implicit constructor warnings.
  factory BatteryManager._() {
    throw new UnsupportedError("Not supported");
  }

  bool? get charging native;

  num? get chargingTime native;

  num? get dischargingTime native;

  num? get level native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BeforeInstallPromptEvent")
class BeforeInstallPromptEvent extends Event {
  // To suppress missing implicit constructor warnings.
  factory BeforeInstallPromptEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory BeforeInstallPromptEvent(String type, [Map? eventInitDict]) {
    if (eventInitDict != null) {
      var eventInitDict_1 = convertDartToNative_Dictionary(eventInitDict);
      return BeforeInstallPromptEvent._create_1(type, eventInitDict_1);
    }
    return BeforeInstallPromptEvent._create_2(type);
  }
  static BeforeInstallPromptEvent _create_1(type, eventInitDict) => JS(
    'BeforeInstallPromptEvent',
    'new BeforeInstallPromptEvent(#,#)',
    type,
    eventInitDict,
  );
  static BeforeInstallPromptEvent _create_2(type) =>
      JS('BeforeInstallPromptEvent', 'new BeforeInstallPromptEvent(#)', type);

  List<String>? get platforms native;

  Future<Map<String, dynamic>?> get userChoice =>
      promiseToFutureAsMap(JS("", "#.userChoice", this));

  Future prompt() => promiseToFuture(JS("", "#.prompt()", this));
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BeforeUnloadEvent")
class BeforeUnloadEvent extends Event {
  // To suppress missing implicit constructor warnings.
  factory BeforeUnloadEvent._() {
    throw new UnsupportedError("Not supported");
  }

  // Shadowing definition.

  String? get returnValue native;

  set returnValue(String? value) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("Blob")
class Blob extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory Blob._() {
    throw new UnsupportedError("Not supported");
  }

  int get size native;

  String get type native;

  Blob slice([int? start, int? end, String? contentType]) native;

  factory Blob(List blobParts, [String? type, String? endings]) {
    // TODO: validate that blobParts is a JS Array and convert if not.
    // TODO: any coercions on the elements of blobParts, e.g. coerce a typed
    // array to ArrayBuffer if it is a total view.
    if (type == null && endings == null) {
      return _create_1(blobParts);
    }
    var bag = _create_bag();
    if (type != null) _bag_set(bag, 'type', type);
    if (endings != null) _bag_set(bag, 'endings', endings);
    return _create_2(blobParts, bag);
  }

  static _create_1(parts) => JS('Blob', 'new self.Blob(#)', parts);
  static _create_2(parts, bag) => JS('Blob', 'new self.Blob(#, #)', parts, bag);

  static _create_bag() => JS('var', '{}');
  static _bag_set(bag, key, value) {
    JS('void', '#[#] = #', bag, key, value);
  }
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// WARNING: Do not edit - generated code.

typedef void BlobCallback(Blob? blob);
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BlobEvent")
class BlobEvent extends Event {
  // To suppress missing implicit constructor warnings.
  factory BlobEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory BlobEvent(String type, Map eventInitDict) {
    var eventInitDict_1 = convertDartToNative_Dictionary(eventInitDict);
    return BlobEvent._create_1(type, eventInitDict_1);
  }
  static BlobEvent _create_1(type, eventInitDict) =>
      JS('BlobEvent', 'new BlobEvent(#,#)', type, eventInitDict);

  Blob? get data native;

  num? get timecode native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BluetoothRemoteGATTDescriptor")
class BluetoothRemoteGattDescriptor extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory BluetoothRemoteGattDescriptor._() {
    throw new UnsupportedError("Not supported");
  }

  _BluetoothRemoteGATTCharacteristic? get characteristic native;

  String? get uuid native;

  ByteData? get value native;

  Future readValue() => promiseToFuture(JS("", "#.readValue()", this));

  Future writeValue(/*BufferSource*/ value) =>
      promiseToFuture(JS("", "#.writeValue(#)", this, value));
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("Body")
class Body extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory Body._() {
    throw new UnsupportedError("Not supported");
  }

  bool? get bodyUsed native;

  Future arrayBuffer() => promiseToFuture(JS("", "#.arrayBuffer()", this));

  Future<Blob> blob() =>
      promiseToFuture<Blob>(JS("creates:Blob;", "#.blob()", this));

  Future<FormData> formData() =>
      promiseToFuture<FormData>(JS("creates:FormData;", "#.formData()", this));

  Future json() => promiseToFuture(JS("", "#.json()", this));

  Future<String> text() => promiseToFuture<String>(JS("", "#.text()", this));
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("HTMLBodyElement")
class BodyElement extends HtmlElement implements WindowEventHandlers {
  // To suppress missing implicit constructor warnings.
  factory BodyElement._() {
    throw new UnsupportedError("Not supported");
  }

  /**
   * Static factory designed to expose `blur` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> blurEvent =
      const EventStreamProvider<Event>('blur');

  /**
   * Static factory designed to expose `error` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> errorEvent =
      const EventStreamProvider<Event>('error');

  /**
   * Static factory designed to expose `focus` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> focusEvent =
      const EventStreamProvider<Event>('focus');

  /**
   * Static factory designed to expose `hashchange` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> hashChangeEvent =
      const EventStreamProvider<Event>('hashchange');

  /**
   * Static factory designed to expose `load` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> loadEvent =
      const EventStreamProvider<Event>('load');

  /**
   * Static factory designed to expose `message` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<MessageEvent> messageEvent =
      const EventStreamProvider<MessageEvent>('message');

  /**
   * Static factory designed to expose `offline` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> offlineEvent =
      const EventStreamProvider<Event>('offline');

  /**
   * Static factory designed to expose `online` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> onlineEvent =
      const EventStreamProvider<Event>('online');

  /**
   * Static factory designed to expose `popstate` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<PopStateEvent> popStateEvent =
      const EventStreamProvider<PopStateEvent>('popstate');

  /**
   * Static factory designed to expose `resize` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> resizeEvent =
      const EventStreamProvider<Event>('resize');

  static const EventStreamProvider<Event> scrollEvent =
      const EventStreamProvider<Event>('scroll');

  /**
   * Static factory designed to expose `storage` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<StorageEvent> storageEvent =
      const EventStreamProvider<StorageEvent>('storage');

  /**
   * Static factory designed to expose `unload` events to event
   * handlers that are not necessarily instances of [BodyElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<Event> unloadEvent =
      const EventStreamProvider<Event>('unload');

  factory BodyElement() => JS<BodyElement>(
    'returns:BodyElement;creates:BodyElement;new:true',
    '#.createElement(#)',
    document,
    "body",
  );

  /// Stream of `blur` events handled by this [BodyElement].
  ElementStream<Event> get onBlur => blurEvent.forElement(this);

  /// Stream of `error` events handled by this [BodyElement].
  ElementStream<Event> get onError => errorEvent.forElement(this);

  /// Stream of `focus` events handled by this [BodyElement].
  ElementStream<Event> get onFocus => focusEvent.forElement(this);

  /// Stream of `hashchange` events handled by this [BodyElement].
  ElementStream<Event> get onHashChange => hashChangeEvent.forElement(this);

  /// Stream of `load` events handled by this [BodyElement].
  ElementStream<Event> get onLoad => loadEvent.forElement(this);

  /// Stream of `message` events handled by this [BodyElement].
  ElementStream<MessageEvent> get onMessage => messageEvent.forElement(this);

  /// Stream of `offline` events handled by this [BodyElement].
  ElementStream<Event> get onOffline => offlineEvent.forElement(this);

  /// Stream of `online` events handled by this [BodyElement].
  ElementStream<Event> get onOnline => onlineEvent.forElement(this);

  /// Stream of `popstate` events handled by this [BodyElement].
  ElementStream<PopStateEvent> get onPopState => popStateEvent.forElement(this);

  /// Stream of `resize` events handled by this [BodyElement].
  ElementStream<Event> get onResize => resizeEvent.forElement(this);

  ElementStream<Event> get onScroll => scrollEvent.forElement(this);

  /// Stream of `storage` events handled by this [BodyElement].
  ElementStream<StorageEvent> get onStorage => storageEvent.forElement(this);

  /// Stream of `unload` events handled by this [BodyElement].
  ElementStream<Event> get onUnload => unloadEvent.forElement(this);
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BroadcastChannel")
class BroadcastChannel extends EventTarget {
  // To suppress missing implicit constructor warnings.
  factory BroadcastChannel._() {
    throw new UnsupportedError("Not supported");
  }

  static const EventStreamProvider<MessageEvent> messageEvent =
      const EventStreamProvider<MessageEvent>('message');

  factory BroadcastChannel(String name) {
    return BroadcastChannel._create_1(name);
  }
  static BroadcastChannel _create_1(name) =>
      JS('BroadcastChannel', 'new BroadcastChannel(#)', name);

  String? get name native;

  void close() native;

  void postMessage(Object message) native;

  Stream<MessageEvent> get onMessage => messageEvent.forTarget(this);
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("BudgetState")
class BudgetState extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory BudgetState._() {
    throw new UnsupportedError("Not supported");
  }

  num? get budgetAt native;

  int? get time native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("HTMLButtonElement")
class ButtonElement extends HtmlElement {
  // To suppress missing implicit constructor warnings.
  factory ButtonElement._() {
    throw new UnsupportedError("Not supported");
  }

  factory ButtonElement() => JS<ButtonElement>(
    'returns:ButtonElement;creates:ButtonElement;new:true',
    '#.createElement(#)',
    document,
    "button",
  );

  bool get autofocus native;

  set autofocus(bool value) native;

  bool get disabled native;

  set disabled(bool value) native;

  FormElement? get form native;

  String? get formAction native;

  set formAction(String? value) native;

  String? get formEnctype native;

  set formEnctype(String? value) native;

  String? get formMethod native;

  set formMethod(String? value) native;

  bool get formNoValidate native;

  set formNoValidate(bool value) native;

  String get formTarget native;

  set formTarget(String value) native;

  @Unstable()
  @Returns('NodeList')
  @Creates('NodeList')
  List<Node>? get labels native;

  String get name native;

  set name(String value) native;

  String get type native;

  set type(String value) native;

  String get validationMessage native;

  ValidityState get validity native;

  String get value native;

  set value(String value) native;

  bool get willValidate native;

  bool checkValidity() native;

  bool reportValidity() native;

  void setCustomValidity(String error) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// http://dom.spec.whatwg.org/#cdatasection
@deprecated // deprecated
@Native("CDATASection")
class CDataSection extends Text {
  // To suppress missing implicit constructor warnings.
  factory CDataSection._() {
    throw new UnsupportedError("Not supported");
  }
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("CacheStorage")
class CacheStorage extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory CacheStorage._() {
    throw new UnsupportedError("Not supported");
  }

  Future delete(String cacheName) =>
      promiseToFuture(JS("", "#.delete(#)", this, cacheName));

  Future has(String cacheName) =>
      promiseToFuture(JS("", "#.has(#)", this, cacheName));

  Future keys() => promiseToFuture(JS("", "#.keys()", this));

  Future match(/*RequestInfo*/ request, [Map? options]) {
    var options_dict = null;
    if (options != null) {
      options_dict = convertDartToNative_Dictionary(options);
    }
    return promiseToFuture(
      JS("creates:_Response;", "#.match(#, #)", this, request, options_dict),
    );
  }

  Future open(String cacheName) =>
      promiseToFuture(JS("creates:_Cache;", "#.open(#)", this, cacheName));
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("CanMakePaymentEvent")
class CanMakePaymentEvent extends ExtendableEvent {
  // To suppress missing implicit constructor warnings.
  factory CanMakePaymentEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory CanMakePaymentEvent(String type, Map eventInitDict) {
    var eventInitDict_1 = convertDartToNative_Dictionary(eventInitDict);
    return CanMakePaymentEvent._create_1(type, eventInitDict_1);
  }
  static CanMakePaymentEvent _create_1(type, eventInitDict) => JS(
    'CanMakePaymentEvent',
    'new CanMakePaymentEvent(#,#)',
    type,
    eventInitDict,
  );

  List? get methodData native;

  List? get modifiers native;

  String? get paymentRequestOrigin native;

  String? get topLevelOrigin native;

  void respondWith(Future canMakePaymentResponse) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("CanvasCaptureMediaStreamTrack")
class CanvasCaptureMediaStreamTrack extends MediaStreamTrack {
  // To suppress missing implicit constructor warnings.
  factory CanvasCaptureMediaStreamTrack._() {
    throw new UnsupportedError("Not supported");
  }

  CanvasElement? get canvas native;

  void requestFrame() native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("HTMLCanvasElement")
class CanvasElement extends HtmlElement implements CanvasImageSource {
  // To suppress missing implicit constructor warnings.
  factory CanvasElement._() {
    throw new UnsupportedError("Not supported");
  }

  /**
   * Static factory designed to expose `webglcontextlost` events to event
   * handlers that are not necessarily instances of [CanvasElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<gl.ContextEvent> webGlContextLostEvent =
      const EventStreamProvider<gl.ContextEvent>('webglcontextlost');

  /**
   * Static factory designed to expose `webglcontextrestored` events to event
   * handlers that are not necessarily instances of [CanvasElement].
   *
   * See [EventStreamProvider] for usage information.
   */
  static const EventStreamProvider<gl.ContextEvent> webGlContextRestoredEvent =
      const EventStreamProvider<gl.ContextEvent>('webglcontextrestored');

  factory CanvasElement({int? width, int? height}) {
    CanvasElement e = JS<CanvasElement>(
      'returns:CanvasElement;creates:CanvasElement;new:true',
      '#.createElement(#)',
      document,
      "canvas",
    );
    if (width != null) e.width = width;
    if (height != null) e.height = height;
    return e;
  }

  /// The height of this canvas element in CSS pixels.

  int? get height native;

  set height(int? value) native;

  /// The width of this canvas element in CSS pixels.

  int? get width native;

  set width(int? value) native;

  MediaStream captureStream([num? frameRate]) native;

  @Creates('CanvasRenderingContext2D|RenderingContext|RenderingContext2')
  @Returns('CanvasRenderingContext2D|RenderingContext|RenderingContext2|Null')
  Object? getContext(String contextId, [Map? attributes]) {
    if (attributes != null) {
      var attributes_1 = convertDartToNative_Dictionary(attributes);
      return _getContext_1(contextId, attributes_1);
    }
    return _getContext_2(contextId);
  }

  @JSName('getContext')
  @Creates('CanvasRenderingContext2D|RenderingContext|RenderingContext2')
  @Returns('CanvasRenderingContext2D|RenderingContext|RenderingContext2|Null')
  Object? _getContext_1(contextId, attributes) native;
  @JSName('getContext')
  @Creates('CanvasRenderingContext2D|RenderingContext|RenderingContext2')
  @Returns('CanvasRenderingContext2D|RenderingContext|RenderingContext2|Null')
  Object? _getContext_2(contextId) native;

  @JSName('toDataURL')
  String _toDataUrl(String? type, [arguments_OR_quality]) native;

  OffscreenCanvas transferControlToOffscreen() native;

  /// Stream of `webglcontextlost` events handled by this [CanvasElement].
  ElementStream<gl.ContextEvent> get onWebGlContextLost =>
      webGlContextLostEvent.forElement(this);

  /// Stream of `webglcontextrestored` events handled by this [CanvasElement].
  ElementStream<gl.ContextEvent> get onWebGlContextRestored =>
      webGlContextRestoredEvent.forElement(this);

  /** An API for drawing on this canvas. */
  CanvasRenderingContext2D get context2D =>
      JS('Null|CanvasRenderingContext2D', '#.getContext(#)', this, '2d');

  /**
   * Returns a new Web GL context for this canvas.
   *
   * ## Other resources
   *
   * * [WebGL fundamentals](http://www.html5rocks.com/en/tutorials/webgl/webgl_fundamentals/)
   *   from HTML5Rocks.
   * * [WebGL homepage](http://get.webgl.org/).
   */
  @SupportedBrowser(SupportedBrowser.CHROME)
  @SupportedBrowser(SupportedBrowser.FIREFOX)
  gl.RenderingContext? getContext3d({
    alpha = true,
    depth = true,
    stencil = false,
    antialias = true,
    premultipliedAlpha = true,
    preserveDrawingBuffer = false,
  }) {
    var options = {
      'alpha': alpha,
      'depth': depth,
      'stencil': stencil,
      'antialias': antialias,
      'premultipliedAlpha': premultipliedAlpha,
      'preserveDrawingBuffer': preserveDrawingBuffer,
    };
    var context = getContext('webgl', options);
    if (context == null) {
      context = getContext('experimental-webgl', options);
    }
    return context as gl.RenderingContext?;
  }

  /**
   * Returns a data URI containing a representation of the image in the
   * format specified by type (defaults to 'image/png').
   *
   * Data Uri format is as follow
   * `data:[<MIME-type>][;charset=<encoding>][;base64],<data>`
   *
   * Optional parameter [quality] in the range of 0.0 and 1.0 can be used when
   * requesting [type] 'image/jpeg' or 'image/webp'. If [quality] is not passed
   * the default value is used. Note: the default value varies by browser.
   *
   * If the height or width of this canvas element is 0, then 'data:' is
   * returned, representing no data.
   *
   * If the type requested is not 'image/png', and the returned value is
   * 'data:image/png', then the requested type is not supported.
   *
   * Example usage:
   *
   *     CanvasElement canvas = new CanvasElement();
   *     var ctx = canvas.context2D
   *     ..fillStyle = "rgb(200,0,0)"
   *     ..fillRect(10, 10, 55, 50);
   *     var dataUrl = canvas.toDataUrl("image/jpeg", 0.95);
   *     // The Data Uri would look similar to
   *     // 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA
   *     // AAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO
   *     // 9TXL0Y4OHwAAAABJRU5ErkJggg=='
   *     //Create a new image element from the data URI.
   *     var img = new ImageElement();
   *     img.src = dataUrl;
   *     document.body.children.add(img);
   *
   * See also:
   *
   * * [Data URI Scheme](http://en.wikipedia.org/wiki/Data_URI_scheme) from Wikipedia.
   *
   * * [HTMLCanvasElement](https://developer.mozilla.org/en-US/docs/DOM/HTMLCanvasElement) from MDN.
   *
   * * [toDataUrl](http://dev.w3.org/html5/spec/the-canvas-element.html#dom-canvas-todataurl) from W3C.
   */
  String toDataUrl([String type = 'image/png', num? quality]) =>
      _toDataUrl(type, quality);

  @JSName('toBlob')
  void _toBlob(BlobCallback callback, [String? type, Object? arguments]) native;

  Future<Blob> toBlob([String? type, Object? arguments]) {
    var completer = new Completer<Blob>();
    _toBlob(
      (value) {
        completer.complete(value);
      },
      type,
      arguments,
    );
    return completer.future;
  }
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * An opaque canvas object representing a gradient.
 *
 * Created by calling the methods
 * [CanvasRenderingContext2D.createLinearGradient] or
 * [CanvasRenderingContext2D.createRadialGradient] on a
 * [CanvasRenderingContext2D] object.
 *
 * Example usage:
 *
 *     var canvas = new CanvasElement(width: 600, height: 600);
 *     var ctx = canvas.context2D;
 *     ctx.clearRect(0, 0, 600, 600);
 *     ctx.save();
 *     // Create radial gradient.
 *     CanvasGradient gradient = ctx.createRadialGradient(0, 0, 0, 0, 0, 600);
 *     gradient.addColorStop(0, '#000');
 *     gradient.addColorStop(1, 'rgb(255, 255, 255)');
 *     // Assign gradients to fill.
 *     ctx.fillStyle = gradient;
 *     // Draw a rectangle with a gradient fill.
 *     ctx.fillRect(0, 0, 600, 600);
 *     ctx.save();
 *     document.body.children.add(canvas);
 *
 * See also:
 *
 * * [CanvasGradient](https://developer.mozilla.org/en-US/docs/DOM/CanvasGradient) from MDN.
 * * [CanvasGradient](https://html.spec.whatwg.org/multipage/scripting.html#canvasgradient)
 *   from WHATWG.
 * * [CanvasGradient](http://www.w3.org/TR/2010/WD-2dcontext-20100304/#canvasgradient) from W3C.
 */
@Native("CanvasGradient")
class CanvasGradient extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory CanvasGradient._() {
    throw new UnsupportedError("Not supported");
  }

  /**
   * Adds a color stop to this gradient at the offset.
   *
   * The [offset] can range between 0.0 and 1.0.
   *
   * See also:
   *
   * * [Multiple Color Stops](https://developer.mozilla.org/en-US/docs/CSS/linear-gradient#Gradient_with_multiple_color_stops) from MDN.
   */
  void addColorStop(num offset, String color) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * An opaque object representing a pattern of image, canvas, or video.
 *
 * Created by calling [CanvasRenderingContext2D.createPattern] on a
 * [CanvasRenderingContext2D] object.
 *
 * Example usage:
 *
 *     var canvas = new CanvasElement(width: 600, height: 600);
 *     var ctx = canvas.context2D;
 *     var img = new ImageElement();
 *     // Image src needs to be loaded before pattern is applied.
 *     img.onLoad.listen((event) {
 *       // When the image is loaded, create a pattern
 *       // from the ImageElement.
 *       CanvasPattern pattern = ctx.createPattern(img, 'repeat');
 *       ctx.rect(0, 0, canvas.width, canvas.height);
 *       ctx.fillStyle = pattern;
 *       ctx.fill();
 *     });
 *     img.src = "images/foo.jpg";
 *     document.body.children.add(canvas);
 *
 * See also:
 * * [CanvasPattern](https://developer.mozilla.org/en-US/docs/DOM/CanvasPattern) from MDN.
 * * [CanvasPattern](https://html.spec.whatwg.org/multipage/scripting.html#canvaspattern)
 *   from WHATWG.
 * * [CanvasPattern](http://www.w3.org/TR/2010/WD-2dcontext-20100304/#canvaspattern) from W3C.
 */
@Native("CanvasPattern")
class CanvasPattern extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory CanvasPattern._() {
    throw new UnsupportedError("Not supported");
  }

  void setTransform(Matrix transform) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

abstract class CanvasRenderingContext {
  CanvasElement get canvas;
}

@Native("CanvasRenderingContext2D")
class CanvasRenderingContext2D extends JavaScriptObject
    implements CanvasRenderingContext {
  // To suppress missing implicit constructor warnings.
  factory CanvasRenderingContext2D._() {
    throw new UnsupportedError("Not supported");
  }

  CanvasElement get canvas native;

  Matrix? get currentTransform native;

  set currentTransform(Matrix? value) native;

  String? get direction native;

  set direction(String? value) native;

  @Creates('String|CanvasGradient|CanvasPattern')
  @Returns('String|CanvasGradient|CanvasPattern')
  Object? get fillStyle native;

  set fillStyle(Object? value) native;

  String? get filter native;

  set filter(String? value) native;

  String get font native;

  set font(String value) native;

  num get globalAlpha native;

  set globalAlpha(num value) native;

  String get globalCompositeOperation native;

  set globalCompositeOperation(String value) native;

  /**
   * Whether images and patterns on this canvas will be smoothed when this
   * canvas is scaled.
   *
   * ## Other resources
   *
   * * [Image
   *   smoothing](https://html.spec.whatwg.org/multipage/scripting.html#image-smoothing)
   *   from WHATWG.
   */

  bool? get imageSmoothingEnabled native;

  set imageSmoothingEnabled(bool? value) native;

  String? get imageSmoothingQuality native;

  set imageSmoothingQuality(String? value) native;

  String get lineCap native;

  set lineCap(String value) native;

  String get lineJoin native;

  set lineJoin(String value) native;

  num get lineWidth native;

  set lineWidth(num value) native;

  num get miterLimit native;

  set miterLimit(num value) native;

  num get shadowBlur native;

  set shadowBlur(num value) native;

  String get shadowColor native;

  set shadowColor(String value) native;

  num get shadowOffsetX native;

  set shadowOffsetX(num value) native;

  num get shadowOffsetY native;

  set shadowOffsetY(num value) native;

  @Creates('String|CanvasGradient|CanvasPattern')
  @Returns('String|CanvasGradient|CanvasPattern')
  Object? get strokeStyle native;

  set strokeStyle(Object? value) native;

  String get textAlign native;

  set textAlign(String value) native;

  String get textBaseline native;

  set textBaseline(String value) native;

  void addHitRegion([Map? options]) {
    if (options != null) {
      var options_1 = convertDartToNative_Dictionary(options);
      _addHitRegion_1(options_1);
      return;
    }
    _addHitRegion_2();
    return;
  }

  @JSName('addHitRegion')
  void _addHitRegion_1(options) native;
  @JSName('addHitRegion')
  void _addHitRegion_2() native;

  void beginPath() native;

  void clearHitRegions() native;

  void clearRect(num x, num y, num width, num height) native;

  void clip([path_OR_winding, String? winding]) native;

  @Creates('ImageData|=Object')
  ImageData createImageData(
    data_OR_imagedata_OR_sw, [
    int? sh_OR_sw,
    imageDataColorSettings_OR_sh,
    Map? imageDataColorSettings,
  ]) {
    if ((data_OR_imagedata_OR_sw is ImageData) &&
        sh_OR_sw == null &&
        imageDataColorSettings_OR_sh == null &&
        imageDataColorSettings == null) {
      var imagedata_1 = convertDartToNative_ImageData(data_OR_imagedata_OR_sw);
      return convertNativeToDart_ImageData(_createImageData_1(imagedata_1));
    }
    if (sh_OR_sw != null &&
        (data_OR_imagedata_OR_sw is int) &&
        imageDataColorSettings_OR_sh == null &&
        imageDataColorSettings == null) {
      return convertNativeToDart_ImageData(
        _createImageData_2(data_OR_imagedata_OR_sw, sh_OR_sw),
      );
    }
    if ((imageDataColorSettings_OR_sh is Map) &&
        sh_OR_sw != null &&
        (data_OR_imagedata_OR_sw is int) &&
        imageDataColorSettings == null) {
      var imageDataColorSettings_1 = convertDartToNative_Dictionary(
        imageDataColorSettings_OR_sh,
      );
      return convertNativeToDart_ImageData(
        _createImageData_3(
          data_OR_imagedata_OR_sw,
          sh_OR_sw,
          imageDataColorSettings_1,
        ),
      );
    }
    if ((imageDataColorSettings_OR_sh is int) &&
        sh_OR_sw != null &&
        data_OR_imagedata_OR_sw != null &&
        imageDataColorSettings == null) {
      return convertNativeToDart_ImageData(
        _createImageData_4(
          data_OR_imagedata_OR_sw,
          sh_OR_sw,
          imageDataColorSettings_OR_sh,
        ),
      );
    }
    if (imageDataColorSettings != null &&
        (imageDataColorSettings_OR_sh is int) &&
        sh_OR_sw != null &&
        data_OR_imagedata_OR_sw != null) {
      var imageDataColorSettings_1 = convertDartToNative_Dictionary(
        imageDataColorSettings,
      );
      return convertNativeToDart_ImageData(
        _createImageData_5(
          data_OR_imagedata_OR_sw,
          sh_OR_sw,
          imageDataColorSettings_OR_sh,
          imageDataColorSettings_1,
        ),
      );
    }
    throw new ArgumentError("Incorrect number or type of arguments");
  }

  @JSName('createImageData')
  @Creates('ImageData|=Object')
  _createImageData_1(imagedata) native;
  @JSName('createImageData')
  @Creates('ImageData|=Object')
  _createImageData_2(int sw, sh) native;
  @JSName('createImageData')
  @Creates('ImageData|=Object')
  _createImageData_3(int sw, sh, imageDataColorSettings) native;
  @JSName('createImageData')
  @Creates('ImageData|=Object')
  _createImageData_4(data, sw, int? sh) native;
  @JSName('createImageData')
  @Creates('ImageData|=Object')
  _createImageData_5(data, sw, int? sh, imageDataColorSettings) native;

  CanvasGradient createLinearGradient(num x0, num y0, num x1, num y1) native;

  CanvasPattern? createPattern(Object image, String repetitionType) native;

  CanvasGradient createRadialGradient(
    num x0,
    num y0,
    num r0,
    num x1,
    num y1,
    num r1,
  ) native;

  void drawFocusIfNeeded(element_OR_path, [Element? element]) native;

  void fill([path_OR_winding, String? winding]) native;

  void fillRect(num x, num y, num width, num height) native;

  Map getContextAttributes() {
    return convertNativeToDart_Dictionary(_getContextAttributes_1())!;
  }

  @JSName('getContextAttributes')
  _getContextAttributes_1() native;

  @Creates('ImageData|=Object')
  ImageData getImageData(int sx, int sy, int sw, int sh) {
    return convertNativeToDart_ImageData(_getImageData_1(sx, sy, sw, sh));
  }

  @JSName('getImageData')
  @Creates('ImageData|=Object')
  _getImageData_1(sx, sy, sw, sh) native;

  @JSName('getLineDash')
  List<num> _getLineDash() native;

  bool isContextLost() native;

  bool isPointInPath(
    path_OR_x,
    num x_OR_y, [
    winding_OR_y,
    String? winding,
  ]) native;

  bool isPointInStroke(path_OR_x, num x_OR_y, [num? y]) native;

  TextMetrics measureText(String text) native;

  void putImageData(
    ImageData imagedata,
    int dx,
    int dy, [
    int? dirtyX,
    int? dirtyY,
    int? dirtyWidth,
    int? dirtyHeight,
  ]) {
    if (dirtyX == null &&
        dirtyY == null &&
        dirtyWidth == null &&
        dirtyHeight == null) {
      var imagedata_1 = convertDartToNative_ImageData(imagedata);
      _putImageData_1(imagedata_1, dx, dy);
      return;
    }
    if (dirtyHeight != null &&
        dirtyWidth != null &&
        dirtyY != null &&
        dirtyX != null) {
      var imagedata_1 = convertDartToNative_ImageData(imagedata);
      _putImageData_2(
        imagedata_1,
        dx,
        dy,
        dirtyX,
        dirtyY,
        dirtyWidth,
        dirtyHeight,
      );
      return;
    }
    throw new ArgumentError("Incorrect number or type of arguments");
  }

  @JSName('putImageData')
  void _putImageData_1(imagedata, dx, dy) native;
  @JSName('putImageData')
  void _putImageData_2(
    imagedata,
    dx,
    dy,
    dirtyX,
    dirtyY,
    dirtyWidth,
    dirtyHeight,
  ) native;

  void removeHitRegion(String id) native;

  void resetTransform() native;

  void restore() native;

  void rotate(num angle) native;

  void save() native;

  void scale(num x, num y) native;

  void scrollPathIntoView([Path2D? path]) native;

  void setTransform(num a, num b, num c, num d, num e, num f) native;

  void stroke([Path2D? path]) native;

  void strokeRect(num x, num y, num width, num height) native;

  void strokeText(String text, num x, num y, [num? maxWidth]) native;

  void transform(num a, num b, num c, num d, num e, num f) native;

  void translate(num x, num y) native;

  // From CanvasPath

  @JSName('arc')
  void _arc(
    num x,
    num y,
    num radius,
    num startAngle,
    num endAngle,
    bool? anticlockwise,
  ) native;

  void arcTo(num x1, num y1, num x2, num y2, num radius) native;

  void bezierCurveTo(
    num cp1x,
    num cp1y,
    num cp2x,
    num cp2y,
    num x,
    num y,
  ) native;

  void closePath() native;

  void ellipse(
    num x,
    num y,
    num radiusX,
    num radiusY,
    num rotation,
    num startAngle,
    num endAngle,
    bool? anticlockwise,
  ) native;

  void lineTo(num x, num y) native;

  void moveTo(num x, num y) native;

  void quadraticCurveTo(num cpx, num cpy, num x, num y) native;

  void rect(num x, num y, num width, num height) native;

  ImageData createImageDataFromImageData(ImageData imagedata) =>
      JS('ImageData', '#.createImageData(#)', this, imagedata);

  /**
   * Sets the color used inside shapes.
   * [r], [g], [b] are 0-255, [a] is 0-1.
   */
  void setFillColorRgb(int r, int g, int b, [num a = 1]) {
    this.fillStyle = 'rgba($r, $g, $b, $a)';
  }

  /**
   * Sets the color used inside shapes.
   * [h] is in degrees, 0-360.
   * [s], [l] are in percent, 0-100.
   * [a] is 0-1.
   */
  void setFillColorHsl(int h, num s, num l, [num a = 1]) {
    this.fillStyle = 'hsla($h, $s%, $l%, $a)';
  }

  /**
   * Sets the color used for stroking shapes.
   * [r], [g], [b] are 0-255, [a] is 0-1.
   */
  void setStrokeColorRgb(int r, int g, int b, [num a = 1]) {
    this.strokeStyle = 'rgba($r, $g, $b, $a)';
  }

  /**
   * Sets the color used for stroking shapes.
   * [h] is in degrees, 0-360.
   * [s], [l] are in percent, 0-100.
   * [a] is 0-1.
   */
  void setStrokeColorHsl(int h, num s, num l, [num a = 1]) {
    this.strokeStyle = 'hsla($h, $s%, $l%, $a)';
  }

  void arc(
    num x,
    num y,
    num radius,
    num startAngle,
    num endAngle, [
    bool anticlockwise = false,
  ]) {
    // TODO(terry): This should not be needed: dartbug.com/20939.
    JS(
      'void',
      '#.arc(#, #, #, #, #, #)',
      this,
      x,
      y,
      radius,
      startAngle,
      endAngle,
      anticlockwise,
    );
  }

  CanvasPattern createPatternFromImage(
    ImageElement image,
    String repetitionType,
  ) =>
      JS('CanvasPattern', '#.createPattern(#, #)', this, image, repetitionType);

  /**
   * Draws an image from a CanvasImageSource to an area of this canvas.
   *
   * The image will be drawn to an area of this canvas defined by
   * [destRect]. [sourceRect] defines the region of the source image that is
   * drawn.
   * If [sourceRect] is not provided, then
   * the entire rectangular image from [source] will be drawn to this context.
   *
   * If the image is larger than canvas
   * will allow, the image will be clipped to fit the available space.
   *
   *     CanvasElement canvas = new CanvasElement(width: 600, height: 600);
   *     CanvasRenderingContext2D ctx = canvas.context2D;
   *     ImageElement img = document.query('img');
   *     img.width = 100;
   *     img.height = 100;
   *
   *     // Scale the image to 20x20.
   *     ctx.drawImageToRect(img, new Rectangle(50, 50, 20, 20));
   *
   *     VideoElement video = document.query('video');
   *     video.width = 100;
   *     video.height = 100;
   *     // Take the middle 20x20 pixels from the video and stretch them.
   *     ctx.drawImageToRect(video, new Rectangle(50, 50, 100, 100),
   *         sourceRect: new Rectangle(40, 40, 20, 20));
   *
   *     // Draw the top 100x20 pixels from the otherCanvas.
   *     CanvasElement otherCanvas = document.query('canvas');
   *     ctx.drawImageToRect(otherCanvas, new Rectangle(0, 0, 100, 20),
   *         sourceRect: new Rectangle(0, 0, 100, 20));
   *
   * See also:
   *
   *   * [CanvasImageSource] for more information on what data is retrieved
   * from [source].
   *   * [drawImage](http://www.whatwg.org/specs/web-apps/current-work/multipage/the-canvas-element.html#dom-context-2d-drawimage)
   * from the WHATWG.
   */
  void drawImageToRect(
    CanvasImageSource source,
    Rectangle destRect, {
    Rectangle? sourceRect,
  }) {
    if (sourceRect == null) {
      drawImageScaled(
        source,
        destRect.left,
        destRect.top,
        destRect.width,
        destRect.height,
      );
    } else {
      drawImageScaledFromSource(
        source,
        sourceRect.left,
        sourceRect.top,
        sourceRect.width,
        sourceRect.height,
        destRect.left,
        destRect.top,
        destRect.width,
        destRect.height,
      );
    }
  }

  /**
   * Draws an image from a CanvasImageSource to this canvas.
   *
   * The entire image from [source] will be drawn to this context with its top
   * left corner at the point ([destX], [destY]). If the image is
   * larger than canvas will allow, the image will be clipped to fit the
   * available space.
   *
   *     CanvasElement canvas = new CanvasElement(width: 600, height: 600);
   *     CanvasRenderingContext2D ctx = canvas.context2D;
   *     ImageElement img = document.query('img');
   *
   *     ctx.drawImage(img, 100, 100);
   *
   *     VideoElement video = document.query('video');
   *     ctx.drawImage(video, 0, 0);
   *
   *     CanvasElement otherCanvas = document.query('canvas');
   *     otherCanvas.width = 100;
   *     otherCanvas.height = 100;
   *     ctx.drawImage(otherCanvas, 590, 590); // will get clipped
   *
   * See also:
   *
   *   * [CanvasImageSource] for more information on what data is retrieved
   * from [source].
   *   * [drawImage](http://www.whatwg.org/specs/web-apps/current-work/multipage/the-canvas-element.html#dom-context-2d-drawimage)
   * from the WHATWG.
   */
  @JSName('drawImage')
  void drawImage(CanvasImageSource source, num destX, num destY) native;

  /**
   * Draws an image from a CanvasImageSource to an area of this canvas.
   *
   * The image will be drawn to this context with its top left corner at the
   * point ([destX], [destY]) and will be scaled to be [destWidth] wide and
   * [destHeight] tall.
   *
   * If the image is larger than canvas
   * will allow, the image will be clipped to fit the available space.
   *
   *     CanvasElement canvas = new CanvasElement(width: 600, height: 600);
   *     CanvasRenderingContext2D ctx = canvas.context2D;
   *     ImageElement img = document.query('img');
   *     img.width = 100;
   *     img.height = 100;
   *
   *     // Scale the image to 300x50 at the point (20, 20)
   *     ctx.drawImageScaled(img, 20, 20, 300, 50);
   *
   * See also:
   *
   *   * [CanvasImageSource] for more information on what data is retrieved
   * from [source].
   *   * [drawImage](http://www.whatwg.org/specs/web-apps/current-work/multipage/the-canvas-element.html#dom-context-2d-drawimage)
   * from the WHATWG.
   */
  @JSName('drawImage')
  void drawImageScaled(
    CanvasImageSource source,
    num destX,
    num destY,
    num destWidth,
    num destHeight,
  ) native;

  /**
   * Draws an image from a CanvasImageSource to an area of this canvas.
   *
   * The image is a region of [source] that is [sourceWidth] wide and
   * [sourceHeight] tall with top left corner at ([sourceX], [sourceY]).
   * The image will be drawn to this context with its top left corner at the
   * point ([destX], [destY]) and will be scaled to be [destWidth] wide and
   * [destHeight] tall.
   *
   * If the image is larger than canvas
   * will allow, the image will be clipped to fit the available space.
   *
   *     VideoElement video = document.query('video');
   *     video.width = 100;
   *     video.height = 100;
   *     // Take the middle 20x20 pixels from the video and stretch them.
   *     ctx.drawImageScaledFromSource(video, 40, 40, 20, 20, 50, 50, 100, 100);
   *
   *     // Draw the top 100x20 pixels from the otherCanvas to this one.
   *     CanvasElement otherCanvas = document.query('canvas');
   *     ctx.drawImageScaledFromSource(otherCanvas, 0, 0, 100, 20, 0, 0, 100, 20);
   *
   * See also:
   *
   *   * [CanvasImageSource] for more information on what data is retrieved
   * from [source].
   *   * [drawImage](http://www.whatwg.org/specs/web-apps/current-work/multipage/the-canvas-element.html#dom-context-2d-drawimage)
   * from the WHATWG.
   */
  @JSName('drawImage')
  void drawImageScaledFromSource(
    CanvasImageSource source,
    num sourceX,
    num sourceY,
    num sourceWidth,
    num sourceHeight,
    num destX,
    num destY,
    num destWidth,
    num destHeight,
  ) native;

  @SupportedBrowser(SupportedBrowser.CHROME)
  @SupportedBrowser(SupportedBrowser.SAFARI)
  @SupportedBrowser(SupportedBrowser.IE, '11')
  @Unstable()
  // TODO(14316): Firefox has this functionality with mozDashOffset, but it
  // needs to be polyfilled.
  num get lineDashOffset =>
      JS('num', '#.lineDashOffset || #.webkitLineDashOffset', this, this);

  @SupportedBrowser(SupportedBrowser.CHROME)
  @SupportedBrowser(SupportedBrowser.SAFARI)
  @SupportedBrowser(SupportedBrowser.IE, '11')
  @Unstable()
  // TODO(14316): Firefox has this functionality with mozDashOffset, but it
  // needs to be polyfilled.
  set lineDashOffset(num value) {
    JS(
      'void',
      'typeof #.lineDashOffset != "undefined" ? #.lineDashOffset = # : '
          '#.webkitLineDashOffset = #',
      this,
      this,
      value,
      this,
      value,
    );
  }

  @SupportedBrowser(SupportedBrowser.CHROME)
  @SupportedBrowser(SupportedBrowser.SAFARI)
  @SupportedBrowser(SupportedBrowser.IE, '11')
  @Unstable()
  List<num> getLineDash() {
    // TODO(14316): Firefox has this functionality with mozDash, but it's a bit
    // different.
    if (JS('bool', '!!#.getLineDash', this)) {
      return JS('List<num>', '#.getLineDash()', this);
    } else if (JS('bool', '!!#.webkitLineDash', this)) {
      return JS('List<num>', '#.webkitLineDash', this);
    }
    return [];
  }

  @SupportedBrowser(SupportedBrowser.CHROME)
  @SupportedBrowser(SupportedBrowser.SAFARI)
  @SupportedBrowser(SupportedBrowser.IE, '11')
  @Unstable()
  void setLineDash(List<num> dash) {
    // TODO(14316): Firefox has this functionality with mozDash, but it's a bit
    // different.
    if (JS('bool', '!!#.setLineDash', this)) {
      JS('void', '#.setLineDash(#)', this, dash);
    } else if (JS('bool', '!!#.webkitLineDash', this)) {
      JS('void', '#.webkitLineDash = #', this, dash);
    }
  }

  /**
   * Draws text to the canvas.
   *
   * The text is drawn starting at coordinates ([x], [y]).
   * If [maxWidth] is provided and the [text] is computed to be wider than
   * [maxWidth], then the drawn text is scaled down horizontally to fit.
   *
   * The text uses the current [CanvasRenderingContext2D.font] property for font
   * options, such as typeface and size, and the current
   * [CanvasRenderingContext2D.fillStyle] for style options such as color.
   * The current [CanvasRenderingContext2D.textAlign] and
   * [CanvasRenderingContext2D.textBaseline] properties are also applied to the
   * drawn text.
   */
  void fillText(String text, num x, num y, [num? maxWidth]) {
    if (maxWidth != null) {
      JS('void', '#.fillText(#, #, #, #)', this, text, x, y, maxWidth);
    } else {
      JS('void', '#.fillText(#, #, #)', this, text, x, y);
    }
  }

  /** Deprecated always returns 1.0 */
  @deprecated
  double get backingStorePixelRatio => 1.0;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("CharacterData")
class CharacterData extends Node
    implements ChildNode, NonDocumentTypeChildNode {
  // To suppress missing implicit constructor warnings.
  factory CharacterData._() {
    throw new UnsupportedError("Not supported");
  }

  String? get data native;

  set data(String? value) native;

  int? get length native;

  void appendData(String data) native;

  void deleteData(int offset, int count) native;

  void insertData(int offset, String data) native;

  void replaceData(int offset, int count, String data) native;

  String substringData(int offset, int count) native;

  // From ChildNode

  void after(Object nodes) native;

  void before(Object nodes) native;

  // From NonDocumentTypeChildNode

  Element? get nextElementSibling native;

  Element? get previousElementSibling native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

abstract class ChildNode extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory ChildNode._() {
    throw new UnsupportedError("Not supported");
  }

  void after(Object nodes);

  void before(Object nodes);

  void remove();
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("Client")
class Client extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory Client._() {
    throw new UnsupportedError("Not supported");
  }

  String? get frameType native;

  String? get id native;

  String? get type native;

  String? get url native;

  void postMessage(Object message, [List<Object>? transfer]) native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("Clients")
class Clients extends JavaScriptObject {
  // To suppress missing implicit constructor warnings.
  factory Clients._() {
    throw new UnsupportedError("Not supported");
  }

  Future claim() => promiseToFuture(JS("", "#.claim()", this));

  Future get(String id) => promiseToFuture(JS("", "#.get(#)", this, id));

  Future<List<dynamic>> matchAll([Map? options]) {
    var options_dict = null;
    if (options != null) {
      options_dict = convertDartToNative_Dictionary(options);
    }
    return promiseToFuture<List<dynamic>>(
      JS("", "#.matchAll(#)", this, options_dict),
    );
  }

  Future<WindowClient> openWindow(String url) => promiseToFuture<WindowClient>(
    JS("creates:WindowClient;", "#.openWindow(#)", this, url),
  );
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("ClipboardEvent")
class ClipboardEvent extends Event {
  // To suppress missing implicit constructor warnings.
  factory ClipboardEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory ClipboardEvent(String type, [Map? eventInitDict]) {
    if (eventInitDict != null) {
      var eventInitDict_1 = convertDartToNative_Dictionary(eventInitDict);
      return ClipboardEvent._create_1(type, eventInitDict_1);
    }
    return ClipboardEvent._create_2(type);
  }
  static ClipboardEvent _create_1(type, eventInitDict) =>
      JS('ClipboardEvent', 'new ClipboardEvent(#,#)', type, eventInitDict);
  static ClipboardEvent _create_2(type) =>
      JS('ClipboardEvent', 'new ClipboardEvent(#)', type);

  DataTransfer? get clipboardData native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("CloseEvent")
class CloseEvent extends Event {
  // To suppress missing implicit constructor warnings.
  factory CloseEvent._() {
    throw new UnsupportedError("Not supported");
  }

  factory CloseEvent(String type, [Map? eventInitDict]) {
    if (eventInitDict != null) {
      var eventInitDict_1 = convertDartToNative_Dictionary(eventInitDict);
      return CloseEvent._create_1(type, eventInitDict_1);
    }
    return CloseEvent._create_2(type);
  }
  static CloseEvent _create_1(type, eventInitDict) =>
      JS('CloseEvent', 'new CloseEvent(#,#)', type, eventInitDict);
  static CloseEvent _create_2(type) =>
      JS('CloseEvent', 'new CloseEvent(#)', type);

  int? get code native;

  String? get reason native;

  bool? get wasClean native;
}
// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Native("Comment")
class Comment extends CharacterData {
  factory Comment([String? data]) {
    return JS(
      'returns:Comment;depends:none;effects:none;new:true',
      '#.createComment(#)',
  
