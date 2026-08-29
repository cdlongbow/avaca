import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:avaca/remote/remote_bytes.dart';
import 'package:avaca/remote/remote_endpoint.dart';
import 'package:avaca/remote/remote_identity.dart';
import 'package:avaca/remote/remote_limits.dart';
import 'package:avaca/remote/remote_pairing.dart';
import 'package:avaca/remote/remote_protocol.dart';
import 'package:avaca/remote/remote_quic.dart';
import 'package:avaca/remote/remote_secret_store.dart';
import 'package:avaca/remote/remote_session.dart';
import 'package:avaca/remote/remote_state_store.dart';
import 'package:avaca/remote/remote_transport.dart';

class _MemoryRemoteSecretStore implements RemoteSecretStore {
  final Map<String, Uint8List> _values = <String, Uint8List>{};

  @override
  Future<void> write(String key, List<int> secret) async {
    _values[key] = Uint8List.fromList(secret);
  }

  @override
  Future<List<int>?> read(String key) async {
    final value = _values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> close() async {}
}

Future<void> main(List<String> args) async {
  if (!Platform.isWindows || args.length < 2 || args.length > 3) {
    stderr.writeln(
      'usage: remote_dart_ffi_runtime_smoke.exe '
      '<server-sha1-40-hex> <server-der-sha256-64-hex> [port]',
    );
    exitCode = 2;
    return;
  }

  final serverSha1 = _parseHex(args[0], 20);
  final serverPin = _parseHex(args[1], RemoteLimits.channelBindingBytes);
  final port = args.length == 3 ? int.parse(args[2]) : 45889;

  RemoteIdentityManager? serverIdentityManager;
  RemoteIdentityManager? clientIdentityManager;
  RemoteQuicTransport? serverTransport;
  RemoteQuicTransport? clientTransport;
  RemoteListener? listener;
  RemoteAuthenticatedSession? serverSession;
  RemoteAuthenticatedSession? clientSession;
  final serverHandlerDone = Completer<void>();

  try {
    final serverState = InMemoryRemoteStateStore();
    final serverSecrets = _MemoryRemoteSecretStore();
    serverIdentityManager = RemoteIdentityManager(
      stateStore: serverState,
      secretStore: serverSecrets,
    );
    final serverIdentity = await serverIdentityManager.loadOrCreate();

    final clientState = InMemoryRemoteStateStore();
    final clientSecrets = _MemoryRemoteSecretStore();
    clientIdentityManager = RemoteIdentityManager(
      stateStore: clientState,
      secretStore: clientSecrets,
    );
    final clientIdentity = await clientIdentityManager.loadOrCreate();

    final sharedPairSecret = Uint8List.fromList(
      List<int>.generate(32, (index) => (0xa0 + index) & 0xff),
    );
    await _installPairedPeer(
      state: serverState,
      secrets: serverSecrets,
      peer: clientIdentity,
      pairSecret: sharedPairSecret,
    );
    await _installPairedPeer(
      state: clientState,
      secrets: clientSecrets,
      peer: serverIdentity,
      pairSecret: sharedPairSecret,
    );
    sharedPairSecret.fillRange(0, sharedPairSecret.length, 0);

    final serverPairing = RemotePairingManager(
      stateStore: serverState,
      secretStore: serverSecrets,
      identityManager: serverIdentityManager,
    );
    final clientPairing = RemotePairingManager(
      stateStore: clientState,
      secretStore: clientSecrets,
      identityManager: clientIdentityManager,
    );
    final serverAuthenticator = RemoteSessionAuthenticator(
      identityManager: serverIdentityManager,
      pairingManager: serverPairing,
    );
    final clientAuthenticator = RemoteSessionAuthenticator(
      identityManager: clientIdentityManager,
      pairingManager: clientPairing,
    );

    final serverSessionCompleter = Completer<RemoteAuthenticatedSession>();
    // Consume a possible handler error so a client-side failure cannot leave
    // an unhandled error while the cleanup path waits for the callback to end.
    unawaited(
      serverSessionCompleter.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    serverTransport = RemoteQuicTransport(
      pinnedServerCertificateSha256: serverPin,
      serverCertificateSha1: serverSha1,
      listenPort: port,
    );
    clientTransport = RemoteQuicTransport(
      pinnedServerCertificateSha256: serverPin,
    );
    listener = await serverTransport.listen((connection) async {
      try {
        final authenticated = await serverAuthenticator.authenticateServer(
          connection,
          source: 'loopback',
        );
        if (!serverSessionCompleter.isCompleted) {
          serverSession = authenticated;
          serverSessionCompleter.complete(authenticated);
        } else {
          await authenticated.close();
        }
      } on Object catch (error, stackTrace) {
        if (!serverSessionCompleter.isCompleted) {
          serverSessionCompleter.completeError(error, stackTrace);
        }
        await _closeQuietly(connection);
      } finally {
        if (!serverHandlerDone.isCompleted) {
          serverHandlerDone.complete();
        }
      }
    });

    final clientConnection = await clientTransport.connect(
      RemoteEndpoint(
        host: '127.0.0.1',
        port: port,
        kind: RemoteEndpointKind.stunCandidate,
      ),
    );
    clientSession = await clientAuthenticator.authenticateClient(
      clientConnection,
      serverDeviceId: serverIdentity.deviceId,
    );
    final authenticatedServerSession = await serverSessionCompleter.future
        .timeout(RemoteLimits.authTimeout);
    serverSession = authenticatedServerSession;

    final clientBinding = await clientConnection.channelBinding;
    final serverBinding =
        await authenticatedServerSession.connection.channelBinding;
    _check(
      clientBinding.length == RemoteLimits.channelBindingBytes &&
          clientBinding.length == serverBinding.length &&
          remoteConstantTimeEquals(clientBinding, serverBinding),
      'Dart FFI channel binding was not established symmetrically',
    );
    _pass('Dart FFI connected with matching TLS exporter channel binding');

    _check(
      clientSession.peerDeviceId == serverIdentity.deviceId &&
          authenticatedServerSession.peerDeviceId == clientIdentity.deviceId,
      'authenticated session peer identities did not match pairing metadata',
    );
    _pass('RemoteSessionAuthenticator completed mutual auth over Dart FFI');

    const pingPayload = <int>[0x44, 0x41, 0x52, 0x54, 0x2d, 0x46, 0x46, 0x49];
    await clientSession.writeFrame(
      const RemoteFrame(
        command: RemoteCommand.ping,
        flags: 0,
        requestId: 1,
        payload: pingPayload,
      ),
    );
    final receivedPing = await authenticatedServerSession.readFrame();
    _check(
      receivedPing.command == RemoteCommand.ping &&
          receivedPing.requestId == 1 &&
          remoteConstantTimeEquals(receivedPing.payload, pingPayload),
      'Dart FFI authenticated ping payload was corrupted',
    );
    await authenticatedServerSession.writeFrame(
      const RemoteFrame(
        command: RemoteCommand.pong,
        flags: 0,
        requestId: 1,
        payload: <int>[0x4f, 0x4b, 0x2d, 0x46, 0x46, 0x49],
      ),
    );
    final receivedPong = await clientSession.readFrame();
    _check(
      receivedPong.command == RemoteCommand.pong &&
          receivedPong.requestId == 1 &&
          remoteConstantTimeEquals(receivedPong.payload, const <int>[
            0x4f,
            0x4b,
            0x2d,
            0x46,
            0x46,
            0x49,
          ]),
      'Dart FFI authenticated pong payload was corrupted',
    );
    _pass('authenticated framed ping/pong traversed Dart FFI to MsQuic');
  } catch (error, stackTrace) {
    stderr.writeln('FAIL: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    try {
      await serverHandlerDone.future.timeout(RemoteLimits.connectionTimeout);
    } on Object {
      // The listener may never have accepted a connection; transport cleanup
      // below remains the authoritative shutdown path.
    }
    await _closeQuietly(clientSession);
    await _closeQuietly(serverSession);
    await _closeQuietly(listener);
    await _closeQuietly(clientTransport);
    await _closeQuietly(serverTransport);
    await _closeQuietly(clientIdentityManager);
    await _closeQuietly(serverIdentityManager);
  }
  if (exitCode == 0) {
    stdout.writeln('PASS: AVACA Dart FFI to MsQuic session smoke');
  }
}

Future<void> _installPairedPeer({
  required InMemoryRemoteStateStore state,
  required _MemoryRemoteSecretStore secrets,
  required RemoteIdentityRecord peer,
  required List<int> pairSecret,
}) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  final metadata = RemotePairedDeviceMetadata(
    deviceId: peer.deviceId,
    publicKey: base64Url.encode(peer.publicKeyBytes).replaceAll('=', ''),
    label: 'synthetic-runtime-peer',
    pairedAtMs: now,
    lastSeenAtMs: now,
    revoked: false,
    keyVersion: 1,
  );
  await state.save((await state.load()).copyWith(pairedDevices: [metadata]));
  final key =
      'paired-${base64Url.encode(utf8.encode(peer.deviceId)).replaceAll('=', '')}';
  final encoded = RemoteByteWriter()
    ..writeUint8(1)
    ..writeLengthPrefixedBytes(pairSecret, maxBytes: 32);
  await secrets.write(key, encoded.takeBytes());
}

List<int> _parseHex(String value, int bytes) {
  if (value.length != bytes * 2 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw FormatException('expected $bytes bytes of hexadecimal input');
  }
  return List<int>.generate(
    bytes,
    (index) => int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
  );
}

void _check(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

void _pass(String message) => stdout.writeln('PASS: $message');

Future<void> _closeQuietly(Object? object) async {
  try {
    if (object is RemoteAuthenticatedSession) {
      await object.close();
    } else if (object is RemoteListener) {
      await object.close();
    } else if (object is RemoteQuicTransport) {
      await object.close();
    } else if (object is RemoteIdentityManager) {
      await object.dispose();
    }
  } on Object catch (error) {
    stderr.writeln('cleanup warning: $error');
  }
}
