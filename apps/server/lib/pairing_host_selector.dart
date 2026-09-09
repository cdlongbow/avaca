import 'dart:io';

/// Selects a usable local IPv4 address for a cross-device pairing invitation.
///
/// This class only chooses an address to display.  It does not bind a second
/// listener and it does not provide any pairing or certificate authority.
final class AvacaPairingHostSelector {
  const AvacaPairingHostSelector._();

  static Future<String?> select() async {
    final hosts = await selectAll();
    return hosts.isEmpty ? null : hosts.first;
  }

  static Future<List<String>> selectAll() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return selectAllFromAddresses(
      interfaces.expand((networkInterface) => networkInterface.addresses),
    );
  }

  /// Pure selection seam used by the Server UI and its focused tests.
  static String? selectFromAddresses(Iterable<InternetAddress> addresses) {
    final hosts = selectAllFromAddresses(addresses);
    return hosts.isEmpty ? null : hosts.first;
  }

  /// Returns every usable address in deterministic preference order so the UI
  /// can offer an explicit choice when a Windows host has multiple NICs.
  static List<String> selectAllFromAddresses(
    Iterable<InternetAddress> addresses,
  ) {
    final candidates = <String, List<int>>{};
    for (final address in addresses) {
      if (address.type != InternetAddressType.IPv4) continue;
      final raw = address.rawAddress;
      if (!_isUsableIpv4(raw)) continue;
      candidates[address.address] = List<int>.from(raw);
    }
    if (candidates.isEmpty) return const <String>[];

    final sorted = candidates.entries.toList(growable: false)
      ..sort((left, right) {
        final rank = _scopeRank(left.value).compareTo(_scopeRank(right.value));
        if (rank != 0) return rank;
        for (var index = 0; index < left.value.length; index++) {
          final byteOrder = left.value[index].compareTo(right.value[index]);
          if (byteOrder != 0) return byteOrder;
        }
        return left.key.compareTo(right.key);
      });
    return sorted.map((entry) => entry.key).toList(growable: false);
  }

  static bool _isUsableIpv4(List<int> bytes) {
    if (bytes.length != 4) return false;
    if (bytes[0] == 127) return false;
    if (bytes.every((byte) => byte == 0)) return false;
    // 224.0.0.0/4 is multicast; 255.255.255.255 is the limited broadcast.
    if (bytes[0] >= 224) return false;
    return true;
  }

  static int _scopeRank(List<int> bytes) {
    if (bytes[0] == 10) return 0;
    if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) return 1;
    if (bytes[0] == 192 && bytes[1] == 168) return 2;
    return 3;
  }
}
