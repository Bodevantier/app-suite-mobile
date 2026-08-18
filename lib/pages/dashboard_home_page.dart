import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../dashboard/auto_mode_detector.dart';
import '../dashboard/dashboard_icons.dart';
import '../dashboard/dashboard_metric_catalog.dart';
import '../models/dashboard_layout.dart';
import '../services/dashboard_layout_service.dart';
import '../widgets/dashboard_edit_dialog.dart';
import '../widgets/dashboard_grid.dart';
import 'dashboard_settings_page.dart';
import 'dashboard_tile_picker_page.dart';

/// The main home-page content: a swipeable set of user-defined dashboards,
/// each a grid of live-data tiles. Device pairing/discovery is unaffected —
/// this only lets the user choose what to look at from what's already on
/// the N2K bus (see [DashboardTilePickerPage]).
class DashboardHomePage extends StatefulWidget {
  const DashboardHomePage({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<DashboardHomePage> createState() => _DashboardHomePageState();
}

class _DashboardHomePageState extends State<DashboardHomePage> {
  late final PageController _pageController;
  late int _currentIndex;
  String? _editingLayoutId;

  AppDependencies get dependencies => widget.dependencies;
  DashboardLayoutService get dashboards => dependencies.dashboards;

  @override
  void initState() {
    super.initState();
    _currentIndex = _initialPageIndex();
    _pageController = PageController(initialPage: _currentIndex);
    dependencies.autoModeDetector.addListener(_maybeAutoSwitch);
    dashboards.addListener(_maybeAutoSwitch);
    dashboards.addListener(_maybeHandleEditRequest);
  }

  @override
  void dispose() {
    dependencies.autoModeDetector.removeListener(_maybeAutoSwitch);
    dashboards.removeListener(_maybeAutoSwitch);
    dashboards.removeListener(_maybeHandleEditRequest);
    _pageController.dispose();
    super.dispose();
  }

  int _initialPageIndex() {
    final layouts = dashboards.layouts;
    if (layouts.isEmpty) return 0;
    final activeId = dashboards.activeLayoutId;
    final index = activeId == null ? -1 : layouts.indexWhere((l) => l.id == activeId);
    return index < 0 ? 0 : index;
  }

  DashboardLayout? _firstWithTag(List<DashboardLayout> layouts, DashboardModeTag tag) {
    for (final layout in layouts) {
      if (layout.modeTag == tag) return layout;
    }
    return null;
  }

  /// Reacts to a new [AutoModeDetector.detectedState] (or to switching auto
  /// mode on) by jumping to whichever dashboard is tagged for that state.
  /// A no-op while the user is actively editing a dashboard, so auto-switch
  /// can't yank them away mid-edit.
  void _maybeAutoSwitch() {
    if (!mounted) return;
    if (_editingLayoutId != null) return;
    if (dashboards.switchMode != DashboardSwitchMode.auto) return;
    final detected = dependencies.autoModeDetector.detectedState;
    if (detected == null) return;

    final layouts = dashboards.layouts;
    if (layouts.isEmpty) return;

    final DashboardLayout? target = switch (detected) {
      DashboardAutoState.motoring => _firstWithTag(layouts, DashboardModeTag.motoring),
      DashboardAutoState.sailing => _firstWithTag(layouts, DashboardModeTag.sailing),
      DashboardAutoState.stationary =>
        _firstWithTag(layouts, DashboardModeTag.anchored) ??
            _firstWithTag(layouts, DashboardModeTag.docked),
    };
    if (target == null) return;

    final index = layouts.indexOf(target);
    if (index < 0 || index == _currentIndex) return;
    if (!_pageController.hasClients) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  /// Used only by [_EmptyState] (no dashboards to reach via Settings yet) —
  /// every other creation/edit entry point lives in Settings → Dashboards
  /// and goes through [_maybeHandleEditRequest] instead.
  Future<void> _createDashboard() async {
    final result = await showEditDashboardDialog(context);
    if (result == null) return;
    final layout = await dashboards.addLayout(
      name: result.name,
      iconKey: result.iconKey,
      modeTag: result.modeTag,
    );
    await dashboards.setActiveLayoutId(layout.id);
    if (!mounted) return;
    final newIndex = dashboards.layouts.indexWhere((l) => l.id == layout.id);
    if (newIndex < 0) return;
    setState(() {
      _currentIndex = newIndex;
      _editingLayoutId = layout.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.animateToPage(
        newIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _editDashboardMeta(DashboardLayout layout) async {
    final result = await showEditDashboardDialog(context, editing: layout);
    if (result == null) return;
    await dashboards.updateLayout(layout.copyWith(
      name: result.name,
      iconKey: result.iconKey,
      modeTag: result.modeTag,
      clearModeTag: result.modeTag == null,
    ));
  }

  /// Settings → Dashboards' "New dashboard"/tap-to-edit actions set
  /// [DashboardLayoutService.editRequestId] and pop back to Home rather than
  /// editing tiles themselves — this is what actually jumps to that
  /// dashboard's page and turns on tile-editing, then clears the request.
  void _maybeHandleEditRequest() {
    if (!mounted) return;
    final requestId = dashboards.editRequestId;
    if (requestId == null) return;
    final index = dashboards.layouts.indexWhere((l) => l.id == requestId);
    dashboards.consumeEditRequest();
    if (index < 0) return;
    setState(() {
      _currentIndex = index;
      _editingLayoutId = requestId;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _deleteDashboard(DashboardLayout layout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete dashboard?'),
        content: Text('"${layout.name}" and its tiles will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _editingLayoutId = null);
    await dashboards.deleteLayout(layout.id);
  }

  Future<void> _addTile(DashboardLayout layout) async {
    final tile = await Navigator.of(context).push<DashboardTile>(
      MaterialPageRoute<DashboardTile>(
        builder: (_) => DashboardTilePickerPage(
          bleGatewayController: dependencies.bleGatewayController,
          nodeSettings: dependencies.nodeSettings,
          dashboards: dashboards,
          existingTiles: layout.tiles,
        ),
      ),
    );
    if (tile == null) return;
    await dashboards.updateLayout(
      layout.copyWith(tiles: [...layout.tiles, tile]),
    );
  }

  Future<void> _removeTile(DashboardLayout layout, String tileId) async {
    await dashboards.updateLayout(
      layout.copyWith(tiles: layout.tiles.where((t) => t.id != tileId).toList()),
    );
  }

  /// Called live while a tile is being dragged over another one (see
  /// DashboardGrid's onWillAcceptWithDetails) — resolves both tiles by id
  /// fresh from the current layout each time, since either may already have
  /// moved from an earlier reorder within the same drag gesture.
  Future<void> _reorderTiles(
    DashboardLayout layout,
    String draggedTileId,
    String overTileId,
  ) async {
    if (draggedTileId == overTileId) return;
    final tiles = List.of(layout.tiles);
    final oldIndex = tiles.indexWhere((t) => t.id == draggedTileId);
    final newIndex = tiles.indexWhere((t) => t.id == overTileId);
    if (oldIndex == -1 || newIndex == -1) return;
    final item = tiles.removeAt(oldIndex);
    tiles.insert(newIndex, item);
    await dashboards.updateLayout(layout.copyWith(tiles: tiles));
  }

  Future<void> _updateTile(
    DashboardLayout layout,
    DashboardTile tile,
    DashboardTile Function(DashboardTile) transform,
  ) async {
    final tiles = layout.tiles
        .map((t) => t.id == tile.id ? transform(t) : t)
        .toList(growable: false);
    await dashboards.updateLayout(layout.copyWith(tiles: tiles));
  }

  Future<void> _cycleUnit(DashboardLayout layout, DashboardTile tile) async {
    final spec = dashboardMetricCatalog[tile.metric]!;
    if (!spec.supportsUnitCycling) return;
    final nextIndex = (tile.unitIndex + 1) % spec.units.length;
    await _updateTile(layout, tile, (t) => t.copyWith(unitIndex: nextIndex));
  }

  Future<void> _toggleWindMode(DashboardLayout layout, DashboardTile tile) async {
    final next = tile.metric == DashboardMetricType.windTrueSpeed
        ? DashboardMetricType.windApparentSpeed
        : DashboardMetricType.windTrueSpeed;
    await _updateTile(layout, tile, (t) => t.copyWith(metric: next));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: dashboards,
      builder: (context, _) {
        final layouts = dashboards.layouts;
        if (layouts.isEmpty) {
          return _EmptyState(onCreate: _createDashboard);
        }

        final safeIndex = _currentIndex.clamp(0, layouts.length - 1);
        if (safeIndex != _currentIndex) {
          // The layout list shrank (a dashboard was deleted) — resync the
          // page controller after this frame rather than during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _currentIndex = safeIndex);
            if (_pageController.hasClients) {
              _pageController.jumpToPage(safeIndex);
            }
          });
        }

        final currentLayout = layouts[safeIndex];
        final editing = _editingLayoutId == currentLayout.id;

        return Column(
          children: [
            _DashboardTabStrip(
              layouts: layouts,
              currentIndex: safeIndex,
              pageController: _pageController,
              editing: editing,
              onSelect: (index) {
                if (editing) return;
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                );
              },
              onFinishEditing: () {
                setState(() => _editingLayoutId = null);
                // Editing is only ever entered from Settings → Dashboards
                // now (see _maybeHandleEditRequest) — that page's own route
                // is gone by the time we're back here (it popped itself to
                // reveal Home), so land back on a fresh instance of it
                // rather than leaving the user on the plain dashboard view.
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DashboardSettingsPage(dashboards: dashboards),
                  ),
                );
              },
              onRename: () => _editDashboardMeta(currentLayout),
              onDelete: () => _deleteDashboard(currentLayout),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: editing
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: layouts.length,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                  unawaited(dashboards.setActiveLayoutId(layouts[index].id));
                },
                itemBuilder: (context, index) {
                  final layout = layouts[index];
                  return DashboardGrid(
                    layout: layout,
                    editing: _editingLayoutId == layout.id,
                    bleGatewayController: dependencies.bleGatewayController,
                    telemetryController: dependencies.telemetryController,
                    onReorder: (draggedTileId, overTileId) =>
                        _reorderTiles(layout, draggedTileId, overTileId),
                    onRemoveTile: (tileId) => _removeTile(layout, tileId),
                    onCycleUnit: (tile) => _cycleUnit(layout, tile),
                    onToggleWindMode: (tile) => _toggleWindMode(layout, tile),
                    windAngleHistory: dependencies.windAngleHistory,
                    onAddTile: () => _addTile(layout),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardTabStrip extends StatefulWidget {
  const _DashboardTabStrip({
    required this.layouts,
    required this.currentIndex,
    required this.pageController,
    required this.editing,
    required this.onSelect,
    required this.onFinishEditing,
    required this.onRename,
    required this.onDelete,
  });

  final List<DashboardLayout> layouts;
  final int currentIndex;
  final PageController pageController;
  final bool editing;
  final void Function(int index) onSelect;
  final VoidCallback onFinishEditing;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  State<_DashboardTabStrip> createState() => _DashboardTabStripState();
}

class _DashboardTabStripState extends State<_DashboardTabStrip> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _viewportKey = GlobalKey();
  final Map<int, GlobalKey> _chipKeys = {};
  final Map<int, double> _chipCenter = {};

  GlobalKey _keyFor(int index) => _chipKeys.putIfAbsent(index, () => GlobalKey());

  @override
  void initState() {
    super.initState();
    widget.pageController.addListener(_followPage);
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant _DashboardTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController != widget.pageController) {
      oldWidget.pageController.removeListener(_followPage);
      widget.pageController.addListener(_followPage);
    }
    _scheduleSync();
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_followPage);
    _scrollController.dispose();
    super.dispose();
  }

  /// Remeasures each chip's horizontal center (in content coordinates) once
  /// the frame settles — covers the initial layout plus any change to the
  /// dashboard list (add/rename/delete alters chip widths) — then snaps the
  /// strip to wherever the page currently sits.
  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measureChips();
      _followPage();
    });
  }

  void _measureChips() {
    final viewportBox = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !_scrollController.hasClients) return;
    for (var i = 0; i < widget.layouts.length; i++) {
      final chipBox = _chipKeys[i]?.currentContext?.findRenderObject() as RenderBox?;
      if (chipBox == null) continue;
      final left =
          chipBox.localToGlobal(Offset.zero, ancestor: viewportBox).dx + _scrollController.offset;
      _chipCenter[i] = left + chipBox.size.width / 2;
    }
  }

  /// Keeps the tab strip's scroll position matching the [PageView]'s live,
  /// fractional page continuously (this fires on every scroll delta, not
  /// just once a page fully changes) — so on a slow swipe the strip tracks
  /// the finger in lockstep instead of jumping to catch up after the fact.
  void _followPage() {
    if (!mounted || !_scrollController.hasClients) return;
    if (!_scrollController.position.hasContentDimensions) return;
    if (widget.layouts.isEmpty) return;

    final controller = widget.pageController;
    double page = widget.currentIndex.toDouble();
    if (controller.hasClients) {
      page = controller.page ?? page;
    }

    final lastIndex = widget.layouts.length - 1;
    final lowIndex = page.floor().clamp(0, lastIndex);
    final highIndex = page.ceil().clamp(0, lastIndex);
    final t = (page - lowIndex).clamp(0.0, 1.0);
    final centerLow = _chipCenter[lowIndex];
    final centerHigh = _chipCenter[highIndex];
    if (centerLow == null || centerHigh == null) return;

    final center = centerLow + (centerHigh - centerLow) * t;
    final viewportWidth = _scrollController.position.viewportDimension;
    final target =
        (center - viewportWidth / 2).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: _viewportKey,
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < widget.layouts.length; i++)
                    Padding(
                      key: _keyFor(i),
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(widget.layouts[i].name),
                        avatar: Icon(dashboardIconFor(widget.layouts[i].iconKey), size: 18),
                        showCheckmark: false,
                        selected: i == widget.currentIndex,
                        onSelected: (_) => widget.onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // New/edit/delete now live in Settings → Dashboards, so the strip
          // stays clean day-to-day — these only appear while a Settings
          // action has put a dashboard into tile-editing mode, as a way to
          // rename/retag/delete it or step back out.
          if (widget.editing) ...[
            IconButton(
              tooltip: 'Rename / retag dashboard',
              icon: const Icon(Icons.edit_note),
              onPressed: widget.onRename,
            ),
            IconButton(
              tooltip: 'Delete dashboard',
              icon: Icon(Icons.delete_outline, color: cs.error),
              onPressed: widget.onDelete,
            ),
            IconButton(
              tooltip: 'Done editing',
              icon: Icon(Icons.check_circle, color: cs.primary),
              onPressed: widget.onFinishEditing,
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dashboard_customize_outlined,
                size: 48, color: cs.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('No dashboards yet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Create a dashboard — like Motoring or Sailing — and pick which live data to show on it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create your first dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
