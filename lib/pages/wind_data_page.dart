import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/ble_controller.dart';
import '../models/n2k_device_info.dart';
import '../services/node_settings_service.dart';
import '../services/wind_angle_history_service.dart';
import '../services/wind_averages_service.dart';
import '../widgets/wind_gauge.dart';
import 'node_settings_page.dart';
import 'wind_settings_page.dart';

class WindDataPage extends StatefulWidget {
  const WindDataPage({
    super.key,
    required this.telemetryController,
    required this.windAngleHistory,
    this.device,
    this.hasNavigationDevice = false,
    this.windAverages,
    this.settingsService,
    this.primaryActionLabel,
    this.onPrimaryAction,
  });

  final BleController telemetryController;
  final WindAngleHistoryService windAngleHistory;
  final N2kDeviceInfo? device;
  final bool hasNavigationDevice;
  final WindAveragesService? windAverages;
  final NodeSettingsService? settingsService;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  @override
  State<WindDataPage> createState() => _WindDataPageState();
}

enum _SogUnit { kn, kmh, ms }

class _WindDataPageState extends State<WindDataPage> {
  // Knots by default — matches SOG's default below and the dashboard
  // tiles' unit order. The sensor's own m/s reading is still one tap away.
  bool _showWindSpeedInKnots = true;
  bool _showHeatmap = false;
  static const _kTrailKey = 'wind_trail_enabled';
  WindSettings _windSettings = const WindSettings();
  _SogUnit _sogUnit = _SogUnit.kn;
  // false = sailing convention (0–180° P/S), true = absolute 0–360°.
  bool _showAngleAsCompass = false;
  final PageController _pageController = PageController();
  int _selectedPage = 0;

