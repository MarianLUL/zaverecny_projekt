// =============================================================
// pedometer_service.dart
// Počítání kroků pomocí HARDWAROVÉHO krokoměru v telefonu.
//
// Výhody oproti akcelerometru:
//   - je přesnější, protože má vlastní algoritmus v čipu,
//   - šetří baterii,
//   - funguje i se zhasnutou obrazovkou.
// Nevýhoda: ne každý telefon senzor má.
//
// Potřebuje oprávnění ACTIVITY_RECOGNITION (Physical activity).
// =============================================================

import 'dart:async';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

class PedometerService {
  final _controller = StreamController<int>.broadcast();

  /// Proud s počtem kroků od spuštění měření.
  Stream<int> get stepStream => _controller.stream;

  StreamSubscription<StepCount>? _sub;

  // Hardwarový čítač vrací kroky od restartu telefonu, ne od našeho startu.
  // Proto si zapamatujeme první hodnotu a odečítáme ji.
  int? _baseline;

  /// Počet kroků od spuštění měření.
  int steps = 0;

  /// Vyžádá oprávnění a spustí měření.
  /// Vrací false, pokud uživatel oprávnění nepovolil.
  Future<bool> start() async {
    final status = await Permission.activityRecognition.request();
    if (!status.isGranted) return false;

    _baseline = null;
    _sub = Pedometer.stepCountStream.listen(
      (event) {
        // První přijatá hodnota se stane výchozím bodem (nulou).
        _baseline ??= event.steps;
        steps = event.steps - _baseline!;
        _controller.add(steps);
      },
      // Pokud telefon senzor nemá, pošleme chybu dál.
      onError: (e) => _controller.addError(e),
    );
    return true;
  }

  /// Zastaví poslech senzoru.
  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// Vynuluje počítadlo (nový výchozí bod se nastaví při příštím kroku).
  void reset() {
    _baseline = null;
    steps = 0;
    _controller.add(steps);
  }

  /// Uvolní zdroje.
  void dispose() {
    stop();
    _controller.close();
  }
}
