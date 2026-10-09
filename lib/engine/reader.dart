/// Reads a test strip against its own bottle chart in the same photo.
/// Dart port of the Python engine (stripreader/engine/reader.py).
///
/// Lighting robustness: every colour is divided by the local white next to it (strip
/// paper beside a pad, chart label beside a swatch row), then compared in CIELAB.
import 'dart:math' as math;
import 'dart:typed_data';

import 'profiles.dart';

/// RGB image as floats, row-major.
class RgbImage {
  final int width, height;
  final Float32List data; // r,g,b,r,g,b...
  RgbImage(this.width, this.height, this.data);

  factory RgbImage.fromBytes(int w, int h, Uint8List rgb) {
    final d = Float32List(w * h * 3);
    for (var i = 0; i < d.length; i++) {
      d[i] = rgb[i].toDouble();
    }
    return RgbImage(w, h, d);
  }

  /// Separable gaussian blur (sigma ~1.2), used only for grid alignment.
  RgbImage blurred() {
    const k = [0.0545, 0.2442, 0.4026, 0.2442, 0.0545];
    final tmp = Float32List(data.length), out = Float32List(data.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        for (var c = 0; c < 3; c++) {
          var s = 0.0;
          for (var i = -2; i <= 2; i++) {
            final xx = (x + i).clamp(0, width - 1);
            s += k[i + 2] * data[(y * width + xx) * 3 + c];
          }
          tmp[(y * width + x) * 3 + c] = s;
        }
      }
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        for (var c = 0; c < 3; c++) {
          var s = 0.0;
          for (var i = -2; i <= 2; i++) {
            final yy = (y + i).clamp(0, height - 1);
            s += k[i + 2] * tmp[(yy * width + x) * 3 + c];
          }
          out[(y * width + x) * 3 + c] = s;
        }
      }
    }
    return RgbImage(width, height, out);
  }
}

class Box {
  final double x, y, w, h;
  const Box(this.x, this.y, this.w, this.h);
  Box shift(double dx, double dy) => Box(x + dx, y + dy, w, h);
}

class PadReading {
  final String key, label, unit, confidence;
  final double value, nearest, position, deltaE;
  PadReading(this.key, this.label, this.unit, this.value, this.nearest, this.position,
      this.deltaE, this.confidence);
}

// ---- geometry (must match the guide frames drawn in the app) ------------------------
const double padZone = 0.80, padSize = 0.55, padHeight = 0.70;
const double labelCol = 0.18, swatchSize = 0.62, swatchHeight = 0.62;

// ---- patch helpers ------------------------------------------------------------------
List<List<double>> _patch(RgbImage im, double cx, double cy, double hw, double hh,
    {int stride = 1}) {
  final x0 = math.max(0.0, cx - hw).toInt(), x1 = math.min(im.width.toDouble(), cx + hw).toInt();
  final y0 = math.max(0.0, cy - hh).toInt(), y1 = math.min(im.height.toDouble(), cy + hh).toInt();
  final out = <List<double>>[];
  for (var y = y0; y < y1; y += stride) {
    for (var x = x0; x < x1; x += stride) {
      final i = (y * im.width + x) * 3;
      out.add([im.data[i], im.data[i + 1], im.data[i + 2]]);
    }
  }
  return out;
}

double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return double.nan;
  final pos = (sorted.length - 1) * p / 100.0;
  final lo = pos.floor(), hi = pos.ceil();
  if (lo == hi) return sorted[lo];
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

List<double> _channelStat(List<List<double>> px, double p) =>
    List.generate(3, (c) => _percentile((px.map((e) => e[c]).toList()..sort()), p));

List<double> _median(List<List<double>> px) => _channelStat(px, 50);

double _meanStd(List<List<double>> px) {
  var tot = 0.0;
  for (var c = 0; c < 3; c++) {
    var m = 0.0;
    for (final p in px) {
      m += p[c];
    }
    m /= px.length;
    var v = 0.0;
    for (final p in px) {
      v += (p[c] - m) * (p[c] - m);
    }
    tot += math.sqrt(v / px.length);
  }
  return tot / 3;
}

/// Median after dropping the brightest 15% (glare) and darkest 5% (edges).
List<double> _robustColor(List<List<double>> px) {
  if (px.isEmpty) return [double.nan, double.nan, double.nan];
  final lum = (px.map((e) => e[0] + e[1] + e[2]).toList()..sort());
  final lo = _percentile(lum, 5), hi = _percentile(lum, 85);
  final keep = px.where((e) {
    final s = e[0] + e[1] + e[2];
    return s >= lo && s <= hi;
  }).toList();
  return _median(keep.isEmpty ? px : keep);
}

