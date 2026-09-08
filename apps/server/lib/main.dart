import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:avaca_library/avaca_library.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';
import 'package:avaca_scraper/avaca_scraper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  assertProtocolV2();
  // Render the management shell immediately.  Database opening is owned by
  // the state lifecycle below so a large/new Server catalog cannot delay the
  // first Windows frame or make the window look hung during startup.
  runApp(
    AvacaServerApp(
      databasePath: Platform.environment['AVACA_SERVER_DB'],
      serverConfig: AvacaServerEnvironmentConfig.fromEnvironment(),
    ),
  );
}

class AvacaServerApp extends StatelessWidget {
  const AvacaServerApp({
    super.key,
    this.runtime,
    this.databasePath,
    this.scraper,
    this.serverConfig,
    this.transportFactory,
  });

  final AvacaServerRuntime? runtime;
  final String? databasePath;
  final AvacaScraper? scraper;
  final AvacaServerEnvironmentConfig? serverConfig;
  final AvacaRemoteTransportFactory? transportFactory;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'AVACA Server',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    home: _ServerHome(
      runtime: runtime,
      databasePath: databasePath,
      scraper: scraper,
      serverConfig: serverConfig,
      transportFactory: transportFactory,
    ),
  );
}

class _ServerHome extends StatefulWidget {
  const _ServerHome({
    required this.runtime,
    required this.databasePath,
    required this.scraper,
    required this.serverConfig,
    required this.transportFactory,
  });

  final AvacaServerRuntime? runtime;
  final String? databasePath;
  final AvacaScraper? scraper;
  final AvacaServerEnvironmentConfig? serverConfig;
  final AvacaRemoteTransportFactory? transportFactory;

  @override
  State<_ServerHome> createState() => _ServerHomeState();
}

class _ServerHomeState extends State<_ServerHome> {
  Future<AvacaServerRuntime?>? _openFuture;
  AvacaServerRuntime? _runtime;
  Object? _openError;
  Object? _startError;
  bool _listenerStarting = false;
  bool _listenerReady = false;
  bool _ownsRuntime = false;
  late final TextEditingController _folderController;
  Future<void>? _importTask;
  ServerImportProgress? _progress;
  ServerImportResult? _importResult;
  Object? _importError;
  bool _cancelRequested = false;
  ServerImportProgress? _pendingProgress;
  Timer? _progressTimer;
  late final TextEditingController _clientIdController;
  late final TextEditingController _hostController;
  late final MethodChannel _certificateStoreChannel;
  late final MethodChannel _discoveryChannel;
  List<_ServerCertificate> _certificates = const <_ServerCertificate>[];
  _ServerCertificate? _selectedCertificate;
  bool _certificatesLoading = false;
  String? _invitationCode;
  Object? _pairingError;
  String? _discoveryError;

