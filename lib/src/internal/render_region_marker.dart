import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/rendering.dart';

import 'package:paint_visibility/src/internal/frame_scheduler.dart';
import 'package:paint_visibility/src/internal/paint_geometry.dart';
import 'package:paint_visibility/src/internal/route_state.dart';
import 'package:paint_visibility/src/region_marker.dart';

/// The notification logic shared by the render objects of [RegionMarker]
/// and [SliverRegionMarker].
///
/// Ancestors can stop painting the marker (Offstage, Opacity, a
/// FadeTransition, a kept-alive child of a lazy list) or move and clip it
/// without laying it out again or updating its widget, so it is evaluated on
/// every rendered frame. The properties are read in each flush, so replacing
/// one does not trigger a computation; the new value is used from the next
/// flush.
mixin RegionObserver on ScheduledObserver {
  /// Called with whether the marker is inside its region, when it enters or
  /// leaves the region.
  ValueChanged<bool> get onRegionChanged;
  set onRegionChanged(ValueChanged<bool> value);

  /// The state of the route of this marker.
  RouteState routeState = noRouteState;

  /// Whether the marker is currently inside its region. False while
  /// detached.
  bool get isInRegion => attached && !routeState.hides && _isInOwnRegion;

  /// Whether the position of the attached marker is inside its region,
  /// ignoring [routeState].
  bool get _isInOwnRegion;

  bool? _lastNotified;

  @override
  bool get lastNotifiedVisible => _lastNotified == true;

  @override
  void flushFrame() {
    // A marker removed before any notification, or after notifying false,
    // has nothing to report.
    if (!attached && !lastNotifiedVisible) {
      return;
    }
    if (attached && routeState.keepsLastValue && _lastNotified != null) {
      return;
    }
    final value = isInRegion;
    if (value == _lastNotified) {
      return;
    }
    _lastNotified = value;
    onRegionChanged(value);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      FlagProperty('isInRegion', value: isInRegion, ifTrue: 'in region'),
    );
  }
}

/// The render object of [SliverRegionMarker].
class RenderSliverRegionMarker extends RenderSliver
    with ScheduledObserver, RegionObserver {
  /// Creates a [RenderSliverRegionMarker].
  RenderSliverRegionMarker({
    required this.onRegionChanged,
    this._region = SliverRegion.cacheExtent,
  });

  @override
  ValueChanged<bool> onRegionChanged;

  /// The region the marker position is tested against.
  SliverRegion get region => _region;
  SliverRegion _region;
  set region(SliverRegion value) {
    if (_region == value) {
      return;
    }
    _region = value;
    markNeedsLayout();
  }

  // The result of the last layout. It is kept while detached: a kept-alive
  // marker is detached and attached again without a new layout when its
  // constraints have not changed.
  bool _laidOutInRegion = false;

  // The position is taken from the last layout; whether the ancestors paint
  // the marker, and whether its viewport is on screen, is read when this is
  // called.
  @override
  bool get _isInOwnRegion =>
      _laidOutInRegion && paintsChain(this) && _isViewportOnScreen();

  // The constraints describe the region of the enclosing viewport only. A
  // viewport that is painted but clipped away by its ancestors, such as a
  // nested scroll view below the fold of a SingleChildScrollView, is not on
  // screen, and neither is its region.
  bool _isViewportOnScreen() {
    final RenderObject? viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is! RenderBox || !viewport.hasSize) {
      return true;
    }
    final geometry = resolvePaintGeometry(viewport);
    if (geometry == null) {
      return false;
    }
    final bounds = MatrixUtils.transformRect(
      geometry.transform,
      Offset.zero & viewport.size,
    );
    return bounds.overlaps(geometry.clip);
  }

  @override
  void performLayout() {
    geometry = SliverGeometry.zero;
    final constraints = this.constraints;
    _laidOutInRegion = switch (_region) {
      // The scroll offset is how far the marker is above the leading edge of
      // the viewport, and the cache origin how far the cache area extends
      // above it.
      SliverRegion.cacheExtent =>
        constraints.remainingCacheExtent > 0 &&
            constraints.scrollOffset <=
                -constraints.cacheOrigin + precisionErrorTolerance,
      // A positive overlap means that a pinned or floating sliver before the
      // marker paints over its position.
      SliverRegion.viewport =>
        constraints.remainingPaintExtent > 0 &&
            constraints.scrollOffset <= precisionErrorTolerance &&
            constraints.overlap <= precisionErrorTolerance,
    };
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<SliverRegion>('region', region));
  }
}

/// The render object of [RegionMarker].
class RenderRegionMarker extends RenderBox
    with ScheduledObserver, RegionObserver {
  /// Creates a [RenderRegionMarker].
  RenderRegionMarker({required this.onRegionChanged});

  @override
  ValueChanged<bool> onRegionChanged;

  @override
  bool get _isInOwnRegion {
    if (!hasSize) {
      return false;
    }
    final geometry = resolvePaintGeometry(this);
    if (geometry == null) {
      return false;
    }
    final c = geometry.clip;
    if (c.width <= 0 || c.height <= 0) {
      return false;
    }
    final r = MatrixUtils.transformRect(geometry.transform, Offset.zero & size);
    // Rect.overlaps uses strict inequalities and never reports a zero-size
    // rect as overlapping, so compare against a half-open interval instead.
    return r.left < c.right &&
        r.right >= c.left &&
        r.top < c.bottom &&
        r.bottom >= c.top;
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return constraints.smallest;
  }
}
