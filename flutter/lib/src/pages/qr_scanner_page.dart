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