List<double> _uniformCenter(RgbImage im, double cx, double cy, double hw, double hh, double search) {
  double? best;
  var bc = [cx, cy];
  for (var i = 0; i < 5; i++) {
    final dx = -search + i * search / 2;
    for (var j = 0; j < 3; j++) {
      final dy = -search * 0.5 + j * search * 0.5;
      final p = _patch(im, cx + dx, cy + dy, hw, hh);
      if (p.length < 9) continue;
      final s = _meanStd(p) * 3;
      if (best == null || s < best) {
        best = s;
        bc = [cx + dx, cy + dy];
      }
    }
  }
  return bc;
}

double _gridScore(RgbImage im, List<List<double>> pts, double hw, double hh) {
  var stds = 0.0, edge = 0.0;
  for (final pt in pts) {
    final p = _patch(im, pt[0], pt[1], hw, hh, stride: 2);
    if (p.length < 4) return 1e9;
    stds += _meanStd(p);
    final ring = _patch(im, pt[0], pt[1], hw * 1.9, hh * 1.9, stride: 3);
    final a = _median(p), b = _median(ring);
    edge += ((a[0] - b[0]).abs() + (a[1] - b[1]).abs() + (a[2] - b[2]).abs()) / 3;
  }
  return stds / pts.length - 0.35 * edge / pts.length;
}

/// Shift the sampling grid to the best fit: coarse search then fine search.
Box _align(RgbImage blur, List<List<double>> Function(Box) centers, Box box, double hw, double hh,
    double sx, double sy) {
  List<double> search(double cx0, double cy0, double rx, double ry, int steps) {
    double? best;
    var off = [cx0, cy0];
    for (var i = 0; i < steps; i++) {
      final dx = cx0 - rx + 2 * rx * i / (steps - 1);
      for (var j = 0; j < steps; j++) {
        final dy = cy0 - ry + 2 * ry * j / (steps - 1);
        final s = _gridScore(blur, centers(box.shift(dx, dy)), hw, hh);
        if (best == null || s < best) {
          best = s;
          off = [dx, dy];
        }
      }
    }
    return off;
  }

  var o = search(0, 0, sx, sy, 9);
  o = search(o[0], o[1], sx / 4, sy / 4, 7);
  return box.shift(o[0], o[1]);
}

List<double> _div(List<double> a, List<double> w) =>
    List.generate(3, (c) => a[c] / math.max(w[c], 1.0));

// ---- sampling -----------------------------------------------------------------------
List<List<double>> sampleStrip(RgbImage im, RgbImage blur, Box box0, int n) {
  final slot0 = box0.w * padZone / n;
  List<List<double>> pts(Box b) =>
      List.generate(n, (i) => [b.x + b.w * padZone / n * (i + 0.5), b.y + b.h / 2]);
  final box = _align(blur, pts, box0, slot0 * padSize * 0.3, box0.h * padHeight * 0.3,
      slot0 * 0.35, box0.h * 0.25);
  final x = box.x, y = box.y, w = box.w, h = box.h;
  final slot = w * padZone / n;
  final hw = slot * padSize * 0.30, hh = h * padHeight * 0.30;
  final cy = y + h / 2;
  final out = <List<double>>[];
  for (var i = 0; i < n; i++) {
    final c = _uniformCenter(im, x + slot * (i + 0.5), cy, hw, hh, slot * 0.18);
    final pad = _robustColor(_patch(im, c[0], c[1], hw, hh));
    final wpx = <List<double>>[
      ..._patch(im, c[0], y + h * 0.08, slot * 0.25, h * 0.04),
      ..._patch(im, c[0], y + h * 0.92, slot * 0.25, h * 0.04),
      ..._patch(im, x + slot * i + slot * 0.04, cy, slot * 0.03, h * 0.15),
      ..._patch(im, x + slot * (i + 1) - slot * 0.04, cy, slot * 0.03, h * 0.15),
    ];
    final white = wpx.isEmpty ? [255.0, 255.0, 255.0] : _channelStat(wpx, 75);
    out.add(_div(pad, white));
  }
  return out;
}

