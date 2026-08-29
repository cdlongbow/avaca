import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'remote_bytes.dart';
import 'remote_errors.dart';

class RemoteCiphertext {
  const RemoteCiphertext({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;
}

class RemoteIdentityKeyMaterial {
  const RemoteIdentityKeyMaterial({
    required this.privateKeyBytes,
    required this.publicKeyBytes,
  });

  final Uint8List privateKeyBytes;
  final Uint8List publicKeyBytes;
}

/// Cryptographic primitives used by Remote Core.
///
/// All random values are supplied by [random], making protocol tests
/// deterministic without weakening production startup, which uses
/// [SecureRemoteRandom].
class RemoteCrypto {
  RemoteCrypto({RemoteRandom? random})
    : random = random ?? SecureRemoteRandom();

  final RemoteRandom random;
  final Ed25519 _ed25519 = Ed25519();
  final Hmac _hmac = Hmac.sha256();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final AesGcm _aesGcm = AesGcm.with256bits();

  Future<RemoteIdentityKeyMaterial> generateIdentityKeyMaterial() async {
    final seed = random.bytes(32);
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = Uint8List.fromList(
      await keyPair.extractPrivateKeyBytes(),
    );
    return RemoteIdentityKeyMaterial(
      privateKeyBytes: privateKeyBytes,
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
    );
  }

  SimpleKeyPairData keyPairFromBytes({
    required List<int> privateKeyBytes,
    required List<int> publicKeyBytes,
  }) {
    if (privateKeyBytes.length != 32 || publicKeyBytes.length != 32) {
      throw const RemoteException(
        RemoteFailureCode.secretStorageCorrupt,
        'identity key material has an invalid length',
      );
    }
    return SimpleKeyPairData(
      Uint8List.fromList(privateKeyBytes),
      publicKey: SimplePublicKey(
        Uint8List.fromList(publicKeyBytes),
        type: KeyPairType.ed25519,
      ),
      type: KeyPairType.ed25519,
    );
  }

  Future<Signature> sign(
    List<int> message, {
    required SimpleKeyPairData keyPair,
  }) => _ed25519.sign(message, keyPair: keyPair);

  Future<bool> verify(
    List<int> message, {
    required List<int> publicKeyBytes,
    required List<int> signatureBytes,
  }) {
    if (publicKeyBytes.length != 32 || signatureBytes.length != 64) {
      return Future<bool>.value(false);
    }
    final signature = Signature(
      Uint8List.fromList(signatureBytes),
      publicKey: SimplePublicKey(
        Uint8List.fromList(publicKeyBytes),
        type: KeyPairType.ed25519,
      ),
    );
    return _ed25519.verify(message, signature: signature);
  }

  Future<Uint8List> deriveKey({
    required List<int> secret,
    required List<int> info,
    List<int> salt = const <int>[],
  }) async {
    if (secret.isEmpty || info.isEmpty) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'key derivation inputs cannot be empty',
      );
    }
    final result = await _hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: salt,
      info: info,
    );
    return Uint8List.fromList(await result.extractBytes());
  }

  Future<Uint8List> hmacSha256({
    required List<int> secret,
    required List<int> message,
  }) async {
    if (secret.isEmpty) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'MAC secret cannot be empty',
      );
    }
    final mac = await _hmac.calculateMac(message, secretKey: SecretKey(secret));
    return Uint8List.fromList(mac.bytes);
  }

  Future<RemoteCiphertext> seal({
    required List<int> key,
    required List<int> cleartext,
    List<int> aad = const <int>[],
  }) async {
    _checkAesKey(key);
    final nonce = random.bytes(_aesGcm.nonceLength);
    final box = await _aesGcm.encrypt(
      cleartext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return RemoteCiphertext(
      nonce: Uint8List.fromList(box.nonce),
      cipherText: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<Uint8List> open({
    required List<int> key,
    required RemoteCiphertext ciphertext,
    List<int> aad = const <int>[],
  }) async {
    _checkAesKey(key);
    if (ciphertext.nonce.length != _aesGcm.nonceLength ||
        ciphertext.mac.length != _aesGcm.macAlgorithm.macLength) {
      throw const RemoteException(
        RemoteFailureCode.malformedFrame,
        'encrypted record has invalid nonce or MAC length',
      );
    }
    try {
      final cleartext = await _aesGcm.decrypt(
        SecretBox(
          ciphertext.cipherText,
          nonce: ciphertext.nonce,
          mac: Mac(ciphertext.mac),
        ),
        secretKey: SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(cleartext);
    } on SecretBoxAuthenticationError {
      throw const RemoteException(
        RemoteFailureCode.authenticationFailed,
        'encrypted record authentication failed',
      );
    }
  }

  void _checkAesKey(List<int> key) {
    if (key.length != 32) {
      throw const RemoteException(
        RemoteFailureCode.invalidInput,
        'AES-GCM requires a 256-bit key',
      );
    }
  }
}
