import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avaca_domain/avaca_domain.dart';
import 'package:path/path.dart' as p;
import 'package:avaca_protocol/avaca_protocol.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';
import 'package:avaca_scraper/avaca_scraper.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'src/server_library_models.dart';

export 'src/server_library_models.dart';

class ServerLibraryException implements Exception {
  const ServerLibraryException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class ServerProtocolException implements Exception, AvacaApplicationFailure {
  const ServerProtocolException(this.code, this.retryable, this.message);

  @override
  final String code;
  @override
  final bool retryable;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// In-memory Server authority for v2 per-client invitations.  A pending
/// invitation becomes an active client credential only after the QUIC HMAC
/// handshake succeeds.  Neither the invitation id nor its secret is written
/// to the catalog or diagnostic output.
final class ServerPairingInvitationAuthority {
  ServerPairingInvitationAuthority({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _codec = AvacaPairingInvitationCodec(clock: clock);

  final DateTime Function() _clock;
  final AvacaPairingInvitationCodec _codec;
  final Map<String, _PendingServerInvitation> _pending =
      <String, _PendingServerInvitation>{};
  final Map<String, Uint8List> _activeSecrets = <String, Uint8List>{};

  AvacaPairingInvitation issue({
    required String serverId,
    required String clientId,
    required String host,
    required int port,
    required List<int> leafCertificateSha256,
    Duration lifetime = AvacaPairingInvitationCodec.maxLifetime,
  }) {
    _prune();
    final secret = Uint8List.fromList(
      List<int>.generate(32, (_) => math.Random.secure().nextInt(256)),
    );
    final invitation = _codec.issue(
      serverId: serverId,
      clientId: clientId,
      host: host,
      port: port,
      leafCertificateSha256: leafCertificateSha256,
      pairingSecret: secret,
      lifetime: lifetime,
    );
    _pending[invitation.invitationId] = _PendingServerInvitation(
      invitation: invitation,
      secret: secret,
    );
    return invitation;
  }

  String encode(AvacaPairingInvitation invitation) => _codec.encode(invitation);

  String issueCode({
    required String serverId,
    required String clientId,
    required String host,
    required int port,
    required List<int> leafCertificateSha256,
    Duration lifetime = AvacaPairingInvitationCodec.maxLifetime,
  }) {
    final invitation = issue(
      serverId: serverId,
      clientId: clientId,
      host: host,
      port: port,
      leafCertificateSha256: leafCertificateSha256,
      lifetime: lifetime,
    );
    return _codec.encode(invitation);
  }

  FutureOr<List<int>?> resolveSecret(String clientId) {
    _prune();
    final active = _activeSecrets[clientId];
    if (active != null) return Uint8List.fromList(active);
    for (final pending in _pending.values) {
      if (pending.invitation.clientId == clientId) {
        return Uint8List.fromList(pending.secret);
      }
    }
    return null;
  }

  void markAuthenticated(String clientId) {
    _prune();
    if (_activeSecrets.containsKey(clientId)) return;
    final entry = _pending.entries
        .where((candidate) => candidate.value.invitation.clientId == clientId)
        .firstOrNull;
    if (entry == null) return;
    final pending = entry.value;
    _pending.remove(entry.key);
    _activeSecrets[clientId] = Uint8List.fromList(pending.secret);
    pending.secret.fillRange(0, pending.secret.length, 0);
    pending.invitation.dispose();
  }

  void revoke(String clientId) {
    final active = _activeSecrets.remove(clientId);
    active?.fillRange(0, active.length, 0);
    final pending = _pending.entries
        .where((entry) => entry.value.invitation.clientId == clientId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final invitationId in pending) {
      final value = _pending.remove(invitationId);
      value?.secret.fillRange(0, value.secret.length, 0);
      value?.invitation.dispose();
    }
  }

  void dispose() {
    for (final value in _activeSecrets.values) {
      value.fillRange(0, value.length, 0);
    }
    for (final value in _pending.values) {
      value.secret.fillRange(0, value.secret.length, 0);
      value.invitation.dispose();
    }
    _activeSecrets.clear();
    _pending.clear();
  }

  void _prune() {
    final now = _clock().toUtc();
    final expired = _pending.entries
        .where((entry) => !entry.value.invitation.expiresAt.isAfter(now))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final invitationId in expired) {
      final value = _pending.remove(invitationId);
      value?.secret.fillRange(0, value.secret.length, 0);
      value?.invitation.dispose();
    }
  }
}

final class _PendingServerInvitation {
  _PendingServerInvitation({required this.invitation, required this.secret});

  final AvacaPairingInvitation invitation;
  final Uint8List secret;
}

class ServerPlaybackGrant {
  const ServerPlaybackGrant({
    required this.token,
    required this.grant,
    required this.resourceId,
    required this.length,
    required this.mimeType,
    required this.expiresAt,
  });

  /// The token is process-local.  Only [grant] crosses the authenticated
  /// protocol, and it is always exactly 32 bytes.
  final String token;
  final Uint8List grant;
  final String resourceId;
  final int length;
  final String mimeType;
  final DateTime expiresAt;
}

class _Grant {
  _Grant({
    required this.token,
    required this.grant,
    required this.resourceId,
    required this.mediaId,
    required this.path,
    required this.length,
    required this.expiresAt,
  });

  final String token;
  final Uint8List grant;
  final String resourceId;
  final AvacaMediaId mediaId;
  final String path;
  final int length;
  final DateTime expiresAt;
}

/// Ephemeral grant authority.  Grants never reach SQLite or disk and are
/// removed on close/expiry, so a leaked portable catalog cannot authorize a
/// media read by itself.
class PlaybackGrantRegistry {
  PlaybackGrantRegistry({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, _Grant> _grants = <String, _Grant>{};
  final math.Random _random = math.Random.secure();

  ServerPlaybackGrant issue({
    required AvacaMediaId mediaId,
    required String resourceId,
    required String path,
    required int length,
    required String mimeType,
    Duration lifetime = const Duration(minutes: 5),
  }) {
    if (length < 0) {
      throw const ServerLibraryException(
        'INVALID_LENGTH',
        'media length is invalid',
      );
    }
    final grantBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    final token = base64UrlEncode(grantBytes).replaceAll('=', '');
    _grants[token] = _Grant(
      token: token,
      grant: Uint8List.fromList(grantBytes),
      resourceId: resourceId,
      mediaId: mediaId,
      path: path,
      length: length,
      expiresAt: _clock().toUtc().add(lifetime),
    );
    return ServerPlaybackGrant(
      token: token,
      grant: Uint8List.fromList(grantBytes),
      resourceId: resourceId,
      length: length,
      mimeType: mimeType,
      expiresAt: _grants[token]!.expiresAt,
    );
  }

  bool isValid(String token, List<int> grantBytes) {
    final entry = _grants[token];
    if (entry == null || !entry.expiresAt.isAfter(_clock().toUtc())) {
      _remove(token);
      return false;
    }
    if (grantBytes.length != entry.grant.length) return false;
    var difference = grantBytes.length ^ entry.grant.length;
    for (var index = 0; index < entry.grant.length; index++) {
      difference |= grantBytes[index] ^ entry.grant[index];
    }
    return difference == 0;
  }

  _Grant _take(String token) {
    final grant = _grants[token];
    if (grant == null || !grant.expiresAt.isAfter(_clock().toUtc())) {
      _remove(token);
      throw const ServerLibraryException(
        'PLAYBACK_GRANT_INVALID',
        'playback grant is expired or unknown',
      );
    }
    return grant;
  }

  void revoke(String token) => _remove(token);

  int get activeCount => _grants.length;

  void _remove(String token) {
    final grant = _grants.remove(token);
    if (grant != null) {
      grant.grant.fillRange(0, grant.grant.length, 0);
    }
  }
}

class ServerMediaResourceHandle {
  const ServerMediaResourceHandle({required this.token, required this.length});

  final String token;
  final int length;
}

/// Range resource authority.  Only this server-side service touches a media
/// path; protocol payloads contain the opaque resource/token, never the path.
class ServerMediaResourceService {
  ServerMediaResourceService({PlaybackGrantRegistry? grants})
    : grants = grants ?? PlaybackGrantRegistry();

  final PlaybackGrantRegistry grants;
  final Map<String, RandomAccessFile> _openFiles = <String, RandomAccessFile>{};
  final Map<String, int> _openReferences = <String, int>{};
  final Map<String, Future<void>> _readTails = <String, Future<void>>{};

  Future<ServerMediaResourceHandle> open(String grantToken) async {
    // Opening the same opaque resource twice must be idempotent.  Replacing a
    // RandomAccessFile in this map would otherwise leak the first native file
    // handle until process shutdown and could keep a Windows file locked.
    final existing = _openFiles[grantToken];
    late final _Grant grant;
    try {
      grant = grants._take(grantToken);
    } on Object {
      // An expired grant may still have an old handle from a previous open;
      // release it before propagating the bounded grant failure.
      if (existing != null) {
        _openFiles.remove(grantToken);
        _openReferences.remove(grantToken);
        _readTails.remove(grantToken);
        await existing.close();
      }
      rethrow;
    }
    if (existing != null) {
      _openReferences[grantToken] = (_openReferences[grantToken] ?? 1) + 1;
      return ServerMediaResourceHandle(token: grantToken, length: grant.length);
    }
    try {
      final file = await File(grant.path).open(mode: FileMode.read);
      _openFiles[grantToken] = file;
      _openReferences[grantToken] = 1;
      return ServerMediaResourceHandle(token: grantToken, length: grant.length);
    } on Object {
      grants.revoke(grantToken);
      rethrow;
    }
  }

  Future<Uint8List> readAt(
    ServerMediaResourceHandle handle,
    int offset,
    int length,
  ) async {
    final grant = grants._take(handle.token);
    if (offset < 0 ||
        length < 0 ||
        length > 4 * 1024 * 1024 ||
        offset > grant.length ||
        length > grant.length - offset) {
      throw const ServerLibraryException(
        'RANGE_INVALID',
        'requested range is outside the granted media',
      );
    }
    final file = _openFiles[handle.token];
    if (file == null) {
      throw const ServerLibraryException(
        'RESOURCE_CLOSED',
        'resource is not open',
      );
    }
    // RandomAccessFile has one mutable cursor.  Serialize operations per
    // grant so concurrent range requests cannot interleave setPosition/read
    // and return bytes from the wrong offset.
    final previous = _readTails[handle.token] ?? Future<void>.value();
    final result = previous.then((_) async {
      await file.setPosition(offset);
      return Uint8List.fromList(await file.read(length));
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _readTails[handle.token] = tail;
    try {
      return await result;
    } finally {
      if (identical(_readTails[handle.token], tail)) {
        _readTails.remove(handle.token);
      }
    }
  }

  Future<void> close(ServerMediaResourceHandle handle) async {
    final references = _openReferences[handle.token];
    if (references == null) return;
    if (references > 1) {
      _openReferences[handle.token] = references - 1;
      return;
    }
    _openReferences.remove(handle.token);
    final file = _openFiles.remove(handle.token);
    _readTails.remove(handle.token);
    await file?.close();
  }

  Future<void> closeAll() async {
    final handles = _openFiles.entries.toList(growable: false);
    _openFiles.clear();
    _openReferences.clear();
    _readTails.clear();
    for (final entry in handles) {
      try {
        await entry.value.close();
      } catch (_) {
        // Continue closing every file; one close failure must not leave the
        // remaining process-local handles open.
      }
    }
  }
}

class PlaybackSessionDescriptor {
  const PlaybackSessionDescriptor({
    required this.sessionId,
    required this.grant,
    required this.clientId,
    required this.controlLeaseId,
  });

  final String sessionId;
  final ServerPlaybackGrant grant;
  final String clientId;
  final String controlLeaseId;
}

/// The result of the Server-side authorization gate immediately before a
/// native range resource is opened.  It deliberately contains only the
/// process-local grant token and bounded metadata; the media path never leaves
/// this library.
class ServerPlaybackAuthorization {
  const ServerPlaybackAuthorization({
    required this.sessionId,
    required this.clientId,
    required this.resourceId,
    required this.token,
    required this.length,
    required this.mimeType,
    required this.expiresAt,
  });

  final String sessionId;
  final String clientId;
  final String resourceId;
  final String token;
  final int length;
  final String mimeType;
  final DateTime expiresAt;
}

final class _PlaybackSessionRecord {
  _PlaybackSessionRecord({
    required this.sessionId,
    required this.clientId,
    required this.resourceId,
    required this.token,
    required this.mimeType,
    required this.length,
    required this.expiresAt,
    required this.controlLeaseId,
  });

  final String sessionId;
  final String clientId;
  final String resourceId;
  final String token;
  final String mimeType;
  final int length;
  final DateTime expiresAt;
  final String controlLeaseId;
  final Set<String> nativeLeaseIds = <String>{};
  bool controlAttached = true;
  bool revoked = false;
}

/// Creates protocol-level playback sessions from catalog media IDs.  Path
/// resolution stays entirely inside the Server process.
class PlaybackSessionService {
  PlaybackSessionService({required this.grants, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final PlaybackGrantRegistry grants;
  final DateTime Function() _clock;
  final Map<String, _PlaybackSessionRecord> _sessions =
      <String, _PlaybackSessionRecord>{};
  final Map<String, String> _resourceTokens = <String, String>{};
  final Map<String, String> _resourceMimeTypes = <String, String>{};
  final Map<String, String> _nativeLeaseSessions = <String, String>{};
  final math.Random _random = math.Random.secure();

  PlaybackSessionDescriptor create({
    required AvacaMediaId mediaId,
    required String resourceId,
    required String absolutePath,
    required int length,
    String mimeType = 'video/x-matroska',
    String clientId = 'fixture-client',
    Duration lifetime = const Duration(minutes: 5),
  }) {
    _validateClientId(clientId);
    final sessionId = _randomToken(16);
    // A resource handle is scoped to one playback session.  Reusing a stable
    // media id here would let a second client overwrite the first client's
    // in-memory grant mapping and make closing one session affect another.
    // The caller-provided id remains a server-side selection hint only; the
    // wire-facing id is opaque and freshly generated for this session.
    final scopedResourceId = 'resource.$sessionId';
    final grant = grants.issue(
      mediaId: mediaId,
      resourceId: scopedResourceId,
      path: absolutePath,
      length: length,
      mimeType: mimeType,
      lifetime: lifetime,
    );
    final controlLeaseId = _randomToken(16);
    _sessions[sessionId] = _PlaybackSessionRecord(
      sessionId: sessionId,
      clientId: clientId,
      resourceId: grant.resourceId,
      token: grant.token,
      mimeType: grant.mimeType,
      length: grant.length,
      expiresAt: grant.expiresAt,
      controlLeaseId: controlLeaseId,
    );
    _resourceTokens[grant.resourceId] = grant.token;
    _resourceMimeTypes[grant.resourceId] = grant.mimeType;
    return PlaybackSessionDescriptor(
      sessionId: sessionId,
      grant: grant,
      clientId: clientId,
      controlLeaseId: controlLeaseId,
    );
  }

  /// Authorize a native open in the exact order used by the production
  /// contract: authenticated connection identity, session ownership, expiry,
  /// resource binding, then constant-time grant comparison.
  ServerPlaybackAuthorization authorize({
    required String clientId,
    required String playbackSessionId,
    required String resourceId,
    required List<int> playbackGrant,
  }) {
    final record = _sessions[playbackSessionId];
    if (record == null || record.revoked || record.clientId != clientId) {
      throw const ServerLibraryException(
        'PLAYBACK_AUTH_INVALID',
        'playback authorization is invalid',
      );
    }
    if (record.resourceId != resourceId) {
      throw const ServerLibraryException(
        'PLAYBACK_AUTH_INVALID',
        'playback authorization is invalid',
      );
    }
    if (!record.expiresAt.isAfter(_clock().toUtc()) ||
        !grants.isValid(record.token, playbackGrant)) {
      revoke(playbackSessionId);
      throw const ServerLibraryException(
        'PLAYBACK_AUTH_INVALID',
        'playback authorization is invalid',
      );
    }
    return ServerPlaybackAuthorization(
      sessionId: record.sessionId,
      clientId: record.clientId,
      resourceId: record.resourceId,
      token: record.token,
      length: record.length,
      mimeType: record.mimeType,
      expiresAt: record.expiresAt,
    );
  }

  String attachNative({
    required String clientId,
    required String playbackSessionId,
    required String resourceId,
    required List<int> playbackGrant,
  }) {
    authorize(
      clientId: clientId,
      playbackSessionId: playbackSessionId,
      resourceId: resourceId,
      playbackGrant: playbackGrant,
    );
    final record = _sessions[playbackSessionId]!;
    final leaseId = _randomToken(16);
    record.nativeLeaseIds.add(leaseId);
    _nativeLeaseSessions[leaseId] = playbackSessionId;
    return leaseId;
  }

  void releaseNative({required String clientId, required String leaseId}) {
    final sessionId = _nativeLeaseSessions.remove(leaseId);
    if (sessionId == null) return;
    final record = _sessions[sessionId];
    if (record == null || record.clientId != clientId) {
      _nativeLeaseSessions[leaseId] = sessionId;
      throw const ServerLibraryException(
        'PLAYBACK_AUTH_INVALID',
        'playback authorization is invalid',
      );
    }
    record.nativeLeaseIds.remove(leaseId);
    _maybeRevoke(record);
  }

  void detachControl({
    required String clientId,
    required String sessionId,
    String? controlLeaseId,
  }) {
    final record = _ownedRecord(clientId, sessionId);
    if (controlLeaseId != null && controlLeaseId != record.controlLeaseId) {
      throw const ServerLibraryException(
        'PLAYBACK_AUTH_INVALID',
        'playback authorization is invalid',
      );
    }
    record.controlAttached = false;
    _maybeRevoke(record);
  }

  void close(String sessionId, {String? clientId}) {
    final record = _sessions[sessionId];
    if (record == null) return;
    if (clientId != null && record.clientId != clientId) {
      throw const ServerLibraryException(
        'PLAYBACK_AUTH_INVALID',
        'playback authorization is invalid',
      );
    }
    _revoke(record);
  }

  void revoke(String sessionId) {
    final record = _sessions[sessionId];
    if (record != null) _revoke(record);
  }

  /// Idempotently revoke every session owned by a Server runtime.  This is
  /// used during listener shutdown; ordinary connection loss uses
  /// [detachControl] so an independently reconnecting native data-plane lease
  /// is not accidentally revoked.
  void closeAll() {
    final records = _sessions.values.toList(growable: false);
    for (final record in records) {
      _revoke(record);
    }
  }

  List<String> resourceIdsForSession(String sessionId) {
    final record = _sessions[sessionId];
    return record == null ? const <String>[] : <String>[record.resourceId];
  }

  String? tokenForResource(String resourceId) => _resourceTokens[resourceId];

  String? mimeTypeForResource(String resourceId) =>
      _resourceMimeTypes[resourceId];

  String? ownerOf(String sessionId) => _sessions[sessionId]?.clientId;

  DateTime? expiresAtFor(String sessionId) => _sessions[sessionId]?.expiresAt;

  int get activeCount => _sessions.length;

  _PlaybackSessionRecord _ownedRecord(String clientId, String sessionId) {
    final record = _sessions[sessionId];
    if (record == null || record.clientId != clientId || record.revoked) {
      throw const ServerLibraryException(
        'PLAYBACK_AUTH_INVALID',
        'playback authorization is invalid',
      );
    }
    return record;
  }

  void _revoke(_PlaybackSessionRecord record) {
    if (record.revoked) return;
    record.revoked = true;
    _sessions.remove(record.sessionId);
    _resourceTokens.remove(record.resourceId);
    _resourceMimeTypes.remove(record.resourceId);
    for (final leaseId in record.nativeLeaseIds) {
      _nativeLeaseSessions.remove(leaseId);
    }
    record.nativeLeaseIds.clear();
    grants.revoke(record.token);
  }

  void _maybeRevoke(_PlaybackSessionRecord record) {
    if (!record.controlAttached && record.nativeLeaseIds.isEmpty) {
      _revoke(record);
    }
  }

  void _validateClientId(String value) {
    if (value.isEmpty || value.length > 256 || value.contains('\u0000')) {
      throw const ServerLibraryException(
        'INVALID_CLIENT_ID',
        'client id is invalid',
      );
    }
  }

  String _randomToken(int bytes) => List<int>.generate(
    bytes,
    (_) => _random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

abstract interface class ServerCatalogRepository {
  Future<AvacaCollectionPage> listCollection({String? cursor, int limit = 50});

  Future<AvacaWorkDetail> getWorkDetail(AvacaWorkId workId);
}

/// Write side of the Server catalog.  Keeping this smaller than
/// [ServerCatalogRepository] lets the folder importer be composed with a
/// Server-owned repository without exposing database or filesystem details to
/// the AVACA client.
abstract interface class ServerCatalogWriter {
  Future<void> upsertWork(AvacaWorkSummary work);

  Future<void> upsertMedia(ServerMediaRecord media);
}

/// Catalog protocol adapter.  It deliberately depends on a Server-owned
/// repository, not on any AVACA UI/database class.
class ServerCatalogService {
  const ServerCatalogService(this.repository);

  final ServerCatalogRepository repository;

  Future<AvacaCollectionPage> listCollection({
    String? cursor,
    int limit = 50,
  }) => repository.listCollection(cursor: cursor, limit: limit);

  Future<AvacaWorkDetail> getWorkDetail(AvacaWorkId workId) =>
      repository.getWorkDetail(workId);
}

class ServerPlaybackSelection {
  const ServerPlaybackSelection({
    required this.mediaId,
    required this.resourceId,
    required this.absolutePath,
    required this.length,
    this.mimeType = 'video/x-matroska',
    this.durationMs,
  });

  final AvacaMediaId mediaId;
  final String resourceId;
  final String absolutePath;
  final int length;
  final String mimeType;
  final int? durationMs;
}

typedef ServerPlaybackSelectionResolver =
    Future<ServerPlaybackSelection?> Function(AvacaMediaId mediaId);

/// Server-side application host.  The host owns the listener and all
/// authenticated sessions; catalog/resource work is injected and therefore
/// remains in the Windows Server process.  No host is started implicitly by a
/// Flutter widget.
final class AvacaServerApplicationHost {
  AvacaServerApplicationHost({
    required this.serverId,
    required List<int> pairingSecret,
    required ServerCatalogService catalog,
    required PlaybackSessionService playbackSessions,
    required ServerMediaResourceService resources,
    required ServerPlaybackSelectionResolver resolvePlayback,
    this.assetCatalog,
    this.pairingSecretResolver,
    this.onClientAuthenticated,
    this.expectedClientId,
  }) : _pairingSecret = Uint8List.fromList(pairingSecret),
       _catalog = catalog,
       _playbackSessions = playbackSessions,
       _resources = resources,
       _resolvePlayback = resolvePlayback;

  final String serverId;
  final String? expectedClientId;
  final FutureOr<List<int>?> Function(String clientId)? pairingSecretResolver;
  final FutureOr<void> Function(String clientId)? onClientAuthenticated;
  final Uint8List _pairingSecret;
  final ServerCatalogService _catalog;
  final PlaybackSessionService _playbackSessions;
  final ServerMediaResourceService _resources;
  final ServerPlaybackSelectionResolver _resolvePlayback;
  final ServerAssetCatalogRepository? assetCatalog;
  final Set<AvacaApplicationSession> _sessions = <AvacaApplicationSession>{};
  Future<void> _operationTail = Future<void>.value();
  Future<void>? _closeFuture;
  AvacaRemoteListener? _listener;
  bool _started = false;
  bool _closing = false;
  bool _disposed = false;

  Future<void> start(AvacaRemoteTransport transport) => _enqueue(() async {
    if (_disposed) {
      throw const ServerProtocolException(
        'server_host_closed',
        false,
        'Server application host is closed',
      );
    }
    if (_started) {
      throw const ServerProtocolException(
        'server_already_started',
        false,
        'Server listener is already running',
      );
    }
    if (transport.role != AvacaRemoteRole.server) {
      throw const ServerProtocolException(
        'server_transport_required',
        false,
        'AVACA Server requires a server-role transport',
      );
    }
    if (_closing) {
      throw const ServerProtocolException(
        'server_host_closing',
        false,
        'Server application host is closing',
      );
    }
    _started = true;
    try {
      _listener = await transport.listen(_acceptConnection);
    } on Object {
      _started = false;
      rethrow;
    }
  });

  Future<void> _acceptConnection(AvacaRemoteConnection connection) async {
    if (_closing || _disposed) {
      await _closeConnectionQuietly(connection);
      return;
    }
    AvacaApplicationSession? session;
    AvacaServerApplicationHandler? handler;
    try {
      session = await AvacaApplicationSession.authenticateServer(
        connection,
        serverId: serverId,
        pairingSecret: _pairingSecret,
        pairingSecretResolver: pairingSecretResolver,
        expectedClientId: expectedClientId,
        // The same authenticated QUIC listener serves the control catalog and
        // the native playback data plane.  Both domains still require the
        // invitation-derived pairing secret; the selected domain is bound to
        // the handshake transcript and retained on the session.
        acceptedAuthDomains: const <String>[
          AvacaHandshakeCodec.controlDomain,
          AvacaHandshakeCodec.playbackDomain,
        ],
      );
      await onClientAuthenticated?.call(session.peerId);
      _sessions.add(session);
      handler = AvacaServerApplicationHandler(
        serverId: AvacaServerId(serverId),
        clientId: session.peerId,
        catalog: _catalog,
        playbackSessions: _playbackSessions,
        resources: _resources,
        resolvePlayback: _resolvePlayback,
        assetCatalog: assetCatalog,
      );
      await session.serve(handler.handle);
    } on Object {
      // Authentication and request failures are already reduced to typed,
      // redacted wire errors.  Closing the connection is the fail-closed path.
    } finally {
      _sessions.remove(session);
      await handler?.close();
      await session?.close();
    }
  }

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final closeFuture = _enqueue<void>(() async {
      if (_disposed) return;
      _closing = true;
      final listener = _listener;
      _listener = null;
      try {
        await listener?.close();
      } on Object {
        // Continue closing sessions and zeroing the in-memory pairing secret.
      }
      final sessions = _sessions.toList(growable: false);
      for (final session in sessions) {
        await session.close();
      }
      _sessions.clear();
      await _resources.closeAll();
      _playbackSessions.closeAll();
      _pairingSecret.fillRange(0, _pairingSecret.length, 0);
      _started = false;
      _disposed = true;
    });
    _closeFuture = closeFuture;
    return closeFuture;
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operationTail.then<T>((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _closeConnectionQuietly(AvacaRemoteConnection connection) async {
    try {
      await connection.close();
    } on Object {
      // A rejected connection is already fail-closed; do not leak the native
      // close error into the listener callback.
    }
  }
}

/// Wire adapter for one authenticated Server connection.  It contains no
/// Flutter state and performs each catalog/file operation asynchronously, so
/// the AVACA UI never waits on a Server filesystem call on its frame isolate.
final class AvacaServerApplicationHandler {
  AvacaServerApplicationHandler({
    required this.serverId,
    this.clientId = 'fixture-client',
    required ServerCatalogService catalog,
    required PlaybackSessionService playbackSessions,
    required ServerMediaResourceService resources,
    required ServerPlaybackSelectionResolver resolvePlayback,
    this.assetCatalog,
    Set<String> features = const <String>{
      'catalog',
      'details',
      'playback-range',
      'artwork-assets',
    },
  }) : _catalog = catalog,
       _playbackSessions = playbackSessions,
       _resources = resources,
       _resolvePlayback = resolvePlayback,
       _features = Set<String>.unmodifiable(features);

  final AvacaServerId serverId;
  final String clientId;
  final ServerCatalogService _catalog;
  final PlaybackSessionService _playbackSessions;
  final ServerMediaResourceService _resources;
  final ServerPlaybackSelectionResolver _resolvePlayback;
  final ServerAssetCatalogRepository? assetCatalog;
  final Set<String> _features;
  final AvacaApplicationCodec _codec = const AvacaApplicationCodec();
  final Map<String, _OpenServerResource> _openResources =
      <String, _OpenServerResource>{};
  final Map<String, String> _playbackSessionLeases = <String, String>{};
  final Map<int, _PendingServerRead> _pendingReads =
      <int, _PendingServerRead>{};
  final math.Random _handleRandom = math.Random.secure();

  Future<AvacaFrame> handle(AvacaFrame request) async {
    try {
      return await _handle(request);
    } on ServerProtocolException {
      rethrow;
    } on ServerLibraryException catch (error) {
      throw ServerProtocolException(error.code, false, error.message);
    } on FileSystemException {
      throw const ServerProtocolException(
        'resource_io_failed',
        true,
        'Server resource I/O failed',
      );
    } on Object {
      throw const ServerProtocolException(
        'internal',
        false,
        'Server request failed',
      );
    }
  }

  Future<AvacaFrame> _handle(AvacaFrame request) async {
    switch (request.opcode) {
      case AvacaOpcode.getCapabilities:
        return _response(
          request,
          AvacaOpcode.capabilities,
          _codec.encodeCapabilities(
            AvacaCapabilitiesDto(
              serverId: serverId,
              features: _features,
              maxCollectionPageSize: AvacaApplicationCodec.maxPageSize,
              maxReadBytes: AvacaApplicationCodec.maxBinaryRangeBytes,
            ),
          ),
        );
      case AvacaOpcode.listCollection:
        final query = _codec.decodeCollectionRequest(request.payload);
        final page = await _catalog.listCollection(
          cursor: query.cursor,
          limit: query.limit,
        );
        return _response(
          request,
          AvacaOpcode.collectionPage,
          _codec.encodeCollectionPage(
            AvacaCollectionPageDto(
              items: page.items
                  .map(
                    (item) => AvacaWorkCardDto(
                      workId: item.workId,
                      code: item.code,
                      title: item.title,
                      cover: item.coverResourceId == null
                          ? null
                          : AvacaAssetRefDto(
                              assetId: item.coverResourceId!,
                              revision: 0,
                            ),
                    ),
                  )
                  .toList(growable: false),
              nextCursor: page.nextCursor,
            ),
          ),
        );
      case AvacaOpcode.getWorkDetail:
        final workId = AvacaWorkId(_codec.decodeIdRequest(request.payload));
        final detail = await _catalog.getWorkDetail(workId);
        return _response(
          request,
          AvacaOpcode.workDetail,
          _codec.encodeWorkDetail(
            AvacaWorkDetailDto(
              workId: detail.workId,
              code: detail.code,
              title: detail.title,
              description: detail.description,
              releaseDate: detail.releaseDate,
              performers: detail.performers
                  .map(
                    (performer) => AvacaPerformerDto(
                      actressId: performer.actressId,
                      displayName: performer.displayName,
                    ),
                  )
                  .toList(growable: false),
              media: detail.media
                  .map(
                    (media) => AvacaMediaCardDto(
                      mediaId: media.mediaId,
                      workId: media.workId,
                      code: media.code,
                      title: media.title,
                      durationMs: media.durationMs,
                      availability: media.availability,
                      artwork: media.artworkResourceId == null
                          ? null
                          : AvacaAssetRefDto(
                              assetId: media.artworkResourceId!,
                              revision: 0,
                            ),
                    ),
                  )
                  .toList(growable: false),
              artwork: detail.coverResourceId == null
                  ? null
                  : AvacaAssetRefDto(
                      assetId: detail.coverResourceId!,
                      revision: 0,
                    ),
            ),
          ),
        );
      case AvacaOpcode.createPlaybackSession:
        final mediaId = AvacaMediaId(_codec.decodeIdRequest(request.payload));
        final selection = await _resolvePlayback(mediaId);
        if (selection == null) {
          throw const ServerProtocolException(
            'media_unavailable',
            false,
            'requested media is unavailable',
          );
        }
        final session = _playbackSessions.create(
          mediaId: selection.mediaId,
          resourceId: selection.resourceId,
          absolutePath: selection.absolutePath,
          length: selection.length,
          mimeType: selection.mimeType,
          clientId: clientId,
        );
        _playbackSessionLeases[session.sessionId] = session.controlLeaseId;
        return _response(
          request,
          AvacaOpcode.playbackSessionCreated,
          _codec.encodePlaybackSession(
            AvacaPlaybackSessionDto(
              playbackSessionId: session.sessionId,
              resourceId: session.grant.resourceId,
              playbackGrant: session.grant.grant,
              contentLength: session.grant.length,
              mimeType: session.grant.mimeType,
              durationMs: selection.durationMs,
              expiresAtMs: session.grant.expiresAt.millisecondsSinceEpoch,
            ),
          ),
        );
      case AvacaOpcode.closePlaybackSession:
        final sessionId = _codec.decodeIdRequest(request.payload);
        final resourceHandles = _openResources.entries
            .where((entry) => entry.value.sessionId == sessionId)
            .map((entry) => entry.key)
            .toList(growable: false);
        for (final resourceHandle in resourceHandles) {
          await _closeOpenResource(resourceHandle);
        }
        _playbackSessions.close(sessionId, clientId: clientId);
        _playbackSessionLeases.remove(sessionId);
        return _response(
          request,
          AvacaOpcode.playbackSessionClosed,
          _codec.encodeIdRequest(sessionId),
        );
      case AvacaOpcode.openResource:
        final open = _codec.decodeResourceOpenRequest(request.payload);
        final authorization = _playbackSessions.authorize(
          clientId: clientId,
          playbackSessionId: open.playbackSessionId,
          resourceId: open.resourceId,
          playbackGrant: open.playbackGrant,
        );
        final leaseId = _playbackSessions.attachNative(
          clientId: clientId,
          playbackSessionId: open.playbackSessionId,
          resourceId: open.resourceId,
          playbackGrant: open.playbackGrant,
        );
        try {
          final fileHandle = await _resources.open(authorization.token);
          final resourceHandle = _newResourceHandle();
          _openResources[resourceHandle] = _OpenServerResource(
            sessionId: open.playbackSessionId,
            resourceId: open.resourceId,
            clientId: clientId,
            leaseId: leaseId,
            handle: fileHandle,
          );
          return _response(
            request,
            AvacaOpcode.resourceOpened,
            _codec.encodeResourceOpened(
              AvacaResourceOpenedDto(
                resourceHandle: resourceHandle,
                contentLength: fileHandle.length,
                mimeType: authorization.mimeType,
              ),
            ),
          );
        } on Object {
          _playbackSessions.releaseNative(clientId: clientId, leaseId: leaseId);
          rethrow;
        }
      case AvacaOpcode.readResource:
        final range = _codec.decodeRangeRequest(request.payload);
        final open = _openResources[range.resourceHandle];
        if (open == null) {
          throw const ServerProtocolException(
            'resource_closed',
            true,
            'resource is not open',
          );
        }
        if (open.clientId != clientId) {
          throw const ServerProtocolException(
            'resource_closed',
            false,
            'resource is not open',
          );
        }
        final read = _PendingServerRead(resourceHandle: range.resourceHandle);
        _pendingReads[request.requestId] = read;
        final operation = _resources.readAt(
          open.handle,
          range.offset,
          range.length,
        );
        final operationDone = operation.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        read.operationDone = operationDone;
        try {
          final bytes = await Future.any<Uint8List>(<Future<Uint8List>>[
            operation,
            read.cancelled.future.then<Uint8List>(
              (_) => throw const _ReadCancelled(),
            ),
          ]);
          return _response(
            request,
            AvacaOpcode.resourceChunk,
            _codec.encodeResourceChunk(
              AvacaResourceChunkDto(
                offset: range.offset,
                bytes: bytes,
                eof: range.offset + bytes.length >= open.handle.length,
              ),
            ),
          );
        } on _ReadCancelled {
          throw const ServerProtocolException(
            'cancelled',
            false,
            'resource read was cancelled',
          );
        } finally {
          _pendingReads.remove(request.requestId);
          read.completed.complete();
        }
      case AvacaOpcode.cancelRead:
        final cancel = _codec.decodeCancelReadRequest(request.payload);
        final pending = _pendingReads[cancel.targetRequestId];
        final cancelled = pending?.cancel() ?? false;
        return _response(
          request,
          AvacaOpcode.pong,
          _codec.encodeCancelReadResult(
            AvacaCancelReadResultDto(
              targetRequestId: cancel.targetRequestId,
              cancelled: cancelled,
            ),
          ),
        );
      case AvacaOpcode.closeResource:
        final resourceHandle = _codec.decodeIdRequest(request.payload);
        await _closeOpenResource(resourceHandle);
        return _response(
          request,
          AvacaOpcode.resourceClosed,
          _codec.encodeIdRequest(resourceHandle),
        );
      case AvacaOpcode.ping:
        return _response(request, AvacaOpcode.pong, Uint8List(0));
      case AvacaOpcode.openAsset:
        final assetRequest = _codec.decodeAssetOpenRequest(request.payload);
        // Asset bytes are carried as base64 inside the framed JSON response;
        // use the codec's effective bound so a handler-level request can
        // always be encoded into one legal assetOpened response.
        const maxAssetBytes = AvacaApplicationCodec.maxBinaryRangeBytes;
        if (assetRequest.revision < 0 ||
            assetRequest.offset < 0 ||
            assetRequest.length <= 0 ||
            assetRequest.length > maxAssetBytes) {
          throw const ServerProtocolException(
            'asset_range_invalid',
            false,
            'requested asset range is invalid',
          );
        }
        final assetStore = assetCatalog;
        if (assetStore == null) {
          throw const ServerProtocolException(
            'asset_unavailable',
            false,
            'asset endpoint is not configured',
          );
        }
        final asset = await assetStore.findAsset(
          assetRequest.assetId,
          assetRequest.revision,
        );
        if (asset == null) {
          throw const ServerProtocolException(
            'asset_unavailable',
            false,
            'requested asset is unavailable',
          );
        }
        if (asset.length < 0 || assetRequest.offset > asset.length) {
          throw const ServerProtocolException(
            'asset_range_invalid',
            false,
            'requested asset range is invalid',
          );
        }
        final readLength = math.min(
          assetRequest.length,
          math.max(0, asset.length - assetRequest.offset),
        );
        final file = File(asset.absolutePath);
        if (!await file.exists() || await file.length() != asset.length) {
          throw const ServerProtocolException(
            'asset_unavailable',
            true,
            'requested asset is unavailable',
          );
        }
        final handle = await file.open();
        late final Uint8List bytes;
        try {
          await handle.setPosition(assetRequest.offset);
          bytes = Uint8List.fromList(await handle.read(readLength));
        } finally {
          await handle.close();
        }
        return _response(
          request,
          AvacaOpcode.assetOpened,
          _codec.encodeAssetOpened(
            AvacaAssetOpenedDto(
              assetId: assetRequest.assetId,
              revision: assetRequest.revision,
              offset: assetRequest.offset,
              bytes: bytes,
              eof: assetRequest.offset + bytes.length >= asset.length,
              mimeType: asset.mimeType,
            ),
          ),
        );
      default:
        throw const ServerProtocolException(
          'invalid_opcode',
          false,
          'request opcode is not supported',
        );
    }
  }

  AvacaFrame _response(
    AvacaFrame request,
    AvacaOpcode opcode,
    List<int> payload,
  ) => AvacaFrame(
    opcode: opcode,
    requestId: request.requestId,
    payload: payload,
  );

  String _newResourceHandle() =>
      'handle.${List<int>.generate(24, (_) => _handleRandom.nextInt(256)).map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';

  Future<void> _closeOpenResource(String resourceHandle) async {
    final open = _openResources.remove(resourceHandle);
    if (open == null) return;
    final pending = _pendingReads.values
        .where((read) => read.resourceHandle == resourceHandle)
        .toList(growable: false);
    for (final read in pending) {
      read.cancel();
    }
    for (final read in pending) {
      try {
        await read.operationDone?.timeout(const Duration(seconds: 2));
      } on Object {
        // The file operation is bounded by the connection cleanup path; do
        // not let a stuck read prevent the resource lease from being closed.
      }
    }
    await _resources.close(open.handle);
    try {
      _playbackSessions.releaseNative(
        clientId: open.clientId,
        leaseId: open.leaseId,
      );
    } on ServerLibraryException {
      // An explicit playback-session revoke already removed this lease.
    }
  }

  Future<void> close() async {
    final handles = _openResources.keys.toList(growable: false);
    for (final resourceHandle in handles) {
      await _closeOpenResource(resourceHandle);
    }
    final sessions = _playbackSessionLeases.entries.toList(growable: false);
    _playbackSessionLeases.clear();
    for (final entry in sessions) {
      try {
        _playbackSessions.detachControl(
          clientId: clientId,
          sessionId: entry.key,
          controlLeaseId: entry.value,
        );
      } on ServerLibraryException {
        // The session may already have been explicitly revoked.
      }
    }
  }
}

final class _OpenServerResource {
  const _OpenServerResource({
    required this.sessionId,
    required this.resourceId,
    required this.clientId,
    required this.leaseId,
    required this.handle,
  });

  final String sessionId;
  final String resourceId;
  final String clientId;
  final String leaseId;
  final ServerMediaResourceHandle handle;
}

final class _PendingServerRead {
  _PendingServerRead({required this.resourceHandle});

  final String resourceHandle;
  final Completer<void> cancelled = Completer<void>();
  final Completer<void> completed = Completer<void>();
  Future<void>? operationDone;

  bool cancel() {
    if (cancelled.isCompleted) return false;
    cancelled.complete();
    return true;
  }
}

final class _ReadCancelled implements Exception {
  const _ReadCancelled();
}

class ServerMediaRecord {
  const ServerMediaRecord({
    required this.mediaId,
    required this.workId,
    required this.absolutePath,
    required this.length,
    this.mimeType = 'video/x-matroska',
    this.durationMs,
  });

  final AvacaMediaId mediaId;
  final AvacaWorkId workId;
  final String absolutePath;
  final int length;
  final String mimeType;
  final int? durationMs;
}

/// SQLite authority for the Windows Server process.  It intentionally uses a
/// new `server_*` schema and database file; the root app's legacy Library DB
/// is neither opened nor migrated by this adapter.
final class ServerSqliteCatalogRepository
    implements
        ServerCatalogRepository,
        ServerCatalogWriter,
        ServerPhysicalCatalogWriter,
        ServerMetadataCatalogWriter,
        ServerMetadataFailureWriter,
        ServerReviewCatalogRepository,
        ServerManualCodeCatalog,
        ServerAssetCatalogRepository {
  ServerSqliteCatalogRepository._(this._database);

  final Database _database;
  bool _closed = false;

  static Future<ServerSqliteCatalogRepository> open({
    required String databasePath,
  }) async {
    if (!Platform.isWindows) {
      throw const ServerProtocolException(
        'windows_server_required',
        false,
        'AVACA Server catalog is Windows-only',
      );
    }
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async => _createSchema(db),
        onUpgrade: _upgradeSchema,
      ),
    );
    await _createSchema(database);
    return ServerSqliteCatalogRepository._(database);
  }

  static Future<void> _createSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS server_works (
        portable_id TEXT PRIMARY KEY,
        code TEXT NOT NULL,
        title TEXT NOT NULL,
        cover_resource_id TEXT,
        modified_at TEXT NOT NULL,
        description TEXT,
        release_date TEXT,
        metadata_state TEXT NOT NULL DEFAULT 'pending',
        metadata_error TEXT,
        metadata_source TEXT,
        metadata_source_uri TEXT,
        metadata_updated_at TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS server_media (
        portable_id TEXT PRIMARY KEY,
        work_portable_id TEXT NOT NULL,
        absolute_path TEXT NOT NULL,
        length_bytes INTEGER NOT NULL,
        mime_type TEXT NOT NULL,
        duration_ms INTEGER,
        modified_at TEXT NOT NULL,
        library_root_id TEXT,
        relative_path TEXT,
        file_name TEXT,
        identity_key TEXT,
        parsed_code TEXT,
        manual_code TEXT,
        parse_status TEXT NOT NULL DEFAULT 'unrecognized',
        variant_token TEXT,
        part_number INTEGER,
        is_present INTEGER NOT NULL DEFAULT 1,
        last_seen_at TEXT,
        metadata_state TEXT NOT NULL DEFAULT 'pending',
        parse_diagnostic TEXT,
        FOREIGN KEY(work_portable_id) REFERENCES server_works(portable_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS server_library_roots (
        root_id TEXT PRIMARY KEY,
        absolute_path TEXT NOT NULL UNIQUE,
        display_name TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        modified_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS server_performers (
        portable_id TEXT PRIMARY KEY,
        external_id TEXT,
        display_name TEXT NOT NULL,
        modified_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS server_work_performers (
        work_portable_id TEXT NOT NULL,
        performer_portable_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(work_portable_id, performer_portable_id),
        FOREIGN KEY(work_portable_id) REFERENCES server_works(portable_id),
        FOREIGN KEY(performer_portable_id) REFERENCES server_performers(portable_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS server_assets (
        asset_id TEXT NOT NULL,
        revision INTEGER NOT NULL,
        work_portable_id TEXT,
        absolute_path TEXT NOT NULL,
        length_bytes INTEGER NOT NULL,
        mime_type TEXT NOT NULL,
        modified_at TEXT NOT NULL,
        PRIMARY KEY(asset_id, revision),
        FOREIGN KEY(work_portable_id) REFERENCES server_works(portable_id)
      )
    ''');
    await _ensureColumn(database, 'server_works', 'description', 'TEXT');
    await _ensureColumn(database, 'server_works', 'release_date', 'TEXT');
    await _ensureColumn(
      database,
      'server_works',
      'metadata_state',
      "TEXT NOT NULL DEFAULT 'pending'",
    );
    await _ensureColumn(database, 'server_works', 'metadata_error', 'TEXT');
    await _ensureColumn(database, 'server_works', 'metadata_source', 'TEXT');
    await _ensureColumn(
      database,
      'server_works',
      'metadata_source_uri',
      'TEXT',
    );
    await _ensureColumn(
      database,
      'server_works',
      'metadata_updated_at',
      'TEXT',
    );
    await _ensureColumn(database, 'server_media', 'library_root_id', 'TEXT');
    await _ensureColumn(database, 'server_media', 'relative_path', 'TEXT');
    await _ensureColumn(database, 'server_media', 'file_name', 'TEXT');
    await _ensureColumn(database, 'server_media', 'identity_key', 'TEXT');
    await _ensureColumn(database, 'server_media', 'parsed_code', 'TEXT');
    await _ensureColumn(database, 'server_media', 'manual_code', 'TEXT');
    await _ensureColumn(
      database,
      'server_media',
      'parse_status',
      "TEXT NOT NULL DEFAULT 'unrecognized'",
    );
    await _ensureColumn(database, 'server_media', 'variant_token', 'TEXT');
    await _ensureColumn(database, 'server_media', 'part_number', 'INTEGER');
    await _ensureColumn(
      database,
      'server_media',
      'is_present',
      'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(database, 'server_media', 'last_seen_at', 'TEXT');
    await _ensureColumn(
      database,
      'server_media',
      'metadata_state',
      "TEXT NOT NULL DEFAULT 'pending'",
    );
    await _ensureColumn(database, 'server_media', 'parse_diagnostic', 'TEXT');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_server_works_code ON server_works(code)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_server_media_work ON server_media(work_portable_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_server_media_root ON server_media(library_root_id, is_present)',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_server_media_identity ON server_media(identity_key) WHERE identity_key IS NOT NULL',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_server_media_review ON server_media(parse_status, metadata_state, is_present)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_server_assets_work ON server_assets(work_portable_id)',
    );
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    // v1 contained the original Server catalog.  Migration is additive and
    // intentionally never drops or recreates the existing tables/rows.
    await _createSchema(database);
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor database,
    String table,
    String column,
    String declaration,
  ) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name']?.toString() == column)) return;
    await database.execute(
      'ALTER TABLE $table ADD COLUMN $column $declaration',
    );
  }

  @override
  Future<void> upsertWork(AvacaWorkSummary work) async {
    _ensureOpen();
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.rawInsert(
      '''
      INSERT INTO server_works
        (portable_id, code, title, cover_resource_id, modified_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(portable_id) DO UPDATE SET
        code = excluded.code,
        title = excluded.title,
        cover_resource_id = COALESCE(excluded.cover_resource_id, server_works.cover_resource_id),
        modified_at = excluded.modified_at
      ''',
      [work.workId.value, work.code, work.title, work.coverResourceId, now],
    );
  }

  @override
  Future<void> upsertMedia(ServerMediaRecord media) async {
    _ensureOpen();
    if (media.length < 0) {
      throw const ServerProtocolException(
        'invalid_media_length',
        false,
        'media length is invalid',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.rawInsert(
      '''
      INSERT INTO server_media
        (portable_id, work_portable_id, absolute_path, length_bytes,
         mime_type, duration_ms, modified_at, is_present, last_seen_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
      ON CONFLICT(portable_id) DO UPDATE SET
        work_portable_id = excluded.work_portable_id,
        absolute_path = excluded.absolute_path,
        length_bytes = excluded.length_bytes,
        mime_type = excluded.mime_type,
        duration_ms = excluded.duration_ms,
        modified_at = excluded.modified_at,
        is_present = 1,
        last_seen_at = excluded.last_seen_at
      ''',
      [
        media.mediaId.value,
        media.workId.value,
        p.normalize(p.absolute(media.absolutePath)),
        media.length,
        media.mimeType,
        media.durationMs,
        now,
        now,
      ],
    );
  }

  @override
  Future<void> upsertLibraryRoot(ServerLibraryRoot root) async {
    _ensureOpen();
    final now = DateTime.now().toUtc().toIso8601String();
    final absolutePath = p.normalize(p.absolute(root.absolutePath));
    await _database.rawInsert(
      '''
      INSERT INTO server_library_roots
        (root_id, absolute_path, display_name, enabled, created_at, modified_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(root_id) DO UPDATE SET
        absolute_path = excluded.absolute_path,
        display_name = excluded.display_name,
        enabled = excluded.enabled,
        modified_at = excluded.modified_at
      ''',
      [
        root.rootId,
        absolutePath,
        root.displayName,
        root.enabled ? 1 : 0,
        now,
        now,
      ],
    );
  }

  @override
  Future<void> upsertPhysicalMedia(ServerPhysicalMediaRecord media) async {
    _ensureOpen();
    if (media.length < 0) {
      throw const ServerProtocolException(
        'invalid_media_length',
        false,
        'media length is invalid',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final workId =
        media.workId ??
        AvacaWorkId('work.pending.${_stableToken(media.mediaId.value)}');
    final code = media.parse.code ?? '';
    final title = p.basenameWithoutExtension(media.fileName).trim();
    await _database.rawInsert(
      '''
      INSERT INTO server_works
        (portable_id, code, title, modified_at, metadata_state)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(portable_id) DO UPDATE SET
        code = CASE WHEN server_works.code = '' THEN excluded.code ELSE server_works.code END,
        title = CASE WHEN server_works.title = '' THEN excluded.title ELSE server_works.title END,
        modified_at = excluded.modified_at
      ''',
      [
        workId.value,
        code,
        title.isEmpty ? media.fileName : title,
        now,
        media.parse.isRecognized
            ? ServerMetadataState.pending.value
            : ServerMetadataState.pending.value,
      ],
    );
    final normalizedAbsolute = p.normalize(p.absolute(media.absolutePath));
    await _database.rawInsert(
      '''
      INSERT INTO server_media
        (portable_id, work_portable_id, absolute_path, length_bytes,
         mime_type, duration_ms, modified_at, library_root_id, relative_path,
         file_name, identity_key, parsed_code, parse_status, variant_token,
         part_number, is_present, last_seen_at, metadata_state, parse_diagnostic)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
      ON CONFLICT(portable_id) DO UPDATE SET
        work_portable_id = excluded.work_portable_id,
        absolute_path = excluded.absolute_path,
        length_bytes = excluded.length_bytes,
        mime_type = excluded.mime_type,
        duration_ms = excluded.duration_ms,
        modified_at = excluded.modified_at,
        library_root_id = excluded.library_root_id,
        relative_path = excluded.relative_path,
        file_name = excluded.file_name,
        identity_key = excluded.identity_key,
        parsed_code = COALESCE(server_media.manual_code, excluded.parsed_code),
        parse_status = CASE
          WHEN server_media.manual_code IS NOT NULL THEN 'recognized'
          ELSE excluded.parse_status
        END,
        variant_token = excluded.variant_token,
        part_number = excluded.part_number,
        is_present = 1,
        last_seen_at = excluded.last_seen_at,
        parse_diagnostic = excluded.parse_diagnostic
      ''',
      [
        media.mediaId.value,
        workId.value,
        normalizedAbsolute,
        media.length,
        media.mimeType,
        media.durationMs,
        now,
        media.rootId,
        media.relativePath,
        media.fileName,
        media.mediaId.value,
        media.parse.code,
        media.parse.status.value,
        media.parse.variantToken,
        media.parse.partNumber,
        now,
        media.parse.isRecognized
            ? ServerMetadataState.pending.value
            : ServerMetadataState.pending.value,
        media.parse.diagnostic,
      ],
    );
  }

  @override
  Future<void> markMissingPhysicalMedia({
    required String rootId,
    required Set<String> seenMediaIds,
  }) async {
    _ensureOpen();
    final rows = await _database.query(
      'server_media',
      columns: const ['portable_id'],
      where: 'library_root_id = ?',
      whereArgs: [rootId],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    for (final row in rows) {
      final mediaId = row['portable_id']?.toString();
      if (mediaId == null || seenMediaIds.contains(mediaId)) continue;
      await _database.update(
        'server_media',
        {'is_present': 0, 'modified_at': now},
        where: 'portable_id = ?',
        whereArgs: [mediaId],
      );
    }
  }

  @override
  Future<void> upsertWorkMetadata(ServerWorkMetadataRecord metadata) async {
    _ensureOpen();
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.rawInsert(
      '''
      INSERT INTO server_works
        (portable_id, code, title, modified_at, description, release_date,
         metadata_state, metadata_error, metadata_source, metadata_source_uri,
         metadata_updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(portable_id) DO UPDATE SET
        code = excluded.code,
        title = excluded.title,
        modified_at = excluded.modified_at,
        description = excluded.description,
        release_date = excluded.release_date,
        metadata_state = excluded.metadata_state,
        metadata_error = excluded.metadata_error,
        metadata_source = excluded.metadata_source,
        metadata_source_uri = excluded.metadata_source_uri,
        metadata_updated_at = excluded.metadata_updated_at
      ''',
      [
        metadata.workId.value,
        metadata.code,
        metadata.title,
        now,
        metadata.description,
        metadata.releaseDate,
        metadata.state.value,
        metadata.error,
        metadata.source,
        metadata.sourceUri,
        now,
      ],
    );
    await _database.update(
      'server_media',
      {
        'work_portable_id': metadata.workId.value,
        'metadata_state': metadata.state.value,
      },
      where: 'parsed_code = ?',
      whereArgs: [metadata.code],
    );
    await _database.delete(
      'server_work_performers',
      where: 'work_portable_id = ?',
      whereArgs: [metadata.workId.value],
    );
    for (var index = 0; index < metadata.performers.length; index++) {
      final performer = metadata.performers[index];
      await _database.rawInsert(
        '''
        INSERT INTO server_performers
          (portable_id, external_id, display_name, modified_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(portable_id) DO UPDATE SET
          external_id = excluded.external_id,
          display_name = excluded.display_name,
          modified_at = excluded.modified_at
        ''',
        [
          performer.performerId.value,
          performer.externalId,
          performer.displayName,
          now,
        ],
      );
      await _database.insert('server_work_performers', {
        'work_portable_id': metadata.workId.value,
        'performer_portable_id': performer.performerId.value,
        'sort_order': index,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final artwork = metadata.artwork;
    if (artwork != null) {
      await _database.insert('server_assets', {
        'asset_id': artwork.assetId,
        'revision': artwork.revision,
        'work_portable_id': metadata.workId.value,
        'absolute_path': p.normalize(p.absolute(artwork.absolutePath)),
        'length_bytes': artwork.length,
        'mime_type': artwork.mimeType,
        'modified_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _database.update(
        'server_works',
        {'cover_resource_id': artwork.assetId},
        where: 'portable_id = ?',
        whereArgs: [metadata.workId.value],
      );
    }
  }

  @override
  Future<void> markMetadataFailure({
    required AvacaMediaId mediaId,
    required String message,
  }) async {
    _ensureOpen();
    final safeMessage = message.trim();
    await _database.update(
      'server_media',
      {
        'metadata_state': ServerMetadataState.failed.value,
        'parse_diagnostic': safeMessage.isEmpty
            ? 'metadata resolution failed'
            : safeMessage.substring(0, math.min(safeMessage.length, 1024)),
      },
      where: 'portable_id = ?',
      whereArgs: [mediaId.value],
    );
  }

  @override
  Future<List<ServerReviewItem>> listReviewItems({
    String? rootId,
    int limit = 100,
  }) async {
    _ensureOpen();
    if (limit < 1 || limit > AvacaApplicationCodec.maxPageSize) {
      throw const ServerProtocolException(
        'invalid_review_limit',
        false,
        'review page limit is invalid',
      );
    }
    final rows = await _database.query(
      'server_media',
      columns: const [
        'portable_id',
        'file_name',
        'relative_path',
        'parse_status',
        'parse_diagnostic',
        'parsed_code',
        'variant_token',
        'metadata_state',
        'library_root_id',
      ],
      where: rootId == null
          ? "COALESCE(parse_status, 'unrecognized') <> 'recognized' OR COALESCE(metadata_state, 'pending') IN ('pending', 'failed', 'stale', 'manual')"
          : "library_root_id = ? AND (COALESCE(parse_status, 'unrecognized') <> 'recognized' OR COALESCE(metadata_state, 'pending') IN ('pending', 'failed', 'stale', 'manual'))",
      whereArgs: rootId == null ? null : [rootId],
      orderBy: 'modified_at DESC, portable_id ASC',
      limit: limit,
    );
    return rows
        .map(
          (row) => ServerReviewItem(
            mediaId: AvacaMediaId(row['portable_id']!.toString()),
            fileName: row['file_name']?.toString() ?? '',
            relativePath: row['relative_path']?.toString() ?? '',
            parseStatus: ServerPhysicalParseStatus.fromValue(
              row['parse_status']?.toString(),
            ),
            diagnostic: row['parse_diagnostic']?.toString() ?? '',
            code: row['parsed_code']?.toString(),
            variantToken: row['variant_token']?.toString(),
            metadataState: ServerMetadataState.fromValue(
              row['metadata_state']?.toString(),
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> applyManualCode({
    required AvacaMediaId mediaId,
    required String code,
  }) async {
    _ensureOpen();
    final normalized = code.trim().toUpperCase();
    final parsed = const ServerFilenameParser().parse('$normalized.mkv');
    if (normalized.isEmpty ||
        normalized.length > 64 ||
        !parsed.isRecognized ||
        parsed.code == null) {
      throw const ServerProtocolException(
        'invalid_manual_code',
        false,
        'manual work code is invalid',
      );
    }
    final changed = await _database.update(
      'server_media',
      {
        'parsed_code': parsed.code,
        'manual_code': parsed.code,
        'parse_status': ServerPhysicalParseStatus.recognized.value,
        'parse_diagnostic': 'manual code correction validated',
        'metadata_state': ServerMetadataState.manual.value,
      },
      where: 'portable_id = ?',
      whereArgs: [mediaId.value],
    );
    if (changed == 0) {
      throw const ServerProtocolException(
        'media_not_found',
        false,
        'requested physical media was not found',
      );
    }
  }

  @override
  Future<String?> findManualCode(AvacaMediaId mediaId) async {
    _ensureOpen();
    final rows = await _database.query(
      'server_media',
      columns: const ['manual_code'],
      where: 'portable_id = ?',
      whereArgs: [mediaId.value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.single['manual_code']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<ServerAssetRecord?> findAsset(String assetId, int revision) async {
    _ensureOpen();
    if (assetId.trim().isEmpty || revision < 0) return null;
    final rows = await _database.query(
      'server_assets',
      columns: const [
        'asset_id',
        'revision',
        'absolute_path',
        'length_bytes',
        'mime_type',
      ],
      where: 'asset_id = ? AND revision = ?',
      whereArgs: [assetId, revision],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ServerAssetRecord(
      assetId: row['asset_id']!.toString(),
      revision: (row['revision'] as num).toInt(),
      absolutePath: row['absolute_path']!.toString(),
      length: (row['length_bytes'] as num).toInt(),
      mimeType: row['mime_type']!.toString(),
    );
  }

  String _stableToken(String value) {
    final digest = crypto.sha256.convert(utf8.encode(value));
    return digest.toString().substring(0, 32);
  }

  @override
  Future<AvacaCollectionPage> listCollection({
    String? cursor,
    int limit = 50,
  }) async {
    _ensureOpen();
    if (limit < 1 || limit > AvacaApplicationCodec.maxPageSize) {
      throw const ServerProtocolException(
        'invalid_page_limit',
        false,
        'collection page limit is invalid',
      );
    }
    var candidateOffset = _decodeCursor(cursor);
    final playableRows = <({Map<String, Object?> row, int index})>[];
    var exhausted = false;
    var scanBudgetReached = false;
    var scannedCandidates = 0;
    final maxCandidatesPerRequest = math.max(limit * 8, limit + 1);
    // A missing/stale media row must not make a metadata-only Work appear in
    // Collection.  Scan bounded batches so a large set of stale rows cannot
    // monopolise one request; the cursor tracks the underlying candidate
    // offset, not the number of visible rows.
    while (playableRows.length <= limit && !exhausted) {
      final remainingBudget = maxCandidatesPerRequest - scannedCandidates;
      if (remainingBudget <= 0) {
        scanBudgetReached = true;
        break;
      }
      final rows = await _database.rawQuery(
        '''
        SELECT w.portable_id, w.code, w.title, w.cover_resource_id
        FROM server_works w
        WHERE EXISTS (
          SELECT 1 FROM server_media m
          WHERE m.work_portable_id = w.portable_id
        )
        ORDER BY w.modified_at DESC, w.portable_id ASC
        LIMIT ? OFFSET ?
        ''',
        [math.min(limit, remainingBudget), candidateOffset],
      );
      if (rows.isEmpty) {
        exhausted = true;
        break;
      }
      final batchStart = candidateOffset;
      candidateOffset += rows.length;
      scannedCandidates += rows.length;
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        if (await _workHasPlayableMedia(row['portable_id']!.toString())) {
          playableRows.add((row: row, index: batchStart + index));
          if (playableRows.length > limit) break;
        }
      }
      if (rows.length < math.min(limit, remainingBudget)) {
        exhausted = true;
      } else if (scannedCandidates >= maxCandidatesPerRequest &&
          playableRows.length <= limit) {
        scanBudgetReached = true;
      }
    }
    final hasMore = playableRows.length > limit || scanBudgetReached;
    final pageRows = playableRows
        .take(limit)
        .map((entry) => entry.row)
        .toList(growable: false);
    return AvacaCollectionPage(
      items: pageRows
          .map(
            (row) => AvacaWorkSummary(
              workId: AvacaWorkId(row['portable_id']!.toString()),
              code: row['code']!.toString(),
              title: row['title']!.toString(),
              coverResourceId: row['cover_resource_id']?.toString(),
            ),
          )
          .toList(growable: false),
      nextCursor: hasMore
          ? _encodeCursor(
              playableRows.length > limit
                  ? playableRows[limit].index
                  : candidateOffset,
            )
          : null,
    );
  }

  Future<bool> _workHasPlayableMedia(String workId) async {
    final rows = await _database.query(
      'server_media',
      columns: const ['absolute_path', 'length_bytes', 'is_present'],
      where: 'work_portable_id = ? AND COALESCE(is_present, 1) = 1',
      whereArgs: [workId],
      limit: AvacaApplicationCodec.maxPageSize,
    );
    for (final row in rows) {
      if (await _mediaRowIsPlayable(row)) return true;
    }
    return false;
  }

  Future<bool> _mediaRowIsPlayable(Map<String, Object?> row) async {
    final path = row['absolute_path']?.toString().trim() ?? '';
    final expectedLength = (row['length_bytes'] as num?)?.toInt() ?? -1;
    if (path.isEmpty || expectedLength < 0) return false;
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      return await file.length() == expectedLength;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<AvacaWorkDetail> getWorkDetail(AvacaWorkId workId) async {
    _ensureOpen();
    final rows = await _database.query(
      'server_works',
      columns: const [
        'portable_id',
        'code',
        'title',
        'cover_resource_id',
        'description',
        'release_date',
      ],
      where: 'portable_id = ?',
      whereArgs: [workId.value],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const ServerProtocolException(
        'work_not_found',
        false,
        'requested work was not found',
      );
    }
    final row = rows.single;
    final resolvedWorkId = AvacaWorkId(row['portable_id']!.toString());
    final mediaRows = await _database.query(
      'server_media',
      columns: const [
        'portable_id',
        'work_portable_id',
        'absolute_path',
        'length_bytes',
        'mime_type',
        'duration_ms',
        'is_present',
        'parsed_code',
      ],
      where: 'work_portable_id = ?',
      whereArgs: [resolvedWorkId.value],
      orderBy: 'portable_id ASC',
      limit: AvacaApplicationCodec.maxPageSize,
    );
    final media = await Future.wait(
      mediaRows.map((mediaRow) async {
        final mediaId = AvacaMediaId(mediaRow['portable_id']!.toString());
        final path = mediaRow['absolute_path']?.toString().trim() ?? '';
        final expectedLength =
            (mediaRow['length_bytes'] as num?)?.toInt() ?? -1;
        var availability = AvacaMediaAvailability.unknown;
        final isPresent = (mediaRow['is_present'] as num?)?.toInt() != 0;
        if (!isPresent) {
          availability = AvacaMediaAvailability.unavailable;
        } else if (path.isNotEmpty && expectedLength >= 0) {
          final file = File(path);
          if (await file.exists()) {
            availability = await file.length() == expectedLength
                ? AvacaMediaAvailability.available
                : AvacaMediaAvailability.unavailable;
          } else {
            availability = AvacaMediaAvailability.unavailable;
          }
        }
        return AvacaMediaSummary(
          mediaId: mediaId,
          workId: resolvedWorkId,
          code: mediaRow['parsed_code']?.toString().isNotEmpty == true
              ? mediaRow['parsed_code']!.toString()
              : row['code']!.toString(),
          title: row['title']!.toString(),
          durationMs: (mediaRow['duration_ms'] as num?)?.toInt(),
          availability: availability,
        );
      }),
    );
    final performerRows = await _database.rawQuery(
      '''
      SELECT p.portable_id, p.external_id, p.display_name
      FROM server_performers p
      INNER JOIN server_work_performers wp
        ON wp.performer_portable_id = p.portable_id
      WHERE wp.work_portable_id = ?
      ORDER BY wp.sort_order ASC, p.portable_id ASC
      LIMIT ?
      ''',
      [resolvedWorkId.value, 1024],
    );
    return AvacaWorkDetail(
      workId: resolvedWorkId,
      code: row['code']!.toString(),
      title: row['title']!.toString(),
      description: row['description']?.toString(),
      releaseDate: row['release_date']?.toString(),
      performers: performerRows
          .map(
            (performer) => AvacaPerformerSummary(
              actressId: AvacaActressId(performer['portable_id']!.toString()),
              displayName: performer['display_name']!.toString(),
            ),
          )
          .toList(growable: false),
      coverResourceId: row['cover_resource_id']?.toString(),
      media: media,
    );
  }

  Future<ServerPlaybackSelection?> findPlayback(AvacaMediaId mediaId) async {
    _ensureOpen();
    final rows = await _database.query(
      'server_media',
      columns: const [
        'portable_id',
        'work_portable_id',
        'absolute_path',
        'length_bytes',
        'mime_type',
        'duration_ms',
        'is_present',
      ],
      where: 'portable_id = ?',
      whereArgs: [mediaId.value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    if ((row['is_present'] as num?)?.toInt() == 0) return null;
    final path = row['absolute_path']?.toString().trim() ?? '';
    final file = File(path);
    if (path.isEmpty || !await file.exists()) return null;
    final storedLength = (row['length_bytes'] as num?)?.toInt() ?? -1;
    final actualLength = await file.length();
    if (storedLength < 0 || actualLength != storedLength) return null;
    return ServerPlaybackSelection(
      mediaId: mediaId,
      resourceId: 'resource.${mediaId.value}',
      absolutePath: path,
      length: actualLength,
      mimeType: row['mime_type']?.toString() ?? 'application/octet-stream',
      durationMs: (row['duration_ms'] as num?)?.toInt(),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _database.close();
  }

  void _ensureOpen() {
    if (_closed) {
      throw const ServerProtocolException(
        'catalog_closed',
        false,
        'Server catalog is closed',
      );
    }
  }

  int _decodeCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) return 0;
    try {
      final value = int.parse(cursor);
      if (value < 0 || value > 0x7fffffff) throw const FormatException();
      return value;
    } on FormatException {
      throw const ServerProtocolException(
        'invalid_cursor',
        false,
        'collection cursor is invalid',
      );
    }
  }

  String _encodeCursor(int value) => value.toString();
}

enum ServerImportStage {
  scanning,
  resolving,
  indexing,
  reviewing,
  completed,
  cancelled,
}

class ServerImportProgress {
  const ServerImportProgress({
    required this.stage,
    required this.completed,
    required this.total,
    required this.elapsed,
    this.fileName,
  });

  final ServerImportStage stage;
  final int completed;
  final int total;
  final Duration elapsed;
  final String? fileName;
}

class ServerImportResult {
  const ServerImportResult({
    required this.scanned,
    required this.imported,
    required this.skipped,
    required this.failed,
    required this.cancelled,
    required this.scanDuration,
    required this.resolveDuration,
    required this.indexDuration,
    this.physicalIndexed = 0,
    this.needsReview = 0,
    this.metadataResolved = 0,
    this.metadataFailed = 0,
  });

  final int scanned;
  final int imported;
  final int skipped;
  final int failed;
  final bool cancelled;
  final Duration scanDuration;
  final Duration resolveDuration;
  final Duration indexDuration;
  final int physicalIndexed;
  final int needsReview;
  final int metadataResolved;
  final int metadataFailed;

  Duration get totalDuration => scanDuration + resolveDuration + indexDuration;
}

typedef ServerImportProgressCallback =
    void Function(ServerImportProgress progress);

/// Windows Server folder indexer.  It is intentionally independent from the
/// legacy root importer: the Server records existing physical media in its
/// own `server_*` schema, while scraping remains an injected Server concern.
/// No client-facing DTO contains the discovered paths.
final class ServerFolderImportService {
  ServerFolderImportService({
    required this.catalogWriter,
    this.scraper,
    this.maxFiles = 10000,
  });

  static const Set<String> supportedExtensions = <String>{
    'avi',
    'flv',
    'm4v',
    'mkv',
    'mov',
    'mp4',
    'mpeg',
    'mpg',
    'ts',
    'webm',
    'wmv',
  };

  final ServerCatalogWriter catalogWriter;
  final AvacaScraper? scraper;
  final int maxFiles;
  final ServerFilenameParser parser = const ServerFilenameParser();

  Future<ServerImportResult> importFolder(
    String folderPath, {
    bool Function()? isCancelled,
    ServerImportProgressCallback? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw const ServerProtocolException(
        'windows_server_required',
        false,
        'AVACA Server import is Windows-only',
      );
    }
    if (maxFiles < 1) {
      throw const ServerProtocolException(
        'invalid_import_limit',
        false,
        'Server import file limit is invalid',
      );
    }
    final requestedRoot = folderPath.trim();
    if (requestedRoot.isEmpty) {
      throw const ServerProtocolException(
        'invalid_import_root',
        false,
        'Server import root is empty',
      );
    }
    final root = p.normalize(p.absolute(requestedRoot));
    final directory = Directory(root);
    if (!await directory.exists()) {
      throw const ServerProtocolException(
        'import_root_missing',
        false,
        'Server import root does not exist',
      );
    }

    final stopwatch = Stopwatch()..start();
    final rootId = _rootId(root);
    final physicalWriter = catalogWriter is ServerPhysicalCatalogWriter
        ? catalogWriter as ServerPhysicalCatalogWriter
        : null;
    final metadataWriter = catalogWriter is ServerMetadataCatalogWriter
        ? catalogWriter as ServerMetadataCatalogWriter
        : null;
    final failureWriter = catalogWriter is ServerMetadataFailureWriter
        ? catalogWriter as ServerMetadataFailureWriter
        : null;
    final manualCodeCatalog = catalogWriter is ServerManualCodeCatalog
        ? catalogWriter as ServerManualCodeCatalog
        : null;
    if (physicalWriter != null) {
      await physicalWriter.upsertLibraryRoot(
        ServerLibraryRoot(rootId: rootId, absolutePath: root),
      );
    }
    final files = <_ServerImportFile>[];
    var failed = 0;
    var limitExceeded = false;
    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (isCancelled?.call() ?? false) {
          return ServerImportResult(
            scanned: files.length,
            imported: 0,
            skipped: files.length,
            failed: failed,
            cancelled: true,
            scanDuration: stopwatch.elapsed,
            resolveDuration: Duration.zero,
            indexDuration: Duration.zero,
          );
        }
        if (entity is! File) continue;
        try {
          final type = await FileSystemEntity.type(
            entity.path,
            followLinks: false,
          );
          if (type != FileSystemEntityType.file) continue;
          final extension = p
              .extension(entity.path)
              .toLowerCase()
              .replaceFirst('.', '');
          if (!supportedExtensions.contains(extension)) continue;
          if (files.length >= maxFiles) {
            limitExceeded = true;
            break;
          }
          final stat = await entity.stat();
          final absolutePath = p.normalize(p.absolute(entity.path));
          files.add(
            _ServerImportFile(
              path: absolutePath,
              relativePath: p.normalize(p.relative(absolutePath, from: root)),
              fileName: p.basename(absolutePath),
              extension: extension,
              size: stat.size,
              modifiedAt: stat.modified,
            ),
          );
        } on FileSystemException {
          // A disappeared or inaccessible file must not abort the whole
          // import.  It is counted and the next item can still proceed.
          failed++;
        }
      }
    } on FileSystemException {
      throw const ServerProtocolException(
        'import_scan_failed',
        true,
        'Server could not enumerate the import root',
      );
    }
    if (limitExceeded) {
      throw const ServerProtocolException(
        'import_limit_exceeded',
        false,
        'Server import contains more supported files than the configured limit',
      );
    }
    files.sort(
      (left, right) =>
          left.path.toLowerCase().compareTo(right.path.toLowerCase()),
    );
    final scanDuration = stopwatch.elapsed;
    onProgress?.call(
      ServerImportProgress(
        stage: ServerImportStage.scanning,
        completed: files.length,
        total: files.length,
        elapsed: scanDuration,
      ),
    );

    var imported = 0;
    var skipped = 0;
    var resolveDuration = Duration.zero;
    var indexDuration = Duration.zero;
    var physicalIndexed = 0;
    var needsReview = 0;
    var metadataResolved = 0;
    var metadataFailed = 0;
    final seenMediaIds = <String>{};
    for (var index = 0; index < files.length; index++) {
      final item = files[index];
      if (isCancelled?.call() ?? false) {
        onProgress?.call(
          ServerImportProgress(
            stage: ServerImportStage.cancelled,
            completed: index,
            total: files.length,
            elapsed: stopwatch.elapsed,
            fileName: p.basename(item.path),
          ),
        );
        return ServerImportResult(
          scanned: files.length,
          imported: imported,
          skipped: skipped,
          failed: failed,
          cancelled: true,
          scanDuration: scanDuration,
          resolveDuration: resolveDuration,
          indexDuration: indexDuration,
        );
      }
      final mediaId = AvacaMediaId(_mediaId(rootId, item.relativePath));
      var parse = parser.parse(item.fileName);
      final manualCode = await manualCodeCatalog?.findManualCode(mediaId);
      if (manualCode != null) {
        parse = parser.applyManualCode(parse, manualCode);
      }
      onProgress?.call(
        ServerImportProgress(
          stage: parse.isRecognized
              ? ServerImportStage.resolving
              : ServerImportStage.reviewing,
          completed: index,
          total: files.length,
          elapsed: stopwatch.elapsed,
          fileName: p.basename(item.path),
        ),
      );
      if (physicalWriter != null) {
        try {
          await physicalWriter.upsertPhysicalMedia(
            ServerPhysicalMediaRecord(
              mediaId: mediaId,
              rootId: rootId,
              absolutePath: item.path,
              relativePath: item.relativePath,
              fileName: item.fileName,
              length: item.size,
              modifiedAt: item.modifiedAt,
              parse: parse,
              mimeType: _mimeType(item.extension),
            ),
          );
          imported++;
          physicalIndexed++;
          seenMediaIds.add(mediaId.value);
        } on Object {
          failed++;
        }
      } else if (!parse.isRecognized) {
        // Legacy test compositions that only implement the pre-recovery
        // writer cannot persist a physical review row.  Production Server
        // repositories always implement ServerPhysicalCatalogWriter, so a
        // real scan never silently drops this item.
        skipped++;
      }

      if (!parse.isRecognized) {
        needsReview++;
        onProgress?.call(
          ServerImportProgress(
            stage: ServerImportStage.reviewing,
            completed: index + 1,
            total: files.length,
            elapsed: stopwatch.elapsed,
            fileName: item.fileName,
          ),
        );
        continue;
      }

      final code = parse.code!;
      final resolveStart = stopwatch.elapsed;
      AvacaWorkSummary? work;
      AvacaWorkMetadata? richMetadata;
      try {
        final currentScraper = scraper;
        if (currentScraper is AvacaRichScraper) {
          final details = await (currentScraper as AvacaRichScraper)
              .resolveWorkDetails(code);
          richMetadata = details;
          work = details.summary;
        } else if (currentScraper != null) {
          work = await currentScraper.resolveWork(code);
        }
      } on Object catch (error) {
        failed++;
        metadataFailed++;
        resolveDuration += stopwatch.elapsed - resolveStart;
        await failureWriter?.markMetadataFailure(
          mediaId: mediaId,
          message: error.toString(),
        );
      }
      resolveDuration += stopwatch.elapsed - resolveStart;
      if (isCancelled?.call() ?? false) {
        onProgress?.call(
          ServerImportProgress(
            stage: ServerImportStage.cancelled,
            completed: index,
            total: files.length,
            elapsed: stopwatch.elapsed,
            fileName: p.basename(item.path),
          ),
        );
        return ServerImportResult(
          scanned: files.length,
          imported: imported,
          skipped: skipped,
          failed: failed,
          cancelled: true,
          scanDuration: scanDuration,
          resolveDuration: resolveDuration,
          indexDuration: indexDuration,
          physicalIndexed: physicalIndexed,
          needsReview: needsReview,
          metadataResolved: metadataResolved,
          metadataFailed: metadataFailed,
        );
      }
      if (work == null) {
        if (scraper == null) needsReview++;
      } else {
        final indexStart = stopwatch.elapsed;
        try {
          if (metadataWriter != null) {
            final metadata = richMetadata;
            await metadataWriter.upsertWorkMetadata(
              metadata == null
                  ? ServerWorkMetadataRecord(
                      workId: work.workId,
                      code: work.code,
                      title: work.title,
                      state: ServerMetadataState.resolved,
                    )
                  : ServerWorkMetadataRecord.fromScrape(metadata),
            );
            metadataResolved++;
          } else {
            await catalogWriter.upsertWork(work);
            if (physicalWriter == null) {
              await catalogWriter.upsertMedia(
                ServerMediaRecord(
                  mediaId: mediaId,
                  workId: work.workId,
                  absolutePath: item.path,
                  length: item.size,
                  mimeType: _mimeType(item.extension),
                ),
              );
              imported++;
            }
            metadataResolved++;
          }
        } on Object catch (error) {
          failed++;
          metadataFailed++;
          await failureWriter?.markMetadataFailure(
            mediaId: mediaId,
            message: error.toString(),
          );
        }
        indexDuration += stopwatch.elapsed - indexStart;
      }
      onProgress?.call(
        ServerImportProgress(
          stage: ServerImportStage.indexing,
          completed: index + 1,
          total: files.length,
          elapsed: stopwatch.elapsed,
          fileName: item.fileName,
        ),
      );
    }
    if (physicalWriter != null) {
      await physicalWriter.markMissingPhysicalMedia(
        rootId: rootId,
        seenMediaIds: seenMediaIds,
      );
    }
    onProgress?.call(
      ServerImportProgress(
        stage: ServerImportStage.completed,
        completed: files.length,
        total: files.length,
        elapsed: stopwatch.elapsed,
      ),
    );
    return ServerImportResult(
      scanned: files.length,
      imported: imported,
      skipped: skipped,
      failed: failed,
      cancelled: false,
      scanDuration: scanDuration,
      resolveDuration: resolveDuration,
      indexDuration: indexDuration,
      physicalIndexed: physicalIndexed,
      needsReview: needsReview,
      metadataResolved: metadataResolved,
      metadataFailed: metadataFailed,
    );
  }

  String _mediaId(String rootId, String relativePath) {
    final digest = crypto.sha256.convert(
      utf8.encode('$rootId\u0000$relativePath'),
    );
    return 'media.${digest.toString().substring(0, 32)}';
  }

  String _rootId(String root) {
    final digest = crypto.sha256.convert(utf8.encode(root.toLowerCase()));
    return 'root.${digest.toString().substring(0, 24)}';
  }

  String _mimeType(String extension) => switch (extension) {
    'mkv' => 'video/x-matroska',
    'webm' => 'video/webm',
    'mp4' || 'm4v' => 'video/mp4',
    'mov' => 'video/quicktime',
    _ => 'video/$extension',
  };
}

final class _ServerImportFile {
  const _ServerImportFile({
    required this.path,
    required this.relativePath,
    required this.fileName,
    required this.extension,
    required this.size,
    required this.modifiedAt,
  });

  final String path;
  final String relativePath;
  final String fileName;
  final String extension;
  final int size;
  final DateTime modifiedAt;
}
