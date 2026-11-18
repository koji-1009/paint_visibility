// Helpers shared by the tests.
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paint_visibility/paint_visibility.dart';
import 'package:paint_visibility/src/internal/render_region_marker.dart';

/// The snapping tolerance of [VisibilityInfo.visibleFraction].
const double tolerance = 0.01;

/// Wraps [child] in a left-to-right [Directionality].
Widget wrap(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

/// A callback that appends each notified value to [infos].
VisibilityChangedCallback record(List<VisibilityInfo> infos) =>
    (info, _) => infos.add(info);

/// The current value of the marker found by [finder].
bool isInRegionOf(WidgetTester tester, Finder finder) {
  return switch (tester.renderObject(finder)) {
    final RenderRegionMarker marker => marker.isInRegion,
    final RenderSliverRegionMarker marker => marker.isInRegion,
    final other => throw StateError('$other is not a marker.'),
  };
}

/// Wraps each probed widget in a [PaintVisibility] or
/// [SliverPaintVisibility] and records the last notified value.
class Recorder {
  final Map<Object, VisibilityInfo> frame = {};
  final Set<Object> _slivers = {};

  /// The key of the observer of the probe [id].
  Key key(Object id) => ValueKey<Object>(('probe', id));

  Widget box(Object id, Widget child) {
    return PaintVisibility(
      key: key(id),
      onVisibilityChanged: (info, _) => frame[id] = info,
      child: child,
    );
  }

  Widget sliver(Object id, Widget sliver) {
    _slivers.add(id);
    return SliverPaintVisibility(
      key: key(id),
      onVisibilityChanged: (info, _) => frame[id] = info,
      sliver: sliver,
    );
  }

  /// Checks every probe that is currently in the tree against a value
  /// derived independently of this package.
  ///
  /// A box is expected to be visible where its rect on screen
  /// ([WidgetTester.getRect]) overlaps [clip], the screen by default. A
  /// sliver is expected to be visible over its paint extent out of its scroll
  /// extent, as laid out by its viewport. Only probes that are painted under
  /// plain scroll views are checked this way.
  void expectClippedTo(WidgetTester tester, {Rect? clip}) {
    final screen =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final region = clip?.intersect(screen) ?? screen;
    var checked = 0;
    for (final id in frame.keys) {
      final finder = find.byKey(key(id), skipOffstage: false);
      if (finder.evaluate().isEmpty) {
        continue;
      }
      final double expected;
      if (_slivers.contains(id)) {
        final geometry = tester.renderObject<RenderSliver>(finder).geometry!;
        expected = geometry.scrollExtent > 0
            ? geometry.paintExtent / geometry.scrollExtent
            : 0;
      } else {
        final rect = tester.getRect(finder);
        final visible = rect.overlaps(region)
            ? rect.intersect(region)
            : Rect.zero;
        expected = rect.isEmpty
            ? 0
            : visible.width * visible.height / (rect.width * rect.height);
      }
      checked++;
      expect(
        frame[id]!.visibleFraction,
        closeTo(expected, tolerance),
        reason: 'probe $id: ${frame[id]}',
      );
    }
    expect(checked, greaterThan(0));
  }
}

/// A header of fixed extents that paints a black box.
class FixedHeader extends SliverPersistentHeaderDelegate {
  const FixedHeader({required this.minExtent, required this.maxExtent});

  @override
  final double minExtent;

  @override
  final double maxExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => const SizedBox.expand(child: ColoredBox(color: Color(0xFF000000)));

  @override
  bool shouldRebuild(FixedHeader oldDelegate) =>
      minExtent != oldDelegate.minExtent || maxExtent != oldDelegate.maxExtent;
}

/// Keeps [child] alive in a lazy list.
///
/// Not named `KeepAlive`, which is a widget of the framework.
class KeptAlive extends StatefulWidget {
  const KeptAlive({super.key, required this.child});

  final Widget child;

  @override
  State<KeptAlive> createState() => _KeptAliveState();
}

class _KeptAliveState extends State<KeptAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
