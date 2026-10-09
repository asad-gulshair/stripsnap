/// Readings -> "add X of Y" steps. Rule-of-thumb amounts per 10,000 US gallons; always
/// shown as estimates ("add about half, circulate, retest").
import 'dart:math' as math;

const double galPerLitre = 0.264172;

class DoseStep {
  final String test, status, action;
  const DoseStep(this.test, this.status, this.action);
}

/// [lo, hi, target]
const Map<String, Map<String, List<double>>> targets = {
  'pool': {
    'ph': [7.4, 7.6, 7.5],
    'total_alkalinity': [60, 120, 80],
    'total_hardness': [200, 400, 300],
    'cyanuric_acid': [30, 50, 40],
  },
  'spa': {
    'ph': [7.4, 7.8, 7.6],
    'total_alkalinity': [50, 80, 60],
    'total_hardness': [150, 250, 200],
    'cyanuric_acid': [0, 40, 30],
  },
};

String _n(double v) => v >= 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(2);

List<double> fcTarget(double cya, String kind) {
  if (kind == 'spa') return [3, 5];
  final lo = math.max(1.0, (0.075 * cya * 10).round() / 10);
  return [lo, math.max(lo + 1, ((0.115 * cya + 1) * 10).round() / 10)];
}

/// Status for one reading ('low' | 'ok' | 'high' | '').
String statusFor(String key, double value, Map<String, double> all, String kind) {
  if (key == 'free_chlorine') {
    final t = fcTarget(all['cyanuric_acid'] ?? 0, kind);
    return value < t[0] ? 'low' : (value > t[1] ? 'high' : 'ok');
  }
  final t = targets[kind]![key];
  if (t == null) return '';
  return value < t[0] ? 'low' : (value > t[1] ? 'high' : 'ok');
}

List<double>? idealRange(String key, Map<String, double> all, String kind) {
  if (key == 'free_chlorine') return fcTarget(all['cyanuric_acid'] ?? 0, kind);
  final t = targets[kind]![key];
  return t == null ? null : [t[0], t[1]];
}

List<DoseStep> plan(Map<String, double> r, double volume, String unit, String kind,
    double chlorineStrength) {
  final gal = unit == 'gal' ? volume : volume * galPerLitre;
  final k = gal / 10000;
  final t = targets[kind]!;
  final steps = <DoseStep>[];

  final ta = r['total_alkalinity'];
  if (ta != null) {
    final x = t['total_alkalinity']!;
    if (ta < x[0]) {
      steps.add(DoseStep('Alkalinity', 'low',
          'Add about ${_n((x[2] - ta) / 10 * 1.5 * k)} lb baking soda (sodium bicarbonate). '
          'Spread it over the water with the pump running.'));
    } else if (ta > x[1]) {
      steps.add(const DoseStep('Alkalinity', 'high',
          'Lower slowly: keep pH near 7.2 with acid for a few days and aerate (jets, waterfalls). '
          'Retest every 2 days.'));
    }
  }

  final taLow = ta != null && ta < t['total_alkalinity']![0];
  final ph = r['ph'];
  if (ph != null) {
    final x = t['ph']!;
    if (ph > x[1]) {
      steps.add(DoseStep('pH', 'high',
          'Add about ${_n((ph - x[2]) / 0.2 * 12 * k)} fl oz muriatic acid (31%). Pour slowly in front of a '
          'return jet. Add half, wait 30 min, retest.'));
    } else if (ph < x[0]) {
      steps.add(DoseStep('pH', 'low',
          '${taLow ? 'Baking soda also raises pH, so add it first and retest pH. If still low, add' : 'Add'} '
          'about ${_n((x[2] - ph) / 0.2 * 6 * k)} oz (weight) soda ash (pH up). Retest after 1 hour.'));
    }
  }

  final fc = r['free_chlorine'];
  if (fc != null) {
    final x = fcTarget(r['cyanuric_acid'] ?? 0, kind);
    if (fc < x[0]) {
      steps.add(DoseStep('Free chlorine', 'low',
          'Add about ${_n((x[1] - fc) * 12.8 * (10 / chlorineStrength) * k)} fl oz liquid chlorine '
          '(${chlorineStrength.toStringAsFixed(chlorineStrength % 1 == 0 ? 0 : 2)}%) to reach '
          '${x[1].toStringAsFixed(1)} ppm. Best added in the evening.'));
    } else if (fc > x[1] * 2) {
      steps.add(DoseStep('Free chlorine', 'high',
          "Don't add chlorine. Leave the cover off in sunlight and wait before swimming until it's "
          'below ${x[1].toStringAsFixed(1)} ppm.'));
    } else if (fc > x[1]) {
      steps.add(DoseStep('Free chlorine', 'high',
          "A little high. Don't add chlorine; it will drop on its own in a day or two. Retest."));
    }
  }

  final tc = r['total_chlorine'];
  if (tc != null && fc != null && tc - fc > 0.5) {
    steps.add(DoseStep('Combined chlorine', 'high',
        'Combined chlorine is ${(tc - fc).toStringAsFixed(1)} ppm (sweat and other by-products). '
        'Raise chlorine high and keep it there until it clears.'));
  }

  for (final e in [
    ['total_hardness', 'Calcium hardness', 1.25, 'calcium chloride'],
    ['cyanuric_acid', 'Stabilizer (CYA)', 13 / 16, 'stabilizer (cyanuric acid)'],
  ]) {
    final v = r[e[0] as String];
    if (v == null) continue;
    final x = t[e[0] as String]!;
    if (v < x[0]) {
      steps.add(DoseStep(e[1] as String, 'low',
          'Add about ${_n((x[2] - v) / 10 * (e[2] as double) * k)} lb ${e[3]}. Dissolve in a bucket of '
          'water first.'));
    } else if (v > x[1]) {
      steps.add(DoseStep(e[1] as String, 'high',
          'The only fix is replacing water: drain about ${((1 - x[2] / v) * 100).round()}% and refill.'));
    }
  }
  return steps;
}
