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
	"strconv"
	"strings"
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
	endpoint, cacheDir, outputDir string
	startTime, endTime            time.Time
	audioChannelID                *uint8
	videoChannelIDs               []uint8
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
	value.value, value.set = uint(parsed), true
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
	channelID uint8
	decoded   *storage.VideoOutput
	encoded   *storage.EncodedVideoOutput
	frames    *frameSignals
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
	appID := os.Getenv("TI_CLOUD_STORAGE_APP_ID")
	accessKeyID := os.Getenv("TI_CLOUD_STORAGE_ACCESS_KEY_ID")
	accessKeySecret := os.Getenv("TI_CLOUD_STORAGE_ACCESS_KEY_SECRET")
	deviceID := os.Getenv("TI_CLOUD_STORAGE_DEVICE_ID")
	if appID == "" || accessKeyID == "" || accessKeySecret == "" || deviceID == "" {
		return errors.New("TI_CLOUD_STORAGE_APP_ID, TI_CLOUD_STORAGE_ACCESS_KEY_ID, TI_CLOUD_STORAGE_ACCESS_KEY_SECRET, and TI_CLOUD_STORAGE_DEVICE_ID are required")
	}
	if err := os.MkdirAll(config.outputDir, 0o700); err != nil {
		return fmt.Errorf("prepare output directory: %w", err)
	}
	client, err := storage.NewClient(storage.ClientOptions{
		AppID: appID, AccessKeyID: accessKeyID, AccessKeySecret: accessKeySecret,
		CacheDir: config.cacheDir, Endpoint: config.endpoint,
	})
	if err != nil {
		return fmt.Errorf("initialize Ti Cloud Storage: %w", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, operationTimeout)
	defer cancel()

	var replay *storage.Replay
	var audio *storage.AudioOutput
	var encodedAudio *storage.EncodedAudioOutput
	var videos []videoOutputPair
	cleaned := false
	cleanup := func() error {
		if cleaned {
			return nil
		}
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cleanupCancel()
		var cleanupErrors []error
		for index := len(videos) - 1; index >= 0; index-- {
			for _, closeResource := range []func() error{videos[index].encoded.Close, videos[index].decoded.Close} {
				cleanupErrors = append(cleanupErrors, closeEventually(cleanupCtx, closeResource))
			}
		}
		for _, closeResource := range []func() error{closeFunction(encodedAudio), closeFunction(audio)} {
			if closeResource != nil {
				cleanupErrors = append(cleanupErrors, closeEventually(cleanupCtx, closeResource))
			}
		}
		if replay != nil {
			cleanupErrors = append(cleanupErrors, closeEventually(cleanupCtx, replay.Close))
		}
		cleanupErrors = append(cleanupErrors, closeEventually(cleanupCtx, client.Close))
		err := errors.Join(cleanupErrors...)
		cleaned = err == nil
		return err
	}
	defer func() { _ = cleanup() }()

	location, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		return err
	}
	startDate := config.startTime.In(location).Format(time.DateOnly)
	endDate := config.endTime.In(location).Format(time.DateOnly)
	if _, err := client.ListRecordingDays(ctx, deviceID, startDate, endDate); err != nil {
		return fmt.Errorf("list recording days: %w", err)
	}
	ranges, err := client.ListRecordings(ctx, deviceID, config.startTime, config.endTime)
	if err != nil {
		return fmt.Errorf("list recording ranges: %w", err)
	}
	ordered := newestFirstRecordingRanges(ranges)
	if len(ordered) == 0 {
		return errors.New("no recording is available in the requested window")
	}
	selected := ordered[0]
	if config.audioChannelID == nil && len(config.videoChannelIDs) == 0 {
		fmt.Println("recording query completed; no media selected")
		return cleanup()
	}

	terminal := make(chan error, 1)
	failures := make(chan error, 16)
	audioFrames := newFrameSignals()
	replay, err = client.NewReplay(deviceID, storage.ReplayOptions{
		OnCompleted: func() { notifyTerminal(terminal, nil) },
		OnError: func(err error) {
			notifyError(failures, err)
			notifyTerminal(terminal, err)
		},
		OnRecordingGap: func(gap storage.RecordingGap) {
			fmt.Printf("replay gap %s..%s tracks=%v reasons=%v\n", gap.Range.StartTime, gap.Range.EndTime, gap.Tracks, gap.Reasons)
		},
	})
	if err != nil {
		return fmt.Errorf("create replay: %w", err)
	}
	if config.audioChannelID != nil {
		audio, encodedAudio, err = createAudioOutputs(audioFrames, failures)
		if err != nil {
			return err
		}
		if err := audio.Attach(replay, *config.audioChannelID); err != nil {
			return fmt.Errorf("attach decoded audio: %w", err)
		}
		if err := encodedAudio.Attach(replay, *config.audioChannelID); err != nil {
			return fmt.Errorf("attach encoded audio: %w", err)
		}
	}
	for _, channelID := range config.videoChannelIDs {
		pair, createErr := createVideoOutputs(channelID, failures)
		if createErr != nil {
			return createErr
		}
		videos = append(videos, pair)
		if err := pair.decoded.Attach(replay, channelID); err != nil {
			return fmt.Errorf("attach decoded video %d: %w", channelID, err)
		}
		if err := pair.encoded.Attach(replay, channelID); err != nil {
			return fmt.Errorf("attach encoded video %d: %w", channelID, err)
		}
	}
	if err := replay.Play(selected.StartTime, selected.EndTime); err != nil {
		return fmt.Errorf("play replay: %w", err)
	}
	if err := waitSelectedFrames(ctx, audioFrames, config.audioChannelID != nil, videos, failures); err != nil {
		return err
	}
	if err := replay.Pause(); err != nil {
		return fmt.Errorf("pause replay: %w", err)
	}
	if err := replay.Resume(); err != nil {
		return fmt.Errorf("resume replay: %w", err)
	}
	for _, pair := range videos {
		recording, startErr := replay.StartRecording(storage.StartRecordingOptions{
			VideoChannelID: pair.channelID, AudioChannelID: config.audioChannelID,
		})
		if startErr != nil {
			return fmt.Errorf("start replay recording channel %d: %w", pair.channelID, startErr)
		}
		baseline := pair.frames.snapshot()
		if waitErr := waitVideoRecordingFramesAfter(ctx, pair.frames, baseline, failures); waitErr != nil {
			file, stopErr := recording.Stop()
			if file.Path != "" {
				stopErr = errors.Join(stopErr, file.Delete())
			}
			return fmt.Errorf("wait for channel %d recording frames: %w", pair.channelID, errors.Join(waitErr, stopErr))
		}
		replayRecording, stopErr := recording.Stop()
		if stopErr != nil {
			if replayRecording.Path != "" {
				stopErr = errors.Join(stopErr, replayRecording.Delete())
			}
			return fmt.Errorf("stop replay recording channel %d: %w", pair.channelID, stopErr)
		}
		if saveErr := saveTemporaryMedia(replayRecording.Path, filepath.Join(config.outputDir, fmt.Sprintf("ti-cloud-storage-replay-recording-channel-%d.mp4", pair.channelID)), []byte("ftyp"), 4); saveErr != nil {
			return errors.Join(saveErr, replayRecording.Delete())
		}
		if deleteErr := replayRecording.Delete(); deleteErr != nil {
			return fmt.Errorf("delete temporary replay recording: %w", deleteErr)
		}
		snapshot, snapshotErr := takeSnapshotWhenReady(ctx, pair.decoded.TakeSnapshot, pair.frames.video, failures)
		if snapshotErr != nil {
			return fmt.Errorf("take channel %d snapshot: %w", pair.channelID, snapshotErr)
		}
		if saveErr := saveTemporaryMedia(snapshot.Path, filepath.Join(config.outputDir, fmt.Sprintf("ti-cloud-storage-snapshot-channel-%d.jpg", pair.channelID)), []byte{0xff, 0xd8}, 0); saveErr != nil {
			return errors.Join(saveErr, snapshot.Delete())
		}
		if deleteErr := snapshot.Delete(); deleteErr != nil {
			return fmt.Errorf("delete temporary snapshot: %w", deleteErr)
		}
		fmt.Printf("consumed video channel %d\n", pair.channelID)
	}
	// The headless callback output proves decoded audio delivery. Detach it before
	// playback-rate verification so the decoded video self-clock owns cadence.
	if audio != nil && len(videos) > 0 {
		if err := audio.Detach(); err != nil {
			return fmt.Errorf("detach decoded audio before playback-rate verification: %w", err)
		}
	}
	seekTarget := selected.StartTime.Add(selected.EndTime.Sub(selected.StartTime) / 5)
	if err := replay.Seek(seekTarget); err != nil {
		return fmt.Errorf("seek replay: %w", err)
	}
	progressFrames := audioFrames.audio
	progressName := "audio"
	if len(videos) > 0 {
		progressFrames = videos[0].frames.video
		progressName = fmt.Sprintf("video channel %d", videos[0].channelID)
	}
	slowPlaybackBaseline := progressFrames.count.Load()
	if err := replay.SetSpeed(storage.ReplaySpeed0_5x); err != nil {
		return fmt.Errorf("set replay speed: %w", err)
	}
	if replay.Speed() != storage.ReplaySpeed0_5x {
		return errors.New("replay speed cache did not update")
	}
	if err := waitFrameAfter(
		ctx, "wait for slow playback "+progressName, progressFrames, slowPlaybackBaseline, failures,
	); err != nil {
		return err
	}
	normalPlaybackBaseline := progressFrames.count.Load()
	if err := replay.SetSpeed(storage.ReplaySpeed1x); err != nil {
		return fmt.Errorf("restore replay speed: %w", err)
	}
	if replay.Speed() != storage.ReplaySpeed1x {
		return errors.New("replay speed cache did not restore")
	}
	if err := waitFrameAfter(
		ctx, "wait for restored playback "+progressName, progressFrames, normalPlaybackBaseline, failures,
	); err != nil {
		return err
	}
	if _, _, err := replay.CurrentTime(); err != nil {
		return fmt.Errorf("read replay time: %w", err)
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

	if len(videos) == 0 {
		return cleanup()
	}
	var retainedReport storage.ExportReport
	for index, pair := range videos {
		exportTask, exportErr := client.ExportRecording(ctx, deviceID, storage.ExportOptions{
			StartTime: selected.StartTime, EndTime: selected.EndTime,
			VideoChannelID: pair.channelID, AudioChannelID: config.audioChannelID,
			OnProgress: func(progress storage.ExportProgress) {
				fmt.Printf("export channel=%d progress %.3f covered=%s\n", pair.channelID, progress.Fraction, progress.CoveredDuration)
			},
			OnRecordingGap: func(gap storage.RecordingGap) {
				fmt.Printf("export channel=%d gap %s..%s tracks=%v reasons=%v\n", pair.channelID, gap.Range.StartTime, gap.Range.EndTime, gap.Tracks, gap.Reasons)
			},
		})
		if exportErr != nil {
			return fmt.Errorf("start channel %d range export: %w", pair.channelID, exportErr)
		}
		exported, waitErr := exportTask.Wait()
		fmt.Printf("export channel=%d report complete=%t termination=%d covered=%s gaps=%d unprocessed=%d cause=%v\n",
			pair.channelID, exported.Report.Complete, exported.Report.Termination, exported.Report.CoveredDuration,
			len(exported.Report.Gaps), len(exported.Report.UnprocessedRanges), exported.Report.Cause)
		if waitErr != nil {
			if exported.File != nil {
				waitErr = errors.Join(waitErr, exported.File.Delete())
			}
			return fmt.Errorf("export channel %d recording range: %w", pair.channelID, waitErr)
		}
		if progress := exportTask.Progress().Fraction; progress < 0 || progress > 1 || (exported.Report.Complete && progress != 1) {
			progressErr := fmt.Errorf("export channel %d returned inconsistent progress %.3f (complete=%t)", pair.channelID, progress, exported.Report.Complete)
			if exported.File != nil {
				progressErr = errors.Join(progressErr, exported.File.Delete())
			}
			return progressErr
		}
		if exported.File == nil {
			return fmt.Errorf("successful channel %d export returned no file", pair.channelID)
		}
		if saveErr := saveTemporaryMedia(exported.File.Path, filepath.Join(config.outputDir, fmt.Sprintf("ti-cloud-storage-range-export-channel-%d.mp4", pair.channelID)), []byte("ftyp"), 4); saveErr != nil {
			return errors.Join(saveErr, exported.File.Delete())
		}
		if deleteErr := exported.File.Delete(); deleteErr != nil {
			return fmt.Errorf("delete temporary range export: %w", deleteErr)
		}
		if index == 0 {
			retainedReport = exported.Report
		}
	}
	retainedRange, available := coveredExportRange(retainedReport)
	if !available {
		return cleanup()
	}

	// Select at most five seconds confirmed by the public report, even for partial output.
	// Collect this completed task only after Client.Close; check its own report again.
	completed := make(chan struct{}, 1)
	retainedTask, err := client.ExportRecording(ctx, deviceID, storage.ExportOptions{
		StartTime: retainedRange.StartTime, EndTime: retainedRange.EndTime,
		VideoChannelID: videos[0].channelID, AudioChannelID: config.audioChannelID,
		OnProgress: func(progress storage.ExportProgress) {
			if progress.Fraction == 1 {
				select {
				case completed <- struct{}{}:
				default:
				}
			}
		},
	})
	if err != nil {
		return fmt.Errorf("start retained export: %w", err)
	}
	select {
	case <-completed:
	case <-ctx.Done():
		cancelErr := retainedTask.Cancel()
		partial, waitErr := retainedTask.Wait()
		if partial.File != nil {
			waitErr = errors.Join(waitErr, partial.File.Delete())
		}
		return fmt.Errorf("wait for retained export completion: %w", errors.Join(ctx.Err(), cancelErr, waitErr))
	}
	if err := cleanup(); err != nil {
		cancelErr := retainedTask.Cancel()
		partial, waitErr := retainedTask.Wait()
		if partial.File != nil {
			waitErr = errors.Join(waitErr, partial.File.Delete())
		}
		return errors.Join(err, cancelErr, waitErr)
	}
	retained, err := retainedTask.Wait()
	if err != nil || retained.File == nil || !retained.Report.Complete {
		if retained.File != nil {
			err = errors.Join(err, retained.File.Delete())
		}
		return fmt.Errorf("collect completed export after client close: %w",
			errors.Join(err, errors.New("complete MP4 required")))
	}
	if err := saveTemporaryMedia(retained.File.Path,
		filepath.Join(config.outputDir, fmt.Sprintf("ti-cloud-storage-export-after-close-channel-%d.mp4", videos[0].channelID)), []byte("ftyp"), 4); err != nil {
		return errors.Join(err, retained.File.Delete())
	}
	copied, err := retainedTask.Wait()
	if err != nil || copied.File == nil || copied.File.Path != retained.File.Path {
		err = errors.Join(err, retained.File.Delete())
		if copied.File != nil && copied.File.Path != retained.File.Path {
			err = errors.Join(err, copied.File.Delete())
		}
		return errors.Join(errors.New("repeated Wait changed the completed export file"), err)
	}
	if err := retained.File.Delete(); err != nil {
		return fmt.Errorf("delete export after client close: %w", err)
	}
	if err := copied.File.Delete(); err != nil {
		return fmt.Errorf("delete copied export result: %w", err)
	}
	fmt.Println("completed export collected, saved and deleted after client close")
	return nil
}

