import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Signature of the callback invoked when the visibility of a
/// `PaintVisibility` or `SliverPaintVisibility` changes.
///
/// [info] is the new visibility. [reasons] tells why it was notified,
/// compared with the value notified before it; several reasons can apply at
/// once, for example [VisibilityChangeReason.resized] together with
/// [VisibilityChangeReason.stepCrossed].
typedef VisibilityChangedCallback = void Function(
  VisibilityInfo info,
  Set<VisibilityChangeReason> reasons,
);

/// Why a visibility was notified; see [VisibilityChangedCallback].
enum VisibilityChangeReason {
  /// The first value after the render object was created.
  initial,

  /// The widget became visible: its visible bounds are no longer empty.
  shown,

  /// The widget became hidden: its visible bounds became empty, including
  /// when it was removed from the tree.
  hidden,

  /// The visible fraction moved to another interval between two multiples of
  /// the `fractionStep` while the widget stayed visible with the same size.
  stepCrossed,

  /// The widget became fully visible.
  fullyVisible,

  /// The size of the widget, measured in global coordinates, changed by more
  /// than floating point error.
  ///
  /// For a lazy sliver list, whose extent is estimated from the children
  /// laid out so far, this happens whenever the estimate changes. Under a
  /// scaling transform such as `ScaleTransition`, it happens on every frame
  /// of the animation.
  resized,
}

/// The visibility of a render object, measured in global logical pixels.
///
/// The definition and formulas match `VisibilityInfo` of
/// `package:visibility_detector`.
@immutable
class VisibilityInfo {
  /// Creates a [VisibilityInfo].
  ///
  /// When [size] or [visibleBounds] are omitted, they default to [Size.zero]
  /// and [Rect.zero], which means completely hidden.
  const VisibilityInfo({this.size = Size.zero, this.visibleBounds = Rect.zero});

  /// The size of the axis-aligned bounding box of the widget in global
  /// coordinates.
  ///
  /// Under a scaling transform such as `Transform.scale`, this is the size
  /// after scaling.
  final Size size;

  /// The visible portion of the widget, relative to the top-left corner of
  /// the bounding box described by [size].
  final Rect visibleBounds;

  /// The fraction of the widget's area that is visible, in the range \[0, 1\].
  ///
  /// Values within a tolerance of 0.01 of 0 or 1 snap to 0 or 1.
  double get visibleFraction {
    final visibleArea = _area(visibleBounds.size);
    final maxVisibleArea = _area(size);
    if (_floatNear(maxVisibleArea, 0)) {
      return 0;
    }
    var fraction = visibleArea / maxVisibleArea;
    if (_floatNear(fraction, 0)) {
      fraction = 0;
    } else if (_floatNear(fraction, 1)) {
      fraction = 1;
    }
    assert(fraction >= 0 && fraction <= 1);
    return fraction;
  }

  double _area(Size size) {
    assert(size.width >= 0 && size.height >= 0);
    return size.width * size.height;
  }

  bool _floatNear(double f1, double f2) {
    const double kDefaultTolerance = 0.01;
    final absDiff = (f1 - f2).abs();
    return absDiff <= kDefaultTolerance ||
        (absDiff / math.max(f1.abs(), f2.abs()) <= kDefaultTolerance);
  }

  @override
  bool operator ==(Object other) {
    return other is VisibilityInfo &&
        other.size == size &&
        other.visibleBounds == visibleBounds;
  }

  @override
  int get hashCode => Object.hash(size, visibleBounds);

  @override
  String toString() {
    return 'VisibilityInfo(size: $size, visibleBounds: $visibleBounds, '
        'visibleFraction: $visibleFraction)';
  }
}