List<List<List<double>>> sampleChart(RgbImage im, RgbImage blur, Box box0, List<int> counts) {
  final rows = counts.length;
  final maxN = counts.reduce(math.max);
  List<List<double>> pts(Box b) {
    final rh = b.h / rows, slot = b.w * (1 - labelCol) / maxN;
    return [
      for (var r = 0; r < rows; r++)
        for (var s = 0; s < counts[r]; s++)
          [b.x + b.w * labelCol + slot * (s + 0.5), b.y + rh * (r + 0.5)]
    ];
  }

  final rh0 = box0.h / rows, slot0 = box0.w * (1 - labelCol) / maxN;
  final box = _align(blur, pts, box0, slot0 * swatchSize * 0.3, rh0 * swatchHeight * 0.3,
      slot0 * 0.35, rh0 * 0.45);
  final x = box.x, y = box.y, w = box.w, h = box.h;
  final rh = h / rows, slot = w * (1 - labelCol) / maxN;
  final out = <List<List<double>>>[];
  for (var r = 0; r < rows; r++) {
    final cy = y + rh * (r + 0.5);
    final wpx = <List<double>>[..._patch(im, x + w * labelCol * 0.5, cy, w * labelCol * 0.3, rh * 0.15)];
    final cols = <List<double>>[];
    for (var s = 0; s < counts[r]; s++) {
      final hw = slot * swatchSize * 0.30, hh = rh * swatchHeight * 0.30;
      final c = _uniformCenter(im, x + w * labelCol + slot * (s + 0.5), cy, hw, hh, slot * 0.12);
      cols.add(_robustColor(_patch(im, c[0], c[1], hw, hh)));
      wpx.addAll(_patch(im, x + w * labelCol + slot * (s + 1) - slot * 0.06, cy, slot * 0.03, rh * 0.15));
    }
    final white = _channelStat(wpx, 75);
    out.add(cols.map((c) => _div(c, white)).toList());
  }
  return out;
}

// ---- colour science -----------------------------------------------------------------
/// sRGB (0..1, white-normalised) -> CIELAB (D65), same convention as OpenCV.
List<double> toLab(List<double> rgb) {
  double lin(double v) {
    v = v.clamp(0.0, 1.0);
    return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = lin(rgb[0]), g = lin(rgb[1]), b = lin(rgb[2]);
  final xx = (0.412453 * r + 0.357580 * g + 0.180423 * b) / 0.950456;
  final yy = 0.212671 * r + 0.715160 * g + 0.072169 * b;
  final zz = (0.019334 * r + 0.119193 * g + 0.950227 * b) / 1.088754;
  double f(double t) => t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final l = yy > 0.008856 ? 116 * math.pow(yy, 1 / 3) - 16 : 903.3 * yy;
  return [l.toDouble(), 500 * (f(xx) - f(yy)), 200 * (f(yy) - f(zz))];
}

double _dist(List<double> a, List<double> b) =>
    math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2) + math.pow(a[2] - b[2], 2));

/// Project the pad onto the poly-line through the swatches. Returns [position, distance].
List<double> matchPad(List<double> pad, List<List<double>> sw) {
  var bestPos = 0.0, bestD = double.infinity;
  for (var i = 0; i < sw.length - 1; i++) {
    final a = sw[i], b = sw[i + 1];
    final ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    final ap = [pad[0] - a[0], pad[1] - a[1], pad[2] - a[2]];
    final den = math.max(ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2], 1e-6);
    final t = ((ap[0] * ab[0] + ap[1] * ab[1] + ap[2] * ab[2]) / den).clamp(0.0, 1.0);
    final proj = [a[0] + t * ab[0], a[1] + t * ab[1], a[2] + t * ab[2]];
    final d = _dist(pad, proj);
    if (d < bestD) {
      bestD = d;
      bestPos = i + t;
    }
  }
  return [bestPos, bestD];
}

double valueAt(List<double> values, double pos) {
  final i = pos.floor();
  if (i >= values.length - 1) return values.last;
  return values[i] + (pos - i) * (values[i + 1] - values[i]);
}

String confidenceFor(double dE, List<List<double>> sw, double pos) {
  final i = math.min(pos.round(), sw.length - 1);
  final gaps = [for (var j = 0; j < sw.length - 1; j++) _dist(sw[j + 1], sw[j])];
  final gap = gaps[math.min(i, gaps.length - 1)];
  final ratio = dE / math.max(gap, 1e-6);
  if (dE < 6 && ratio < 0.35) return 'High';
  if (dE < 12 && ratio < 0.7) return 'Medium';
  return 'Low';
}

double _round(double v, int d) {
  final m = math.pow(10, d);
  return (v * m).round() / m;
}

/// Full read. [im] is the photo, boxes come from the guide frames (pixels).
List<PadReading> readStrip(RgbImage im, Box strip, Box chart, StripProfile profile) {
  final blur = im.blurred();
  final rows = profile.rows;
  final pads = sampleStrip(im, blur, strip, rows.length).map(toLab).toList();
  final charts = sampleChart(im, blur, chart, rows.map((r) => r.values.length).toList());
  final out = <PadReading>[];
  for (var k = 0; k < rows.length; k++) {
    final row = rows[k];
    final sw = charts[k].map(toLab).toList();
    final m = matchPad(pads[k], sw);
    final pos = m[0], d = m[1];
    out.add(PadReading(row.key, row.label, row.unit, _round(valueAt(row.values, pos), 2),
        row.values[pos.round()], _round(pos, 3), _round(d, 2), confidenceFor(d, sw, pos)));
  }
  return out;
}
