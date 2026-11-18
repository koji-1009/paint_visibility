import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paint_visibility/paint_visibility.dart';

void main() {
  group('VisibilityInfo', () {
    test('defaults to hidden', () {
      const info = VisibilityInfo();
      expect(info.size, Size.zero);
      expect(info.visibleBounds, Rect.zero);
      expect(info.visibleFraction, 0);
    });

    test('visibleFraction snaps to 0 and 1 within 0.01', () {
      const nearlyHidden = VisibilityInfo(
        size: Size(100, 100),
        visibleBounds: Rect.fromLTWH(0, 0, 100, 0.5),
      );
      expect(nearlyHidden.visibleFraction, 0);

      const nearlyFull = VisibilityInfo(
        size: Size(100, 100),
        visibleBounds: Rect.fromLTWH(0, 0, 100, 99.5),
      );
      expect(nearlyFull.visibleFraction, 1);
    });

    test('visibleFraction is 0 for an empty size', () {
      const info = VisibilityInfo(size: Size(0, 100));
      expect(info.visibleFraction, 0);
    });

    test('equality compares size and bounds', () {
      const a = VisibilityInfo(
        size: Size(10, 10),
        visibleBounds: Rect.fromLTWH(0, 0, 10, 5),
      );
      const b = VisibilityInfo(
        size: Size(10, 10),
        visibleBounds: Rect.fromLTWH(0, 0, 10, 5),
      );
      const c = VisibilityInfo(
        size: Size(10, 10),
        visibleBounds: Rect.fromLTWH(0, 5, 10, 5),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), contains('visibleFraction: 0.5'));
    });
  });
}