  @override
  void initState() {
    super.initState();
    _folderController = TextEditingController();
    _clientIdController = TextEditingController(text: 'avaca-client');
    _hostController = TextEditingController(text: '127.0.0.1');
    _certificateStoreChannel = const MethodChannel(
      'avaca/server/certificate_store',
    );
    _discoveryChannel = const MethodChannel('avaca/server/discovery');
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadCertificates());
      });
    }
    final injected = widget.runtime;
    if (injected != null) {
      _runtime = injected;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startRuntimeIfConfigured(injected));
      });
      return;
    }
    final databasePath = widget.databasePath?.trim();
    if (databasePath != null && databasePath.isNotEmpty) {
      _openFuture = _openDatabase(databasePath);
    }
  }

  Future<AvacaServerRuntime?> _openDatabase(String databasePath) async {
    try {
      final runtime = await AvacaServerRuntime.openSqlite(
        databasePath,
        scraper: widget.scraper,
      );
      if (!mounted) {
        await runtime.close();
        return null;
      }
      setState(() {
        _runtime = runtime;
        _ownsRuntime = true;
      });
      await _startRuntimeIfConfigured(runtime);
      return runtime;
    } on Object catch (error) {
      if (mounted) setState(() => _openError = error);
      return null;
    }
  }

  Future<void> _startRuntimeIfConfigured(AvacaServerRuntime runtime) async {
    final config = widget.serverConfig;
    if (config == null || !runtime.isConfigured || !mounted) return;
    setState(() {
      _listenerStarting = true;
      _startError = null;
    });
    try {
      await runtime.start(
        transportFactory:
            widget.transportFactory ?? const AvacaMsQuicTransportFactory(),
        transportConfig: AvacaRemoteServerConfig(
          certificateSha1Thumbprint: Uint8List.fromList(
            config.certificateSha1Thumbprint,
          ),
          listenPort: config.listenPort,
        ),
        serverId: config.serverId,
        pairingSecret: config.pairingSecret,
        // v2 pairing authority resolves the client secret after clientId is
        // received; the legacy single-client allow-list is not a production
        // authentication path for the separated Server app.
        expectedClientId: null,
      );
      if (mounted) {
        setState(() {
          _listenerStarting = false;
          _listenerReady = true;
        });
      }
      await _startDiscovery(config);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _listenerStarting = false;
          _startError = error;
        });
      }
    }
  }

  Future<void> _startDiscovery(AvacaServerEnvironmentConfig config) async {
    final selected = _selectedCertificate;
    final selectedMatchesListener =
        selected == null ||
        _sameBytes(selected.sha1, config.certificateSha1Thumbprint);
    final pin = selectedMatchesListener
        ? selected?.sha256 ?? config.certificateSha256Pin
        : null;
    if (pin == null || pin.length != 32) {
      if (mounted) {
        setState(() {
          _discoveryError = 'mDNS discovery 尚未啟用：缺少 leaf SHA-256 pin。';
        });
      }
      return;
    }
    final nonce = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    try {
      await _discoveryChannel.invokeMethod<void>('start', {
        'serverId': config.serverId,
        'port': config.listenPort,
        'certPin': _base64Url(pin),
        'nonce': _base64Url(nonce),
      });
      if (mounted) setState(() => _discoveryError = null);
    } on Object {
      if (mounted) {
        setState(() {
          _discoveryError = 'mDNS discovery 未啟動；direct invitation 仍可使用。';
        });
      }
    }
  }

  Future<void> _stopDiscovery() async {
    try {
      await _discoveryChannel.invokeMethod<void>('stop');
    } on Object {
      // Closing the server process also tears down the native DNS-SD handle.
    }
  }

  void _startImport() {
    final runtime = _runtime;
    final folderPath = _folderController.text.trim();
    if (runtime == null ||
        !runtime.isImportConfigured ||
        folderPath.isEmpty ||
        _importTask != null) {
      return;
    }
    _cancelRequested = false;
    setState(() {
      _progress = null;
      _importResult = null;
      _importError = null;
    });
    final task = _performImport(runtime, folderPath);
    // Use a block so the setState callback returns void.  Returning the
    // Future from an assignment makes Flutter treat the callback as async and
    // throws during the tap, which was the exact import-button freeze path.
    setState(() {
      _importTask = task;
    });
    unawaited(task);
  }

  Future<void> _performImport(
    AvacaServerRuntime runtime,
    String folderPath,
  ) async {
    try {
      final result = await runtime.importFolder(
        folderPath,
        isCancelled: () => _cancelRequested,
        onProgress: _queueProgress,
      );
      if (mounted) setState(() => _importResult = result);
    } on Object catch (error) {
      if (mounted) setState(() => _importError = error);
    } finally {
      if (mounted) setState(() => _importTask = null);
    }
  }

  void _queueProgress(ServerImportProgress progress) {
    _pendingProgress = progress;
    if (_progressTimer != null) return;
    _progressTimer = Timer(const Duration(milliseconds: 16), () {
      _progressTimer = null;
      final progress = _pendingProgress;
      _pendingProgress = null;
      if (progress != null && mounted) setState(() => _progress = progress);
    });
  }

  void _cancelImport() {
    if (_importTask == null) return;
    _cancelRequested = true;
  }

  void _createPairingInvitation() {
    final runtime = _runtime;
    final config = widget.serverConfig;
    final clientId = _clientIdController.text.trim();
    final host = _hostController.text.trim();
    final selected = _selectedCertificate;
    final selectedMatchesListener =
        selected == null ||
        _sameBytes(
          selected.sha1,
          config?.certificateSha1Thumbprint ?? const [],
        );
    if (runtime == null ||
        config == null ||
        (selected == null && config.certificateSha256Pin == null) ||
        !selectedMatchesListener ||
        !_listenerReady ||
        clientId.isEmpty ||
        host.isEmpty) {
      setState(() {
        _pairingError = '請先讓 QUIC listener ready，並提供 clientId、端點與 SHA-256 pin。';
        _invitationCode = null;
      });
      return;
    }
    try {
      final code = runtime.createPairingInvitation(
        serverId: config.serverId,
        clientId: clientId,
        host: host,
        port: config.listenPort,
        leafCertificateSha256: selected?.sha256 ?? config.certificateSha256Pin!,
      );
      setState(() {
        _pairingError = null;
        _invitationCode = code;
      });
    } on Object catch (error) {
      setState(() {
        _pairingError = error;
        _invitationCode = null;
      });
    }
  }

  Future<void> _loadCertificates() async {
    if (_certificatesLoading) return;
    setState(() => _certificatesLoading = true);
    try {
      final raw = await _certificateStoreChannel.invokeMethod<Object?>('list');
      final values = raw is List ? raw : const <Object?>[];
      final certificates = <_ServerCertificate>[];
      for (final value in values) {
        if (value is! Map) continue;
        final sha256 = _bytes(value['certPin']);
        final sha1 = _bytes(value['sha1Thumbprint']);
        final subject = value['subject']?.toString().trim() ?? '';
        if (subject.isEmpty || sha256.length != 32 || sha1.length != 20) {
          continue;
        }
        certificates.add(
          _ServerCertificate(subject: subject, sha256: sha256, sha1: sha1),
        );
      }
      if (mounted) {
        setState(() {
          _certificates = certificates;
          final configuredSha1 = widget.serverConfig?.certificateSha1Thumbprint;
          _selectedCertificate = configuredSha1 == null
              ? null
              : certificates
                    .where(
                      (certificate) =>
                          _sameBytes(certificate.sha1, configuredSha1),
                    )
                    .firstOrNull;
          _certificatesLoading = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _certificatesLoading = false;
          _pairingError = error;
        });
      }
    }
  }

  List<int> _bytes(Object? value) {
    if (value is List && value.every((item) => item is num)) {
      return value.map((item) => (item as num).toInt()).toList(growable: false);
    }
    return const <int>[];
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _progressTimer?.cancel();
    _folderController.dispose();
    _clientIdController.dispose();
    _hostController.dispose();
    unawaited(_stopDiscovery());
    if (_ownsRuntime) unawaited(_runtime?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AVACA Server')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Windows Server', style: TextStyle(fontSize: 22)),
          const SizedBox(height: 12),
          const Text('Library、scraper、catalog 與 QUIC 資源服務只在此程序執行。'),
          const SizedBox(height: 8),
          const Text('AVACA 用戶端透過 protocol v2 取得目錄與播放授權。'),
          const SizedBox(height: 8),
          if (_openError != null)
            const Text('Server library authority: 啟動失敗，請檢查設定後重試')
          else if (_openFuture != null && _runtime == null)
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Server library authority: 正在載入 catalog'),
              ],
            )
          else
            Text(
              _runtime == null || !_runtime!.isConfigured
                  ? 'Server library authority: 尚未設定 catalog adapter'
                  : 'Server library authority: ready',
            ),
          if (_listenerStarting)
            const Text('QUIC listener: 正在啟動…')
          else if (_listenerReady)
            const Text('QUIC listener: ready')
          else if (_startError != null)
            const Text('QUIC listener: 啟動失敗，catalog 仍可在本機管理'),
          if (_discoveryError != null) Text(_discoveryError!),
          const SizedBox(height: 24),
          _pairingPanel(),
          const SizedBox(height: 24),
          _importPanel(),
        ],
      ),
    ),
  );

  Widget _importPanel() {
    final runtime = _runtime;
    final task = _importTask;
    final progress = _progress;
    final result = _importResult;
    final importReady = runtime?.isImportConfigured ?? false;
    final progressValue = progress == null || progress.total == 0
        ? null
        : (progress.completed / progress.total).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '匯入 Server 媒體',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('只在 AVACA Server 掃描 Windows 資料夾；用戶端不會取得實體路徑。'),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey<String>('server-folder-path'),
              controller: _folderController,
              enabled: task == null && importReady,
              decoration: const InputDecoration(
                labelText: '媒體資料夾路徑',
                hintText: r'D:\Media',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _startImport(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: task == null && importReady ? _startImport : null,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('開始匯入'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: task == null ? null : _cancelImport,
                  child: const Text('取消'),
                ),
              ],
            ),
            if (!importReady) ...[
              const SizedBox(height: 8),
              const Text(
                '匯入尚未啟用：請在 Server composition 注入 catalog writer 與 scraper。',
              ),
            ],
            if (task != null || progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progressValue),
              const SizedBox(height: 8),
              Text(_progressLabel(progress)),
            ],
            if (_importError != null) ...[
              const SizedBox(height: 8),
              const Text('匯入失敗；既有資料未清除，請修正路徑或 scraper 後重試。'),
            ],
            if (result != null) ...[
              const SizedBox(height: 8),
              Text(
                '完成：掃描 ${result.scanned}、匯入 ${result.imported}、跳過 ${result.skipped}、失敗 ${result.failed}'
                '${result.cancelled ? '（已取消）' : ''}；掃描 ${result.scanDuration.inMilliseconds}ms、解析 ${result.resolveDuration.inMilliseconds}ms、索引 ${result.indexDuration.inMilliseconds}ms',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pairingPanel() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '配對 AVACA Player',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '產生一次性、10 分鐘有效的 AVACA-PAIR-V2 invitation。只在成功 HMAC 認證後消耗。',
          ),
          const SizedBox(height: 12),
          _certificatePicker(),
          const SizedBox(height: 12),
          TextField(
            controller: _clientIdController,
            decoration: const InputDecoration(
              labelText: 'Player clientId',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Server host',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _listenerReady ? _createPairingInvitation : null,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('產生 invitation code'),
          ),
          if (widget.serverConfig?.certificateSha256Pin == null) ...[
            const SizedBox(height: 8),
            const Text(
              '尚未取得 Server leaf certificate SHA-256 pin；目前不會產生可用 invitation。',
            ),
          ],
          if (_pairingError != null) ...[
            const SizedBox(height: 8),
            const Text('配對 invitation 產生失敗，請檢查 listener、端點與 certificate pin。'),
          ],
          if (_invitationCode != null) ...[
            const SizedBox(height: 12),
            const Text('請在 AVACA Player 掃描 QR 或貼上以下代碼：'),
            const SizedBox(height: 8),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: _invitationCode!,
                version: QrVersions.auto,
                size: 220,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(_invitationCode!),
          ],
        ],
      ),
    ),
  );

  Widget _certificatePicker() {
    if (_certificatesLoading) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('正在讀取 Windows certificate store…'),
        ],
      );
    }
    if (_certificates.isEmpty) {
      return const Text(
        '找不到可選的 Windows MY certificate；目前可使用環境設定提供的 SHA-256 leaf pin。',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<_ServerCertificate>(
          initialValue: _selectedCertificate,
          decoration: const InputDecoration(
            labelText: 'Windows certificate store（CurrentUser/MY）',
            border: OutlineInputBorder(),
          ),
          items: _certificates
              .map(
                (certificate) => DropdownMenuItem<_ServerCertificate>(
                  value: certificate,
                  child: Text(certificate.subject),
                ),
              )
              .toList(growable: false),
          onChanged: (certificate) {
            setState(() => _selectedCertificate = certificate);
            final config = widget.serverConfig;
            if (certificate != null && _listenerReady && config != null) {
              unawaited(_startDiscovery(config));
            }
          },
        ),
        if (_selectedCertificate != null) ...[
          const SizedBox(height: 8),
          SelectableText(
            'leaf SHA-256 pin：${_hex(_selectedCertificate!.sha256)}',
          ),
          const SizedBox(height: 4),
          const Text('私鑰不會離開 Windows certificate store。'),
        ],
      ],
    );
  }

  String _progressLabel(ServerImportProgress? progress) {
    if (progress == null) return '正在準備匯入…';
    final stage = switch (progress.stage) {
      ServerImportStage.scanning => '掃描中',
      ServerImportStage.resolving => '解析中',
      ServerImportStage.indexing => '寫入 catalog',
      ServerImportStage.completed => '已完成',
      ServerImportStage.cancelled => '已取消',
    };
    final file = progress.fileName == null ? '' : '：${progress.fileName}';
    return '$stage ${progress.completed}/${progress.total}$file';
  }
}

