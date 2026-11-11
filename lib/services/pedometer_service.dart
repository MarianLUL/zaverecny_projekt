import 'dart:async';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

class PedometerService {
  final _controller = StreamController<int>.broadcast();
  Stream<int> get stepStream => _controller.stream;

  StreamSubscription<StepCount>? _sub;
  int? _baseline; // hodnota čítače při startu
  int steps = 0;

  Future<bool> start() async {
    final status = await Permission.activityRecognition.request();
    if (!status.isGranted) return false;

    _baseline = null;
    _sub = Pedometer.stepCountStream.listen(
      (event) {
        // senzor vrací počet kroků od restartu telefonu
        _baseline ??= event.steps;
        steps = event.steps - _baseline!;
        _controller.add(steps);
      },
      onError: (e) => _controller.addError(e),
    );
    return true;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void reset() {
    _baseline = null;
    steps = 0;
    _controller.add(steps);
  }

  void dispose() {
    stop();
    _controller.close();
  }
}