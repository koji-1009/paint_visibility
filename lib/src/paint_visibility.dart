import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:paint_visibility/src/internal/frame_scheduler.dart';
import 'package:paint_visibility/src/internal/paint_geometry.dart';
import 'package:paint_visibility/src/internal/route_state.dart';
import 'package:paint_visibility/src/route_coverage.dart';
import 'package:paint_visibility/src/visibility_info.dart';

const double _defaultFractionStep = 0.1;

/// The difference in logical pixels below which two sizes are the same.
///
/// The floating point error of a global position grows with its magnitude:
/// about 1e-13 at 1e3 and 1e-10 at 1e6, the scroll offset of a long feed.
/// [precisionErrorTolerance] (1e-10) is too small for the latter, while
/// 1e-6 is still far below a physical pixel.
const double _sizeTolerance = 1e-6;

/// The configuration shared by [PaintVisibility] and [SliverPaintVisibility].
abstract class _PaintVisibilityWidget extends SingleChildRenderObjectWidget {
  const _PaintVisibilityWidget({
    super.key,
    required this.onVisibilityChanged,
    required this.routeCoverage,
    required this.fractionStep,
    super.child,
  }) : assert(fractionStep >= 0.01 && fractionStep <= 1);

  /// Called when the visibility changes.
  final VisibilityChangedCallback onVisibilityChanged;

  /// How the child is reported while its route is covered by another route.
  ///
  /// Defaults to [RouteCoverage.page].
  final RouteCoverage routeCoverage;

  /// The step of [VisibilityInfo.visibleFraction] whose multiples are
  /// notified while the child stays visible with the same size.
  ///
  /// A value is notified when the visible fraction moves to another interval
  /// between two multiples of the step, for example from \[0.4, 0.5) to
  /// \[0.5, 0.6) with the default 0.1. The last notified value is therefore
  /// always in the same interval as the current one, so a test against a
  /// multiple of the step, such as `visibleFraction >= 0.5`, gives the same
  /// result for both, even after scrolling stops.
  ///
  /// Between 0.01, the tolerance with which the visible fraction snaps to 0
  /// and 1, and 1. Becoming hidden, becoming fully visible and changes of
  /// size beyond floating point error are always notified.
  final double fractionStep;

  _VisibilityObserver _createObserver();

  @override
  RenderObject createRenderObject(BuildContext context) {
    final observer = _createObserver();
    updateRenderObject(context, observer);
    return observer;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _VisibilityObserver)
      ..onVisibilityChanged = onVisibilityChanged
      ..routeState = routeStateOf(context, routeCoverage)
      ..fractionStep = fractionStep;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<RouteCoverage>('routeCoverage', routeCoverage))
      ..add(DoubleProperty('fractionStep', fractionStep));
  }
}

/// Reports the visibility of [child] once per rendered frame.
///
/// The value is computed in the post-frame phase of each rendered frame,
/// after layout, paint and compositing, and [onVisibilityChanged] is invoked
/// synchronously when it differs from the last notified value. No timer is
/// used, so in a widget test the callback has been invoked by the time
/// `tester.pump()` returns.
///
/// A value is hidden when its [VisibilityInfo.visibleBounds] is empty, and
/// visible otherwise. A value whose [VisibilityInfo.visibleFraction] snaps to
/// 0 but whose bounds are not empty is visible.
///
/// The first value after the render object is created is always notified,
/// even when it is hidden. After that, a hidden value is notified only when
/// the last notified value was visible: while the child stays hidden, changes
/// of its size are not notified. While the child stays visible with the same
/// size, a value is notified only when its visible fraction crosses a
/// multiple of [fractionStep], or when the child becomes fully visible, so a
/// child crossing the edge of the viewport is not notified on every frame.
/// Sizes that differ by floating point error only are treated as the same.
///
/// When the render object is removed from the tree while the last notified
/// value was visible, a hidden value is notified on the next flush. The
/// [State] that owns the callback may already be disposed at that point, so
/// check `mounted` before calling `setState`.
///
/// The child is reported as hidden while an ancestor does not paint it, as
/// reported by [RenderObject.paintsChild] (including a [Visibility] that is
/// not visible and a child of an [IndexedStack] that is not displayed), and
/// while its route is covered according to [routeCoverage]. The overlay
/// child of an [OverlayPortal] is painted by the [Overlay], so it does not
/// follow a [Visibility] placed between the [OverlayPortal] and the
/// [Overlay]. The `replacement` of a hidden [Visibility] is painted, so a
/// child inside it is measured like any other, although [Visibility.of]
/// reports false there.
///
/// Occlusion by other widgets painted on top is not taken into account.
///
/// The [key] is an ordinary widget key and is not used for identification.
class PaintVisibility extends _PaintVisibilityWidget {
  /// Creates a widget that reports the visibility of [child].
  const PaintVisibility({
    super.key,
    required super.onVisibilityChanged,
    super.routeCoverage = RouteCoverage.page,
    super.fractionStep = _defaultFractionStep,
    super.child,
  });