/// Server composition root.  The concrete grant/resource services are kept
/// behind this Windows-only app and are never reachable from AVACA client
/// code.  Database/catalog adapters can be attached here without changing the
/// Player runtime or introducing a second library authority.
final class AvacaServerRuntime {
  AvacaServerRuntime({
    ServerCatalogRepository? repository,
    ServerPlaybackSelectionResolver? resolvePlayback,
    AvacaScraper? scraper,
  }) : grants = PlaybackGrantRegistry(),
       pairingAuthority = ServerPairingInvitationAuthority(),
       _repository = repository,
       _resolvePlayback = resolvePlayback,
       _scraper = scraper {
    resources = ServerMediaResourceService(grants: grants);
    playbackSessions = PlaybackSessionService(grants: grants);
    _refreshImporter();
  }

  static Future<AvacaServerRuntime> openSqlite(
    String databasePath, {
    AvacaScraper? scraper,
  }) async {
    final repository = await ServerSqliteCatalogRepository.open(
      databasePath: databasePath,
    );
    final runtime = AvacaServerRuntime(
      repository: repository,
      resolvePlayback: repository.findPlayback,
      scraper: scraper,
    );
    runtime._ownedRepository = repository;
    return runtime;
  }

  final PlaybackGrantRegistry grants;
  final ServerPairingInvitationAuthority pairingAuthority;
  late final ServerMediaResourceService resources;
  late final PlaybackSessionService playbackSessions;
  ServerCatalogRepository? _repository;
  ServerPlaybackSelectionResolver? _resolvePlayback;
  AvacaScraper? _scraper;
  ServerFolderImportService? _importer;
  AvacaServerApplicationHost? _host;
  AvacaRemoteTransport? _transport;
  ServerSqliteCatalogRepository? _ownedRepository;
  Future<void> _operationTail = Future<void>.value();
  Future<void>? _closeFuture;
  bool _closing = false;
  bool _disposed = false;
  bool _importing = false;
  bool _cancelImportRequested = false;