  // Angle history is logged app-wide (see `AppDependencies.standard()`) so
  // the trail keeps accumulating regardless of which page is open; this page
  // just queries the currently selected window on each rebuild.
  Duration get _historyWindow =>
      Duration(minutes: _windSettings.trailWindowMinutes);

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final trailOn = prefs.getBool(_kTrailKey) ?? false;
    final settings = await WindSettings.load();
    setState(() {
      _showHeatmap = trailOn;
      _windSettings = settings;
    });
  }

  void _clearTrailData() {
    widget.windAngleHistory.clear();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WindSettingsPage(
          settings: _windSettings,
          onChanged: (updated) {
            setState(() => _windSettings = updated);
          },
          onClearTrail: _clearTrailData,
        ),
      ),
    );
  }

  void _openNodeSettings() {
    final device = widget.device;
    final settingsService = widget.settingsService;
    if (device == null || settingsService == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NodeSettingsPage(
          device: device,
          settingsService: settingsService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleWindSpeedUnit() {
    setState(() {
      _showWindSpeedInKnots = !_showWindSpeedInKnots;
    });
  }

  void _toggleAngleUnit() {
    setState(() {
      _showAngleAsCompass = !_showAngleAsCompass;
    });
  }

  void _toggleHeatmap() {
    setState(() {
      _showHeatmap = !_showHeatmap;
    });
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_kTrailKey, _showHeatmap));
  }

  void _toggleSogUnit() {
    setState(() {
      _sogUnit = _SogUnit.values[(_sogUnit.index + 1) % _SogUnit.values.length];
    });
  }

  String? _formatSog(double? ms) {
    if (ms == null) return null;
    return switch (_sogUnit) {
      _SogUnit.kn  => '${(ms * 1.94384).toStringAsFixed(1)} kn',
      _SogUnit.kmh => '${(ms * 3.6).toStringAsFixed(1)} km/h',
      _SogUnit.ms  => '${ms.toStringAsFixed(1)} m/s',
    };
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final settingsService = widget.settingsService;
    final hasNodeSettings = device != null && settingsService != null;
    final overrideName = hasNodeSettings
        ? settingsService.forDevice(device).customName
        : null;
    final title = (overrideName != null && overrideName.trim().isNotEmpty)
        ? overrideName
        : (device == null ? 'Wind Data' : 'Wind Device');
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xfff5f7fb),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Color(0xff000000),
          ),
        ),
        actions: [
          if (hasNodeSettings)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Device settings',
              onPressed: _openNodeSettings,
            ),
          // Wind-specific trail/averaging settings — always visible.
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Color(0xff64748b)),
            tooltip: 'Wind settings',
            onPressed: _openSettings,
          ),
          // Heatmap toggle is only meaningful on the gauge pages, not on
          // the Averages/Statistics page.
          if (_selectedPage < (widget.hasNavigationDevice ? 2 : 1))
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _HeatmapToggleButton(
                  active: _showHeatmap,
                  onTap: _toggleHeatmap,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            widget.telemetryController,
            widget.windAngleHistory,
            if (widget.windAverages != null) widget.windAverages!,
          ]),
          builder: (context, _) {
            final telemetry = widget.telemetryController.telemetry;
            final windSpeed = telemetry.effectiveTrueWindSpeedMs;
            final windAngle = telemetry.effectiveTrueWindAngleDeg;
            final apparentWindSpeed = telemetry.apparentWindSpeedMs;
            final apparentWindAngle = telemetry.apparentWindAngleDeg;
            final pageCount = 1 +
                (widget.hasNavigationDevice ? 1 : 0) +
                (widget.windAverages != null ? 1 : 0);

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() {
                          _selectedPage = index;
                        });
                      },
                      children: [
                        _WindModeView(
                          title: 'Apparent wind',
                          speedLabel: 'AWS',
                          speedValue: _formatWindSpeed(apparentWindSpeed),
                          angleDeg: apparentWindAngle,
                          sogValue: _formatSog(
                            widget.hasNavigationDevice ? telemetry.sogMs : null,
                          ),
                          onSogTap: _toggleSogUnit,
                          onSpeedTap: _toggleWindSpeedUnit,
                          showAngleAsCompass: _showAngleAsCompass,
                          onAngleTap: _toggleAngleUnit,
                          missingDataMessage: _apparentWindMissingMessage(
                            telemetry.apparentWindSpeedMs,
                          ),
                          history: widget.windAngleHistory
                              .apparentHistory(_historyWindow),
                          showHeatmap: _showHeatmap,
                          onHeatmapToggle: _toggleHeatmap,
                          trailHalfLifeSec: _windSettings.trailHalfLifeSec,
                          trailSigmaDeg: _windSettings.trailSigmaDeg,
                        ),
                        if (widget.hasNavigationDevice)
                          _WindModeView(
                            title: 'True wind',
                            speedLabel: 'TWS',
                            speedValue: _formatWindSpeed(windSpeed),
                            angleDeg: windAngle,
                            sogValue: _formatSog(telemetry.sogMs),
                            onSogTap: _toggleSogUnit,
                            onSpeedTap: _toggleWindSpeedUnit,
                            showAngleAsCompass: _showAngleAsCompass,
                            onAngleTap: _toggleAngleUnit,
                            missingDataMessage: _trueWindMissingMessage(
                              telemetry.effectiveTrueWindSpeedMs,
                            ),
                            history:
                                widget.windAngleHistory.trueHistory(_historyWindow),
                            showHeatmap: _showHeatmap,
                            onHeatmapToggle: _toggleHeatmap,
                            trailHalfLifeSec: _windSettings.trailHalfLifeSec,
                            trailSigmaDeg: _windSettings.trailSigmaDeg,
                          ),
                        if (widget.windAverages != null)
                          _WindAveragesView(
                            averages: widget.windAverages!,
                            showKnots: _showWindSpeedInKnots,
                            onUnitTap: _toggleWindSpeedUnit,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (pageCount > 1)
                    _WindPagerIndicator(
                      activeIndex: _selectedPage,
                      count: pageCount,
                    ),
                  if (widget.primaryActionLabel != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: widget.onPrimaryAction,
                        child: Text(widget.primaryActionLabel!),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String? _apparentWindMissingMessage(double? apparentWindSpeed) {
    if (apparentWindSpeed == null) return 'Waiting for wind sensor';
    return null;
  }

  String? _trueWindMissingMessage(double? effectiveTws) {
    if (effectiveTws == null) return 'Waiting for wind sensor and SOG';
    return null;
  }

  String _formatWindSpeed(double? speedMps) {
    if (speedMps == null) {
      return '--';
    }

    if (_showWindSpeedInKnots) {
      final speedKnots = speedMps * 1.94384;
      return '${speedKnots.toStringAsFixed(1)} kn';
    }

    return '${speedMps.toStringAsFixed(1)} m/s';
  }
}

class _WindModeView extends StatelessWidget {
  const _WindModeView({
    required this.title,
    required this.speedLabel,
    required this.speedValue,
    required this.angleDeg,
    this.sogValue,
    this.onSogTap,
    this.onSpeedTap,
    this.showAngleAsCompass = false,
    this.onAngleTap,
    this.missingDataMessage,
    this.history = const [],
    this.showHeatmap = false,
    this.onHeatmapToggle,
    this.trailHalfLifeSec = 60.0,
    this.trailSigmaDeg = 2.0,
  });

  final String title;
  final String speedLabel;
  final String speedValue;
  final double? angleDeg;
  final String? sogValue;
  final VoidCallback? onSogTap;
  final VoidCallback? onSpeedTap;
  final bool showAngleAsCompass;
  final VoidCallback? onAngleTap;
  final String? missingDataMessage;
  final List<AngleSample> history;
  final bool showHeatmap;
  final VoidCallback? onHeatmapToggle;
  final double trailHalfLifeSec;
  final double trailSigmaDeg;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfff9fbff), Color(0xffedf3ff)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xffd9e4ff), width: 1.2),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: Color(0xff111827),
            ),
          ),
          const SizedBox(height: 14),
          const SizedBox(height: 10),
          Expanded(
            child: missingDataMessage != null
                ? Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffffffff),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xffdfe5ef),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sensors_off_rounded,
                            size: 36,
                            color: Color(0xff94a3b8),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            missingDataMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xff64748b),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _WindBoatAngleView(
                    angleDeg: angleDeg,
                    speedLabel: speedLabel,
                    speedValue: speedValue,
                    angleLabel: speedLabel == 'TWS' ? 'TWA' : 'AWA',
                    sogValue: sogValue,
                    onSogTap: onSogTap,
                    onSpeedTap: onSpeedTap,
                    showAngleAsCompass: showAngleAsCompass,
                    onAngleTap: onAngleTap,
                    history: history,
                    showHeatmap: showHeatmap,
                    onHeatmapToggle: onHeatmapToggle,
                    trailHalfLifeSec: trailHalfLifeSec,
                    trailSigmaDeg: trailSigmaDeg,
                  ),
          ),
        ],
      ),
    );
  }
}

