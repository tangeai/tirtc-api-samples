package main

import (
	"context"
	"errors"
	"runtime"
	"strings"
	"testing"
	"time"
)

func TestOutputErrorNotifierPreservesOutputIdentity(t *testing.T) {
	failures := make(chan error, 1)
	want := errors.New("decoder failed")
	outputErrorNotifier("decoded video output", failures)(want)
	got := <-failures
	if !errors.Is(got, want) || !strings.Contains(got.Error(), "decoded video output") {
		t.Fatalf("output error = %v, want source identity and wrapped cause", got)
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

func TestSelectedRecordingRequiresNewAudioAndKeepsVideoOnly(t *testing.T) {
	for _, name := range []string{"buffered-audio-only", "new-decoded-only", "new-encoded-only", "new-audio-and-video", "video-only"} {
		t.Run(name, func(t *testing.T) {
			receiveAudio := name != "video-only"
			decodedAudio := name == "new-decoded-only" || name == "new-audio-and-video"
			encodedAudio := name == "new-encoded-only" || name == "new-audio-and-video"
			passed := name == "new-audio-and-video" || name == "video-only"
			frames := newFrameSignals()
			frames.audio.notify()
			frames.encodedAudio.notify()
			baseline := frames.snapshot()
			frames.video.notify()
			frames.encodedVideoKeyFrame.notify()
			if decodedAudio {
				frames.audio.notify()
			}
			if encodedAudio {
				frames.encodedAudio.notify()
			}
			ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
			defer cancel()
			done := make(chan struct{})
			go func() {
				defer close(done)
				for {
					select {
					case <-ctx.Done():
						return
					default:
						frames.encodedVideo.notify()
						runtime.Gosched()
					}
				}
			}()
			err := waitSelectedRecordingFramesAfter(ctx, frames, baseline, receiveAudio, make(chan error))
			cancel()
			<-done
			if passed && err != nil {
				t.Fatalf("selected recording = %v, want ready", err)
			}
			if !passed && !errors.Is(err, context.DeadlineExceeded) {
				t.Fatalf("selected recording = %v, want deadline without both post-start audio observations", err)
			}
		})
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
func TestRecordingAudioBeforeVideoAnchorDoesNotMakeReady(t *testing.T) {
	frames := newFrameSignals()
	baseline := frames.snapshot()
	// Both audio callbacks occur before the recording's video anchor.
	frames.audio.notify()
	frames.encodedAudio.notify()
	frames.video.notify()
	frames.encodedVideoKeyFrame.notify()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	defer cancel()
	done := make(chan struct{})
	go func() {
		defer close(done)
		for ctx.Err() == nil {
			frames.encodedVideo.notify()
			runtime.Gosched()
		}
	}()
	failures := make(chan error)
	err := waitSelectedRecordingFramesAfter(ctx, frames, baseline, true, failures)
	if err == nil {
		fresh := newFrameSignal()
		err = observeRecordingAudio(ctx, fresh, failures, func() error {
			// Late consumption from the original mailbox must not satisfy the new generation.
			frames.encodedAudio.notify()
			frames.encodedAudio.notify()
			return nil
		}, func() error { return nil })
	}
	cancel()
	<-done
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("recording became ready with only pre-anchor audio: %v", err)
	}
}

func TestRecordingAudioObserverRequiresTwoCallbacksAndCloses(t *testing.T) {
	for _, scenario := range []string{"none", "one", "two-during-attach", "two-then-cancel", "one-then-cancel", "attach-fails", "close-fails", "output-fails"} {
		t.Run(scenario, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
			defer cancel()
			frames := newFrameSignal()
			failures := make(chan error, 1)
			want := errors.New(scenario)
			closed := 0
			err := observeRecordingAudio(ctx, frames, failures, func() error {
				if scenario == "attach-fails" {
					return want
				}
				if scenario != "none" {
					frames.notify()
				}
				if scenario != "none" && scenario != "one" && scenario != "one-then-cancel" {
					frames.notify()
				}
				if scenario == "two-then-cancel" || scenario == "one-then-cancel" {
					cancel()
				}
				if scenario == "output-fails" {
					failures <- want
				}
				return nil
			}, func() error {
				closed++
				if scenario == "close-fails" {
					return want
				}
				return nil
			})
			if closed != 1 {
				t.Fatalf("closed %d times, want 1", closed)
			}
			switch scenario {
			case "two-during-attach":
				if err != nil {
					t.Fatalf("two fresh callbacks: %v", err)
				}
			case "none", "one":
				if !errors.Is(err, context.DeadlineExceeded) {
					t.Fatalf("missing second callback: %v", err)
				}
			case "two-then-cancel", "one-then-cancel":
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("cancel lost: %v", err)
				}
			default:
				if !errors.Is(err, want) {
					t.Fatalf("lifecycle/output failure lost: %v", err)
				}
			}
		})
	}
}

func TestRecordingAudioObserverDoesNotBecomeReadyAtFirstCallback(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	frames := newFrameSignal()
	first := make(chan struct{})
	resume := make(chan struct{})
	done := make(chan error, 1)
	go func() {
		done <- observeRecordingAudio(ctx, frames, make(chan error), func() error {
			go func() {
				frames.notify()
				close(first)
				<-resume        // First native dispatch has not yet reached its enqueue.
				frames.notify() // Next serial dispatch fences the first enqueue.
			}()
			return nil
		}, func() error { return nil })
	}()
	<-first
	select {
	case err := <-done:
		t.Fatalf("ready before the first dispatch completed: %v", err)
	default:
	}
	close(resume)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}

func TestIndependentObservationsRetainCancellationAndFailure(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	started := time.Now()
	for index := 0; index < 2; index++ {
		frames := newFrameSignal()
		go func() { time.Sleep(25 * time.Millisecond); frames.notify() }()
		if err := waitFrameAfter(ctx, "independent frame", frames, 0, make(chan error)); err != nil {
			t.Fatal(err)
		}
	}
	if time.Since(started) < 45*time.Millisecond {
		t.Fatal("did not exercise sequential observations")
	}
	if _, deadline := ctx.Deadline(); deadline {
		t.Fatal("observations installed a caller work deadline")
	}
	want := errors.New("actual media error")
	failures := make(chan error, 1)
	failures <- want
	if err := waitFrameAfter(ctx, "failed media", newFrameSignal(), 0, failures); !errors.Is(err, want) {
		t.Fatalf("media failure changed: %v", err)
	}
	short, stop := context.WithTimeout(ctx, 5*time.Millisecond)
	defer stop()
	if err := waitFrameAfter(short, "missing media", newFrameSignal(), 0, make(chan error)); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("missing media did not time out: %v", err)
	}
	cancel()
	if err := waitFrameAfter(ctx, "cancelled media", newFrameSignal(), 0, make(chan error)); !errors.Is(err, context.Canceled) {
		t.Fatalf("cancelled media did not stop: %v", err)
	}
	proof, _ := newMessageProof([]uint8{11, 12}, true)
	if err := proof.wait(ctx); err == nil {
		t.Fatal("missing messages accepted after cancellation")
	}
}
