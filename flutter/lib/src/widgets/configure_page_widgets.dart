import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../demo_widget_keys.dart';
import 'token_acquisition_section.dart';

class ConfigurePageBackground extends StatelessWidget {
  const ConfigurePageBackground({
    super.key,
    required this.showBackdropOrbs,
    required this.onTap,
    required this.child,
  });

  final bool showBackdropOrbs;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: ExampleTheme.pageBackgroundDecoration,
            ),
          ),
          if (showBackdropOrbs)
            const Positioned(
              top: -120,
              right: -90,
              child: _DecorativeOrb(size: 260, color: ExampleTheme.overlayGlow),
            ),
          if (showBackdropOrbs)
            const Positioned(
              bottom: -110,
              left: -70,
              child: _DecorativeOrb(size: 220, color: ExampleTheme.overlayShadow),
            ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class ConfigureHeader extends StatelessWidget {
  const ConfigureHeader({
    super.key,
    required this.startingPlayer,
    required this.onOpenSettings,
  });

  final bool startingPlayer;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final TextStyle baseStyle = Theme.of(context).textTheme.headlineLarge ?? const TextStyle();
    final TextStyle titleStyle = baseStyle.copyWith(
      fontSize: 22,
      color: ExampleTheme.brandText,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: 1.0,
    );

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Ti RTC',
                style: titleStyle,
              ),
              const SizedBox(height: 5),
              const Text(
                'Based on Flutter',
                style: TextStyle(
                  color: ExampleTheme.textHint,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: startingPlayer ? null : onOpenSettings,
          style: TextButton.styleFrom(
            foregroundColor: startingPlayer ? ExampleTheme.textHint : ExampleTheme.primary,
            backgroundColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
              side: BorderSide(
                color: (startingPlayer ? ExampleTheme.textHint : ExampleTheme.primary).withAlpha(180),
              ),
            ),
          ),
          child: const Text(
            '偏好设置',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class ConfigureForm extends StatelessWidget {
  const ConfigureForm({
    super.key,
    required this.formKey,
    required this.submitted,
    required this.enabled,
    required this.startingPlayer,
    required this.appIdController,
    required this.endpointController,
    required this.remoteIdController,
    required this.audioStreamIdController,
    required this.videoStreamIdController,
    required this.tokenController,
    required this.tokenServerAddressController,
    required this.validateEndpoint,
    required this.validateStreamId,
    required this.validateOneTimeToken,
    required this.validateTokenServerAddress,
    required this.scanSupported,
    required this.onScanToken,
    required this.onStartPlaying,
  });

  final GlobalKey<FormState> formKey;
  final bool submitted;
  final bool enabled;
  final bool startingPlayer;
  final TextEditingController appIdController;
  final TextEditingController endpointController;
  final TextEditingController remoteIdController;
  final TextEditingController audioStreamIdController;
  final TextEditingController videoStreamIdController;
  final TextEditingController tokenController;
  final TextEditingController tokenServerAddressController;
  final FormFieldValidator<String> validateEndpoint;
  final FormFieldValidator<String> validateStreamId;
  final FormFieldValidator<String> validateOneTimeToken;
  final FormFieldValidator<String> validateTokenServerAddress;
  final bool scanSupported;
  final VoidCallback onScanToken;
  final VoidCallback onStartPlaying;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      autovalidateMode: submitted ? AutovalidateMode.always : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _EndpointAndAppIdFields(
            appIdController: appIdController,
            endpointController: endpointController,
            enabled: enabled,
            validateEndpoint: validateEndpoint,
          ),
          const SizedBox(height: 16),
          _RemoteIdField(controller: remoteIdController, enabled: enabled),
          const SizedBox(height: 16),
          _StreamIdRow(
            audioStreamIdController: audioStreamIdController,
            videoStreamIdController: videoStreamIdController,
            enabled: enabled,
            validator: validateStreamId,
          ),
          const SizedBox(height: 16),
          ConfigureTokenAcquisitionSection(
            tokenController: tokenController,
            tokenServerAddressController: tokenServerAddressController,
            enabled: enabled,
            scanSupported: scanSupported,
            validateOneTimeToken: validateOneTimeToken,
            validateTokenServerAddress: validateTokenServerAddress,
            onScanToken: onScanToken,
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: DemoWidgetKeys.startDownlinkButton,
            onPressed: enabled ? onStartPlaying : null,
            child: _EnterPlayerButtonLabel(startingPlayer: startingPlayer),
          ),
        ],
      ),
    );
  }
}

