import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/n2k_device_info.dart';
import '../models/node_settings.dart';
import '../models/engine_settings.dart';
import '../n2k/fluid_icons.dart';
import '../services/node_settings_service.dart';

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Per-node configuration screen. Currently tailored for fluid-level
/// sensors (PGN 127505) but the layout is generic enough to extend to
/// other categories — the irrelevant sections are simply hidden when the
/// device is not a fluid-level source.
class NodeSettingsPage extends StatefulWidget {
  const NodeSettingsPage({
    super.key,
    required this.device,
    required this.settingsService,
    this.initialFluidType,
    this.initialCapacityL,
  });

  final N2kDeviceInfo device;
  final NodeSettingsService settingsService;

  /// The device's own broadcast fluid-type label (PGN 127505), read once
  /// when this page is opened. Only used as a fallback to pick the right
  /// alarm direction (low vs. high) when the user hasn't set a fluid-type
  /// override yet — this page has no live telemetry feed of its own.
  final String? initialFluidType;

  /// The device's own broadcast tank capacity (PGN 127505), read once when
  /// this page is opened. Shown as the capacity field's hint so an empty
  /// field reads as "currently using 200 L from the device" rather than
  /// looking like nothing is known — same reasoning as [initialFluidType].
  final double? initialCapacityL;

  @override
  State<NodeSettingsPage> createState() => _NodeSettingsPageState();
}

