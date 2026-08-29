import 'dart:typed_data';

import 'package:avaca/remote/remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/remote_fakes.dart';

void main() {
  test('Ed25519 identity signs and rejects transcript tampering', () async {
    final crypto = RemoteCrypto(random: FixedRemoteRandom(7));
    final material = await crypto.generateIdentityKeyMaterial();
    final keyPair = crypto.keyPairFromBytes(
      privateKeyBytes: material.privateKeyBytes,
      publicKeyBytes: material.publicKeyBytes,
    );
    final message = Uint8List.fromList('remote transcript'.codeUnits);
    final signature = await crypto.sign(message, keyPair: keyPair);

    expect(
      await crypto.verify(
        message,
        publicKeyBytes: material.publicKeyBytes,
        signatureBytes: signature.bytes,
      ),
      isTrue,
    );
    expect(
      await crypto.verify(
        Uint8List.fromList(<int>[...message, 0]),
        publicKeyBytes: material.publicKeyBytes,
        signatureBytes: signature.bytes,
      ),
      isFalse,
    );
    keyPair.destroy();
  });

  test('HKDF labels separate keys and AES-GCM authenticates records', () async {
    final crypto = RemoteCrypto(random: FixedRemoteRandom(20));
    final pairSecret = Uint8List.fromList(
      List<int>.generate(32, (index) => index),
    );
    final discoveryKey = await crypto.deriveKey(
      secret: pairSecret,
      info: 'AVACA-REMOTE/DISCOVERY/V1'.codeUnits,
    );
    final preAuthKey = await crypto.deriveKey(
      secret: pairSecret,
      info: 'AVACA-REMOTE/PREAUTH/V1'.codeUnits,
    );
    expect(remoteConstantTimeEquals(discoveryKey, preAuthKey), isFalse);

    final sealed = await crypto.seal(
      key: discoveryKey,
      cleartext: 'opaque discovery'.codeUnits,
      aad: 'namespace'.codeUnits,
    );
    expect(
      await crypto.open(
        key: discoveryKey,
        ciphertext: sealed,
        aad: 'namespace'.codeUnits,
      ),
      'opaque discovery'.codeUnits,
    );
    await expectLater(
      crypto.open(
        key: discoveryKey,
        ciphertext: sealed,
        aad: 'changed'.codeUnits,
      ),
      throwsA(isA<RemoteException>()),
    );
  });
}
