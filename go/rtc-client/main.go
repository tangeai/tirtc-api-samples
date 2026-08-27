package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"sync/atomic"
	"syscall"
	"time"

	tirtc "github.com/tangeai/tirtc-client-go/v2"
)

const (
	maximumMediaFileSize = int64(512 << 20)
	operationTimeout     = 90 * time.Second
)

type clientConfig struct {
	endpoint      string
	remoteID      string
	cacheDir      string
	outputDir     string
	audioStreamID uint8
	videoStreamID uint8
}

type frameSignals struct {
	audio                *frameSignal
	video                *frameSignal
	encodedAudio         *frameSignal
	encodedVideo         *frameSignal
	encodedVideoKeyFrame *frameSignal
}

type frameSignal struct {
	count atomic.Uint64
	ready chan struct{}
}

type frameSnapshot struct {
	audio                uint64
	video                uint64
	encodedAudio         uint64
	encodedVideo         uint64
	encodedVideoKeyFrame uint64
}

func newFrameSignals() *frameSignals {
	return &frameSignals{
		audio:                newFrameSignal(),
		video:                newFrameSignal(),
		encodedAudio:         newFrameSignal(),
		encodedVideo:         newFrameSignal(),
		encodedVideoKeyFrame: newFrameSignal(),
	}
}

func newFrameSignal() *frameSignal {
	return &frameSignal{ready: make(chan struct{}, 8)}
}

func (s *frameSignal) notify() {
	s.count.Add(1)
	select {
	case s.ready <- struct{}{}:
	default:
	}
}

