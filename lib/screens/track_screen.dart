import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/sensor_service.dart';
import '../services/tracking_service.dart';
import 'package:geolocator/geolocator.dart';
import '../services/pedometer_service.dart';

// klíč se předává při spuštění: --dart-define=MAPY_KEY=...
const mapyKey = String.fromEnvironment('MAPY_KEY');

class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key});
  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  final _track = TrackingService(StepService(), PedometerService());
  final _map = MapController();
  bool _mapReady = false;

  LatLng? _current; 

  @override
  void initState() {
    super.initState();
    _track.addListener(_followUser);
    _initLocation();
  }

  Future<void> _initLocation() async {    // <-- nová metoda
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    final p = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() => _current = LatLng(p.latitude, p.longitude));
    if (_mapReady) _map.move(_current!, 16);
  }


  void _followUser() {
    if (_mapReady && _track.route.isNotEmpty) {
      _map.move(_track.route.last, 17);
    }
  }

  Future<void> _toggle() async {
    if (_track.running) {
      _track.stop();
      return;
    }
    final err = await _track.start();
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  

  @override
  void dispose() {
    _track.removeListener(_followUser);
    _track.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  Widget _stat(String label, String value) => Column(
        children: [
          Text(value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('StepSense')),
      body: ListenableBuilder(
        listenable: _track,
        builder: (context, _) {
          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: const LatLng(49.94, 17.90), // Opava
                    initialZoom: 15,
                    onMapReady: () { 
                      _mapReady = true; 
                      if (_current != null) _map.move(_current!, 16);},
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://api.mapy.com/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$mapyKey',
                      userAgentPackageName: 'com.example.stepsense',
                      maxZoom: 19,
                    ),
                    if (_track.route.length >= 2)
                        PolylineLayer(polylines: [
                          Polyline(
                            points: List.of(_track.route),
                            strokeWidth: 5,
                            color: Colors.blue,
                          ),
                        ]),
                    if (_track.route.isNotEmpty || _current != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _track.route.isNotEmpty ? _track.route.last : _current!,
                          width: 30,
                          height: 30,
                          child: const Icon(Icons.my_location,
                              color: Colors.red, size: 30),
                        ),
                      ]),
                    // povinná atribuce Mapy.cz (logo doplň podle dokumentace)
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('© Seznam.cz a.s. a další'),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _stat('kroky', '${_track.steps}'),
                        _stat('km', _track.distanceKm.toStringAsFixed(2)),
                        _stat('km/h', _track.speedKmh.toStringAsFixed(1)),
                        _stat('Ø km/h', _track.avgSpeedKmh.toStringAsFixed(1)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _stat('nahoru', '${_track.ascentM.toStringAsFixed(0)} m'),
                        _stat('dolů', '${_track.descentM.toStringAsFixed(0)} m'),
                        _stat('výška', '${_track.altitudeM.toStringAsFixed(0)} m'),
                        _stat('čas', _fmt(_track.elapsed)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'GPS: ${_track.gpsGood ? "OK" : "slabý signál"} · '
                      '${_track.moving ? "pohyb" : "stojím"} · '
                      'zahozeno kroků: ${_track.rejectedSteps}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _toggle,
                      child: Text(_track.running ? 'Stop' : 'Start'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}