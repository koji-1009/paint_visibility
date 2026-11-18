// Tests for the clips and the skipped children that resolvePaintGeometry
// derives from public state because the framework does not report them
// through describeApproximatePaintClip or paintsChild.
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paint_visibility/src/internal/paint_geometry.dart';

import '../helpers.dart';

void main() {
  testWidgets('the flush cache gives the same results as no cache', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Transform.scale(
          scale: 0.9,
          child: ListView(
            children: [
              for (var i = 0; i < 30; i++)
                Opacity(
                  opacity: i.isEven ? 1 : 0,
                  child: SizedBox(
                    height: 50,
                    child: Text('$i', key: ValueKey(i)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    final targets = [
      for (final element in find.byType(Text, skipOffstage: false).evaluate())
        element.renderObject!,
    ];
    final expected = [
      for (final target in targets) resolvePaintGeometry(target),
    ];
    expect(expected.whereType<Object>(), isNotEmpty);
    expect(expected.where((geometry) => geometry == null), isNotEmpty);

    final actual = <({Matrix4 transform, Rect clip})?>[];
    PaintGeometryCache.begin();
    try {
      // Twice, so the second pass reads cached ancestors.
      for (var pass = 0; pass < 2; pass++) {
        actual.clear();
        for (final target in targets) {
          actual.add(resolvePaintGeometry(target));
        }
      }
    } finally {
      PaintGeometryCache.end();
    }
    for (var i = 0; i < targets.length; i++) {
      expect(actual[i]?.clip, expected[i]?.clip, reason: '$i');
      expect(actual[i]?.transform, expected[i]?.transform, reason: '$i');
    }
  });

  // The clips of Wrap, FittedBox, AnimatedSize and RenderParagraph are
  // recomputed from copies of their private layout code and paint
  // conditions. These compare the result with the clip each render object
  // actually paints, so that a change of the framework fails here.
  group('recomputed clips match the painted clips', () {
    const screen = Rect.fromLTWH(0, 0, 800, 600);

    /// Whether the package clips [child] to the bounds of [parent], checked
    /// against the clip [parent] paints. Returns whether it clips.
    bool expectAgreement(RenderBox parent, RenderObject child, String reason) {
      final clips = resolvePaintGeometry(child)!.clip != screen;
      expect(
        parent,
        clips
            ? (paints..clipRect(rect: Offset.zero & parent.size))
            : isNot(paints..clipRect()),
        reason: reason,
      );
      return clips;
    }

    testWidgets('Wrap clips exactly when RenderWrap paints a clip', (
      tester,
    ) async {
      const childSets = <List<Size>>[
        [Size(40, 30), Size(50, 30), Size(30, 20), Size(60, 30)],
        [Size(150, 30), Size(20, 20)],
        [Size(33.3, 17.7), Size(33.3, 17.7), Size(33.4, 17.7)],
      ];
      var cases = 0;
      var clipped = 0;
      for (final direction in Axis.values) {
        for (final spacing in const [0.0, 8.0, -8.0]) {
          for (final runSpacing in const [0.0, 8.0, -8.0]) {
            for (final children in childSets) {
              for (final tight in const [true, false]) {
                final wrapWidget = Wrap(
                  direction: direction,
                  spacing: spacing,
                  runSpacing: runSpacing,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (final size in children) SizedBox.fromSize(size: size),
                  ],
                );
                await tester.pumpWidget(
                  wrap(
                    Center(
                      child: tight
                          ? SizedBox(width: 100, height: 100, child: wrapWidget)
                          : ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 100,
                                maxHeight: 100,
                              ),
                              child: wrapWidget,
                            ),
                    ),
                  ),
                );
                final renderWrap = tester.renderObject<RenderWrap>(
                  find.byType(Wrap),
                );
                final packageClips = expectAgreement(
                  renderWrap,
                  renderWrap.firstChild!,
                  '$direction spacing=$spacing runSpacing=$runSpacing '
                  'children=$children tight=$tight',
                );
                cases++;
                if (packageClips) {
                  clipped++;
                }
              }
            }
          }
        }
      }
      expect(cases, 108);
      // Both outcomes are covered.
      expect(clipped, inExclusiveRange(0, cases));
    });

    testWidgets('FittedBox', (tester) async {
      final outcomes = <bool>{};
      for (final fit in BoxFit.values) {
        for (final childSize in const [Size(50, 50), Size(300, 50)]) {
          await tester.pumpWidget(
            wrap(
              Center(
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: FittedBox(
                    fit: fit,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox.fromSize(size: childSize),
                  ),
                ),
              ),
            ),
          );
          final box = tester.renderObject<RenderFittedBox>(
            find.byType(FittedBox),
          );
          outcomes.add(expectAgreement(box, box.child!, '$fit $childSize'));
        }
      }
      expect(outcomes, {true, false});
    });

    testWidgets('AnimatedSize', (tester) async {
      final outcomes = <bool>{};
      Widget build(double height) => wrap(
        Center(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 100),
            clipBehavior: Clip.hardEdge,
            child: SizedBox(width: 100, height: height),
          ),
        ),
      );
      await tester.pumpWidget(build(100));
      for (final height in const [300.0, 50.0]) {
        await tester.pumpWidget(build(height));
        for (var i = 0; i < 6; i++) {
          final box = tester.renderObject<RenderAnimatedSize>(
            find.byType(AnimatedSize),
          );
          outcomes.add(
            expectAgreement(box, box.child!, 'height $height frame $i'),
          );
          await tester.pump(const Duration(milliseconds: 25));
        }
      }
      expect(outcomes, {true, false});
    });

    testWidgets('RenderParagraph', (tester) async {
      final outcomes = <bool>{};
      for (final overflow in TextOverflow.values) {
        for (final width in const [40.0, 400.0]) {
          await tester.pumpWidget(
            wrap(
              Center(
                child: SizedBox(
                  width: width,
                  child: Text.rich(
                    const TextSpan(
                      children: [
                        TextSpan(text: 'abc '),
                        WidgetSpan(child: SizedBox(width: 30, height: 10)),
                      ],
                    ),
                    softWrap: false,
                    overflow: overflow,
                  ),
                ),
              ),
            ),
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byType(RichText),
          );
          final inline = tester.renderObject(
            find.byWidgetPredicate(
              (widget) =>
                  widget is SizedBox &&
                  widget.width == 30 &&
                  widget.height == 10,
            ),
          );
          outcomes.add(expectAgreement(paragraph, inline, '$overflow $width'));
        }
      }
      expect(outcomes, {true, false});
    });
  });

  group('overflow-conditional clips', () {
    testWidgets('Wrap without overflow does not clip a translated child', (
      tester,
    ) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        wrap(
          _at(
            const Offset(0, 0),
            Wrap(
              clipBehavior: Clip.hardEdge,
              children: [
                Transform.translate(
                  offset: const Offset(0, 100),
                  child: recorder.box(
                    'wrap',
                    const SizedBox(width: 100, height: 50),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(recorder.frame['wrap']!.visibleFraction, 1);
      expect(
        recorder.frame['wrap']!.visibleBounds,
        const Rect.fromLTWH(0, 0, 100, 50),
      );
    });

    testWidgets('overflowing Wrap clips a translated child', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        wrap(
          _at(
            const Offset(0, 0),
            size: const Size(100, 50),
            Wrap(
              clipBehavior: Clip.hardEdge,
              children: [
                Transform.translate(
                  offset: const Offset(0, 25),
                  child: recorder.box(
                    'wrap',
                    const SizedBox(width: 100, height: 100),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      // Painted at y 25..125, clipped to 0..50.
      expect(recorder.frame['wrap']!.visibleFraction, 0.25);
    });

    testWidgets('Wrap with several runs that fit is not clipped', (
      tester,
    ) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        wrap(
          _at(
            const Offset(0, 0),
            size: const Size(100, 300),
            Wrap(
              clipBehavior: Clip.hardEdge,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < 3; i++)
                  SizedBox(
                    width: 100 / 3,
                    height: 50,
                    child: i == 2
                        ? Transform.translate(
                            offset: const Offset(0, 400),
                            child: recorder.box('wrap', const SizedBox()),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ),
      );
      // 33.3 + 10 + 33.3 + 10 + 33.3 > 100, so the third box starts a second
      // run at y 60. The two runs (50 + 10 + 50) fit in 300, so the Wrap
      // does not overflow and the box translated to y 460 is not clipped.
      expect(recorder.frame['wrap']!.visibleFraction, 1);
      expect(
        recorder.frame['wrap']!.visibleBounds,
        const Rect.fromLTWH(0, 0, 100 / 3, 50),
      );
    });

    testWidgets('AnimatedSize without overflow does not clip', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        wrap(
          _at(
            const Offset(0, 0),
            AnimatedSize(
              duration: const Duration(milliseconds: 100),
              child: Transform.translate(
                offset: const Offset(0, 100),
                child: recorder.box(
                  'animatedSize',
                  const SizedBox(width: 100, height: 50),
                ),
              ),
            ),
          ),
        ),
      );
      expect(recorder.frame['animatedSize']!.visibleFraction, 1);
    });

    testWidgets('AnimatedSize clips only while it overflows', (tester) async {
      final recorder = Recorder();
      Widget build(double height) => wrap(
        _at(
          const Offset(0, 0),
          AnimatedSize(
            duration: const Duration(milliseconds: 100),
            alignment: Alignment.topLeft,
            child: Transform.translate(
              offset: const Offset(0, 30),
              child: recorder.box(
                'animatedSize',
                SizedBox(width: 100, height: height),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(build(10));
      await tester.pumpWidget(build(110));
      await tester.pump(const Duration(milliseconds: 50));
      // AnimatedSize is about 60 tall; the child is painted at y 30..140.
      expect(
        recorder.frame['animatedSize']!.visibleFraction,
        closeTo(30 / 110, tolerance),
      );
      await tester.pumpAndSettle();
      // Settled at 110 tall: no overflow, so the translated child is not
      // clipped.
      expect(recorder.frame['animatedSize']!.visibleFraction, 1);
    });

    testWidgets('FittedBox without overflow does not clip', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        wrap(
          _at(
            const Offset(0, 0),
            size: const Size(100, 100),
            FittedBox(
              fit: BoxFit.none,
              clipBehavior: Clip.hardEdge,
              child: Transform.translate(
                offset: const Offset(0, 150),
                child: recorder.box(
                  'fittedBox',
                  const SizedBox(width: 50, height: 50),
                ),
              ),
            ),
          ),
        ),
      );
      expect(recorder.frame['fittedBox']!.visibleFraction, 1);
      expect(
        recorder.frame['fittedBox']!.visibleBounds,
        const Rect.fromLTWH(0, 0, 50, 50),
      );
    });

    testWidgets('FittedBox that scales down without overflow does not clip', (
      tester,
    ) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        wrap(
          _at(
            const Offset(0, 0),
            size: const Size(100, 100),
            FittedBox(
              clipBehavior: Clip.hardEdge,
              child: Transform.translate(
                offset: const Offset(0, 200),
                child: recorder.box(
                  'fittedBox',
                  const SizedBox(width: 200, height: 200),
                ),
              ),
            ),
          ),
        ),
      );
      // BoxFit.contain scales the 200x200 child and its translation by 0.5,
      // so it is painted whole at y 100..200.
      expect(recorder.frame['fittedBox']!.visibleFraction, 1);
      expect(
        recorder.frame['fittedBox']!.visibleBounds,
        const Rect.fromLTWH(0, 0, 100, 100),
      );
    });

    testWidgets('overflowing FittedBox clips a translated child', (
      tester,
    ) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        wrap(
          _at(
            const Offset(0, 0),
            size: const Size(100, 50),
            FittedBox(
              fit: BoxFit.none,
              clipBehavior: Clip.hardEdge,
              child: Transform.translate(
                offset: const Offset(0, 50),
                child: recorder.box(
                  'fittedBox',
                  const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );
      // The 100x50 source rect is centered (y 25..75), so the child is
      // painted at y -25 + 50 = 25..125 and clipped to 0..50.
      expect(recorder.frame['fittedBox']!.visibleFraction, 0.25);
    });
  });

  group('RenderParagraph', () {
    Widget paragraph(Recorder recorder, TextOverflow overflow) {
      return wrap(
        _at(
          const Offset(0, 0),
          size: const Size(100, 10),
          Text.rich(
            TextSpan(
              text: 'aaaaaaaaa',
              children: [
                WidgetSpan(
                  child: recorder.box(
                    overflow.name,
                    const SizedBox(width: 20, height: 10),
                  ),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 10, height: 1),
            softWrap: false,
            overflow: overflow,
          ),
        ),
      );
    }

    for (final overflow in [TextOverflow.clip, TextOverflow.fade]) {
      testWidgets('clips a WidgetSpan with TextOverflow.${overflow.name}', (
        tester,
      ) async {
        final recorder = Recorder();
        await tester.pumpWidget(paragraph(recorder, overflow));
        // Nine 10 px glyphs, then the 20 px placeholder at x 90..110 in a
        // 100 px wide paragraph.
        expect(recorder.frame[overflow.name]!.visibleFraction, 0.5);
        expect(
          recorder.frame[overflow.name]!.visibleBounds,
          const Rect.fromLTWH(0, 0, 10, 10),
        );
      });
    }

    testWidgets('does not clip a WidgetSpan with TextOverflow.visible', (
      tester,
    ) async {
      final recorder = Recorder();
      await tester.pumpWidget(paragraph(recorder, TextOverflow.visible));
      expect(recorder.frame['visible']!.visibleFraction, 1);
    });

    testWidgets('does not clip a WidgetSpan when the text fits', (
      tester,
    ) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        wrap(
          _at(
            const Offset(0, 0),
            size: const Size(200, 10),
            Text.rich(
              TextSpan(
                text: 'a',
                children: [
                  WidgetSpan(
                    child: Transform.translate(
                      offset: const Offset(0, 100),
                      child: recorder.box(
                        'fits',
                        const SizedBox(width: 20, height: 10),
                      ),
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 10, height: 1),
              overflow: TextOverflow.clip,
            ),
          ),
        ),
      );
      expect(recorder.frame['fits']!.visibleFraction, 1);
    });
  });

  group('RenderTwoDimensionalViewport', () {
    testWidgets('partially visible cells are clipped to the viewport', (
      tester,
    ) async {
      final recorder = Recorder();
      final vertical = ScrollController();
      final horizontal = ScrollController();
      addTearDown(vertical.dispose);
      addTearDown(horizontal.dispose);
      await tester.pumpWidget(
        wrap(_grid(recorder, vertical: vertical, horizontal: horizontal)),
      );
      vertical.jumpTo(100);
      horizontal.jumpTo(100);
      await tester.pump();
      // The 400x400 viewport is at (100, 100); cells are 200x200.
      expect(recorder.frame[(0, 0)]!.visibleFraction, 0.25);
      expect(
        recorder.frame[(0, 0)]!.visibleBounds,
        const Rect.fromLTWH(100, 100, 100, 100),
      );
      expect(recorder.frame[(1, 1)]!.visibleFraction, 1);
      expect(recorder.frame[(2, 1)]!.visibleFraction, 0.5);
      expect(recorder.frame[(2, 2)]!.visibleFraction, 0.25);
      // Cache cells, laid out but not painted.
      expect(recorder.frame[(3, 0)]!.visibleFraction, 0);
      expect(recorder.frame[(0, 3)]!.visibleFraction, 0);
    });

    testWidgets('the viewport clips whenever it paints a cell', (tester) async {
      await tester.pumpWidget(
        wrap(
          _at(
            Offset.zero,
            size: const Size(400, 400),
            _Grid(
              verticalDetails: const ScrollableDetails.vertical(),
              horizontalDetails: const ScrollableDetails.horizontal(),
              clipBehavior: Clip.hardEdge,
              delegate: TwoDimensionalChildBuilderDelegate(
                maxXIndex: 0,
                maxYIndex: 0,
                builder: (context, vicinity) => const SizedBox(),
              ),
            ),
          ),
        ),
      );
      final viewport = tester.renderObject<RenderTwoDimensionalViewport>(
        find.byType(_GridViewport),
      );
      final cell = viewport.firstChild!;
      expect(resolvePaintGeometry(cell)!.clip, Offset.zero & viewport.size);
      expect(viewport, paints..clipRect(rect: Offset.zero & viewport.size));
    });

    testWidgets('kept-alive cells are hidden after scrolling', (tester) async {
      final recorder = Recorder();
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        wrap(_grid(recorder, vertical: vertical, keepAlive: true)),
      );
      expect(recorder.frame[(0, 0)]!.visibleFraction, 1);
      vertical.jumpTo(1200);
      await tester.pump();

      // The cell is kept alive, so it stays attached without being painted.
      expect(_cellOf(tester, recorder, (0, 0)).attached, isTrue);
      expect(recorder.frame[(0, 0)]!.visibleFraction, 0);
      expect(recorder.frame[(1, 0)]!.visibleFraction, 0);
      expect(recorder.frame[(0, 6)]!.visibleFraction, 1);

      // Scrolling back reuses the kept-alive cells.
      vertical.jumpTo(0);
      await tester.pump();
      expect(recorder.frame[(0, 0)]!.visibleFraction, 1);
      // RenderTwoDimensionalViewport keeps a kept-alive child in both its
      // active children and its keep-alive bucket, and detaching it twice
      // when the tree is torn down fails an assertion. Scrolling back above
      // moved every kept-alive cell out of the bucket.
    });

    testWidgets('cache cells are hidden with Clip.none', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(wrap(_grid(recorder, clipBehavior: Clip.none)));
      expect(recorder.frame[(0, 0)]!.visibleFraction, 1);
      expect(recorder.frame[(1, 1)]!.visibleFraction, 1);
      // Laid out at (100, 500) and (500, 100) on screen, but not painted.
      expect(recorder.frame[(0, 2)]!.visibleFraction, 0);
      expect(recorder.frame[(2, 0)]!.visibleFraction, 0);
      expect(recorder.frame[(2, 2)]!.visibleFraction, 0);
    });

    testWidgets('partially visible cells are not clipped with Clip.none', (
      tester,
    ) async {
      final recorder = Recorder();
      final vertical = ScrollController();
      addTearDown(vertical.dispose);
      await tester.pumpWidget(
        wrap(_grid(recorder, vertical: vertical, clipBehavior: Clip.none)),
      );
      vertical.jumpTo(100);
      await tester.pump();
      // Painted whole at (100, 0)..(300, 200).
      expect(recorder.frame[(0, 0)]!.visibleFraction, 1);
      expect(
        recorder.frame[(0, 0)]!.visibleBounds,
        const Rect.fromLTWH(0, 0, 200, 200),
      );
      expect(recorder.frame[(0, 2)]!.visibleFraction, 1);
      expect(recorder.frame[(0, 3)]!.visibleFraction, 0);
    });
  });

  testWidgets('hidden IndexedStack child is not painted', (tester) async {
    const hidden = ValueKey('hidden');
    const shown = ValueKey('shown');
    await tester.pumpWidget(
      wrap(
        const Align(
          alignment: Alignment.topLeft,
          child: IndexedStack(
            index: 1,
            children: [
              SizedBox(key: hidden, width: 10, height: 10),
              SizedBox(key: shown, width: 10, height: 10),
            ],
          ),
        ),
      ),
    );
    // The SizedBox render objects are the direct children of
    // RenderIndexedStack, and no PaintVisibility or Visibility.of is
    // involved, so only the RenderIndexedStack branch of resolvePaintGeometry
    // can hide the first one.
    final hiddenBox = tester.renderObject<RenderBox>(
      find.byKey(hidden, skipOffstage: false),
    );
    expect(hiddenBox.parent, isA<RenderIndexedStack>());
    expect(resolvePaintGeometry(hiddenBox), isNull);
    final shownBox = tester.renderObject<RenderBox>(find.byKey(shown));
    expect(resolvePaintGeometry(shownBox), isNotNull);
  });
}

Widget _at(Offset position, Widget child, {Size? size}) {
  return Stack(
    children: [
      Positioned(
        left: position.dx,
        top: position.dy,
        width: size?.width,
        height: size?.height,
        child: child,
      ),
    ],
  );
}

const double _cell = 200;
const int _gridCount = 10;

/// A 400x400 [_Grid] of 200x200 cells at (100, 100). With [keepAlive], the
/// cells of the first row are kept alive.
Widget _grid(
  Recorder recorder, {
  ScrollController? vertical,
  ScrollController? horizontal,
  bool keepAlive = false,
  Clip clipBehavior = Clip.hardEdge,
}) {
  return _at(
    const Offset(100, 100),
    size: const Size(400, 400),
    _Grid(
      verticalDetails: ScrollableDetails.vertical(controller: vertical),
      horizontalDetails: ScrollableDetails.horizontal(controller: horizontal),
      clipBehavior: clipBehavior,
      delegate: TwoDimensionalChildBuilderDelegate(
        maxXIndex: _gridCount - 1,
        maxYIndex: _gridCount - 1,
        builder: (context, vicinity) {
          final probe = recorder.box((
            vicinity.xIndex,
            vicinity.yIndex,
          ), const SizedBox.expand());
          return keepAlive && vicinity.yIndex == 0
              ? KeptAlive(child: probe)
              : probe;
        },
      ),
    ),
  );
}

/// The child of the viewport that contains the probe [id].
RenderObject _cellOf(WidgetTester tester, Recorder recorder, Object id) {
  RenderObject cell = tester.renderObject(
    find.byKey(recorder.key(id), skipOffstage: false),
  );
  while (cell.parent is! RenderTwoDimensionalViewport) {
    cell = cell.parent!;
  }
  return cell;
}

/// A minimal [TwoDimensionalScrollView] that lays out a grid of fixed-size
/// cells, plus one cell of cache extent on each side.
class _Grid extends TwoDimensionalScrollView {
  const _Grid({
    required super.delegate,
    super.verticalDetails,
    super.horizontalDetails,
    super.clipBehavior,
  });

  @override
  Widget buildViewport(
    BuildContext context,
    ViewportOffset verticalOffset,
    ViewportOffset horizontalOffset,
  ) {
    return _GridViewport(
      verticalOffset: verticalOffset,
      verticalAxisDirection: verticalDetails.direction,
      horizontalOffset: horizontalOffset,
      horizontalAxisDirection: horizontalDetails.direction,
      delegate: delegate,
      mainAxis: mainAxis,
      clipBehavior: clipBehavior,
    );
  }
}

class _GridViewport extends TwoDimensionalViewport {
  const _GridViewport({
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.delegate,
    required super.mainAxis,
    super.clipBehavior,
  });

  @override
  RenderTwoDimensionalViewport createRenderObject(BuildContext context) {
    return _RenderGridViewport(
      horizontalOffset: horizontalOffset,
      horizontalAxisDirection: horizontalAxisDirection,
      verticalOffset: verticalOffset,
      verticalAxisDirection: verticalAxisDirection,
      mainAxis: mainAxis,
      delegate: delegate,
      childManager: context as TwoDimensionalChildManager,
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTwoDimensionalViewport renderObject,
  ) {
    renderObject
      ..horizontalOffset = horizontalOffset
      ..horizontalAxisDirection = horizontalAxisDirection
      ..verticalOffset = verticalOffset
      ..verticalAxisDirection = verticalAxisDirection
      ..mainAxis = mainAxis
      ..delegate = delegate
      ..clipBehavior = clipBehavior;
  }
}

class _RenderGridViewport extends RenderTwoDimensionalViewport {
  _RenderGridViewport({
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.delegate,
    required super.mainAxis,
    required super.childManager,
    super.clipBehavior,
  });

  @override
  void layoutChildSequence() {
    final builder = delegate as TwoDimensionalChildBuilderDelegate;
    final maxX = builder.maxXIndex!;
    final maxY = builder.maxYIndex!;
    final dx = horizontalOffset.pixels;
    final dy = verticalOffset.pixels;
    final viewport = viewportDimension;
    final firstX = math.max(0, (dx / _cell).floor() - 1);
    final lastX = math.min(maxX, ((dx + viewport.width) / _cell).ceil());
    final firstY = math.max(0, (dy / _cell).floor() - 1);
    final lastY = math.min(maxY, ((dy + viewport.height) / _cell).ceil());
    for (var x = firstX; x <= lastX; x++) {
      for (var y = firstY; y <= lastY; y++) {
        final vicinity = ChildVicinity(xIndex: x, yIndex: y);
        final child = buildOrObtainChildFor(vicinity)!;
        child.layout(
          BoxConstraints.tight(const Size.square(_cell)),
          parentUsesSize: true,
        );
        parentDataOf(child).layoutOffset = Offset(
          x * _cell - dx,
          y * _cell - dy,
        );
      }
    }
    verticalOffset.applyContentDimensions(
      0,
      math.max(0, (maxY + 1) * _cell - viewport.height),
    );
    horizontalOffset.applyContentDimensions(
      0,
      math.max(0, (maxX + 1) * _cell - viewport.width),
    );
  }
}
