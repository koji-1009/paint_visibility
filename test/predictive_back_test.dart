import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paint_visibility/paint_visibility.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the covered page is painted again during an Android '
      'predictive back gesture', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final fractions = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: PaintVisibility(
          onVisibilityChanged: (info, _) => fractions.add(info.visibleFraction),
          child: const SizedBox.expand(),
        ),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const ColoredBox(color: Color(0xFFFFFFFF)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PaintVisibility), findsNothing);
    expect(fractions.last, 0);

    await _sendBackGesture(tester, 'startBackGesture', {
      'touchOffset': [5.0, 300.0],
      'progress': 0.0,
      'swipeEdge': 0,
    });
    await _sendBackGesture(tester, 'updateBackGestureProgress', {
      'touchOffset': [100.0, 300.0],
      'progress': 0.5,
      'swipeEdge': 0,
    });
    await tester.pump();
    expect(find.byType(PaintVisibility), findsOne);
    expect(fractions.last, greaterThan(0));

    await _sendBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(fractions.last, 1);
  });
}

Future<void> _sendBackGesture(
  WidgetTester tester,
  String method, [
  Map<String, Object?>? arguments,
]) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.backGesture.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}
