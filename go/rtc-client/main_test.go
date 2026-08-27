package main

import (
	"context"
	"errors"
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