// Choose from published segments, excluding every reported selected-track gap.
func coveredExportRange(report storage.ExportReport) (storage.RecordingRange, bool) {
	var best storage.RecordingRange
	consider := func(start, end time.Time) {
		if end.After(start.Add(5 * time.Second)) {
			end = start.Add(5 * time.Second)
		}
		if end.Sub(start) > best.EndTime.Sub(best.StartTime) {
			best = storage.RecordingRange{StartTime: start, EndTime: end}
		}
	}
	gapIndex := 0
	for _, segment := range report.Segments {
		start, end := segment.SourceRange.StartTime, segment.SourceRange.EndTime
		if start.Before(report.RequestedRange.StartTime) {
			start = report.RequestedRange.StartTime
		}
		if end.After(report.RequestedRange.EndTime) {
			end = report.RequestedRange.EndTime
		}
		for gapIndex < len(report.Gaps) && !report.Gaps[gapIndex].Range.EndTime.After(start) {
			gapIndex++
		}
		for i := gapIndex; i < len(report.Gaps) && report.Gaps[i].Range.StartTime.Before(end); i++ {
			gap := report.Gaps[i].Range
			if gap.StartTime.After(start) {
				consider(start, gap.StartTime)
			}
			if gap.EndTime.After(start) {
				start = gap.EndTime
			}
		}
		consider(start, end)
		if best.EndTime.Sub(best.StartTime) == 5*time.Second {
			return best, true
		}
	}
	return best, best.EndTime.After(best.StartTime)
}

