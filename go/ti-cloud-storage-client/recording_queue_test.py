#!/usr/bin/env python3
"""Run the Example against its actual SDK callbackQueue and frozen Native closure.

The overlay changes only queue.go's package name to place the unchanged queue
implementation beside the Example's private waiting code; no SDK hook is added.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'go/tool'))
from go_environment import prepare_environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tree', type=Path, required=True)
    parser.add_argument('--artifact-root', type=Path, required=True)
    parser.add_argument('--old-wait', action='store_true')
    args = parser.parse_args()
    root = args.artifact_root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    tree = args.tree.resolve()
    environment, report = prepare_environment('verify', 'darwin-arm64', install=False, require_online=False)
    (root / 'environment.json').write_text(json.dumps(report, indent=2) + '\n')
    if report['status'] != 'ready':
        raise RuntimeError('selected Go environment is not ready')
    queue = ROOT / 'go/storage/queue.go'
    (root / 'queue_test.go').write_text(queue.read_text().replace('package storage', 'package main', 1))
    (root / 'recording_queue_test.go').write_text(TEST)
    overlay = {str(tree / 'example/storage/main.go'): str(ROOT / 'go/example/storage/main.go'),
               str(tree / 'example/storage/main_test.go'): str(ROOT / 'go/example/storage/main_test.go'),
               str(tree / 'example/storage/actual_queue_test.go'): str(root / 'queue_test.go'),
               str(tree / 'example/storage/recording_queue_test.go'): str(root / 'recording_queue_test.go')}
    (root / 'overlay.json').write_text(json.dumps({'Replace': overlay}, indent=2) + '\n')
    if args.old_wait:
        environment['TIRTC_TEST_RECORDING_OLD_WAIT'] = '1'
    with (root / 'go-test.log').open('w') as log:
        result = subprocess.run(['go', 'test', '-race', '-count=1', '-overlay', str(root / 'overlay.json'),
                                 '-v', './example/storage'], cwd=tree, env=environment,
                                stdout=log, stderr=subprocess.STDOUT, timeout=120)
    (root / 'proof.json').write_text(json.dumps({'returncode': result.returncode, 'old_wait': args.old_wait,
        'queue_sha256': hashlib.sha256(queue.read_bytes()).hexdigest(),
        'main_sha256': hashlib.sha256((ROOT / 'go/example/storage/main.go').read_bytes()).hexdigest(),
        'tree': str(tree)}, indent=2) + '\n')
    return result.returncode


TEST = r'''
package main
import("context";"errors";"os";"testing";"time")
func TestRecordingRejectsOldMailboxDelivery(t *testing.T) {
  old:=newFrameSignals();queue:=newCallbackQueue();release:=make(chan struct{});entered:=make(chan struct{})
  queue.post(func(){close(entered);<-release});<-entered
  queue.post(func(){old.video.notify();old.encodedVideo.notify();old.encodedVideoKeyFrame.notify()})
  for i:=0;i<60;i++{queue.post(func(){time.Sleep(time.Millisecond);old.encodedVideo.notify()})}
  defer queue.close()
  ctx,cancel:=context.WithTimeout(context.Background(),30*time.Millisecond);defer cancel()
  baseline:=old.snapshot();close(release)
  var err error
  if os.Getenv("TIRTC_TEST_RECORDING_OLD_WAIT")=="1" {
    err=waitVideoRecordingFramesAfter(ctx,old,baseline,make(chan error))
  } else {
    err=observeRecordingVideo(ctx,old,make(chan error),func(*frameSignals)error{return nil})
  }
  if !errors.Is(err,context.DeadlineExceeded){t.Fatalf("Start-before-admission recording became ready from old mailbox: %v",err)}
}
'''

if __name__ == '__main__':
    sys.exit(main())
