import 'dart:async';
import 'dart:io';

import 'package:avaca_client/avaca_client.dart';
import 'package:avaca_domain/avaca_domain.dart';
import 'package:avaca_player_native/avaca_player_native.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:avaca_remote_core/avaca_remote_core.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  assertProtocolV2();
  final environmentConnection =
      AvacaClientEnvironmentConnection.fromEnvironment();
  runApp(
    AvacaClientApp(
      connectHost: environmentConnection?.connect,
      initialProfile: environmentConnection?.toProfile(),
    ),
  );
}

class AvacaClientApp extends StatelessWidget {
  const AvacaClientApp({
    super.key,
    this.catalog,
    this.playbackBridge,
    this.connectHost,
    this.initialProfile,
  });

  /// An authenticated catalog is injected by the client composition after
  /// connection.  Keeping it optional lets the first frame render while the
  /// connection/handshake is still in flight.
  final AvacaRemoteCatalogApi? catalog;
  final AvacaRemotePlaybackBridge? playbackBridge;
  final Future<AvacaClientApplicationHost> Function()? connectHost;
  final AvacaRemoteClientProfile? initialProfile;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'AVACA',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
    home: _ClientBootstrap(
      catalog: catalog,
      playbackBridge: playbackBridge,
      connectHost: connectHost,
      initialProfile: initialProfile,
    ),
  );
}

/// Starts an optional real Server connection after the first frame.  The
/// offline shell remains available when no complete environment configuration
/// is present, and a failed handshake never blocks navigation or widget build.
class _ClientBootstrap extends StatefulWidget {
  const _ClientBootstrap({
    this.catalog,
    this.playbackBridge,
    this.connectHost,
    this.initialProfile,
  });

  final AvacaRemoteCatalogApi? catalog;
  final AvacaRemotePlaybackBridge? playbackBridge;
  final Future<AvacaClientApplicationHost> Function()? connectHost;
  final AvacaRemoteClientProfile? initialProfile;

  @override
  State<_ClientBootstrap> createState() => _ClientBootstrapState();
}

