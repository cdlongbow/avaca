import 'dart:async';
import 'dart:io';

import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_library/avaca_library.dart';
import 'package:avaca_scraper/avaca_scraper.dart';
import 'package:avaca_server/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'server environment config rejects incomplete or out-of-range values',
    () {
      final certificate = List<String>.filled(20, 'aa').join();
      final pairingSecret = List<String>.filled(32, 'bb').join();
      final valid = <String, String>{
        'AVACA_SERVER_ID': 'server-local',
        'AVACA_SERVER_PORT': '4545',
        'AVACA_SERVER_CERT_SHA1_HEX': certificate,
        'AVACA_PAIRING_SECRET_HEX': pairingSecret,
        'AVACA_EXPECTED_CLIENT_ID': 'client-local',
      };

      final config = AvacaServerEnvironmentConfig.fromEnvironment(valid);
      expect(config, isNotNull);
      expect(config!.listenPort, 4545);
      expect(config.certificateSha1Thumbprint, hasLength(20));
      expect(config.pairingSecret, hasLength(32));
      expect(config.expectedClientId, 'client-local');

      expect(
        AvacaServerEnvironmentConfig.fromEnvironment({
          ...valid,
          'AVACA_SERVER_PORT': '0',
        }),
        isNull,
      );
      expect(
        AvacaServerEnvironmentConfig.fromEnvironment({
          ...valid,
          'AVACA_SERVER_CERT_SHA1_HEX': 'aa',
        }),
        isNull,
      );
      expect(
        AvacaServerEnvironmentConfig.fromEnvironment({
          ...valid,
          'AVACA_PAIRING_SECRET_HEX': 'bb' * 33,
        }),
        isNull,
      );
      expect(
        AvacaServerEnvironmentConfig.fromEnvironment({
          ...valid,
          'AVACA_PAIRING_SECRET_HEX': 'gg',
        }),
        isNull,
      );
      expect(
        AvacaServerEnvironmentConfig.fromEnvironment({
          ...valid,
          'AVACA_SERVER_ID': 'server local',
        }),
        isNull,
      );
    },
    skip: !Platform.isWindows,
  );

  testWidgets('Server boot is a management-only Flutter shell', (tester) async {
    await tester.pumpWidget(const AvacaServerApp());
    expect(find.text('AVACA Server'), findsOneWidget);
    expect(find.textContaining('Library'), findsOneWidget);
    expect(find.textContaining('QUIC'), findsOneWidget);
  });

  testWidgets(
    'import panel starts and completes without blocking a frame',
    (tester) async {
      final root = (await tester.runAsync(() async {
        final directory = Directory(
          '${Directory.current.path}${Platform.pathSeparator}build${Platform.pathSeparator}test-import-ui-${DateTime.now().microsecondsSinceEpoch}',
        );
        await directory.create(recursive: true);
        return directory;
      }))!;
      try {
        await tester.runAsync(
          () => File(
            '${root.path}${Platform.pathSeparator}ABP-001.mkv',
          ).writeAsBytes(const <int>[1, 2, 3]),
        );
        final runtime = AvacaServerRuntime(
          repository: _RuntimeCatalog(),
          resolvePlayback: (_) async => null,
          scraper: const _RuntimeScraper(),
        );
        await tester.pumpWidget(AvacaServerApp(runtime: runtime));
        await tester.enterText(
          find.byKey(const ValueKey<String>('server-folder-path')),
          root.path,
        );
        await tester.scrollUntilVisible(
          find.text('開始匯入'),
          500,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('開始匯入'));
        // The tap only schedules async filesystem work.  A normal pump must
        // still return immediately while the Server import is running.
        await tester.pump();
        for (var index = 0; index < 20; index++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          if (find.textContaining('完成：掃描 1').evaluate().isNotEmpty) break;
        }
        expect(find.textContaining('完成：掃描 1'), findsOneWidget);
        await runtime.close();
      } finally {
        await tester.runAsync(() => root.delete(recursive: true));
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'runtime serializes an import and close without closing the writer early',
    () async {
      final root = await Directory.systemTemp.createTemp('avaca-server-app-');
      try {
        await File(
          '${root.path}${Platform.pathSeparator}ABP-001.mkv',
        ).writeAsBytes(const <int>[1, 2, 3]);
        final writer = _RuntimeCatalog();
        final runtime = AvacaServerRuntime(
          repository: writer,
          resolvePlayback: (_) async => null,
          scraper: const _RuntimeScraper(),
        );
        var cancel = false;
        final import = runtime.importFolder(
          root.path,
          isCancelled: () => cancel,
          onProgress: (progress) {
            if (progress.stage == ServerImportStage.scanning) cancel = true;
          },
        );
        final close = runtime.close();
        final result = await import;
        await close;

        expect(result.cancelled, isTrue);
        expect(writer.media, isEmpty);
        await runtime.close();
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'runtime close cancels a slow scraper before the catalog write boundary',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'avaca-server-app-slow-',
      );
      final started = Completer<void>();
      final release = Completer<void>();
      try {
        await File(
          '${root.path}${Platform.pathSeparator}ABP-001.mkv',
        ).writeAsBytes(const <int>[1, 2, 3]);
        final writer = _RuntimeCatalog();
        final runtime = AvacaServerRuntime(
          repository: writer,
          resolvePlayback: (_) async => null,
          scraper: _BlockingRuntimeScraper(started, release),
        );
        final import = runtime.importFolder(root.path);
        await started.future;
        final close = runtime.close();
        release.complete();
        final result = await import;
        await close;

        expect(result.cancelled, isTrue);
        expect(writer.media, isEmpty);
      } finally {
        if (!release.isCompleted) release.complete();
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}

final class _RuntimeCatalog
    implements ServerCatalogRepository, ServerCatalogWriter {
  final List<ServerMediaRecord> media = <ServerMediaRecord>[];

  @override
  Future<AvacaCollectionPage> listCollection({
    String? cursor,
    int limit = 50,
  }) async =>
      const AvacaCollectionPage(items: <AvacaWorkSummary>[], nextCursor: null);

  @override
  Future<AvacaWorkDetail> getWorkDetail(AvacaWorkId workId) async =>
      AvacaWorkDetail(workId: workId, code: 'ABP-1', title: 'Runtime fixture');

  @override
  Future<void> upsertWork(AvacaWorkSummary work) async {}

  @override
  Future<void> upsertMedia(ServerMediaRecord value) async => media.add(value);
}

final class _RuntimeScraper implements AvacaScraper {
  const _RuntimeScraper();

  @override
  Future<AvacaWorkSummary> resolveWork(String code) async => AvacaWorkSummary(
    workId: AvacaWorkId('work.$code'),
    code: code,
    title: 'Runtime $code',
  );
}

final class _BlockingRuntimeScraper implements AvacaScraper {
  _BlockingRuntimeScraper(this.started, this.release);

  final Completer<void> started;
  final Completer<void> release;

  @override
  Future<AvacaWorkSummary> resolveWork(String code) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return AvacaWorkSummary(
      workId: AvacaWorkId('work.$code'),
      code: code,
      title: 'Runtime $code',
    );
  }
}
