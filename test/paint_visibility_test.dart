import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paint_visibility/paint_visibility.dart';

import 'helpers.dart';

void main() {
  group('PaintVisibility notification contract', () {
    testWidgets('settles the first value within one pump', (tester) async {
      final infos = <VisibilityInfo>[];
      await tester.pumpWidget(
        Center(
          child: PaintVisibility(
            onVisibilityChanged: record(infos),
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      expect(infos, hasLength(1));
      expect(infos.single.size, const Size(100, 100));
      expect(infos.single.visibleFraction, 1);
    });

    testWidgets('notifies the first value even when hidden', (tester) async {
      final infos = <VisibilityInfo>[];
      await tester.pumpWidget(
        Offstage(
          child: PaintVisibility(
            onVisibilityChanged: record(infos),
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      expect(infos, hasLength(1));
      expect(infos.single.visibleFraction, 0);
    });

    testWidgets('does not notify when the value does not change', (
      tester,
    ) async {
      final infos = <VisibilityInfo>[];
      Widget build(Color color) => Center(
        child: PaintVisibility(
          onVisibilityChanged: record(infos),
          child: ColoredBox(
            color: color,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pumpWidget(build(const Color(0xFFFF0000)));
      await tester.pumpWidget(build(const Color(0xFF0000FF)));
      await tester.pump();
      expect(infos, hasLength(1));
    });

    testWidgets('notifies each scrolled frame that changes the fraction', (
      tester,
    ) async {
      final infos = <VisibilityInfo>[];
      await tester.pumpWidget(
        wrap(
          ListView(
            children: [
              PaintVisibility(
                onVisibilityChanged: record(infos),
                child: const SizedBox(height: 100),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
      expect(infos.last.visibleFraction, 1);

      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      expect(infos.last.visibleFraction, closeTo(0.7, 1e-9));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      expect(infos.last.visibleFraction, closeTo(0.5, 1e-9));
      await gesture.up();
      await tester.pump();
    });

    group('reasons', () {
      testWidgets('each notification carries why it was notified', (
        tester,
      ) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final reasons = <Set<VisibilityChangeReason>>[];
        Widget build({double height = 100, bool present = true}) => wrap(
          ListView(
            controller: controller,
            children: [
              if (present)
                PaintVisibility(
                  key: const ValueKey('probe'),
                  onVisibilityChanged: (_, r) => reasons.add(r),
                  child: SizedBox(height: height),
                ),
              const SizedBox(height: 2000),
            ],
          ),
        );
        await tester.pumpWidget(build());
        expect(reasons.last, {VisibilityChangeReason.initial});

        // 15% hidden: from [1, 1.1) to [0.8, 0.9).
        controller.jumpTo(15);
        await tester.pump();
        expect(reasons.last, {VisibilityChangeReason.stepCrossed});

        controller.jumpTo(0);
        await tester.pump();
        expect(reasons.last, {
          VisibilityChangeReason.stepCrossed,
          VisibilityChangeReason.fullyVisible,
        });

        await tester.pumpWidget(build(height: 120));
        expect(reasons.last, {VisibilityChangeReason.resized});

        // Out of the viewport but within the cache extent, so the same render
        // object stays.
        controller.jumpTo(200);
        await tester.pump();
        expect(reasons.last, {VisibilityChangeReason.hidden});

        controller.jumpTo(0);
        await tester.pump();
        expect(reasons.last, {
          VisibilityChangeReason.shown,
          VisibilityChangeReason.fullyVisible,
        });

        await tester.pumpWidget(build(present: false));
        expect(reasons.last, {VisibilityChangeReason.hidden});
      });
    });

    group('fraction step', () {
      Future<List<VisibilityInfo>> pumpList(
        WidgetTester tester,
        ScrollController controller, {
        double fractionStep = 0.01,
        double height = 100,
      }) async {
        final infos = <VisibilityInfo>[];
        await tester.pumpWidget(
          wrap(
            ListView(
              controller: controller,
              children: [
                PaintVisibility(
                  fractionStep: fractionStep,
                  onVisibilityChanged: record(infos),
                  child: SizedBox(height: height),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        );
        return infos;
      }

      testWidgets('notifies only when the fraction crosses a multiple', (
        tester,
      ) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final infos = await pumpList(tester, controller);
        expect(infos, hasLength(1));

        // Each step hides 0.4% of the 100 px child: 0.996, 0.992, 0.988, ...
        for (var i = 1; i <= 10; i++) {
          controller.jumpTo(i * 0.4);
          await tester.pump();
        }
        // Notified when entering [0.98, 0.99) at 0.988, [0.97, 0.98) at 0.976
        // and [0.96, 0.97) at 0.968.
        expect(infos.map((info) => info.visibleBounds.top), [
          0,
          closeTo(1.2, 1e-9),
          closeTo(2.4, 1e-9),
          closeTo(3.2, 1e-9),
        ]);
      });

      testWidgets('the last value is in the interval of the current one', (
        tester,
      ) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final fractions = <double>[];
        // A 200 px child whose top 14 px are inside the 600 px viewport (7%).
        await tester.pumpWidget(
          wrap(
            ListView(
              controller: controller,
              children: [
                const SizedBox(height: 586),
                PaintVisibility(
                  fractionStep: 0.1,
                  onVisibilityChanged: (info, _) =>
                      fractions.add(info.visibleFraction),
                  child: const SizedBox(height: 200),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        );
        // Reveals 1% per frame and stops at 58%. The change since the value
        // notified last before stopping is below 0.1.
        for (var px = 2; px <= 102; px += 2) {
          controller.jumpTo(px.toDouble());
          await tester.pump();
        }
        int interval(double fraction) => (fraction * 10 + 1e-9).floor();
        expect(fractions.first, closeTo(0.07, 1e-9));
        expect(interval(fractions.last), interval(0.58));
        expect(fractions.last, greaterThanOrEqualTo(0.5));
        // Each notification enters a new interval.
        for (var i = 1; i < fractions.length; i++) {
          expect(interval(fractions[i]), isNot(interval(fractions[i - 1])));
        }
      });

      testWidgets('notifies becoming fully visible', (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final infos = await pumpList(tester, controller);
        controller.jumpTo(5);
        await tester.pump();
        expect(infos.last.visibleBounds.top, 5);

        controller.jumpTo(0.5);
        await tester.pump();
        expect(infos.last.visibleBounds.top, closeTo(0.5, 1e-9));

        // 0.5% away from the last value, but fully visible.
        controller.jumpTo(0);
        await tester.pump();
        expect(infos.last.visibleBounds, const Rect.fromLTWH(0, 0, 800, 100));
      });

      testWidgets('notifies a change of size', (tester) async {
        final infos = <VisibilityInfo>[];
        Widget build(double width) => wrap(
          Center(
            child: PaintVisibility(
              onVisibilityChanged: record(infos),
              child: SizedBox(width: width, height: 100),
            ),
          ),
        );
        await tester.pumpWidget(build(100));
        await tester.pumpWidget(build(100.5));
        expect(infos.map((info) => info.size.width), [100, 100.5]);
      });

      // The size is the difference of two global positions, which carries
      // floating point error at fractional scroll offsets: a 73.7 px child
      // measures 73.70000000000002 at one offset and 73.69999999999999 at
      // another.
      testWidgets('does not notify floating point error in the size', (
        tester,
      ) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final reasons = <Set<VisibilityChangeReason>>[];
        final sizes = <double>{};
        await tester.pumpWidget(
          wrap(
            ListView(
              controller: controller,
              children: [
                const SizedBox(height: 200),
                PaintVisibility(
                  onVisibilityChanged: (info, r) => reasons.add(r),
                  child: const SizedBox(height: 73.7),
                ),
                const SizedBox(height: 5000),
              ],
            ),
          ),
        );
        final box = tester.renderObject<RenderBox>(
          find.byType(PaintVisibility),
        );
        for (var i = 1; i <= 300; i++) {
          controller.jumpTo(i * 0.37);
          await tester.pump();
          sizes.add(
            MatrixUtils.transformRect(
              box.getTransformTo(null),
              Offset.zero & box.size,
            ).height,
          );
        }
        // The error is present, and the child stays fully visible with the
        // same size, so only the first value is notified.
        expect(sizes.length, greaterThan(1));
        expect(reasons, [
          {VisibilityChangeReason.initial},
        ]);
      });

      testWidgets('notifies no resize while a child crosses the edge at '
          'fractional offsets', (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final reasons = <Set<VisibilityChangeReason>>[];
        await tester.pumpWidget(
          wrap(
            ListView(
              controller: controller,
              children: [
                const SizedBox(height: 550.3),
                PaintVisibility(
                  onVisibilityChanged: (info, r) => reasons.add(r),
                  child: const SizedBox(height: 73.7),
                ),
                const SizedBox(height: 5000),
              ],
            ),
          ),
        );
        for (var i = 1; i <= 300; i++) {
          controller.jumpTo(i * 0.37);
          await tester.pump();
        }
        expect(reasons.length, greaterThan(2));
        for (final r in reasons.skip(1)) {
          expect(r, isNot(contains(VisibilityChangeReason.resized)));
        }
      });
    });

    testWidgets('notifies a hidden value once on detach', (tester) async {
      final infos = <VisibilityInfo>[];
      await tester.pumpWidget(
        Center(
          child: PaintVisibility(
            onVisibilityChanged: record(infos),
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      expect(infos, hasLength(1));

      await tester.pumpWidget(const SizedBox());
      expect(infos, hasLength(2));
      expect(infos.last.size, const Size(100, 100));
      expect(infos.last.visibleBounds, Rect.zero);
      expect(infos.last.visibleFraction, 0);

      await tester.pump();
      expect(infos, hasLength(2));
    });

    testWidgets('does not notify on detach when last value was hidden', (
      tester,
    ) async {
      final infos = <VisibilityInfo>[];
      await tester.pumpWidget(
        Offstage(
          child: PaintVisibility(
            onVisibilityChanged: record(infos),
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      expect(infos, hasLength(1));
    });

    testWidgets('a recreated render object notifies again', (tester) async {
      final infos = <VisibilityInfo>[];
      Widget build(Key key) => Center(
        key: key,
        child: PaintVisibility(
          onVisibilityChanged: record(infos),
          child: const SizedBox(width: 100, height: 100),
        ),
      );
      await tester.pumpWidget(build(const ValueKey(1)));
      expect(infos, hasLength(1));

      await tester.pumpWidget(build(const ValueKey(2)));
      // The old render object reports hidden, the new one reports visible.
      expect(infos.map((i) => i.visibleFraction), [1, 0, 1]);
    });

    testWidgets('follows an ancestor Visibility with maintainSize', (
      tester,
    ) async {
      final infos = <VisibilityInfo>[];
      Widget build(bool visible) => Center(
        child: Visibility.maintain(
          visible: visible,
          child: PaintVisibility(
            onVisibilityChanged: record(infos),
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pumpWidget(build(true));
      await tester.pumpWidget(build(false));
      await tester.pumpWidget(build(true));
      expect(infos.map((i) => i.visibleFraction), [1, 0, 1]);
      expect(infos[1].size, const Size(100, 100));
    });

    testWidgets('measures the replacement of a hidden Visibility', (
      tester,
    ) async {
      final infos = <VisibilityInfo>[];
      await tester.pumpWidget(
        Center(
          child: Visibility(
            visible: false,
            replacement: PaintVisibility(
              onVisibilityChanged: record(infos),
              child: const SizedBox(width: 100, height: 100),
            ),
            child: const SizedBox(),
          ),
        ),
      );
      expect(infos.single.visibleFraction, 1);
    });

    testWidgets('notifies a hidden first value under Visibility with '
        'maintainSize and not its resizes', (tester) async {
      final infos = <VisibilityInfo>[];
      Widget build({required bool visible, required double width}) => Center(
        child: Visibility.maintain(
          visible: visible,
          child: PaintVisibility(
            onVisibilityChanged: record(infos),
            child: SizedBox(width: width, height: 100),
          ),
        ),
      );
      await tester.pumpWidget(build(visible: false, width: 100));
      expect(infos, hasLength(1));
      expect(infos.single.size, const Size(100, 100));
      expect(infos.single.visibleBounds, Rect.zero);

      await tester.pumpWidget(build(visible: false, width: 200));
      await tester.pumpWidget(build(visible: false, width: 300));
      expect(infos, hasLength(1));

      await tester.pumpWidget(build(visible: true, width: 300));
      expect(infos, hasLength(2));
      expect(infos.last.size, const Size(300, 100));
      expect(infos.last.visibleFraction, 1);

      // Visible to hidden is notified, hidden to hidden is not.
      await tester.pumpWidget(build(visible: false, width: 300));
      await tester.pumpWidget(build(visible: false, width: 50));
      expect(infos.map((i) => i.visibleFraction), [0, 1, 0]);
      expect(infos.last.size, const Size(300, 100));
    });

    testWidgets('does not notify resizes while the route is covered', (
      tester,
    ) async {
      final infos = <VisibilityInfo>[];
      Widget build(double width) => TickerMode(
        enabled: false,
        child: Center(
          child: PaintVisibility(
            onVisibilityChanged: record(infos),
            child: SizedBox(width: width, height: 100),
          ),
        ),
      );
      await tester.pumpWidget(build(100));
      await tester.pumpWidget(build(200));
      await tester.pumpWidget(build(300));
      expect(infos, hasLength(1));
      expect(infos.single.visibleFraction, 0);
    });

    testWidgets('does not notify resizes while scrolled out of view', (
      tester,
    ) async {
      final infos = <VisibilityInfo>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget build(double height) => wrap(
        // Keeps the scrolled-out item laid out so that it can resize.
        SingleChildScrollView(
          controller: controller,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PaintVisibility(
                onVisibilityChanged: record(infos),
                child: SizedBox(height: height),
              ),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      );
      await tester.pumpWidget(build(100));
      controller.jumpTo(1000);
      await tester.pump();
      expect(infos.map((i) => i.visibleFraction), [1, 0]);

      await tester.pumpWidget(build(150));
      await tester.pumpWidget(build(200));
      expect(infos, hasLength(2));

      controller.jumpTo(0);
      await tester.pump();
      expect(infos, hasLength(3));
      expect(infos.last.size, const Size(800, 200));
      expect(infos.last.visibleFraction, 1);
    });

    testWidgets('treats non-empty bounds below 1% as visible', (tester) async {
      final infos = <VisibilityInfo>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        wrap(
          ListView(
            controller: controller,
            children: [
              PaintVisibility(
                onVisibilityChanged: record(infos),
                child: const SizedBox(height: 1000),
              ),
              const SizedBox(height: 3000),
            ],
          ),
        ),
      );
      // 5 of 1000 pixels are visible: the fraction snaps to 0, but the
      // bounds are not empty.
      controller.jumpTo(995);
      await tester.pump();
      expect(infos, hasLength(2));
      expect(infos.last.visibleFraction, 0);
      expect(infos.last.visibleBounds.isEmpty, isFalse);

      // Removing it notifies a hidden value, because the last value was
      // visible.
      await tester.pumpWidget(const SizedBox());
      expect(infos, hasLength(3));
      expect(infos.last.visibleBounds, Rect.zero);
    });

    testWidgets('moving with a GlobalKey within a frame does not notify', (
      tester,
    ) async {
      final infos = <VisibilityInfo>[];
      final key = GlobalKey();
      final probe = PaintVisibility(
        key: key,
        onVisibilityChanged: record(infos),
        child: const SizedBox(width: 100, height: 100),
      );
      await tester.pumpWidget(Center(child: probe));
      await tester.pumpWidget(
        Center(
          child: Padding(padding: EdgeInsets.zero, child: probe),
        ),
      );
      expect(infos, hasLength(1));
    });

    testWidgets('uses the replaced callback from the next flush', (
      tester,
    ) async {
      final first = <VisibilityInfo>[];
      final second = <VisibilityInfo>[];
      Widget build(VisibilityChangedCallback callback, double width) => Center(
        child: PaintVisibility(
          onVisibilityChanged: callback,
          child: SizedBox(width: width, height: 100),
        ),
      );
      await tester.pumpWidget(build(record(first), 100));
      await tester.pumpWidget(build(record(second), 200));
      expect(first, hasLength(1));
      expect(second, hasLength(1));
      expect(second.single.size, const Size(200, 100));
    });

    testWidgets('keeps a value per render object without keys', (tester) async {
      final a = <VisibilityInfo>[];
      final b = <VisibilityInfo>[];
      await tester.pumpWidget(
        Column(
          children: [
            PaintVisibility(
              onVisibilityChanged: record(a),
              child: const SizedBox(width: 10, height: 10),
            ),
            PaintVisibility(
              onVisibilityChanged: record(b),
              child: const SizedBox(width: 20, height: 20),
            ),
          ],
        ),
      );
      expect(a.single.size, const Size(10, 10));
      expect(b.single.size, const Size(20, 20));
    });

    testWidgets('does not request frames while idle', (tester) async {
      await tester.pumpWidget(
        Center(
          child: PaintVisibility(
            onVisibilityChanged: (_, _) {},
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('setState in the callback lands on the next frame', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const _SetStateProbe()));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(find.text('1.0'), findsOneWidget);
    });

    testWidgets('reports errors thrown by callbacks and keeps going', (
      tester,
    ) async {
      final infos = <VisibilityInfo>[];
      final throwerInfos = <VisibilityInfo>[];
      Widget build(double throwerWidth) => Column(
        children: [
          PaintVisibility(
            onVisibilityChanged: (info, _) {
              throwerInfos.add(info);
              if (throwerInfos.length == 1) {
                throw StateError('boom');
              }
            },
            child: SizedBox(width: throwerWidth, height: 10),
          ),
          PaintVisibility(
            onVisibilityChanged: record(infos),
            child: const SizedBox(width: 10, height: 10),
          ),
        ],
      );
      await tester.pumpWidget(build(10));
      expect(tester.takeException(), isStateError);
      // The other observer of the same flush is notified.
      expect(infos, hasLength(1));

      // The observer whose callback threw is notified of later changes.
      await tester.pumpWidget(build(20));
      expect(throwerInfos.map((info) => info.size.width), [10, 20]);
    });
  });

  group('PaintVisibility under OverlayPortal', () {
    testWidgets('an overlay child is not hidden by a Visibility it is not '
        'painted under', (tester) async {
      final overlayInfos = <VisibilityInfo>[];
      final childInfos = <VisibilityInfo>[];
      final inner = ValueNotifier<bool>(false);
      addTearDown(inner.dispose);
      await tester.pumpWidget(
        _OverlayPortalTree(
          outerVisible: true,
          innerVisible: inner,
          overlayChild: PaintVisibility(
            onVisibilityChanged: record(overlayInfos),
            child: const SizedBox(width: 50, height: 50),
          ),
          child: PaintVisibility(
            onVisibilityChanged: record(childInfos),
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      // The overlay child is painted by the Overlay.
      expect(overlayInfos.map((i) => i.visibleFraction), [1]);
      // A normal child is painted under the hidden Visibility.
      expect(childInfos.map((i) => i.visibleFraction), [0]);

      inner.value = true;
      await tester.pump();
      expect(overlayInfos.map((i) => i.visibleFraction), [1]);
      expect(childInfos.map((i) => i.visibleFraction), [0, 1]);

      inner.value = false;
      await tester.pump();
      expect(overlayInfos.map((i) => i.visibleFraction), [1]);
      expect(childInfos.map((i) => i.visibleFraction), [0, 1, 0]);
    });

    testWidgets('an overlay child follows a Visibility above the Overlay', (
      tester,
    ) async {
      final overlayInfos = <VisibilityInfo>[];
      final inner = ValueNotifier<bool>(false);
      addTearDown(inner.dispose);
      Widget build(bool outerVisible) => _OverlayPortalTree(
        outerVisible: outerVisible,
        innerVisible: inner,
        overlayChild: PaintVisibility(
          onVisibilityChanged: record(overlayInfos),
          child: const SizedBox(width: 50, height: 50),
        ),
      );
      await tester.pumpWidget(build(true));
      expect(overlayInfos.map((i) => i.visibleFraction), [1]);

      // The inner hidden Visibility comes first in the element tree, but the
      // outer one still hides the overlay child.
      await tester.pumpWidget(build(false));
      expect(overlayInfos.map((i) => i.visibleFraction), [1, 0]);

      await tester.pumpWidget(build(true));
      expect(overlayInfos.map((i) => i.visibleFraction), [1, 0, 1]);
    });

    testWidgets('an Overlay in a hidden IndexedStack child hides both '
        'children', (tester) async {
      final overlayInfos = <VisibilityInfo>[];
      final childInfos = <VisibilityInfo>[];
      final controller = OverlayPortalController()..show();
      Widget build(int index) => wrap(
        IndexedStack(
          index: index,
          children: [
            const SizedBox(),
            Overlay.wrap(
              child: Center(
                child: OverlayPortal(
                  controller: controller,
                  overlayChildBuilder: (_) => Center(
                    child: PaintVisibility(
                      onVisibilityChanged: record(overlayInfos),
                      child: const SizedBox(width: 50, height: 50),
                    ),
                  ),
                  child: PaintVisibility(
                    onVisibilityChanged: record(childInfos),
                    child: const SizedBox(width: 100, height: 100),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpWidget(build(0));
      expect(overlayInfos.map((i) => i.visibleFraction), [0]);
      expect(childInfos.map((i) => i.visibleFraction), [0]);

      await tester.pumpWidget(build(1));
      expect(overlayInfos.map((i) => i.visibleFraction), [0, 1]);
      expect(childInfos.map((i) => i.visibleFraction), [0, 1]);
    });
  });

  group('SliverPaintVisibility', () {
    testWidgets('is hidden when a Clip.none viewport does not paint it', (
      tester,
    ) async {
      final infos = <VisibilityInfo>[];
      final boxes = <VisibilityInfo>[];
      await tester.pumpWidget(
        wrap(
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 300,
              child: CustomScrollView(
                clipBehavior: Clip.none,
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 300)),
                  // Laid out after the viewport is full, so its geometry is
                  // not visible and the viewport does not paint it, although
                  // nothing clips it.
                  SliverPaintVisibility(
                    onVisibilityChanged: record(infos),
                    sliver: SliverToBoxAdapter(
                      child: PaintVisibility(
                        onVisibilityChanged: record(boxes),
                        child: const SizedBox(height: 100),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(infos.single.visibleFraction, 0);
      expect(boxes.single.visibleFraction, 0);
    });

    testWidgets('children of a Clip.none lazy list in the cache extent are '
        'hidden', (tester) async {
      final fractions = <int, double>{};
      await tester.pumpWidget(
        wrap(
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 250,
              child: ListView.builder(
                clipBehavior: Clip.none,
                itemCount: 10,
                itemBuilder: (context, index) => PaintVisibility(
                  onVisibilityChanged: (info, _) =>
                      fractions[index] = info.visibleFraction,
                  child: const SizedBox(height: 100),
                ),
              ),
            ),
          ),
        ),
      );
      // Items 0 and 1 are painted, item 2 is half inside the viewport and,
      // with nothing clipping it, painted whole. The rest are laid out in
      // the cache extent and not painted by the list.
      expect(fractions[0], 1);
      expect(fractions[1], 1);
      expect(fractions[2], 1);
      expect(fractions.keys, containsAll([3, 4]));
      for (final index in fractions.keys.where((i) => i >= 3)) {
        expect(fractions[index], 0, reason: 'item $index');
      }
    });

    for (final reverse in [false, true]) {
      testWidgets('measures a pinned header where it is painted '
          '(reverse: $reverse)', (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final infos = <VisibilityInfo>[];
        await tester.pumpWidget(
          wrap(
            CustomScrollView(
              controller: controller,
              reverse: reverse,
              slivers: [
                SliverPaintVisibility(
                  onVisibilityChanged: record(infos),
                  sliver: const SliverPersistentHeader(
                    pinned: true,
                    delegate: FixedHeader(minExtent: 50, maxExtent: 200),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 2000)),
              ],
            ),
          ),
        );
        expect(infos.last.visibleFraction, 1);

        // Collapsed to its minimum extent of 50 out of 200.
        controller.jumpTo(500);
        await tester.pump();
        expect(infos.last.size, const Size(800, 200));
        expect(infos.last.visibleFraction, closeTo(0.25, 1e-9));
      });
    }
    testWidgets('does not notify resizes while hidden', (tester) async {
      final infos = <VisibilityInfo>[];
      Widget build(double height) => wrap(
        Visibility.maintain(
          visible: false,
          child: CustomScrollView(
            slivers: [
              SliverPaintVisibility(
                onVisibilityChanged: record(infos),
                sliver: SliverToBoxAdapter(child: SizedBox(height: height)),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(build(100));
      await tester.pumpWidget(build(200));
      expect(infos, hasLength(1));
      expect(infos.single.size, const Size(800, 100));
      expect(infos.single.visibleFraction, 0);
    });

    testWidgets('reports the visible fraction of a sliver', (tester) async {
      final infos = <VisibilityInfo>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        wrap(
          CustomScrollView(
            controller: controller,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 500)),
              SliverPaintVisibility(
                onVisibilityChanged: record(infos),
                sliver: const SliverToBoxAdapter(child: SizedBox(height: 200)),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 1000)),
            ],
          ),
        ),
      );
      expect(infos.last.size, const Size(800, 200));
      expect(infos.last.visibleFraction, 0.5);

      controller.jumpTo(100);
      await tester.pump();
      expect(infos.last.visibleFraction, 1);

      controller.jumpTo(1000);
      await tester.pump();
      expect(infos.last.visibleFraction, 0);
    });

    testWidgets('notifies a hidden value on detach', (tester) async {
      final infos = <VisibilityInfo>[];
      await tester.pumpWidget(
        wrap(
          CustomScrollView(
            slivers: [
              SliverPaintVisibility(
                onVisibilityChanged: record(infos),
                sliver: const SliverToBoxAdapter(child: SizedBox(height: 200)),
              ),
            ],
          ),
        ),
      );
      expect(infos.single.visibleFraction, 1);
      await tester.pumpWidget(const SizedBox());
      expect(infos.last.visibleFraction, 0);
      expect(infos.last.size, const Size(800, 200));
    });
  });
}

/// An [Overlay] under `Visibility.maintain(visible: outerVisible)` whose
/// entry shows an [OverlayPortal] under
/// `Visibility.maintain(visible: innerVisible.value)`.
///
/// [overlayChild] is painted by the [Overlay], [child] under the inner
/// [Visibility].
class _OverlayPortalTree extends StatefulWidget {
  const _OverlayPortalTree({
    required this.outerVisible,
    required this.innerVisible,
    required this.overlayChild,
    this.child,
  });

  final bool outerVisible;
  final ValueListenable<bool> innerVisible;
  final Widget overlayChild;
  final Widget? child;

  @override
  State<_OverlayPortalTree> createState() => _OverlayPortalTreeState();
}

class _OverlayPortalTreeState extends State<_OverlayPortalTree> {
  final _controller = OverlayPortalController()..show();
  late final _entry = OverlayEntry(
    builder: (context) => Center(
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.innerVisible,
        builder: (context, visible, _) => Visibility.maintain(
          visible: visible,
          child: OverlayPortal(
            controller: _controller,
            overlayChildBuilder: (_) =>
                Align(alignment: Alignment.topLeft, child: widget.overlayChild),
            child: widget.child ?? const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return wrap(
      Visibility.maintain(
        visible: widget.outerVisible,
        child: Overlay(initialEntries: [_entry]),
      ),
    );
  }
}

class _SetStateProbe extends StatefulWidget {
  const _SetStateProbe();

  @override
  State<_SetStateProbe> createState() => _SetStateProbeState();
}

class _SetStateProbeState extends State<_SetStateProbe> {
  double? _fraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PaintVisibility(
          onVisibilityChanged: (info, _) {
            if (mounted) {
              setState(() => _fraction = info.visibleFraction);
            }
          },
          child: const SizedBox(width: 10, height: 10),
        ),
        Text(_fraction?.toStringAsFixed(1) ?? '-'),
      ],
    );
  }
}
