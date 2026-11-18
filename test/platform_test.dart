import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paint_visibility/paint_visibility.dart';

import 'helpers.dart';

void main() {
  testWidgets('visibleFraction changes continuously during an iOS swipe back', (
    tester,
  ) async {
    final infos = <VisibilityInfo>[];
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            child: const Text('push'),
            onPressed: () => Navigator.of(context).push(
              CupertinoPageRoute<void>(
                builder: (context) => PaintVisibility(
                  fractionStep: 0.01,
                  onVisibilityChanged: record(infos),
                  child: const ColoredBox(color: Color(0xFF000000)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(infos.last.visibleFraction, 1);
    infos.clear();

    final gesture = await tester.startGesture(const Offset(5, 300));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
    }
    final fractions = infos.map((i) => i.visibleFraction).toList();
    final partial = fractions.where((f) => f > 0 && f < 1).toList();
    expect(partial.length, greaterThanOrEqualTo(5));
    for (var i = 1; i < fractions.length; i++) {
      expect(fractions[i], lessThanOrEqualTo(fractions[i - 1]));
    }
    // 400 logical pixels of 800 have been dragged away.
    expect(fractions.last, closeTo(0.5, 0.02));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('each view is clipped by its own RenderView', (tester) async {
    final main = <VisibilityInfo>[];
    final second = <VisibilityInfo>[];
    final secondView = _SecondView(tester, const Size(400, 300));

    await tester.pumpWidget(
      wrapWithView: false,
      ViewCollection(
        views: [
          View(
            view: tester.view,
            child: _positioned(top: 550, onChanged: record(main)),
          ),
          View(
            view: secondView,
            child: _positioned(top: 250, onChanged: record(second)),
          ),
        ],
      ),
    );
    // Both boxes are 100 tall and stick out of the bottom of their view by 50.
    expect(main.last.visibleFraction, 0.5);
    expect(second.last.visibleFraction, 0.5);
  });
}

Widget _positioned({
  required double top,
  required VisibilityChangedCallback onChanged,
}) {
  return wrap(
    Stack(
      children: [
        Positioned(
          top: top,
          left: 0,
          child: PaintVisibility(
            onVisibilityChanged: onChanged,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ],
    ),
  );
}

/// A second view that shares everything with the test view except its id
/// and size.
class _SecondView extends TestFlutterView {
  _SecondView(WidgetTester tester, this._logicalSize)
    : super(
        view: tester.view,
        platformDispatcher: tester.platformDispatcher,
        display: tester.view.display,
      );

  final Size _logicalSize;

  @override
  int get viewId => super.viewId + 1;

  @override
  Size get physicalSize => _logicalSize * devicePixelRatio;

  @override
  ui.ViewConstraints get physicalConstraints =>
      ui.ViewConstraints.tight(physicalSize);

  @override
  void render(ui.Scene scene, {Size? size}) {}
}
