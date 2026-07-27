import {useCallback, useEffect, useRef, useState} from 'react';
import {Alert} from 'react-native';
import type {TiRtcLoggingUploadResult} from 'tirtc-react-native';

type LogUploadRunner = () => Promise<TiRtcLoggingUploadResult>;

export function useExampleLogUpload(upload: LogUploadRunner): {
  uploadingLogs: boolean;
  uploadLogs: () => void;
} {
  const uploadRef = useRef(upload);
  const runningRef = useRef(false);
  const [uploadingLogs, setUploadingLogs] = useState(false);

  useEffect(() => {
    uploadRef.current = upload;
  }, [upload]);

  const uploadLogs = useCallback(() => {
    if (runningRef.current) {
      return;
    }
    runningRef.current = true;
    setUploadingLogs(true);
    Promise.resolve()
      .then(() => uploadRef.current())
      .then(showLogUploadResult)
      .catch(showLogUploadFailure)
      .finally(() => {
        runningRef.current = false;
        setUploadingLogs(false);
      });
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
