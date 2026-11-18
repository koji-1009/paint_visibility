import 'package:flutter/rendering.dart';

/// The paint transform of a node, or null when it is not painted, and the
/// accumulated clip in global coordinates.
typedef _CachedGeometry = ({Matrix4? transform, Rect clip});

/// Resolves the paint transform and the accumulated paint clip of [target],
/// both in the global logical coordinates of the [RenderView] that contains
/// it.
///
/// Returns null when an ancestor does not paint the chain leading to
/// [target] (for example `Offstage`, a hidden child of `IndexedStack`, a
/// child of a lazy list that is kept alive or only in its cache extent, or
/// `Opacity` with zero opacity).
///
/// The framework APIs [RenderObject.paintsChild],
/// [RenderObject.describeApproximatePaintClip] and
/// [RenderObject.applyPaintTransform] are used. Two framework render objects
/// skip painting without reporting it through [RenderObject.paintsChild],
/// and they are handled with the same conditions as their `paint` methods:
///
/// * [RenderTransform] paints nothing when its matrix is singular.
/// * [RenderFollowerLayer] that is unlinked and not shown when unlinked
///   paints into a layer that is not composited.
///
/// Neither the canvas nor the layer tree is consulted, so the result does
/// not depend on the renderer. A render object that skips painting a child
/// without reporting it, or clips without describing it, is not detected.
///
/// The device pixel ratio transform of the [RenderView] is not applied, so
/// the result is in logical pixels. When the root of the tree is not a
/// [RenderView], the initial clip is [Rect.largest].
///
/// While the widgets of this package are notified in the post-frame phase,
/// the results for shared ancestors are reused within that phase; outside of
/// it, the chain is resolved every time.
({Matrix4 transform, Rect clip})? resolvePaintGeometry(RenderObject target) {
  final cache = PaintGeometryCache._current;

  // Collects the chain from [target] up to the root, or up to the closest
  // ancestor whose geometry is cached.
  final chain = <RenderObject>[];
  _CachedGeometry? cached;
  RenderObject? node = target;
  while (node != null) {
    cached = cache?._entries[node];
    if (cached != null) {
      break;
    }
    chain.add(node);
    node = node.parent;
  }

  final Matrix4 transform;
  Rect clip;
  RenderObject parent;
  int next;
  if (cached != null) {
    final cachedTransform = cached.transform;
    if (cachedTransform == null) {
      cache!._storeUnpainted(chain, chain.length);
      return null;
    }
    transform = cachedTransform.clone();
    clip = cached.clip;
    parent = node!;
    next = chain.length - 1;
  } else {
    final root = chain.last;
    clip = root is RenderView ? Offset.zero & root.size : Rect.largest;
    transform = Matrix4.identity();
    cache?._store(root, transform, clip);
    parent = root;
    next = chain.length - 2;
  }

  for (var i = next; i >= 0; i--) {
    final child = chain[i];
    if (!_paintsChild(parent, child)) {
      cache?._storeUnpainted(chain, i + 1);
      return null;
    }
    final parentClip = parent.describeApproximatePaintClip(child);
    if (parentClip != null) {
      clip = clip.intersect(MatrixUtils.transformRect(transform, parentClip));
    }
    if (parent is! RenderView) {
      parent.applyPaintTransform(child, transform);
    }
    // The target itself is reused only when an observer below it is flushed
    // later, which is rare, so only its ancestors are cached.
    if (i > 0) {
      cache?._store(child, transform, clip);
    }
    parent = child;
  }
  return (transform: transform, clip: clip);
}

/// Reuses the results of [resolvePaintGeometry] and [paintsChain] for shared
/// ancestors between [begin] and [end].
///
/// Many observed render objects share most of their ancestors (the app, the
/// route, the scroll view), and the cost of [resolvePaintGeometry] grows with
/// the length of the chain. While the cache is active, the transform and the
/// clip of each visited ancestor, or the fact that it is not painted, are
/// kept, so each ancestor is resolved once.
///
/// The cache assumes that the render tree does not change while it is
/// active. The
/// post-frame phase comes after layout, paint and compositing, and the
/// changes requested by the callbacks (`setState`, `markNeedsLayout`, a new
/// scroll offset) are applied in the next frame. A callback that changes a
/// render object synchronously, such as setting the value of an animation
/// that drives a `FadeTransition`, is not reflected in the values notified
/// later in the same phase; they all describe the frame that was rendered.
/// The change is reflected in the next frame, which it schedules.
final class PaintGeometryCache {
  PaintGeometryCache._();

  static PaintGeometryCache? _current;

  final Map<RenderObject, _CachedGeometry> _entries =
      Map<RenderObject, _CachedGeometry>.identity();

  /// Activates a new cache. Call [end] when the render tree may change
  /// again, also when an error is thrown.
  static void begin() {
    assert(_current == null, 'PaintGeometryCache.begin is not reentrant.');
    _current = PaintGeometryCache._();
  }

  /// Discards the active cache.
  static void end() {
    _current = null;
  }

  /// The ancestors that [paintsChain] has found to be painted up to the
  /// root.
  final Set<RenderObject> _paintedChains = Set<RenderObject>.identity();

  void _store(RenderObject node, Matrix4 transform, Rect clip) {
    _entries[node] = (transform: transform.clone(), clip: clip);
  }

  /// Stores the first [count] nodes of [chain] as not painted.
  void _storeUnpainted(List<RenderObject> chain, int count) {
    for (var i = 0; i < count; i++) {
      _entries[chain[i]] = (transform: null, clip: Rect.zero);
    }
  }
}

/// Whether every ancestor of [target] paints the chain leading to it, with
/// the same rules as [resolvePaintGeometry], without computing the transform
/// or the clip.
///
/// The viewports and slivers that paint a sliver child only when its
/// geometry is visible are not consulted for their sliver children. [target]
/// may be a zero-extent sliver, whose geometry is never visible, and so are
/// the slivers that wrap only it; its position is decided from its
/// constraints instead.
bool paintsChain(RenderObject target) {
  final painted = PaintGeometryCache._current?._paintedChains;
  final visited = <RenderObject>[];
  RenderObject child = target;
  for (var parent = target.parent; parent != null; parent = parent.parent) {
    if (painted != null && painted.contains(child)) {
      break;
    }
    if (!_paintsSliverByGeometry(parent, child) &&
        !_paintsChild(parent, child)) {
      return false;
    }
    visited.add(child);
    child = parent;
  }
  painted?.addAll(visited);
  return true;
}

// The render objects whose paintsChild for a sliver child depends only on
// the geometry of that child.
bool _paintsSliverByGeometry(RenderObject parent, RenderObject child) {
  return child is RenderSliver &&
      switch (parent) {
        RenderViewportBase() ||
        RenderSliverMainAxisGroup() ||
        RenderSliverCrossAxisGroup() ||
        RenderSliverEdgeInsetsPadding() ||
        RenderDecoratedSliver() => true,
        _ => false,
      };
}

bool _paintsChild(RenderObject parent, RenderObject child) {
  switch (parent) {
    case RenderTransform():
      // Matches RenderTransform.paint, which paints nothing when the matrix
      // is singular.
      final transform = Matrix4.identity();
      parent.applyPaintTransform(child as RenderBox, transform);
      final determinant = transform.determinant();
      if (determinant == 0 || !determinant.isFinite) {
        return false;
      }
    case RenderFollowerLayer():
      // An unlinked follower that is not shown when unlinked paints nothing
      // that is composited (see FollowerLayer).
      if (parent.link.leader == null && !parent.showWhenUnlinked) {
        return false;
      }
  }
  return parent.paintsChild(child);
}
