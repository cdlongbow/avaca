import 'dart:io';

import 'package:avaca_client_app/main.dart';
import 'package:avaca_client/avaca_client.dart';
import 'package:avaca_domain/avaca_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'client environment connection rejects incomplete or out-of-range config',
    () {
      final valid = <String, String>{
        'AVACA_SERVER_HOST': '127.0.0.1',
        'AVACA_SERVER_PORT': '4545',
        'AVACA_SERVER_ID': 'server-local',
        'AVACA_CLIENT_ID': 'client-local',
        'AVACA_SERVER_CERT_SHA256_HEX': 'aa' * 32,
        'AVACA_PAIRING_SECRET_HEX': 'bb' * 32,
      };
      expect(
        AvacaClientEnvironmentConnection.fromEnvironment(valid),
        isNotNull,
      );
      expect(
        AvacaClientEnvironmentConnection.fromEnvironment({
          ...valid,
          'AVACA_SERVER_PORT': '70000',
        }),
        isNull,
      );
      expect(
        AvacaClientEnvironmentConnection.fromEnvironment({
          ...valid,
          'AVACA_SERVER_CERT_SHA256_HEX': 'aa',
        }),
        isNull,
      );
      expect(
        AvacaClientEnvironmentConnection.fromEnvironment({
          ...valid,
          'AVACA_PAIRING_SECRET_HEX': 'bb' * 33,
        }),
        isNull,
      );
      expect(
        AvacaClientEnvironmentConnection.fromEnvironment({
          ...valid,
          'AVACA_CLIENT_ID': 'client local',
        }),
        isNull,
      );
    },
    skip: !Platform.isWindows,
  );

  testWidgets('AVACA boot is a client browsing and playback shell', (
    tester,
  ) async {
    await tester.pumpWidget(const AvacaClientApp());
    expect(find.text('AVACA'), findsOneWidget);
    expect(find.textContaining('瀏覽 Library'), findsOneWidget);
    expect(find.textContaining('QUIC'), findsOneWidget);
  });

  testWidgets('client navigation preserves a bounded animated transition', (
    tester,
  ) async {
    await tester.pumpWidget(const AvacaClientApp());
    expect(find.text('瀏覽 Library'), findsOneWidget);

    await tester.tap(find.text('伺服器').first);
    await tester.pump(const Duration(milliseconds: 90));
    expect(find.text('伺服器', skipOffstage: false), findsWidgets);
    await tester.pumpAndSettle();
    expect(
      find.text('連線與配對由 AVACA 用戶端負責；Library 真相保留在 AVACA Server。'),
      findsOneWidget,
    );

    await tester.tap(find.text('Library').first);
    await tester.pumpAndSettle();
    expect(find.text('瀏覽 Library'), findsOneWidget);
  });

  testWidgets('pairing preview shows trust material before confirmation', (
    tester,
  ) async {
    final invitation = AvacaPairingInvitationCodec().issue(
      serverId: 'ui-server',
      clientId: 'ui-client',
      host: 'server.local',
      port: 4545,
      leafCertificateSha256: Uint8List.fromList(List<int>.filled(32, 0xab)),
      pairingSecret: Uint8List.fromList(List<int>.filled(32, 0xcd)),
      lifetime: const Duration(minutes: 5),
      invitationId: 'ui-invite',
    );
    final code = AvacaPairingInvitationCodec().encode(invitation);
    invitation.dispose();

    await tester.pumpWidget(const AvacaClientApp());
    await tester.tap(find.text('伺服器').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.text('預覽 invitation'));
    await tester.pumpAndSettle();

    expect(find.text('Server ID：ui-server'), findsOneWidget);
    expect(find.text('端點：server.local:4545'), findsOneWidget);
    expect(find.text('端點來源：直接 invitation'), findsOneWidget);
    expect(find.textContaining('leaf SHA-256：ABAB'), findsOneWidget);
    expect(find.textContaining('CDCD'), findsNothing);
    expect(find.text('確認並保存配對'), findsOneWidget);
  });

  testWidgets('client browse/detail/play/stop stays asynchronous', (
    tester,
  ) async {
    final catalog = _FixtureCatalog();
    final bridge = _FixturePlaybackBridge();
    await tester.pumpWidget(
      AvacaClientApp(catalog: catalog, playbackBridge: bridge),
    );
    await tester.pumpAndSettle();
    expect(find.text('Demo work'), findsOneWidget);

    await tester.tap(find.text('Demo work'));
    await tester.pumpAndSettle();
    expect(find.text('Demo media'), findsOneWidget);
    await tester.tap(find.text('播放'));
    await tester.pumpAndSettle();
    expect(find.textContaining('播放中'), findsOneWidget);
    expect(bridge.openCalls, 1);

    await tester.tap(find.text('停止'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已停止'), findsOneWidget);
    expect(bridge.closeCalls, 1);
    expect(catalog.closedSessions, 1);
  });
}

final class _FixtureCatalog implements AvacaRemoteCatalogApi {
  int closedSessions = 0;

  @override
  Future<AvacaCollectionPage> listCollection({
    String? cursor,
    int limit = 50,
  }) => Future<AvacaCollectionPage>.value(
    const AvacaCollectionPage(
      items: <AvacaWorkSummary>[
        AvacaWorkSummary(
          workId: AvacaWorkId('work-ui'),
          code: 'UI-001',
          title: 'Demo work',
        ),
      ],
      nextCursor: null,
    ),
  );

  @override
  Future<AvacaWorkDetail> getWorkDetail(AvacaWorkId workId) =>
      Future<AvacaWorkDetail>.value(
        const AvacaWorkDetail(
          workId: AvacaWorkId('work-ui'),
          code: 'UI-001',
          title: 'Demo work',
          media: <AvacaMediaSummary>[
            AvacaMediaSummary(
              mediaId: AvacaMediaId('media-ui'),
              workId: AvacaWorkId('work-ui'),
              code: 'UI-001',
              title: 'Demo media',
              availability: AvacaMediaAvailability.available,
            ),
          ],
        ),
      );

  @override
  Future<AvacaAssetDescriptor> createPlaybackSession(AvacaMediaId mediaId) =>
      Future<AvacaAssetDescriptor>.value(
        AvacaAssetDescriptor(
          mediaId: mediaId,
          resourceId: 'resource-ui',
          length: 4,
          container: 'video/x-matroska',
          sessionId: 'session-ui',
          playbackGrant: Uint8List(32),
        ),
      );

  @override
  Future<void> closePlaybackSession(String sessionId) async {
    closedSessions++;
  }
}

final class _FixturePlaybackBridge implements AvacaRemotePlaybackBridge {
  int openCalls = 0;
  int closeCalls = 0;

  @override
  Future<AvacaRemotePlaybackHandle> open(
    AvacaRemoteResourceDescriptor descriptor,
  ) async {
    openCalls++;
    return _FixturePlaybackHandle(onClose: () => closeCalls++);
  }
}

final class _FixturePlaybackHandle implements AvacaRemotePlaybackHandle {
  _FixturePlaybackHandle({required this.onClose});

  final VoidCallback onClose;
  bool closed = false;

  @override
  int get length => 4;

  @override
  Future<Uint8List> readAt(int offset, int length) async => Uint8List(length);

  @override
  Future<void> cancel() async {}

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    onClose();
  }
}
