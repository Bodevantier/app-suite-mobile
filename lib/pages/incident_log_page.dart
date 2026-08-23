import 'package:flutter/material.dart';

import '../services/incident_log_service.dart';

/// History of every alarm trigger/clear event, newest first — the record of
/// what actually happened while you weren't watching the dashboard.
class IncidentLogPage extends StatelessWidget {
  const IncidentLogPage({super.key, required this.incidentLog});

  final IncidentLogService incidentLog;

  Future<void> _clearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear incident log?'),
        content: const Text(
          'This permanently removes every recorded alarm event.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await incidentLog.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident log'),
        actions: [
          AnimatedBuilder(
            animation: incidentLog,
            builder: (context, _) => IconButton(
              tooltip: 'Clear log',
              icon: const Icon(Icons.delete_outline),
              onPressed: incidentLog.entries.isEmpty
                  ? null
                  : () => _clearAll(context),
            ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: incidentLog,
        builder: (context, _) {
          final entries = incidentLog.entries;
          if (entries.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _IncidentTile(entry: entries[index]),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_outlined,
              size: 40,
              color: cs.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              'No incidents yet',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Alarm triggers and clears will show up here once a device '
              'crosses an alarm threshold you\'ve set in its Device settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncidentTile extends StatelessWidget {
  const _IncidentTile({required this.entry});

  final IncidentLogEntry entry;

  String _relativeTime(DateTime at) {
    final age = DateTime.now().difference(at);
    if (age.inSeconds < 60) return 'just now';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    if (age.inDays < 7) return '${age.inDays}d ago';
    final t = entry.time;
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = entry.isTrigger ? cs.error : Colors.green.shade600;
    final icon = entry.isTrigger
        ? Icons.warning_amber_rounded
        : Icons.check_circle_outline;
    final verb = entry.isTrigger ? 'Triggered' : 'Cleared';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: color),
        title: Text(
          '${entry.deviceName} — ${entry.alarmLabel}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          '$verb at ${entry.value.toStringAsFixed(1)}${entry.unit} '
          '(threshold ${entry.threshold.toStringAsFixed(1)}${entry.unit})',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.65)),
        ),
        trailing: Text(
          _relativeTime(entry.time),
          style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.55)),
        ),
      ),
    );
  }
}
