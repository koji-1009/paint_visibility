import 'dart:async';

import 'package:paint_visibility/paint_visibility.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'paint_visibility',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('paint_visibility'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Fraction'),
              Tab(text: 'Infinite'),
              Tab(text: 'Marker'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [FractionPage(), InfinitePage(), MarkerPage()],
        ),
      ),
    );
  }
}

/// Shows the visible fraction of every item, updated on every frame.
class FractionPage extends StatelessWidget {
  const FractionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 50,
      itemBuilder: (context, index) => FractionTile(index: index),
    );
  }
}

class FractionTile extends StatefulWidget {
  const FractionTile({super.key, required this.index});

  final int index;

  @override
  State<FractionTile> createState() => _FractionTileState();
}

class _FractionTileState extends State<FractionTile> {
  double _fraction = 0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PaintVisibility(
      onVisibilityChanged: (info, reasons) {
        // The render object may report a hidden value after this State has
        // been disposed.
        if (mounted) {
          setState(() => _fraction = info.visibleFraction);
        }
      },
      child: Container(
        height: 120,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        color: Color.lerp(
          colorScheme.surfaceContainerHighest,
          colorScheme.primaryContainer,
          _fraction,
        ),
        alignment: Alignment.center,
        child: Text(
          'Item ${widget.index}: ${(_fraction * 100).toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}

/// Loads the next page when a zero-extent marker enters the cache extent.
class InfinitePage extends StatefulWidget {
  const InfinitePage({super.key});

  @override
  State<InfinitePage> createState() => _InfinitePageState();
}

class _InfinitePageState extends State<InfinitePage> {
  // One page is taller than the viewport plus the cache extent, so the
  // marker leaves the region after each load and can enter it again.
  static const int _pageSize = 20;

  final List<int> _items = List.generate(_pageSize, (i) => i);
  bool _loading = false;

  Future<void> _loadMore() async {
    if (_loading) {
      return;
    }
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) {
      return;
    }
    setState(() {
      _items.addAll(List.generate(_pageSize, (i) => _items.length + i));
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverList.builder(
          itemCount: _items.length,
          itemBuilder: (context, index) =>
              ListTile(title: Text('Row ${_items[index]}')),
        ),
        SliverRegionMarker(
          onRegionChanged: (isInRegion) {
            if (isInRegion) {
              unawaited(_loadMore());
            }
          },
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Text('${_items.length} rows'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reports whether the end of a plain Column has been reached.
class MarkerPage extends StatefulWidget {
  const MarkerPage({super.key});

  @override
  State<MarkerPage> createState() => _MarkerPageState();
}

class _MarkerPageState extends State<MarkerPage> {
  bool _reachedEnd = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: _reachedEnd
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: ListTile(
            title: Text(_reachedEnd ? 'End reached' : 'Scroll to the end'),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 30; i++)
                  ListTile(title: Text('Paragraph $i')),
                RegionMarker(
                  onRegionChanged: (isInRegion) {
                    if (mounted) {
                      setState(() => _reachedEnd = isInRegion);
                    }
                  },
                ),
                // The trailing edge of the region is exclusive. Without
                // content after it, the marker would sit exactly on that
                // edge when scrolled to the end and report false.
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
