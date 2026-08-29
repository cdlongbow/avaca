import 'package:flutter/foundation.dart';

enum RemoteDiagnosticLevel { info, warning, error }

class RemoteDiagnostic {
  const RemoteDiagnostic({
    required this.level,
    required this.event,
    this.state,
    this.failureCode,
  });

  final RemoteDiagnosticLevel level;
  final String event;
  final String? state;
  final String? failureCode;
}

abstract interface class RemoteDiagnosticsSink {
  void record(RemoteDiagnostic diagnostic);
}

class NoopRemoteDiagnosticsSink implements RemoteDiagnosticsSink {
  const NoopRemoteDiagnosticsSink();

  @override
  void record(RemoteDiagnostic diagnostic) {}
}

/// Production diagnostics contain only allowlisted structural fields.
class DebugPrintRemoteDiagnosticsSink implements RemoteDiagnosticsSink {
  const DebugPrintRemoteDiagnosticsSink();

  @override
  void record(RemoteDiagnostic diagnostic) {
    final state = diagnostic.state;
    final failureCode = diagnostic.failureCode;
    final suffix = <String>[
      if (state != null) 'state=$state',
      if (failureCode != null) 'code=$failureCode',
    ];
    debugPrint(
      '[remote] ${diagnostic.level.name}: ${diagnostic.event}'
      '${suffix.isEmpty ? '' : ' (${suffix.join(', ')})'}',
    );
  }
}