  @override
  _VisibilityObserver _createObserver() => _RenderPaintVisibility();
}

/// Reports the visibility of a sliver once per rendered frame.
///
/// The sliver counterpart of [PaintVisibility], with the same parameters.
/// The bounds of the sliver start at its scroll offset and span its scroll
/// extent along the main axis, as in `SliverVisibilityDetector` of
/// `package:visibility_detector`. A sliver that paints outside of those
/// bounds, such as a pinned header that has been scrolled past, is measured
/// by bounds that end where it paints.
class SliverPaintVisibility extends _PaintVisibilityWidget {
  /// Creates a widget that reports the visibility of [sliver].
  const SliverPaintVisibility({
    super.key,
    required super.onVisibilityChanged,
    super.routeCoverage = RouteCoverage.page,
    super.fractionStep = _defaultFractionStep,
    required Widget sliver,
  }) : super(child: sliver);

  @override
  _VisibilityObserver _createObserver() => _RenderSliverPaintVisibility();
}

/// The notification logic shared by the render objects of [PaintVisibility]
/// and [SliverPaintVisibility].
///
/// The properties are read by the widget and in each flush, so replacing one
/// does not trigger a computation; the new value is used from the next
/// flush.
mixin _VisibilityObserver on ScheduledObserver {
  /// Called when the visibility changes.
  VisibilityChangedCallback onVisibilityChanged = _ignore;

  /// The state of the route of this render object.
  RouteState routeState = noRouteState;

  /// The step of the visible fraction whose multiples are notified while the
  /// render object stays visible with the same size, from 0.01 to 1.
  double fractionStep = _defaultFractionStep;

  VisibilityInfo? _lastNotified;

  VisibilityInfo _computeVisibility();

  static void _ignore(
    VisibilityInfo info,
    Set<VisibilityChangeReason> reasons,
  ) {}

  /// Whether [info] is hidden: its visible bounds are empty.
  ///
  /// [VisibilityInfo.visibleFraction] is not used, because it snaps values
  /// below 0.01 to 0 although part of the widget is still painted. With it,
  /// a widget that leaves the viewport from a sliver below 1% would never
  /// report empty bounds, and its last value would keep stale bounds.
  static bool _isHidden(VisibilityInfo info) => info.visibleBounds.isEmpty;

  @override
  bool get lastNotifiedVisible {
    final last = _lastNotified;
    return last != null && !_isHidden(last);
  }

  @override
  void flushFrame() {
    final last = _lastNotified;
    final VisibilityInfo info;
    if (!attached) {
      if (!lastNotifiedVisible) {
        return;
      }
      info = VisibilityInfo(size: last!.size);
    } else if (routeState.keepsLastValue && last != null) {
      return;
    } else if (routeState.hides) {
      // Hidden to hidden is not notified, so the geometry is not needed.
      if (last != null && _isHidden(last)) {
        return;
      }
      info = VisibilityInfo(size: _computeVisibility().size);
    } else {
      info = _computeVisibility();
    }
    final reasons = last == null
        ? const {VisibilityChangeReason.initial}
        : _reasonsFor(info, last);
    if (reasons.isEmpty) {
      return;
    }
    _lastNotified = info;
    onVisibilityChanged(info, reasons);
  }

  /// Why [info] is notified after [last], or an empty set when it is not
  /// notified.
  ///
  /// Hidden to hidden is not notified, even when the size changes, as in
  /// visibility_detector. Becoming fully visible is always notified, so that
  /// the last notified value of a widget that settles inside the viewport has
  /// its complete bounds.
  Set<VisibilityChangeReason> _reasonsFor(
    VisibilityInfo info,
    VisibilityInfo last,
  ) {
    final hidden = _isHidden(info);
    final wasHidden = _isHidden(last);
    if (hidden && wasHidden) {
      return const {};
    }
    return {
      if (hidden && !wasHidden) VisibilityChangeReason.hidden,
      if (!hidden && wasHidden) VisibilityChangeReason.shown,
      if (!_isSameSize(info.size, last.size)) VisibilityChangeReason.resized,
      if (!hidden &&
          !wasHidden &&
          _stepOf(info.visibleFraction) != _stepOf(last.visibleFraction))
        VisibilityChangeReason.stepCrossed,
      if (!hidden && _isFullyVisible(info) && !_isFullyVisible(last))
        VisibilityChangeReason.fullyVisible,
    };
  }

  static bool _isFullyVisible(VisibilityInfo info) =>
      info.visibleBounds == Offset.zero & info.size;

  /// Whether [a] and [b] are the same size within [_sizeTolerance].
  ///
  /// The size is the bounding box in global coordinates, computed as the
  /// difference of two global positions, so the same widget gets sizes such
  /// as 73.70000000000002 and 73.69999999999999 at different scroll offsets.
  static bool _isSameSize(Size a, Size b) =>
      (a.width - b.width).abs() <= _sizeTolerance &&
      (a.height - b.height).abs() <= _sizeTolerance;

  /// The index of the interval of [fraction]. A fraction within floating
  /// point error of a multiple belongs to the interval above it, so 0.5 is in
  /// \[0.5, 0.6) with a step of 0.1.
  int _stepOf(double fraction) =>
      (fraction / fractionStep + precisionErrorTolerance).floor();
}

