#!/usr/bin/env python3
"""sign.py — ed25519 signing for the pack catalog (docs/ARCHITECTURE.md).

The catalog is the control plane: the app verifies its signature against
a public key baked into the binary before trusting anything in it
(versions, URLs, sha256s). The secret key lives ONLY in the CI secret
PACK_SIGNING_KEY (base64 of the 32-byte seed) — never in the repo.

Usage:
  python3 sign.py keygen            # prints base64 seed (secret) + pubkey
  python3 sign.py pubkey <seed_b64> # prints base64 public key
  python3 sign.py sign <file>       # writes <file>.sig (raw 64-byte sig)

Requires PyNaCl (pip install pynacl).
"""

import base64
import sys
from pathlib import Path


def _nacl():
    try:
        import nacl.signing
        return nacl.signing
    except ImportError:
        sys.exit("PyNaCl required: pip install pynacl")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    signing = _nacl()
    cmd = sys.argv[1]

    if cmd == "keygen":
        sk = signing.SigningKey.generate()
        print("seed (SECRET — put in CI secret PACK_SIGNING_KEY):")
        print(base64.b64encode(bytes(sk)).decode())
        print("pubkey (bake into the app):")
        print(base64.b64encode(bytes(sk.verify_key)).decode())
    elif cmd == "pubkey":
        sk = signing.SigningKey(base64.b64decode(sys.argv[2]))
        print(base64.b64encode(bytes(sk.verify_key)).decode())
    elif cmd == "sign":
        import os
        seed = os.environ.get("PACK_SIGNING_KEY")
        if not seed:
            sys.exit("PACK_SIGNING_KEY env var (base64 seed) not set")
        sk = signing.SigningKey(base64.b64decode(seed))
        data = Path(sys.argv[2]).read_bytes()
        sig = sk.sign(data).signature
        out = Path(str(sys.argv[2]) + ".sig")
        out.write_bytes(sig)
        print(f"wrote {out} ({len(sig)} bytes)")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
