import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import '../demo_configuration.dart';
import '../demo_downlink_support.dart';
import '../demo_permissions.dart';
import '../demo_test_hooks.dart';
import '../settings/downlink_configuration_store.dart';
import '../settings/demo_example_settings_store.dart';
import '../store/store_entry_page.dart';
import '../widgets/configure_page_widgets.dart';
import '../widgets/notice_dialog.dart';
import 'player_page.dart';
import 'qr_scanner_page.dart';
import 'settings_page.dart';

class DemoConfigurePage extends StatefulWidget {
  const DemoConfigurePage({super.key});

  @override
  State<DemoConfigurePage> createState() => _DemoConfigurePageState();
}

class _DemoConfigurePageState extends State<DemoConfigurePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const int _runtimeObjectsLiveCode = 6026;
  static const int _runtimeShutdownRetryCount = 10;
  static const Duration _runtimeShutdownRetryDelay = Duration(milliseconds: 100);
  static const SystemUiOverlayStyle _configurePageOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _appIdController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _remoteIdController = TextEditingController();
  final TextEditingController _audioStreamIdController = TextEditingController();
  final TextEditingController _videoStreamIdController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _tokenServerAddressController = TextEditingController();
  final DemoTokenAcquirer _tokenAcquirer = const DemoTokenAcquirer();
  final DemoExamplePermissions _permissions = const DemoExamplePermissions();
  final DemoExampleSettingsStore _settingsStore = const DemoExampleSettingsStore();
  final DemoDownlinkConfigurationStore _configurationStore = const DemoDownlinkConfigurationStore();
  final DemoLogUploader _logUploader = DemoLogUploader();
  late final TabController _productTabController;

  bool _submitted = false;
  bool _startingPlayer = false;
  bool _uploadingLogs = false;
  DemoExampleSettings _settings = const DemoExampleSettings();
  bool _iosLocalNetworkPermissionReady = false;
  Future<bool>? _iosLocalNetworkPermissionRequest;
  Timer? _configurationSaveDebounce;
  bool _applyingStoredConfiguration = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _productTabController = TabController(length: 2, vsync: this);
    _productTabController.addListener(_onProductTabChanged);
    _attachConfigurationAutosaveListeners();
    unawaited(_loadConfigurationSnapshot());
    unawaited(_loadSettingsSnapshot(reason: 'initial'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyConfigurePageSystemOverlayStyle();
      unawaited(_requestIosLocalNetworkPermissionIfNeeded());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _productTabController
      ..removeListener(_onProductTabChanged)
      ..dispose();
    _appIdController.dispose();
    _endpointController.dispose();
    _remoteIdController.dispose();
    _audioStreamIdController.dispose();
    _videoStreamIdController.dispose();
    _tokenController.dispose();
    _tokenServerAddressController.dispose();
    _configurationSaveDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showBackdropOrbs = !Platform.isMacOS;
    final bool runtimeBusy = _startingPlayer || _uploadingLogs;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _configurePageOverlayStyle,
      child: Scaffold(
        body: ConfigurePageBackground(
          showBackdropOrbs: showBackdropOrbs,
          onTap: _dismissKeyboard,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      ConfigureHeader(
                        startingPlayer: runtimeBusy,
                        onOpenSettings: _openSettings,
                      ),
                      const SizedBox(height: 16),
                      ConfigureProductTabBar(controller: _productTabController),
                      const SizedBox(height: 20),
                      IndexedStack(
                        index: _productTabController.index,
                        children: <Widget>[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              ConfigureForm(
                                formKey: _formKey,
                                submitted: _submitted,
                                enabled: !runtimeBusy,
                                startingPlayer: _startingPlayer,
                                appIdController: _appIdController,
                                endpointController: _endpointController,
                                remoteIdController: _remoteIdController,
                                audioStreamIdController: _audioStreamIdController,
                                videoStreamIdController: _videoStreamIdController,
                                tokenController: _tokenController,
                                tokenServerAddressController: _tokenServerAddressController,
                                validateEndpoint: _validateEndpoint,
                                validateStreamId: _validateStreamId,
                                validateOneTimeToken: _validateOneTimeToken,
                                validateTokenServerAddress: _validateTokenServerAddress,
                                scanSupported: _scanSupported,
                                onScanToken: _scanToken,
                                onStartPlaying: _startPlaying,
                              ),
                              const SizedBox(height: 2),
                              ConfigureLogUploadAction(
                                enabled: !runtimeBusy,
                                uploading: _uploadingLogs,
                                onUpload: _uploadLogsFromConfigurePage,
                              ),
                            ],
                          ),
                          DemoStoreEntryPage(enabled: !runtimeBusy),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _scanSupported => Platform.isAndroid || Platform.isIOS;

  void _onProductTabChanged() {
    if (!_productTabController.indexIsChanging && mounted) {
      setState(() {});
    }
  }

  String? _validateEndpoint(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }

    final Uri? uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '请输入完整的 http(s) URL。';
    }
    return null;
  }

  String? _validateOneTimeToken(String? value) {
    final String token = (value ?? '').trim();
    if (token.isEmpty) {
      if (_tokenServerAddressController.text.trim().isEmpty) {
        return '请填写一次性 Token，或填写 DevTools 服务地址。';
      }
      return null;
    }
    try {
      normalizeDemoConnectionToken(token);
    } on FormatException {
      return '请输入有效的一次性连接 Token。';
    }
    return null;
  }

  String? _validateTokenServerAddress(String? value) {
    if (_tokenController.text.trim().isNotEmpty) {
      return null;
    }
    final String address = (value ?? '').trim();
    if (address.isEmpty) {
      return null;
    }
    try {
      normalizeDemoTokenServerAddress(address);
    } on FormatException {
      return '请输入完整的 DevTools 服务地址，例如 http://192.168.1.10:8966。';
    }
    return null;
  }

  String? _validateStreamId(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    if (int.tryParse(text) == null) {
      return '请输入整数。';
    }
    return null;
  }

  String _resolvedEndpoint() {
    return _endpointController.text.trim();
  }

  String _resolvedAppId() {
    return _appIdController.text.trim();
  }

  Future<void> _startPlaying() async {
    if (_startingPlayer || _uploadingLogs) {
      return;
    }
    final DemoDownlinkConfiguration? configuration = _validatedConfiguration(showFeedback: true);
    if (configuration == null) {
      return;
    }
    await _saveConfigurationSnapshot();
    await _openPlayer(configuration);
  }

  Future<void> _uploadLogsFromConfigurePage() async {
    if (_startingPlayer || _uploadingLogs) {
      return;
    }

    _dismissKeyboard();
    setState(() {
      _uploadingLogs = true;
    });

    try {
      final int initializeCode = await TiRtc.init(const TiRtcInitOptions());
      if (initializeCode != 0) {
        if (mounted) {
          await context.showNoticeDialog(
            title: '日志上传失败',
            content: '日志初始化失败，code $initializeCode。',
          );
        }
        return;
      }

      final String marker = 'FLUTTER_HOME_LOG_UPLOAD_${DateTime.now().toLocal().toIso8601String()}';
      TiRtcLogging.i(
        'flutter_example',
        'home_log_upload_marker=$marker',
      );
      await _logUploader.upload(
        remoteId: _remoteIdController.text.trim(),
        isActive: () => mounted,
        showResult: ({
          required String title,
          required String content,
        }) {
          if (!mounted) {
            return Future<void>.value();
          }
          return context.showNoticeDialog(
            title: title,
            content: content,
          );
        },
      );
    } finally {
      final int shutdownCode = await _shutdownRuntimeAfterDisposal();
      if (shutdownCode != 0) {
        TiRtcLogging.w(
          'flutter_example',
          'home_log_upload_runtime_shutdown_failed code=$shutdownCode',
        );
      }
      if (mounted) {
        setState(() {
          _uploadingLogs = false;
        });
      }
    }
  }

  DemoDownlinkConfiguration? _validatedConfiguration({
    required bool showFeedback,
  }) {
    setState(() {
      _submitted = true;
    });

    final bool valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      if (showFeedback) {
        _showSnack('请先补全必填项。');
      }
      return null;
    }

    return DemoDownlinkConfiguration(
      appId: _resolvedAppId(),
      endpoint: _resolvedEndpoint(),
      remoteId: _remoteIdController.text.trim(),
      audioStreamId: _resolvedStreamId(
        controller: _audioStreamIdController,
        fallback: DemoDownlinkConfiguration.defaultAudioStreamId,
      ),
      videoStreamId: _resolvedStreamId(
        controller: _videoStreamIdController,
        fallback: DemoDownlinkConfiguration.defaultVideoStreamId,
      ),
      token: _tokenController.text.trim(),
      settings: _settings,
      tokenServerAddress: _tokenServerAddressController.text.trim(),
    );
  }

  int _resolvedStreamId({
    required TextEditingController controller,
    required int fallback,
  }) {
    final String text = controller.text.trim();
    if (text.isEmpty) {
      return fallback;
    }
    return int.parse(text);
  }

  Future<void> _openPlayer(DemoDownlinkConfiguration configuration) async {
    if (_startingPlayer) {
      return;
    }

    _dismissKeyboard();
    setState(() {
      _startingPlayer = true;
    });

    final bool localNetworkReady = await _requestIosLocalNetworkPermissionIfNeeded();
    if (!localNetworkReady) {
      if (mounted) {
        setState(() {
          _startingPlayer = false;
        });
        _showSnack('请先允许 iOS 本地网络权限后再播放。');
      }
      return;
    }

    final DemoDownlinkConfiguration resolvedConfiguration;
    try {
      resolvedConfiguration = await _configurationWithResolvedToken(configuration);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _startingPlayer = false;
        });
        _showSnack('token 获取失败：$error');
      }
      return;
    }
    if (!mounted) {
      return;
    }

    TiRtcLogging.i(
      'flutter_example',
      'runtime_initialize_requested appIdPresent=${resolvedConfiguration.appId.isNotEmpty} '
          'endpoint=${resolvedConfiguration.endpoint} remoteId=${resolvedConfiguration.remoteId} '
          'tokenPresent=${resolvedConfiguration.token.isNotEmpty}',
    );
    final int initializeCode = await TiRtc.init(
      TiRtcInitOptions(
        appId: resolvedConfiguration.appId,
        endpoint: resolvedConfiguration.endpoint,
        consoleLogEnabled: resolvedConfiguration.settings.consoleLogEnabled,
      ),
    );
    if (!mounted) {
      if (initializeCode == 0) {
        await _shutdownRuntimeAfterDisposal();
      }
      return;
    }

    if (initializeCode != 0) {
      setState(() {
        _startingPlayer = false;
      });
      TiRtcLogging.w(
        'flutter_example',
        'runtime_initialize_failed code=$initializeCode endpoint=${resolvedConfiguration.endpoint}',
      );
      _showSnack('运行时初始化失败，code $initializeCode。');
      return;
    }

    TiRtcLogging.i(
      'flutter_example',
      'runtime_initialized endpoint=${resolvedConfiguration.endpoint}',
    );

    try {
      TiRtcLogging.i(
        'flutter_example',
        'open_player endpoint=${resolvedConfiguration.endpoint} '
            'remoteId=${resolvedConfiguration.remoteId} '
            'audioStreamId=${resolvedConfiguration.audioStreamId} '
            'videoStreamId=${resolvedConfiguration.videoStreamId}',
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (BuildContext context) {
            final DemoExampleSmokeHooks? smokeHooks = DemoExampleSmokeHooks.current;
            return DemoPlayerPage(
              configuration: resolvedConfiguration,
              smokeMarkerSink: smokeHooks?.markerSink,
              smokeRenderWindowSeconds: smokeHooks?.renderWindowSeconds ?? 30,
            );
          },
        ),
      );
      _dismissKeyboard();
      _clearVolatileTokenInputs();
      _applyConfigurePageSystemOverlayStyle();
    } finally {
      final int shutdownCode = await _shutdownRuntimeAfterDisposal();
      if (shutdownCode != 0) {
        TiRtcLogging.w('flutter_example', 'runtime_shutdown_failed code=$shutdownCode');
      }
      if (mounted) {
        setState(() {
          _startingPlayer = false;
        });
      }
    }
  }

  Future<DemoDownlinkConfiguration> _configurationWithResolvedToken(
    DemoDownlinkConfiguration configuration,
  ) async {
    final String token = await _tokenAcquirer.resolve(
      token: configuration.token,
      serverAddress: configuration.tokenServerAddress,
      remoteId: configuration.remoteId,
    );
    TiRtcLogging.i(
      'flutter_example',
      'token_resolved source=${configuration.token.isNotEmpty ? 'one_time' : 'devtools_server'} '
          'remoteId=${configuration.remoteId}',
    );
    return configuration.withToken(token);
  }

  Future<void> _openSettings() async {
    if (_startingPlayer || _uploadingLogs) {
      return;
    }
    _dismissKeyboard();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DemoSettingsPage(
          initialSettings: _settings,
          settingsStore: _settingsStore,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    await _loadSettingsSnapshot(reason: 'settings_return');
    _applyConfigurePageSystemOverlayStyle();
  }

  Future<void> _loadSettingsSnapshot({required String reason}) async {
    final DemoExampleSettings settings = await _settingsStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
    });
    TiRtcLogging.i(
      'flutter_example',
      'example_settings_loaded reason=$reason '
          'video_decoder_preference=${settings.videoDecoderPreference} '
          'output_buffer_policy=${settings.outputBufferPolicy} '
          'console_log_enabled=${settings.consoleLogEnabled}',
    );
  }

  void _attachConfigurationAutosaveListeners() {
    for (final TextEditingController controller in <TextEditingController>[
      _appIdController,
      _endpointController,
      _remoteIdController,
      _audioStreamIdController,
      _videoStreamIdController,
      _tokenServerAddressController,
    ]) {
      controller.addListener(_scheduleConfigurationSave);
    }
  }

  Future<void> _loadConfigurationSnapshot() async {
    final DemoDownlinkConfigurationSnapshot snapshot = await _configurationStore.load();
    if (!mounted) {
      return;
    }
    _applyingStoredConfiguration = true;
    _appIdController.text = snapshot.appId;
    _endpointController.text = snapshot.endpoint;
    _remoteIdController.text = snapshot.remoteId;
    _audioStreamIdController.text = snapshot.audioStreamId;
    _videoStreamIdController.text = snapshot.videoStreamId;
    _tokenServerAddressController.text = snapshot.tokenServerAddress;
    _applyingStoredConfiguration = false;
    TiRtcLogging.i(
      'flutter_example',
      'downlink_configuration_loaded appIdPresent=${snapshot.appId.isNotEmpty} '
          'endpoint=${snapshot.endpoint} remoteId=${snapshot.remoteId} '
          'tokenServerAddressPresent=${snapshot.tokenServerAddress.isNotEmpty}',
    );
  }

  Future<void> _scanToken() async {
    if (!_scanSupported || _startingPlayer || _uploadingLogs) {
      return;
    }

    _dismissKeyboard();
    final DemoScanPayload? payload = await Navigator.of(context).push<DemoScanPayload>(
      MaterialPageRoute<DemoScanPayload>(
        builder: (BuildContext context) => const DemoQrScannerPage(),
      ),
    );
    if (!mounted || payload == null) {
      return;
    }

    setState(() {
      _tokenController.text = payload.token;
      if (payload.appId != null) {
        _appIdController.text = payload.appId!;
      }
      if (payload.remoteId != null) {
        _remoteIdController.text = payload.remoteId!;
      }
      if (payload.endpoint != null) {
        _endpointController.text = payload.endpoint!;
      }
    });
    TiRtcLogging.i(
      'flutter_example',
      'qr_token_applied appIdPresent=${payload.appId != null} '
          'remoteIdPresent=${payload.remoteId != null} endpointPresent=${payload.endpoint != null}',
    );
  }

  void _clearVolatileTokenInputs() {
    if (_tokenController.text.isEmpty) {
      return;
    }
    _tokenController.clear();
  }

  void _scheduleConfigurationSave() {
    if (_applyingStoredConfiguration) {
      return;
    }
    _configurationSaveDebounce?.cancel();
    _configurationSaveDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_saveConfigurationSnapshot());
    });
  }

  DemoDownlinkConfigurationSnapshot _currentConfigurationSnapshot() {
    return DemoDownlinkConfigurationSnapshot(
      appId: _appIdController.text.trim(),
      endpoint: _endpointController.text.trim(),
      remoteId: _remoteIdController.text.trim(),
      audioStreamId: _audioStreamIdController.text.trim(),
      videoStreamId: _videoStreamIdController.text.trim(),
      tokenServerAddress: _tokenServerAddressController.text.trim(),
    );
  }

  Future<void> _saveConfigurationSnapshot() async {
    try {
      await _configurationStore.save(_currentConfigurationSnapshot());
    } on Object catch (error) {
      TiRtcLogging.w('flutter_example', 'downlink_configuration_save_failed error=$error');
    }
  }

  Future<bool> _requestIosLocalNetworkPermissionIfNeeded() async {
    if (!Platform.isIOS || _iosLocalNetworkPermissionReady) {
      return true;
    }
    final Future<bool>? inFlightRequest = _iosLocalNetworkPermissionRequest;
    if (inFlightRequest != null) {
      return inFlightRequest;
    }

    final Future<bool> request = _permissions.requestLocalNetworkPermissionIfNeeded();
    _iosLocalNetworkPermissionRequest = request;
    TiRtcLogging.i('flutter_example', 'ios_local_network_permission_request_started');
    try {
      final bool granted = await request;
      _iosLocalNetworkPermissionReady = granted;
      TiRtcLogging.i('flutter_example', 'ios_local_network_permission_request_finished granted=$granted');
      return granted;
    } finally {
      _iosLocalNetworkPermissionRequest = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyConfigurePageSystemOverlayStyle();
    }
  }

  void _applyConfigurePageSystemOverlayStyle() {
    SystemChrome.setSystemUIOverlayStyle(_configurePageOverlayStyle);
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<int> _shutdownRuntimeAfterDisposal() async {
    TiRtcLogging.i('flutter_example', 'runtime_shutdown_requested');
    int code = TiRtc.shutdown();
    for (int attempt = 0; attempt < _runtimeShutdownRetryCount && code == _runtimeObjectsLiveCode; attempt += 1) {
      await Future<void>.delayed(_runtimeShutdownRetryDelay);
      code = TiRtc.shutdown();
    }
    return code;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