  bool get isConfigured => _repository != null && _resolvePlayback != null;
  bool get isImportConfigured => _importer != null;

  void configure({
    required ServerCatalogRepository repository,
    required ServerPlaybackSelectionResolver resolvePlayback,
  }) {
    if (_host != null || _importing || _disposed) {
      throw StateError('AVACA Server cannot be reconfigured while running');
    }
    _repository = repository;
    _resolvePlayback = resolvePlayback;
    _refreshImporter();
  }

  void configureScraper(AvacaScraper scraper) {
    if (_host != null || _importing || _disposed) {
      throw StateError('AVACA Server scraper cannot change while running');
    }
    _scraper = scraper;
    _refreshImporter();
  }

  void _refreshImporter() {
    final repository = _repository;
    final scraper = _scraper;
    final writer = repository is ServerCatalogWriter
        ? repository as ServerCatalogWriter
        : null;
    _importer = writer != null && scraper != null
        ? ServerFolderImportService(catalogWriter: writer, scraper: scraper)
        : null;
  }

  Future<ServerImportResult> importFolder(
    String folderPath, {
    bool Function()? isCancelled,
    ServerImportProgressCallback? onProgress,
  }) => _enqueue(() async {
    if (_disposed || _closing) {
      throw const ServerProtocolException(
        'server_runtime_closed',
        false,
        'AVACA Server runtime is closed',
      );
    }
    final importer = _importer;
    if (importer == null) {
      throw const ServerProtocolException(
        'server_import_not_configured',
        false,
        'AVACA Server requires a catalog writer and scraper for import',
      );
    }
    _importing = true;
    _cancelImportRequested = false;
    try {
      return await importer.importFolder(
        folderPath,
        isCancelled: () =>
            _cancelImportRequested || (isCancelled?.call() ?? false),
        onProgress: onProgress,
      );
    } finally {
      _importing = false;
    }
  });

