import {useCallback, useEffect, useRef, useState} from 'react';
import {Alert} from 'react-native';
import type {TiRtcLoggingUploadResult} from 'tirtc-react-native';

type LogUploadRunner = () => Promise<TiRtcLoggingUploadResult>;

export function useExampleLogUpload(upload: LogUploadRunner): {
  uploadingLogs: boolean;
  uploadLogs: () => Promise<boolean>;
} {
  const uploadRef = useRef(upload);
  const runningRef = useRef(false);
  const [uploadingLogs, setUploadingLogs] = useState(false);

  useEffect(() => {
    uploadRef.current = upload;
  }, [upload]);

  const pendingRef = useRef<Promise<boolean> | null>(null);
  const uploadLogs = useCallback((): Promise<boolean> => {
    if (runningRef.current) {
      return pendingRef.current ?? Promise.resolve(false);
    }
    runningRef.current = true;
    setUploadingLogs(true);
    const pending = Promise.resolve()
      .then(() => uploadRef.current())
      .then((result) => {
        showLogUploadResult(result);
        return result.code === 0;
      })
      .catch(() => {
        showLogUploadFailure();
        return false;
      })
      .finally(() => {
        runningRef.current = false;
        pendingRef.current = null;
        setUploadingLogs(false);
      });
    pendingRef.current = pending;
    return pending;
  }, []);

  return {uploadingLogs, uploadLogs};
}

function showLogUploadResult(upload: TiRtcLoggingUploadResult) {
  if (upload.code === 0) {
    const logId = upload.logId?.trim() ?? '';
    Alert.alert(
      '日志上传成功',
      logId.length > 0 ? `日志 ID: ${logId}\n将此编号提供给开发人员排查` : '日志上传成功。',
      [{text: '确定'}],
    );
    return;
  }
  showLogUploadFailure();
}

function showLogUploadFailure() {
  Alert.alert('日志上传失败', '请重试。', [{text: '确定'}]);
}
