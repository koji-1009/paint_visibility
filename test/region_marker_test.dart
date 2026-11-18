import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paint_visibility/paint_visibility.dart';
import 'package:paint_visibility/src/internal/render_region_marker.dart';

import 'helpers.dart';

// The test surface is 800x600 and the default cache extent is 250.
const double _viewport = 600;
const double _cache = 250;
const double _markerOffset = 1000;

// A zero-extent sliver is never "onstage" for finders.
final Finder _sliverMarker = find.byType(
  SliverRegionMarker,
  skipOffstage: false,
);

void main() {
  group('SliverRegionMarker', () {
    Future<ScrollController> pumpMarker(
      WidgetTester tester, {
      required List<bool> values,
      SliverRegion region = SliverRegion.cacheExtent,
    }) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _MarkerList(controller: controller, values: values, region: region),
      );
      return controller;
    }

    testWidgets('cacheExtent: trailing edge is exclusive', (tester) async {
      final values = <bool>[];
      final controller = await pumpMarker(tester, values: values);
      expect(values, [false]);

      // The marker sits exactly on the trailing edge of the cache area.
      controller.jumpTo(_markerOffset - _viewport - _cache);
      await tester.pump();
      expect(values, [false]);
      expect(isInRegionOf(tester, _sliverMarker), isFalse);

      controller.jumpTo(_markerOffset - _viewport - _cache + 1);
      await tester.pump();
      expect(values, [false, true]);
      expect(isInRegionOf(tester, _sliverMarker), isTrue);
    });

    testWidgets('cacheExtent: leading edge is inclusive', (tester) async {
      final values = <bool>[];
      final controller = await pumpMarker(tester, values: values);

      // The marker sits exactly on the leading edge of the cache area.
      controller.jumpTo(_markerOffset + _cache);
      await tester.pump();
      expect(values, [false, true]);

      controller.jumpTo(_markerOffset + _cache + 1);
      await tester.pump();
      expect(values, [false, true, false]);
    });

    testWidgets('viewport: trailing edge is exclusive', (tester) async {
      final values = <bool>[];
      final controller = await pumpMarker(
        tester,
        values: values,
        region: SliverRegion.viewport,
      );

      controller.jumpTo(_markerOffset - _viewport);
      await tester.pump();
      expect(values, [false]);

      controller.jumpTo(_markerOffset - _viewport + 1);
      await tester.pump();
      expect(values, [false, true]);
    });

    testWidgets('viewport: leading edge is inclusive', (tester) async {
      final values = <bool>[];
      final controller = await pumpMarker(
        tester,
        values: values,
        region: SliverRegion.viewport,
      );

      controller.jumpTo(_markerOffset);
      await tester.pump();
      expect(values, [false, true]);

      controller.jumpTo(_markerOffset + 1);
      await tester.pump();
      expect(values, [false, true, false]);
    });

    testWidgets('viewport excludes the cache area', (tester) async {
      final values = <bool>[];
      final controller = await pumpMarker(
        tester,
        values: values,
        region: SliverRegion.viewport,
      );
      controller.jumpTo(_markerOffset - _viewport - _cache + 1);
      await tester.pump();
      expect(values, [false]);
    });

    testWidgets('switching region relayouts and notifies', (tester) async {
      final values = <bool>[];
      final controller = ScrollController(
        initialScrollOffset: _markerOffset - _viewport - 100,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _MarkerList(controller: controller, values: values),
      );
      expect(values, [true]);

      await tester.pumpWidget(
        _MarkerList(
          controller: controller,
          values: values,
          region: SliverRegion.viewport,
        ),
      );
      expect(values, [true, false]);
    });

    testWidgets('stays silent while it remains in the region', (tester) async {
      final values = <bool>[];
      final controller = await pumpMarker(
        tester,
        values: values,
        region: SliverRegion.viewport,
      );
      controller.jumpTo(_markerOffset - 300);
      await tester.pump();
      controller.jumpTo(_markerOffset - 200);
      await tester.pump();
      controller.jumpTo(_markerOffset - 100);
      await tester.pump();
      expect(values, [false, true]);
    });

    testWidgets('replacing the callback does not relayout', (tester) async {
      final values = <bool>[];
      final controller = await pumpMarker(tester, values: values);
      final renderObject = tester.renderObject<RenderSliverRegionMarker>(
        _sliverMarker,
      );
      final other = <bool>[];
      await tester.pumpWidget(
        _MarkerList(controller: controller, values: other),
      );
      expect(renderObject.debugNeedsLayout, isFalse);
      expect(other, isEmpty);

      controller.jumpTo(_markerOffset);
      await tester.pump();
      expect(values, [false]);
      expect(other, [true]);
    });

    testWidgets('notifies false on detach after being in the region', (
      tester,
    ) async {
      final values = <bool>[];
      await tester.pumpWidget(
        wrap(
          CustomScrollView(
            slivers: [SliverRegionMarker(onRegionChanged: values.add)],
          ),
        ),
      );
      expect(values, [true]);

      await tester.pumpWidget(const SizedBox());
      expect(values, [true, false]);
    });

    testWidgets('notifies once per frame across multiple layouts', (
      tester,
    ) async {
      final values = <bool>[];
      final layouts = <bool>[];
      await tester.pumpWidget(
        wrap(
          CustomScrollView(
            slivers: [
              _CountingMarker(values: values, layouts: layouts),
              const _CorrectingSliver(correction: 100),
              const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ],
          ),
        ),
      );
      // The first layout sees the marker at the top of the viewport, the
      // corrected layout sees it scrolled past.
      expect(layouts, [true, false]);
      expect(values, [false]);
    });

    testWidgets('is outside the region in a hidden IndexedStack child', (
      tester,
    ) async {
      final values = <bool>[];
      Widget build(int index) => wrap(
        IndexedStack(
          index: index,
          children: [
            const SizedBox(),
            CustomScrollView(
              slivers: [SliverRegionMarker(onRegionChanged: values.add)],
            ),
          ],
        ),
      );
      await tester.pumpWidget(build(0));
      expect(values, [false]);

      await tester.pumpWidget(build(1));
      expect(values, [false, true]);

      await tester.pumpWidget(build(0));
      expect(values, [false, true, false]);
    });

    testWidgets('follows an IndexedStack without being rebuilt or laid out', (
      tester,
    ) async {
      final values = <bool>[];
      // The same widget instance is reused, so only the dependency registered
      // by the marker updates it.
      final scrollView = CustomScrollView(
        slivers: [SliverRegionMarker(onRegionChanged: values.add)],
      );
      Widget build(int index) => wrap(
        IndexedStack(index: index, children: [const SizedBox(), scrollView]),
      );
      await tester.pumpWidget(build(1));
      expect(values, [true]);
      final renderObject = tester.renderObject<RenderSliverRegionMarker>(
        _sliverMarker,
      );

      await tester.pumpWidget(build(0));
      expect(renderObject.debugNeedsLayout, isFalse);
      expect(values, [true, false]);

      await tester.pumpWidget(build(1));
      expect(values, [true, false, true]);
    });

    group('follows ancestors that stop painting it without a layout', () {
      Future<void> expectToggles(
        WidgetTester tester,
        Widget Function(Widget scrollView, {required bool painted}) build,
      ) async {
        final values = <bool>[];
        // The same widget instance is reused, so the marker is neither
        // rebuilt nor laid out by the toggles.
        final scrollView = CustomScrollView(
          slivers: [SliverRegionMarker(onRegionChanged: values.add)],
        );
        await tester.pumpWidget(wrap(build(scrollView, painted: true)));
        await tester.pumpWidget(wrap(build(scrollView, painted: false)));
        await tester.pumpWidget(wrap(build(scrollView, painted: true)));
        expect(values, [true, false, true]);
      }

      testWidgets('Offstage', (tester) async {
        await expectToggles(
          tester,
          (scrollView, {required painted}) =>
              Offstage(offstage: !painted, child: scrollView),
        );
      });

      testWidgets('Opacity', (tester) async {
        await expectToggles(
          tester,
          (scrollView, {required painted}) =>
              Opacity(opacity: painted ? 1 : 0, child: scrollView),
        );
      });

      testWidgets('SliverOffstage and SliverOpacity', (tester) async {
        for (final wrapSliver in <Widget Function(Widget, bool)>[
          (sliver, painted) =>
              SliverOffstage(offstage: !painted, sliver: sliver),
          (sliver, painted) =>
              SliverOpacity(opacity: painted ? 1 : 0, sliver: sliver),
        ]) {
          final values = <bool>[];
          final marker = SliverRegionMarker(onRegionChanged: values.add);
          Widget build(bool painted) =>
              wrap(CustomScrollView(slivers: [wrapSliver(marker, painted)]));
          await tester.pumpWidget(build(true));
          await tester.pumpWidget(build(false));
          await tester.pumpWidget(build(true));
          expect(values, [true, false, true]);
          await tester.pumpWidget(const SizedBox());
        }
      });
    });

    testWidgets('uses the cache extent of the viewport inside SliverPadding', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final values = <bool>[];
      await tester.pumpWidget(
        wrap(
          CustomScrollView(
            controller: controller,
            scrollCacheExtent: const ScrollCacheExtent.pixels(250),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.only(top: 100),
                sliver: SliverRegionMarker(onRegionChanged: values.add),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ],
          ),
        ),
      );
      // The marker is 200 above the viewport, inside the cache extent.
      controller.jumpTo(300);
      await tester.pump();
      expect(values, [true]);

      // 300 above the viewport, outside of it.
      controller.jumpTo(400);
      await tester.pump();
      expect(values, [true, false]);
    });

    testWidgets('is outside the viewport region under a pinned header', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final values = <bool>[];
      await tester.pumpWidget(
        wrap(
          CustomScrollView(
            controller: controller,
            slivers: [
              const SliverPersistentHeader(
                pinned: true,
                delegate: FixedHeader(minExtent: 50, maxExtent: 50),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 300)),
              SliverRegionMarker(
                region: SliverRegion.viewport,
                onRegionChanged: values.add,
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 2000)),
            ],
          ),
        ),
      );
      expect(values, [true]);

      // The marker at 350 is 70 below the top of the viewport, below the
      // header.
      controller.jumpTo(280);
      await tester.pump();
      expect(values, [true]);

      // 30 below the top of the viewport, under the header of extent 50.
      controller.jumpTo(320);
      await tester.pump();
      expect(values, [true, false]);
    });

    testWidgets('follows a move with a GlobalKey under a hidden Visibility', (
      tester,
    ) async {
      final values = <bool>[];
      final infos = <VisibilityInfo>[];
      // The same instances are moved, so only the dependencies registered by
      // the widgets update them.
      final marker = RegionMarker(
        key: GlobalKey(),
        onRegionChanged: values.add,
      );
      final box = PaintVisibility(
        key: GlobalKey(),
        routeCoverage: RouteCoverage.keep,
        onVisibilityChanged: record(infos),
        child: const SizedBox(width: 10, height: 10),
      );
      Widget build({required bool hidden}) {
        final children = Column(
          mainAxisSize: MainAxisSize.min,
          children: [marker, box],
        );
        return wrap(
          Center(
            child: hidden
                ? Visibility.maintain(visible: false, child: children)
                : Padding(padding: EdgeInsets.zero, child: children),
          ),
        );
      }

      await tester.pumpWidget(build(hidden: false));
      await tester.pumpWidget(build(hidden: true));
      expect(values, [true, false]);
      expect(infos.map((info) => info.visibleFraction), [1, 0]);
    });

    testWidgets('is outside the region under a singular transform', (
      tester,
    ) async {
      final values = <bool>[];
      Widget build(double scale) => wrap(
        Center(
          child: Transform.scale(
            scale: scale,
            child: RegionMarker(onRegionChanged: values.add),
          ),
        ),
      );
      await tester.pumpWidget(build(1));
      await tester.pumpWidget(build(0));
      expect(values, [true, false]);
    });

    testWidgets('is in the region again on a kept-alive page', (tester) async {
      final values = <bool>[];
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        wrap(
          PageView(
            controller: controller,
            children: [
              KeptAlive(
                child: CustomScrollView(
                  slivers: [SliverRegionMarker(onRegionChanged: values.add)],
                ),
              ),
              const SizedBox(),
              const SizedBox(),
            ],
          ),
        ),
      );
      expect(values, [true]);

      controller.jumpToPage(2);
      await tester.pump();
      expect(values, [true, false]);

      controller.jumpToPage(0);
      await tester.pump();
      expect(values, [true, false, true]);
    });

    testWidgets('follows an ancestor Visibility with maintainSize', (
      tester,
    ) async {
      final values = <bool>[];
      Widget build(bool visible) => wrap(
        Visibility.maintain(
          visible: visible,
          child: CustomScrollView(
            slivers: [SliverRegionMarker(onRegionChanged: values.add)],
          ),
        ),
      );
      await tester.pumpWidget(build(false));
      expect(values, [false]);

      await tester.pumpWidget(build(true));
      expect(values, [false, true]);

      await tester.pumpWidget(build(false));
      expect(values, [false, true, false]);
    });

    testWidgets('is in the region in an overlay child under a hidden '
        'Visibility', (tester) async {
      final overlayValues = <bool>[];
      final childValues = <bool>[];
      await tester.pumpWidget(
        _hiddenOverlayPortal(
          overlayChild: CustomScrollView(
            slivers: [
              SliverRegionMarker(
                key: const ValueKey('overlay'),
                onRegionChanged: overlayValues.add,
              ),
            ],
          ),
          child: SizedBox(
            width: 100,
            height: 100,
            child: CustomScrollView(
              slivers: [
                SliverRegionMarker(
                  key: const ValueKey('child'),
                  onRegionChanged: childValues.add,
                ),
              ],
            ),
          ),
        ),
      );
      // The overlay child is painted by the Overlay, the normal child under
      // the hidden Visibility.
      expect(overlayValues, [true]);
      expect(childValues, [false]);
      Finder marker(String key) =>
          find.byKey(ValueKey(key), skipOffstage: false);
      expect(isInRegionOf(tester, marker('overlay')), isTrue);
      expect(isInRegionOf(tester, marker('child')), isFalse);
    });

    testWidgets('works in a reversed sliver before center', (tester) async {
      final values = <bool>[];
      const centerKey = ValueKey('center');
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        wrap(
          CustomScrollView(
            controller: controller,
            center: centerKey,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 1000)),
              SliverRegionMarker(
                onRegionChanged: values.add,
                region: SliverRegion.viewport,
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 300)),
              const SliverToBoxAdapter(
                key: centerKey,
                child: SizedBox(height: 2000),
              ),
            ],
          ),
        ),
      );
      // The marker is 300 above center, which is at the top of the viewport.
      expect(values, [false]);

      // The reversed slivers grow upward, so the top of the viewport is the
      // trailing edge for the marker and is exclusive.
      controller.jumpTo(-300);
      await tester.pump();
      expect(values, [false]);

      controller.jumpTo(-301);
      await tester.pump();
      expect(values, [false, true]);

      // The bottom of the viewport is the leading edge and is inclusive.
      controller.jumpTo(-300 - _viewport);
      await tester.pump();
      expect(values, [false, true]);

      controller.jumpTo(-301 - _viewport);
      await tester.pump();
      expect(values, [false, true, false]);
    });

    for (final region in SliverRegion.values) {
      testWidgets('$region: is outside the region while its viewport is '
          'clipped away', (tester) async {
        final values = <bool>[];
        final controller = ScrollController();
        addTearDown(controller.dispose);
        // A nested scroll view below the fold of a SingleChildScrollView is
        // laid out and painted, but clipped away by the outer viewport.
        await tester.pumpWidget(
          wrap(
            SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [
                  const SizedBox(height: _viewport),
                  SizedBox(
                    height: 200,
                    child: CustomScrollView(
                      slivers: [
                        SliverRegionMarker(
                          onRegionChanged: values.add,
                          region: region,
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 400)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(values, [false]);

        controller.jumpTo(1);
        await tester.pump();
        expect(values, [false, true]);
      });
    }

    testWidgets('is outside the region in a cache extent child of an outer '
        'lazy list', (tester) async {
      final values = <bool>[];
      await tester.pumpWidget(
        wrap(
          ListView(
            scrollDirection: Axis.horizontal,
            children: [
              const SizedBox(width: 800),
              SizedBox(
                width: 200,
                child: CustomScrollView(
                  slivers: [
                    SliverRegionMarker(onRegionChanged: values.add),
                    const SliverToBoxAdapter(child: SizedBox(height: 400)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      // The inner scroll view is laid out in the cache extent of the
      // horizontal list, which does not paint it.
      expect(find.byType(CustomScrollView, skipOffstage: false), findsOne);
      expect(values, [false]);
    });
  });

  group('RegionMarker', () {
    Future<ScrollController> pumpColumn(
      WidgetTester tester,
      List<bool> values, {
      CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    }) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            controller: controller,
            child: Column(
              crossAxisAlignment: crossAxisAlignment,
              children: [
                const SizedBox(height: _markerOffset),
                RegionMarker(onRegionChanged: values.add),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('has zero size', (tester) async {
      await pumpColumn(tester, []);
      expect(tester.getSize(find.byType(RegionMarker)), Size.zero);
    });

    testWidgets('trailing edge is exclusive', (tester) async {
      final values = <bool>[];
      final controller = await pumpColumn(tester, values);
      expect(values, [false]);

      controller.jumpTo(_markerOffset - _viewport);
      await tester.pump();
      expect(values, [false]);
      expect(isInRegionOf(tester, find.byType(RegionMarker)), isFalse);

      controller.jumpTo(_markerOffset - _viewport + 1);
      await tester.pump();
      expect(values, [false, true]);
      expect(isInRegionOf(tester, find.byType(RegionMarker)), isTrue);
    });

    testWidgets('leading edge is inclusive', (tester) async {
      final values = <bool>[];
      final controller = await pumpColumn(tester, values);

      controller.jumpTo(_markerOffset);
      await tester.pump();
      expect(values, [false, true]);

      controller.jumpTo(_markerOffset + 1);
      await tester.pump();
      expect(values, [false, true, false]);
    });

    testWidgets('becomes a line when stretched', (tester) async {
      final values = <bool>[];
      final controller = await pumpColumn(
        tester,
        values,
        crossAxisAlignment: CrossAxisAlignment.stretch,
      );
      expect(tester.getSize(find.byType(RegionMarker)), const Size(800, 0));

      controller.jumpTo(_markerOffset);
      await tester.pump();
      expect(values, [false, true]);
    });

    testWidgets('is outside the region under Visibility with maintainSize', (
      tester,
    ) async {
      final values = <bool>[];
      Widget build(bool visible) => Center(
        child: Visibility.maintain(
          visible: visible,
          child: RegionMarker(onRegionChanged: values.add),
        ),
      );
      await tester.pumpWidget(build(false));
      expect(values, [false]);
      await tester.pumpWidget(build(true));
      expect(values, [false, true]);
    });

    testWidgets('is in the region in an overlay child under a hidden '
        'Visibility', (tester) async {
      final overlayValues = <bool>[];
      final childValues = <bool>[];
      await tester.pumpWidget(
        _hiddenOverlayPortal(
          overlayChild: Center(
            child: RegionMarker(onRegionChanged: overlayValues.add),
          ),
          child: RegionMarker(onRegionChanged: childValues.add),
        ),
      );
      // The overlay child is painted by the Overlay, the normal child under
      // the hidden Visibility.
      expect(overlayValues, [true]);
      expect(childValues, [false]);
    });

    testWidgets('is outside the region when not painted', (tester) async {
      final values = <bool>[];
      await tester.pumpWidget(
        Offstage(child: RegionMarker(onRegionChanged: values.add)),
      );
      expect(values, [false]);
    });

    testWidgets('notifies false on detach after being in the region', (
      tester,
    ) async {
      final values = <bool>[];
      await tester.pumpWidget(
        Center(child: RegionMarker(onRegionChanged: values.add)),
      );
      expect(values, [true]);

      await tester.pumpWidget(const SizedBox());
      expect(values, [true, false]);
    });

    testWidgets('uses the replaced callback', (tester) async {
      final first = <bool>[];
      final second = <bool>[];
      await tester.pumpWidget(
        Center(child: RegionMarker(onRegionChanged: first.add)),
      );
      await tester.pumpWidget(
        Center(child: RegionMarker(onRegionChanged: second.add)),
      );
      await tester.pumpWidget(const SizedBox());
      expect(first, [true]);
      expect(second, [false]);
    });
  });
}

/// An [OverlayPortal] showing [overlayChild] under
/// `Visibility.maintain(visible: false)`, with [child] as its normal child.
/// The overlay child is painted by the [Overlay] above the [Visibility].
Widget _hiddenOverlayPortal({
  required Widget overlayChild,
  required Widget child,
}) {
  return wrap(
    Overlay.wrap(
      child: Center(
        child: Visibility.maintain(
          visible: false,
          child: OverlayPortal(
            controller: OverlayPortalController()..show(),
            overlayChildBuilder: (_) => overlayChild,
            child: child,
          ),
        ),
      ),
    ),
  );
}

class _MarkerList extends StatelessWidget {
  const _MarkerList({
    required this.controller,
    required this.values,
    this.region = SliverRegion.cacheExtent,
  });

  final ScrollController controller;
  final List<bool> values;
  final SliverRegion region;

  @override
  Widget build(BuildContext context) {
    return wrap(
      CustomScrollView(
        controller: controller,
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: _markerOffset)),
          SliverRegionMarker(onRegionChanged: values.add, region: region),
          const SliverToBoxAdapter(child: SizedBox(height: 2000)),
        ],
      ),
    );
  }
}

class _CountingMarker extends LeafRenderObjectWidget {
  const _CountingMarker({required this.values, required this.layouts});

  final List<bool> values;
  final List<bool> layouts;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCountingMarker(values: values, layouts: layouts);
  }
}

class _RenderCountingMarker extends RenderSliverRegionMarker {
  _RenderCountingMarker({required List<bool> values, required this.layouts})
    : super(onRegionChanged: values.add, region: SliverRegion.viewport);

  final List<bool> layouts;

  @override
  void performLayout() {
    super.performLayout();
    layouts.add(isInRegion);
  }
}

/// A sliver that asks the viewport for a scroll offset correction on its
/// first layout, forcing the viewport to lay out its children again within
/// the same frame.
class _CorrectingSliver extends LeafRenderObjectWidget {
  const _CorrectingSliver({required this.correction});

  final double correction;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCorrectingSliver(correction);
  }
}

class _RenderCorrectingSliver extends RenderSliver {
  _RenderCorrectingSliver(this.correction);

  final double correction;
  bool _corrected = false;

  @override
  void performLayout() {
    if (!_corrected) {
      _corrected = true;
      geometry = SliverGeometry(scrollOffsetCorrection: correction);
      return;
    }
    geometry = SliverGeometry.zero;
  }
}