  Future<void> start({
    required AvacaRemoteTransportFactory transportFactory,
    required AvacaRemoteServerConfig transportConfig,
    required String serverId,
    required List<int> pairingSecret,
    String? expectedClientId,
  }) => _enqueue(() async {
    if (_disposed) {
      throw const ServerProtocolException(
        'server_runtime_closed',
        false,
        'AVACA Server runtime is closed',
      );
    }
    if (_closing) {
      throw const ServerProtocolException(
        'server_runtime_closing',
        false,
        'AVACA Server runtime is closing',
      );
    }
    final repository = _repository;
    final resolvePlayback = _resolvePlayback;
    if (repository == null || resolvePlayback == null) {
      throw StateError(
        'AVACA Server requires a catalog repository and playback resolver',
      );
    }
    if (_host != null) {
      throw StateError('AVACA Server listener is already running');
    }
    final transport = await transportFactory.createServer(transportConfig);
    final host = AvacaServerApplicationHost(
      serverId: serverId,
      pairingSecret: pairingSecret,
      pairingSecretResolver: pairingAuthority.resolveSecret,
      onClientAuthenticated: pairingAuthority.markAuthenticated,
      expectedClientId: expectedClientId,
      catalog: ServerCatalogService(repository),
      playbackSessions: playbackSessions,
      resources: resources,
      resolvePlayback: resolvePlayback,
    );
    try {
      await host.start(transport);
      _host = host;
      _transport = transport;
    } on Object {
      await host.close();
      await transport.close();
      rethrow;
    }
  });

