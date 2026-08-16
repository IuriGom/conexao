import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'pack_manager.dart';

/// The pack control plane (docs/ARCHITECTURE.md): a signed catalog.json on
/// a GitHub Release. The app verifies the ed25519 signature against the
/// public key baked in below BEFORE trusting any URL, size or checksum.
/// The matching secret lives only in the CI secret PACK_SIGNING_KEY.
class PackCatalog {
  /// Release tag that CI keeps updated with the latest packs + catalog.
  static const releaseBase =
      'https://github.com/IuriGom/conexao/releases/download/packs';

  /// ed25519 public key (pipeline/sign.py keygen, 2026-08-16).
  static const pubkeyB64 = '5LjxgUx19i5vhpQCpG//0sLYGmq1xseIZdf0gSEh5mg=';

  final Map<String, CityEntry> cities;

  const PackCatalog(this.cities);

  /// Downloads and verifies the catalog. Throws on any verification
  /// failure — an unsigned or tampered catalog is treated as absent.
  static Future<PackCatalog> fetch({HttpClient? client}) async {
    final http = client ?? HttpClient();
    try {
      final catalogBytes = await _get(http, '$releaseBase/catalog.json');
      final sigBytes = await _get(http, '$releaseBase/catalog.json.sig');
      final ok = await Ed25519().verify(
        catalogBytes,
        signature: Signature(
          sigBytes,
          publicKey: SimplePublicKey(
            base64.decode(pubkeyB64),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      if (!ok) throw const FormatException('catalog signature invalid');
      final json =
          jsonDecode(utf8.decode(catalogBytes)) as Map<String, dynamic>;
      final cities = <String, CityEntry>{};
      for (final e in (json['cities'] as Map<String, dynamic>).entries) {
        cities[e.key] = CityEntry.fromJson(e.value as Map<String, dynamic>);
      }
      return PackCatalog(cities);
    } finally {
      if (client == null) http.close();
    }
  }

  static Future<List<int>> _get(HttpClient http, String url) async {
    final req = await http.getUrl(Uri.parse(url));
    final res = await req.close().timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw HttpException('GET $url -> ${res.statusCode}');
    }
    return res.fold<List<int>>([], (a, b) => a..addAll(b));
  }
}

class CityEntry {
  final String? badge;
  final Map<String, PackFile> files; // 'sqlite' | 'pmtiles'

  const CityEntry({required this.badge, required this.files});

  factory CityEntry.fromJson(Map<String, dynamic> json) => CityEntry(
        badge: json['badge'] as String?,
        files: {
          for (final e in (json['files'] as Map<String, dynamic>).entries)
            e.key: PackFile.fromJson(e.value as Map<String, dynamic>),
        },
      );

  int get totalSize => files.values.fold(0, (sum, f) => sum + f.size);
}

class PackFile {
  final String url;
  final int size;
  final String sha256;
  final bool gzipped;

  const PackFile({
    required this.url,
    required this.size,
    required this.sha256,
    this.gzipped = false,
  });

  factory PackFile.fromJson(Map<String, dynamic> json) => PackFile(
        url: json['url'] as String,
        size: json['size'] as int,
        sha256: json['sha256'] as String,
        gzipped: json['compressed'] == 'gzip',
      );
}

/// Downloads one city's pack files into the packs dir. Every file is
/// sha256-checked against the (signed) catalog entry and installed
/// atomically: partial downloads never appear as installed packs.
Future<void> downloadCity(
  CityEntry entry,
  void Function(int received, int total)? onProgress,
) async {
  final dir = await PackManager().packsDir();
  await dir.create(recursive: true);
  final http = HttpClient();
  var tmp = File('${dir.path}/.partial');
  try {
    var received = 0;
    for (final f in entry.files.values) {
      final sink = tmp.openWrite();
      final req = await http.getUrl(Uri.parse(f.url));
      final res = await req.close();
      if (res.statusCode != 200) {
        await sink.close();
        throw HttpException('GET ${f.url} -> ${res.statusCode}');
      }
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, entry.totalSize);
      }
      await sink.close();
      final digest = await Sha256().hash(await tmp.readAsBytes());
      if (digest.toString() != f.sha256) {
        await tmp.delete();
        throw const FormatException('pack checksum mismatch');
      }
      var name = f.url.split('/').last;
      if (f.gzipped) {
        // Stream-decompress to the final name (big packs stay off the heap).
        name = name.replaceAll(RegExp(r'\.gz$'), '');
        final out = File('${dir.path}/$name');
        final outSink = out.openWrite();
        await tmp.openRead().transform(gzip.decoder).pipe(outSink);
        await tmp.delete();
        tmp = out; // so a later failure cleans up the partial output
      }
      final target = '${dir.path}/$name';
      if (tmp.path != target) await tmp.rename(target);
    }
  } finally {
    http.close();
    if (tmp.existsSync()) await tmp.delete();
  }
}
