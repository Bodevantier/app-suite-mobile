// NMEA 2000 device class and device function constants,
// and a shared category lookup used across the app.
//
// Device function codes are scoped to their device class — the same number
// means different things in different classes (e.g. 130 = Wind in class 85,
// but also = VHF Radio in class 60). The lookup therefore requires both.
//
// NOTE: For Class 85 (External Environment) the NMEA 2000 standard only
// formally defines Function 130 (Atmospheric) and 140 (Aquatic). The other
// codes below (150/155/160/170/180) are a project-internal convention used
// by our sensors. Categorization based on transmitted PGN evidence (handled
// by N2kDeviceTracker._markLive*) is authoritative; this lookup is only a
// fallback when no live PGN frames have been seen yet.

abstract final class N2kDeviceClass {
  static const int safety            = 20;
  static const int steering          = 30;
  static const int propulsion        = 40;
  static const int navigation        = 50;
  static const int communication     = 60;
  static const int sensor            = 75;
  static const int instrumentation   = 80;
  static const int environmental     = 85;
  static const int electrical        = 90;
}

abstract final class N2kDeviceFunction {
  // Environmental (class 85) ------------------------------------------------
  static const int wind              = 130;
  static const int depth             = 140;
  static const int speed             = 150;
  static const int heading           = 155;
  static const int temperature       = 160;
  static const int humidity          = 170;
  static const int pressure          = 180;

  // Navigation (class 50) ---------------------------------------------------
  static const int gps               = 145;
  static const int echosounder       = 140;
  static const int chartplotter      = 190;

  // Communication (class 60) ------------------------------------------------
  static const int vhfRadio          = 130;
  static const int aisClassA         = 135;
  static const int aisClassB         = 136;
  static const int integratedNavSystem = 185;
  static const int chartplotterComm  = 205; // seen on Garmin GPSmap 720s
}

/// Returns a human-readable category string for the given NMEA 2000
/// [deviceClass] and [deviceFunction] codes, or `null` when unknown.
///
/// Function codes are interpreted relative to their device class because the
/// same function code number has different meanings in different classes.
String? n2kCategoryFromCodes(int? deviceClass, int? deviceFunction) {
  if (deviceClass == N2kDeviceClass.environmental) {
    switch (deviceFunction) {
      case N2kDeviceFunction.wind:        return 'wind';
      case N2kDeviceFunction.depth:       return 'depth';
      case N2kDeviceFunction.speed:       return 'speed';
      case N2kDeviceFunction.heading:     return 'heading';
      case N2kDeviceFunction.temperature: return 'temperature';
      case N2kDeviceFunction.humidity:    return 'humidity';
      case N2kDeviceFunction.pressure:    return 'pressure';
    }
    return 'environmental';
  }
  if (deviceClass == N2kDeviceClass.navigation) {
    // Navigation class devices (chartplotters, GPS) are always 'navigation'
    return 'navigation';
  }
  if (deviceClass == N2kDeviceClass.communication) {
    switch (deviceFunction) {
      case N2kDeviceFunction.chartplotterComm:    return 'navigation';
      case N2kDeviceFunction.integratedNavSystem: return 'navigation';
    }
    return 'communication';
  }
  switch (deviceClass) {
    case N2kDeviceClass.instrumentation:  return 'instrumentation';
    case N2kDeviceClass.propulsion:       return 'propulsion';
    case N2kDeviceClass.steering:         return 'steering';
    case N2kDeviceClass.safety:           return 'safety';
    case N2kDeviceClass.electrical:       return 'electrical';
    case N2kDeviceClass.sensor:           return 'sensor';
  }
  return null;
}