class _ClientBootstrapState extends State<_ClientBootstrap> {
  AvacaRemoteCatalogApi? _catalog;
  AvacaClientApplicationHost? _host;
  AvacaRemoteClientProfile? _profile;
  NativeAvacaRemotePlaybackBridge? _nativePlaybackBridge;
  final AvacaRemoteProfileStore _profileStore = NativeAvacaRemoteProfileStore();
  Object? _connectionError;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog;
    _profile = widget.initialProfile;
    if (_profile != null) {
      _nativePlaybackBridge = NativeAvacaRemotePlaybackBridge(
        profile: _profile!,
      );
    }
    final connectHost = widget.connectHost;
    if (_catalog == null && connectHost != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_connectWithFactory(connectHost));
      });
    } else if (_catalog == null && _profile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_loadStoredProfile());
      });
    }
  }

  Future<void> _connectWithFactory(
    Future<AvacaClientApplicationHost> Function() connectHost,
  ) async {
    if (!mounted || _connecting) return;
    setState(() {
      _connecting = true;
      _connectionError = null;
    });
    try {
      final host = await connectHost();
      if (!mounted) {
        await host.close();
        return;
      }
      setState(() {
        _host = host;
        _catalog = host.catalog;
        _connecting = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _connectionError = error;
        });
      }
    }
  }

  Future<void> _loadStoredProfile() async {
    try {
      // A profile key is not discoverable by design.  The native store keeps
      // one profile under this stable local-client key until a future
      // multi-server index is added; the invitation still controls all
      // server/client material written into it.
      final profile = await _profileStore.load(
        AvacaRemoteProfileStore.activeKey,
      );
      if (!mounted || profile == null) return;
      setState(() {
        _profile = profile;
        _nativePlaybackBridge = NativeAvacaRemotePlaybackBridge(
          profile: profile,
        );
      });
      await _connectProfile(profile);
    } on Object catch (error) {
      if (mounted) setState(() => _connectionError = error);
    }
  }

  Future<void> _saveAndConnectProfile(AvacaRemoteClientProfile profile) async {
    try {
      await _profileStore.save(profile);
      if (!mounted) {
        profile.dispose();
        return;
      }
      final previous = _profile;
      setState(() {
        _profile = profile;
        _nativePlaybackBridge = NativeAvacaRemotePlaybackBridge(
          profile: profile,
        );
      });
      previous?.dispose();
      await _connectProfile(profile);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _connectionError = error);
      }
      // The profile remains in the secure store after a network/auth failure
      // so the user can retry without re-exposing the secret.
    }
  }

  Future<void> _connectProfile(AvacaRemoteClientProfile profile) async {
    if (!mounted || _connecting) return;
    setState(() {
      _connecting = true;
      _connectionError = null;
    });
    final transport = AvacaMsQuicTransport.client(
      certificateSha256Pin: profile.leafCertificateSha256,
    );
    final host = AvacaClientApplicationHost(transport: transport);
    try {
      await host.connect(
        endpoint: profile.endpoint,
        clientId: profile.clientId,
        expectedServerId: profile.serverId,
        pairingSecret: profile.pairingSecret,
      );
      if (!mounted) {
        await host.close();
        return;
      }
      final previousHost = _host;
      setState(() {
        _host = host;
        _catalog = host.catalog;
        _connecting = false;
      });
      await previousHost?.close();
    } on Object catch (error) {
      await host.close();
      if (mounted) {
        setState(() {
          _connecting = false;
          _connectionError = error;
        });
      }
    }
  }

  Future<void> _revokeProfile() async {
    final profile = _profile;
    if (profile == null) return;
    try {
      await _profileStore.delete(AvacaRemoteProfileStore.activeKey);
    } on Object catch (error) {
      if (mounted) setState(() => _connectionError = error);
      return;
    }
    final host = _host;
    _host = null;
    _catalog = null;
    _profile = null;
    _nativePlaybackBridge = null;
    profile.dispose();
    await host?.close();
    if (mounted) {
      setState(() {
        _connectionError = null;
        _connecting = false;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_host?.close());
    _profile?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ClientHome(
    catalog: _catalog,
    playbackBridge: widget.playbackBridge ?? _nativePlaybackBridge,
    profile: _profile,
    onProfileAccepted: _saveAndConnectProfile,
    onProfileRevoked: _revokeProfile,
    connectionStatus: _connecting
        ? '正在連線到 AVACA Server…'
        : _connectionError == null
        ? null
        : '連線失敗；請檢查 Server 設定後重試。',
  );
}

class _ClientHome extends StatefulWidget {
  const _ClientHome({
    this.catalog,
    this.playbackBridge,
    this.profile,
    this.onProfileAccepted,
    this.onProfileRevoked,
    this.connectionStatus,
  });

  final AvacaRemoteCatalogApi? catalog;
  final AvacaRemotePlaybackBridge? playbackBridge;
  final AvacaRemoteClientProfile? profile;
  final Future<void> Function(AvacaRemoteClientProfile)? onProfileAccepted;
  final Future<void> Function()? onProfileRevoked;
  final String? connectionStatus;

  @override
  State<_ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends State<_ClientHome> {
  static const _transitionDuration = Duration(milliseconds: 180);
  static const _libraryPageKey = ValueKey<String>('library-page');

  int _selectedIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // Keep page subtrees stable across navigation rebuilds.  Recreating a
    // FutureBuilder on every frame would restart catalog requests and make a
    // rapid tab switch look like a freeze.
    _pages = <Widget>[
      _LibraryPage(
        key: _libraryPageKey,
        catalog: widget.catalog,
        playbackBridge: widget.playbackBridge,
        connectionStatus: widget.connectionStatus,
      ),
      _ServersPage(
        profile: widget.profile,
        connectionStatus: widget.connectionStatus,
        onProfileAccepted: widget.onProfileAccepted,
        onProfileRevoked: widget.onProfileRevoked,
      ),
      const _SettingsPage(),
    ];
  }

  @override
  void didUpdateWidget(covariant _ClientHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The bootstrap widget is rebuilt once a Server handshake completes. Keep
    // the navigation subtree stable, but replace the library configuration
    // with the newly authenticated catalog. The stable key lets
    // _LibraryPageState reuse its lifecycle instead of restarting the whole
    // shell or leaving the page permanently offline.
    if (!identical(oldWidget.catalog, widget.catalog) ||
        oldWidget.connectionStatus != widget.connectionStatus ||
        !identical(oldWidget.playbackBridge, widget.playbackBridge)) {
      _pages[0] = _LibraryPage(
        key: _libraryPageKey,
        catalog: widget.catalog,
        playbackBridge: widget.playbackBridge,
        connectionStatus: widget.connectionStatus,
      );
    }
    if (oldWidget.profile != widget.profile ||
        oldWidget.connectionStatus != widget.connectionStatus ||
        oldWidget.onProfileAccepted != widget.onProfileAccepted ||
        oldWidget.onProfileRevoked != widget.onProfileRevoked) {
      _pages[1] = _ServersPage(
        profile: widget.profile,
        connectionStatus: widget.connectionStatus,
        onProfileAccepted: widget.onProfileAccepted,
        onProfileRevoked: widget.onProfileRevoked,
      );
    }
  }

  void _selectPage(int index) {
    if (index == _selectedIndex || index < 0 || index >= _pages.length) {
      return;
    }
    // Navigation state is local and synchronous; no I/O is started from this
    // callback.  That keeps pointer/keyboard transitions independent from a
    // reconnect or a catalog request.
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final body = AnimatedSwitcher(
      duration: _transitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: <Widget>[...previousChildren, ?currentChild],
      ),
      child: KeyedSubtree(
        key: ValueKey<int>(_selectedIndex),
        child: _pages[_selectedIndex],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        return Scaffold(
          appBar: AppBar(title: const Text('AVACA')),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _selectPage,
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.video_library_outlined),
                          selectedIcon: Icon(Icons.video_library),
                          label: Text('Library'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.dns_outlined),
                          selectedIcon: Icon(Icons.dns),
                          label: Text('伺服器'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: Text('設定'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectPage,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.video_library_outlined),
                      selectedIcon: Icon(Icons.video_library),
                      label: 'Library',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.dns_outlined),
                      selectedIcon: Icon(Icons.dns),
                      label: '伺服器',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: '設定',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _LibraryPage extends StatefulWidget {
  const _LibraryPage({
    super.key,
    this.catalog,
    this.playbackBridge,
    this.connectionStatus,
  });

  final AvacaRemoteCatalogApi? catalog;
  final AvacaRemotePlaybackBridge? playbackBridge;
  final String? connectionStatus;

  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  Future<AvacaCollectionPage>? _pageFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.catalog, widget.catalog)) {
      _reload();
    }
  }

  void _reload() {
    final catalog = widget.catalog;
    if (catalog == null) {
      _pageFuture = null;
      return;
    }
    // The request starts from lifecycle code, never from build.  FutureBuilder
    // only observes its result, so a slow Server cannot block a frame.
    _pageFuture = catalog.listCollection(limit: 50);
  }

  @override
  Widget build(BuildContext context) {
    final future = _pageFuture;
    if (future == null) {
      return _offlineView();
    }
    return FutureBuilder<AvacaCollectionPage>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = snapshot.error;
        if (error != null) {
          return _CatalogError(
            message: '目錄載入失敗，Server 仍可操作。',
            onRetry: () => setState(_reload),
          );
        }
        final page = snapshot.data;
        if (page == null || page.items.isEmpty) {
          return _emptyView();
        }
        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: page.items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = page.items[index];
            return Card(
              child: ListTile(
                title: Text(item.title),
                subtitle: Text(item.code),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openDetail(context, item),
              ),
            );
          },
        );
      },
    );
  }

  Widget _offlineView() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('瀏覽 Library', style: TextStyle(fontSize: 22)),
        const SizedBox(height: 12),
        if (widget.connectionStatus != null) ...[
          Text(widget.connectionStatus!),
          const SizedBox(height: 8),
        ],
        const Text('尚未連線到 AVACA Server，請先在「伺服器」完成配對。'),
        const SizedBox(height: 8),
        const Text('目錄、詳情與播放由 AVACA 用戶端負責。'),
        const SizedBox(height: 8),
        const Text('媒體資料只透過原生 QUIC range stream 讀取，不建立 HTTP/SMB 或暫存整檔。'),
      ],
    ),
  );

  Widget _emptyView() => const Center(child: Text('Server Library 目前沒有可播放媒體。'));

  void _openDetail(BuildContext context, AvacaWorkSummary item) {
    final catalog = widget.catalog;
    if (catalog == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _WorkDetailPage(
          catalog: catalog,
          playbackBridge: widget.playbackBridge,
          work: item,
        ),
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 40),
        const SizedBox(height: 12),
        Text(message),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('重試')),
      ],
    ),
  );
}

