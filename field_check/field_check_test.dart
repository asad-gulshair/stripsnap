// Field check: runs the real engine on "phone-like" photos made by make_cases.py.
// Not part of CI. Run: flutter test field_check/field_check_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stripsnap/engine/profiles.dart';
import 'package:stripsnap/engine/reader.dart';

void main() {
  test('field check', () {
    final cases = jsonDecode(File('field_check/cases.json').readAsStringSync()) as List;
    final out = <Map<String, dynamic>>[];
    for (final c in cases) {
      final m = c as Map<String, dynamic>;
      final r = <String, dynamic>{'file': m['file'], 'condition': m['condition'], 'expect': m['expect']};
      try {
        final decoded = img.decodeJpg(File('field_check/images/${m['file']}').readAsBytesSync())!;
        final rgb = decoded.convert(format: img.Format.uint8, numChannels: 3);
        final im = RgbImage.fromBytes(rgb.width, rgb.height, rgb.getBytes(order: img.ChannelOrder.rgb));
        List<double> b(String k) => (m[k] as List).map((e) => (e as num).toDouble()).toList();
        final s = b('strip_box'), ch = b('chart_box');
        final prof = profiles[m['profile']]!;
        final res = readStrip(im, Box(s[0], s[1], s[2], s[3]), Box(ch[0], ch[1], ch[2], ch[3]), prof);
        final truth = m['true_pos'] == null ? null : b('true_pos');
        r['readings'] = [
          for (var i = 0; i < res.length; i++)
            {
              'label': res[i].label,
              'value': res[i].value,
              'conf': res[i].confidence,
              'dE': res[i].deltaE,
              if (truth != null) 'true': valueAt(prof.rows[i].values, truth[i]),
              if (truth != null) 'ok': (res[i].position - truth[i]).abs() <= 0.5,
            }
        ];
      } catch (e) {
        r['error'] = e.toString();
      }
      out.add(r);
      // ignore: avoid_print
      print('${m['file']}: ${r['error'] ?? (r['readings'] as List).map((x) => '${x['value']}/${x['conf']}${x.containsKey('ok') ? (x['ok'] ? '' : '(WRONG)') : ''}').join(', ')}');
    }
    File('field_check/results.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  }, timeout: const Timeout(Duration(minutes: 40)));
}