class _NodeSettingsPageState extends State<NodeSettingsPage> {
  // Per product scope: only the tank media the SDolve sensor is actually
  // used for are user-selectable. Other PGN 127505 fluid type codes are
  // still decoded from the bus, but not offered as overrides.
  static const List<String> _fluidTypes = <String>[
    'Fuel',
    'Water',
    'Gray water',
    'Black water',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;
  late final TextEditingController _notesController;

  // True once any field diverges from what was loaded — gates the
  // leave-without-saving warning in the PopScope below.
  bool _dirty = false;
  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  String? _fluidTypeOverride;
  bool _alarmEnabled = false;
  // ValueNotifier (instead of plain double + setState) so dragging the
  // threshold slider only rebuilds the slider row itself, not the whole
  // settings form. This removes visible drag lag on lower-end devices.
  final ValueNotifier<double> _alarmPct = ValueNotifier<double>(10);

  // High-level alarm — shown instead of the low-level one for waste tanks
  // (gray/black water), which fill up during use rather than draining down.
  bool _highLevelAlarmEnabled = false;
  final ValueNotifier<double> _highLevelAlarmPct = ValueNotifier<double>(90);

  bool _highTempAlarmEnabled = false;
  final ValueNotifier<double> _highTempAlarmC = ValueNotifier<double>(35.0);
  bool _lowTempAlarmEnabled = false;
  final ValueNotifier<double> _lowTempAlarmC = ValueNotifier<double>(5.0);

  // ── Engine RPM calibration (PGN 127488) ────────────────────────────────
  // Selectable even alternator pole counts. 6 poles is the most common on
  // small-craft alternators and matches the firmware default.
  static const List<int> _alternatorPoleOptions = <int>[
    2, 4, 6, 8, 10, 12, 14, 16,
  ];
  int _alternatorPoles = 6;
  // ValueNotifier so dragging the pulley-ratio slider only rebuilds the
  // slider + readout, not the whole settings form.
  final ValueNotifier<double> _pulleyRatio = ValueNotifier<double>(2.0);
  // Selectable full-scale values for the RPM dial (kept as multiples of 1000
  // so the gauge ticks stay clean).
  static const List<int> _maxRpmOptions = <int>[
    3000, 4000, 5000, 6000, 7000, 8000,
  ];
  int _maxRpm = 6000;

  @override
  void initState() {
    super.initState();
    final s = widget.settingsService.forDevice(widget.device);
    _nameController = TextEditingController(text: s.customName ?? '');
    _capacityController = TextEditingController(
      text: s.customCapacityL?.toStringAsFixed(1) ?? '',
    );
    _notesController = TextEditingController(text: s.notes ?? '');
    _fluidTypeOverride = s.customFluidTypeLabel;
    _alarmEnabled = s.lowLevelAlarmEnabled;
    _alarmPct.value = s.lowLevelAlarmPct;
    _highLevelAlarmEnabled = s.highLevelAlarmEnabled;
    _highLevelAlarmPct.value = s.highLevelAlarmPct;
    _highTempAlarmEnabled = s.highTempAlarmEnabled;
    _highTempAlarmC.value = s.highTempAlarmC;
    _lowTempAlarmEnabled = s.lowTempAlarmEnabled;
    _lowTempAlarmC.value = s.lowTempAlarmC;

    // Listeners are attached only after every field above has its initial
    // value, so loading existing settings never itself counts as a change.
    _nameController.addListener(_markDirty);
    _capacityController.addListener(_markDirty);
    _notesController.addListener(_markDirty);
    _alarmPct.addListener(_markDirty);
    _highLevelAlarmPct.addListener(_markDirty);
    _highTempAlarmC.addListener(_markDirty);
    _lowTempAlarmC.addListener(_markDirty);

    // Engine calibration is stored globally (shared across engine sources),
    // so load it asynchronously and fold it into the form when ready.
    if (widget.device.isEngineDevice) {
      EngineSettings.load().then((engine) {
        if (!mounted) return;
        setState(() {
          _alternatorPoles = engine.alternatorPoles;
          _maxRpm = engine.maxRpm;
        });
        _pulleyRatio.value = engine.pulleyRatio;
        // Attached after the loaded value lands, same reasoning as above.
        _pulleyRatio.addListener(_markDirty);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    _notesController.dispose();
    _alarmPct.dispose();
    _highLevelAlarmPct.dispose();
    _highTempAlarmC.dispose();
    _lowTempAlarmC.dispose();
    _pulleyRatio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final notes = _notesController.text.trim();
    final capacityText = _capacityController.text.trim();
    final capacity = capacityText.isEmpty
        ? null
        : double.tryParse(capacityText.replaceAll(',', '.'));

    if (capacityText.isNotEmpty && capacity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tank capacity must be a number (litres).'),
        ),
      );
      return;
    }

    final newSettings = NodeSettings(
      customName: name.isEmpty ? null : name,
      customFluidTypeLabel: _fluidTypeOverride,
      customCapacityL: capacity,
      lowLevelAlarmEnabled: _alarmEnabled,
      lowLevelAlarmPct: _alarmPct.value,
      highLevelAlarmEnabled: _highLevelAlarmEnabled,
      highLevelAlarmPct: _highLevelAlarmPct.value,
      highTempAlarmEnabled: _highTempAlarmEnabled,
      highTempAlarmC: _highTempAlarmC.value,
      lowTempAlarmEnabled: _lowTempAlarmEnabled,
      lowTempAlarmC: _lowTempAlarmC.value,
      notes: notes.isEmpty ? null : notes,
    );
    await widget.settingsService.saveForDevice(widget.device, newSettings);

    // Engine calibration lives in its own (global) store.
    if (widget.device.isEngineDevice) {
      await EngineSettings(
        alternatorPoles: _alternatorPoles,
        pulleyRatio: _pulleyRatio.value,
        maxRpm: _maxRpm,
      ).save();
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Confirmation shown when the user tries to leave with unsaved edits.
  /// Returns true only when they explicitly choose to discard them — a
  /// "Save" tap here saves and pops the settings page itself, so this
  /// resolves false (nothing more to do) in that case.
  Future<bool> _confirmDiscardChanges() async {
    final cs = Theme.of(context).colorScheme;
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Discard changes',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return AlertDialog(
          icon: Icon(Icons.error_outline_rounded, color: cs.error),
          title: const Text('Unsaved changes'),
          content: const Text(
            "You've changed this device's settings but haven't saved. "
            'Leave anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Discard', style: TextStyle(color: cs.error)),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(context).pop(false);
                await _save();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all settings?'),
        content: Text(
          'This removes every custom value for ${widget.device.displayName}. '
          'The device will be shown using its broadcast values again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.settingsService.saveForDevice(
      widget.device,
      NodeSettings.empty,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isFluidLevel = widget.device.isFluidLevelDevice;
    final isTemperature = widget.device.isTemperatureDevice;
    final isEngine = widget.device.isEngineDevice;
    // No live telemetry feed on this page — fall back to the value seen
    // when it was opened until the user picks an explicit override.
    final isWasteTank = isWasteFluidType(
      _fluidTypeOverride ?? widget.initialFluidType,
    );
    final cs = Theme.of(context).colorScheme;

    return PopScope<void>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await _confirmDiscardChanges();
        if (discard && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Device settings'),
          actions: [
            IconButton(
              tooltip: 'Reset to defaults',
              icon: const Icon(Icons.restart_alt),
              onPressed: _resetAll,
            ),
          ],
        ),
        body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DeviceHeader(device: widget.device),
          const SizedBox(height: 16),

          // ── Identity ────────────────────────────────────────────────────
          _SectionCard(
            title: 'Identity',
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Custom name',
                  hintText: widget.device.displayName,
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 8),
              Text(
                'Replaces the name shown in this app. The device keeps its '
                'real identity on the NMEA 2000 bus.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Fluid-level specific settings ──────────────────────────────
          if (isFluidLevel) ...[
            _SectionCard(
              title: 'Tank',
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: _fluidTypeOverride,
                  decoration: const InputDecoration(
                    labelText: 'Fluid type (display only)',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Use device value'),
                    ),
                    ..._fluidTypes.map(
                      (t) => DropdownMenuItem<String?>(
                        value: t,
                        child: Text(t),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _fluidTypeOverride = value;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _capacityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Tank capacity (litres)',
                    hintText: widget.initialCapacityL != null
                        ? '${widget.initialCapacityL!.round()} (device value)'
                        : 'Leave empty to use device value',
                    border: const OutlineInputBorder(),
                    suffixText: 'L',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.initialCapacityL != null
                      ? 'Device currently reports ${widget.initialCapacityL!.round()} L. '
                          'App-side override only — to change what it broadcasts to '
                          'chart-plotters and other instruments, update '
                          'TANK_CAPACITY_L in the sensor firmware.'
                      : 'App-side override only. To change what the device '
                          'broadcasts to chart-plotters and other instruments, '
                          'update TANK_CAPACITY_L in the sensor firmware.',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Alarm ─────────────────────────────────────────────────────
            // Waste tanks (gray/black water) fill up during use, so they
            // want a "getting full" warning; fuel/water tanks drain down
            // and want a "getting empty" one. Only one is shown at a time.
            if (isWasteTank)
              _SectionCard(
                title: 'High-level alarm',
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Warn when tank is nearly full'),
                    value: _highLevelAlarmEnabled,
                    onChanged: (v) => setState(() {
                      _highLevelAlarmEnabled = v;
                      _dirty = true;
                    }),
                  ),
                  Opacity(
                    opacity: _highLevelAlarmEnabled ? 1.0 : 0.5,
                    child: _AlarmThresholdSlider(
                      value: _highLevelAlarmPct,
                      enabled: _highLevelAlarmEnabled,
                      min: 50,
                      max: 100,
                    ),
                  ),
                ],
              )
            else
              _SectionCard(
                title: 'Low-level alarm',
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Warn when level is low'),
                    value: _alarmEnabled,
                    onChanged: (v) => setState(() {
                      _alarmEnabled = v;
                      _dirty = true;
                    }),
                  ),
                  Opacity(
                    opacity: _alarmEnabled ? 1.0 : 0.5,
                    child: _AlarmThresholdSlider(
                      value: _alarmPct,
                      enabled: _alarmEnabled,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
          ],

          // ── Temperature alarms ─────────────────────────────────────────
          if (isTemperature) ...[
            _SectionCard(
              title: 'Temperature alarms',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('High-temperature warning'),
                  value: _highTempAlarmEnabled,
                  onChanged: (v) => setState(() {
                    _highTempAlarmEnabled = v;
                    _dirty = true;
                  }),
                ),
                Opacity(
                  opacity: _highTempAlarmEnabled ? 1.0 : 0.5,
                  child: _TempThresholdSlider(
                    value: _highTempAlarmC,
                    enabled: _highTempAlarmEnabled,
                    min: -10,
                    max: 100,
                    label: 'Warn above',
                    unit: '°C',
                  ),
                ),
                const Divider(height: 20),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Low-temperature warning'),
                  value: _lowTempAlarmEnabled,
                  onChanged: (v) => setState(() {
                    _lowTempAlarmEnabled = v;
                    _dirty = true;
                  }),
                ),
                Opacity(
                  opacity: _lowTempAlarmEnabled ? 1.0 : 0.5,
                  child: _TempThresholdSlider(
                    value: _lowTempAlarmC,
                    enabled: _lowTempAlarmEnabled,
                    min: -10,
                    max: 100,
                    label: 'Warn below',
                    unit: '°C',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── Engine RPM calibration ─────────────────────────────────────
          if (isEngine) ...[
            _SectionCard(
              title: 'Engine RPM calibration',
              children: [
                Text(
                  'The sensor measures RPM from the alternator W-terminal. '
                  'Enter your alternator and pulley details so the gauge '
                  'shows true engine RPM.',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: _alternatorPoles,
                  decoration: const InputDecoration(
                    labelText: 'Alternator poles',
                    border: OutlineInputBorder(),
                  ),
                  items: _alternatorPoleOptions
                      .map(
                        (p) => DropdownMenuItem<int>(
                          value: p,
                          child: Text('$p poles'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _alternatorPoles = value;
                        _dirty = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<double>(
                  valueListenable: _pulleyRatio,
                  builder: (context, ratio, _) {
                    final ppr = (_alternatorPoles / 2.0) * ratio;
                    final factor = ppr <= 0
                        ? 1.0
                        : EngineSettings.sensorAssumedPulsesPerRev / ppr;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Pulley ratio (engine : alternator)',
                              style: TextStyle(fontSize: 13),
                            ),
                            Text(
                              '${ratio.toStringAsFixed(2)}:1',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: ratio.clamp(0.5, 4.0),
                          min: 0.5,
                          max: 4.0,
                          divisions: 70, // 0.05 steps
                          label: '${ratio.toStringAsFixed(2)}:1',
                          onChanged: (v) => _pulleyRatio.value =
                              double.parse(v.toStringAsFixed(2)),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceAround,
                            children: [
                              _calcReadout(
                                'Pulses / rev',
                                ppr.toStringAsFixed(1),
                                cs,
                              ),
                              _calcReadout(
                                'Display factor',
                                '×${factor.toStringAsFixed(3)}',
                                cs,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Gauge scale',
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _maxRpm,
                  decoration: const InputDecoration(
                    labelText: 'Maximum RPM (dial full-scale)',
                    border: OutlineInputBorder(),
                  ),
                  items: _maxRpmOptions
                      .map(
                        (m) => DropdownMenuItem<int>(
                          value: m,
                          child: Text('$m RPM'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _maxRpm = value;
                        _dirty = true;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Sets the end of the RPM dial. Pick a value just above your '
                  "engine's redline.",
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── Notes ───────────────────────────────────────────────────────
          _SectionCard(
            title: 'Notes',
            children: [
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. starboard locker, replaced sender 2025-08',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _calcReadout(String label, String value, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({required this.device});
  final N2kDeviceInfo device;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            device.displayName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            'src ${device.sourceAddress} · ${_capitalize(device.displayCategory)}',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Threshold slider isolated into its own widget so dragging it does not
/// trigger a rebuild of the entire settings form (which contains several
/// TextFields, a Dropdown, and section cards). Listens to a parent-owned
/// [ValueNotifier] so the saved value stays in sync without setState.
class _AlarmThresholdSlider extends StatelessWidget {
  const _AlarmThresholdSlider({
    required this.value,
    required this.enabled,
    this.min = 0,
    this.max = 50,
  });

  final ValueNotifier<double> value;
  final bool enabled;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: value,
      builder: (context, v, _) {
        final clamped = v.clamp(min, max);
        return Row(
          children: [
            const Text('Threshold'),
            Expanded(
              child: Slider(
                min: min,
                max: max,
                divisions: (max - min).round(),
                label: '${clamped.round()} %',
                value: clamped,
                onChanged: enabled ? (nv) => value.value = nv : null,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '${clamped.round()} %',
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Temperature threshold slider — same isolated-ValueNotifier pattern as
/// [_AlarmThresholdSlider], but for °C with configurable min/max.
class _TempThresholdSlider extends StatelessWidget {
  const _TempThresholdSlider({
    required this.value,
    required this.enabled,
    required this.min,
    required this.max,
    required this.label,
    required this.unit,
  });

  final ValueNotifier<double> value;
  final bool enabled;
  final double min;
  final double max;
  final String label;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: value,
      builder: (context, v, _) {
        final clamped = v.clamp(min, max);
        return Row(
          children: [
            Text(label),
            Expanded(
              child: Slider(
                min: min,
                max: max,
                divisions: (max - min).round(),
                label: '${clamped.round()} $unit',
                value: clamped,
                onChanged: enabled ? (nv) => value.value = nv : null,
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                '${clamped.round()} $unit',
                textAlign: TextAlign.right,
              ),
            ),
          ],
        );
      },
    );
  }
}
