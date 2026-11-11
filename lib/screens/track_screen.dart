// =============================================================
// track_screen.dart
// Hlavní obrazovka: mapa Mapy.cz s trasou, aktuální poloha
// a statistiky (kroky, km, rychlost, převýšení, čas) + tlačítko Start/Stop.
//
// Data bere z TrackingService, který při každé změně zavolá
// notifyListeners() a ListenableBuilder obrazovku překreslí.
// =============================================================
 
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/pedometer_service.dart';
import '../services/sensor_service.dart';
import '../services/tracking_service.dart';
 
/// API klíč k Mapy.cz. NENÍ v kódu (aby se nedostal na GitHub),
/// předává se při spuštění:
///   flutter run --dart-define=MAPY_KEY=tvuj_klic
const mapyKey = String.fromEnvironment('MAPY_KEY');
 
class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key});
  @override
  State<TrackScreen> createState() => _TrackScreenState();
}
 
class _TrackScreenState extends State<TrackScreen> {
  // Služba, která měří aktivitu: hardwarový krokoměr + akcelerometr jako záloha.
  final _track = TrackingService(StepService(), PedometerService());
 
  // Ovládání mapy (přesun, přiblížení).
  final _map = MapController();
 
  // Mapa je připravená až po prvním vykreslení.
  bool _mapReady = false;
 
  // Aktuální poloha zjištěná ještě před stiskem Start (pro značku na mapě).
  LatLng? _current;
 
  @override
  void initState() {
    super.initState();
    // Při každé změně polohy v trase posuneme mapu za uživatelem.
    _track.addListener(_followUser);
    // Hned po otevření zjistíme polohu, ať je vidět i před Startem.
    _initLocation();
  }
 
  /// Zjistí aktuální polohu a přesune na ni mapu.
  Future<void> _initLocation() async {
    // GPS musí být zapnuté.
    if (!await Geolocator.isLocationServiceEnabled()) return;
 
    // Kontrola a vyžádání oprávnění.
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
 
    final p = await Geolocator.getCurrentPosition();
    if (!mounted) return; // obrazovka mohla mezitím zaniknout
    setState(() => _current = LatLng(p.latitude, p.longitude));
    if (_mapReady) _map.move(_current!, 16);
  }
 
  /// Posune mapu na poslední bod trasy (kontrola isNotEmpty chrání .last).
  void _followUser() {
    if (_mapReady && _track.route.isNotEmpty) {
      _map.move(_track.route.last, 17);
    }
  }
 
  /// Tlačítko Start/Stop.
  Future<void> _toggle() async {
    if (_track.running) {
      _track.stop();
      return;
    }
    final err = await _track.start();
    // Při chybě (vypnutá poloha, chybí oprávnění) ukážeme hlášku.
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
 
  /// Převede Duration na text HH:MM:SS.
  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }
 
  /// Jedna statistika: velká hodnota a malý popisek pod ní.
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
      // ListenableBuilder překreslí obsah při každém notifyListeners().
      body: ListenableBuilder(
        listenable: _track,
        builder: (context, _) {
          return Column(
            children: [
              // ===== MAPA (zabere zbytek místa nad statistikami) =====
              Expanded(
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: const LatLng(49.94, 17.90), // Opava
                    initialZoom: 15,
                    onMapReady: () {
                      _mapReady = true;
                      // Pokud už známe polohu, přesuneme mapu na ni.
                      if (_current != null) _map.move(_current!, 16);
                    },
                  ),
                  children: [
                    // Podkladové dlaždice Mapy.cz (turistická mapa).
                    TileLayer(
                      urlTemplate:
                          'https://api.mapy.com/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$mapyKey',
                      userAgentPackageName: 'com.example.stepsense',
                      maxZoom: 19,
                    ),
 
                    // Modrá čára trasy. Kreslí se až od 2 bodů,
                    // prázdný seznam by způsobil červenou chybovou obrazovku.
                    if (_track.route.length >= 2)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: List.of(_track.route),
                          strokeWidth: 5,
                          color: Colors.blue,
                        ),
                      ]),
 
                    // Červená značka polohy: poslední bod trasy,
                    // nebo poloha zjištěná před startem.
                    if (_track.route.isNotEmpty || _current != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _track.route.isNotEmpty
                              ? _track.route.last
                              : _current!,
                          width: 30,
                          height: 30,
                          child: const Icon(Icons.my_location,
                              color: Colors.red, size: 30),
                        ),
                      ]),
 
                    // Povinná atribuce Mapy.cz (logo a plné znění viz dokumentace).
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('© Seznam.cz a.s. a další'),
                      ],
                    ),
                  ],
                ),
              ),
 
              // ===== STATISTIKY A OVLÁDÁNÍ =====
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    // První řádek: kroky, vzdálenost, rychlosti.
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
 
                    // Druhý řádek: převýšení, výška, čas.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _stat('nahoru',
                            '${_track.ascentM.toStringAsFixed(0)} m'),
                        _stat('dolů',
                            '${_track.descentM.toStringAsFixed(0)} m'),
                        _stat('výška',
                            '${_track.altitudeM.toStringAsFixed(0)} m'),
                        _stat('čas', _fmt(_track.elapsed)),
                      ],
                    ),
                    const SizedBox(height: 8),
 
                    // Stavový řádek: GPS, pohyb, zahozené kroky, zdroj kroků.
                    Text(
                      'GPS: ${_track.gpsGood ? "OK" : "slabý signál"} · '
                      '${_track.moving ? "pohyb" : "stojím"} · '
                      'zahozeno kroků: ${_track.rejectedSteps} · '
                      'zdroj: ${_track.usingHardware ? "hardware" : "akcelerometr"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
 
                    // Tlačítko Start / Stop.
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
 
