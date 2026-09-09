import 'client_profile.dart';
import 'discovery.dart';

/// Resolves a trusted client profile from an invitation and an optional mDNS
/// endpoint candidate.
///
/// Discovery is deliberately treated as an address hint.  It can replace
/// only the invitation host after every identity field that is advertised by
/// discovery has matched the invitation.  The invitation remains the source
/// of the client id, certificate pin, port, and pairing secret.
final class AvacaPairingEndpointResolver {
  AvacaPairingEndpointResolver({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Returns only candidates that can safely replace the invitation host.
  ///
  /// An expired invitation is rejected rather than silently falling back to
  /// its direct endpoint.  This keeps preview and confirmation subject to the
  /// same expiry boundary.
  List<AvacaRemoteDiscoveryEvent> matchingCandidates(
    AvacaPairingInvitation invitation,
    Iterable<AvacaRemoteDiscoveryEvent> events,
  ) {
    _checkInvitationActive(invitation);
    return events
        .where((event) => matches(invitation, event))
        .toList(growable: false);
  }

  /// Checks the complete non-secret identity tuple required for endpoint
  /// substitution.  No network probe is performed here.
  bool matches(
    AvacaPairingInvitation invitation,
    AvacaRemoteDiscoveryEvent event,
  ) {
    _checkInvitationActive(invitation);
    return event.candidate.protocolVersion == 2 &&
        event.candidate.serverId == invitation.serverId &&
        event.candidate.port == invitation.port &&
        event.endpoint.port == invitation.port &&
        _sameBytes(
          event.candidate.leafCertificateSha256,
          invitation.leafCertificateSha256,
        );
  }

  /// Creates the final trusted profile after the user has accepted the
  /// preview.  A discovery event can contribute its host only when it is an
  /// exact match; every trust-bearing field is copied from the invitation.
  AvacaRemoteClientProfile createProfile(
    AvacaPairingInvitation invitation, {
    AvacaRemoteDiscoveryEvent? selectedMatchingCandidate,
  }) {
    _checkInvitationActive(invitation);
    if (selectedMatchingCandidate != null &&
        !matches(invitation, selectedMatchingCandidate)) {
      throw StateError(
        'discovery endpoint does not match the pairing invitation',
      );
    }
    return AvacaRemoteClientProfile(
      serverId: invitation.serverId,
      clientId: invitation.clientId,
      host: selectedMatchingCandidate?.endpoint.host ?? invitation.host,
      port: invitation.port,
      leafCertificateSha256: invitation.leafCertificateSha256,
      pairingSecret: invitation.pairingSecret,
    );
  }

  void _checkInvitationActive(AvacaPairingInvitation invitation) {
    if (!invitation.expiresAt.isAfter(_clock().toUtc())) {
      throw const FormatException('pairing invitation has expired');
    }
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
