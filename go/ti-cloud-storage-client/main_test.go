package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	"github.com/tangeai/tirtc-client-go/v2/storage"
)

func TestNewestFirstRecordingRanges(t *testing.T) {
	input := []storage.RecordingRange{
		{StartTime: time.UnixMilli(100), EndTime: time.UnixMilli(200)},
		{StartTime: time.UnixMilli(300), EndTime: time.UnixMilli(350)},
		{StartTime: time.UnixMilli(300), EndTime: time.UnixMilli(400)},
	}

	got := newestFirstRecordingRanges(input)
	if got[0].EndTime.UnixMilli() != 400 || got[1].EndTime.UnixMilli() != 350 ||
		got[2].StartTime.UnixMilli() != 100 {
		t.Fatalf("unexpected newest-first order: %#v", got)
	}
	if input[0].StartTime.UnixMilli() != 100 {
		t.Fatal("sorting must not mutate the SDK result slice")
	}
}

func TestTakeSnapshotWhenReadyRetriesAfterNextDecodedVideoFrame(t *testing.T) {
	videoFrames := newFrameSignal()
	failures := make(chan error)
	want := storage.SnapshotFile{Path: "/tmp/snapshot.jpg"}
	calls := 0

	got, err := takeSnapshotWhenReady(context.Background(), func() (storage.SnapshotFile, error) {
		calls++
		if calls == 1 {
			videoFrames.notify()
			return storage.SnapshotFile{}, storage.ErrNoFrame
		}
		return want, nil
	}, videoFrames, failures)
	if err != nil {
		t.Fatalf("take snapshot: %v", err)
	}
	if calls != 2 || got != want {
		t.Fatalf("got (%#v, %d calls), want (%#v, 2 calls)", got, calls, want)
	}
}

func TestTakeSnapshotWhenReadyDoesNotRetryOtherErrors(t *testing.T) {
	wantErr := errors.New("snapshot failed")
	calls := 0
	_, err := takeSnapshotWhenReady(context.Background(), func() (storage.SnapshotFile, error) {
		calls++
		return storage.SnapshotFile{}, wantErr
	}, newFrameSignal(), make(chan error))
	if !errors.Is(err, wantErr) || calls != 1 {
		t.Fatalf("got (%v, %d calls), want (%v, 1 call)", err, calls, wantErr)
	}
}

func TestWaitFramesAfterRejectsBufferedPreRecordingSignals(t *testing.T) {
	frames := newFrameSignals()
	for _, signal := range []*frameSignal{frames.audio, frames.video, frames.encodedAudio, frames.encodedVideo} {
		signal.notify()
	}
	baseline := frames.snapshot()
	frames.audio.notify()
	frames.video.notify()
	frames.encodedAudio.notify()

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if err := waitFramesAfter(ctx, frames, baseline, make(chan error)); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("waitFramesAfter error = %v, want deadline while encoded video has no new frame", err)
	}

	frames.encodedVideo.notify()
	ctx, cancel = context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := waitFramesAfter(ctx, frames, baseline, make(chan error)); err != nil {
		t.Fatalf("waitFramesAfter with new frames: %v", err)
	}
}

func TestWaitRecordingFramesAfterRequiresPostStartKeyFrameAndFollowingVideo(t *testing.T) {
	frames := newFrameSignals()
	for _, signal := range []*frameSignal{
		frames.audio,
		frames.video,
		frames.encodedAudio,
		frames.encodedVideo,
		frames.encodedVideoKeyFrame,
	} {
		signal.notify()
	}
	baseline := frames.snapshot()
	frames.audio.notify()
	frames.video.notify()
	frames.encodedAudio.notify()
	frames.encodedVideo.notify()

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if err := waitRecordingFramesAfter(ctx, frames, baseline, make(chan error)); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("waitRecordingFramesAfter error = %v, want deadline without a post-start key frame", err)
	}

	frames.encodedVideo.notify()
	frames.encodedVideoKeyFrame.notify()
	go func() {
		time.Sleep(10 * time.Millisecond)
		frames.encodedVideo.notify()
	}()
	ctx, cancel = context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := waitRecordingFramesAfter(ctx, frames, baseline, make(chan error)); err != nil {
		t.Fatalf("waitRecordingFramesAfter with key frame and following video: %v", err)
	}
}

