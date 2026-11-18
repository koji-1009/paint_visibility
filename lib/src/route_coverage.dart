import 'package:flutter/widgets.dart';

/// How a widget is reported while the route that contains it is covered by
/// another route.
enum RouteCoverage {
  /// Hidden while an opaque route covers the route, so that the [Overlay]
  /// of the [Navigator] no longer paints it.
  ///
  /// This is the case from the end of the push transition of an opaque route
  /// (any `PageRoute`, a `fullscreenDialog`, or any other opaque route) until
  /// the start of its pop transition, including iOS back swipes, during
  /// which the covered page is painted again. Dialogs, bottom sheets and
  /// other translucent routes do not hide the route below them, because it
  /// is still painted (occlusion is not taken into account).
  ///
  /// Works across nested [Navigator]s: a route pushed on an outer
  /// [Navigator] hides the widgets inside an inner one.
  ///
  /// The [Overlay] reports the entries it does not paint through
  /// [RenderObject.paintsChild], so this is what the render tree reports.
  page,

  /// Hidden while any route is on top of the route in its [Navigator],
  /// including dialogs and bottom sheets, and while the route itself is
  /// being popped.
  ///
  /// Read from [ModalRoute.isCurrentOf], so only the nearest [Navigator] is
  /// considered.
  any,

  /// The last value is kept while an opaque route covers the route, and the
  /// widget is evaluated again when the route is painted again.
  ///
  /// During a transition the covered page is measured like any other moving
  /// content. Read from [TickerMode.valuesOf], which the [Overlay] disables
  /// for the entries it does not paint. A `TickerMode(enabled: false)` placed
  /// by the app also keeps the last value of the widgets below it.
  keep,
}
