import React, {useCallback, useEffect, useMemo, useState} from 'react';
import {BackHandler, Platform} from 'react-native';
import {ClientSession} from './ExampleClientSession';
import {ConfigureScreen} from './ExamplePages';
import {PlayerScreen} from './ExampleStagePages';
import {
  QrScannerScreen,
  applyScanPayloadToConfig,
  applyScanPayloadToStoreConfig,
} from './ExampleQrScanner';
import {SettingsScreen} from './ExampleSettings';
import {StoreScreen} from './ExampleStorePage';
import {loadStoredConfig, saveStoredConfig} from './ExampleStorage';
import {resolveStoreToken, resolveToken} from './ExampleToken';
import {ExampleConfig, Page, initialConfig, parseStreamIds} from './ExampleTypes';

export default function App(): React.ReactElement {
  const [page, setPage] = useState<Page>('configure');
  const [configureProduct, setConfigureProduct] = useState<'rtc' | 'store'>('rtc');
  const [config, setConfig] = useState<ExampleConfig>(initialConfig);
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);
  const [storageReady, setStorageReady] = useState(false);

  const clientSession = useMemo(() => new ClientSession(setStatus), []);

  useEffect(() => {
    loadStoredConfig()
      .then((stored) => {
        setConfig((current) => ({...current, ...stored}));
      })
      .finally(() => setStorageReady(true));
  }, []);

  useEffect(() => {
    if (!storageReady) {
      return;
    }
    saveStoredConfig(config).catch((error: unknown) => {
      setStatus(`配置保存失败 ${String(error)}`);
    });
  }, [config, storageReady]);

  const updateConfig = <K extends keyof ExampleConfig>(key: K, value: ExampleConfig[K]) => {
    setConfig((current) => normalizeConfigChange({...current, [key]: value}));
  };

  const openPlayer = async () => {
    if (busy) {
      return;
    }
    setBusy(true);
    setStatus('Token 校验中');
    let token: string;
    try {
      token = await resolveToken(config);
    } catch (error) {
      setStatus(`Token 校验失败 ${String(error)}`);
      setBusy(false);
      return;
    }
    const nextConfig = {...config, token};
    setConfig(nextConfig);
    setPage('player');
    setStatus('连接中');
    try {
      await clientSession.start(nextConfig, parseStreamIds(nextConfig));
    } catch (error) {
      setStatus(`播放启动失败 ${String(error)}`);
    } finally {
      setBusy(false);
    }
  };

  const openStore = async () => {
    if (busy) return;
    setBusy(true);
    setStatus('Store Token 校验中');
    try {
      const token = await resolveStoreToken(config.storeToken);
      setConfig((current) => ({...current, storeToken: token}));
      setPage('store');
      setStatus('');
    } catch (error) {
      setStatus(`Store Token 校验失败 ${String(error)}`);
    } finally {
      setBusy(false);
    }
  };

  const returnToConfigure = useCallback(async () => {
    await clientSession.stop();
    setStatus('');
    setPage('configure');
  }, [clientSession]);

  useEffect(() => {
    if (Platform.OS !== 'android') {
      return;
    }
    const subscription = BackHandler.addEventListener('hardwareBackPress', () => {
      if (page === 'configure') {
        return false;
      }
      if (page === 'player') {
        void returnToConfigure();
        return true;
      }
      setStatus('');
      setPage('configure');
      return true;
    });
    return () => subscription.remove();
  }, [page, returnToConfigure]);

  if (page === 'player') {
    return <PlayerScreen config={config} session={clientSession} status={status} onBack={returnToConfigure} />;
  }

  if (page === 'settings') {
    return <SettingsScreen config={config} onChange={updateConfig} onBack={() => setPage('configure')} />;
  }

  if (page === 'store') {
    return (
      <StoreScreen
        config={config}
        onBack={() => {
          setConfigureProduct('store');
          setPage('configure');
        }}
      />
    );
  }

  if (page === 'qrScanner') {
    const scanProduct = configureProduct;
    return (
      <QrScannerScreen
        product={scanProduct}
        onBack={() => setPage('configure')}
        onScan={(payload) => {
          setConfig((current) => scanProduct === 'store'
            ? applyScanPayloadToStoreConfig(current, payload)
            : applyScanPayloadToConfig(current, payload));
          setStatus('二维码已填充');
          setPage('configure');
        }}
      />
    );
  }

  return (
    <ConfigureScreen
      config={config}
      product={configureProduct}
      busy={busy}
      status={status}
      onChange={updateConfig}
      onSelectProduct={setConfigureProduct}
      onStart={openPlayer}
      onOpenStore={openStore}
      onOpenSettings={() => setPage('settings')}
      onScanToken={() => setPage('qrScanner')}
    />
  );
}

function normalizeConfigChange(config: ExampleConfig): ExampleConfig {
  const next = {...config};
  if (next.localAudioCodec === 'amr') {
    next.localAudioSampleRateHz = '8000';
  }
  return next;
}
