import 'dart:math' as math;

/// Sunrise/sunset for one calendar day at a given position. All times are
/// UTC. When the sun never sets or never rises (polar day/night), [sunrise]
/// and [sunset] are null and [alwaysUp]/[alwaysDown] indicate which.
class SunTimes {
  const SunTimes({
    this.sunrise,
    this.sunset,
    this.alwaysUp = false,
    this.alwaysDown = false,
  });

  final DateTime? sunrise;
  final DateTime? sunset;
  final bool alwaysUp;
  final bool alwaysDown;
}

/// Computes local sunrise/sunset from latitude/longitude/date alone — no
/// network access, matching how a standalone chartplotter does it. Based on
/// the NOAA Solar Calculator formulas (NOAA Global Monitoring Laboratory,
/// a US government work, itself derived from Meeus, "Astronomical
/// Algorithms"), accurate to within about a minute — far tighter than this
/// app needs, since it only decides which side of sunrise/sunset "now" is.
class SunCalculator {
  SunCalculator._();

  static const double _zenith = 90.833; // includes atmospheric refraction + solar radius

  /// [date] may be any time on the day of interest; only its UTC
  /// year/month/day are used. [latitude]/[longitude] in degrees, longitude
  /// positive east.
  static SunTimes calculate({
    required double latitude,
    required double longitude,
    required DateTime date,
  }) {
    final utc = date.toUtc();
    final noon = DateTime.utc(utc.year, utc.month, utc.day, 12);
    final jd = _julianDay(noon);
    final t = (jd - 2451545.0) / 36525.0;

    final l0 = _normalizeDeg(280.46646 + t * (36000.76983 + t * 0.0003032));
    final m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
    final e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    final mRad = _deg2rad(m);
    final c = math.sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        math.sin(2 * mRad) * (0.019993 - 0.000101 * t) +
        math.sin(3 * mRad) * 0.000289;
    final trueLong = l0 + c;
    final omega = 125.04 - 1934.136 * t;
    final appLong = trueLong - 0.00569 - 0.00478 * math.sin(_deg2rad(omega));

    final meanObliq =
        23.0 + (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0;
    final obliqCorr = meanObliq + 0.00256 * math.cos(_deg2rad(omega));

    final declRad = math.asin(
      math.sin(_deg2rad(obliqCorr)) * math.sin(_deg2rad(appLong)),
    );

    final y = math.tan(_deg2rad(obliqCorr) / 2) * math.tan(_deg2rad(obliqCorr) / 2);
    final eqTimeMin = 4 *
        _rad2deg(
          y * math.sin(2 * _deg2rad(l0)) -
              2 * e * math.sin(mRad) +
              4 * e * y * math.sin(mRad) * math.cos(2 * _deg2rad(l0)) -
              0.5 * y * y * math.sin(4 * _deg2rad(l0)) -
              1.25 * e * e * math.sin(2 * mRad),
        );

    final latRad = _deg2rad(latitude);
    final cosHourAngle = (math.cos(_deg2rad(_zenith)) /
            (math.cos(latRad) * math.cos(declRad))) -
        math.tan(latRad) * math.tan(declRad);

    if (cosHourAngle > 1) {
      // Sun never rises above the refraction-corrected horizon this day.
      return const SunTimes(alwaysDown: true);
    }
    if (cosHourAngle < -1) {
      // Sun never sets this day.
      return const SunTimes(alwaysUp: true);
    }

    final hourAngleDeg = _rad2deg(math.acos(cosHourAngle));
    final solarNoonMin = 720 - 4 * longitude - eqTimeMin;
    final sunriseMin = solarNoonMin - 4 * hourAngleDeg;
    final sunsetMin = solarNoonMin + 4 * hourAngleDeg;

    return SunTimes(
      sunrise: _minutesToUtc(noon, sunriseMin),
      sunset: _minutesToUtc(noon, sunsetMin),
    );
  }

  static DateTime _minutesToUtc(DateTime dayNoonUtc, double minutesFromMidnight) {
    final midnight = DateTime.utc(dayNoonUtc.year, dayNoonUtc.month, dayNoonUtc.day);
    return midnight.add(
      Duration(microseconds: (minutesFromMidnight * Duration.microsecondsPerMinute).round()),
    );
  }

  static double _julianDay(DateTime utc) {
    // Julian day number at the given UTC instant.
    return utc.millisecondsSinceEpoch / 86400000.0 + 2440587.5;
  }

  static double _deg2rad(double deg) => deg * math.pi / 180.0;
  static double _rad2deg(double rad) => rad * 180.0 / math.pi;

  static double _normalizeDeg(double deg) {
    final r = deg % 360.0;
    return r < 0 ? r + 360.0 : r;
  }
}
