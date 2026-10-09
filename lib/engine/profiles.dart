/// Strip layouts. The engine never needs a brand's colours: it reads them from the
/// bottle chart in the same photo. A profile only lists which test is on which pad /
/// chart row and the value printed under each swatch.
class StripRow {
  final String key;
  final String label;
  final String unit;
  final List<double> values;
  const StripRow(this.key, this.label, this.unit, this.values);
}

class StripProfile {
  final String id;
  final String name;
  final List<StripRow> rows;
  final String note;
  const StripProfile(this.id, this.name, this.rows, {this.note = ''});
}

const genericPool6 = StripProfile(
  'generic_pool_6',
  '6-in-1 pool strip',
  [
    StripRow('total_hardness', 'Total hardness', 'ppm', [0, 100, 250, 500, 1000]),
    StripRow('total_chlorine', 'Total chlorine', 'ppm', [0, 0.5, 1, 3, 5, 10]),
    StripRow('free_chlorine', 'Free chlorine', 'ppm', [0, 0.5, 1, 3, 5, 10]),
    StripRow('ph', 'pH', '', [6.2, 6.8, 7.2, 7.6, 7.8, 8.4]),
    StripRow('total_alkalinity', 'Total alkalinity', 'ppm', [0, 40, 80, 120, 180, 240]),
    StripRow('cyanuric_acid', 'Stabilizer (CYA)', 'ppm', [0, 30, 50, 100, 150, 300]),
  ],
  note: 'Most common 6-way layout. Check your bottle lists the tests in this order.',
);

const genericSpa4 = StripProfile(
  'generic_spa_4',
  '4-in-1 hot tub strip',
  [
    StripRow('free_chlorine', 'Free chlorine', 'ppm', [0, 1, 3, 5, 10]),
    StripRow('ph', 'pH', '', [6.2, 6.8, 7.2, 7.8, 8.4]),
    StripRow('total_alkalinity', 'Total alkalinity', 'ppm', [0, 40, 80, 120, 180, 240]),
    StripRow('total_hardness', 'Total hardness', 'ppm', [0, 100, 250, 500, 1000]),
  ],
);

const Map<String, StripProfile> profiles = {
  'generic_pool_6': genericPool6,
  'generic_spa_4': genericSpa4,
};
