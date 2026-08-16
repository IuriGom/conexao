import 'dart:convert';

import 'package:conexao/packs/pack_download.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ed25519 verification matches pipeline/sign.py (PyNaCl)', () async {
    // Signed by pipeline/sign.py (PyNaCl) with the CI keypair on
    // 2026-08-16. If package:cryptography disagrees with PyNaCl on raw
    // ed25519, the whole pack control plane breaks — pin it here.
    const message = 'conexao catalog test vector\n';
    const sigB64 =
        'sznMbXh2jSCs06yE5fbxaDABXuyM2pencgR4UkGMUVEmtL57c6rWkSvS5sxlHnDB'
        'x6GlNOebj+eMWhOKg4a8AQ==';
    final ok = await Ed25519().verify(
      utf8.encode(message),
      signature: Signature(
        base64.decode(sigB64),
        publicKey: SimplePublicKey(
          base64.decode(PackCatalog.pubkeyB64),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    expect(ok, isTrue);

    // And a tampered message must NOT verify.
    final forged = await Ed25519().verify(
      utf8.encode('tampered\n'),
      signature: Signature(
        base64.decode(sigB64),
        publicKey: SimplePublicKey(
          base64.decode(PackCatalog.pubkeyB64),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    expect(forged, isFalse);
  });

  test('catalog JSON parses into city entries', () {
    final entry = CityEntry.fromJson({
      'badge': 'SCHEDULED',
      'files': {
        'sqlite': {'url': 'https://x/brasilia.sqlite', 'size': 10, 'sha256': 'a'},
        'pmtiles': {'url': 'https://x/brasilia.pmtiles', 'size': 20, 'sha256': 'b'},
      },
    });
    expect(entry.badge, 'SCHEDULED');
    expect(entry.totalSize, 30);
    expect(entry.files['sqlite']!.sha256, 'a');
  });
}