  /// Creates a one-time ten-minute invitation.  The returned code is only
  /// meant for the pairing UI; the authority retains the secret in memory
  /// until the first successful v2 HMAC authentication.
  String createPairingInvitation({
    required String serverId,
    required String clientId,
    required String host,
    required int port,
    required List<int> leafCertificateSha256,
  }) => pairingAuthority.issueCode(
    serverId: serverId,
    clientId: clientId,
    host: host,
    port: port,
    leafCertificateSha256: leafCertificateSha256,
  );

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    // Signal an in-flight scan immediately; the queued close then waits for
    // the importer to reach its next safe item boundary before closing the
    // owned catalog.  This prevents a window close from racing a DB write.
    _cancelImportRequested = true;
    final closeFuture = _enqueue<void>(() async {
      if (_disposed) return;
      _closing = true;
      final host = _host;
      _host = null;
      try {
        await host?.close();
      } finally {
        final transport = _transport;
        _transport = null;
        await transport?.close();
        pairingAuthority.dispose();
        final repository = _ownedRepository;
        _ownedRepository = null;
        await repository?.close();
        _disposed = true;
      }
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
}

/// Real Windows Server listener configuration. It is opt-in so a fresh
/// install can still render its management shell without guessing a
/// certificate, port, or pairing record. Secrets are read only from the
/// process environment and are passed directly to the in-memory runtime.
final class AvacaServerEnvironmentConfig {
  const AvacaServerEnvironmentConfig({
    required this.serverId,
    required this.listenPort,
    required this.certificateSha1Thumbprint,
    this.certificateSha256Pin,
    required this.pairingSecret,
    this.expectedClientId,
  });

  final String serverId;
  final int listenPort;
  final List<int> certificateSha1Thumbprint;
  final List<int>? certificateSha256Pin;
  final List<int> pairingSecret;
  final String? expectedClientId;

  static AvacaServerEnvironmentConfig? fromEnvironment([
    Map<String, String>? values,
  ]) {
    if (!Platform.isWindows) return null;
    final environment = values ?? Platform.environment;
    final serverId = environment['AVACA_SERVER_ID']?.trim();
    final expectedClientId = environment['AVACA_EXPECTED_CLIENT_ID']?.trim();
    final listenPort = int.tryParse(environment['AVACA_SERVER_PORT'] ?? '');
    final certificate = _decodeHex(
      environment['AVACA_SERVER_CERT_SHA1_HEX'],
      exactBytes: 20,
    );
    final certificateSha256 = _decodeHex(
      environment['AVACA_SERVER_CERT_SHA256_HEX'],
      exactBytes: 32,
    );
    final pairingSecret = _decodeHex(
      environment['AVACA_PAIRING_SECRET_HEX'],
      exactBytes: 32,
    );
    if (!_validId(serverId) ||
        listenPort == null ||
        listenPort < 1 ||
        listenPort > 65535 ||
        certificate == null ||
        pairingSecret == null ||
        (expectedClientId != null && !_validId(expectedClientId))) {
      return null;
    }
    return AvacaServerEnvironmentConfig(
      serverId: serverId!,
      listenPort: listenPort,
      certificateSha1Thumbprint: certificate,
      certificateSha256Pin: certificateSha256,
      pairingSecret: pairingSecret,
      expectedClientId: expectedClientId,
    );
  }

  static List<int>? _decodeHex(
    String? raw, {
    int? exactBytes,
    int? minimumBytes,
  }) {
    final value = raw?.trim();
    if (value == null ||
        value.isEmpty ||
        value.length.isOdd ||
        !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(value)) {
      return null;
    }
    final byteLength = value.length ~/ 2;
    if ((exactBytes != null && byteLength != exactBytes) ||
        (minimumBytes != null && byteLength < minimumBytes)) {
      return null;
    }
    return List<int>.generate(
      byteLength,
      (index) =>
          int.parse(value.substring(index * 2, index * 2 + 2), radix: 16),
      growable: false,
    );
  }

  static bool _validId(String? value) =>
      value != null &&
      value.isNotEmpty &&
      value.length <= 256 &&
      RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(value);
}

final class _ServerCertificate {
  const _ServerCertificate({
    required this.subject,
    required this.sha256,
    required this.sha1,
  });

  final String subject;
  final List<int> sha256;
  final List<int> sha1;
}

String _hex(List<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();

bool _sameBytes(List<int> left, List<int> right) =>
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);

String _base64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');