class ConfigureLogUploadAction extends StatelessWidget {
  const ConfigureLogUploadAction({
    super.key,
    required this.enabled,
    required this.uploading,
    required this.onUpload,
  });

  final bool enabled;
  final bool uploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        key: DemoWidgetKeys.configureLogUploadButton,
        onPressed: enabled ? onUpload : null,
        style: TextButton.styleFrom(
          foregroundColor: ExampleTheme.textHint,
          disabledForegroundColor: ExampleTheme.textHint.withAlpha(145),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        child: uploading
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(ExampleTheme.textHint),
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '正在上传…',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                  ),
                ],
              )
            : const Text(
                '上传日志',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  decoration: TextDecoration.underline,
                  decorationThickness: 0.8,
                ),
              ),
      ),
    );
  }
}

class _EndpointAndAppIdFields extends StatelessWidget {
  const _EndpointAndAppIdFields({
    required this.appIdController,
    required this.endpointController,
    required this.enabled,
    required this.validateEndpoint,
  });

  final TextEditingController appIdController;
  final TextEditingController endpointController;
  final bool enabled;
  final FormFieldValidator<String> validateEndpoint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _EndpointField(
          controller: endpointController,
          enabled: enabled,
          validator: validateEndpoint,
        ),
        const SizedBox(height: 16),
        _AppIdField(controller: appIdController, enabled: enabled),
      ],
    );
  }
}

class _EndpointField extends StatelessWidget {
  const _EndpointField({
    required this.controller,
    required this.enabled,
    required this.validator,
  });

  final TextEditingController controller;
  final bool enabled;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: DemoWidgetKeys.endpointField,
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 13),
      decoration: const InputDecoration(
        labelText: 'endpoint',
        hintText: '接入的云端环境，留空则使用默认环境。',
      ),
      validator: validator,
    );
  }
}

class _AppIdField extends StatelessWidget {
  const _AppIdField({
    required this.controller,
    required this.enabled,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: DemoWidgetKeys.appIdField,
      controller: controller,
      enabled: enabled,
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 13),
      decoration: const InputDecoration(
        labelText: 'app_id',
        hintText: 'TiRTC 应用标识，进入播放页前必须提供。',
      ),
      validator: (String? value) {
        if ((value ?? '').trim().isEmpty) {
          return 'app_id 为必填项。';
        }
        return null;
      },
    );
  }
}

class _RemoteIdField extends StatelessWidget {
  const _RemoteIdField({
    required this.controller,
    required this.enabled,
  });

  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: DemoWidgetKeys.remoteIdField,
      controller: controller,
      enabled: enabled,
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 13),
      decoration: const InputDecoration(
        labelText: 'remote_id',
        hintText: '待连接的设备 ID',
      ),
      validator: (String? value) {
        if ((value ?? '').trim().isEmpty) {
          return 'remote_id 为必填项。';
        }
        return null;
      },
    );
  }
}

class _StreamIdRow extends StatelessWidget {
  const _StreamIdRow({
    required this.audioStreamIdController,
    required this.videoStreamIdController,
    required this.enabled,
    required this.validator,
  });

  final TextEditingController audioStreamIdController;
  final TextEditingController videoStreamIdController;
  final bool enabled;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextFormField(
            key: DemoWidgetKeys.audioStreamIdField,
            controller: audioStreamIdController,
            enabled: enabled,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'audio_stream_id',
              hintText: '音频流 ID，默认 10',
            ),
            validator: validator,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextFormField(
            key: DemoWidgetKeys.videoStreamIdField,
            controller: videoStreamIdController,
            enabled: enabled,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'video_stream_id',
              hintText: '视频流 ID，默认 11',
            ),
            validator: validator,
          ),
        ),
      ],
    );
  }
}

class _EnterPlayerButtonLabel extends StatelessWidget {
  const _EnterPlayerButtonLabel({required this.startingPlayer});

  final bool startingPlayer;

  @override
  Widget build(BuildContext context) {
    if (!startingPlayer) {
      return const Text('开始连接、拉流播放');
    }

    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(ExampleTheme.foreground),
          ),
        ),
        SizedBox(width: 10),
        Text('初始化中'),
      ],
    );
  }
}

class _DecorativeOrb extends StatelessWidget {
  const _DecorativeOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withAlpha(0)],
          ),
        ),
      ),
    );
  }
}
