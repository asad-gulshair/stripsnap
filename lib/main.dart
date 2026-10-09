import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'engine/dosing.dart';
import 'engine/profiles.dart';
import 'engine/reader.dart';
import 'store.dart';

void main() => runApp(const StripSnapApp());

const kStripColor = Color(0xFFF5B400);

/// Runs the engine on a background isolate. Top-level so the closure captures only
/// plain values (never a widget or State).
Future<List<PadReading>> runRead(PreparedPhoto p, double sx, double sy, double sw, double sh, double cx,
    double cy, double cw, double ch, String profileId) {
  final rgb = p.rgb, w = p.width, h = p.height;
  return runInBackground(() => readStrip(RgbImage.fromBytes(w, h, rgb), Box(sx, sy, sw, sh),
      Box(cx, cy, cw, ch), profiles[profileId]!));
}
const kChartColor = Color(0xFF0EA5E9);

class StripSnapApp extends StatelessWidget {
  const StripSnapApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'StripSnap',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF0891B2), useMaterial3: true),
        home: const HomeScreen(),
      );
}

String fmt(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

// ======================================================================================
// Home: start a test, see history
// ======================================================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Settings? settings;
  List<HistoryEntry> history = [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Store.loadSettings();
    final h = await Store.loadHistory();
    if (!mounted) return;
    setState(() {
      settings = s;
      history = h;
    });
    if (s == null) await _openSettings(firstRun: true);
  }

  Future<void> _openSettings({bool firstRun = false}) async {
    final s = await Navigator.push<Settings>(context,
        MaterialPageRoute(builder: (_) => SettingsScreen(initial: settings ?? Settings(), firstRun: firstRun)));
    if (s != null) {
      await Store.saveSettings(s);
      setState(() => settings = s);
    }
  }

  Future<void> _start(ImageSource? source) async {
    final s = settings ?? Settings();
    late Uint8List bytes;
    List<double>? stripFrac, chartFrac;
    String profileId = s.profileId;
    bool isSample = false;
    if (source == null) {
      // bundled sample photo (computer-made) so anyone can try the app without strips
      final list = jsonDecode(await rootBundle.loadString('assets/samples/samples.json')) as List;
      final pick = list[DateTime.now().second % list.length] as Map<String, dynamic>;
      bytes = (await rootBundle.load('assets/samples/${pick['file']}')).buffer.asUint8List();
      stripFrac = (pick['strip'] as List).map((e) => (e as num).toDouble()).toList();
      chartFrac = (pick['chart'] as List).map((e) => (e as num).toDouble()).toList();
      profileId = pick['profile'] as String;
      isSample = true;
    } else {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 95);
      if (x == null) return;
      bytes = await x.readAsBytes();
    }
    setState(() => busy = true);
    final photo = await preparePhoto(bytes);
    if (!mounted) return;
    setState(() => busy = false);
    if (photo == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't open that photo. Try another one.")));
      return;
    }
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AlignScreen(
                  photo: photo,
                  settings: s,
                  profile: profiles[profileId]!,
                  stripFrac: stripFrac,
                  chartFrac: chartFrac,
                  isSample: isSample,
                )));
    final h = await Store.loadHistory();
    if (mounted) setState(() => history = h);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('StripSnap', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(icon: const Icon(Icons.tune), tooltip: 'My water', onPressed: _openSettings)],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                color: cs.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Test your water', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    const Text('Dip the strip, then take ONE photo with the strip lying just above '
                        "the bottle's color chart. Any brand works."),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                        onPressed: () => _start(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Take photo')),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                              onPressed: () => _start(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('From gallery'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: OutlinedButton.icon(
                              onPressed: () => _start(null),
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: const Text('Try a sample'))),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              const _Tips(),
              const SizedBox(height: 8),
              if (settings != null)
                ListTile(
                  leading: Icon(settings!.kind == 'pool' ? Icons.pool : Icons.hot_tub),
                  title: Text('${settings!.kind == 'pool' ? 'Pool' : 'Hot tub'} · '
                      '${fmt(settings!.volume)} ${settings!.unit == 'gal' ? 'gallons' : 'litres'}'),
                  subtitle: Text(profiles[settings!.profileId]!.name),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _openSettings,
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('History', style: Theme.of(context).textTheme.titleMedium),
              ),
              if (history.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Your tests will appear here, so you can see trends over time.')),
              ...history.map((h) => _HistoryTile(entry: h, settings: settings ?? Settings())),
            ]),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) => const ExpansionTile(
        title: Text('Tips for an accurate reading'),
        leading: Icon(Icons.lightbulb_outline),
        children: [
          ListTile(dense: true, leading: Icon(Icons.wb_shade_outlined), title: Text('Shade, not direct sun. No flash.')),
          ListTile(dense: true, leading: Icon(Icons.timer_outlined), title: Text('Wait the time printed on the bottle (often 15 s).')),
          ListTile(dense: true, leading: Icon(Icons.straighten), title: Text('Strip flat and straight (not tilted), pads up, handle on the right.')),
          ListTile(dense: true, leading: Icon(Icons.crop_free), title: Text('Fill the photo with the strip and the chart.')),
        ],
      );
}

