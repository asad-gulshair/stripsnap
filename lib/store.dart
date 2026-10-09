import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

/// User's water + strip setup. Saved on the phone only.
class Settings {
  String kind; // 'pool' | 'spa'
  double volume;
  String unit; // 'gal' | 'l'
  String profileId;
  double chlorineStrength;

  Settings({
    this.kind = 'pool',
    this.volume = 15000,
    this.unit = 'gal',
    this.profileId = 'generic_pool_6',
    this.chlorineStrength = 10,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'volume': volume,
        'unit': unit,
        'profileId': profileId,
        'chlorineStrength': chlorineStrength,
      };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        kind: j['kind'] as String? ?? 'pool',
        volume: (j['volume'] as num?)?.toDouble() ?? 15000,
        unit: j['unit'] as String? ?? 'gal',
        profileId: j['profileId'] as String? ?? 'generic_pool_6',
        chlorineStrength: (j['chlorineStrength'] as num?)?.toDouble() ?? 10,
      );
}

/// One saved test.
class HistoryEntry {
  final DateTime when;
  final String kind;
  final Map<String, double> values;
  final Map<String, String> confidence;
  final bool sample;

  HistoryEntry(this.when, this.kind, this.values, this.confidence, {this.sample = false});

  Map<String, dynamic> toJson() => {
        'when': when.toIso8601String(),
        'kind': kind,
        'values': values,
        'confidence': confidence,
        'sample': sample,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        DateTime.parse(j['when'] as String),
        j['kind'] as String,
        (j['values'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        (j['confidence'] as Map).map((k, v) => MapEntry(k as String, v as String)),
        sample: j['sample'] as bool? ?? false,
      );
}

class Store {
  static const _kSettings = 'settings_v1', _kHistory = 'history_v1';

  static Future<Settings?> loadSettings() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kSettings);
    return s == null ? null : Settings.fromJson(jsonDecode(s) as Map<String, dynamic>);
  }

  static Future<void> saveSettings(Settings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSettings, jsonEncode(s.toJson()));
  }

  static Future<List<HistoryEntry>> loadHistory() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kHistory);
    if (s == null) return [];
    return (jsonDecode(s) as List)
        .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> addHistory(HistoryEntry e) async {
    final list = await loadHistory();
    list.insert(0, e);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHistory, jsonEncode(list.take(60).map((x) => x.toJson()).toList()));
  }
}

/// Photo decoded once: upright, max 1280 px, raw RGB for the engine + JPEG for display.
class PreparedPhoto {
  final int width, height;
  final Uint8List rgb, jpg;
  PreparedPhoto(this.width, this.height, this.rgb, this.jpg);
}

/// Background work: its own isolate on phones; inline on web (web has no isolates).
Future<T> runInBackground<T>(T Function() task) => kIsWeb ? Future(task) : Isolate.run(task);

Future<PreparedPhoto?> preparePhoto(Uint8List bytes) => runInBackground(() {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      var im = img.bakeOrientation(decoded);
      final longSide = im.width > im.height ? im.width : im.height;
      if (longSide > 1280) {
        im = im.width >= im.height
            ? img.copyResize(im, width: 1280)
            : img.copyResize(im, height: 1280);
      }
      final rgb = im.convert(format: img.Format.uint8, numChannels: 3);
      return PreparedPhoto(rgb.width, rgb.height, rgb.getBytes(order: img.ChannelOrder.rgb),
          img.encodeJpg(rgb, quality: 85));
    });
