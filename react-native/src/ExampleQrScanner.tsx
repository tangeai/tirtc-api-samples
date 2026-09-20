import React, {useRef, useState} from 'react';
import {Pressable, ScrollView, Text, useWindowDimensions, View} from 'react-native';
import {Camera, useCameraDevice, useCodeScanner} from 'react-native-vision-camera';
import {BackHeader, ConfigureShell, ExampleScreenRoot, InputField, PrimaryButton, StatusText, uiStyles} from './ExampleUi';
import type {ExampleConfig, ExampleScanPayload} from './ExampleTypes';
import {parseScanPayload, tiCloudStorageParseScanPayload} from './ExampleTypes';

export function QrScannerScreen({
  product,
  onBack,
  onScan,
}: {
  product: 'rtc' | 'tiCloudStorage';
  onBack: () => void;
  onScan: (payload: ExampleScanPayload) => void;
}) {
  const window = useWindowDimensions();
  const wide = window.width >= 600;
  const accessibilityPrefix = product === 'tiCloudStorage' ? 'Ti Cloud Storage' : 'TiRTC';
  const device = useCameraDevice('back');
  const processing = useRef(false);
  const [permission, setPermission] = useState(Camera.getCameraPermissionStatus());
  const [status, setStatus] = useState(
    product === 'tiCloudStorage' ? '对准 APP Access Token 二维码' : '对准 JSON 二维码，或 v1.xxx 纯 Token 二维码',
  );
  const [manualValue, setManualValue] = useState('');
  const invalidPayloadText = product === 'tiCloudStorage'
    ? '二维码内容无效，请使用云录像 APP Token 或包含 app_id、token 和可选 endpoint 的 JSON'
    : '二维码内容无效，请使用包含 app_id、remote_id、token 的 JSON，或 v1.xxx 纯 Token';
  const parsePayload = product === 'tiCloudStorage' ? tiCloudStorageParseScanPayload : parseScanPayload;
  const cameraStateLabel = permission === 'granted'
    ? '相机已就绪'
    : permission === 'denied'
      ? '相机权限未授予'
      : '相机未启用';

  const codeScanner = useCodeScanner({
    codeTypes: ['qr'],
    onCodeScanned: (codes) => {
      if (processing.current) {
        return;
      }
      for (const code of codes) {
        const value = code.value?.trim();
        if (!value) {
          continue;
        }
        const payload = parsePayload(value);
        if (payload === null) {
          processing.current = true;
          setStatus(invalidPayloadText);
          setTimeout(() => {
            processing.current = false;
          }, 900);
          return;
        }
        processing.current = true;
        onScan(payload);
        return;
      }
    },
  });
  const applyManualValue = () => {
    const payload = parsePayload(manualValue);
    if (payload === null) {
      setStatus(invalidPayloadText);
      return;
    }
    onScan(payload);
  };
  const requestPermission = () => {
    setStatus('正在请求相机权限…');
    Camera.requestCameraPermission()
      .then((next) => {
        setPermission(next);
        setStatus(next === 'granted' ? '相机已就绪' : '相机权限未授予，可继续手动粘贴');
      })
      .catch((error: unknown) => setStatus(`相机权限请求失败 ${String(error)}，可继续手动粘贴`));
  };
  const [helpVisible, setHelpVisible] = useState(false);

  return (
    <ExampleScreenRoot>
      <ScrollView keyboardShouldPersistTaps="handled">
      <ConfigureShell>
        <BackHeader
          title="扫描二维码"
          accessibilityLabel={`${accessibilityPrefix} QR Scanner Back`}
          onBack={onBack}
        />
        <Text style={uiStyles.scannerLead}>
          {product === 'tiCloudStorage'
            ? '扫描或粘贴 APP Access Token。扫码只更新云录像 Token，其他配置保持不变。'
            : '支持包含 app_id、remote_id、token 和可选 endpoint 的 JSON，或 v1.xxx 开头的纯 Token。纯 Token 只会填充 Token。'}
        </Text>
        <View testID={wide ? 'qr-layout-wide' : 'qr-layout-compact'} style={[uiStyles.scannerLayout, wide ? uiStyles.scannerLayoutWide : null]}>
        <View style={uiStyles.scannerColumn}>
        <View accessibilityLabel={`${accessibilityPrefix} QR Camera Viewfinder: ${cameraStateLabel}`} accessible style={uiStyles.scannerFrame}>
          {permission === 'granted' && device ? (
            <Camera
              style={uiStyles.scannerCamera}
              device={device}
              isActive
              codeScanner={codeScanner}
            />
          ) : (
            <View style={uiStyles.scannerPlaceholder}>
              <Text style={uiStyles.scannerPlaceholderText}>
                {permission === 'denied' ? '相机权限未授予' : '相机未启用'}
              </Text>
            </View>
          )}
          <View style={[uiStyles.scannerBadge, uiStyles.noPointerEvents]}>
            <Text style={uiStyles.scannerBadgeText}>对准二维码</Text>
          </View>
        </View>
        {permission !== 'granted' ? (
          <Pressable accessibilityRole="button" accessibilityLabel={`${accessibilityPrefix} QR Enable Camera`} onPress={requestPermission} style={uiStyles.scannerPermissionButton}>
            <Text style={uiStyles.scannerPermissionText}>{permission === 'denied' ? '重新请求相机权限' : '启用相机'}</Text>
          </Pressable>
        ) : null}
        </View>
        <View style={uiStyles.scannerColumn}>
        <InputField
          label="二维码内容"
          hint={product === 'tiCloudStorage' ? '粘贴 APP Token 或配置 JSON' : '粘贴 JSON 或 v1.xxx Token'}
          value={manualValue}
          accessibilityLabel={`${accessibilityPrefix} QR Manual Content`}
          autoCapitalize="none"
          autoCorrect={false}
          multiline
          onChangeText={(value) => { setManualValue(value); if (status === invalidPayloadText) setStatus('已修改内容，请重新应用'); }}
        />
        <PrimaryButton
          label="应用二维码内容"
          accessibilityLabel={`${accessibilityPrefix} QR Apply Content`}
          onPress={applyManualValue}
        />
        {product === 'rtc' ? <Pressable accessibilityRole="button" accessibilityLabel="TiRTC QR Format Help" accessibilityState={{expanded: helpVisible}} onPress={() => setHelpVisible((value) => !value)} style={uiStyles.scannerHelpButton}>
          <Text style={uiStyles.scannerPermissionText}>{helpVisible ? '收起格式帮助' : '查看格式帮助'}</Text>
        </Pressable> : null}
        {product === 'rtc' && helpVisible ? <View style={uiStyles.diagnosticsPanel}>
          <Text style={uiStyles.diagnosticsTitle}>二维码内容格式</Text>
          <Text style={uiStyles.diagnosticsLine}>
            {`JSON:\n{\n  "app_id": "rn-example-app",\n  "remote_id": "TESTTIRTC01",\n  "token": "v1.eyJzxxx",\n  "endpoint": "https://xxx.com"\n}\n\n纯 Token:\nv1.eyJzxxx`}
          </Text>
        </View> : null}
        <View accessibilityLiveRegion="polite" accessible accessibilityLabel={`${accessibilityPrefix} QR Status: ${status}`}><StatusText>{status}</StatusText></View>
        </View>
        </View>
      </ConfigureShell>
      </ScrollView>
    </ExampleScreenRoot>
  );
}

export function tiCloudStorageApplyScanPayloadToConfig(
  current: ExampleConfig,
  payload: ExampleScanPayload,
): ExampleConfig {
  return {
    ...current,
    appId: payload.appId ?? current.appId,
    endpoint: payload.endpoint ?? current.endpoint,
    tiCloudStorageToken: payload.token,
  };
}

export function applyScanPayloadToConfig(
  current: ExampleConfig,
  payload: ExampleScanPayload,
): ExampleConfig {
  return {
    ...current,
    appId: payload.appId ?? current.appId,
    remoteId: payload.remoteId ?? current.remoteId,
    endpoint: payload.endpoint ?? current.endpoint,
    token: payload.token,
  };
}
