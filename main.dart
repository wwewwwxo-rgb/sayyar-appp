import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

const Color bg = Color(0xFF101614);
const Color panel = Color(0xFF18221E);
const Color green = Color(0xFF27D69A);
const Color muted = Color(0xFF9AAEA5);
const String appUserAgent = 'SayyarNavigation/1.0 (personal small-group app)';

void main() => runApp(const SayyarApp());

class SayyarApp extends StatelessWidget {
  const SayyarApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'سيّار | SAYYAR',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(seedColor: green, brightness: Brightness.dark),
          useMaterial3: true,
          fontFamily: 'sans-serif',
        ),
        home: const SayyarHome(),
      );
}

class Place {
  final String name;
  final String displayName;
  final LatLng point;
  const Place(this.name, this.displayName, this.point);
}

class Maneuver {
  final String instruction;
  final LatLng point;
  bool spoken = false;
  Maneuver(this.instruction, this.point);
}

class SayyarHome extends StatefulWidget {
  const SayyarHome({super.key});
  @override
  State<SayyarHome> createState() => _SayyarHomeState();
}

class _SayyarHomeState extends State<SayyarHome> {
  final MapController mapController = MapController();
  final TextEditingController searchController = TextEditingController();
  final FlutterTts tts = FlutterTts();
  LatLng current = const LatLng(32.4837, 44.4272); // Hillah fallback until GPS is allowed.
  LatLng? destination;
  String destinationName = '';
  bool locating = false, searching = false, routing = false, navigating = false;
  String status = 'اضغط على الموقع لتحديد مكانك';
  String routeSummary = '';
  List<Place> results = [];
  List<LatLng> routePoints = [];
  List<Maneuver> maneuvers = [];
  StreamSubscription<Position>? positionSubscription;
  DateTime lastSearch = DateTime.fromMillisecondsSinceEpoch(0);
  int lastSpoken = -1;

  @override
  void initState() {
    super.initState();
    _setupTts();
    // Ask for location on first open, but the user can also retry from the location button.
    WidgetsBinding.instance.addPostFrameCallback((_) => locateUser());
  }

  Future<void> _setupTts() async {
    try {
      await tts.setLanguage('ar');
      await tts.setSpeechRate(0.48);
      await tts.setVolume(1.0);
    } catch (_) {}
  }

  @override
  void dispose() {
    positionSubscription?.cancel();
    searchController.dispose();
    tts.stop();
    super.dispose();
  }

