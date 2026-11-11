// =============================================================
// sensor_service.dart
// Vlastní počítání kroků z akcelerometru (záložní zdroj kroků).
//
// Princip:
//   1. Z hodnot x, y, z spočítáme celkovou velikost zrychlení.
//   2. Odečteme gravitaci (pomalý low-pass filtr) -> zůstane jen pohyb.
//   3. Vyhladíme šum (druhý low-pass filtr).
//   4. Hledáme "peaky" (lokální maxima nad prahem) -> každý peak = krok.
//   5. Mezi dvěma kroky musí být minimální odstup, aby se jeden krok
//      nepočítal dvakrát.
// =============================================================

import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class StepService {
  // Broadcast stream umožňuje, aby poslouchalo víc posluchačů najednou.
  final _controller = StreamController<int>.broadcast();

  /// Proud, který posílá celkový počet kroků při každém novém kroku.
  Stream<int> get stepStream => _controller.stream;

  StreamSubscription<AccelerometerEvent>? _sub;

  /// Aktuální počet napočítaných kroků.
  int steps = 0;

  // ===== nastavení pro ladění =====

  /// Citlivost v m/s². Menší hodnota = citlivější (víc kroků i falešných).
  double threshold = 1.0;

  /// Minimální odstup mezi dvěma kroky (rychlejší než 300 ms člověk nejde).
  static const _minGap = Duration(milliseconds: 300);

  // ===== vnitřní stav filtrů =====
  double _gravity = 9.8;   // odhad gravitace
  double _smooth = 0;      // vyhlazená dynamická složka zrychlení
  double _prev = 0;        // předchozí vyhlazená hodnota
  double _prev2 = 0;       // hodnota před předchozí (pro hledání peaku)
  DateTime _lastStep = DateTime.fromMillisecondsSinceEpoch(0);

  /// Spustí poslech akcelerometru.
  void start() {
    _sub?.cancel(); // pro jistotu zrušíme případný starý odběr
    _sub = accelerometerEventStream(
      // gameInterval = cca 50 měření za sekundu, na chůzi to stačí
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onEvent);
  }

  /// Zastaví poslech akcelerometru (počet kroků zůstane zachován).
  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Vynuluje počítadlo kroků.
  void reset() {
    steps = 0;
    _controller.add(steps);
  }

  /// Zpracuje jedno měření z akcelerometru.
  void _onEvent(AccelerometerEvent e) {
    // 1) Celková velikost zrychlení (nezávisí na natočení telefonu).
    final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

    // 2) Odhad gravitace pomalým low-pass filtrem a její odečtení.
    //    Zůstane jen zrychlení způsobené pohybem.
    _gravity = 0.98 * _gravity + 0.02 * mag;
    final dyn = mag - _gravity;

    // 3) Vyhlazení šumu rychlejším low-pass filtrem.
    _smooth = 0.7 * _smooth + 0.3 * dyn;

    // 4) Detekce peaku: prostřední hodnota (_prev) je větší než obě sousední
    //    a zároveň překračuje práh citlivosti.
    final now = DateTime.now();
    final isPeak = _prev > _prev2 && _prev > _smooth && _prev > threshold;

    // 5) Peak se počítá jako krok, jen pokud od posledního uplynul minimální čas.
    if (isPeak && now.difference(_lastStep) > _minGap) {
      steps++;
      _lastStep = now;
      _controller.add(steps);
    }

    // Posun hodnot pro další měření.
    _prev2 = _prev;
    _prev = _smooth;
  }

  /// Uvolní zdroje. Volá se při zavření obrazovky.
  void dispose() {
    stop();
    _controller.close();
  }
}
