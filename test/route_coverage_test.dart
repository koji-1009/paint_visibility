import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paint_visibility/paint_visibility.dart';

import 'helpers.dart';

void main() {
  final navKey = GlobalKey<NavigatorState>();

  Future<void> pumpApp(WidgetTester tester, Widget home) {
    return tester.pumpWidget(CupertinoApp(navigatorKey: navKey, home: home));
  }

  const blank = ColoredBox(color: Color(0xFFFFFFFF));

  void push(Route<void> route) => navKey.currentState!.push(route);

  void pushPage() => push(CupertinoPageRoute<void>(builder: (_) => blank));

  void showDialog() {
    showCupertinoDialog<void>(
      context: navKey.currentContext!,
      builder: (_) => const Center(child: Text('dialog')),
    );
  }

  Widget probe(
    List<double> fractions, {
    RouteCoverage coverage = RouteCoverage.page,
  }) {
    return PaintVisibility(
      routeCoverage: coverage,
      onVisibilityChanged: (i, _) => fractions.add(i.visibleFraction),
      child: const SizedBox.expand(),
    );
  }

  group('page', () {
    testWidgets('hidden once the push transition completes', (tester) async {
      final fractions = <double>[];
      await pumpApp(tester, probe(fractions));
      expect(fractions, [1]);

      pushPage();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Still painted during the transition, so measured geometrically.
      expect(fractions.last, inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(fractions.last, 0);
    });

    testWidgets('visible again from the start of a pop', (tester) async {
      final fractions = <double>[];
      await pumpApp(tester, probe(fractions));
      pushPage();
      await tester.pumpAndSettle();
      fractions.clear();

      navKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fractions, isNotEmpty);
      expect(fractions.first, greaterThan(0));

      await tester.pumpAndSettle();
      expect(fractions.last, 1);
    });

    testWidgets('painted again during an iOS back swipe', (tester) async {
      final fractions = <double>[];
      await pumpApp(tester, probe(fractions));
      pushPage();
      await tester.pumpAndSettle();
      fractions.clear();

      final gesture = await tester.startGesture(const Offset(5, 300));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump();
      }
      expect(fractions, isNotEmpty);
      expect(fractions.last, greaterThan(0));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(fractions.last, 1);
    });

    testWidgets('hidden by any opaque route', (tester) async {
      final routes = <String, Route<void> Function()>{
        'fullscreenDialog': () => CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => blank,
        ),
        'PageRouteBuilder': () =>
            PageRouteBuilder<void>(pageBuilder: (_, _, _) => blank),
        'opaque ModalRoute': _OpaqueRoute.new,
      };
      for (final MapEntry(:key, :value) in routes.entries) {
        final fractions = <double>[];
        await pumpApp(tester, probe(fractions));
        push(value());
        await tester.pumpAndSettle();
        expect(fractions.last, 0, reason: key);
        navKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(fractions.last, 1, reason: key);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a dialog does not hide the page', (tester) async {
      final fractions = <double>[];
      await pumpApp(tester, probe(fractions));
      showDialog();
      await tester.pumpAndSettle();
      expect(fractions, [1]);
    });

    testWidgets('a Cupertino sheet does not hide the page', (tester) async {
      final fractions = <double>[];
      await pumpApp(tester, probe(fractions));
      push(CupertinoSheetRoute<void>(scrollableBuilder: (_, _) => blank));
      await tester.pumpAndSettle();
      // The page behind the sheet is still painted, scaled down.
      expect(fractions.last, greaterThan(0));
    });

    testWidgets('a push on an outer navigator hides an inner navigator', (
      tester,
    ) async {
      final fractions = <double>[];
      await pumpApp(
        tester,
        Navigator(
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => probe(fractions),
          ),
        ),
      );
      expect(fractions, [1]);

      pushPage();
      await tester.pumpAndSettle();
      expect(fractions.last, 0);
    });
  });

  group('any', () {
    testWidgets('a dialog hides the page', (tester) async {
      final fractions = <double>[];
      await pumpApp(tester, probe(fractions, coverage: RouteCoverage.any));
      showDialog();
      await tester.pump();
      expect(fractions, [1, 0]);

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(fractions, [1, 0, 1]);
    });
  });

  group('keep', () {
    testWidgets('the last value is kept while covered', (tester) async {
      final fractions = <double>[];
      await pumpApp(tester, probe(fractions, coverage: RouteCoverage.keep));
      pushPage();
      await tester.pumpAndSettle();
      // The covered page keeps the geometry of the end of the transition,
      // which shifts it partly out of the screen; the exact amount belongs
      // to the transition.
      expect(fractions.last, inExclusiveRange(0, 1));
    });
  });

  testWidgets('the coverage can be switched at runtime', (tester) async {
    final fractions = <double>[];
    await pumpApp(tester, probe(fractions, coverage: RouteCoverage.keep));
    showDialog();
    await tester.pumpAndSettle();
    expect(fractions, [1]);

    await pumpApp(tester, probe(fractions, coverage: RouteCoverage.any));
    expect(fractions, [1, 0]);
  });

  testWidgets('SliverPaintVisibility is hidden while covered', (tester) async {
    final fractions = <double>[];
    await pumpApp(
      tester,
      CustomScrollView(
        slivers: [
          SliverPaintVisibility(
            onVisibilityChanged: (i, _) => fractions.add(i.visibleFraction),
            sliver: const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ),
        ],
      ),
    );
    pushPage();
    await tester.pumpAndSettle();
    expect(fractions.last, 0);
  });

  group('markers', () {
    Widget sliverMarker(List<bool> values, RouteCoverage coverage) {
      return CustomScrollView(
        slivers: [
          SliverRegionMarker(
            routeCoverage: coverage,
            onRegionChanged: values.add,
          ),
        ],
      );
    }

    testWidgets('SliverRegionMarker keeps its value while covered by default', (
      tester,
    ) async {
      final values = <bool>[];
      await pumpApp(
        tester,
        CustomScrollView(
          slivers: [SliverRegionMarker(onRegionChanged: values.add)],
        ),
      );
      pushPage();
      await tester.pumpAndSettle();
      expect(values, [true]);
    });

    testWidgets('SliverRegionMarker with page coverage', (tester) async {
      final values = <bool>[];
      await pumpApp(tester, sliverMarker(values, RouteCoverage.page));
      pushPage();
      await tester.pumpAndSettle();
      expect(values, [true, false]);
      expect(
        isInRegionOf(
          tester,
          find.byType(SliverRegionMarker, skipOffstage: false),
        ),
        isFalse,
      );

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(values, [true, false, true]);
    });

    testWidgets('SliverRegionMarker reports a coverage switch while covered', (
      tester,
    ) async {
      final values = <bool>[];
      await pumpApp(tester, sliverMarker(values, RouteCoverage.any));
      showDialog();
      await tester.pumpAndSettle();
      expect(values, [true, false]);

      await pumpApp(tester, sliverMarker(values, RouteCoverage.keep));
      expect(values, [true, false, true]);
    });

    testWidgets('RegionMarker with any coverage', (tester) async {
      final values = <bool>[];
      await pumpApp(
        tester,
        Center(
          child: RegionMarker(
            routeCoverage: RouteCoverage.any,
            onRegionChanged: values.add,
          ),
        ),
      );
      showDialog();
      await tester.pump();
      expect(values, [true, false]);
    });
  });
}

/// An opaque route that is not a PageRoute.
class _OpaqueRoute extends ModalRoute<void> {
  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 100);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => const ColoredBox(color: Color(0xFFFFFFFF));
}
