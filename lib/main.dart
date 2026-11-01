import 'package:flutter/material.dart';
import 'services/sensor_service.dart';
import 'services/pedometer_service.dart';

void main() => runApp(const MaterialApp(home : StepScreen()));

class StepScreen extends StatefulWidget {
  const StepScreen({super.key});
  @override
  State<StepScreen> createState() => _StepScreenState();
}

class _StepScreenState extends State<StepScreen> {
  final _algo = StepService();
  final _hw = PedometerService();
  bool _isRunning = false;
  String? _error;



Future<void> _toggle() async {
  if (_isRunning) {
    _algo.stop();
    _hw.stop();
    setState(() => _isRunning = false);
    return;
  } 
  final ok = await _hw.start();
  if (!ok) {
    setState(() => _error = 'Permission denied');
    return;
  }
  _algo.start();
  setState((){
    _isRunning = true;
    _error = null;
  });
}

void _reset() {
  _algo.reset();
  _hw.reset();
}
@override
void dispose() {
  _algo.dispose();
  _hw.dispose();
  super.dispose();
}

Widget _couter(String title, Stream<int> stream){
  return Column(
    children: [
      Text(title),
      StreamBuilder<int>(
        stream: stream,
        initialData: 0,
        builder: (context, snap) => Text(
          '${snap.data}', 
          style: Theme.of(context).textTheme.displayMedium
      ),
     ),
    ],
  );
}


@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('StepSense')),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _couter('Hardwarový senzor', _hw.stepStream),
          const SizedBox(height: 24),
          _couter('Vlastní Algoritmus', _algo.stepStream),
          const SizedBox(height: 24),
          if (_error != null) 
            Text(_error!, style: const TextStyle(color:  Colors.red)),
          FilledButton(
            onPressed: _toggle, 
            child: Text(_isRunning ? 'Stop' : 'Start')
          ),
          TextButton(onPressed: _reset, child: const Text('Reset')
          ),
        ],) 
    ),
  );
  }
}