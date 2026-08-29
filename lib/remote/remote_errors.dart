enum RemoteFailureCode {
  invalidInput,
  malformedFrame,
  frameTooLarge,
  truncatedFrame,
  invalidState,
  authenticationFailed,
  authenticationExpired,
  replayDetected,
  unknownPeer,
  revokedPeer,
  pairingExpired,
  pairingConsumed,
  secretStorageUnavailable,
  secretStorageCorrupt,
  stateCorrupt,
  expiredDiscovery,
  staleDiscovery,
  unsupported,
  unavailable,
  rangeInvalid,
  resourceNotFound,
  resourceClosed,
  timeout,
  cancelled,
  connectionFailed,
  internal,
}

/// Typed errors used at Remote boundaries.
///
/// Messages intentionally contain only structural information. Callers must
/// not put keys, pairing secrets, decrypted records, media bytes, or paths in
/// [message].
class RemoteException implements Exception {
  const RemoteException(this.code, this.message);

  final RemoteFailureCode code;
  final String message;

  @override
  String toString() => 'RemoteException(${code.name}): $message';
}

class RemoteSecureStorageUnavailableException extends RemoteException {
  const RemoteSecureStorageUnavailableException()
    : super(
        RemoteFailureCode.secretStorageUnavailable,
        'A user-scoped secure secret store is unavailable on this platform.',
      );
}