class _WindBoatAngleView extends StatelessWidget {
  const _WindBoatAngleView({
    required this.angleDeg,
    required this.speedLabel,
    required this.speedValue,
    required this.angleLabel,
    this.sogValue,
    this.onSogTap,
    this.onSpeedTap,
    this.showAngleAsCompass = false,
    this.onAngleTap,
    this.history = const [],
    this.showHeatmap = false,
    this.onHeatmapToggle,
    this.trailHalfLifeSec = 60.0,
    this.trailSigmaDeg = 2.0,
  });

  final double? angleDeg;
  final String speedLabel;
  final String speedValue;
  final String angleLabel;
  final String? sogValue;
  final VoidCallback? onSogTap;
  final VoidCallback? onSpeedTap;
  final bool showAngleAsCompass;
  final VoidCallback? onAngleTap;
  final List<AngleSample> history;
  final bool showHeatmap;
  final VoidCallback? onHeatmapToggle;
  final double trailHalfLifeSec;
  final double trailSigmaDeg;

  Widget _valueText(String value) {
    return Text(
      value,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: Color(0xff1e293b),
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _pill(String label, Widget value, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xffffffff),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xffc7d2fe), width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xff64748b),
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 72),
              child: Center(child: value),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: WindGauge(
                  angleDeg: angleDeg,
                  history: history,
                  showHeatmap: showHeatmap,
                  trailHalfLifeSec: trailHalfLifeSec,
                  trailSigmaDeg: trailSigmaDeg,
                ),
              ),
              // Heatmap toggle has been moved to the page AppBar so it does
              // not crowd the gauge — `onHeatmapToggle` is kept for callers
              // but no longer rendered here.
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pill(speedLabel, _valueText(speedValue), onTap: onSpeedTap),
            const SizedBox(width: 8),
            _pill(
              angleLabel,
              _AnimatedAngleText(
                angleDeg: angleDeg,
                asCompass: showAngleAsCompass,
              ),
              onTap: onAngleTap,
            ),
          ],
        ),
        if (sogValue != null) ...[
          const SizedBox(height: 8),
          _pill('SOG', _valueText(sogValue!), onTap: onSogTap),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Small pill button shown over the gauge that toggles the angle heatmap.
class _HeatmapToggleButton extends StatelessWidget {
  const _HeatmapToggleButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xff0ea5e9) : const Color(0xffffffff),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? const Color(0xff0ea5e9)
                : const Color(0xffc7d2fe),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.donut_small_rounded,
              size: 14,
              color: active ? Colors.white : const Color(0xff64748b),
            ),
            const SizedBox(width: 4),
            Text(
              'Trail',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : const Color(0xff64748b),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedAngleText extends StatefulWidget {
  const _AnimatedAngleText({
    required this.angleDeg,
    this.asCompass = false,
  });

  final double? angleDeg;
  final bool asCompass;

  @override
  State<_AnimatedAngleText> createState() => _AnimatedAngleTextState();
}

class _AnimatedAngleTextState extends State<_AnimatedAngleText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _displayAngle = 0;

  @override
  void initState() {
    super.initState();
    _displayAngle = widget.angleDeg ?? 0;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = AlwaysStoppedAnimation(_displayAngle);
  }

  @override
  void didUpdateWidget(_AnimatedAngleText oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newAngle = widget.angleDeg;
    if (newAngle == null || newAngle == oldWidget.angleDeg) return;

    // Use the current visual position so interrupted animations don't jump.
    final current = _animation.value;
    // Shortest-arc delta in O(1): bring into (-360,360) then clamp to [-180,180].
    var delta = (newAngle - current) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    final target = current + delta;

    _animation = Tween<double>(begin: current, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _displayAngle = target;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.angleDeg == null) {
      return const Text(
        '--',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xff1e293b),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        var normalized = _animation.value % 360;
        if (normalized < 0) normalized += 360;
        final String label;
        if (widget.asCompass) {
          // Absolute 0–360° form (0° = dead ahead, increasing clockwise).
          final v = normalized.round() % 360;
          label = '$v°';
        } else {
          // Sailing convention: 0–180° S / 0–180° P.
          // 0° = dead ahead, 180° = dead astern (no suffix needed).
          if (normalized < 0.5 || normalized >= 359.5) {
            label = '0°';
          } else if ((normalized - 180).abs() < 0.5) {
            label = '180°';
          } else if (normalized < 180) {
            label = '${normalized.round()}° S';
          } else {
            label = '${(360 - normalized).round()}° P';
          }
        }
        return Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xff1e293b),
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

class _WindPagerIndicator extends StatelessWidget {
  const _WindPagerIndicator({
    required this.activeIndex,
    this.count = 2,
  });

  final int activeIndex;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (index) {
        final isActive = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xff0ea5e9) : const Color(0xffcbd5e1),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

// ── Wind Averages page ───────────────────────────────────────────────────────

class _WindAveragesView extends StatelessWidget {
  const _WindAveragesView({
    required this.averages,
    required this.showKnots,
    this.onUnitTap,
  });

  final WindAveragesService averages;
  final bool showKnots;
  final VoidCallback? onUnitTap;

  // ── Formatting helpers ──────────────────────────────────────────────────

  String _fmt(double? mps) {
    if (mps == null) return '--';
    if (showKnots) return '${(mps * 1.94384).toStringAsFixed(1)} kn';
    return '${mps.toStringAsFixed(1)} m/s';
  }

  String _fmtVmg(double? mps) {
    if (mps == null) return '--';
    final kn = mps * 1.94384;
    return '${kn >= 0 ? '+' : ''}${kn.toStringAsFixed(1)} kn';
  }

  String _fmtSog(double? mps) {
    if (mps == null) return '--';
    return '${(mps * 1.94384).toStringAsFixed(1)} kn';
  }

  String _fmtDeg(double? deg) {
    if (deg == null) return '--';
    return '${deg.toStringAsFixed(0)}°';
  }

  String _fmtPct(double? f) {
    if (f == null) return '--';
    return '${(f * 100).toStringAsFixed(0)}%';
  }

  String _fmtGustFactor(double? g) {
    if (g == null) return '--';
    return g.toStringAsFixed(2);
  }

  String _fmtDistance(double nm) {
    if (nm < 0.1) return '${(nm * 1852).toStringAsFixed(0)} m';
    return '${nm.toStringAsFixed(2)} nm';
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _fmtAge(DateTime t) {
    final age = DateTime.now().difference(t);
    if (age.inSeconds < 60) return '${age.inSeconds}s ago';
    if (age.inMinutes < 60) return '${age.inMinutes}m ago';
    if (age.inHours < 24) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }

  String _spanLabel(Duration span) {
    if (span.inSeconds < 60) return '${span.inSeconds}s of data';
    if (span.inMinutes < 60) return '${span.inMinutes} min of data';
    return '${span.inHours}h ${span.inMinutes % 60}min of data';
  }

  // ── Compass label (N/NE/E/...) for a TWD bearing ────────────────────────
  String _compass(double? deg) {
    if (deg == null) return '--';
    const dirs = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                  'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    var d = deg % 360;
    if (d < 0) d += 360;
    final idx = ((d / 22.5) + 0.5).floor() % 16;
    return '${dirs[idx]} ${d.toStringAsFixed(0)}°';
  }

  // ── Build ───────────────────────────────────────────────────────────────

  static const _windowsShort = [
    (Duration(seconds: 60), '1m'),
    (Duration(minutes: 5), '5m'),
    (Duration(minutes: 30), '30m'),
    (Duration(hours: 1), '1h'),
  ];
  static const _windowsLong = [
    (Duration(hours: 1), '1h'),
    (Duration(hours: 6), '6h'),
    (Duration(hours: 24), '24h'),
  ];

  @override
  Widget build(BuildContext context) {
    final span = averages.collectionSpan;
    final unitLabel = showKnots ? 'kn' : 'm/s';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xfff9fbff), Color(0xffedf3ff)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xffd9e4ff), width: 1.2),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(
            children: [
              const Text(
                'Statistics',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xff111827),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onUnitTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xffc7d2fe)),
                  ),
                  child: Text(
                    unitLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xff3b82f6),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            span.inSeconds < 2 ? 'Collecting data...' : _spanLabel(span),
            style: const TextStyle(fontSize: 12, color: Color(0xff94a3b8)),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildNowSection(),
                  const SizedBox(height: 10),
                  _buildShortStatsCard(
                    title: 'Wind Speed (TWS)',
                    statsFn: averages.twsStats,
                    formatter: _fmt,
                    accent: const Color(0xff0ea5e9),
                  ),
                  const SizedBox(height: 10),
                  _buildShortStatsCard(
                    title: 'Apparent Wind (AWS)',
                    statsFn: averages.awsStats,
                    formatter: _fmt,
                    accent: const Color(0xff14b8a6),
                  ),
                  const SizedBox(height: 10),
                  _buildDirectionCard(),
                  const SizedBox(height: 10),
                  _buildSogVmgCard(),
                  const SizedBox(height: 10),
                  _buildLongTermCard(),
                  const SizedBox(height: 10),
                  _buildSessionCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section: Now ────────────────────────────────────────────────────────

  Widget _buildNowSection() {
    final tws = averages.currentTwsMs;
    final aws = averages.currentAwsMs;
    final sog = averages.currentSogMs;
    final vmg = averages.currentVmgMs;
    final beaufortLabel = averages.beaufortLabel;
    final beaufort = averages.beaufort;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Now', accent: const Color(0xff0f172a)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _bigStat('TWS', _fmt(tws))),
              Expanded(child: _bigStat('AWS', _fmt(aws))),
              Expanded(child: _bigStat('SOG', _fmtSog(sog))),
              Expanded(
                child: _bigStat(
                  'VMG',
                  _fmtVmg(vmg),
                  color: vmg == null
                      ? const Color(0xff94a3b8)
                      : vmg >= 0
                          ? const Color(0xff16a34a)
                          : const Color(0xffdc2626),
                ),
              ),
            ],
          ),
          if (beaufortLabel != null) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xfff1f5f9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.air_rounded,
                      size: 16, color: Color(0xff64748b)),
                  const SizedBox(width: 6),
                  Text(
                    'Force $beaufort — $beaufortLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff334155),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Section: short-window stats card (TWS / AWS) ────────────────────────

  Widget _buildShortStatsCard({
    required String title,
    required WindWindowStats Function(Duration) statsFn,
    required String Function(double?) formatter,
    required Color accent,
  }) {
    final stats = [for (final w in _windowsShort) statsFn(w.$1)];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(title, accent: accent),
          const SizedBox(height: 8),
          // Header
          _statsRow(
            label: '',
            cells: [for (final w in _windowsShort) w.$2],
            isHeader: true,
          ),
          const SizedBox(height: 4),
          _statsRow(
            label: 'Avg',
            cells: [for (final s in stats) formatter(s.average)],
          ),
          _statsRow(
            label: 'Min',
            cells: [for (final s in stats) formatter(s.min)],
            subtle: true,
          ),
          _statsRow(
            label: 'Max',
            cells: [for (final s in stats) formatter(s.max)],
            highlight: true,
          ),
          _statsRow(
            label: 'Gust f.',
            cells: [for (final s in stats) _fmtGustFactor(s.gustFactor)],
            subtle: true,
          ),
        ],
      ),
    );
  }

  // ── Section: Wind Direction (TWD) ───────────────────────────────────────

  Widget _buildDirectionCard() {
    final w5 = averages.directionStats(const Duration(minutes: 5));
    final w30 = averages.directionStats(const Duration(minutes: 30));
    final w60 = averages.directionStats(const Duration(hours: 1));

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(
            'Wind Direction (TWD, where wind blows from)',
            accent: const Color(0xff8b5cf6),
          ),
          const SizedBox(height: 8),
          _statsRow(
            label: '',
            cells: const ['5m', '30m', '1h'],
            isHeader: true,
          ),
          const SizedBox(height: 4),
          _statsRow(
            label: 'Mean',
            cells: [_compass(w5.meanDeg), _compass(w30.meanDeg), _compass(w60.meanDeg)],
          ),
          _statsRow(
            label: 'Steady',
            cells: [_fmtPct(w5.steadiness), _fmtPct(w30.steadiness), _fmtPct(w60.steadiness)],
            subtle: true,
          ),
          _statsRow(
            label: 'Swing',
            cells: [_fmtDeg(w5.oscillationDeg), _fmtDeg(w30.oscillationDeg), _fmtDeg(w60.oscillationDeg)],
            subtle: true,
          ),
          // Trend hint: compare 1m mean direction (raw current) to 5m mean.
          // A persistent offset is a "lift" or "header" depending on tack.
          _buildTrendHint(w5),
        ],
      ),
    );
  }

  Widget _buildTrendHint(WindDirectionStats w5) {
    final w1 = averages.directionStats(const Duration(seconds: 60));
    if (w1.meanDeg == null || w5.meanDeg == null) {
      return const SizedBox.shrink();
    }
    var delta = (w1.meanDeg! - w5.meanDeg!) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    if (delta.abs() < 3) return const SizedBox.shrink();

    final shift = delta > 0 ? 'right' : 'left';
    final magnitude = delta.abs().toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xfff5f3ff),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xffe9d5ff)),
        ),
        child: Row(
          children: [
            Icon(
              delta > 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              size: 16,
              color: const Color(0xff7c3aed),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Wind shifted $magnitude° to the $shift in last minute vs 5-min mean',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xff5b21b6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section: SOG / VMG ──────────────────────────────────────────────────

  Widget _buildSogVmgCard() {
    final sog5 = averages.sogStats(const Duration(minutes: 5));
    final sog30 = averages.sogStats(const Duration(minutes: 30));
    final sog60 = averages.sogStats(const Duration(hours: 1));
    final vmg5 = averages.vmgStats(const Duration(minutes: 5));
    final vmg30 = averages.vmgStats(const Duration(minutes: 30));
    final vmg60 = averages.vmgStats(const Duration(hours: 1));

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Boat Speed & VMG', accent: const Color(0xff16a34a)),
          const SizedBox(height: 8),
          _statsRow(
            label: '',
            cells: const ['5m', '30m', '1h'],
            isHeader: true,
          ),
          const SizedBox(height: 4),
          _statsRow(
            label: 'SOG avg',
            cells: [_fmtSog(sog5.average), _fmtSog(sog30.average), _fmtSog(sog60.average)],
          ),
          _statsRow(
            label: 'SOG max',
            cells: [_fmtSog(sog5.max), _fmtSog(sog30.max), _fmtSog(sog60.max)],
            highlight: true,
          ),
          _statsRow(
            label: 'VMG avg',
            cells: [_fmtVmg(vmg5.average), _fmtVmg(vmg30.average), _fmtVmg(vmg60.average)],
          ),
          _statsRow(
            label: 'VMG up',
            cells: [_fmtVmg(vmg5.max), _fmtVmg(vmg30.max), _fmtVmg(vmg60.max)],
            subtle: true,
          ),
          _statsRow(
            label: 'VMG dn',
            cells: [_fmtVmg(vmg5.min), _fmtVmg(vmg30.min), _fmtVmg(vmg60.min)],
            subtle: true,
          ),
        ],
      ),
    );
  }

  // ── Section: long-term (6h / 24h) ───────────────────────────────────────

  Widget _buildLongTermCard() {
    final twsStats = [for (final w in _windowsLong) averages.twsStats(w.$1)];
    final sogStats = [for (final w in _windowsLong) averages.sogStats(w.$1)];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Long Term', accent: const Color(0xfff59e0b)),
          const SizedBox(height: 8),
          _statsRow(
            label: '',
            cells: [for (final w in _windowsLong) w.$2],
            isHeader: true,
          ),
          const SizedBox(height: 4),
          _statsRow(
            label: 'TWS avg',
            cells: [for (final s in twsStats) _fmt(s.average)],
          ),
          _statsRow(
            label: 'TWS max',
            cells: [for (final s in twsStats) _fmt(s.max)],
            highlight: true,
          ),
          _statsRow(
            label: 'SOG avg',
            cells: [for (final s in sogStats) _fmtSog(s.average)],
          ),
          _statsRow(
            label: 'SOG max',
            cells: [for (final s in sogStats) _fmtSog(s.max)],
            subtle: true,
          ),
        ],
      ),
    );
  }

  // ── Section: session totals ─────────────────────────────────────────────

  Widget _buildSessionCard() {
    final peak = averages.peakTwsMs;
    final peakAt = averages.peakTwsAt;
    final gustiness = averages.peakTwsGustinessAtPeak;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Session', accent: const Color(0xfff43f5e)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _bigStat(
                  'Tacks',
                  '${averages.tackCount}',
                ),
              ),
              Expanded(
                child: _bigStat(
                  'Distance',
                  _fmtDistance(averages.distanceNm),
                ),
              ),
              Expanded(
                child: _bigStat(
                  'Duration',
                  _fmtDuration(averages.sessionDuration),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xfffef2f2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xfffecaca)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded,
                    size: 16, color: Color(0xffdc2626)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    peak == null
                        ? 'Peak gust: --'
                        : 'Peak gust: ${_fmt(peak)}'
                            '${gustiness != null ? ' (×${gustiness.toStringAsFixed(2)} mean)' : ''}'
                            '${peakAt != null ? ' · ${_fmtAge(peakAt)}' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xff991b1b),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable widgets ────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffdfe5ef)),
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text, {required Color accent}) {
    return Row(
      children: [
        Container(width: 4, height: 14, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xff0f172a),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bigStat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xff94a3b8),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: color ?? const Color(0xff0f172a),
          ),
        ),
      ],
    );
  }

  Widget _statsRow({
    required String label,
    required List<String> cells,
    bool isHeader = false,
    bool highlight = false,
    bool subtle = false,
  }) {
    final TextStyle valueStyle;
    if (isHeader) {
      valueStyle = const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xff94a3b8),
        letterSpacing: 0.4,
      );
    } else if (highlight) {
      valueStyle = const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xffdc2626),
      );
    } else if (subtle) {
      valueStyle = const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xff64748b),
      );
    } else {
      valueStyle = const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xff0f172a),
      );
    }
    final labelStyle = isHeader
        ? const TextStyle(fontSize: 11, color: Color(0xff94a3b8))
        : const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xff64748b),
            letterSpacing: 0.4,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label.toUpperCase(), style: labelStyle),
          ),
          for (final cell in cells)
            Expanded(child: Center(child: Text(cell, style: valueStyle))),
        ],
      ),
    );
  }
}