func TestFirstFrameWaitPreservesReplayFailure(t *testing.T) {
	failures := make(chan error, 1)
	notifyError(failures, storage.ErrUnavailable)
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	err := waitFrames(ctx, newFrameSignals(), failures)
	if !errors.Is(err, storage.ErrUnavailable) || errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("first frame wait lost source failure: %v", err)
	}
}

func TestRetryWhileInUseStopsAtFirstStableResult(t *testing.T) {
	calls := 0
	err := retryWhileInUse(context.Background(), func() error {
		calls++
		if calls < 3 {
			return storage.ErrInUse
		}
		return nil
	})
	if err != nil || calls != 3 {
		t.Fatalf("retryWhileInUse = (%v, %d calls), want (nil, 3 calls)", err, calls)
	}
}

func TestCoveredExportRangeExcludesReportedGapsAndPreRoll(t *testing.T) {
	at := func(seconds int64) time.Time { return time.Unix(seconds, 0) }
	report := storage.ExportReport{
		RequestedRange: storage.RecordingRange{StartTime: at(10), EndTime: at(20)},
		Segments:       []storage.ExportSegment{{SourceRange: storage.RecordingRange{StartTime: at(9), EndTime: at(20)}}},
		Gaps: []storage.RecordingGap{
			{Range: storage.RecordingRange{StartTime: at(10), EndTime: at(11)}},
			{Range: storage.RecordingRange{StartTime: at(19), EndTime: at(20)}},
		},
	}
	got, ok := coveredExportRange(report)
	if !ok || got.StartTime != at(11) || got.EndTime != at(16) {
		t.Fatalf("unexpected covered range: %#v, %v", got, ok)
	}
	report.Gaps = []storage.RecordingGap{{Range: report.RequestedRange}}
	if _, ok := coveredExportRange(report); ok {
		t.Fatal("selected a range entirely covered by a gap")
	}
	report.Gaps = nil
	report.Segments = nil
	if _, ok := coveredExportRange(report); ok {
		t.Fatal("selected a range without published media")
	}
}

func TestNetworkFailureAdmissionAndCleanupReceipt(t *testing.T) {
	for _, code := range []int32{6009, 6114, 6136, 6137, 6024, 6000, 6044, 6043, 6115, 6199} {
		for _, callsite := range []string{"cloud.initial_query", "cloud.open_start"} {
			for _, cleanupFailed := range []bool{false, true} {
				t.Run(fmt.Sprintf("%d/%s/cleanup=%v", code, callsite, cleanupFailed), func(t *testing.T) {
					output := t.TempDir()
					original := fmt.Errorf("original operation: %w", &storage.Error{Code: code})
					admitted := networkFailure(callsite, original)
					var cleanupErr error
					if cleanupFailed {
						cleanupErr = errors.New("original cleanup failure")
					}
					result := finishNetworkFailure(output, admitted, cleanupErr)
					if !errors.Is(result, original) || (cleanupErr != nil && !errors.Is(result, cleanupErr)) {
						t.Fatal("original error or cleanup lost", result)
					}
					if admitted.Error() != original.Error() {
						t.Fatal("original operation reason changed", admitted)
					}
					payload, err := os.ReadFile(filepath.Join(output, "network-failure.json"))
					eligible := code == 6009 || code == 6114 || code == 6136 || code == 6137
					if !eligible || cleanupFailed {
						if !errors.Is(err, os.ErrNotExist) {
							t.Fatal("unqualified failure wrote receipt", string(payload), err)
						}
						return
					}
					if err != nil {
						t.Fatal(err)
					}
					var receipt struct {
						Schema      string `json:"schema"`
						Callsite    string `json:"callsite"`
						PublicError struct {
							Code   int32  `json:"code"`
							Source string `json:"source"`
						} `json:"public_error"`
						Cleanup bool `json:"cleanup_complete"`
					}
					if err := json.Unmarshal(payload, &receipt); err != nil {
						t.Fatal(err)
					}
					if receipt.Schema != "tirtc.headless-network-failure/v1" || receipt.Callsite != callsite || receipt.PublicError.Code != code || receipt.PublicError.Source != "go-public-sdk" || !receipt.Cleanup {
						t.Fatalf("wrong receipt: %s", payload)
					}
				})
			}
		}
	}
	for _, err := range []error{errors.New("6114 local file failure"), storage.ErrIO, storage.ErrNoFrame, nil} {
		if networkFailure("cloud.initial_query", err) != err {
			t.Fatal("non-public-code error admitted", err)
		}
	}
	// The same public error from later media/control paths has no annotation.
	output := t.TempDir()
	_ = finishNetworkFailure(output, &storage.Error{Code: 6114}, nil)
	if _, err := os.Stat(filepath.Join(output, "network-failure.json")); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("later operation was admitted", err)
	}
}

