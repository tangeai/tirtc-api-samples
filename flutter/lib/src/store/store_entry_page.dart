import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../demo_configuration.dart';
import '../demo_widget_keys.dart';
import '../pages/qr_scanner_page.dart';
import '../widgets/token_acquisition_section.dart';
import 'store_configuration_store.dart';
import 'store_recordings_page.dart';

final class DemoStoreEntryPage extends StatefulWidget {
  const DemoStoreEntryPage({
    super.key,
    this.enabled = true,
    this.configurationStore = const DemoStoreConfigurationStore(),
  });

  final bool enabled;
  final DemoStoreConfigurationStore configurationStore;

  @override
  State<DemoStoreEntryPage> createState() => _DemoStoreEntryPageState();
}

final class _DemoStoreEntryPageState extends State<DemoStoreEntryPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _appIdController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _audioChannelController = TextEditingController();
  final TextEditingController _videoChannelController = TextEditingController();
  bool _submitted = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPersistedConfiguration();
  }

  @override
  void dispose() {
    _appIdController.dispose();
    _endpointController.dispose();
    _tokenController.dispose();
    _audioChannelController.dispose();
    _videoChannelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      autovalidateMode: _submitted ? AutovalidateMode.always : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            key: DemoWidgetKeys.storeAppIdField,
            controller: _appIdController,
            enabled: widget.enabled && !_loading,
            textInputAction: TextInputAction.next,
            style: ExampleTheme.inputTextStyle,
            decoration: const InputDecoration(
              labelText: 'app_id',
              hintText: 'TiStore 应用标识，进入播放页前必须提供。',
            ),
            validator: _validateAppId,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: DemoWidgetKeys.storeEndpointField,
            controller: _endpointController,
            enabled: widget.enabled && !_loading,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            style: ExampleTheme.inputTextStyle,
            decoration: const InputDecoration(
              labelText: 'endpoint',
              hintText: '接入的云端环境，留空则使用默认环境。',
            ),
            validator: _validateEndpoint,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  key: DemoWidgetKeys.storeTokenField,
                  controller: _tokenController,
                  enabled: widget.enabled && !_loading,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: ExampleTheme.inputTextStyle,
                  decoration: const InputDecoration(
                    labelText: 'token',
                    hintText: '粘贴云录像客户端 Token，或点右侧扫码。',
                  ),
                  validator: _validateToken,
                ),
              ),
              const SizedBox(width: 10),
              ConfigureScanButton(
                buttonKey: DemoWidgetKeys.storeScanButton,
                enabled: widget.enabled && !_loading && _scanSupported,
                onPressed: _scanStoreToken,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  key: DemoWidgetKeys.storeAudioChannelField,
                  controller: _audioChannelController,
                  enabled: widget.enabled && !_loading,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  style: ExampleTheme.inputTextStyle,
                  decoration: const InputDecoration(
                    labelText: 'audio_channel_id',
                    hintText: '音频 Channel，0..255',
                  ),
                  validator: _validateChannelId,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  key: DemoWidgetKeys.storeVideoChannelField,
                  controller: _videoChannelController,
                  enabled: widget.enabled && !_loading,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  style: ExampleTheme.inputTextStyle,
                  decoration: const InputDecoration(
                    labelText: 'video_channel_id',
                    hintText: '视频 Channel，0..255',
                  ),
                  validator: _validateChannelId,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: DemoWidgetKeys.storeEnterButton,
            onPressed: widget.enabled && !_loading ? _enterStore : null,
            child: const Text('播放云录像'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPersistedConfiguration() async {
    final DemoStoreConfigurationSnapshot snapshot = await widget.configurationStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _appIdController.text = snapshot.appId;
      _endpointController.text = snapshot.endpoint;
      _audioChannelController.text = snapshot.audioChannelId;
      _videoChannelController.text = snapshot.videoChannelId;
      _loading = false;
    });
  }

  Future<void> _enterStore() async {
    setState(() {
      _submitted = true;
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await widget.configurationStore.save(
      DemoStoreConfigurationSnapshot(
        appId: _appIdController.text.trim(),
        endpoint: _endpointController.text.trim(),
        audioChannelId: _audioChannelController.text.trim(),
        videoChannelId: _videoChannelController.text.trim(),
      ),
    );
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DemoStoreRecordingsPage(
          appId: _appIdController.text.trim(),
          endpoint: _endpointController.text.trim(),
          token: _tokenController.text,
          audioChannelId: int.parse(_audioChannelController.text),
          videoChannelId: int.parse(_videoChannelController.text),
        ),
      ),
    );
  }

  bool get _scanSupported => Platform.isAndroid || Platform.isIOS;

  Future<void> _scanStoreToken() async {
    if (!_scanSupported || !widget.enabled || _loading) {
      return;
    }
    final DemoStoreScanPayload? payload = await Navigator.of(context).push<DemoStoreScanPayload>(
      MaterialPageRoute<DemoStoreScanPayload>(
        builder: (BuildContext context) => const DemoStoreQrScannerPage(),
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
      if (payload.endpoint != null) {
        _endpointController.text = payload.endpoint!;
      }
    });
  }

  String? _validateAppId(String? value) {
    return (value ?? '').trim().isEmpty ? 'app_id 为必填项。' : null;
  }

  String? _validateEndpoint(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !uri.isAbsolute) {
      return '请输入不含用户信息和片段的绝对 HTTPS URL。';
    }
    return null;
  }

  String? _validateToken(String? value) {
    final String token = value ?? '';
    if (token.isEmpty) {
      return '请填写 token。';
    }
    if (token != token.trim()) {
      return 'Token 首尾不能包含空白。';
    }
    return null;
  }

  String? _validateChannelId(String? value) {
    final String text = (value ?? '').trim();
    final int? channelId = int.tryParse(text);
    if (text.isEmpty || !RegExp(r'^\d+$').hasMatch(text) || channelId == null || channelId < 0 || channelId > 255) {
      return '请输入 0..255。';
    }
    return null;
  }
}
