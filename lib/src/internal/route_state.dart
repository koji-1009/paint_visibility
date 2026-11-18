import 'package:flutter/widgets.dart';

import 'package:paint_visibility/src/route_coverage.dart';

/// The state of the route of a widget according to a [RouteCoverage], read
/// by the widget and passed to its render object.
///
/// `hides` is whether the widget is hidden, with [RouteCoverage.any].
/// `keepsLastValue` is whether the last notified value is kept, with
/// [RouteCoverage.keep]. Ancestors that do not paint the render object,
/// including an [Overlay] that does not paint a covered route, report it
/// through [RenderObject.paintsChild] and are detected from the render tree
/// instead.
typedef RouteState = ({bool hides, bool keepsLastValue});

/// The route neither hides the widget nor keeps its last value.
const RouteState noRouteState = (hides: false, keepsLastValue: false);

/// Reads the state of the route of [context] and registers the dependencies
/// that update the widget of [context] when it changes.
RouteState routeStateOf(BuildContext context, RouteCoverage coverage) {
  return switch (coverage) {
    .page => noRouteState,
    .any => (
      hides: !(ModalRoute.isCurrentOf(context) ?? true),
      keepsLastValue: false,
    ),
    .keep => (
      hides: false,
      keepsLastValue: !TickerMode.valuesOf(context).enabled,
    ),
  };
}
