// Runs the Dart engine on synthetic test photos (made by the Python engine's generator)
// and checks it reads them about as well as the Python version.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stripsnap/engine/dosing.dart';
import 'package:stripsnap/engine/profiles.dart';
import 'package:stripsnap/engine/reader.dart';

void main() {
  test('reads synthetic strip photos', () {
    final fx = jsonDecode(File('test/fixtures/fixtures.json').readAsStringSync()) as List;
    var ok = 0, total = 0, agree = 0;
    for (final f in fx) {
      final m = f as Map<String, dynamic>;
      final decoded = img.decodeJpg(File('test/fixtures/${m['file']}').readAsBytesSync())!;
      final rgb = decoded.convert(format: img.Format.uint8, numChannels: 3);
      final im = RgbImage.fromBytes(rgb.width, rgb.height, rgb.getBytes(order: img.ChannelOrder.rgb));
      List<double> b(String k) => (m[k] as List).map((e) => (e as num).toDouble()).toList();
      final s = b('strip_box'), c = b('chart_box');
      final res = readStrip(im, Box(s[0], s[1], s[2], s[3]), Box(c[0], c[1], c[2], c[3]),
          profiles[m['profile']]!);
      final truth = b('true_pos'), py = b('py_pos');
      for (var i = 0; i < res.length; i++) {
        total++;
        if ((res[i].position - truth[i]).abs() <= 0.5) ok++;
        if ((res[i].position - py[i]).abs() <= 0.5) agree++;
      }
    }
    final acc = ok / total, agr = agree / total;
    // ignore: avoid_print
    print('Dart engine: ${(acc * 100).toStringAsFixed(1)}% correct, '
        '${(agr * 100).toStringAsFixed(1)}% agrees with Python ($total pad readings)');
    expect(acc, greaterThan(0.75));
    expect(agr, greaterThan(0.80));
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('dosing amounts', () {
    final steps = plan({'total_alkalinity': 50, 'free_chlorine': 0.5, 'cyanuric_acid': 40}, 15000, 'gal',
        'pool', 10);
    expect(steps.first.action, contains('6.75 lb baking soda'));
    expect(steps.any((s) => s.test == 'Free chlorine' && s.status == 'low'), isTrue);
  });

  test('slightly high chlorine still gets a step (never "all in range" next to a HIGH chip)', () {
    final steps = plan({'free_chlorine': 6, 'cyanuric_acid': 40}, 15000, 'gal', 'pool', 10);
    expect(steps.any((s) => s.test == 'Free chlorine' && s.status == 'high'), isTrue);
  });

  test('low alkalinity + low pH: baking soda first, then retest pH', () {
    final steps = plan({'total_alkalinity': 40, 'ph': 7.0}, 15000, 'gal', 'pool', 10);
    expect(steps.firstWhere((s) => s.test == 'pH').action, contains('retest pH'));
  });
}
