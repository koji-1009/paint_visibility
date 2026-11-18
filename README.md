# paint_visibility

[![pub package](https://img.shields.io/pub/v/paint_visibility.svg)](https://pub.dev/packages/paint_visibility)
[![GitHub license](https://img.shields.io/github/license/koji-1009/paint_visibility)](https://github.com/koji-1009/paint_visibility/blob/main/LICENSE)
[![CI](https://github.com/koji-1009/paint_visibility/actions/workflows/analyze.yml/badge.svg)](https://github.com/koji-1009/paint_visibility/actions/workflows/analyze.yml)
[![codecov](https://codecov.io/gh/koji-1009/paint_visibility/branch/main/graph/badge.svg)](https://codecov.io/gh/koji-1009/paint_visibility)

Frame-accurate visibility detection for Flutter. Values are computed from the render tree alone and settled once per rendered frame, without timers, keys, or renderer-dependent state.

## Features

* **Visible fraction**: `PaintVisibility` and `SliverPaintVisibility` report how much of a widget is visible.
* **Zero-size markers**: `RegionMarker` and `SliverRegionMarker` report whether a position is inside a region, like a sentinel element of the web's IntersectionObserver. Use them for infinite loading, reading progress, or detecting that a section was reached.
* **Settled every frame**: values are computed in the post-frame phase of every rendered frame, after layout, paint and compositing. Nothing is computed while the app is idle.
* **Test friendly**: callbacks have fired by the time `tester.pump()` returns. No test-only configuration, and no timers left behind.
* **Renderer independent**: only `RenderObject` APIs are used and the canvas is never read, so the result does not depend on the renderer.
* **No keys**: each render object keeps its own last value.

## Live Preview

[https://koji-1009.github.io/paint_visibility/](https://koji-1009.github.io/paint_visibility/)

## Usage

### Visible fraction

```dart
PaintVisibility(
  onVisibilityChanged: (info, reasons) {
    if (info.visibleFraction >= 0.5) {
      logImpression(item.id);
    }
  },
  child: ItemCard(item: item),
)
```

For slivers:

```dart
SliverPaintVisibility(
  onVisibilityChanged: (info, reasons) => debugPrint('${info.visibleFraction}'),
  sliver: SliverList.builder(
    itemCount: items.length,
    itemBuilder: (context, index) => ItemTile(item: items[index]),
  ),
)
```

`VisibilityInfo` has:

| Property          | Meaning                                                                                                                        |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `size`            | Size of the axis-aligned bounding box of the widget in global logical pixels. Under `Transform.scale` this is the scaled size. |
| `visibleBounds`   | The visible part, relative to the top-left corner of that bounding box.                                                        |
| `visibleFraction` | `area(visibleBounds) / area(size)`, from 0 to 1. Values within 0.01 of 0 or 1 snap to 0 or 1.                                  |

The second argument of the callback, `reasons`, tells why the value was notified compared with the value notified before it: `initial`, `shown`, `hidden`, `stepCrossed`, `fullyVisible` and `resized`, several at once if they apply.

`size` is measured in global coordinates, so `resized` is notified whenever the measured size changes, not only when the layout changes:

* The extent of a lazy sliver such as `SliverList.builder` is estimated from the children laid out so far, so its `size` changes as children are created and destroyed.
* Under a scaling transform such as `ScaleTransition`, including page transitions that scale the page, the size changes on every frame of the animation.

Ignore notifications whose only reason is `resized` when the size does not matter:

```dart
onVisibilityChanged: (info, reasons) {
  if (reasons.length == 1 && reasons.contains(VisibilityChangeReason.resized)) {
    return;
  }
  // ...
},
```

### Zero-size markers

A zero-size marker has no area, so it reports a `bool` instead of a fraction.

```dart
CustomScrollView(
  slivers: [
    SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => ItemTile(item: items[index]),
    ),
    SliverRegionMarker(
      // SliverRegion.cacheExtent (default) or SliverRegion.viewport
      onRegionChanged: (isInRegion) {
        if (isInRegion) {
          loadNextPage();
        }
      },
    ),
  ],
)
```

`RegionMarker` is the box version, for places without slivers such as the end of a `Column` in a `SingleChildScrollView`. Its region is the viewport; the cache extent cannot be observed from a box.

The main axis is the half-open interval [leading edge, trailing edge): a marker exactly on the leading edge is inside, and a marker exactly on the trailing edge is outside. A marker at the very end of the scrollable content therefore sits on the trailing edge of the viewport when scrolled to the end, and is reported as outside. Put some content or padding after a `RegionMarker`, or after a `SliverRegionMarker` with `SliverRegion.viewport`, when it must be detected at the end of the content.

> [!IMPORTANT]
> A marker reports only the moments it enters or leaves the region. If the marker is still inside the region after a page has been loaded, no further notification arrives. For infinite loading, choose a page size large enough that one page is taller than the region (the viewport plus the cache extent for `SliverRegion.cacheExtent`).

### Navigation

A page covered by an opaque route is not painted by the `Navigator`, so it is hidden like any other widget that is not painted. `routeCoverage` decides how the route state is reported on top of that.

| `routeCoverage`      | While the route is covered                                                                                                                                                                                                  | Default for                                |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `RouteCoverage.page` | Hidden while an opaque route covers the page so that the `Navigator` no longer paints it: from the end of the push until the start of the pop. Dialogs, bottom sheets and Cupertino sheets do not hide the page below them. | `PaintVisibility`, `SliverPaintVisibility` |
| `RouteCoverage.any`  | Hidden while any route is on top, including dialogs and bottom sheets, and while the route itself is being popped.                                                                                                          | —                                          |
| `RouteCoverage.keep` | The last value is kept while an opaque route covers the page, and the widget is evaluated again when the page is painted again.                                                                                             | `RegionMarker`, `SliverRegionMarker`       |

```dart
PaintVisibility(
  routeCoverage: RouteCoverage.any, // also hidden under dialogs
  onVisibilityChanged: (info, reasons) => ...,
  child: ...,
)
```

`RouteCoverage.page` covers every kind of opaque route and nested navigators, and the covered page becomes visible again while a back swipe paints it. `RouteCoverage.any` follows `ModalRoute.isCurrentOf`, so only the nearest `Navigator` is considered. `RouteCoverage.keep` follows `TickerMode.valuesOf`, so a `TickerMode(enabled: false)` placed by the app also keeps the last value of the widgets below it.

The markers default to `RouteCoverage.keep` because, with another value, returning to a page reports `true` again while the marker is still inside the region, which would trigger another load.

## Notifications

* Values are settled in the post-frame phase of each rendered frame. No extra frames are requested, and nothing is computed while no frame is rendered.
* The first value after the render object is created is always notified (`initial`), even when it is hidden.
* After that, a value is notified when the widget becomes hidden or visible, when its size changes, when `visibleFraction` crosses a multiple of `fractionStep` (0.1 by default, from 0.01 to 1), or when it becomes fully visible. Nothing is notified while it stays hidden.
* The last notified value is in the same interval between two multiples of `fractionStep` as the current one, so a test such as `visibleFraction >= 0.5` gives the same result for both.
* When the widget is removed while its last value was visible, a hidden value is notified on the next frame. The `State` that owns the callback may already be disposed, so check `mounted` before calling `setState`.
* When a widget is recreated with a new render object, it starts over from `initial`.

Apart from `fractionStep`, throttling and debouncing are not provided, because the right strategy depends on the use case. Implement it on top of the callback.

## Testing

In a widget test, the callback has fired by the time `await tester.pump()` returns, so assert on the values it received. The last received value is in the same `fractionStep` interval as the current one, so assert against the interval.

```dart
final fractions = <double>[];
await tester.pumpWidget(
  PaintVisibility(
    onVisibilityChanged: (info, reasons) => fractions.add(info.visibleFraction),
    child: child,
  ),
);
await tester.drag(find.byType(ListView), const Offset(0, -300));
await tester.pump();
// The current fraction is 0.55; the last notified one is in [0.5, 0.6).
expect(fractions.last, allOf(greaterThanOrEqualTo(0.5), lessThan(0.6)));
```

For a value within 0.01 of the current one, set `fractionStep: 0.01`.

## How it works

Once per rendered frame, the ancestor chain of each observed render object is walked:

* **Hidden** when an ancestor does not paint it, as reported by `RenderObject.paintsChild`.
* **Clipped** by every ancestor clip, as described by `RenderObject.describeApproximatePaintClip`.
* **Positioned** by `RenderObject.applyPaintTransform`, then measured as the axis-aligned bounding box in global logical pixels.

## Limitations

* Widgets painted on top, such as overlays, `Stack` siblings and dialogs, do not hide what is below them. Use `RouteCoverage.any` to hide a page under dialogs.
* A custom render object that skips painting a child without overriding `paintsChild`, or clips without implementing `describeApproximatePaintClip`, is treated as painting and not clipping.
* Under rotation and perspective, the bounding box of the transformed rect is measured.
* While the app is in the background, or no frames are rendered, nothing is notified until the next frame.

## License

MIT License - see [LICENSE](LICENSE) for details.
