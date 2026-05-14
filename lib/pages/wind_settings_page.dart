import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted display + trail settings for the Wind Data page.
class WindSettings {
  const WindSettings({
    this.trailWindowMinutes = 5,
    this.trailHalfLifeSec = 60.0,
    this.trailSigmaDeg = 2.0,
  });

  /// How many minutes of angle history the trail covers.
  final int trailWindowMinutes;

  /// Exponential fade half-life in seconds. Lower = faster fade.
  final double trailHalfLifeSec;

  /// Gaussian smoothing width in degrees.
  final double trailSigmaDeg;

  static const _kWindow    = 'wind_trail_window_min';
  static const _kHalfLife  = 'wind_trail_halflife_sec';
  static const _kSigma     = 'wind_trail_sigma_deg';

  static Future<WindSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return WindSettings(
      trailWindowMinutes: prefs.getInt(_kWindow)        ?? 5,
      trailHalfLifeSec:   prefs.getDouble(_kHalfLife)  ?? 60.0,
      trailSigmaDeg:      prefs.getDouble(_kSigma)     ?? 4.0,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWindow, trailWindowMinutes);
    await prefs.setDouble(_kHalfLife, trailHalfLifeSec);
    await prefs.setDouble(_kSigma, trailSigmaDeg);
  }

  WindSettings copyWith({
    int?    trailWindowMinutes,
    double? trailHalfLifeSec,
    double? trailSigmaDeg,
  }) {
    return WindSettings(
      trailWindowMinutes: trailWindowMinutes ?? this.trailWindowMinutes,
      trailHalfLifeSec:   trailHalfLifeSec   ?? this.trailHalfLifeSec,
      trailSigmaDeg:      trailSigmaDeg      ?? this.trailSigmaDeg,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class WindSettingsPage extends StatefulWidget {
  const WindSettingsPage({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onClearTrail,
  });

  final WindSettings settings;
  final ValueChanged<WindSettings> onChanged;
  final VoidCallback onClearTrail;

  @override
  State<WindSettingsPage> createState() => _WindSettingsPageState();
}

class _WindSettingsPageState extends State<WindSettingsPage> {
  late WindSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(WindSettings updated) {
    setState(() => _settings = updated);
    widget.onChanged(updated);
    updated.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xfff5f7fb),
        title: const Text(
          'Wind Settings',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Color(0xff000000),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ── Trail ──────────────────────────────────────────────────────────
          const _SectionHeader('Trail'),
          _SettingsCard(
            children: [
              _SegmentRow<int>(
                label: 'Window',
                subtitle: 'How far back the trail shows',
                value: _settings.trailWindowMinutes,
                options: const [1, 2, 5, 10, 15],
                labels: const ['1 min', '2 min', '5 min', '10 min', '15 min'],
                onChanged: (v) =>
                    _update(_settings.copyWith(trailWindowMinutes: v)),
              ),
              const _Divider(),
              _SegmentRow<double>(
                label: 'Fade speed',
                subtitle: 'How quickly old angles fade out',
                value: _settings.trailHalfLifeSec,
                options: const [30.0, 60.0, 120.0],
                labels: const ['Fast', 'Normal', 'Slow'],
                onChanged: (v) =>
                    _update(_settings.copyWith(trailHalfLifeSec: v)),
              ),
              const _Divider(),
              _SegmentRow<double>(
                label: 'Smoothing',
                subtitle: 'Trail edge softness',
                value: _settings.trailSigmaDeg,
                options: const [0.5, 1.0, 2.0, 4.0],
                labels: const ['Very Sharp', 'Sharp', 'Medium', 'Soft'],
                onChanged: (v) =>
                    _update(_settings.copyWith(trailSigmaDeg: v)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Data ───────────────────────────────────────────────────────────
          const _SectionHeader('Data'),
          _SettingsCard(
            children: [
              _ActionTile(
                icon: Icons.delete_sweep_rounded,
                iconColor: const Color(0xffef4444),
                iconBg: const Color(0xfffef2f2),
                title: 'Clear trail data',
                subtitle: 'Erases the recorded angle history',
                titleColor: const Color(0xffef4444),
                onTap: () {
                  widget.onClearTrail();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Trail data cleared'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Color(0xff94a3b8),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffe2e8f0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0a000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Color(0xffe2e8f0),
    );
  }
}

class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.labels,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final T value;
  final List<T> options;
  final List<String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xff1e293b),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xff94a3b8)),
          ),
          const SizedBox(height: 10),
          _SegmentControl<T>(
            value: value,
            options: options,
            labels: labels,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SegmentControl<T> extends StatelessWidget {
  const _SegmentControl({
    required this.value,
    required this.options,
    required this.labels,
    required this.onChanged,
  });

  final T value;
  final List<T> options;
  final List<String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xfff1f5f9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffe2e8f0)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(options.length, (i) {
          final selected = options[i] == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(options[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: selected
                      ? const [
                          BoxShadow(
                            color: Color(0x1a000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? const Color(0xff0ea5e9)
                        : const Color(0xff64748b),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor = const Color(0xff1e293b),
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color titleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: titleColor,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Color(0xff94a3b8)),
      ),
      onTap: onTap,
    );
  }
}
