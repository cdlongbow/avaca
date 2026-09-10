import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';

import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_library/avaca_library.dart';
import 'package:avaca_remote_core/avaca_remote_core.dart';
import 'package:avaca_scraper/avaca_scraper.dart';

import 'pairing_host_selector.dart';

const _serverCertificateSubject = 'AVACA Server QUIC';

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
      autoConfigure: true,
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
    this.autoConfigure = false,
  });

  final AvacaServerRuntime? runtime;
  final String? databasePath;
  final AvacaScraper? scraper;
  final AvacaServerEnvironmentConfig? serverConfig;
  final AvacaRemoteTransportFactory? transportFactory;
  final bool autoConfigure;

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
      autoConfigure: autoConfigure,
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
    required this.autoConfigure,
  });

  final AvacaServerRuntime? runtime;
  final String? databasePath;
  final AvacaScraper? scraper;
  final AvacaServerEnvironmentConfig? serverConfig;
  final AvacaRemoteTransportFactory? transportFactory;
  final bool autoConfigure;

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
  Future<void>? _setupFuture;
  AvacaServerEnvironmentConfig? _effectiveServerConfig;
  late final TextEditingController _folderController;
  Future<void>? _importTask;
  ServerImportProgress? _progress;
  ServerImportResult? _importResult;
  Object? _importError;
  bool _cancelRequested = false;
  List<ServerReviewItem> _reviewItems = const <ServerReviewItem>[];
  bool _reviewLoading = false;
  ServerImportProgress? _pendingProgress;
  Timer? _progressTimer;
  late final TextEditingController _hostController;
  late final MethodChannel _certificateStoreChannel;
  late final MethodChannel _discoveryChannel;
  _ServerCertificate? _selectedCertificate;
  List<_ServerCertificate> _availableCertificates =
      const <_ServerCertificate>[];
  bool _certificatesLoading = false;
  bool _pairingPreparing = false;
  String? _invitationCode;
  Object? _pairingError;
  String? _discoveryError;

  AvacaServerEnvironmentConfig? get _serverConfig =>
      _effectiveServerConfig ?? widget.serverConfig;

  @override
  void initState() {
    super.initState();
    _folderController = TextEditingController();
    _hostController = TextEditingController();
    _certificateStoreChannel = const MethodChannel(
      'avaca/server/certificate_store',
    );
    _discoveryChannel = const MethodChannel('avaca/server/discovery');
    if (widget.autoConfigure && Platform.isWindows && widget.runtime == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final future = _initializeServer();
        _setupFuture = future;
        unawaited(future);
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
    if (widget.autoConfigure && Platform.isWindows) return;
    final databasePath = widget.databasePath?.trim();
    if (databasePath != null && databasePath.isNotEmpty) {
      _openFuture = _openDatabase(databasePath, scraper: widget.scraper);
    }
  }

  Future<void> _loadPairingHosts() async {
    List<String> hosts;
    try {
      hosts = await AvacaPairingHostSelector.selectAll();
    } on Object {
      // The user can still provide an explicit host when interface discovery
      // is unavailable or denied by the platform.
      hosts = const <String>[];
    }
    if (!mounted) return;
    // Never overwrite a value that the user entered while discovery was
    // running.  There is intentionally no loopback fallback here.
    setState(() {
      if (_hostController.text.trim().isEmpty && hosts.isNotEmpty) {
        _hostController.text = hosts.first;
      }
    });
  }

  Future<void> _initializeServer() async {
    final pairingPreparation = _preparePairingConfiguration();
    try {
      final databasePath = await _serverDatabasePath();
      await Directory(p.dirname(databasePath)).create(recursive: true);
      final scraper =
          widget.scraper ??
          DefaultAvacaScraper(
            artworkCacheDirectory: p.join(
              p.dirname(databasePath),
              'artwork-cache',
            ),
          );
      final future = _openDatabase(databasePath, scraper: scraper);
      _openFuture = future;
      final runtime = await future;
      if (runtime == null &&
          widget.scraper == null &&
          scraper is CloseableAvacaScraper) {
        await scraper.close();
      }
      await pairingPreparation;
      if (runtime != null && !_listenerReady && _serverConfig != null) {
        await _startRuntimeIfConfigured(runtime);
      }
    } on Object catch (error) {
      debugPrint('AVACA Server initialization failed: $error');
      if (mounted) {
        setState(() => _pairingError = error);
      }
    }
  }

  Future<void> _preparePairingConfiguration() async {
    try {
      await _loadCertificates();
      await _loadPairingHosts();
      if (!mounted) return;
      final config = await _buildServerConfig();
      if (mounted) {
        setState(() {
          _effectiveServerConfig = config;
          _pairingError = null;
        });
      }
    } on Object catch (error) {
      // Catalog/import must remain usable when pairing prerequisites are
      // missing.  The pairing card shows this error, while the local catalog
      // still opens independently.
      if (mounted) setState(() => _pairingError = error);
    }
  }

  Future<AvacaServerEnvironmentConfig?> _buildServerConfig() async {
    final configured = widget.serverConfig;
    final selected = _selectedCertificate;
    if (configured != null) {
      if (selected != null &&
          !_sameBytes(selected.sha1, configured.certificateSha1Thumbprint)) {
        throw StateError('環境設定指定的憑證與 Windows 憑證不一致，已停止啟動以避免產生錯誤 QR。');
      }
      return AvacaServerEnvironmentConfig(
        serverId: configured.serverId,
        listenPort: configured.listenPort,
        certificateSha1Thumbprint: List<int>.from(
          configured.certificateSha1Thumbprint,
        ),
        certificateSha256Pin: List<int>.from(
          selected?.sha256 ?? configured.certificateSha256Pin ?? const <int>[],
        ),
        pairingSecret: List<int>.from(configured.pairingSecret),
        expectedClientId: configured.expectedClientId,
      );
    }

    if (selected == null) {
      throw StateError(
        '找不到可用的 Windows Server 憑證。Server 本來會自動建立；請確認目前 Windows 使用者可寫入憑證存放區後重新開啟 Server。',
      );
    }
    final port = await _findAvailableServerPort();
    return AvacaServerEnvironmentConfig(
      serverId: _automaticServerId(),
      listenPort: port,
      certificateSha1Thumbprint: List<int>.from(selected.sha1),
      certificateSha256Pin: List<int>.from(selected.sha256),
      pairingSecret: List<int>.generate(
        32,
        (_) => Random.secure().nextInt(256),
        growable: false,
      ),
    );
  }

  Future<String> _serverDatabasePath() async {
    final configured = widget.databasePath?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
    if (localAppData == null || localAppData.isEmpty) {
      throw StateError('找不到 Windows 的 LOCALAPPDATA，無法建立 Server catalog。');
    }
    return p.join(localAppData, 'AVACA', 'server.sqlite');
  }

  Future<int> _findAvailableServerPort() async {
    for (var port = 4545; port <= 4555; port++) {
      RawDatagramSocket? socket;
      try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
        return port;
      } on Object {
        // Try the next private application port.
      } finally {
        socket?.close();
      }
    }
    throw StateError('找不到可用的 QUIC 連接埠（已檢查 4545–4555）。');
  }

  String _automaticServerId() {
    final hostname = Platform.localHostname.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._~-]+'),
      '-',
    );
    final suffix = hostname.isEmpty ? 'local' : hostname;
    final id = 'server-$suffix';
    return id.length <= 256 ? id : id.substring(0, 256);
  }

  String _newPairingClientId() {
    final token = List<int>.generate(
      8,
      (_) => Random.secure().nextInt(256),
      growable: false,
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return 'avaca-player-$token';
  }

  Future<AvacaServerRuntime?> _openDatabase(
    String databasePath, {
    AvacaScraper? scraper,
  }) async {
    try {
      final runtime = await AvacaServerRuntime.openSqlite(
        databasePath,
        scraper: scraper ?? widget.scraper,
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
      if (scraper is CloseableAvacaScraper && scraper != widget.scraper) {
        await scraper.close();
      }
      debugPrint('AVACA Server catalog open failed: $error');
      if (mounted) setState(() => _openError = error);
      return null;
    }
  }

  Future<void> _pickLibraryFolder() async {
    if (_importTask != null || !(_runtime?.isImportConfigured ?? false)) {
      return;
    }
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '選擇 AVACA Server 媒體資料夾',
      );
      if (selected == null || selected.trim().isEmpty || !mounted) return;
      setState(() => _folderController.text = selected);
    } on Object catch (error) {
      if (mounted) setState(() => _importError = error);
    }
  }

  Future<void> _startRuntimeIfConfigured(AvacaServerRuntime runtime) async {
    final config = _serverConfig;
    if (config == null || !runtime.isConfigured || !mounted) return;
    setState(() {
      _listenerStarting = true;
      _startError = null;
    });
    final candidates = <_ServerCertificate?>[];
    if (widget.serverConfig == null) {
      final selected = _selectedCertificate;
      if (selected != null) candidates.add(selected);
      for (final certificate in _availableCertificates) {
        if (certificate.subject == _serverCertificateSubject &&
            (selected == null ||
                !_sameBytes(certificate.sha1, selected.sha1))) {
          candidates.add(certificate);
        }
      }
    }
    if (candidates.isEmpty) candidates.add(null);

    Object? lastError;
    for (final candidate in candidates) {
      final attemptConfig = candidate != null
          ? _configWithCertificate(config, candidate)
          : config;
      try {
        await runtime.start(
          transportFactory:
              widget.transportFactory ?? const AvacaMsQuicTransportFactory(),
          transportConfig: AvacaRemoteServerConfig(
            certificateSha1Thumbprint: Uint8List.fromList(
              attemptConfig.certificateSha1Thumbprint,
            ),
            listenPort: attemptConfig.listenPort,
          ),
          serverId: attemptConfig.serverId,
          pairingSecret: attemptConfig.pairingSecret,
          // v2 pairing authority resolves the client secret after clientId is
          // received; the legacy single-client allow-list is not a production
          // authentication path for the separated Server app.
          expectedClientId: null,
        );
        if (mounted) {
          setState(() {
            if (candidate != null) {
              _selectedCertificate = candidate;
              if (widget.serverConfig == null) {
                _effectiveServerConfig = attemptConfig;
              }
            }
            _listenerStarting = false;
            _listenerReady = true;
            _startError = null;
            _pairingError = null;
          });
        }
        await _startDiscovery(attemptConfig);
        return;
      } on Object catch (error) {
        lastError = error;
        debugPrint(
          'AVACA Server QUIC listener attempt failed '
          '(certificate=${candidate?.sha1Hex ?? 'configured'}): $error',
        );
      }
    }
    if (mounted) {
      setState(() {
        _listenerStarting = false;
        _startError = lastError ?? StateError('Server 安全連線無法啟動。');
        _pairingError = _startError;
      });
    }
  }

  AvacaServerEnvironmentConfig _configWithCertificate(
    AvacaServerEnvironmentConfig config,
    _ServerCertificate certificate,
  ) => AvacaServerEnvironmentConfig(
    serverId: config.serverId,
    listenPort: config.listenPort,
    certificateSha1Thumbprint: List<int>.from(certificate.sha1),
    certificateSha256Pin: List<int>.from(certificate.sha256),
    pairingSecret: List<int>.from(config.pairingSecret),
    expectedClientId: config.expectedClientId,
  );

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
      if (mounted) {
        setState(() => _importResult = result);
        await _loadReviewItems(runtime);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _importError = error);
    } finally {
      if (mounted) setState(() => _importTask = null);
    }
  }

  Future<void> _loadReviewItems([AvacaServerRuntime? runtime]) async {
    final target = runtime ?? _runtime;
    if (target == null || !mounted) return;
    setState(() => _reviewLoading = true);
    try {
      final items = await target.listReviewItems();
      if (mounted) setState(() => _reviewItems = items);
    } on Object catch (error) {
      if (mounted) setState(() => _importError = error);
    } finally {
      if (mounted) setState(() => _reviewLoading = false);
    }
  }

  Future<void> _editReviewItem(ServerReviewItem item) async {
    final runtime = _runtime;
    if (runtime == null) return;
    final controller = TextEditingController(text: item.code ?? '');
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手動修正作品代碼'),
        content: TextField(
          autofocus: true,
          controller: controller,
          decoration: const InputDecoration(
            labelText: '作品代碼',
            hintText: 'ABP-001',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty || !mounted) return;
    try {
      await runtime.applyManualCode(mediaId: item.mediaId, code: code);
      await _loadReviewItems(runtime);
    } on Object catch (error) {
      if (mounted) setState(() => _importError = error);
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

  Future<void> _startPairing() async {
    if (_pairingPreparing) return;
    setState(() {
      _pairingPreparing = true;
      _pairingError = null;
      _invitationCode = null;
    });
    try {
      final setup = _setupFuture;
      if (setup != null) await setup;
      if (!_listenerReady && _runtime != null) {
        await _startRuntimeIfConfigured(_runtime!);
      }
      final startError = _startError;
      if (startError != null) {
        if (mounted) setState(() => _pairingError = startError);
        return;
      }
      if (!_listenerReady) {
        if (mounted && _pairingError == null) {
          setState(() => _pairingError = 'Server 尚未準備完成，請稍候再按一次。');
        }
        return;
      }
      _createPairingInvitation();
    } on Object catch (error) {
      if (mounted) setState(() => _pairingError = error);
    } finally {
      if (mounted) setState(() => _pairingPreparing = false);
    }
  }

  void _createPairingInvitation() {
    final runtime = _runtime;
    final config = _serverConfig;
    final clientId = _newPairingClientId();
    final host = _hostController.text.trim();
    final selected = _selectedCertificate;
    final selectedMatchesListener =
        selected == null ||
        _sameBytes(
          selected.sha1,
          config?.certificateSha1Thumbprint ?? const [],
        );
    final leafPin = selected?.sha256 ?? config?.certificateSha256Pin;
    if (runtime == null ||
        config == null ||
        leafPin == null ||
        leafPin.length != 32 ||
        !selectedMatchesListener ||
        !_listenerReady ||
        host.isEmpty) {
      setState(() {
        _pairingError = host.isEmpty
            ? '找不到可讓手機連線的區網位址；請確認 Server 電腦已連上區域網路。'
            : 'Server 尚未準備完成，請稍候再按一次。';
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
        leafCertificateSha256: leafPin,
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
      var certificates = _parseCertificates(raw);
      final hasDedicatedCertificate = certificates.any(
        (certificate) => certificate.subject == _serverCertificateSubject,
      );
      if (certificates.isEmpty ||
          (widget.serverConfig == null && !hasDedicatedCertificate)) {
        // The native runner creates and stores a non-exportable self-signed
        // certificate only when the user profile has no usable certificate.
        final ensured = await _certificateStoreChannel.invokeMethod<Object?>(
          'ensure',
        );
        final ensuredCertificates = _parseCertificates(ensured);
        if (ensuredCertificates.isNotEmpty) {
          certificates = <_ServerCertificate>[
            ...certificates,
            ...ensuredCertificates,
          ];
        }
      }
      if (mounted) {
        setState(() {
          _availableCertificates = certificates;
          final configuredSha1 = widget.serverConfig?.certificateSha1Thumbprint;
          _selectedCertificate = _selectCertificate(
            certificates,
            configuredSha1,
          );
          _certificatesLoading = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        debugPrint('AVACA Server certificate setup failed: $error');
        setState(() {
          _certificatesLoading = false;
          _pairingError = error;
        });
      }
    }
  }

  _ServerCertificate? _selectCertificate(
    List<_ServerCertificate> certificates,
    List<int>? configuredSha1,
  ) {
    if (configuredSha1 != null) {
      return certificates
          .where((certificate) => _sameBytes(certificate.sha1, configuredSha1))
          .firstOrNull;
    }
    return certificates
        .where(
          (certificate) => certificate.subject == _serverCertificateSubject,
        )
        .firstOrNull;
  }

  List<_ServerCertificate> _parseCertificates(Object? raw) {
    final values = raw is List ? raw : const <Object?>[];
    final certificates = <_ServerCertificate>[];
    for (final value in values) {
      if (value is! Map) continue;
      final sha256 = _bytes(value['certPin']);
      final sha1 = _bytes(value['sha1Thumbprint']);
      final subject = value['subject']?.toString().trim() ?? '';
      if (value['hasPrivateKey'] != true ||
          subject.isEmpty ||
          sha256.length != 32 ||
          sha1.length != 20) {
        continue;
      }
      certificates.add(
        _ServerCertificate(
          subject: subject,
          sha256: sha256,
          sha1: sha1,
          hasPrivateKey: true,
        ),
      );
    }
    return certificates;
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
          const Text('資料庫、scraper、catalog 與 QUIC 資源服務只在此程序執行。'),
          const SizedBox(height: 8),
          const Text('AVACA 用戶端透過 protocol v2 取得目錄與播放授權。'),
          const SizedBox(height: 8),
          if (_openError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Server library authority: 啟動失敗'),
                Text(_friendlyError(_openError!)),
              ],
            )
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
            Text(
              'QUIC listener: 啟動失敗；catalog 仍可在本機管理：'
              '${_friendlyError(_startError!)}',
            ),
          if (_discoveryError != null) Text(_discoveryError!),
          const SizedBox(height: 24),
          _pairingPanel(),
          const SizedBox(height: 24),
          _importPanel(),
          const SizedBox(height: 24),
          _libraryReviewPanel(),
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
              'Server Library',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('掃描與管理 Windows 實體媒體；用戶端不會取得實體路徑。'),
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
                OutlinedButton.icon(
                  key: const ValueKey<String>('server-select-folder'),
                  onPressed: task == null && importReady
                      ? _pickLibraryFolder
                      : null,
                  icon: const Icon(Icons.folder),
                  label: const Text('選擇資料夾'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: task == null && importReady ? _startImport : null,
                  icon: const Icon(Icons.folder_open),
                  label: Text(
                    _reviewItems.isEmpty ? '開始匯入' : '重新掃描／重試 metadata',
                  ),
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
                '匯入尚未啟用：請在 Server composition 注入 catalog writer。scraper 可稍後加入，實體 inventory 仍會保留。',
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
                '、待複核 ${result.needsReview}、metadata 成功 ${result.metadataResolved}'
                '${result.cancelled ? '（已取消）' : ''}；掃描 ${result.scanDuration.inMilliseconds}ms、解析 ${result.resolveDuration.inMilliseconds}ms、索引 ${result.indexDuration.inMilliseconds}ms',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _libraryReviewPanel() {
    final runtime = _runtime;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '媒體資料待複核',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('server-refresh-review'),
                  onPressed: runtime == null || _reviewLoading
                      ? null
                      : () => unawaited(_loadReviewItems(runtime)),
                  icon: const Icon(Icons.refresh),
                  tooltip: '重新整理待複核項目',
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '實體檔案先進入 inventory；檔名歧義、沒有 code 或 metadata provider 失敗時，會在這裡保留並等待修正。',
            ),
            const SizedBox(height: 12),
            if (_reviewLoading)
              const LinearProgressIndicator()
            else if (_reviewItems.isEmpty)
              const Text('目前沒有待複核項目。')
            else
              ..._reviewItems
                  .take(20)
                  .map(
                    (item) => ListTile(
                      dense: true,
                      leading: Icon(
                        item.parseStatus == ServerPhysicalParseStatus.recognized
                            ? Icons.info_outline
                            : Icons.warning_amber,
                      ),
                      title: Text(item.fileName),
                      subtitle: Text(
                        '${item.parseStatus.name} · ${item.metadataState.name} · ${item.diagnostic}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: () => unawaited(_editReviewItem(item)),
                        child: const Text('手動修正'),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _pairingPanel() {
    final config = _serverConfig;
    final pinReady = config?.certificateSha256Pin?.length == 32;
    final pairingError = _pairingError;
    return Card(
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
              '只要按一次「開始配對」，Server 會自動準備安全連線並顯示一次性 QR；不需要選憑證、IP、連接埠或 Client ID。',
            ),
            const SizedBox(height: 12),
            if (_certificatesLoading ||
                (_openFuture != null && _runtime == null))
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('正在準備 Server…'),
                ],
              )
            else if (_listenerReady)
              Text(
                _selectedCertificate == null
                    ? 'Server 已準備完成。'
                    : 'Server 已準備完成（已自動選擇可用憑證）。',
              )
            else if (_startError != null)
              const Text('安全連線啟動失敗，請重新開啟 Server。')
            else
              const Text('Server 正在等待安全連線準備完成。'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  Platform.isWindows &&
                      !_pairingPreparing &&
                      _startError == null
                  ? _startPairing
                  : null,
              icon: const Icon(Icons.qr_code_2),
              label: Text(_pairingPreparing ? '準備中…' : '開始配對'),
            ),
            if (_listenerReady && !pinReady) ...[
              const SizedBox(height: 8),
              const Text('目前的 Server 憑證沒有可用的 SHA-256 pin，因此不會產生錯誤的 QR。'),
            ],
            if (pairingError != null) ...[
              const SizedBox(height: 8),
              Text('配對未完成：${_friendlyError(pairingError)}'),
            ],
            if (_invitationCode != null) ...[
              const SizedBox(height: 12),
              const Text('請用手機上的 AVACA Player 掃描這個 QR：'),
              const SizedBox(height: 8),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: _invitationCode!,
                  version: QrVersions.auto,
                  size: 300,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(_invitationCode!),
              const SizedBox(height: 4),
              const Text('此 QR 只給一台裝置使用，逾時或成功配對後即失效。'),
            ],
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object error) {
    final text = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '');
    if (text.toLowerCase().contains('unable to open database file')) {
      return '無法寫入 Server catalog；請確認資料夾可寫入，或設定 AVACA_SERVER_DB 到可寫入位置。';
    }
    if (text.contains('CERTIFICATE_CREATE_FAILED')) {
      return 'Server 無法自動建立安全憑證；請確認目前 Windows 使用者可寫入憑證存放區，然後重新開啟 Server。';
    }
    if (text.contains('configured MsQuic bridge') ||
        text.contains('MsQuic bridge is not present')) {
      return 'Server 的安全連線元件無法啟動；請重新開啟 Server。';
    }
    return text;
  }

  String _progressLabel(ServerImportProgress? progress) {
    if (progress == null) return '正在準備匯入…';
    final stage = switch (progress.stage) {
      ServerImportStage.scanning => '掃描中',
      ServerImportStage.resolving => '解析中',
      ServerImportStage.indexing => '寫入 catalog',
      ServerImportStage.reviewing => '待複核',
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
    _importer = writer == null
        ? null
        : ServerFolderImportService(catalogWriter: writer, scraper: scraper);
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
        'AVACA Server requires a catalog writer for physical inventory',
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

  Future<List<ServerReviewItem>> listReviewItems({
    String? rootId,
    int limit = 100,
  }) => _enqueue(() async {
    final repository = _repository;
    if (repository is! ServerReviewCatalogRepository) {
      return const <ServerReviewItem>[];
    }
    return (repository as ServerReviewCatalogRepository).listReviewItems(
      rootId: rootId,
      limit: limit,
    );
  });

  Future<void> applyManualCode({
    required AvacaMediaId mediaId,
    required String code,
  }) => _enqueue(() async {
    final repository = _repository;
    if (repository is! ServerReviewCatalogRepository) {
      throw const ServerProtocolException(
        'server_review_not_configured',
        false,
        'Server review actions are not configured',
      );
    }
    await (repository as ServerReviewCatalogRepository).applyManualCode(
      mediaId: mediaId,
      code: code,
    );
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
      assetCatalog: repository is ServerAssetCatalogRepository
          ? repository as ServerAssetCatalogRepository
          : null,
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
        final scraper = _scraper;
        if (scraper is CloseableAvacaScraper) {
          await scraper.close();
        }
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
    required this.hasPrivateKey,
  });

  final String subject;
  final List<int> sha256;
  final List<int> sha1;
  final bool hasPrivateKey;

  String get sha1Hex =>
      sha1.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

bool _sameBytes(List<int> left, List<int> right) =>
    left.length == right.length &&
    left.asMap().entries.every((entry) => entry.value == right[entry.key]);

String _base64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');