class _WorkDetailPage extends StatefulWidget {
  const _WorkDetailPage({
    required this.catalog,
    required this.work,
    this.playbackBridge,
  });

  final AvacaRemoteCatalogApi catalog;
  final AvacaRemotePlaybackBridge? playbackBridge;
  final AvacaWorkSummary work;

  @override
  State<_WorkDetailPage> createState() => _WorkDetailPageState();
}

class _WorkDetailPageState extends State<_WorkDetailPage> {
  late final Future<AvacaWorkDetail> _detailFuture = widget.catalog
      .getWorkDetail(widget.work.workId);
  AvacaRemotePlaybackHandle? _playbackHandle;
  AvacaRemotePlaybackSource? _playbackSource;
  NativeAvacaPlayerSurfaceInfo? _nativeSurface;
  bool _playbackBusy = false;
  bool _disposed = false;
  String? _playbackStatus;

  @override
  void dispose() {
    _disposed = true;
    unawaited(_stopPlayback(updateStatus: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.work.code)),
    body: FutureBuilder<AvacaWorkDetail>(
      future: _detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final detail = snapshot.data;
        if (detail == null || snapshot.hasError) {
          return const Center(child: Text('詳情載入失敗，請返回後重試。'));
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              detail.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(detail.code),
            if (detail.description != null) ...[
              const SizedBox(height: 12),
              Text(detail.description!),
            ],
            if (_nativeSurface != null) ...[
              const SizedBox(height: 20),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: NativeAvacaPlayerSurface(surface: _nativeSurface!),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text('媒體', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (detail.media.isEmpty)
              const Text('此 Work 沒有可播放媒體。')
            else
              ...detail.media.map(_mediaTile),
            if (_playbackHandle != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _playbackBusy ? null : _stopPlayback,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('停止'),
              ),
            ],
            if (_playbackStatus != null) ...[
              const SizedBox(height: 16),
              Text(_playbackStatus!),
            ],
          ],
        );
      },
    ),
  );

  Widget _mediaTile(AvacaMediaSummary media) => Card(
    child: ListTile(
      title: Text(media.title),
      subtitle: Text(_availabilityLabel(media.availability)),
      trailing: media.availability == AvacaMediaAvailability.available
          ? FilledButton(
              onPressed: _playbackBusy ? null : () => _startPlayback(media),
              child: const Text('播放'),
            )
          : null,
    ),
  );

  Future<void> _startPlayback(AvacaMediaSummary media) async {
    final bridge = widget.playbackBridge;
    if (bridge == null) {
      setState(() => _playbackStatus = '原生播放 bridge 尚未設定，已安全停止。');
      return;
    }
    if (_playbackBusy) return;
    setState(() {
      _playbackBusy = true;
      _playbackStatus = '正在建立播放 session…';
    });
    AvacaRemotePlaybackSource? source;
    AvacaRemotePlaybackHandle? handle;
    try {
      source = await RemotePlaybackRepository(
        widget.catalog,
      ).createSession(media.mediaId);
      handle = await AvacaNativePlaybackSource(source.resource).open(bridge);
      await _stopPlayback();
      if (!mounted) {
        await handle.close();
        await widget.catalog.closePlaybackSession(source.sessionId);
        return;
      }
      setState(() {
        _playbackSource = source;
        _playbackHandle = handle;
        _nativeSurface = bridge is NativeAvacaRemotePlaybackBridge
            ? bridge.lastSurface
            : null;
        _playbackStatus = '播放中（Server range stream），可按停止釋放 session。';
      });
    } on Object {
      if (handle != null) await handle.close();
      if (source != null) {
        await widget.catalog.closePlaybackSession(source.sessionId);
      }
      if (mounted) {
        setState(() => _playbackStatus = '播放初始化失敗，已釋放 Server session。');
      }
    } finally {
      if (mounted) setState(() => _playbackBusy = false);
    }
  }

  Future<void> _stopPlayback({bool updateStatus = true}) async {
    final handle = _playbackHandle;
    final source = _playbackSource;
    _playbackHandle = null;
    _playbackSource = null;
    _nativeSurface = null;
    if (handle != null) {
      try {
        await handle.close();
      } on Object {
        // Session close below remains authoritative.
      }
    }
    if (source != null) {
      try {
        await widget.catalog.closePlaybackSession(source.sessionId);
      } on Object {
        // A disconnected Server has already invalidated the session.
      }
    }
    if (updateStatus && mounted && !_disposed && !_playbackBusy) {
      setState(() => _playbackStatus = '已停止並釋放播放 session。');
    }
  }

  String _availabilityLabel(AvacaMediaAvailability availability) =>
      switch (availability) {
        AvacaMediaAvailability.available => '可播放',
        AvacaMediaAvailability.unavailable => 'Server 媒體不可用',
        AvacaMediaAvailability.unknown => 'Server 尚未確認媒體狀態',
      };
}

