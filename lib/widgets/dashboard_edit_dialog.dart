import 'package:flutter/material.dart';

import '../dashboard/dashboard_icons.dart';
import '../models/dashboard_layout.dart';

/// Result of [showEditDashboardDialog] — the fields needed to create or
/// update a [DashboardLayout]'s metadata. Tiles are edited separately, on
/// the dashboard grid itself (see dashboard_home_page.dart).
class EditDashboardResult {
  const EditDashboardResult({required this.name, required this.iconKey, this.modeTag});

  final String name;
  final String iconKey;
  final DashboardModeTag? modeTag;
}

/// Prompts for a dashboard's name, icon and optional auto-switch tag.
/// Used both to create a new dashboard and, passing [editing], to
/// rename/retag an existing one — same dialog either way.
Future<EditDashboardResult?> showEditDashboardDialog(
  BuildContext context, {
  DashboardLayout? editing,
}) {
  return showDialog<EditDashboardResult>(
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
              'Used only when Settings → Dashboards → Dashboard switching is '
              'set to Auto. Anchored and Docked can\'t be told apart automatically.',
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
                    label: Text(dashboardModeTagLabel(tag)),
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
                    EditDashboardResult(
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
