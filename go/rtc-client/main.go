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
	"strconv"
	"strings"
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
	endpoint       string
	remoteID       string
	cacheDir       string
	outputDir      string
	audioStreamID  *uint8
	videoStreamIDs []uint8
	rawDumpSeconds uint
	rawDump        bool
	rawDumpCopyTo  string
	uploadLogs     bool
	caseID         string
}

type optionalUintFlag struct {
	value uint
	set   bool
}

func (value *optionalUintFlag) String() string {
	if !value.set {
		return ""
	}
	return strconv.FormatUint(uint64(value.value), 10)
}

func (value *optionalUintFlag) Set(text string) error {
	parsed, err := strconv.ParseUint(text, 10, 8)
	if err != nil {
		return err
	}
	value.value = uint(parsed)
	value.set = true
	return nil
}

type uintListFlag []uint

func (value *uintListFlag) String() string {
	parts := make([]string, len(*value))
	for index, item := range *value {
		parts[index] = strconv.FormatUint(uint64(item), 10)
	}
	return strings.Join(parts, ",")
}

func (value *uintListFlag) Set(text string) error {
	parsed, err := strconv.ParseUint(text, 10, 8)
	if err != nil {
		return err
	}
	*value = append(*value, uint(parsed))
	return nil
}

type videoOutputPair struct {
	streamID uint8
	decoded  *tirtc.VideoOutput
	encoded  *tirtc.EncodedVideoOutput
	frames   *frameSignals
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
	appID := os.Getenv("TIRTC_APP_ID")
	accessKeyID := os.Getenv("TIRTC_ACCESS_KEY_ID")
	accessKeySecret := os.Getenv("TIRTC_SECRET_KEY_ID")
	if appID == "" || accessKeyID == "" || accessKeySecret == "" {
		return errors.New("TIRTC_APP_ID, TIRTC_ACCESS_KEY_ID, and TIRTC_SECRET_KEY_ID are required")
	}
	if err := os.MkdirAll(config.outputDir, 0o700); err != nil {
		return fmt.Errorf("prepare output directory: %w", err)
	}
	client, err := tirtc.NewClient(tirtc.ClientOptions{
		AppID: appID, AccessKeyID: accessKeyID, AccessKeySecret: accessKeySecret,
		CacheDir: config.cacheDir, Endpoint: config.endpoint,
	})
	if err != nil {
		return fmt.Errorf("initialize TiRTC: %w", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()

	commandReceived := make(chan struct{}, 1)
	messageReceived := make(chan struct{}, 1)
	failures := make(chan error, 16)
	audioFrames := newFrameSignals()
	connection, err := client.NewConnection(tirtc.ConnOptions{
		OnStateChanged: func(_ tirtc.ConnState, err error) {
			if err != nil {
				notifyError(failures, err)
			}
		},
		OnCommand: func(uint32, []byte) { notify(commandReceived) },
		OnStreamMessage: func(uint8, time.Duration, []byte) {
			notify(messageReceived)
		},
	})
	if err != nil {
		_ = client.Close()
		return fmt.Errorf("create connection: %w", err)
	}

	var audio *tirtc.AudioOutput
	var encodedAudio *tirtc.EncodedAudioOutput
	if config.audioStreamID != nil {
		audio, encodedAudio, err = createAudioOutputs(audioFrames, failures)
		if err != nil {
			_ = connection.Close()
			_ = client.Close()
			return err
		}
	}
	videos := make([]videoOutputPair, 0, len(config.videoStreamIDs))
	for _, streamID := range config.videoStreamIDs {
		pair, createErr := createVideoOutputs(streamID, failures)
		if createErr != nil {
			for index := len(videos) - 1; index >= 0; index-- {
				_ = videos[index].encoded.Close()
				_ = videos[index].decoded.Close()
			}
			if encodedAudio != nil {
				_ = encodedAudio.Close()
			}
			if audio != nil {
				_ = audio.Close()
			}
			_ = connection.Close()
			_ = client.Close()
			return createErr
		}
		videos = append(videos, pair)
	}
	cleaned := false
	cleanup := func() error {
		if cleaned {
			return nil
		}
		cleaned = true
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cleanupCancel()
		var cleanupErrors []error
		for index := len(videos) - 1; index >= 0; index-- {
			cleanupErrors = append(cleanupErrors,
				closeEventually(cleanupCtx, videos[index].encoded.Close),
				closeEventually(cleanupCtx, videos[index].decoded.Close),
			)
		}
		if encodedAudio != nil {
			cleanupErrors = append(cleanupErrors, closeEventually(cleanupCtx, encodedAudio.Close))
		}
		if audio != nil {
			cleanupErrors = append(cleanupErrors, closeEventually(cleanupCtx, audio.Close))
		}
		cleanupErrors = append(cleanupErrors, connection.Close(), client.Close())
		return errors.Join(cleanupErrors...)
	}
	defer func() { _ = cleanup() }()

	if config.audioStreamID != nil {
		if err := audio.Attach(connection, *config.audioStreamID); err != nil {
			return fmt.Errorf("attach decoded audio: %w", err)
		}
		if err := encodedAudio.Attach(connection, *config.audioStreamID); err != nil {
			return fmt.Errorf("attach encoded audio: %w", err)
		}
	}
	for _, pair := range videos {
		if err := pair.decoded.Attach(connection, pair.streamID); err != nil {
			return fmt.Errorf("attach decoded video %d: %w", pair.streamID, err)
		}
		if err := pair.encoded.Attach(connection, pair.streamID); err != nil {
			return fmt.Errorf("attach encoded video %d: %w", pair.streamID, err)
		}
	}
	if err := connection.Connect(ctx, config.remoteID); err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	if config.audioStreamID != nil {
		if err := connection.SubscribeAudio(*config.audioStreamID); err != nil {
			return fmt.Errorf("subscribe audio: %w", err)
		}
	}
	for _, pair := range videos {
		if err := connection.SubscribeVideo(pair.streamID); err != nil {
			return fmt.Errorf("subscribe video %d: %w", pair.streamID, err)
		}
		if err := connection.RequestVideoKeyframe(pair.streamID); err != nil {
			return fmt.Errorf("request key frame %d: %w", pair.streamID, err)
		}
	}
	var rawDump *tirtc.RawDump
	var rawDumpStarted time.Time
	if config.rawDump {
		audioIDs := make([]uint8, 0, 1)
		if config.audioStreamID != nil {
			audioIDs = append(audioIDs, *config.audioStreamID)
		}
		rawDump, err = connection.StartRawDump(tirtc.RawDumpOptions{
			AudioStreamIDs: audioIDs, VideoStreamIDs: config.videoStreamIDs,
		})
		if err != nil {
			return fmt.Errorf("start raw dump: %w", err)
		}
		rawDumpStarted = time.Now()
		defer func() { _ = rawDump.Close() }()
	}
	if err := waitSelectedFrames(ctx, audioFrames, config.audioStreamID != nil, videos, failures); err != nil {
		return err
	}

	if err := connection.SendCommand(0x2001, []byte("go-client-command")); err != nil {
		return fmt.Errorf("send command: %w", err)
	}
	timestamp := time.Duration(uint32(time.Now().UnixMilli())) * time.Millisecond
	messageStreamID := uint8(0)
	if len(videos) > 0 {
		messageStreamID = videos[0].streamID
	} else if config.audioStreamID != nil {
		messageStreamID = *config.audioStreamID
	}
	if err := connection.SendStreamMessage(messageStreamID, timestamp, []byte("go-client-message")); err != nil {
		return fmt.Errorf("send stream message: %w", err)
	}
	if err := waitSignal(ctx, "remote command", commandReceived, failures); err != nil {
		return err
	}
	if err := waitSignal(ctx, "remote stream message", messageReceived, failures); err != nil {
		return err
	}
	if rawDump != nil {
		if config.caseID == "integration.raw-dump-recovery" {
			_, duplicateErr := connection.StartRawDump(tirtc.RawDumpOptions{
				AudioStreamIDs: func() []uint8 {
					if config.audioStreamID == nil {
						return nil
					}
					return []uint8{*config.audioStreamID}
				}(),
				VideoStreamIDs: config.videoStreamIDs,
			})
			if !errors.Is(duplicateErr, tirtc.ErrInUse) {
				return fmt.Errorf("duplicate raw dump start must return ErrInUse: %w", duplicateErr)
			}
		}
		remaining := time.Duration(config.rawDumpSeconds)*time.Second - time.Since(rawDumpStarted)
		if remaining > 0 {
			select {
			case <-time.After(remaining):
			case <-ctx.Done():
				return ctx.Err()
			}
		}
		archive, stopErr := rawDump.Stop()
		if stopErr != nil {
			return fmt.Errorf("stop raw dump: %w", stopErr)
		}
		fmt.Printf("raw dump capture_id=%s path=%s size=%d sha256=%s duration=%s complete=%t empty=%t\n",
			archive.CaptureID, archive.Path, archive.Size, archive.SHA256,
			archive.CapturedDuration, archive.CaptureComplete, archive.Empty)
		if config.rawDumpCopyTo != "" {
			if err := copyRawDump(archive.Path, config.rawDumpCopyTo); err != nil {
				return err
			}
			fmt.Printf("raw dump copy path=%s\n", config.rawDumpCopyTo)
		}
		if config.caseID == "integration.raw-dump-recovery" {
			repeated, repeatedErr := rawDump.Stop()
			if repeatedErr != nil || repeated != archive {
				return fmt.Errorf("repeated raw dump stop changed terminal result: %w", repeatedErr)
			}
		}
	}

	for _, pair := range videos {
		recording, startErr := connection.StartRecording(tirtc.StartRecordingOptions{
			VideoStreamID: pair.streamID,
			AudioStreamID: config.audioStreamID,
		})
		if startErr != nil {
			return fmt.Errorf("start recording stream %d: %w", pair.streamID, startErr)
		}
		baseline := pair.frames.snapshot()
		if requestErr := connection.RequestVideoKeyframe(pair.streamID); requestErr != nil {
			file, stopErr := recording.Stop()
			if file.Path != "" {
				stopErr = errors.Join(stopErr, file.Delete())
			}
			return fmt.Errorf("request recording key frame %d: %w", pair.streamID, errors.Join(requestErr, stopErr))
		}
		if waitErr := waitVideoRecordingFramesAfter(ctx, pair.frames, baseline, failures); waitErr != nil {
			file, stopErr := recording.Stop()
			if file.Path != "" {
				stopErr = errors.Join(stopErr, file.Delete())
			}
			return fmt.Errorf("wait for stream %d recording frames: %w", pair.streamID, errors.Join(waitErr, stopErr))
		}
		recordingFile, stopErr := recording.Stop()
		if stopErr != nil {
			if recordingFile.Path != "" {
				stopErr = errors.Join(stopErr, recordingFile.Delete())
			}
			return fmt.Errorf("stop recording stream %d: %w", pair.streamID, stopErr)
		}
		if saveErr := saveTemporaryMedia(recordingFile.Path, filepath.Join(config.outputDir, fmt.Sprintf("rtc-recording-stream-%d.mp4", pair.streamID)), []byte("ftyp"), 4); saveErr != nil {
			return errors.Join(saveErr, recordingFile.Delete())
		}
		if deleteErr := recordingFile.Delete(); deleteErr != nil {
			return fmt.Errorf("delete temporary recording: %w", deleteErr)
		}
		snapshot, snapshotErr := pair.decoded.TakeSnapshot()
		if snapshotErr != nil {
			return fmt.Errorf("take stream %d snapshot: %w", pair.streamID, snapshotErr)
		}
		if saveErr := saveTemporaryMedia(snapshot.Path, filepath.Join(config.outputDir, fmt.Sprintf("rtc-snapshot-stream-%d.jpg", pair.streamID)), []byte{0xff, 0xd8}, 0); saveErr != nil {
			return errors.Join(saveErr, snapshot.Delete())
		}
		if deleteErr := snapshot.Delete(); deleteErr != nil {
			return fmt.Errorf("delete temporary snapshot: %w", deleteErr)
		}
		fmt.Printf("consumed video stream %d\n", pair.streamID)
	}
	for index := len(videos) - 1; index >= 0; index-- {
		if err := connection.UnsubscribeVideo(videos[index].streamID); err != nil {
			return fmt.Errorf("unsubscribe video %d: %w", videos[index].streamID, err)
		}
	}
	if config.audioStreamID != nil {
		if err := connection.UnsubscribeAudio(*config.audioStreamID); err != nil {
			return fmt.Errorf("unsubscribe audio: %w", err)
		}
	}
	if config.uploadLogs {
		logID, err := client.UploadLogs()
		if err != nil {
			return fmt.Errorf("upload logs: %w", err)
		}
		fmt.Printf("log_id=%s\n", logID)
	}
	return cleanup()
}

func parseConfig() (clientConfig, error) {
	var endpoint, remoteID, cacheDir, outputDir string
	var audioStreamID optionalUintFlag
	var videoStreamIDs uintListFlag
	var noReceiveAudio, noReceiveVideo bool
	var rawDumpSeconds uint
	var rawDump, uploadLogs bool
	var rawDumpCopyTo, caseID string
	flag.StringVar(&endpoint, "endpoint", "", "TiRTC endpoint")
	flag.StringVar(&remoteID, "remote-id", "", "remote device ID")
	flag.StringVar(&cacheDir, "cache-dir", "", "absolute writable SDK work directory")
	flag.StringVar(&outputDir, "output-dir", "", "absolute application-owned output directory")
	flag.Var(&audioStreamID, "audio-stream-id", "remote audio stream ID")
	flag.Var(&videoStreamIDs, "video-stream-id", "remote video stream ID; repeat up to three times")
	flag.BoolVar(&noReceiveAudio, "no-receive-audio", false, "do not receive audio")
	flag.BoolVar(&noReceiveVideo, "no-receive-video", false, "do not receive video")
	flag.BoolVar(&rawDump, "raw-dump", false, "capture the selected encoded inputs")
	flag.UintVar(&rawDumpSeconds, "raw-dump-seconds", 10, "capture selected encoded inputs for this many seconds before continuing")
	flag.StringVar(&rawDumpCopyTo, "raw-dump-copy-to", "", "copy the stopped diagnostic ZIP before upload")
	flag.BoolVar(&uploadLogs, "upload-logs", false, "upload logs and the stopped raw dump attachment")
	flag.StringVar(&caseID, "case-id", "", "smoke.raw-dump-upload or integration.raw-dump-recovery")
	flag.Parse()
	if caseID != "" {
		if caseID != "smoke.raw-dump-upload" && caseID != "integration.raw-dump-recovery" {
			return clientConfig{}, fmt.Errorf("unknown --case-id %q", caseID)
		}
		rawDump, uploadLogs = true, true
	}
	if noReceiveAudio && audioStreamID.set {
		return clientConfig{}, errors.New("--no-receive-audio conflicts with --audio-stream-id")
	}
	if noReceiveVideo && len(videoStreamIDs) > 0 {
		return clientConfig{}, errors.New("--no-receive-video conflicts with --video-stream-id")
	}
	if !audioStreamID.set {
		audioStreamID.value = 10
	}
	if len(videoStreamIDs) == 0 && !noReceiveVideo {
		videoStreamIDs = append(videoStreamIDs, 11)
	}
	seen := make(map[uint]bool, len(videoStreamIDs))
	for _, streamID := range videoStreamIDs {
		if streamID > 15 || seen[streamID] {
			return clientConfig{}, errors.New("video stream IDs must be distinct values from 0 through 15")
		}
		seen[streamID] = true
	}
	if remoteID == "" || !filepath.IsAbs(cacheDir) || !filepath.IsAbs(outputDir) ||
		(!noReceiveAudio && audioStreamID.value > 15) || len(videoStreamIDs) > 3 || rawDumpSeconds == 0 || rawDumpSeconds > 300 ||
		(rawDumpCopyTo != "" && (!rawDump || !filepath.IsAbs(rawDumpCopyTo))) ||
		(!noReceiveAudio && seen[audioStreamID.value]) {
		return clientConfig{}, errors.New("--remote-id, absolute --cache-dir/--output-dir, optional audio, and up to three distinct 0..15 video stream IDs are required")
	}
	var resolvedAudioID *uint8
	if !noReceiveAudio {
		value := uint8(audioStreamID.value)
		resolvedAudioID = &value
	}
	resolvedVideoIDs := make([]uint8, len(videoStreamIDs))
	for index, value := range videoStreamIDs {
		resolvedVideoIDs[index] = uint8(value)
	}
	return clientConfig{
		endpoint: endpoint, remoteID: remoteID,
		cacheDir: filepath.Clean(cacheDir), outputDir: filepath.Clean(outputDir),
		audioStreamID: resolvedAudioID, videoStreamIDs: resolvedVideoIDs,
		rawDumpSeconds: rawDumpSeconds,
		rawDump:        rawDump, rawDumpCopyTo: rawDumpCopyTo, uploadLogs: uploadLogs, caseID: caseID,
	}, nil
}

func copyRawDump(sourcePath, destinationPath string) error {
	if !filepath.IsAbs(destinationPath) {
		return errors.New("--raw-dump-copy-to must be absolute")
	}
	if err := os.MkdirAll(filepath.Dir(destinationPath), 0o755); err != nil {
		return err
	}
	source, err := os.Open(sourcePath)
	if err != nil {
		return err
	}
	defer source.Close()
	destination, err := os.OpenFile(destinationPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(destination, source)
	closeErr := destination.Close()
	if copyErr != nil || closeErr != nil {
		_ = os.Remove(destinationPath)
	}
	return errors.Join(copyErr, closeErr)
}

func createAudioOutputs(frames *frameSignals, failures chan<- error) (*tirtc.AudioOutput, *tirtc.EncodedAudioOutput, error) {
	audio, err := tirtc.NewAudioOutput(tirtc.AudioOutputOptions{
		OnFrame: func(tirtc.AudioFrame) { frames.audio.notify() },
		OnError: outputErrorNotifier("decoded audio output", failures),
	})
	if err != nil {
		return nil, nil, err
	}
	encodedAudio, err := tirtc.NewEncodedAudioOutput(tirtc.EncodedAudioOutputOptions{
		OnFrame: func(tirtc.EncodedAudioFrame) { frames.encodedAudio.notify() },
		OnError: outputErrorNotifier("encoded audio output", failures),
	})
	if err != nil {
		_ = audio.Close()
		return nil, nil, err
	}
	return audio, encodedAudio, nil
}

func createVideoOutputs(streamID uint8, failures chan<- error) (videoOutputPair, error) {
	frames := newFrameSignals()
	video, err := tirtc.NewVideoOutput(tirtc.VideoOutputOptions{
		OnFrame: func(tirtc.VideoFrame) { frames.video.notify() },
		OnError: outputErrorNotifier(fmt.Sprintf("decoded video output %d", streamID), failures),
	})
	if err != nil {
		return videoOutputPair{}, err
	}
	encodedVideo, err := tirtc.NewEncodedVideoOutput(tirtc.EncodedVideoOutputOptions{
		OnFrame: func(frame tirtc.EncodedVideoFrame) {
			frames.encodedVideo.notify()
			if frame.KeyFrame {
				frames.encodedVideoKeyFrame.notify()
			}
		}, OnError: outputErrorNotifier(fmt.Sprintf("encoded video output %d", streamID), failures),
	})
	if err != nil {
		_ = video.Close()
		return videoOutputPair{}, err
	}
	return videoOutputPair{streamID: streamID, decoded: video, encoded: encodedVideo, frames: frames}, nil
}

func waitSelectedFrames(ctx context.Context, audioFrames *frameSignals, receiveAudio bool, videos []videoOutputPair, failures <-chan error) error {
	if receiveAudio {
		if err := waitFrameAfter(ctx, "decoded audio frame", audioFrames.audio, 0, failures); err != nil {
			return err
		}
		if err := waitFrameAfter(ctx, "encoded audio frame", audioFrames.encodedAudio, 0, failures); err != nil {
			return err
		}
	}
	for _, pair := range videos {
		if err := waitFrameAfter(ctx, fmt.Sprintf("decoded video frame stream %d", pair.streamID), pair.frames.video, 0, failures); err != nil {
			return err
		}
		if err := waitFrameAfter(ctx, fmt.Sprintf("encoded video frame stream %d", pair.streamID), pair.frames.encodedVideo, 0, failures); err != nil {
			return err
		}
	}
	return nil
}

func waitVideoRecordingFramesAfter(ctx context.Context, frames *frameSignals, baseline frameSnapshot, failures <-chan error) error {
	if err := waitFrameAfter(ctx, "decoded video frame", frames.video, baseline.video, failures); err != nil {
		return err
	}
	if err := waitFrameAfter(ctx, "encoded video key frame", frames.encodedVideoKeyFrame, baseline.encodedVideoKeyFrame, failures); err != nil {
		return err
	}
	return waitFrameAfter(ctx, "encoded video frame after key frame", frames.encodedVideo, frames.encodedVideo.count.Load(), failures)
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
