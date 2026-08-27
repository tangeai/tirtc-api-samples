package main

import (
	"context"
	"errors"
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
