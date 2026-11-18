import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:paint_visibility/src/internal/render_region_marker.dart';
import 'package:paint_visibility/src/internal/route_state.dart';
import 'package:paint_visibility/src/route_coverage.dart';

/// The region a [SliverRegionMarker] tests its position against.
enum SliverRegion {
  /// The viewport plus the cache extent on both sides.
  cacheExtent,

  /// The viewport only.
  viewport,
}

/// The configuration shared by [RegionMarker] and [SliverRegionMarker].
abstract class _RegionMarkerWidget extends LeafRenderObjectWidget {
  const _RegionMarkerWidget({
    super.key,
    required this.onRegionChanged,
    required this.routeCoverage,
  });

  /// Called with whether the marker is inside its region, when it enters or
  /// leaves the region.
  final ValueChanged<bool> onRegionChanged;

  /// How the marker is reported while its route is covered by another route.
  ///
  /// Defaults to [RouteCoverage.keep]. With another value, returning to the
  /// page reports `true` again when the marker is still inside the region,
  /// which triggers another load when used for infinite loading.
  final RouteCoverage routeCoverage;

  RegionObserver _createObserver();

  @override
  RenderObject createRenderObject(BuildContext context) {
    final observer = _createObserver();
    updateRenderObject(context, observer);
    return observer;
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as RegionObserver)
      ..onRegionChanged = onRegionChanged
      ..routeState = routeStateOf(context, routeCoverage);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<RouteCoverage>('routeCoverage', routeCoverage));
  }
}

/// A zero-extent sliver that reports whether its position is inside a
/// region of the enclosing viewport.
///
/// A zero-extent marker has no area, so instead of a visible fraction it
/// reports a bool, like a sentinel element observed by the web's
/// IntersectionObserver. Typical uses are triggering infinite loading,
/// recording reading progress and detecting that a section was reached.
///
/// The main axis is treated as the half-open interval \[leading, trailing):
/// a marker exactly on the leading edge is inside, a marker exactly on the
/// trailing edge is outside.
///
/// The position is evaluated during layout from [SliverConstraints] alone.
/// In the post-frame phase of each rendered frame, the marker checks that
/// its ancestors still paint it, and [onRegionChanged] is invoked when the
/// value differs from the last notified value. The first value is always
/// notified.
///
/// The marker is outside the region while an ancestor does not paint it
/// (`Offstage`, `SliverOffstage`, `Opacity` or `SliverOpacity` at zero, a
/// [Visibility] or [SliverVisibility] that is not visible, a child of an
/// [IndexedStack] that is not displayed, a kept-alive child of a lazy list or
/// a child in its cache extent), while its viewport is entirely clipped away
/// by the ancestors of the viewport, and while its route is covered according
/// to [routeCoverage].
///
/// The marker reports only the moments it enters or leaves the region. When
/// it stays inside the region after a page has been loaded, no further
/// notification arrives. For infinite loading, choose a page size large
/// enough that one page is taller than the region.
class SliverRegionMarker extends _RegionMarkerWidget {
  /// Creates a zero-extent sliver marker.
  const SliverRegionMarker({
    super.key,
    required super.onRegionChanged,
    this.region = SliverRegion.cacheExtent,
    super.routeCoverage = RouteCoverage.keep,
  });

  /// The region the marker position is tested against.
  final SliverRegion region;

  @override
  RegionObserver _createObserver() =>
      RenderSliverRegionMarker(onRegionChanged: onRegionChanged);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as RenderSliverRegionMarker).region = region;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<SliverRegion>('region', region));
  }
}

/// A zero-size box that reports whether its position is inside the visible
/// region of its ancestors.
///
/// The box counterpart of [SliverRegionMarker], for places where no sliver
/// can be used, such as the end of a [Column] inside a
/// [SingleChildScrollView]. When stretched along the cross axis, the marker
/// becomes a line.
///
/// The region is the accumulated paint clip of the ancestors, which is the
/// viewport. The cache extent is internal to the viewport and cannot be
/// observed from a box, so it is not included.
///
/// The position is evaluated in the post-frame phase of each rendered frame,
/// treating each axis as the half-open interval \[leading, trailing).
class RegionMarker extends _RegionMarkerWidget {
  /// Creates a zero-size marker.
  const RegionMarker({
    super.key,
    required super.onRegionChanged,
    super.routeCoverage = RouteCoverage.keep,
  });

  @override
  RegionObserver _createObserver() =>
      RenderRegionMarker(onRegionChanged: onRegionChanged);
}
