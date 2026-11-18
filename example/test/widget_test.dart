import 'package:flutter_test/flutter_test.dart';
import 'package:paint_visibility_example/main.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shows visible fractions', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.text('Item 0: 100%'), findsOneWidget);
  });

  testWidgets('loads the next page at the end of the list', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Infinite'));
    await tester.pumpAndSettle();
    expect(find.text('20 rows', skipOffstage: false), findsOneWidget);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -2000),
      3000,
    );
    await tester.pumpAndSettle();
    final label = tester.widget<Text>(
      find.textContaining(RegExp(r'^\d+ rows$'), skipOffstage: false),
    );
    expect(int.parse(label.data!.split(' ').first), greaterThan(20));
  });

  testWidgets('detects the end of a column', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('Marker'));
    await tester.pumpAndSettle();
    expect(find.text('Scroll to the end'), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -5000),
    );
    await tester.pumpAndSettle();
    expect(find.text('End reached'), findsOneWidget);
  });
}