func (s *frameSignals) snapshot() frameSnapshot {
	return frameSnapshot{
		audio:                s.audio.count.Load(),
		video:                s.video.count.Load(),
		encodedAudio:         s.encodedAudio.count.Load(),
		encodedVideo:         s.encodedVideo.count.Load(),
		encodedVideoKeyFrame: s.encodedVideoKeyFrame.count.Load(),
	}
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	config, err := parseConfig()
	if err != nil {
		return err
	}
	appID, token := os.Getenv("TIRTC_APP_ID"), os.Getenv("TIRTC_TOKEN")
	if appID == "" || token == "" {
		return errors.New("TIRTC_APP_ID and TIRTC_TOKEN are required")
	}
	if err := os.MkdirAll(config.outputDir, 0o700); err != nil {
		return fmt.Errorf("prepare output directory: %w", err)
	}
	if err := tirtc.Init(tirtc.InitOptions{
		AppID: appID, CacheDir: config.cacheDir, Endpoint: config.endpoint,
	}); err != nil {
		return fmt.Errorf("initialize TiRTC: %w", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()

	connected := make(chan struct{}, 1)
	commandReceived := make(chan struct{}, 1)
	messageReceived := make(chan struct{}, 1)
	failures := make(chan error, 16)
	frames := newFrameSignals()
	connection, err := tirtc.NewConn(tirtc.ConnOptions{
		OnStateChanged: func(state tirtc.ConnState, err error) {
			if err != nil {
				notifyError(failures, err)
			}
			if state == tirtc.ConnConnected {
				notify(connected)
			}
		},
		OnCommand: func(uint32, []byte) { notify(commandReceived) },
		OnStreamMessage: func(uint8, time.Duration, []byte) {
			notify(messageReceived)
		},
	})
	if err != nil {
		_ = tirtc.Shutdown()
		return fmt.Errorf("create connection: %w", err)
	}

	audio, video, encodedAudio, encodedVideo, err := createOutputs(frames, failures)
	if err != nil {
		_ = connection.Close()
		_ = tirtc.Shutdown()
		return err
	}
	cleaned := false
	cleanup := func() error {
		if cleaned {
			return nil
		}
		cleaned = true
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cleanupCancel()
		return errors.Join(
			closeEventually(cleanupCtx, encodedVideo.Close),
			closeEventually(cleanupCtx, encodedAudio.Close),
			closeEventually(cleanupCtx, video.Close),
			closeEventually(cleanupCtx, audio.Close),
			connection.Close(),
			tirtc.Shutdown(),
		)
	}
	defer func() { _ = cleanup() }()

	for name, attach := range map[string]func() error{
		"decoded audio": func() error { return audio.Attach(connection, config.audioStreamID) },
		"decoded video": func() error { return video.Attach(connection, config.videoStreamID) },
		"encoded audio": func() error { return encodedAudio.Attach(connection, config.audioStreamID) },
		"encoded video": func() error { return encodedVideo.Attach(connection, config.videoStreamID) },
	} {
		if err := attach(); err != nil {
			return fmt.Errorf("attach %s: %w", name, err)
		}
	}
	if err := connection.Connect(config.remoteID, token); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	if err := waitSignal(ctx, "connection", connected, failures); err != nil {
		return err
	}
	if err := connection.SubscribeAudio(config.audioStreamID); err != nil {
		return fmt.Errorf("subscribe audio: %w", err)
	}
	if err := connection.SubscribeVideo(config.videoStreamID); err != nil {
		return fmt.Errorf("subscribe video: %w", err)
	}
	if err := waitFrames(ctx, frames, failures); err != nil {
		return err
	}

	if err := connection.SendCommand(0x2001, []byte("go-client-command")); err != nil {
		return fmt.Errorf("send command: %w", err)
	}
	timestamp := time.Duration(uint32(time.Now().UnixMilli())) * time.Millisecond
	if err := connection.SendStreamMessage(config.videoStreamID, timestamp, []byte("go-client-message")); err != nil {
		return fmt.Errorf("send stream message: %w", err)
	}
	if err := connection.RequestVideoKeyframe(config.videoStreamID); err != nil {
		return fmt.Errorf("request key frame: %w", err)
	}
	if err := waitSignal(ctx, "remote command", commandReceived, failures); err != nil {
		return err
	}
	if err := waitSignal(ctx, "remote stream message", messageReceived, failures); err != nil {
		return err
	}

	audioID := config.audioStreamID
	recording, err := connection.StartRecording(tirtc.StartRecordingOptions{
		VideoStreamID: config.videoStreamID,
		AudioStreamID: &audioID,
	})
	if err != nil {
		return fmt.Errorf("start recording: %w", err)
	}
	postRecordingBaseline := frames.snapshot()
	if err := connection.RequestVideoKeyframe(config.videoStreamID); err != nil {
		_, _ = recording.Stop()
		return fmt.Errorf("request recording key frame: %w", err)
	}
	if err := waitRecordingFramesAfter(ctx, frames, postRecordingBaseline, failures); err != nil {
		_, _ = recording.Stop()
		return fmt.Errorf("wait for post-recording frames: %w", err)
	}
	recordingFile, err := recording.Stop()
	if err != nil {
		return fmt.Errorf("stop recording: %w", err)
	}
	if err := saveTemporaryMedia(
		recordingFile.Path,
		filepath.Join(config.outputDir, "rtc-recording.mp4"),
		[]byte("ftyp"), 4,
	); err != nil {
		return err
	}
	if err := recordingFile.Delete(); err != nil {
		return fmt.Errorf("delete temporary recording: %w", err)
	}

	snapshot, err := video.TakeSnapshot()
	if err != nil {
		return fmt.Errorf("take snapshot: %w", err)
	}
	if err := saveTemporaryMedia(
		snapshot.Path,
		filepath.Join(config.outputDir, "rtc-snapshot.jpg"),
		[]byte{0xff, 0xd8}, 0,
	); err != nil {
		return err
	}
	if err := snapshot.Delete(); err != nil {
		return fmt.Errorf("delete temporary snapshot: %w", err)
	}
	if err := connection.UnsubscribeVideo(config.videoStreamID); err != nil {
		return fmt.Errorf("unsubscribe video: %w", err)
	}
	if err := connection.UnsubscribeAudio(config.audioStreamID); err != nil {
		return fmt.Errorf("unsubscribe audio: %w", err)
	}
	return cleanup()
}

func parseConfig() (clientConfig, error) {
	var endpoint, remoteID, cacheDir, outputDir string
	var audioStreamID, videoStreamID uint
	flag.StringVar(&endpoint, "endpoint", "", "TiRTC endpoint")
	flag.StringVar(&remoteID, "remote-id", "", "remote device ID")
	flag.StringVar(&cacheDir, "cache-dir", "", "absolute writable SDK work directory")
	flag.StringVar(&outputDir, "output-dir", "", "absolute application-owned output directory")
	flag.UintVar(&audioStreamID, "audio-stream-id", 10, "remote audio stream ID")
	flag.UintVar(&videoStreamID, "video-stream-id", 11, "remote video stream ID")
	flag.Parse()
	if remoteID == "" || !filepath.IsAbs(cacheDir) || !filepath.IsAbs(outputDir) ||
		audioStreamID > 15 || videoStreamID > 15 || audioStreamID == videoStreamID {
		return clientConfig{}, errors.New("--remote-id, absolute --cache-dir/--output-dir, and distinct 0..15 stream IDs are required")
	}
	return clientConfig{
		endpoint: endpoint, remoteID: remoteID,
		cacheDir: filepath.Clean(cacheDir), outputDir: filepath.Clean(outputDir),
		audioStreamID: uint8(audioStreamID), videoStreamID: uint8(videoStreamID),
	}, nil
}

func createOutputs(frames *frameSignals, failures chan<- error) (
	*tirtc.AudioOutput,
	*tirtc.VideoOutput,
	*tirtc.EncodedAudioOutput,
	*tirtc.EncodedVideoOutput,
	error,
) {
	audio, err := tirtc.NewAudioOutput(tirtc.AudioOutputOptions{
		OnFrame: func(tirtc.AudioFrame) { frames.audio.notify() },
		OnError: outputErrorNotifier("decoded audio output", failures),
	})
	if err != nil {
		return nil, nil, nil, nil, err
	}
	video, err := tirtc.NewVideoOutput(tirtc.VideoOutputOptions{
		OnFrame: func(tirtc.VideoFrame) { frames.video.notify() },
		OnError: outputErrorNotifier("decoded video output", failures),
	})
	if err != nil {
		_ = audio.Close()
		return nil, nil, nil, nil, err
	}
	encodedAudio, err := tirtc.NewEncodedAudioOutput(tirtc.EncodedAudioOutputOptions{
		OnFrame: func(tirtc.EncodedAudioFrame) { frames.encodedAudio.notify() },
		OnError: outputErrorNotifier("encoded audio output", failures),
	})
	if err != nil {
		_ = video.Close()
		_ = audio.Close()
		return nil, nil, nil, nil, err
	}
	encodedVideo, err := tirtc.NewEncodedVideoOutput(tirtc.EncodedVideoOutputOptions{
		OnFrame: func(frame tirtc.EncodedVideoFrame) {
			frames.encodedVideo.notify()
			if frame.KeyFrame {
				frames.encodedVideoKeyFrame.notify()
			}
		}, OnError: outputErrorNotifier("encoded video output", failures),
	})
	if err != nil {
		_ = encodedAudio.Close()
		_ = video.Close()
		_ = audio.Close()
		return nil, nil, nil, nil, err
	}
	return audio, video, encodedAudio, encodedVideo, nil
}

func outputErrorNotifier(name string, failures chan<- error) func(error) {
	return func(err error) {
		if err != nil {
			notifyError(failures, fmt.Errorf("%s: %w", name, err))
		}
	}
}

func waitFrames(ctx context.Context, frames *frameSignals, failures <-chan error) error {
	return waitFramesAfter(ctx, frames, frameSnapshot{}, failures)
}

func waitFramesAfter(ctx context.Context, frames *frameSignals, baseline frameSnapshot, failures <-chan error) error {
	for _, item := range []struct {
		name     string
		signal   *frameSignal
		baseline uint64
	}{
		{"decoded audio frame", frames.audio, baseline.audio},
		{"decoded video frame", frames.video, baseline.video},
		{"encoded audio frame", frames.encodedAudio, baseline.encodedAudio},
		{"encoded video frame", frames.encodedVideo, baseline.encodedVideo},
	} {
		if err := waitFrameAfter(ctx, item.name, item.signal, item.baseline, failures); err != nil {
			return err
		}
	}
	return nil
}

func waitRecordingFramesAfter(ctx context.Context, frames *frameSignals, baseline frameSnapshot, failures <-chan error) error {
	if err := waitFramesAfter(ctx, frames, baseline, failures); err != nil {
		return err
	}
	if err := waitFrameAfter(ctx, "encoded video key frame", frames.encodedVideoKeyFrame, baseline.encodedVideoKeyFrame, failures); err != nil {
		return err
	}
	return waitFrameAfter(ctx, "encoded video frame after key frame", frames.encodedVideo, frames.encodedVideo.count.Load(), failures)
}

func waitFrameAfter(ctx context.Context, name string, signal *frameSignal, baseline uint64, failures <-chan error) error {
	for signal.count.Load() <= baseline {
		if err := waitSignal(ctx, name, signal.ready, failures); err != nil {
			return err
		}
	}
	return nil
}

func waitSignal(ctx context.Context, name string, signal <-chan struct{}, failures <-chan error) error {
	select {
	case <-signal:
		return nil
	case err := <-failures:
		return fmt.Errorf("%s failed: %w", name, err)
	case <-ctx.Done():
		return fmt.Errorf("%s: %w", name, ctx.Err())
	}
}

func notify(target chan<- struct{}) {
	select {
	case target <- struct{}{}:
	default:
	}
}

func notifyError(target chan<- error, err error) {
	if err == nil {
		return
	}
	select {
	case target <- err:
	default:
	}
}

func closeEventually(ctx context.Context, closeResource func() error) error {
	ticker := time.NewTicker(5 * time.Millisecond)
	defer ticker.Stop()
	for {
		err := closeResource()
		if !errors.Is(err, tirtc.ErrInUse) {
			return err
		}
		select {
		case <-ticker.C:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
}

func saveTemporaryMedia(sourcePath, destinationPath string, signature []byte, offset int64) (resultErr error) {
	source, err := os.Open(sourcePath)
	if err != nil {
		return fmt.Errorf("open temporary media: %w", err)
	}
	defer source.Close()
	info, err := source.Stat()
	if err != nil {
		return fmt.Errorf("inspect temporary media: %w", err)
	}
	if info.Size() <= offset+int64(len(signature)) || info.Size() > maximumMediaFileSize {
		return fmt.Errorf("temporary media size %d is outside the supported bound", info.Size())
	}
	header := make([]byte, len(signature))
	if _, err := source.ReadAt(header, offset); err != nil || !equalBytes(header, signature) {
		return errors.New("temporary media header is invalid")
	}
	if _, err := source.Seek(0, io.SeekStart); err != nil {
		return err
	}
	destination, err := os.OpenFile(destinationPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return fmt.Errorf("create application media: %w", err)
	}
	defer func() {
		if closeErr := destination.Close(); resultErr == nil {
			resultErr = closeErr
		}
		if resultErr != nil {
			_ = os.Remove(destinationPath)
		}
	}()
	written, err := io.Copy(destination, io.LimitReader(source, maximumMediaFileSize+1))
	if err != nil {
		return fmt.Errorf("copy application media: %w", err)
	}
	if written != info.Size() || written > maximumMediaFileSize {
		return errors.New("application media copy was incomplete or exceeded the size bound")
	}
	return destination.Sync()
}

func equalBytes(left, right []byte) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index] != right[index] {
			return false
		}
	}
	return true
}
