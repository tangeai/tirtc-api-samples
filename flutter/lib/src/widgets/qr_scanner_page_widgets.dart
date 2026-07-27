import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_theme.dart';

typedef DemoQrPayloadParser<T extends Object> = T? Function(String rawValue);

class DemoQrScannerPayloadPage<T extends Object> extends StatefulWidget {
  const DemoQrScannerPayloadPage({
    super.key,
    this.title = '扫描二维码',
    required this.leadText,
    required this.guideText,
    required this.samplePayloadText,
    required this.parsePayload,
  });

  final String title;
  final String leadText;
  final String guideText;
  final String samplePayloadText;
  final DemoQrPayloadParser<T> parsePayload;

  @override
  State<DemoQrScannerPayloadPage<T>> createState() => _DemoQrScannerPayloadPageState<T>();
}

class _DemoQrScannerPayloadPageState<T extends Object> extends State<DemoQrScannerPayloadPage<T>> {
  static const SystemUiOverlayStyle _scannerPageOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  final MobileScannerController _scannerController = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _scannerPageOverlayStyle,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: ExampleTheme.pageBackgroundDecoration,
              ),
            ),
            const Positioned(
              top: -120,
              right: -90,
              child: _DecorativeOrb(size: 260, color: ExampleTheme.overlayGlow),
            ),
            const Positioned(
              bottom: -110,
              left: -70,
              child: _DecorativeOrb(size: 220, color: ExampleTheme.overlayShadow),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _buildHeader(context),
                            const SizedBox(height: 18),
                            _buildPageLead(context),
                            const SizedBox(height: 20),
                            _buildScannerPanel(),
                            const SizedBox(height: 18),
                            _buildPayloadGuideCard(context),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageLead(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Text(
      widget.leadText,
      style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
        color: ExampleTheme.textSecondary,
        height: 1.6,
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: ExampleTheme.surface.withAlpha(232),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ExampleTheme.primary.withAlpha(31)),
          ),
          child: IconButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.arrow_back_rounded),
            color: ExampleTheme.primary,
            tooltip: '返回',
          ),
        ),
        const SizedBox(width: 14),
        Text(
          widget.title,
          style: (textTheme.headlineSmall ?? const TextStyle()).copyWith(
            color: ExampleTheme.brandText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildScannerPanel() {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: const BoxDecoration(color: ExampleTheme.videoBackground),
              child: MobileScanner(
                controller: _scannerController,
                fit: BoxFit.cover,
                onDetect: (BarcodeCapture capture) async {
                  await _handleCapture(capture);
                },
              ),
            ),
            const IgnorePointer(child: _ScannerFrameOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _buildPayloadGuideCard(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: ExampleTheme.surfaceDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ExampleTheme.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.qr_code_2_rounded,
                  color: ExampleTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '二维码内容格式',
                  style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
                    color: ExampleTheme.brandText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            widget.guideText,
            style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
              color: ExampleTheme.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ExampleTheme.inputSurface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: ExampleTheme.inputBorder),
            ),
            child: Text(
              widget.samplePayloadText,
              style: const TextStyle(
                color: ExampleTheme.textPrimary,
                fontSize: 13,
                height: 1.6,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    if (_processing) {
      return;
    }

    for (final Barcode barcode in capture.barcodes) {
      final String rawValue = (barcode.rawValue ?? '').trim();
      if (rawValue.isEmpty) {
        continue;
      }

      _processing = true;
      final T? payload = widget.parsePayload(rawValue);
      if (!mounted) {
        return;
      }
      if (payload != null) {
        Navigator.of(context).pop(payload);
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('二维码内容无效，请使用包含 app_id、remote_id、token 的 JSON，或 v1.xxx 纯 Token。'),
          ),
        );
      await Future<void>.delayed(const Duration(milliseconds: 900));
      _processing = false;
      return;
    }
  }
}

class _ScannerFrameOverlay extends StatelessWidget {
  const _ScannerFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.black.withAlpha(34),
            Colors.transparent,
            Colors.black.withAlpha(58),
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(112),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            '对准二维码',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
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
