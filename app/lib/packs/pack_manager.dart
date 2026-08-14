import 'dart:io';

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
