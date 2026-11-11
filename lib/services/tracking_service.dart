// =============================================================
// tracking_service.dart
// Hlavní logika měření aktivity. Spojuje:
//   - kroky (hardwarový krokoměr, záloha akcelerometr),
//   - GPS (poloha, rychlost, nadmořská výška).
//
// Klíčový nápad: KROK SE ZAPOČÍTÁ, JEN KDYŽ GPS POTVRZUJE POHYB.
// Když jen zatřesu mobilem a stojím na místě, GPS hlásí rychlost 0,
// takže se krok zahodí (počítá se do rejectedSteps).
//
// Třída je ChangeNotifier: při každé změně zavolá notifyListeners()
// a obrazovka se sama překreslí.
// =============================================================
 
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'pedometer_service.dart';
import 'sensor_service.dart';
 
class TrackingService extends ChangeNotifier {
  /// [_accel] = akcelerometr (záloha), [_hw] = hardwarový krokoměr (volitelný).
  TrackingService(this._accel, [this._hw]);
  final StepService _accel;
  final PedometerService? _hw;
 
  // ===========================================================
  // NASTAVENÍ (dá se ladit)
  // ===========================================================
 
  /// GPS body s horší přesností (v metrech) zahodíme.
  static const double maxAccuracyM = 25;
 
  /// Rychlost pod touto hranicí (m/s) považujeme za stání.
  static const double minSpeedMs = 0.5;
 
  /// Minimální změna výšky (m), než ji započítáme do převýšení.
  /// Chrání před šumem GPS výšky.
  static const double minAltChangeM = 2.0;
 
  /// Minimální vzdálenost (m) mezi dvěma body trasy.
  /// Chrání před hromaděním bodů, když stojíme.
  static const double minRoutePointM = 3.0;
 
  /// Jak dlouho po posledním potvrzeném pohybu ještě kroky platí.
  /// Hardware hlásí kroky se zpožděním, proto je okno delší.
  Duration get movingGrace => usingHardware
      ? const Duration(seconds: 10)
      : const Duration(seconds: 4);
 
  /// true = kroky se počítají jen při pohybu potvrzeném GPS.
  bool requireGps = true;
 
  /// true = preferovat hardwarový krokoměr, false = vždy akcelerometr.
  /// (Pro test třesení nastav false, hardware třesení ignoruje.)
  bool preferHardware = true;
 
  /// Výška uživatele pro odhad délky kroku. Později z profilu.
  double heightCm = 175;
 
  // ===========================================================
  // STAV (čte ho obrazovka)
  // ===========================================================
 
  bool running = false;       // měření běží
  bool gpsGood = false;       // GPS má dostatečnou přesnost
  bool moving = false;        // GPS hlásí pohyb
  bool usingHardware = false; // zdroj kroků: hardware (true) / akcelerometr (false)
 
  int steps = 0;              // ověřené kroky
  int rejectedSteps = 0;      // zahozené kroky (třesení apod.)
 
  double distanceM = 0;       // ušlá vzdálenost v metrech
  double ascentM = 0;         // nastoupané metry
  double descentM = 0;        // sestoupané metry
  double altitudeM = 0;       // aktuální nadmořská výška
  double speedKmh = 0;        // okamžitá rychlost
  Duration movingTime = Duration.zero; // čistý čas pohybu (bez stání)
 
  /// Body trasy, které se vykreslují na mapě.
  final List<LatLng> route = [];
 
  // ===========================================================
  // VNITŘNÍ PROMĚNNÉ
  // ===========================================================
 
  DateTime? _startTime;     // kdy měření začalo
  DateTime? _lastMovingAt;  // kdy GPS naposledy potvrdilo pohyb
  DateTime? _lastMoveTime;  // čas předchozího GPS bodu při pohybu
  LatLng? _lastPoint;       // předchozí bod pro výpočet vzdálenosti
  double? _smoothAlt;       // vyhlazená nadmořská výška
  double? _refAlt;          // referenční výška pro počítání převýšení
  int _lastTotal = 0;       // poslední celkový počet kroků ze zdroje
 
  StreamSubscription<Position>? _posSub; // odběr GPS
  StreamSubscription<int>? _stepSub;     // odběr kroků
  Timer? _timer;                         // sekundový časovač pro čas na displeji
 
  // ===========================================================
  // VYPOČÍTANÉ HODNOTY
  // ===========================================================
 
  double get distanceKm => distanceM / 1000;
 
  /// Průměrná rychlost = vzdálenost / čas pohybu.
  double get avgSpeedKmh =>
      movingTime.inSeconds > 0 ? distanceM / movingTime.inSeconds * 3.6 : 0;
 
  /// Celkový uplynulý čas od startu.
  Duration get elapsed => _startTime == null
      ? Duration.zero
      : DateTime.now().difference(_startTime!);
 
  /// Odhad vzdálenosti jen z kroků (záloha, když GPS není k dispozici).
  /// Délka kroku ≈ výška × 0,415.
  double get estimatedDistanceM => steps * heightCm * 0.415 / 100;
 
  // ===========================================================
  // START A STOP
  // ===========================================================
 
  /// Spustí měření. Vrací text chyby, nebo null, když vše proběhlo v pořádku.
  Future<String?> start() async {
    // 1) Kontrola, že je v telefonu zapnutá poloha.
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Zapni polohu (GPS) v telefonu';
    }
 