class _ServersPage extends StatefulWidget {
  const _ServersPage({
    this.profile,
    this.connectionStatus,
    this.onProfileAccepted,
    this.onProfileRevoked,
  });

  final AvacaRemoteClientProfile? profile;
  final String? connectionStatus;
  final Future<void> Function(AvacaRemoteClientProfile)? onProfileAccepted;
  final Future<void> Function()? onProfileRevoked;

  @override
  State<_ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<_ServersPage> {
  late final TextEditingController _invitationController;
  final NativeAvacaRemoteDiscovery _discovery =
      const NativeAvacaRemoteDiscovery();
  StreamSubscription<AvacaRemoteDiscoveryEvent>? _discoverySubscription;
  final List<AvacaRemoteDiscoveryEvent> _discovered =
      <AvacaRemoteDiscoveryEvent>[];
  final AvacaPairingEndpointResolver _endpointResolver =
      AvacaPairingEndpointResolver();
  List<AvacaRemoteDiscoveryEvent> _matchingCandidates =
      <AvacaRemoteDiscoveryEvent>[];
  AvacaRemoteDiscoveryEvent? _selectedMatchingCandidate;
  AvacaPairingInvitation? _pendingInvitation;
  Object? _error;
  String? _discoveryError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _invitationController = TextEditingController();
    if (Platform.isWindows || Platform.isAndroid) {
      unawaited(_startDiscovery());
    }
  }

