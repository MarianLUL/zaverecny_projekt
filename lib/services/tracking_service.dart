import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'sensor_service.dart';
import 'pedometer_service.dart';

class TrackingService extends ChangeNotifier {
  TrackingService(this._accel, [this._hw]);
  final StepService _accel;
  final PedometerService? _hw;
  bool preferHardware = true;

  // ===== nastavení (dá se ladit) =====
  static const double maxAccuracyM = 25;           // horší GPS body zahodit
  static const double minSpeedMs = 0.5;            // pod tím = stojím
  static const Duration movingGrace = Duration(seconds: 10);
  static const double minAltChangeM = 2.0;         // hystereze převýšení
  bool requireGps = true;                          // false = počítat kroky i bez GPS
  double heightCm = 175;                           // později z profilu

  // ===== stav =====
  bool running = false;
  bool gpsGood = false;
  bool moving = false;
  int steps = 0;             // ověřené kroky
  int rejectedSteps = 0;     // zahozené kroky (třesení apod.)
  double distanceM = 0;
  double ascentM = 0;
  double descentM = 0;
  double altitudeM = 0;
  double speedKmh = 0;
  Duration movingTime = Duration.zero;
  final List<LatLng> route = [];

  DateTime? _startTime;
  DateTime? _lastMovingAt;
  DateTime? _lastMoveTime;
  LatLng? _lastPoint;
  double? _smoothAlt;
  double? _refAlt;
  int _lastTotal = 0;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<int>? _stepSub;
  Timer? _timer;

  double get distanceKm => distanceM / 1000;
  double get avgSpeedKmh =>
      movingTime.inSeconds > 0 ? distanceM / movingTime.inSeconds * 3.6 : 0;
  Duration get elapsed =>
      _startTime == null ? Duration.zero : DateTime.now().difference(_startTime!);
  double get estimatedDistanceM => steps * heightCm * 0.415 / 100;

  /// Vrací text chyby, nebo null když vše proběhlo v pořádku.
  Future<String?> start() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Zapni polohu (GPS) v telefonu';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return 'Chybí oprávnění k poloze';
    }

    _resetState();
    _startTime = DateTime.now();
    running = true;

    // kroky z akcelerometru (ověřují se podle GPS)
    _lastTotal = 0;
    preferHardware = false;
if (preferHardware && _hw != null && await _hw!.start()) {
  _hw!.reset();
  preferHardware = true;
  _stepSub = _hw!.stepStream.listen(_onStepTotal);
} else {
  _accel.reset();
  _accel.start();
  _stepSub = _accel.stepStream.listen(_onStepTotal);
}
    // GPS
    final  settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
      intervalDuration: Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'StepSense',
        notificationText: 'Měření aktivity běží',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (_) {
      gpsGood = false;
      notifyListeners();
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
    return null;
  }

  void stop() {
    _posSub?.cancel();
    _stepSub?.cancel();
    _timer?.cancel();
    _accel.stop();
    running = false;
    moving = false;
    notifyListeners();
  }

  void _resetState() {
    steps = 0;
    rejectedSteps = 0;
    distanceM = 0;
    ascentM = 0;
    descentM = 0;
    altitudeM = 0;
    speedKmh = 0;
    movingTime = Duration.zero;
    route.clear();
    _lastPoint = null;
    _lastMoveTime = null;
    _lastMovingAt = null;
    _smoothAlt = null;
    _refAlt = null;
    gpsGood = false;
    moving = false;
  }

  // ===== kroky: počítají se jen při potvrzeném pohybu =====
  void _onStepTotal(int total) {
    final delta = total - _lastTotal;
    _lastTotal = total;
    if (delta <= 0) return;

    final now = DateTime.now();
    final recentlyMoving =
        _lastMovingAt != null && now.difference(_lastMovingAt!) <= movingGrace;

    if (recentlyMoving || !requireGps) {
      steps += delta;
    } else {
      rejectedSteps += delta;
    }
    notifyListeners();
  }

  // ===== GPS =====
  void _onPosition(Position p) {
    final now = DateTime.now();

    if (p.accuracy > maxAccuracyM) {
      gpsGood = false;
      notifyListeners();
      return;
    }
    gpsGood = true;

    final speedMs = p.speed < 0 ? 0.0 : p.speed;
    speedKmh = speedMs * 3.6;
    altitudeM = p.altitude;
    moving = speedMs >= minSpeedMs;

    // vyhlazení nadmořské výšky
    _smoothAlt = _smoothAlt == null
        ? p.altitude
        : 0.8 * _smoothAlt! + 0.2 * p.altitude;

    if (moving) {
      _lastMovingAt = now;
      final here = LatLng(p.latitude, p.longitude);

      if (_lastPoint != null) {
        final d = Geolocator.distanceBetween(
          _lastPoint!.latitude, _lastPoint!.longitude,
          here.latitude, here.longitude,
        );
        if (d >= 1 && d <= 100) distanceM += d; // ignoruj šum a skoky
      }
      if (_lastMoveTime != null) {
        final dt = now.difference(_lastMoveTime!);
        if (dt <= const Duration(seconds: 5)) movingTime += dt;
      }
      _lastPoint = here;
      _lastMoveTime = now;
      if (route.isEmpty || Geolocator.distanceBetween(
          route.last.latitude, route.last.longitude,
          here.latitude, here.longitude,
        ) >= 3) {
  route.add(here);
}

      // převýšení s hysterezí
      _refAlt ??= _smoothAlt;
      final diff = _smoothAlt! - _refAlt!;
      if (diff.abs() >= minAltChangeM) {
        if (diff > 0) {
          ascentM += diff;
        } else {
          descentM += -diff;
        }
        _refAlt = _smoothAlt;
      }
    } else {
      _lastMoveTime = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stepSub?.cancel();
    _timer?.cancel();
    _accel.dispose();
    _hw?.dispose();
    super.dispose();
  }
}