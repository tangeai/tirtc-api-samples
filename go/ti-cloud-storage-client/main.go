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
	"sort"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/tangeai/tirtc-client-go/v2/storage"
)

const (
	maximumMediaFileSize = int64(512 << 20)
	operationTimeout     = 3 * time.Minute
)

type cloudStorageConfig struct {
	endpoint, cacheDir, outputDir  string
	startTime, endTime             time.Time
	audioChannelID, videoChannelID uint8
}

type frameSignals struct {
	audio, video, encodedAudio, encodedVideo, encodedVideoKeyFrame *frameSignal
}

type frameSignal struct {
	count atomic.Uint64
	ready chan struct{}
}

type frameSnapshot struct {
	audio, video, encodedAudio, encodedVideo, encodedVideoKeyFrame uint64
}

func newFrameSignals() *frameSignals {
	return &frameSignals{
		audio: newFrameSignal(), video: newFrameSignal(),
		encodedAudio: newFrameSignal(), encodedVideo: newFrameSignal(),
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
		audio: s.audio.count.Load(), video: s.video.count.Load(),
		encodedAudio: s.encodedAudio.count.Load(), encodedVideo: s.encodedVideo.count.Load(),
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
	appID, token := os.Getenv("TI_CLOUD_STORAGE_APP_ID"), os.Getenv("TI_CLOUD_STORAGE_ACCESS_TOKEN")
	if appID == "" || token == "" {
		return errors.New("TI_CLOUD_STORAGE_APP_ID and TI_CLOUD_STORAGE_ACCESS_TOKEN are required")
	}
	if err := os.MkdirAll(config.outputDir, 0o700); err != nil {
		return fmt.Errorf("prepare output directory: %w", err)
	}
	if err := storage.Init(storage.InitOptions{AppID: appID, CacheDir: config.cacheDir, Endpoint: config.endpoint}); err != nil {
		return fmt.Errorf("initialize Ti Cloud Storage: %w", err)
	}
	cloudStorage, err := storage.New(token)
	if err != nil {
		_ = storage.Shutdown()
		return fmt.Errorf("create cloudStorage: %w", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()

	var replay *storage.Replay
	var audio *storage.AudioOutput
	var video *storage.VideoOutput
	var encodedAudio *storage.EncodedAudioOutput
	var encodedVideo *storage.EncodedVideoOutput
	cleaned := false
	cleanup := func() error {
		if cleaned {
			return nil
		}
		cleaned = true
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cleanupCancel()
		var cleanupErrors []error
		for _, closeResource := range []func() error{
			closeFunction(encodedVideo), closeFunction(encodedAudio), closeFunction(video), closeFunction(audio),
		} {
			if closeResource != nil {
				cleanupErrors = append(cleanupErrors, closeEventually(cleanupCtx, closeResource))
			}
		}
		if replay != nil {
			cleanupErrors = append(cleanupErrors, closeEventually(cleanupCtx, replay.Close))
		}
		cleanupErrors = append(cleanupErrors, closeEventually(cleanupCtx, cloudStorage.Close), storage.Shutdown())
		return errors.Join(cleanupErrors...)
	}
	defer func() { _ = cleanup() }()

	location, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		return err
	}
	startDate := config.startTime.In(location).Format(time.DateOnly)
	endDate := config.endTime.In(location).Format(time.DateOnly)
	if _, err := listDaysWithTokenRetry(ctx, cloudStorage, startDate, endDate); err != nil {
		return fmt.Errorf("list recording days: %w", err)
	}
	ranges, err := listRangesWithTokenRetry(ctx, cloudStorage, config.startTime, config.endTime)
	if err != nil {
		return fmt.Errorf("list recording ranges: %w", err)
	}
	ordered := newestFirstRecordingRanges(ranges)
	if len(ordered) == 0 {
		return errors.New("no recording is available in the requested window")
	}
	selected := ordered[0]

	terminal := make(chan error, 1)
	failures := make(chan error, 16)
	frames := newFrameSignals()
	replay, err = cloudStorage.NewReplay(storage.ReplayOptions{
		OnCompleted: func() { notifyTerminal(terminal, nil) },
		OnError:     func(err error) { notifyTerminal(terminal, err) },
	})
	if err != nil {
		return fmt.Errorf("create replay: %w", err)
	}
	audio, video, encodedAudio, encodedVideo, err = createOutputs(frames, failures)
	if err != nil {
		return err
	}
	for name, attach := range map[string]func() error{
		"decoded audio": func() error { return audio.Attach(replay, config.audioChannelID) },
		"decoded video": func() error { return video.Attach(replay, config.videoChannelID) },
		"encoded audio": func() error { return encodedAudio.Attach(replay, config.audioChannelID) },
		"encoded video": func() error { return encodedVideo.Attach(replay, config.videoChannelID) },
	} {
		if err := attach(); err != nil {
			return fmt.Errorf("attach %s: %w", name, err)
		}
	}
	if err := replay.Play(selected.StartTime, selected.EndTime); err != nil {
		return fmt.Errorf("play replay: %w", err)
	}
	if err := waitFrames(ctx, frames, failures); err != nil {
		return err
	}
	if err := replay.Pause(); err != nil {
		return fmt.Errorf("pause replay: %w", err)
	}
	if err := replay.Resume(); err != nil {
		return fmt.Errorf("resume replay: %w", err)
	}
	audioID := config.audioChannelID
	recording, err := replay.StartRecording(storage.StartRecordingOptions{
		VideoChannelID: config.videoChannelID, AudioChannelID: &audioID,
	})
	if err != nil {
		return fmt.Errorf("start replay recording: %w", err)
	}
	postRecordingBaseline := frames.snapshot()
	if err := waitRecordingFramesAfter(ctx, frames, postRecordingBaseline, failures); err != nil {
		_, _ = recording.Stop()
		return fmt.Errorf("wait for post-recording frames: %w", err)
	}
	replayRecording, err := recording.Stop()
	if err != nil {
		return fmt.Errorf("stop replay recording: %w", err)
	}
	if err := saveTemporaryMedia(replayRecording.Path, filepath.Join(config.outputDir, "ti-cloud-storage-replay-recording.mp4"), []byte("ftyp"), 4); err != nil {
		return err
	}
	if err := replayRecording.Delete(); err != nil {
		return fmt.Errorf("delete temporary replay recording: %w", err)
	}
	// The headless callback output proves decoded audio delivery. Detach it before
	// playback-rate verification so the decoded video self-clock owns cadence.
	if err := audio.Detach(); err != nil {
		return fmt.Errorf("detach decoded audio before playback-rate verification: %w", err)
	}
	seekTarget := selected.StartTime.Add(selected.EndTime.Sub(selected.StartTime) / 5)
	if err := replay.Seek(seekTarget); err != nil {
		return fmt.Errorf("seek replay: %w", err)
	}
	slowPlaybackBaseline := frames.video.count.Load()
	if err := replay.SetSpeed(storage.ReplaySpeed0_5x); err != nil {
		return fmt.Errorf("set replay speed: %w", err)
	}
	if replay.Speed() != storage.ReplaySpeed0_5x {
		return errors.New("replay speed cache did not update")
	}
	if err := waitFrameAfter(
		ctx, "wait for slow playback video", frames.video, slowPlaybackBaseline, failures,
	); err != nil {
		return err
	}
	normalPlaybackBaseline := frames.video.count.Load()
	if err := replay.SetSpeed(storage.ReplaySpeed1x); err != nil {
		return fmt.Errorf("restore replay speed: %w", err)
	}
	if replay.Speed() != storage.ReplaySpeed1x {
		return errors.New("replay speed cache did not restore")
	}
	if err := waitFrameAfter(
		ctx, "wait for restored playback video", frames.video, normalPlaybackBaseline, failures,
	); err != nil {
		return err
	}
	if _, _, err := replay.CurrentTime(); err != nil {
		return fmt.Errorf("read replay time: %w", err)
	}

	snapshot, err := takeSnapshotWhenReady(ctx, video.TakeSnapshot, frames.video, failures)
	if err != nil {
		return fmt.Errorf("take snapshot: %w", err)
	}
	if err := saveTemporaryMedia(snapshot.Path, filepath.Join(config.outputDir, "ti-cloud-storage-snapshot.jpg"), []byte{0xff, 0xd8}, 0); err != nil {
		return err
	}
	if err := snapshot.Delete(); err != nil {
		return fmt.Errorf("delete temporary snapshot: %w", err)
	}

	if err := waitReplayTerminal(ctx, terminal, failures); err != nil {
		if errors.Is(err, context.DeadlineExceeded) {
			currentTime, present, currentTimeErr := replay.CurrentTime()
			if currentTimeErr == nil && present {
				return fmt.Errorf(
					"%w (source progress %s of %s)", err,
					currentTime.Sub(selected.StartTime), selected.EndTime.Sub(selected.StartTime),
				)
			}
		}
		return err
	}

	exportTask, err := cloudStorage.ExportRecording(storage.ExportOptions{
		StartTime: selected.StartTime, EndTime: selected.EndTime,
		VideoChannelID: config.videoChannelID, AudioChannelID: &audioID,
	})
	if err != nil {
		return fmt.Errorf("start range export: %w", err)
	}
	exported, err := waitExport(ctx, exportTask)
	if err != nil {
		return fmt.Errorf("export recording range: %w", err)
	}
	if exportTask.Progress() != 1 {
		return fmt.Errorf("export completed with progress %.3f", exportTask.Progress())
	}
	if err := saveTemporaryMedia(exported.Path, filepath.Join(config.outputDir, "ti-cloud-storage-range-export.mp4"), []byte("ftyp"), 4); err != nil {
		return err
	}
	if err := exported.Delete(); err != nil {
		return fmt.Errorf("delete temporary range export: %w", err)
	}
	return cleanup()
}

func parseConfig() (cloudStorageConfig, error) {
	var endpoint, cacheDir, outputDir string
	var startMS, endMS int64
	var audioChannelID, videoChannelID uint
	flag.StringVar(&endpoint, "endpoint", "", "Ti Cloud Storage endpoint")
	flag.StringVar(&cacheDir, "cache-dir", "", "absolute writable SDK work directory")
	flag.StringVar(&outputDir, "output-dir", "", "absolute application-owned output directory")
	flag.Int64Var(&startMS, "start-ms", -1, "recording query start time in Unix milliseconds")
	flag.Int64Var(&endMS, "end-ms", -1, "recording query end time in Unix milliseconds")
	flag.UintVar(&audioChannelID, "audio-channel-id", 0, "recorded audio channel ID")
	flag.UintVar(&videoChannelID, "video-channel-id", 1, "recorded video channel ID")
	flag.Parse()
	if !filepath.IsAbs(cacheDir) || !filepath.IsAbs(outputDir) || startMS < 0 || startMS >= endMS ||
		audioChannelID > 255 || videoChannelID > 255 || audioChannelID == videoChannelID {
		return cloudStorageConfig{}, errors.New("absolute --cache-dir/--output-dir, a valid --start-ms/--end-ms window, and distinct 0..255 channel IDs are required")
	}
	return cloudStorageConfig{
		endpoint: endpoint, cacheDir: filepath.Clean(cacheDir), outputDir: filepath.Clean(outputDir),
		startTime: time.UnixMilli(startMS).UTC(), endTime: time.UnixMilli(endMS).UTC(),
		audioChannelID: uint8(audioChannelID), videoChannelID: uint8(videoChannelID),
	}, nil
}

func listDaysWithTokenRetry(ctx context.Context, cloudStorage *storage.CloudStorage, startDate, endDate string) ([]storage.RecordingDay, error) {
	days, err := cloudStorage.ListRecordingDays(ctx, startDate, endDate)
	if !errors.Is(err, storage.ErrTokenExpired) {
		return days, err
	}
	if err := refreshToken(cloudStorage); err != nil {
		return nil, err
	}
	return cloudStorage.ListRecordingDays(ctx, startDate, endDate)
}

func listRangesWithTokenRetry(ctx context.Context, cloudStorage *storage.CloudStorage, startTime, endTime time.Time) ([]storage.RecordingRange, error) {
	ranges, err := cloudStorage.ListRecordings(ctx, startTime, endTime)
	if !errors.Is(err, storage.ErrTokenExpired) {
		return ranges, err
	}
	if err := refreshToken(cloudStorage); err != nil {
		return nil, err
	}
	return cloudStorage.ListRecordings(ctx, startTime, endTime)
}

func refreshToken(cloudStorage *storage.CloudStorage) error {
	refreshed := os.Getenv("TI_CLOUD_STORAGE_REFRESHED_ACCESS_TOKEN")
	if refreshed == "" {
		return errors.New("operation returned ErrTokenExpired; set TI_CLOUD_STORAGE_REFRESHED_ACCESS_TOKEN and retry")
	}
	if err := cloudStorage.UpdateToken(refreshed); err != nil {
		return fmt.Errorf("update expired token: %w", err)
	}
	return nil
}

func newestFirstRecordingRanges(input []storage.RecordingRange) []storage.RecordingRange {
	result := append([]storage.RecordingRange(nil), input...)
	sort.Slice(result, func(left, right int) bool {
		if result[left].EndTime.Equal(result[right].EndTime) {
			return result[left].StartTime.After(result[right].StartTime)
		}
		return result[left].EndTime.After(result[right].EndTime)
	})
	return result
}

func createOutputs(frames *frameSignals, failures chan<- error) (*storage.AudioOutput, *storage.VideoOutput, *storage.EncodedAudioOutput, *storage.EncodedVideoOutput, error) {
	onError := func(err error) { notifyError(failures, err) }
	audio, err := storage.NewAudioOutput(storage.AudioOutputOptions{OnFrame: func(storage.AudioFrame) { frames.audio.notify() }, OnError: onError})
	if err != nil {
		return nil, nil, nil, nil, err
	}
	video, err := storage.NewVideoOutput(storage.VideoOutputOptions{OnFrame: func(storage.VideoFrame) { frames.video.notify() }, OnError: onError})
	if err != nil {
		_ = audio.Close()
		return nil, nil, nil, nil, err
	}
	encodedAudio, err := storage.NewEncodedAudioOutput(storage.EncodedAudioOutputOptions{OnFrame: func(storage.EncodedAudioFrame) { frames.encodedAudio.notify() }, OnError: onError})
	if err != nil {
		_ = video.Close()
		_ = audio.Close()
		return nil, nil, nil, nil, err
	}
	encodedVideo, err := storage.NewEncodedVideoOutput(storage.EncodedVideoOutputOptions{OnFrame: func(frame storage.EncodedVideoFrame) {
		frames.encodedVideo.notify()
		if frame.KeyFrame {
			frames.encodedVideoKeyFrame.notify()
		}
	}, OnError: onError})
	if err != nil {
		_ = encodedAudio.Close()
		_ = video.Close()
		_ = audio.Close()
		return nil, nil, nil, nil, err
	}
	return audio, video, encodedAudio, encodedVideo, nil
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
		select {
		case <-signal.ready:
		case err := <-failures:
			return fmt.Errorf("%s failed: %w", name, err)
		case <-ctx.Done():
			return fmt.Errorf("%s: %w", name, ctx.Err())
		}
	}
	return nil
}

func takeSnapshotWhenReady(
	ctx context.Context,
	take func() (storage.SnapshotFile, error),
	videoFrames *frameSignal,
	failures <-chan error,
) (storage.SnapshotFile, error) {
	for {
		baseline := videoFrames.count.Load()
		snapshot, err := take()
		if !errors.Is(err, storage.ErrNoFrame) {
			return snapshot, err
		}
		if err := waitFrameAfter(ctx, "wait for snapshot frame", videoFrames, baseline, failures); err != nil {
			return storage.SnapshotFile{}, err
		}
	}
}

func waitReplayTerminal(ctx context.Context, terminal <-chan error, failures <-chan error) error {
	select {
	case err := <-terminal:
		if err != nil {
			return fmt.Errorf("replay failed: %w", err)
		}
		return nil
	case err := <-failures:
		return fmt.Errorf("replay output failed: %w", err)
	case <-ctx.Done():
		return fmt.Errorf("wait for replay completion: %w", ctx.Err())
	}
}

func waitExport(ctx context.Context, task *storage.ExportTask) (storage.RecordingFile, error) {
	type result struct {
		file storage.RecordingFile
		err  error
	}
	done := make(chan result, 1)
	go func() {
		file, err := task.Wait()
		done <- result{file, err}
	}()
	select {
	case result := <-done:
		return result.file, result.err
	case <-ctx.Done():
		file, err := task.Stop()
		return file, errors.Join(ctx.Err(), err)
	}
}

type closeable interface{ Close() error }

func closeFunction(resource closeable) func() error {
	if resource == nil {
		return nil
	}
	return resource.Close
}

func closeEventually(ctx context.Context, closeResource func() error) error {
	ticker := time.NewTicker(5 * time.Millisecond)
	defer ticker.Stop()
	for {
		err := closeResource()
		if !errors.Is(err, storage.ErrInUse) {
			return err
		}
		select {
		case <-ticker.C:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
}

func notifyTerminal(target chan<- error, err error) {
	select {
	case target <- err:
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