/// The render object of [PaintVisibility].
class _RenderPaintVisibility extends RenderProxyBox
    with ScheduledObserver, _VisibilityObserver {
  /// The bounds are the [semanticBounds], mapped to global coordinates with
  /// [RenderObject.applyPaintTransform] and clipped by every ancestor clip
  /// described by [RenderObject.describeApproximatePaintClip]. The box is
  /// hidden when an ancestor does not paint it, as reported by
  /// [RenderObject.paintsChild].
  @override
  VisibilityInfo _computeVisibility() {
    if (!hasSize) {
      return const VisibilityInfo();
    }
    return _fromLocalBounds(this, semanticBounds);
  }
}

/// The render object of [SliverPaintVisibility].
class _RenderSliverPaintVisibility extends RenderProxySliver
    with ScheduledObserver, _VisibilityObserver {
  /// The bounds are derived from the constraints and geometry with the same
  /// formulas as `RenderSliverVisibilityDetector.bounds` of
  /// `package:visibility_detector`, except for slivers that paint outside of
  /// those bounds, such as a pinned header that has been scrolled past, which
  /// are measured by bounds that end where they paint.
  @override
  VisibilityInfo _computeVisibility() {
    if (geometry == null) {
      return const VisibilityInfo();
    }
    return _fromLocalBounds(this, _sliverBounds(this));
  }
}

/// The bounds of [sliver] in its own paint coordinates.
///
/// The bounds start at `-scrollOffset` along the main axis, as the content of
/// a sliver scrolls with it. A sliver that paints outside of those bounds,
/// such as a pinned or floating header that stays at the leading edge after
/// it has been scrolled past, is measured by bounds that end where it paints
/// instead, so its visible fraction is its painted extent over its scroll
/// extent.
Rect _sliverBounds(RenderSliver sliver) {
  final geometry = sliver.geometry!;
  final start = -sliver.constraints.scrollOffset;
  final paintEnd = geometry.paintOrigin + geometry.paintExtent;
  if (geometry.paintExtent > 0 &&
      (geometry.paintOrigin < start - precisionErrorTolerance ||
          paintEnd > start + geometry.scrollExtent + precisionErrorTolerance)) {
    return _boundsFromStart(sliver, paintEnd - geometry.scrollExtent);
  }
  // visibility_detector clamps the bounds of reversed slivers to the
  // trailing edge of the painted area.
  return _boundsFromStart(sliver, start, clampReversed: true);
}

// Bounds that start at [start] along the main axis, measured from the leading
// edge of the painted area in the growth direction.
Rect _boundsFromStart(
  RenderSliver sliver,
  double start, {
  bool clampReversed = false,
}) {
  final constraints = sliver.constraints;
  final geometry = sliver.geometry!;
  final extent = geometry.scrollExtent;
  final crossAxisExtent = constraints.crossAxisExtent;
  // The paint coordinates of reversed slivers run against the growth
  // direction from the trailing edge of the painted area.
  double reversed() {
    final offset = geometry.paintExtent - start - extent;
    return clampReversed ? math.min(offset, 0) : offset;
  }

  return switch (applyGrowthDirectionToAxisDirection(
    constraints.axisDirection,
    constraints.growthDirection,
  )) {
    AxisDirection.down => Offset(0, start) & Size(crossAxisExtent, extent),
    AxisDirection.right => Offset(start, 0) & Size(extent, crossAxisExtent),
    AxisDirection.up => Offset(0, reversed()) & Size(crossAxisExtent, extent),
    AxisDirection.left => Offset(reversed(), 0) & Size(extent, crossAxisExtent),
  };
}

VisibilityInfo _fromLocalBounds(RenderObject target, Rect localBounds) {
  final geometry = resolvePaintGeometry(target);
  if (geometry == null) {
    return VisibilityInfo(size: localBounds.size);
  }
  final bounds = MatrixUtils.transformRect(geometry.transform, localBounds);
  final clip = geometry.clip;
  return VisibilityInfo(
    size: bounds.size,
    visibleBounds: bounds.overlaps(clip)
        ? bounds.intersect(clip).shift(-bounds.topLeft)
        : Rect.zero,
  );
}