    // 2) Kontrola a vyžádání oprávnění k poloze.
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return 'Chybí oprávnění k poloze';
    }
 
    // 3) Vynulování předchozího měření.
    _resetState();
    _startTime = DateTime.now();
    running = true;
 
    // 4) Výběr zdroje kroků:
    //    hardwarový krokoměr, a když není (nebo chybí oprávnění),
    //    akcelerometr jako záloha.
    _lastTotal = 0;
    usingHardware = false;
    if (preferHardware && _hw != null && await _hw!.start()) {
      _hw!.reset();
      usingHardware = true;
      _stepSub = _hw!.stepStream.listen(_onStepTotal);
    } else {
      _accel.reset();
      _accel.start();
      _stepSub = _accel.stepStream.listen(_onStepTotal);
    }
 
    // 5) Nastavení GPS včetně foreground služby (trvalé upozornění),
    //    díky níž měření běží i se zhasnutou obrazovkou.
    //    Musí být "final", ne "const" (konstruktor není konstantní).
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0, // hlásit každou změnu
      intervalDuration: const Duration(seconds: 1),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'StepSense',
        notificationText: 'Měření aktivity běží',
        enableWakeLock: true, // nedovolí procesoru usnout
        setOngoing: true,     // upozornění nejde smazat přejetím
      ),
    );
 
    _posSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (_) {
      gpsGood = false;
      notifyListeners();
    });
 
    // 6) Každou sekundu překreslit obrazovku (kvůli uplynulému času).
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
 
    notifyListeners();
    return null;
  }
 
  /// Zastaví měření a všechny odběry (ukončí i foreground službu).
  void stop() {
    _posSub?.cancel();
    _stepSub?.cancel();
    _timer?.cancel();
    _accel.stop();
    _hw?.stop();
    running = false;
    moving = false;
    notifyListeners();
  }
 
  /// Vynuluje všechny hodnoty před novým měřením.
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
 
  // ===========================================================
  // KROKY: počítají se jen při potvrzeném pohybu
  // ===========================================================
 
  /// Volá se při každé změně celkového počtu kroků ze zdroje.
  void _onStepTotal(int total) {
    // Kolik kroků přibylo od minula.
    final delta = total - _lastTotal;
    _lastTotal = total;
    if (delta <= 0) return;
 
    // Potvrdilo GPS pohyb v nedávné době?
    final now = DateTime.now();
    final recentlyMoving =
        _lastMovingAt != null && now.difference(_lastMovingAt!) <= movingGrace;
 
    if (recentlyMoving || !requireGps) {
      steps += delta;          // platný krok
    } else {
      rejectedSteps += delta;  // krok bez pohybu podle GPS (třesení)
    }
    notifyListeners();
  }
 
  // ===========================================================
  // GPS: poloha, vzdálenost, rychlost, převýšení, trasa
  // ===========================================================
 
  /// Volá se při každém novém GPS bodu.
  void _onPosition(Position p) {
    final now = DateTime.now();
 
    // Body s nízkou přesností ignorujeme.
    if (p.accuracy > maxAccuracyM) {
      gpsGood = false;
      notifyListeners();
      return;
    }
    gpsGood = true;
 
    // Rychlost (záporná hodnota = neznámá) a stav pohybu.
    final speedMs = p.speed < 0 ? 0.0 : p.speed;
    speedKmh = speedMs * 3.6;
    altitudeM = p.altitude;
    moving = speedMs >= minSpeedMs;
 
    // Vyhlazení nadmořské výšky (exponenciální průměr).
    _smoothAlt = _smoothAlt == null
        ? p.altitude
        : 0.8 * _smoothAlt! + 0.2 * p.altitude;
 
    if (moving) {
      _lastMovingAt = now; // zapamatujeme čas posledního potvrzeného pohybu
      final here = LatLng(p.latitude, p.longitude);
 
      // --- vzdálenost ---
      if (_lastPoint != null) {
        final d = Geolocator.distanceBetween(
          _lastPoint!.latitude, _lastPoint!.longitude,
          here.latitude, here.longitude,
        );
        // Ignorujeme šum (< 1 m) a nesmyslné skoky (> 100 m).
        if (d >= 1 && d <= 100) distanceM += d;
      }
 
      // --- čas pohybu ---
      if (_lastMoveTime != null) {
        final dt = now.difference(_lastMoveTime!);
        if (dt <= const Duration(seconds: 5)) movingTime += dt;
      }
      _lastPoint = here;
      _lastMoveTime = now;
 
      // --- trasa ---
      // Bod přidáme, jen když je trasa prázdná, nebo je nový bod aspoň
      // minRoutePointM od předchozího (jinak vznikají duplicitní body
      // a hrozí chyba "Bad state: No element" v mapě).
      if (route.isEmpty ||
          Geolocator.distanceBetween(
                route.last.latitude, route.last.longitude,
                here.latitude, here.longitude,
              ) >=
              minRoutePointM) {
        route.add(here);
      }
 
      // --- převýšení s hysterezí ---
      // Změnu výšky započítáme až po překročení minAltChangeM.
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
      // Stojíme: přerušíme měření času pohybu.
      _lastMoveTime = null;
    }
    notifyListeners();
  }
 
  /// Uvolní všechny zdroje při zavření obrazovky.
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
 
