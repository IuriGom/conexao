import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Builds a MapLibre style JSON string that reads everything locally:
/// vector tiles from the pack's PMTiles file, glyphs from a directory of
/// downloaded .pbf font ranges. Forked from OpenFreeMap's Positron style.
///
/// Layers referencing removed sources (hillshade) or the sprite sheet
/// (icon-image) are dropped — no network references remain, satisfying the
/// offline-by-default architecture (docs/ARCHITECTURE.md).
class OfflineStyle {
  static Future<String> build({
    required String pmtilesPath,
    required String glyphsDir,
  }) async {
    final raw = await rootBundle.loadString('assets/style/positron.json');
    final style = jsonDecode(raw) as Map<String, dynamic>;

    style['sources'] = {
      'openmaptiles': {
        'type': 'vector',
        'url': 'pmtiles://file://$pmtilesPath',
      },
    };
    style['glyphs'] = 'file://$glyphsDir/{fontstack}/{range}.pbf';
    style.remove('sprite');

    style['layers'] = [
      for (final l in style['layers'] as List)
        if ((l['source'] == null || l['source'] == 'openmaptiles') &&
            !((l['layout'] as Map?)?.containsKey('icon-image') ?? false))
          l,
    ];
    return jsonEncode(style);
  }
}