func TestRunClearsStaleNetworkReceiptBeforeMissingEnvironment(t *testing.T) {
	output := t.TempDir()
	receipt := filepath.Join(output, "network-failure.json")
	if err := os.WriteFile(receipt, []byte(`{"cleanup_complete":true}`), 0600); err != nil {
		t.Fatal(err)
	}
	previousArgs, previousFlags := os.Args, flag.CommandLine
	defer func() { os.Args = previousArgs; flag.CommandLine = previousFlags }()
	flag.CommandLine = flag.NewFlagSet("storage-contract", flag.ContinueOnError)
	os.Args = []string{"storage", "--output-dir", output, "--cache-dir", t.TempDir(), "--start-ms", "1", "--end-ms", "2", "--video-channel-id", "11", "--no-receive-audio"}
	for _, name := range []string{"TI_CLOUD_STORAGE_APP_ID", "TI_CLOUD_STORAGE_ACCESS_KEY_ID", "TI_CLOUD_STORAGE_ACCESS_KEY_SECRET", "TI_CLOUD_STORAGE_DEVICE_ID"} {
		t.Setenv(name, "")
	}
	if err := run(); err == nil {
		t.Fatal("missing input unexpectedly passed")
	}
	if _, err := os.Stat(receipt); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("stale network receipt survived", err)
	}
}