  Future<void> locateUser() async {
    if (locating) return;
    setState(() { locating = true; status = 'جارٍ تحديد موقعك…'; });
    try {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() => status = 'شغّل GPS من إعدادات الهاتف ثم أعد المحاولة');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        setState(() => status = 'إذن الموقع مرفوض؛ اسمح لسيّار باستخدام الموقع');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => status = 'إذن الموقع مرفوض نهائياً؛ افتح إعدادات التطبيق');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      if (!mounted) return;
      setState(() {
        current = LatLng(p.latitude, p.longitude);
        status = 'تم تحديد موقعك';
      });
      mapController.move(current, 15.5);
    } catch (e) {
      if (mounted) setState(() => status = 'تعذّر تحديد الموقع؛ تأكد من GPS والإنترنت');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> searchPlaces(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      setState(() { results = []; status = 'اكتب اسم مكان أو عنواناً'; });
      return;
    }
    // Public Nominatim asks clients to avoid autocomplete; searches run only on button press.
    if (DateTime.now().difference(lastSearch).inMilliseconds < 1100) {
      await Future.delayed(const Duration(milliseconds: 1100));
    }
    lastSearch = DateTime.now();
    setState(() { searching = true; results = []; status = 'جارٍ البحث عن الأماكن…'; });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'jsonv2',
        'limit': '8',
        'addressdetails': '1',
        'accept-language': 'ar,en',
      });
      final response = await http.get(uri, headers: {
        'User-Agent': appUserAgent,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final List data = jsonDecode(response.body) as List;
      final parsed = data.map((item) {
        final m = item as Map<String, dynamic>;
        final display = (m['display_name'] ?? '').toString();
        final name = (m['name'] ?? display.split(',').first).toString();
        return Place(name, display, LatLng(double.parse(m['lat'].toString()), double.parse(m['lon'].toString())));
      }).toList();
      if (!mounted) return;
      setState(() {
        results = parsed;
        status = parsed.isEmpty ? 'ما لكينا نتائج؛ جرّب اسم أوضح' : 'اختَر المكان المطلوب';
      });
    } catch (_) {
      if (mounted) setState(() => status = 'فشل البحث؛ تأكد من الإنترنت وحاول لاحقاً');
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  Future<void> openSearch() async {
    searchController.clear();
    setState(() => results = []);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: panel,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.68,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Expanded(child: Text('وين تريد تروح؟', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) async { await searchPlaces(v); setSheet(() {}); },
                decoration: InputDecoration(
                  hintText: 'اكتب اسم المكان أو العنوان',
                  filled: true, fillColor: bg,
                  prefixIcon: const Icon(Icons.search, color: green),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: searching ? null : () async { await searchPlaces(searchController.text); setSheet(() {}); },
                icon: searching
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: Text(searching ? 'جارٍ البحث…' : 'ابحث'),
                style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: bg, padding: const EdgeInsets.all(14)),
              ),
              const SizedBox(height: 8),
              Text(status, style: const TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 6),
              Expanded(child: results.isEmpty
                  ? const Center(child: Text('نتائج الأماكن تظهر هنا', style: TextStyle(color: muted)))
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                      itemBuilder: (_, i) {
                        final p = results[i];
                        return ListTile(
                          leading: const CircleAvatar(backgroundColor: bg, child: Icon(Icons.place, color: green)),
                          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(p.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            setState(() { destination = p.point; destinationName = p.name; routePoints = []; maneuvers = []; routeSummary = ''; });
                            mapController.move(p.point, 15.5);
                            Navigator.pop(ctx);
                            _showDestinationPanel();
                          },
                        );
                      },
                    )),
            ]),
          ),
        );
      }),
    );
  }

  void _showDestinationPanel() {
    if (destination == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('الوجهة المحددة', style: TextStyle(color: muted)),
          const SizedBox(height: 6),
          Text(destinationName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: routing ? null : () { Navigator.pop(ctx); calculateRoute(); },
            icon: routing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.alt_route),
            label: Text(routing ? 'جارٍ حساب الطريق…' : 'احسب الطريق'),
            style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: bg, padding: const EdgeInsets.all(14)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ]),
      ),
    );
  }

  Future<void> calculateRoute() async {
    if (destination == null) return;
    setState(() { routing = true; status = 'جارٍ حساب الطريق…'; });
    try {
      final payload = {
        'locations': [
          {'lat': current.latitude, 'lon': current.longitude, 'type': 'break'},
          {'lat': destination!.latitude, 'lon': destination!.longitude, 'type': 'break'},
        ],
        'costing': 'auto',
        'units': 'kilometers',
        'language': 'ar',
        'directions_options': {'units': 'kilometers', 'language': 'ar'},
      };
      final uri = Uri.https('valhalla1.openstreetmap.de', '/route', {'json': jsonEncode(payload)});
      final response = await http.get(uri, headers: {'User-Agent': appUserAgent, 'X-Client-Id': 'sayyar-personal-app'}).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final trip = data['trip'] as Map<String, dynamic>?;
      if (trip == null) throw Exception('No route');
      final legs = (trip['legs'] as List?) ?? [];
      if (legs.isEmpty) throw Exception('No route legs');
      final leg = legs.first as Map<String, dynamic>;
      final shape = (leg['shape'] ?? '').toString();
      final decoded = _decodePolyline6(shape);
      if (decoded.length < 2) throw Exception('Empty route geometry');
      final maneuversRaw = (leg['maneuvers'] as List?) ?? [];
      final parsedManeuvers = <Maneuver>[];
      for (final raw in maneuversRaw) {
        final m = raw as Map<String, dynamic>;
        final index = (m['begin_shape_index'] as num?)?.toInt() ?? 0;
        if (decoded.isEmpty) continue;
        final safeIndex = index.clamp(0, decoded.length - 1);
        final instruction = (m['instruction'] ?? m['verbal_transition_alert_instruction'] ?? '').toString();
        if (instruction.trim().isNotEmpty) parsedManeuvers.add(Maneuver(instruction, decoded[safeIndex]));
      }
      final summary = (leg['summary'] as Map<String, dynamic>?) ?? {};
      final km = (summary['length'] as num?)?.toDouble();
      final secs = (summary['time'] as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        routePoints = decoded;
        maneuvers = parsedManeuvers;
        routeSummary = '${km == null ? '—' : km.toStringAsFixed(1)} كم • ${secs == null ? '—' : _duration(secs)}';
        status = 'تم حساب الطريق';
      });
      mapController.fitCamera(CameraFit.coordinates(
        coordinates: decoded,
        padding: const EdgeInsets.fromLTRB(40, 130, 40, 260),
        maxZoom: 16,
      ));
    } catch (_) {
      if (mounted) setState(() => status = 'تعذّر حساب الطريق؛ جرّب مرة ثانية أو تحقق من الإنترنت');
    } finally {
      if (mounted) setState(() => routing = false);
    }
  }

  String _duration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins دقيقة';
    return '${mins ~/ 60} س ${mins % 60} د';
  }

  List<LatLng> _decodePolyline6(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lon = 0;
    while (index < encoded.length) {
      int result = 0, shift = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      result = 0; shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20 && index < encoded.length);
      lon += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e6, lon / 1e6));
    }
    return points;
  }

  Future<void> startNavigation() async {
    if (routePoints.isEmpty) return;
    setState(() { navigating = true; lastSpoken = -1; });
    await positionSubscription?.cancel();
    try {
      await tts.setLanguage('ar');
      if (maneuvers.isNotEmpty) await tts.speak('بدأت الملاحة. ${maneuvers.first.instruction}');
    } catch (_) {}
    positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 8),
    ).listen((p) async {
      final here = LatLng(p.latitude, p.longitude);
      if (!mounted) return;
      setState(() => current = here);
      mapController.move(here, 16);
      if (!navigating || maneuvers.isEmpty) return;
      for (int i = 0; i < maneuvers.length; i++) {
        if (maneuvers[i].spoken) continue;
        final distance = const Distance().as(LengthUnit.Meter, here, maneuvers[i].point);
        if (distance < 250) {
          maneuvers[i].spoken = true;
          lastSpoken = i;
          try { await tts.speak(maneuvers[i].instruction); } catch (_) {}
          break;
        }
      }
    }, onError: (_) {
      if (mounted) setState(() => status = 'انقطع تحديث الموقع؛ تحقق من إذن الموقع');
    });
  }

  Future<void> stopNavigation() async {
    await positionSubscription?.cancel();
    positionSubscription = null;
    await tts.stop();
    if (mounted) setState(() { navigating = false; status = 'تم إيقاف الملاحة'; });
  }

  @override
  Widget build(BuildContext context) {
    final center = current;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(initialCenter: center, initialZoom: 13.5, minZoom: 3, maxZoom: 19),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sayyar.navigation',
              maxNativeZoom: 19,
            ),
            if (routePoints.length > 1)
              PolylineLayer(polylines: [
                Polyline(points: routePoints, strokeWidth: 9, color: Colors.black.withValues(alpha: 0.25)),
              ]),
            if (routePoints.length > 1)
              PolylineLayer(polylines: [Polyline(points: routePoints, strokeWidth: 5, color: green)]),
            MarkerLayer(markers: [
              Marker(point: current, width: 34, height: 34, child: Container(
                decoration: BoxDecoration(color: green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)]),
                child: const Icon(Icons.navigation, color: bg, size: 19),
              )),
              if (destination != null)
                Marker(point: destination!, width: 44, height: 44, child: const Icon(Icons.location_pin, color: Color(0xFFFF665F), size: 42)),
            ]),
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [TextSourceAttribution('© OpenStreetMap contributors', onTap: () {})],
            ),
          ],
        ),
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: bg.withValues(alpha: .95), borderRadius: BorderRadius.circular(16), border: Border.all(color: green.withValues(alpha: .5))),
              child: const Icon(Icons.alt_route, color: green, size: 29)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('سيّار', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, height: 1.0)),
              Text('SAYYAR  •  ملاحتك', style: TextStyle(color: green.withValues(alpha: .95), fontSize: 11, letterSpacing: 1.2)),
            ])),
            _roundButton(Icons.my_location, locateUser, loading: locating),
          ]),
        )),
        Positioned(left: 16, right: 16, top: MediaQuery.of(context).padding.top + 76, child: Material(
          color: panel.withValues(alpha: .97), borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: openSearch,
            child: const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15), child: Row(children: [
              Icon(Icons.search, color: green, size: 25), SizedBox(width: 12),
              Expanded(child: Text('ابحث عن مكان أو عنوان', style: TextStyle(fontSize: 15, color: Colors.white70))),
              Icon(Icons.tune, color: muted),
            ])),
          ),
        )),
        Positioned(left: 16, right: 16, bottom: 18, child: SafeArea(top: false, child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: bg.withValues(alpha: .97), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white12), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 18)]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Icon(Icons.circle, color: green, size: 10), const SizedBox(width: 8),
              Expanded(child: Text(status, style: const TextStyle(color: muted, fontSize: 12))),
              if (routeSummary.isNotEmpty) Text(routeSummary, style: const TextStyle(color: green, fontWeight: FontWeight.bold, fontSize: 12)),
            ]),
            if (destinationName.isNotEmpty) ...[
              const SizedBox(height: 9),
              Row(children: [
                const Icon(Icons.location_on, color: Color(0xFFFF665F)),
                const SizedBox(width: 8),
                Expanded(child: Text(destinationName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                IconButton(onPressed: () => setState(() { destination = null; destinationName = ''; routePoints = []; maneuvers = []; routeSummary = ''; navigating = false; }), icon: const Icon(Icons.close, color: muted)),
              ]),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: openSearch,
                icon: const Icon(Icons.search),
                label: const Text('اختيار وجهة'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 13)),
              )),
              const SizedBox(width: 10),
              Expanded(child: FilledButton.icon(
                onPressed: navigating ? stopNavigation : (routePoints.isNotEmpty ? startNavigation : (destination != null ? calculateRoute : null)),
                icon: Icon(navigating ? Icons.stop_circle_outlined : (routePoints.isNotEmpty ? Icons.navigation : Icons.alt_route)),
                label: Text(navigating ? 'إيقاف الملاحة' : (routePoints.isNotEmpty ? 'ابدأ الملاحة' : 'احسب الطريق')),
                style: FilledButton.styleFrom(backgroundColor: green, foregroundColor: bg, padding: const EdgeInsets.symmetric(vertical: 13)),
              )),
            ]),
          ]),
        ))),
      ]),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap, {bool loading = false}) => Material(
    color: bg.withValues(alpha: .95), shape: const CircleBorder(), child: InkWell(
      customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 46, height: 46,
        child: Center(child: loading ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2, color: green)) : Icon(icon, color: green))),
    ),
  );
}