func parseConfig() (cloudStorageConfig, error) {
	var endpoint, cacheDir, outputDir string
	var startMS, endMS int64
	var audioChannelID optionalUintFlag
	var videoChannelIDs uintListFlag
	var noReceiveAudio, noReceiveVideo bool
	flag.StringVar(&endpoint, "endpoint", "", "Ti Cloud Storage endpoint")
	flag.StringVar(&cacheDir, "cache-dir", "", "absolute writable SDK work directory")
	flag.StringVar(&outputDir, "output-dir", "", "absolute application-owned output directory")
	flag.Int64Var(&startMS, "start-ms", -1, "recording query start time in Unix milliseconds")
	flag.Int64Var(&endMS, "end-ms", -1, "recording query end time in Unix milliseconds")
	flag.Var(&audioChannelID, "audio-channel-id", "recorded audio channel ID")
	flag.Var(&videoChannelIDs, "video-channel-id", "recorded video channel ID; repeat up to three times")
	flag.BoolVar(&noReceiveAudio, "no-receive-audio", false, "do not consume audio")
	flag.BoolVar(&noReceiveVideo, "no-receive-video", false, "do not consume video")
	flag.Parse()
	if noReceiveAudio && audioChannelID.set {
		return cloudStorageConfig{}, errors.New("--no-receive-audio conflicts with --audio-channel-id")
	}
	if noReceiveVideo && len(videoChannelIDs) > 0 {
		return cloudStorageConfig{}, errors.New("--no-receive-video conflicts with --video-channel-id")
	}
	if !audioChannelID.set {
		audioChannelID.value = 0
	}
	if len(videoChannelIDs) == 0 && !noReceiveVideo {
		videoChannelIDs = append(videoChannelIDs, 1)
	}
	seen := make(map[uint]bool, len(videoChannelIDs))
	for _, channelID := range videoChannelIDs {
		if channelID > 255 || seen[channelID] {
			return cloudStorageConfig{}, errors.New("video channel IDs must be distinct values from 0 through 255")
		}
		seen[channelID] = true
	}
	if !filepath.IsAbs(cacheDir) || !filepath.IsAbs(outputDir) || startMS < 0 || startMS >= endMS ||
		(!noReceiveAudio && audioChannelID.value > 255) || len(videoChannelIDs) > 3 {
		return cloudStorageConfig{}, errors.New("absolute --cache-dir/--output-dir, a valid --start-ms/--end-ms window, optional audio, and up to three distinct 0..255 video channel IDs are required")
	}
	var resolvedAudioID *uint8
	if !noReceiveAudio {
		value := uint8(audioChannelID.value)
		resolvedAudioID = &value
	}
	resolvedVideoIDs := make([]uint8, len(videoChannelIDs))
	for index, value := range videoChannelIDs {
		resolvedVideoIDs[index] = uint8(value)
	}
	return cloudStorageConfig{
		endpoint: endpoint, cacheDir: filepath.Clean(cacheDir), outputDir: filepath.Clean(outputDir),
		startTime: time.UnixMilli(startMS).UTC(), endTime: time.UnixMilli(endMS).UTC(),
		audioChannelID: resolvedAudioID, videoChannelIDs: resolvedVideoIDs,
	}, nil
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

func createAudioOutputs(frames *frameSignals, failures chan<- error) (*storage.AudioOutput, *storage.EncodedAudioOutput, error) {
	onError := func(err error) { notifyError(failures, err) }
	audio, err := storage.NewAudioOutput(storage.AudioOutputOptions{OnFrame: func(storage.AudioFrame) { frames.audio.notify() }, OnError: onError})
	if err != nil {
		return nil, nil, err
	}
	encodedAudio, err := storage.NewEncodedAudioOutput(storage.EncodedAudioOutputOptions{OnFrame: func(storage.EncodedAudioFrame) { frames.encodedAudio.notify() }, OnError: onError})
	if err != nil {
		_ = audio.Close()
		return nil, nil, err
	}
	return audio, encodedAudio, nil
}

func createVideoOutputs(channelID uint8, failures chan<- error) (videoOutputPair, error) {
	frames := newFrameSignals()
	onError := func(err error) { notifyError(failures, fmt.Errorf("video channel %d: %w", channelID, err)) }
	video, err := storage.NewVideoOutput(storage.VideoOutputOptions{OnFrame: func(storage.VideoFrame) { frames.video.notify() }, OnError: onError})
	if err != nil {
		return videoOutputPair{}, err
	}
	encodedVideo, err := storage.NewEncodedVideoOutput(storage.EncodedVideoOutputOptions{OnFrame: func(frame storage.EncodedVideoFrame) {
		frames.encodedVideo.notify()
		if frame.KeyFrame {
			frames.encodedVideoKeyFrame.notify()
		}
	}, OnError: onError})
	if err != nil {
		_ = video.Close()
		return videoOutputPair{}, err
	}
	return videoOutputPair{channelID: channelID, decoded: video, encoded: encodedVideo, frames: frames}, nil
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
		if err := waitFrameAfter(ctx, fmt.Sprintf("decoded video frame channel %d", pair.channelID), pair.frames.video, 0, failures); err != nil {
			return err
		}
		if err := waitFrameAfter(ctx, fmt.Sprintf("encoded video frame channel %d", pair.channelID), pair.frames.encodedVideo, 0, failures); err != nil {
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
