import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../ble/controllers/ble_gateway_controller.dart';
import '../controllers/ble_controller.dart';
import '../models/dashboard_layout.dart';
import '../services/wind_angle_history_service.dart';
import 'metric_tile.dart';
import 'wind_compass_tile.dart';

/// Number of tile columns. A wind-compass tile spans 2x2 of these cells.
const int dashboardGridCrossAxisCount = 3;

/// Grid of tiles for one [DashboardLayout]. In edit mode, tiles get a remove
/// affordance and can be drag-reordered, and a trailing "add tile" cell
/// appears.
class DashboardGrid extends StatelessWidget {
  const DashboardGrid({
    super.key,
    required this.layout,
    required this.editing,
    required this.bleGatewayController,
    required this.telemetryController,
    required this.onReorder,
    required this.onRemoveTile,
    required this.onAddTile,
    required this.onCycleUnit,
    required this.onToggleWindMode,
    required this.windAngleHistory,
  });

  final DashboardLayout layout;
  final bool editing;
  final BleGatewayController bleGatewayController;
  final BleController telemetryController;

  /// Called the instant a dragged tile is held over another tile, so the
  /// grid reflows live (other tiles slide aside) to preview where it will
  /// land — the same feel as rearranging icons on a phone home screen —
  /// rather than only committing the move once the finger lifts.
  final void Function(String draggedTileId, String overTileId) onReorder;
  final void Function(String tileId) onRemoveTile;
  final VoidCallback onAddTile;
  final void Function(DashboardTile tile) onCycleUnit;
  final void Function(DashboardTile tile) onToggleWindMode;
  final WindAngleHistoryService windAngleHistory;

  @override
  Widget build(BuildContext context) {
    final tiles = layout.tiles;
    if (tiles.isEmpty && !editing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No tiles yet — tap the pencil to add some.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: StaggeredGrid.count(
        crossAxisCount: dashboardGridCrossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (var index = 0; index < tiles.length; index++)
            _buildCell(context, tiles[index], index),
          if (editing)
            StaggeredGridTile.count(
              key: const ValueKey<String>('add-tile-cell'),
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: _AddTileCell(onTap: onAddTile),
            ),
        ],
      ),
    );
  }

  Widget _buildCell(BuildContext context, DashboardTile tile, int index) {
    final isCompass = tile.kind == DashboardTileKind.windCompass;
    final child = isCompass
        ? WindCompassTile(
            key: ValueKey<String>(tile.id),
            tile: tile,
            bleGatewayController: bleGatewayController,
            telemetryController: telemetryController,
            windAngleHistory: windAngleHistory,
            onRemove: editing ? () => onRemoveTile(tile.id) : null,
            onCycleUnit: () => onCycleUnit(tile),
            onToggleMode: () => onToggleWindMode(tile),
          )
        : MetricTile(
            key: ValueKey<String>(tile.id),
            tile: tile,
            bleGatewayController: bleGatewayController,
            telemetryController: telemetryController,
            onRemove: editing ? () => onRemoveTile(tile.id) : null,
            onCycleUnit: () => onCycleUnit(tile),
          );

    final wrapped = editing
        ? _DraggableTile(
            tileId: tile.id,
            index: index,
            onReorder: onReorder,
            child: child,
          )
        : child;

    return StaggeredGridTile.count(
      // Keyed by tile id (not position) so a tile's drag/wiggle state
      // survives it moving to a different index mid-drag — see _DraggableTile.
      key: ValueKey<String>('cell-${tile.id}'),
      crossAxisCellCount: isCompass ? 2 : 1,
      mainAxisCellCount: isCompass ? 2 : 1,
      child: wrapped,
    );
  }
}

/// Long-press-drag reordering for one grid cell while editing, with a
/// continuous iOS/Android-home-screen-style "wiggle" so it's obvious at a
/// glance that tiles can be picked up and rearranged, and a live reflow as
/// you drag over other tiles (see [DashboardGrid.onReorder]) so you can see
/// where the tile will land instead of only finding out on drop. Hand-rolled
/// with [LongPressDraggable]/[DragTarget] rather than the grid package's own
/// reordering (which doesn't support span-aware reordering).
///
/// Still gated behind a (short) long-press rather than an immediate drag —
/// this grid lives inside a [SingleChildScrollView], and a plain [Draggable]
/// would fight every scroll gesture for ownership.
class _DraggableTile extends StatefulWidget {
  const _DraggableTile({
    required this.tileId,
    required this.index,
    required this.onReorder,
    required this.child,
  });

  final String tileId;
  /// Only used to vary the wiggle's phase/period per tile — the actual drag
  /// identity is [tileId], which (unlike a list index) stays valid even as
  /// the tile moves to a different position mid-drag.
  final int index;
  final void Function(String draggedTileId, String overTileId) onReorder;
  final Widget child;

  @override
  State<_DraggableTile> createState() => _DraggableTileState();
}

class _DraggableTileState extends State<_DraggableTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wiggle;

  @override
  void initState() {
    super.initState();
    // Vary period slightly per tile (based on its index) so a whole grid
    // doesn't wiggle in perfect unison — drifting in and out of phase reads
    // as organic, the same trick iOS uses for its home-screen jiggle.
    _wiggle = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 260 + (widget.index % 3) * 45),
    )..repeat(reverse: true);
    _wiggle.value = (widget.index % 5) / 5;
  }

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      // Reorder fires the instant a new tile is entered (not on drop) —
      // that's what makes the other tiles visibly slide aside as you drag,
      // like moving an icon between other icons on a phone home screen.
      onWillAcceptWithDetails: (details) {
        final isSelf = details.data == widget.tileId;
        if (!isSelf) widget.onReorder(details.data, widget.tileId);
        return !isSelf;
      },
      builder: (context, candidateData, rejectedData) {
        final highlighted = candidateData.isNotEmpty;
        return LongPressDraggable<String>(
          data: widget.tileId,
          delay: const Duration(milliseconds: 250),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 150,
              height: 150,
              child: Opacity(opacity: 0.9, child: widget.child),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.25, child: widget.child),
          child: AnimatedBuilder(
            animation: _wiggle,
            child: widget.child,
            builder: (context, child) {
              final angle = (_wiggle.value - 0.5) * 0.045; // ≈ ±1.3°
              return Transform.scale(
                scale: highlighted ? 1.04 : 1.0,
                child: Transform.rotate(angle: angle, child: child),
              );
            },
          ),
        );
      },
    );
  }
}

class _AddTileCell extends StatelessWidget {
  const _AddTileCell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outline.withValues(alpha: 0.4), width: 1.4),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: cs.primary),
              const SizedBox(height: 4),
              Text(
                'Add tile',
                style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
