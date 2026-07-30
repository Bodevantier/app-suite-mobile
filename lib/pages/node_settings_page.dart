import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/n2k_device_info.dart';
import '../models/node_settings.dart';
import '../models/engine_settings.dart';
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
  });

  final N2kDeviceInfo device;
  final NodeSettingsService settingsService;

  @override
  State<NodeSettingsPage> createState() => _NodeSettingsPageState();
}

class _NodeSettingsPageState extends State<NodeSettingsPage> {
  // Per product scope: only the three tank media the SDolve sensor is
  // actually used for are user-selectable. Other PGN 127505 fluid type
  // codes are still decoded from the bus, but not offered as overrides.
  static const List<String> _fluidTypes = <String>[
    'Fuel',
    'Water',
    'Gray water',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;
  late final TextEditingController _notesController;
  String? _fluidTypeOverride;
  bool _alarmEnabled = false;
  // ValueNotifier (instead of plain double + setState) so dragging the
  // threshold slider only rebuilds the slider row itself, not the whole
  // settings form. This removes visible drag lag on lower-end devices.
  final ValueNotifier<double> _alarmPct = ValueNotifier<double>(10);

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
    _highTempAlarmEnabled = s.highTempAlarmEnabled;
    _highTempAlarmC.value = s.highTempAlarmC;
    _lowTempAlarmEnabled = s.lowTempAlarmEnabled;
    _lowTempAlarmC.value = s.lowTempAlarmC;

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
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    _notesController.dispose();
    _alarmPct.dispose();
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
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
                  onChanged: (value) =>
                      setState(() => _fluidTypeOverride = value),
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
                  decoration: const InputDecoration(
                    labelText: 'Tank capacity (litres)',
                    hintText: 'Leave empty to use device value',
                    border: OutlineInputBorder(),
                    suffixText: 'L',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'App-side override only. To change what the device '
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
            _SectionCard(
              title: 'Low-level alarm',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Warn when level is low'),
                  value: _alarmEnabled,
                  onChanged: (v) => setState(() => _alarmEnabled = v),
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
                  onChanged: (v) =>
                      setState(() => _highTempAlarmEnabled = v),
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
                  onChanged: (v) =>
                      setState(() => _lowTempAlarmEnabled = v),
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
                      setState(() => _alternatorPoles = value);
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
                      setState(() => _maxRpm = value);
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
  });

  final ValueNotifier<double> value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: value,
      builder: (context, v, _) {
        final clamped = v.clamp(0.0, 50.0);
        return Row(
          children: [
            const Text('Threshold'),
            Expanded(
              child: Slider(
                min: 0,
                max: 50,
                divisions: 50,
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
