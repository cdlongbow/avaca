/// Centralized bounds for the first Remote Connectivity Core phase.
///
/// These limits are deliberately conservative. They are protocol limits, not
/// UI limits, and every decoder must enforce them before allocating memory.
abstract final class RemoteLimits {
  static const protocolVersion = 1;
  static const channelBindingBytes = 32;
  static const preAuthFrameBytes = 1024;
  static const authFrameBytes = 16 * 1024;
  static const applicationFrameBytes = 1024 * 1024;
  static const maxIdentifierBytes = 1024;
  static const maxDiscoveryEndpoints = 16;
  static const maxDiscoveryRecordBytes = 900;
  static const maxDiscoveryEnvelopeBytes = 1000;
  static const maxPairedDevices = 64;
  static const maxUnauthenticatedSessions = 32;
  static const maxAuthenticatedRequestsPerSession = 16;
  static const maxReadBytes = 4 * 1024 * 1024;
  static const maxBufferedBytesPerSession = 16 * 1024 * 1024;
  static const authTimeout = Duration(seconds: 10);
  static const connectionTimeout = Duration(seconds: 15);
  static const idleTimeout = Duration(seconds: 60);
  static const pairingLifetime = Duration(minutes: 5);
  static const discoveryLifetime = Duration(hours: 2);
  static const discoveryClockSkew = Duration(minutes: 2);
  static const preAuthClockSkew = Duration(seconds: 30);
  static const maxEndpointHostBytes = 256;
  static const maxEndpointPort = 65535;
  static const maxResourceIdBytes = 128;
  static const maxAuthFailuresPerSource = 8;
  static const authFailureWindow = Duration(minutes: 5);
  static const maxReplayEntries = 512;
}
