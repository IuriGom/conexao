import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Minimal on-device pack storage. Packs live in app-private storage:
/// `<app support>/packs/<city>.sqlite` (Android: `/data/data/<pkg>/files/packs`)
///
/// Phase 1 will add: download from GitHub Releases, ed25519 signature
/// verification, atomic apply + rollback, delta updates (see
/// docs/ARCHITECTURE.md). This is the local-storage piece only.
class PackManager {
  Future<Directory> packsDir() async {
    final docs = await getApplicationSupportDirectory();
    return Directory('${docs.path}/packs');
  }

  Future<File?> packFile(String cityId) async {
    final dir = await packsDir();
    final f = File('${dir.path}/$cityId.sqlite');
    return f.existsSync() ? f : null;
  }

  /// The offline map pack for a city.
  Future<File?> mapFile(String cityId) async {
    final dir = await packsDir();
    final f = File('${dir.path}/$cityId.pmtiles');
    return f.existsSync() ? f : null;
  }

  /// Copies the bundled font glyph ranges to app storage so MapLibre can
  /// read them via file:// (assets aren't real files on Android).
  /// Returns the directory for style 'glyphs' templates.
  Future<Directory> ensureGlyphs() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/glyphs');
    const stack = 'Noto Sans Regular';
    const ranges = ['0-255', '256-511', '8192-8447', '12288-12543'];
    final stackDir = Directory('${dir.path}/$stack');
    await stackDir.create(recursive: true);
    for (final r in ranges) {
      final out = File('${stackDir.path}/$r.pbf');
      if (!out.existsSync()) {
        final data = await rootBundle
            .load('assets/glyphs/$stack/$r.pbf');
        await out.writeAsBytes(data.buffer.asUint8List());
      }
    }
    return dir;
  }

  Future<List<String>> installedCities() async {
    final dir = await packsDir();
    if (!dir.existsSync()) return const [];
    return [
      for (final f in dir.listSync())
        if (f.path.endsWith('.sqlite'))
          f.uri.pathSegments.last.replaceAll('.sqlite', ''),
    ];
  }
}