class _HistoryTile extends StatelessWidget {
  final HistoryEntry entry;
  final Settings settings;
  const _HistoryTile({required this.entry, required this.settings});

  @override
  Widget build(BuildContext context) {
    final bad = entry.values.entries.where((e) => statusFor(e.key, e.value, entry.values, entry.kind) != 'ok' &&
        statusFor(e.key, e.value, entry.values, entry.kind) != '');
    final d = entry.when;
    final when = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Card(
      child: ListTile(
        leading: Icon(bad.isEmpty ? Icons.check_circle : Icons.error_outline,
            color: bad.isEmpty ? Colors.green : Colors.orange),
        title: Text(bad.isEmpty ? 'All in range' : '${bad.length} to fix'),
        subtitle: Text('$when${entry.sample ? ' · sample' : ''}\n'
            '${entry.values.entries.map((e) => '${_short(e.key)} ${fmt(e.value)}').join(' · ')}'),
        isThreeLine: true,
      ),
    );
  }
}

String _short(String key) => const {
      'free_chlorine': 'FC',
      'total_chlorine': 'TC',
      'ph': 'pH',
      'total_alkalinity': 'TA',
      'total_hardness': 'CH',
      'cyanuric_acid': 'CYA',
    }[key] ??
    key;

// ======================================================================================
// Settings
// ======================================================================================
class SettingsScreen extends StatefulWidget {
  final Settings initial;
  final bool firstRun;
  const SettingsScreen({super.key, required this.initial, this.firstRun = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Settings s = Settings.fromJson(widget.initial.toJson());
  late final TextEditingController vol = TextEditingController(text: fmt(s.volume));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.firstRun ? 'Welcome! Your water' : 'My water')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('What are you testing?'),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'pool', label: Text('Pool'), icon: Icon(Icons.pool)),
            ButtonSegment(value: 'spa', label: Text('Hot tub'), icon: Icon(Icons.hot_tub)),
          ],
          selected: {s.kind},
          onSelectionChanged: (v) => setState(() {
            s.kind = v.first;
            s.profileId = s.kind == 'pool' ? 'generic_pool_6' : 'generic_spa_4';
            if (s.kind == 'spa' && s.volume > 3000 && s.unit == 'gal') s.volume = 400;
            if (s.kind == 'pool' && s.volume < 1000 && s.unit == 'gal') s.volume = 15000;
            vol.text = fmt(s.volume);
          }),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: TextField(
              controller: vol,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Water volume', border: OutlineInputBorder()),
              onChanged: (t) => s.volume = double.tryParse(t) ?? s.volume,
            ),
          ),
          const SizedBox(width: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'gal', label: Text('gal')),
              ButtonSegment(value: 'l', label: Text('litres')),
            ],
            selected: {s.unit},
            onSelectionChanged: (v) => setState(() => s.unit = v.first),
          ),
        ]),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          value: s.profileId,
          decoration: const InputDecoration(labelText: 'Strip type', border: OutlineInputBorder()),
          items: profiles.values.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
          onChanged: (v) => setState(() => s.profileId = v ?? s.profileId),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
              'Order of tests on the strip: ${profiles[s.profileId]!.rows.map((r) => r.label).join(' → ')}',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<double>(
          value: s.chlorineStrength,
          decoration:
              const InputDecoration(labelText: 'Liquid chlorine you buy', border: OutlineInputBorder()),
          items: const [6.0, 8.25, 10.0, 12.5]
              .map((v) => DropdownMenuItem(value: v, child: Text('${fmt(v)}% strength')))
              .toList(),
          onChanged: (v) => setState(() => s.chlorineStrength = v ?? s.chlorineStrength),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () {
            if (s.volume <= 0) return;
            Navigator.pop(context, s);
          },
          child: const Text('Save'),
        ),
        const SizedBox(height: 12),
        Text('Saved only on this phone.', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

// ======================================================================================
// Align: drag the two frames onto the strip and the chart
// ======================================================================================
class AlignScreen extends StatefulWidget {
  final PreparedPhoto photo;
  final Settings settings;
  final StripProfile profile;
  final List<double>? stripFrac, chartFrac;
  final bool isSample;
  const AlignScreen(
      {super.key,
      required this.photo,
      required this.settings,
      required this.profile,
      this.stripFrac,
      this.chartFrac,
      this.isSample = false});

  @override
  State<AlignScreen> createState() => _AlignScreenState();
}

class _AlignScreenState extends State<AlignScreen> {
  late Rect strip, chart; // image pixels
  bool reading = false;

  // drag state
  String? _target; // 'strip' | 'chart'
  int _corner = -1; // -1 move, 0 tl, 1 tr, 2 br, 3 bl

  @override
  void initState() {
    super.initState();
    final w = widget.photo.width.toDouble(), h = widget.photo.height.toDouble();
    Rect fr(List<double> f) => Rect.fromLTWH(f[0] * w, f[1] * h, f[2] * w, f[3] * h);
    strip = fr(widget.stripFrac ?? [0.06, 0.12, 0.88, 0.09]);
    chart = fr(widget.chartFrac ?? [0.08, 0.30, 0.84, 0.55]);
  }

  Rect _clamp(Rect r) {
    final w = widget.photo.width.toDouble(), h = widget.photo.height.toDouble();
    final cw = r.width.clamp(30.0, w), ch = r.height.clamp(12.0, h);
    final l = r.left.clamp(0.0, w - cw), t = r.top.clamp(0.0, h - ch);
    return Rect.fromLTWH(l, t, cw, ch);
  }

  void _onStart(Offset img, double scale) {
    final tol = 28 / scale; // finger-sized corner handles
    for (final name in ['strip', 'chart']) {
      final r = name == 'strip' ? strip : chart;
      final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
      for (var i = 0; i < 4; i++) {
        if ((corners[i] - img).distance < tol) {
          _target = name;
          _corner = i;
          return;
        }
      }
    }
    for (final name in ['strip', 'chart']) {
      if ((name == 'strip' ? strip : chart).inflate(6 / scale).contains(img)) {
        _target = name;
        _corner = -1;
        return;
      }
    }
    _target = null;
  }

  void _onUpdate(Offset delta) {
    if (_target == null) return;
    var r = _target == 'strip' ? strip : chart;
    if (_corner == -1) {
      r = r.shift(delta);
    } else {
      var l = r.left, t = r.top, rr = r.right, b = r.bottom;
      if (_corner == 0 || _corner == 3) l += delta.dx;
      if (_corner == 1 || _corner == 2) rr += delta.dx;
      if (_corner == 0 || _corner == 1) t += delta.dy;
      if (_corner == 2 || _corner == 3) b += delta.dy;
      if (rr - l > 30 && b - t > 12) r = Rect.fromLTRB(l, t, rr, b);
    }
    setState(() {
      if (_target == 'strip') {
        strip = _clamp(r);
      } else {
        chart = _clamp(r);
      }
    });
  }

  Future<void> _read() async {
    setState(() => reading = true);
    final prof = widget.profile;
    final res = await runRead(widget.photo, strip.left, strip.top, strip.width, strip.height, chart.left,
        chart.top, chart.width, chart.height, prof.id);
    if (!mounted) return;
    setState(() => reading = false);
    // push (not pushReplacement) so Home's await only returns after the results are closed,
    // and Home then reloads history with this test in it.
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ResultScreen(
                readings: res, settings: widget.settings, profile: prof, isSample: widget.isSample)));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.photo;
    return Scaffold(
      appBar: AppBar(title: const Text('Line up the frames')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            _legend(kStripColor, 'Strip: pads in the boxes'),
            const SizedBox(width: 12),
            _legend(kChartColor, 'Chart: dots on swatches'),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final scale = math.min(box.maxWidth / p.width, box.maxHeight / p.height);
            final dw = p.width * scale, dh = p.height * scale;
            final ox = (box.maxWidth - dw) / 2, oy = (box.maxHeight - dh) / 2;
            Offset toImg(Offset local) => Offset((local.dx - ox) / scale, (local.dy - oy) / scale);
            return GestureDetector(
              onPanStart: (d) => _onStart(toImg(d.localPosition), scale),
              onPanUpdate: (d) => _onUpdate(d.delta / scale),
              onPanEnd: (_) => _target = null,
              child: Stack(children: [
                Positioned(left: ox, top: oy, width: dw, height: dh, child: Image.memory(p.jpg, fit: BoxFit.fill)),
                Positioned(
                  left: ox,
                  top: oy,
                  width: dw,
                  height: dh,
                  child: CustomPaint(
                      painter: _FramesPainter(strip, chart, scale, widget.profile)),
                ),
              ]),
            );
          }),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(
              widget.isSample
                  ? 'Sample photo: frames are already placed. Tap Read.'
                  : 'Drag a frame to move it, drag its corners to resize. '
                      'Strip pads go left → right in the same order as the chart rows.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: reading ? null : _read,
                icon: reading
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.colorize),
                label: Text(reading ? 'Reading colors…' : 'Read my strip'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _legend(Color c, String t) => Expanded(
        child: Row(children: [
          Container(width: 14, height: 14, decoration: BoxDecoration(border: Border.all(color: c, width: 3))),
          const SizedBox(width: 6),
          Flexible(child: Text(t, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

class _FramesPainter extends CustomPainter {
  final Rect strip, chart;
  final double scale;
  final StripProfile profile;
  _FramesPainter(this.strip, this.chart, this.scale, this.profile);

  Rect _s(Rect r) => Rect.fromLTWH(r.left * scale, r.top * scale, r.width * scale, r.height * scale);

  @override
  void paint(Canvas canvas, Size size) {
    final n = profile.rows.length;
    // strip frame + pad slots (same geometry the engine samples)
    final s = _s(strip);
    _frame(canvas, s, kStripColor);
    final slot = s.width * padZone / n;
    final thin = Paint()
      ..color = kStripColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < n; i++) {
      final cx = s.left + slot * (i + 0.5);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(cx, s.center.dy), width: slot * padSize, height: s.height * padHeight),
          thin);
    }
    // chart frame + swatch dots
    final c = _s(chart);
    _frame(canvas, c, kChartColor);
    final maxN = profile.rows.map((r) => r.values.length).reduce(math.max);
    final rh = c.height / n, sw = c.width * (1 - labelCol) / maxN;
    final dot = Paint()..color = kChartColor;
    for (var r = 0; r < n; r++) {
      for (var k = 0; k < profile.rows[r].values.length; k++) {
        canvas.drawCircle(Offset(c.left + c.width * labelCol + sw * (k + 0.5), c.top + rh * (r + 0.5)), 3.5, dot);
      }
    }
  }

  void _frame(Canvas canvas, Rect r, Color color) {
    canvas.drawRect(r, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawRect(
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    for (final p in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) {
      canvas.drawCircle(p, 9, Paint()..color = Colors.white);
      canvas.drawCircle(p, 7, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _FramesPainter o) => o.strip != strip || o.chart != chart || o.scale != scale;
}

// ======================================================================================
// Results + what to add
// ======================================================================================
class ResultScreen extends StatefulWidget {
  final List<PadReading> readings;
  final Settings settings;
  final StripProfile profile;
  final bool isSample;
  const ResultScreen(
      {super.key, required this.readings, required this.settings, required this.profile, this.isSample = false});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

/// 2+ unclear tests usually means the photo is tilted, shaded, or not a strip at all
/// (field check: random photos and wrong strip types always tripped this). Then we give
/// no advice and don't save it.
bool photoUnreliable(List<PadReading> r) => r.where((x) => x.confidence == 'Low').length >= 2;

/// Never claim certainty: these are colour matches, not lab results.
String confidenceText(String c) => switch (c) {
      'High' => 'Good colour match',
      'Medium' => 'Fair match',
      _ => 'Unsure',
    };

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();
    final good = widget.readings.where((r) => r.confidence != 'Low');
    if (good.isNotEmpty && !photoUnreliable(widget.readings)) {
      Store.addHistory(HistoryEntry(
        DateTime.now(),
        widget.isSample ? (widget.profile.id == 'generic_spa_4' ? 'spa' : 'pool') : widget.settings.kind,
        {for (final r in good) r.key: r.value},
        {for (final r in good) r.key: r.confidence},
        sample: widget.isSample,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    // A sample photo may be a hot tub strip while "My water" is a pool (or the other way).
    // Then give advice for a typical size of that kind, not the user's own volume.
    final sampleKind = widget.profile.id == 'generic_spa_4' ? 'spa' : 'pool';
    final mismatch = widget.isSample && sampleKind != s.kind;
    final kind = widget.isSample ? sampleKind : s.kind;
    final vol = mismatch ? (sampleKind == 'spa' ? 400.0 : 15000.0) : s.volume;
    final unit = mismatch ? 'gal' : s.unit;
    final values = {for (final r in widget.readings) r.key: r.value};
    final good = {for (final r in widget.readings.where((r) => r.confidence != 'Low')) r.key: r.value};
    final low = widget.readings.where((r) => r.confidence == 'Low').toList();
    final unreliable = photoUnreliable(widget.readings);
    final steps = unreliable ? <DoseStep>[] : plan(good, vol, unit, kind, s.chlorineStrength);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Your results')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.isSample)
          const Card(
            child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('This was a computer-made sample photo, not a real strip.')),
          ),
        if (unreliable)
          Card(
            color: Colors.red.shade50,
            child: ListTile(
              leading: const Icon(Icons.no_photography_outlined, color: Colors.red),
              title: const Text("We couldn't read this photo reliably"),
              subtitle: Text('${low.length} of ${widget.readings.length} tests did not match the chart well. '
                  'This happens with a tilted strip, shadow, glare, frames not lined up, or the wrong strip type. '
                  'Retake: strip straight and flat, in shade, frames lined up. No advice for this photo.'),
            ),
          )
        else if (low.isNotEmpty)
          Card(
            color: Colors.orange.shade50,
            child: ListTile(
              leading: const Icon(Icons.refresh, color: Colors.orange),
              title: Text('Not sure about ${low.map((r) => r.label).join(', ')}'),
              subtitle: const Text('Retake in shade, strip flat, and line the frames up closely. '
                  'These are left out of the advice below.'),
            ),
          ),
        ...widget.readings.map((r) {
          final st = statusFor(r.key, r.value, values, kind);
          final ideal = idealRange(r.key, values, kind);
          final color = switch (st) {
            'ok' => Colors.green,
            'low' => Colors.amber.shade800,
            'high' => Colors.red,
            _ => Colors.grey,
          };
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.label, style: text.bodyMedium),
                    Text('${fmt(r.value)} ${r.unit}',
                        style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (ideal != null)
                      Text('Ideal ${fmt(ideal[0])}–${fmt(ideal[1])}', style: text.bodySmall),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (st.isNotEmpty && r.confidence != 'Low' && !unreliable)
                    Chip(
                        label: Text(st.toUpperCase()),
                        backgroundColor: color.withValues(alpha: 0.15),
                        labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
                        visualDensity: VisualDensity.compact),
                  Text(unreliable ? 'Unsure' : confidenceText(r.confidence), style: text.bodySmall),
                ]),
              ]),
            ),
          );
        }),
        const SizedBox(height: 12),
        Text('What to do', style: text.titleLarge),
        const SizedBox(height: 6),
        if (unreliable)
          const Card(
            child: ListTile(
                leading: Icon(Icons.photo_camera_outlined),
                title: Text('Retake the photo first. Do not add chemicals based on this one.')),
          )
        else if (steps.isEmpty)
          const Card(
            child: ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('Everything we could read is in range. Nothing to add.')),
          ),
        ...steps.asMap().entries.map((e) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${e.key + 1}')),
                title: Text('${e.value.test} is ${e.value.status}'),
                subtitle: Text(e.value.action),
              ),
            )),
        const SizedBox(height: 10),
        Text(
          'Amounts are estimates for ${fmt(vol)} ${unit == 'gal' ? 'gallons' : 'litres'}${mismatch ? ' (a typical size for this sample)' : ''}. Add about half, '
          'run the pump, and retest before adding more. Always add chemicals to water, never water to chemicals.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ]),
    );
  }
}