  Future<void> _startDiscovery() async {
    _discovered.clear();
    _matchingCandidates = <AvacaRemoteDiscoveryEvent>[];
    _selectedMatchingCandidate = null;
    _discoverySubscription = _discovery.events().listen(
      (event) {
        if (!mounted) return;
        final key = _candidateKey(event);
        setState(() {
          _discovered.removeWhere((existing) => _candidateKey(existing) == key);
          _discovered.add(event);
          _refreshMatchingCandidates();
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (mounted) setState(() => _discoveryError = 'Discovery 暫時不可用。');
      },
    );
    try {
      await _discovery.start();
    } on Object {
      if (mounted) setState(() => _discoveryError = 'Discovery 暫時不可用。');
    }
  }

  @override
  void dispose() {
    _pendingInvitation?.dispose();
    _invitationController.dispose();
    _discoverySubscription?.cancel();
    unawaited(_discovery.stop());
    super.dispose();
  }

  void _previewInvitation() {
    final code = _invitationController.text.trim();
    try {
      final invitation = AvacaPairingInvitationCodec().decode(code);
      final matches = _endpointResolver.matchingCandidates(
        invitation,
        _discovered,
      );
      _pendingInvitation?.dispose();
      setState(() {
        _pendingInvitation = invitation;
        _matchingCandidates = matches;
        _selectedMatchingCandidate = matches.length == 1
            ? matches.single
            : null;
        _error = null;
      });
    } on Object catch (error) {
      setState(() {
        _pendingInvitation?.dispose();
        _pendingInvitation = null;
        _matchingCandidates = <AvacaRemoteDiscoveryEvent>[];
        _selectedMatchingCandidate = null;
        _error = error;
      });
    }
  }

  Future<void> _scanInvitation() async {
    if (!Platform.isAndroid || _busy) return;
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('掃描 AVACA invitation'),
        content: SizedBox(
          width: 360,
          height: 360,
          child: MobileScanner(
            onDetect: (capture) {
              final value = capture.barcodes
                  .map((barcode) => barcode.rawValue)
                  .whereType<String>()
                  .firstWhere(
                    (value) =>
                        value.startsWith(AvacaPairingInvitationCodec.prefix),
                    orElse: () => '',
                  );
              if (value.isNotEmpty && dialogContext.mounted) {
                Navigator.of(dialogContext).pop(value);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (!mounted || code == null || code.isEmpty) return;
    _invitationController.text = code;
    _previewInvitation();
  }

  Future<void> _acceptInvitation() async {
    final invitation = _pendingInvitation;
    final callback = widget.onProfileAccepted;
    if (invitation == null || callback == null || _busy) return;
    if (_matchingCandidates.length > 1 && _selectedMatchingCandidate == null) {
      setState(() {
        _error = StateError('請先選擇符合的區網 Server 端點。');
      });
      return;
    }
    late final AvacaRemoteClientProfile profile;
    try {
      profile = _endpointResolver.createProfile(
        invitation,
        selectedMatchingCandidate: _selectedMatchingCandidate,
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
      return;
    }
    setState(() => _busy = true);
    try {
      await callback(profile);
      if (mounted) {
        setState(() {
          _pendingInvitation = null;
          _matchingCandidates = <AvacaRemoteDiscoveryEvent>[];
          _selectedMatchingCandidate = null;
          _error = null;
        });
      }
      invitation.dispose();
    } on Object catch (error) {
      profile.dispose();
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    final callback = widget.onProfileRevoked;
    if (callback == null || _busy) return;
    setState(() => _busy = true);
    try {
      await callback();
      if (mounted) setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _refreshMatchingCandidates() {
    final invitation = _pendingInvitation;
    if (invitation == null) {
      _matchingCandidates = <AvacaRemoteDiscoveryEvent>[];
      _selectedMatchingCandidate = null;
      return;
    }
    try {
      final matches = _endpointResolver.matchingCandidates(
        invitation,
        _discovered,
      );
      final selectedKey = _selectedMatchingCandidate == null
          ? null
          : _candidateKey(_selectedMatchingCandidate!);
      AvacaRemoteDiscoveryEvent? selected;
      if (selectedKey != null) {
        for (final candidate in matches) {
          if (_candidateKey(candidate) == selectedKey) {
            selected = candidate;
            break;
          }
        }
      }
      if (selected == null && matches.length == 1) {
        selected = matches.single;
      }
      _matchingCandidates = matches;
      _selectedMatchingCandidate = selected;
    } on FormatException {
      _matchingCandidates = <AvacaRemoteDiscoveryEvent>[];
      _selectedMatchingCandidate = null;
    }
  }

  String _candidateKey(AvacaRemoteDiscoveryEvent event) =>
      '${event.candidate.serverId}\u0000${event.endpoint.host}\u0000${event.endpoint.port}';

  bool get _canConfirmInvitation =>
      _pendingInvitation != null &&
      (_matchingCandidates.length < 2 || _selectedMatchingCandidate != null);

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('伺服器', style: TextStyle(fontSize: 22)),
        const SizedBox(height: 12),
        const Text('連線與配對由 AVACA 用戶端負責；Library 真相保留在 AVACA Server。'),
        const SizedBox(height: 16),
        _pairingCard(context),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Discovery',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  '_avaca-remote._udp 只提供 protocol、Server ID、port、certificate pin 與短期 nonce；不會公告 secret，也不會因 discovery 自動信任。',
                ),
                const SizedBox(height: 8),
                Text(
                  widget.connectionStatus ??
                      (widget.profile == null ? '尚未配對' : '已保存配對資料'),
                ),
                if (_discoveryError != null) ...[
                  const SizedBox(height: 8),
                  Text(_discoveryError!),
                ],
                if (_discovered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('目前沒有通過 mDNS 發現的 Server；仍可貼上 invitation。'),
                  )
                else ...[
                  const SizedBox(height: 12),
                  const Text(
                    '發現到的 Server 候選（只提供提示，仍需 invitation 認證）：',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  ..._discovered.map(
                    (event) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(event.candidate.serverId),
                      subtitle: Text(
                        '${event.endpoint.host}:${event.endpoint.port}\n'
                        'leaf SHA-256：${_hex(event.candidate.leafCertificateSha256)}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _pairingCard(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '配對 AVACA Server',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '請掃描 Server 顯示的 QR，或貼上 AVACA-PAIR-V2. invitation。解析後會先顯示端點與 pin，確認後才寫入 Windows DPAPI／Android Keystore。',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _invitationController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Invitation code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _previewInvitation,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('預覽 invitation'),
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _scanInvitation,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('掃描 QR'),
                ),
              ],
              if (widget.profile != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _revoke,
                  icon: const Icon(Icons.link_off),
                  label: const Text('撤銷配對'),
                ),
              ],
            ],
          ),
          if (widget.profile != null) ...[
            const SizedBox(height: 12),
            _profileSummary(widget.profile!, title: '目前配對'),
          ],
          if (_pendingInvitation != null) ...[
            const SizedBox(height: 12),
            _pendingInvitationPreview(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              '配對資料無效或保存失敗，請重新取得 invitation。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _profileSummary(
    AvacaRemoteClientProfile profile, {
    required String title,
    DateTime? expiresAt,
  }) {
    final pin = _hex(profile.leafCertificateSha256);
    // This temporary profile is created solely to render the confirmation
    // fields; its secret is never rendered and is wiped immediately.
    if (expiresAt != null) profile.dispose();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Server ID：${profile.serverId}'),
        Text('端點：${profile.host}:${profile.port}'),
        Text('leaf SHA-256：$pin'),
        if (expiresAt != null)
          Text('有效至：${expiresAt.toLocal().toIso8601String()}'),
      ],
    );
  }

  Widget _pendingInvitationPreview() {
    final invitation = _pendingInvitation!;
    final selected = _selectedMatchingCandidate;
    final hasMultipleMatches = _matchingCandidates.length > 1;
    final endpoint = selected?.endpoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '請確認這個 Server',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text('Server ID：${invitation.serverId}'),
        Text('leaf SHA-256：${_hex(invitation.leafCertificateSha256)}'),
        Text('有效至：${invitation.expiresAt.toLocal().toIso8601String()}'),
        if (endpoint != null) ...[
          Text('端點：${endpoint.host}:${endpoint.port}'),
          Text(
            '端點來源：${hasMultipleMatches ? '已選擇的 LAN discovery matched' : 'LAN discovery matched'}',
          ),
        ] else if (_matchingCandidates.isEmpty) ...[
          Text('端點：${invitation.host}:${invitation.port}'),
          const Text('端點來源：直接 invitation'),
        ] else ...[
          const Text('端點：尚未選擇'),
          const Text('端點來源：多個符合的 LAN discovery 候選'),
        ],
        if (hasMultipleMatches) ...[
          const SizedBox(height: 8),
          const Text('找到多個完全符合的區網端點，請明確選擇：'),
          RadioGroup<String>(
            groupValue: selected == null ? null : _candidateKey(selected),
            onChanged: (value) {
              if (value == null) return;
              for (final item in _matchingCandidates) {
                if (_candidateKey(item) == value) {
                  setState(() => _selectedMatchingCandidate = item);
                  break;
                }
              }
            },
            child: Column(
              children: _matchingCandidates
                  .map(
                    (candidate) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: _candidateKey(candidate),
                      title: Text(
                        '${candidate.endpoint.host}:${candidate.endpoint.port}',
                      ),
                      subtitle: Text(
                        'Server ID：${candidate.candidate.serverId}\n'
                        'leaf SHA-256：${_hex(candidate.candidate.leafCertificateSha256)}',
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy || !_canConfirmInvitation ? null : _acceptInvitation,
          child: const Text('確認並保存配對'),
        ),
      ],
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    padding: EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('設定', style: TextStyle(fontSize: 22)),
        SizedBox(height: 12),
        Text('用戶端只保存連線、顯示與播放偏好，不保存 Server Library 真相。'),
      ],
    ),
  );
}

/// Real Windows client composition. Configuration is opt-in: without all
/// required fields the app intentionally stays in its responsive offline
/// shell instead of guessing a host, identity, or pairing secret.
final class AvacaClientEnvironmentConnection {
  const AvacaClientEnvironmentConnection({
    required this.host,
    required this.port,
    required this.serverId,
    required this.clientId,
    required this.serverCertificateSha256,
    required this.pairingSecret,
  });

  final String host;
  final int port;
  final String serverId;
  final String clientId;
  final List<int> serverCertificateSha256;
  final List<int> pairingSecret;

  static AvacaClientEnvironmentConnection? fromEnvironment([
    Map<String, String>? values,
  ]) {
    if (!Platform.isWindows) return null;
    final environment = values ?? Platform.environment;
    final host = environment['AVACA_SERVER_HOST']?.trim();
    final serverId = environment['AVACA_SERVER_ID']?.trim();
    final clientId = environment['AVACA_CLIENT_ID']?.trim();
    final port = int.tryParse(environment['AVACA_SERVER_PORT'] ?? '');
    final certificate = _decodeHex(
      environment['AVACA_SERVER_CERT_SHA256_HEX'],
      exactBytes: 32,
    );
    final secret = _decodeHex(
      environment['AVACA_PAIRING_SECRET_HEX'],
      exactBytes: 32,
    );
    if (host == null ||
        host.isEmpty ||
        !_validId(serverId) ||
        !_validId(clientId) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        certificate == null ||
        secret == null) {
      return null;
    }
    return AvacaClientEnvironmentConnection(
      host: host,
      port: port,
      serverId: serverId!,
      clientId: clientId!,
      serverCertificateSha256: certificate,
      pairingSecret: secret,
    );
  }

  Future<AvacaClientApplicationHost> connect() async {
    final transport = AvacaMsQuicTransport.client(
      certificateSha256Pin: serverCertificateSha256,
    );
    final application = AvacaClientApplicationHost(transport: transport);
    try {
      await application.connect(
        endpoint: AvacaRemoteEndpoint(host: host, port: port),
        clientId: clientId,
        expectedServerId: serverId,
        pairingSecret: pairingSecret,
      );
      return application;
    } on Object {
      await application.close();
      rethrow;
    }
  }

  AvacaRemoteClientProfile toProfile() => AvacaRemoteClientProfile(
    serverId: serverId,
    clientId: clientId,
    host: host,
    port: port,
    leafCertificateSha256: serverCertificateSha256,
    pairingSecret: pairingSecret,
  );

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

String _hex(List<int> bytes) => bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join()
    .toUpperCase();
