import 'package:flutter/material.dart';

import '../demo_configuration.dart';
import '../widgets/qr_scanner_page_widgets.dart';

class DemoQrScannerPage extends StatelessWidget {
  const DemoQrScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DemoQrScannerPayloadPage<DemoScanPayload>(
      leadText: '对准 TiRTC 或 DevTools 生成的 JSON 二维码，或 v1.xxx 开头的纯 Token 二维码。',
      guideText: 'JSON 会填充 app_id、remote_id、token 和可选 endpoint；纯 Token 只会填充 Token，其他字段继续使用首页输入。',
      samplePayloadText: '{\n'
          '  "app_id": "flutter-example-app",\n'
          '  "remote_id": "TESTTIRTC01",\n'
          '  "token": "v1.eyJzxxx",\n'
          '  "endpoint": "https://xxx.com"\n'
          '}\n\n'
          '// 或只提供一次性连接 Token\n'
          'v1.eyJzxxx',
      parsePayload: DemoScanPayload.tryParse,
    );
  }
}

class DemoStoreQrScannerPage extends StatelessWidget {
  const DemoStoreQrScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DemoQrScannerPayloadPage<DemoStoreScanPayload>(
      leadText: '对准 DevTools 签发的云录像客户端 Token 二维码，或整张码只有一段 Token。',
      guideText: 'JSON 会填充 app_id、token 和可选的云录像 endpoint；纯 Token 只会填充 Token。不要使用 RTC 连接码。',
      samplePayloadText: '{\n'
          '  "app_id": "flutter-example-app",\n'
          '  "token": "eyJhbGciOiJxxx",\n'
          '  "endpoint": "https://store.xxx.com"\n'
          '}\n\n'
          '// 或只提供云录像客户端 Token\n'
          'eyJhbGciOiJxxx',
      parsePayload: DemoStoreScanPayload.tryParse,
      invalidPayloadText: '二维码内容无效，请使用包含 app_id、token 的 JSON，或云录像客户端 Token。不要使用 RTC 连接码。',
    );
  }
}
