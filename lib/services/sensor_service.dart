import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class StepService {
  final _controller = StreamController<int>.broadcast();
  Stream<int> get stepStream => _controller.stream;


StreamSubscription<AccelerometerEvent>? _sub;

int steps = 0;



double threshold = 1.0;                           //citlivost senzoru
static const _minGap = Duration(milliseconds: 300); //minimální časový rozdíl mezi kroky

double _gravity = 9.81; 
double _smooth = 0;
double _prev = 0, _prev2 = 0;
DateTime _lastStep = DateTime.fromMillisecondsSinceEpoch(0);

void start() {
  _sub?.cancel();
  _sub = accelerometerEventStream(
    samplingPeriod: SensorInterval.gameInterval,
  ).listen(_onEvent);
}

void stop() {
  _sub?.cancel();
  _sub = null;
}

void reset() {
  steps = 0;
  _controller.add(steps);
}

void _onEvent(AccelerometerEvent e){
  final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);

  _gravity = 0.98 * _gravity + 0.02 * mag;
  final dyn = mag - _gravity;


  _smooth = 0.7 * _smooth + 0.3 * dyn;


  final now = DateTime.now();
  final isPeak = _prev > _prev2 && _prev > _smooth && _prev > threshold;
  if (isPeak && now.difference(_lastStep) > _minGap) {
    steps++;
    _controller.add(steps);
    _lastStep = now;
  }
  _prev2 = _prev;
  _prev = _smooth;
}

void dispose() {
  stop();
  _controller.close();

}
}