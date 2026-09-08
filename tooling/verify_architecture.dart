import 'dart:io';

/// Static composition check for the separated applications.  This deliberately
/// runs without Flutter or a database so CI can fail before a wrong package is
/// bundled into either executable.
void main() {
  final failures = <String>[];
  final root = Directory.current;
  final server = Directory(
    '${root.path}${Platform.pathSeparator}apps${Platform.pathSeparator}server',
  );
  final client = Directory(
    '${root.path}${Platform.pathSeparator}apps${Platform.pathSeparator}avaca',
  );
  for (final directory in [server, client]) {
    if (!directory.existsSync()) {
      failures.add('missing application: ${directory.path}');
    }
  }
  if (Directory(
    '${server.path}${Platform.pathSeparator}android',
  ).existsSync()) {
    failures.add('AVACA Server must remain Windows-only');
  }
  for (final platform in ['windows', 'android']) {
    if (!Directory(
      '${client.path}${Platform.pathSeparator}$platform',
    ).existsSync()) {
      failures.add('AVACA client is missing its $platform target');
    }
  }
  if (!Directory(
    '${server.path}${Platform.pathSeparator}windows',
  ).existsSync()) {
    failures.add('AVACA Server is missing its Windows target');
  }
  final rootMain = File(
    '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}main.dart',
  );
  if (!rootMain.existsSync()) {
    failures.add('root migration fixture entrypoint is missing');
  } else {
    final entrypoint = RegExp(
      r'void main\(\)\s*\{([\s\S]*?)\n\}',
      multiLine: true,
    ).firstMatch(rootMain.readAsStringSync())?.group(1);
    if (entrypoint == null ||
        !entrypoint.contains('runApp(const _LegacyTargetNotice())')) {
      failures.add('root target must remain a lightweight migration fixture');
    }
    if (entrypoint != null &&
        (entrypoint.contains('AppDatabase(') ||
            entrypoint.contains('RemoteServiceCoordinator') ||
            entrypoint.contains('LibraryImportRecoveryService') ||
            entrypoint.contains('await '))) {
      failures.add('root target main must not start legacy services');
    }
  }
  final protocol = File(
    '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}avaca_protocol${Platform.pathSeparator}lib${Platform.pathSeparator}avaca_protocol.dart',
  );
  if (!protocol.existsSync() ||
      !protocol.readAsStringSync().contains('static const version = 2')) {
    failures.add('protocol v2 package is missing or not pinned to version 2');
  }
  _scanDart(
    server,
    failures,
    forbidden: const ['avaca_player_native', 'package:avaca/'],
  );
  _scanDart(
    client,
    failures,
    forbidden: const [
      'avaca_library',
      'avaca_scraper',
      'package:avaca/',
      'package:avaca/library',
      'package:avaca/services/scrape',
    ],
  );
  for (final packageName in [
    'avaca_domain',
    'avaca_protocol',
    'avaca_remote_core',
  ]) {
    _scanDart(
      Directory(
        '${root.path}${Platform.pathSeparator}packages${Platform.pathSeparator}$packageName${Platform.pathSeparator}lib',
      ),
      failures,
      forbidden: const ['package:flutter', 'package:avaca/'],
      skipFileNames: packageName == 'avaca_remote_core'
          ? const {'profile_store.dart'}
          : const <String>{},
    );
  }
  _checkDependencyCycles(root, failures);
  final serverPubspec = File(
    '${server.path}${Platform.pathSeparator}pubspec.yaml',
  );
  final clientPubspec = File(
    '${client.path}${Platform.pathSeparator}pubspec.yaml',
  );
  if (serverPubspec.existsSync() &&
      !serverPubspec.readAsStringSync().contains('name: avaca_server')) {
    failures.add('Server display/package name must remain AVACA Server');
  }
  if (clientPubspec.existsSync() &&
      !clientPubspec.readAsStringSync().contains('name: avaca_client_app')) {
    failures.add('client package name is not avaca_client_app');
  }
  final serverPlugins = File(
    '${server.path}${Platform.pathSeparator}windows${Platform.pathSeparator}flutter${Platform.pathSeparator}generated_plugins.cmake',
  );
  if (serverPlugins.existsSync() &&
      serverPlugins.readAsStringSync().contains('avaca_player_native')) {
    failures.add('Server Windows runner links the Player native plugin');
  }
  final clientPlugins = File(
    '${client.path}${Platform.pathSeparator}windows${Platform.pathSeparator}flutter${Platform.pathSeparator}generated_plugins.cmake',
  );
  if (clientPlugins.existsSync() &&
      !clientPlugins.readAsStringSync().contains('avaca_player_native')) {
    failures.add('AVACA Windows runner is missing the Player native plugin');
  }
  if (failures.isNotEmpty) {
    stderr.writeln('ARCHITECTURE_CHECK_FAILED');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'ARCHITECTURE_CHECK_PASS: Server and AVACA compositions are acyclic and role-separated.',
  );
}

void _checkDependencyCycles(Directory root, List<String> failures) {
  final packageDirectories = <String, Directory>{};
  for (final parentName in ['packages', 'apps']) {
    final parent = Directory(
      '${root.path}${Platform.pathSeparator}$parentName',
    );
    if (!parent.existsSync()) continue;
    for (final entity in parent.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final pubspec = File(
        '${entity.path}${Platform.pathSeparator}pubspec.yaml',
      );
      if (!pubspec.existsSync()) continue;
      final match = RegExp(
        r'^name:\s*([^\s#]+)',
        multiLine: true,
      ).firstMatch(pubspec.readAsStringSync());
      if (match != null) packageDirectories[match.group(1)!] = entity;
    }
  }
  final graph = <String, Set<String>>{
    for (final name in packageDirectories.keys) name: <String>{},
  };
  for (final entry in packageDirectories.entries) {
    final pubspec = File(
      '${entry.value.path}${Platform.pathSeparator}pubspec.yaml',
    ).readAsStringSync();
    for (final dependency in packageDirectories.keys) {
      if (dependency == entry.key) continue;
      final declaration = RegExp(
        '^\\s{2}${RegExp.escape(dependency)}(?:\\s*:|\\s*\$)',
        multiLine: true,
      );
      if (declaration.hasMatch(pubspec)) graph[entry.key]!.add(dependency);
    }
  }

  final visiting = <String>{};
  final visited = <String>{};
  final stack = <String>[];
  void visit(String packageName) {
    if (visited.contains(packageName) ||
        failures.any((value) => value.startsWith('dependency cycle:'))) {
      return;
    }
    if (!visiting.add(packageName)) {
      final cycleStart = stack.indexOf(packageName);
      final cycle = cycleStart < 0
          ? <String>[...stack, packageName]
          : <String>[...stack.sublist(cycleStart), packageName];
      failures.add('dependency cycle: ${cycle.join(' -> ')}');
      return;
    }
    stack.add(packageName);
    for (final dependency in graph[packageName]!) {
      visit(dependency);
    }
    stack.removeLast();
    visiting.remove(packageName);
    visited.add(packageName);
  }

  for (final packageName in graph.keys) {
    visit(packageName);
  }
}

void _scanDart(
  Directory root,
  List<String> failures, {
  required List<String> forbidden,
  Set<String> skipFileNames = const <String>{},
}) {
  if (!root.existsSync()) return;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    if (skipFileNames.contains(entity.uri.pathSegments.last)) continue;
    final content = entity.readAsStringSync();
    for (final token in forbidden) {
      if (content.contains(token)) {
        failures.add('${entity.path} imports forbidden token "$token"');
      }
    }
  }
}
