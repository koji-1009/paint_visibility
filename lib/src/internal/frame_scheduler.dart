import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'package:paint_visibility/src/internal/paint_geometry.dart';

/// A render object that is flushed on every rendered frame while it is
/// attached.
///
/// When it is detached while its last notified value was visible (or in its
/// region), it is flushed once more, so that the hidden value is notified.
mixin ScheduledObserver on RenderObject {
  /// Whether the last notified value was visible or in the region.
  bool get lastNotifiedVisible;

  /// Computes the current value and notifies listeners when it differs from
  /// the last notified value.
  ///
  /// Called from the post-frame phase. The observer may be detached.
  void flushFrame();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _FrameScheduler.instance.add(this);
  }

  @override
  void detach() {
    _FrameScheduler.instance.remove(this);
    if (lastNotifiedVisible) {
      _FrameScheduler.instance.schedule(this);
    }
    super.detach();
  }
}

/// Coalesces post-frame callbacks so that at most one is registered per
/// frame.
///
/// The scheduler holds only which observers to flush, never the notified
/// values.
final class _FrameScheduler {
  _FrameScheduler._();

  /// The singleton instance.
  static final _FrameScheduler instance = _FrameScheduler._();

  /// Observers computed on every rendered frame.
  final Set<ScheduledObserver> _targets = <ScheduledObserver>{};

  /// Observers flushed once on the next rendered frame.
  final Set<ScheduledObserver> _pending = <ScheduledObserver>{};

  bool _armed = false;

  late final FrameCallback _flushCallback = _flush;

  /// Registers [observer] to be flushed on every rendered frame, starting
  /// with the current one.
  void add(ScheduledObserver observer) {
    _targets.add(observer);
    _arm();
  }

  /// Stops flushing [observer] on every frame.
  void remove(ScheduledObserver observer) {
    _targets.remove(observer);
  }

  /// Flushes [observer] once on the next post-frame phase.
  void schedule(ScheduledObserver observer) {
    _pending.add(observer);
    _arm();
  }

  void _arm() {
    if (_armed) {
      return;
    }
    _armed = true;
    SchedulerBinding.instance.addPostFrameCallback(
      _flushCallback,
      debugLabel: 'FrameScheduler.flush',
    );
  }

  void _flush(Duration _) {
    _armed = false;
    final observers = _pending.isEmpty
        ? _targets.toList()
        : <ScheduledObserver>{..._pending, ..._targets}.toList();
    _pending.clear();
    // The observers share most of their ancestors, whose geometry is
    // resolved once for the whole flush.
    PaintGeometryCache.begin();
    try {
      for (final observer in observers) {
        try {
          observer.flushFrame();
        } catch (exception, stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: exception,
              stack: stack,
              library: 'paint_visibility',
              context: ErrorDescription('while notifying $observer'),
            ),
          );
        }
      }
    } finally {
      PaintGeometryCache.end();
    }
    // Callbacks added during the post-frame phase run on the next frame and
    // do not request one, so idle periods cost nothing.
    if (_targets.isNotEmpty) {
      _arm();
    }
  }
}
