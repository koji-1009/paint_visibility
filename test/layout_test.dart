// Visible fractions on common layouts and scroll positions, checked against
// values derived independently of this package (see
// Recorder.expectClippedTo) or by hand.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('ListView vertical scroll', (tester) async {
    final recorder = Recorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        ListView.builder(
          controller: controller,
          itemCount: 30,
          itemBuilder: (context, i) =>
              recorder.box(i, const SizedBox(height: 130)),
        ),
      ),
    );
    recorder.expectClippedTo(tester);
    for (final offset in [37.0, 200.0, 555.5, 1000.0]) {
      controller.jumpTo(offset);
      await tester.pump();
      recorder.expectClippedTo(tester);
    }
  });

  testWidgets('ListView horizontal and reverse', (tester) async {
    final recorder = Recorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          reverse: true,
          itemCount: 30,
          itemBuilder: (context, i) =>
              recorder.box(i, const SizedBox(width: 170)),
        ),
      ),
    );
    recorder.expectClippedTo(tester);
    for (final offset in [45.0, 333.0, 900.0]) {
      controller.jumpTo(offset);
      await tester.pump();
      recorder.expectClippedTo(tester);
    }
  });

  testWidgets('GridView', (tester) async {
    final recorder = Recorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        GridView.builder(
          controller: controller,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
          ),
          itemCount: 60,
          itemBuilder: (context, i) => recorder.box(i, const SizedBox()),
        ),
      ),
    );
    recorder.expectClippedTo(tester);
    for (final offset in [77.0, 410.0]) {
      controller.jumpTo(offset);
      await tester.pump();
      recorder.expectClippedTo(tester);
    }
  });

  testWidgets('CustomScrollView slivers, including before center', (
    tester,
  ) async {
    final recorder = Recorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    const centerKey = ValueKey('center');
    await tester.pumpWidget(
      wrap(
        CustomScrollView(
          controller: controller,
          center: centerKey,
          slivers: [
            recorder.sliver('before-1', _sliverBox(400)),
            recorder.sliver('before-0', _sliverBox(250)),
            KeyedSubtree(
              key: centerKey,
              child: recorder.sliver('center', _sliverBox(300)),
            ),
            recorder.sliver('after-0', _sliverBox(500)),
            recorder.sliver(
              'list',
              SliverList.builder(
                itemCount: 10,
                itemBuilder: (context, i) => const SizedBox(height: 100),
              ),
            ),
          ],
        ),
      ),
    );
    recorder.expectClippedTo(tester);
    for (final offset in [-120.0, -500.0, 150.0, 640.0, 1200.0]) {
      controller.jumpTo(offset);
      await tester.pump();
      recorder.expectClippedTo(tester);
    }
    // At 1200 only the list is visible; the slivers above it are hidden.
    expect(recorder.frame['center']!.visibleFraction, 0);
    expect(recorder.frame['after-0']!.visibleFraction, 0);
    expect(recorder.frame['list']!.visibleFraction, greaterThan(0));
  });

  testWidgets('horizontal reverse slivers', (tester) async {
    final recorder = Recorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        CustomScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          reverse: true,
          slivers: [
            for (var i = 0; i < 5; i++)
              recorder.sliver(
                i,
                const SliverToBoxAdapter(child: SizedBox(width: 330)),
              ),
          ],
        ),
      ),
    );
    recorder.expectClippedTo(tester);
    controller.jumpTo(250);
    await tester.pump();
    recorder.expectClippedTo(tester);
  });

  testWidgets('nested scroll views', (tester) async {
    final recorder = Recorder();
    final outer = ScrollController();
    final inner = ScrollController();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    await tester.pumpWidget(
      wrap(
        ListView(
          controller: outer,
          children: [
            const SizedBox(height: 300),
            SizedBox(
              height: 200,
              child: ListView.builder(
                key: const ValueKey('inner'),
                controller: inner,
                scrollDirection: Axis.horizontal,
                itemCount: 20,
                itemBuilder: (context, i) =>
                    recorder.box(i, const SizedBox(width: 150)),
              ),
            ),
            const SizedBox(height: 1000),
          ],
        ),
      ),
    );
    Rect innerRect() => tester.getRect(find.byKey(const ValueKey('inner')));
    recorder.expectClippedTo(tester, clip: innerRect());
    inner.jumpTo(75);
    outer.jumpTo(180);
    await tester.pump();
    recorder.expectClippedTo(tester, clip: innerRect());
    outer.jumpTo(420);
    await tester.pump();
    recorder.expectClippedTo(tester, clip: innerRect());
  });

  testWidgets('Transform.scale and FittedBox', (tester) async {
    final recorder = Recorder();
    await tester.pumpWidget(
      wrap(
        Stack(
          children: [
            Positioned(
              left: 100,
              top: 100,
              child: Transform.scale(
                scale: 1.5,
                child: recorder.box(
                  'scaled-inside',
                  const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
            Positioned(
              left: 700,
              top: 0,
              child: Transform.scale(
                scale: 2,
                child: recorder.box(
                  'scaled',
                  const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 500,
              width: 300,
              height: 200,
              child: FittedBox(
                child: recorder.box(
                  'fitted',
                  const SizedBox(width: 50, height: 50),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    expect(recorder.frame['scaled-inside']!.size, const Size(150, 150));
    expect(recorder.frame['scaled-inside']!.visibleFraction, 1);
    // The box spans (650, -50)-(850, 150) and the view is 800x600.
    expect(recorder.frame['scaled']!.size, const Size(200, 200));
    expect(
      recorder.frame['scaled']!.visibleBounds,
      const Rect.fromLTRB(0, 50, 150, 200),
    );
    // FittedBox scales 50x50 by 4 into 200x200 at y=500..700.
    expect(recorder.frame['fitted']!.size, const Size(200, 200));
    expect(
      recorder.frame['fitted']!.visibleBounds,
      const Rect.fromLTRB(0, 0, 200, 100),
    );
  });

  testWidgets('ClipRect and ClipRRect', (tester) async {
    final recorder = Recorder();
    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            ClipRect(
              child: SizedBox(
                width: 200,
                height: 100,
                child: OverflowBox(
                  maxHeight: 400,
                  alignment: Alignment.topCenter,
                  child: recorder.box(
                    'rect',
                    const SizedBox(width: 200, height: 400),
                  ),
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: 200,
                height: 50,
                child: OverflowBox(
                  maxHeight: 200,
                  alignment: Alignment.topCenter,
                  child: recorder.box(
                    'rrect',
                    const SizedBox(width: 200, height: 200),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    expect(
      recorder.frame['rect']!.visibleBounds,
      const Rect.fromLTRB(0, 0, 200, 100),
    );
    expect(recorder.frame['rect']!.visibleFraction, 0.25);
    expect(
      recorder.frame['rrect']!.visibleBounds,
      const Rect.fromLTRB(0, 0, 200, 50),
    );
    expect(recorder.frame['rrect']!.visibleFraction, 0.25);
  });

  testWidgets('Offstage and IndexedStack', (tester) async {
    final recorder = Recorder();
    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            Offstage(
              child: recorder.box(
                'offstage',
                const SizedBox(width: 10, height: 10),
              ),
            ),
            IndexedStack(
              index: 1,
              children: [
                recorder.box('hidden', const SizedBox(width: 10, height: 10)),
                recorder.box('shown', const SizedBox(width: 10, height: 10)),
              ],
            ),
          ],
        ),
      ),
    );
    expect(recorder.frame['offstage']!.visibleFraction, 0);
    expect(recorder.frame['hidden']!.visibleFraction, 0);
    expect(recorder.frame['shown']!.visibleFraction, 1);
  });

  testWidgets('widgets that hide their child', (tester) async {
    final recorder = Recorder();
    await tester.pumpWidget(
      wrap(
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Visibility.maintain(
                visible: false,
                child: recorder.box('maintainSize', const SizedBox(height: 50)),
              ),
            ),
            SliverOpacity(
              opacity: 0,
              sliver: recorder.sliver('sliverOpacity', _sliverBox(50)),
            ),
            SliverOffstage(
              sliver: recorder.sliver('sliverOffstage', _sliverBox(50)),
            ),
            SliverOpacity(
              opacity: 0.5,
              sliver: recorder.sliver('sliverHalfOpacity', _sliverBox(50)),
            ),
          ],
        ),
      ),
    );
    expect(recorder.frame['maintainSize']!.visibleFraction, 0);
    expect(recorder.frame['sliverOpacity']!.visibleFraction, 0);
    expect(recorder.frame['sliverOffstage']!.visibleFraction, 0);
    expect(recorder.frame['sliverHalfOpacity']!.visibleFraction, 1);
  });

  testWidgets('widgets that clip their children', (tester) async {
    final recorder = Recorder();
    Widget clipped(Widget child) =>
        SizedBox(width: 100, height: 50, child: child);
    await tester.pumpWidget(
      wrap(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            clipped(
              FittedBox(
                fit: BoxFit.none,
                clipBehavior: Clip.hardEdge,
                child: recorder.box(
                  'fittedBox',
                  const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
            clipped(
              Wrap(
                clipBehavior: Clip.hardEdge,
                children: [
                  recorder.box('wrap', const SizedBox(width: 100, height: 100)),
                ],
              ),
            ),
            clipped(
              Flow(
                delegate: const _OffsetFlowDelegate(Offset(0, 25)),
                children: [
                  recorder.box('flow', const SizedBox(width: 100, height: 50)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    expect(recorder.frame['fittedBox']!.visibleFraction, 0.5);
    expect(recorder.frame['wrap']!.visibleFraction, 0.5);
    expect(recorder.frame['flow']!.visibleFraction, 0.5);
  });

  testWidgets('AnimatedSize clips a growing child', (tester) async {
    final recorder = Recorder();
    Widget build(double height) => wrap(
      Align(
        alignment: Alignment.topLeft,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 100),
          alignment: Alignment.topLeft,
          child: recorder.box('child', SizedBox(width: 100, height: height)),
        ),
      ),
    );
    await tester.pumpWidget(build(10));
    await tester.pumpWidget(build(110));
    await tester.pump(const Duration(milliseconds: 50));
    // AnimatedSize is about 60 tall (curve is linear) while the child is 110.
    expect(
      recorder.frame['child']!.visibleFraction,
      closeTo(60 / 110, tolerance),
    );
    await tester.pumpAndSettle();
    expect(recorder.frame['child']!.visibleFraction, 1);
  });

  testWidgets('content under a pinned header is hidden', (tester) async {
    final recorder = Recorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        CustomScrollView(
          controller: controller,
          slivers: [
            const SliverPersistentHeader(
              pinned: true,
              delegate: FixedHeader(minExtent: 100, maxExtent: 100),
            ),
            SliverToBoxAdapter(
              child: recorder.box('item', const SizedBox(height: 100)),
            ),
            _sliverBox(2000),
          ],
        ),
      ),
    );
    controller.jumpTo(50);
    await tester.pump();
    // The viewport reports the area under a pinned header as clipped for the
    // following slivers.
    expect(recorder.frame['item']!.visibleFraction, 0.5);
    controller.jumpTo(100);
    await tester.pump();
    expect(recorder.frame['item']!.visibleFraction, 0);
  });

  testWidgets('a pinned header scrolled past', (tester) async {
    final recorder = Recorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        CustomScrollView(
          controller: controller,
          slivers: [
            recorder.sliver(
              'header',
              const SliverPersistentHeader(
                pinned: true,
                delegate: FixedHeader(minExtent: 50, maxExtent: 200),
              ),
            ),
            _sliverBox(2000),
          ],
        ),
      ),
    );
    controller.jumpTo(500);
    await tester.pump();
    // Collapsed to 50 of 200 and still painted at the top.
    expect(recorder.frame['header']!.visibleFraction, closeTo(0.25, 1e-9));
  });

  testWidgets('page covered by an opaque route', (tester) async {
    final recorder = Recorder();
    final navigator = GlobalKey<NavigatorState>();
    PageRouteBuilder<void> route(Widget page) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (context, animation, secondaryAnimation) => page,
    );
    await tester.pumpWidget(
      wrap(
        Navigator(
          key: navigator,
          onGenerateRoute: (_) =>
              route(recorder.box('page', const SizedBox.expand())),
        ),
      ),
    );
    expect(recorder.frame['page']!.visibleFraction, 1);

    unawaited(navigator.currentState!.push(route(const SizedBox.expand())));
    await tester.pumpAndSettle();
    expect(recorder.frame['page']!.visibleFraction, 0);
  });

  testWidgets('kept-alive children', (tester) async {
    final recorder = Recorder();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      wrap(
        ListView.builder(
          controller: controller,
          itemCount: 50,
          itemBuilder: (context, i) =>
              KeptAlive(child: recorder.box(i, const SizedBox(height: 100))),
        ),
      ),
    );
    expect(recorder.frame[0]!.visibleFraction, 1);
    controller.jumpTo(3000);
    await tester.pump();
    expect(recorder.frame[0]!.visibleFraction, 0);
    expect(recorder.frame[30]!.visibleFraction, 1);
  });
}

Widget _sliverBox(double extent) {
  return SliverToBoxAdapter(child: SizedBox(height: extent));
}

class _OffsetFlowDelegate extends FlowDelegate {
  const _OffsetFlowDelegate(this.offset);

  final Offset offset;

  @override
  void paintChildren(FlowPaintingContext context) {
    for (var i = 0; i < context.childCount; i++) {
      context.paintChild(
        i,
        transform: Matrix4.translationValues(offset.dx, offset.dy, 0),
      );
    }
  }

  @override
  bool shouldRepaint(_OffsetFlowDelegate oldDelegate) =>
      offset != oldDelegate.offset;
}