func TestOnlyInitialCloudCallsAttachNetworkFailure(t *testing.T) {
	file, err := parser.ParseFile(token.NewFileSet(), "main.go", nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	calls := map[string]string{}
	ast.Inspect(file, func(node ast.Node) bool {
		call, ok := node.(*ast.CallExpr)
		if !ok {
			return true
		}
		function, ok := call.Fun.(*ast.Ident)
		if !ok || function.Name != "networkFailure" {
			return true
		}
		callsite, ok := call.Args[0].(*ast.BasicLit)
		if !ok {
			t.Fatal("nonliteral callsite")
		}
		wrapped, ok := call.Args[1].(*ast.CallExpr)
		if !ok {
			t.Fatal("original operation label missing")
		}
		label, ok := wrapped.Args[0].(*ast.BasicLit)
		if !ok {
			t.Fatal("nonliteral original label")
		}
		calls[label.Value] = callsite.Value
		return true
	})
	want := map[string]string{`"list recording days: %w"`: `"cloud.initial_query"`, `"list recording ranges: %w"`: `"cloud.initial_query"`, `"create replay: %w"`: `"cloud.open_start"`, `"play replay: %w"`: `"cloud.open_start"`}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("unexpected admission sites: %#v", calls)
	}
	original := networkFailure("cloud.initial_query", &storage.Error{Code: 6114})
	blocked := filepath.Join(t.TempDir(), "blocked")
	if err := os.WriteFile(blocked, []byte("file"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := finishNetworkFailure(blocked, original, nil); !errors.Is(err, original) {
		t.Fatal("receipt failure lost original error", err)
	}
}

func TestRecordingVideoObservationUsesNewBindingAndPreservesErrors(t *testing.T) {
	for _, scenario := range []string{"none", "old-only", "key-only", "key-and-following", "attach-error", "close-error", "cancel", "output-error"} {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
			defer cancel()
			old := newFrameSignals()
			failures := make(chan error, 1)
			want := errors.New(scenario)
			stopped := make(chan struct{})
			err := observeRecordingVideo(ctx, old, failures, func(fresh *frameSignals) error {
				if fresh == old || fresh.encodedVideo == old.encodedVideo || fresh.encodedVideoKeyFrame == old.encodedVideoKeyFrame {
					t.Fatal("recording observer shares an old encoded mailbox signal")
				}
				old.video.notify()
				old.encodedVideo.notify()
				old.encodedVideoKeyFrame.notify()
				if scenario == "attach-error" || scenario == "close-error" {
					close(stopped)
					return want
				}
				if scenario != "none" && scenario != "old-only" {
					fresh.encodedVideo.notify()
					fresh.encodedVideoKeyFrame.notify()
				}
				if scenario == "cancel" {
					cancel()
				}
				if scenario == "output-error" {
					failures <- want
				}
				go func() {
					defer close(stopped)
					ticker := time.NewTicker(time.Millisecond)
					defer ticker.Stop()
					for {
						select {
						case <-ctx.Done():
							return
						case <-ticker.C:
							if scenario == "key-and-following" {
								fresh.encodedVideo.notify()
							}
						}
					}
				}()
				return nil
			})
			cancel()
			<-stopped
			switch scenario {
			case "key-and-following":
				if err != nil {
					t.Fatalf("fresh key and following video rejected: %v", err)
				}
			case "none", "old-only", "key-only":
				if !errors.Is(err, context.DeadlineExceeded) {
					t.Fatalf("missing fresh recording video accepted: %v", err)
				}
			case "cancel":
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("cancel lost: %v", err)
				}
			default:
				if !errors.Is(err, want) {
					t.Fatalf("replacement or output failure lost: %v", err)
				}
			}
		})
	}
}

func TestRecordingAudioRequiresPostAnchorBinding(t *testing.T) {
	for _, scenario := range []string{"old-only", "new", "attach-error", "close-error", "cancel", "output-error"} {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
			defer cancel()
			old := newFrameSignal()
			failures := make(chan error, 1)
			want := errors.New(scenario)
			err := observeRecordingAudio(ctx, failures, func(fresh *frameSignal) error {
				old.notify() // Late consumption of pre-anchor audio is insufficient.
				if fresh == old {
					t.Fatal("recording audio shares old observation generation")
				}
				if scenario == "attach-error" || scenario == "close-error" {
					return want
				}
				if scenario != "old-only" {
					fresh.notify()
				}
				if scenario == "cancel" {
					cancel()
				}
				if scenario == "output-error" {
					failures <- want
				}
				return nil
			})
			switch scenario {
			case "new":
				if err != nil {
					t.Fatalf("fresh post-anchor audio rejected: %v", err)
				}
			case "old-only":
				if !errors.Is(err, context.DeadlineExceeded) {
					t.Fatalf("old audio accepted: %v", err)
				}
			case "cancel":
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("cancel lost: %v", err)
				}
			default:
				if !errors.Is(err, want) {
					t.Fatalf("replacement or output failure lost: %v", err)
				}
			}
		})
	}
}
