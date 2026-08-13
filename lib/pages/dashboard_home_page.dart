import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_dependencies.dart';
import '../dashboard/auto_mode_detector.dart';
import '../dashboard/dashboard_icons.dart';
import '../dashboard/dashboard_metric_catalog.dart';
import '../models/dashboard_layout.dart';
import '../services/dashboard_layout_service.dart';
import '../widgets/dashboard_grid.dart';
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
  }

  @override
  void dispose() {
    dependencies.autoModeDetector.removeListener(_maybeAutoSwitch);
    dashboards.removeListener(_maybeAutoSwitch);
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

  Future<void> _createDashboard() async {
    final result = await _showEditDashboardDialog(context);
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
    setState(() => _currentIndex = newIndex);
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
    final result = await _showEditDashboardDialog(context, editing: layout);
    if (result == null) return;
    await dashboards.updateLayout(layout.copyWith(
      name: result.name,
      iconKey: result.iconKey,
      modeTag: result.modeTag,
      clearModeTag: result.modeTag == null,
    ));
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
              editing: editing,
              onSelect: (index) {
                if (editing) return;
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                );
              },
              onAddDashboard: _createDashboard,
              onToggleEdit: () {
                setState(() {
                  _editingLayoutId = editing ? null : currentLayout.id;
                });
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

class _DashboardTabStrip extends StatelessWidget {
  const _DashboardTabStrip({
    required this.layouts,
    required this.currentIndex,
    required this.editing,
    required this.onSelect,
    required this.onAddDashboard,
    required this.onToggleEdit,
    required this.onRename,
    required this.onDelete,
  });

  final List<DashboardLayout> layouts;
  final int currentIndex;
  final bool editing;
  final void Function(int index) onSelect;
  final VoidCallback onAddDashboard;
  final VoidCallback onToggleEdit;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < layouts.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(layouts[i].name),
                        avatar: Icon(dashboardIconFor(layouts[i].iconKey), size: 18),
                        selected: i == currentIndex,
                        onSelected: (_) => onSelect(i),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                    onPressed: onAddDashboard,
                  ),
                ],
              ),
            ),
          ),
          if (editing) ...[
            IconButton(
              tooltip: 'Rename / retag dashboard',
              icon: const Icon(Icons.edit_note),
              onPressed: onRename,
            ),
            IconButton(
              tooltip: 'Delete dashboard',
              icon: Icon(Icons.delete_outline, color: cs.error),
              onPressed: onDelete,
            ),
          ],
          IconButton(
            tooltip: editing ? 'Done editing' : 'Edit dashboard',
            icon: Icon(
              editing ? Icons.check_circle : Icons.edit_outlined,
              color: editing ? cs.primary : null,
            ),
            onPressed: onToggleEdit,
          ),
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

class _EditDashboardResult {
  const _EditDashboardResult({required this.name, required this.iconKey, this.modeTag});

  final String name;
  final String iconKey;
  final DashboardModeTag? modeTag;
}

Future<_EditDashboardResult?> _showEditDashboardDialog(
  BuildContext context, {
  DashboardLayout? editing,
}) {
  return showDialog<_EditDashboardResult>(
    context: context,
    builder: (context) => _EditDashboardDialog(editing: editing),
  );
}

class _EditDashboardDialog extends StatefulWidget {
  const _EditDashboardDialog({this.editing});

  final DashboardLayout? editing;

  @override
  State<_EditDashboardDialog> createState() => _EditDashboardDialogState();
}

class _EditDashboardDialogState extends State<_EditDashboardDialog> {
  late final TextEditingController _nameController;
  late String _iconKey;
  DashboardModeTag? _modeTag;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.editing?.name ?? '');
    _iconKey = widget.editing?.iconKey ?? defaultDashboardIconKey;
    _modeTag = widget.editing?.modeTag;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static String _tagLabel(DashboardModeTag tag) => switch (tag) {
        DashboardModeTag.sailing => 'Sailing',
        DashboardModeTag.motoring => 'Motoring',
        DashboardModeTag.anchored => 'Anchored',
        DashboardModeTag.docked => 'Docked',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNew = widget.editing == null;
    return AlertDialog(
      title: Text(isNew ? 'New dashboard' : 'Edit dashboard'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text('Icon', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: dashboardIconChoices.entries.map((entry) {
                final selected = entry.key == _iconKey;
                return ChoiceChip(
                  label: Icon(entry.value, size: 20),
                  selected: selected,
                  onSelected: (_) => setState(() => _iconKey = entry.key),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Auto-switch tag (optional)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Used only when Settings → Dashboard switching is set to Auto. '
              'Anchored and Docked can\'t be told apart automatically.',
              style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('None'),
                  selected: _modeTag == null,
                  onSelected: (_) => setState(() => _modeTag = null),
                ),
                for (final tag in DashboardModeTag.values)
                  ChoiceChip(
                    label: Text(_tagLabel(tag)),
                    selected: _modeTag == tag,
                    onSelected: (_) => setState(() => _modeTag = tag),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _nameController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _EditDashboardResult(
                      name: _nameController.text.trim(),
                      iconKey: _iconKey,
                      modeTag: _modeTag,
                    ),
                  ),
          child: Text(isNew ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
