package com.tange.ai.tirtc.example;

import com.tange.ai.tirtc.*;
import com.tange.ai.tirtc.storage.*;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import static com.tange.ai.tirtc.example.RtcExample.*;

/** Cloud recording query, Replay and independent Export through the public SDK. */
public final class StorageExample {
    public static void main(String[] args) throws Exception {
        Map<String,String> flags=flags(args);
        if(flags.containsKey("help")) { System.out.println("--endpoint --cache-dir --output-dir --start-ms --end-ms --audio-channel-id --video-channel-id; credentials/device use TI_CLOUD_STORAGE_* environment"); return; }
        Path output=Paths.get(required(flags,"output-dir")).toAbsolutePath(); Files.createDirectories(output);
        String device=env("TI_CLOUD_STORAGE_DEVICE_ID");
        Instant start=Instant.ofEpochMilli(Long.parseLong(required(flags,"start-ms")));
        Instant end=Instant.ofEpochMilli(Long.parseLong(required(flags,"end-ms")));
        int audioId=Integer.parseInt(required(flags,"audio-channel-id")),videoId=Integer.parseInt(required(flags,"video-channel-id"));
        Properties result=new Properties(); Frames frames=new Frames();
        ClientOptions options=options(flags,"TI_CLOUD_STORAGE_APP_ID","TI_CLOUD_STORAGE_ACCESS_KEY_ID","TI_CLOUD_STORAGE_ACCESS_KEY_SECRET");
        ExportTask retainedTask=null;
        try (CloudStorageClient client=new CloudStorageClient(options)) {
            List<RecordingDay> days=client.listRecordingDays(device,start.atZone(ZoneOffset.UTC).toLocalDate(),end.atZone(ZoneOffset.UTC).toLocalDate(),ZoneOffset.UTC).get(90,TimeUnit.SECONDS);
            check(days.stream().anyMatch(RecordingDay::hasRecording),"recording dates present"); result.setProperty("dates","true");
            List<RecordingRange> ranges=client.listRecordings(device,start,end).get(90,TimeUnit.SECONDS);
            check(!ranges.isEmpty(),"recording ranges present"); result.setProperty("ranges","true");
            RecordingRange available=ranges.stream().filter(r -> Duration.between(r.startTime(),r.endTime()).compareTo(Duration.ofSeconds(4))>=0)
                    .findFirst().orElseThrow(() -> new IllegalStateException("fixture needs at least four seconds of continuous recording"));
            // Keep the example observation bounded even when the device has a long recording.
            RecordingRange selected=new RecordingRange(available.startTime(),
                    available.endTime().isAfter(available.startTime().plusSeconds(12))
                            ? available.startTime().plusSeconds(12) : available.endTime());
            AtomicBoolean completed=new AtomicBoolean();
            try (Replay replay=client.newReplay(device,new Replay.Listener() {
                public void onCompleted() { completed.set(true); }
                public void onError(TiRtcException error) { frames.error(error); }
            })) {
                frames.reentry=replay::pause;
                try (VideoOutput video=new VideoOutput(replay,videoId,frames.video());
                     AudioOutput audio=new AudioOutput(replay,audioId,frames.audio());
                     EncodedVideoOutput encodedVideo=new EncodedVideoOutput(replay,videoId,frames.encodedVideo());
                     EncodedAudioOutput encodedAudio=new EncodedAudioOutput(replay,audioId,frames.encodedAudio())) {
                    replay.play(selected.startTime(),selected.endTime());
                    await(() -> frames.all() && replay.currentTime().isPresent(),frames,"replay media and playback position");
                    replay.pause(); check(replay.currentTime().isPresent(),"paused replay position");
                    replay.resume();
                    replay.setSpeed(ReplaySpeed.X0_5); check(replay.speed()==ReplaySpeed.X0_5,"half speed selected");
                    final int baseline=frames.v.get();
                    replay.seek(selected.startTime());
                    await(() -> frames.v.get()>baseline,frames,"video after seek at half speed");
                    replay.setSpeed(ReplaySpeed.X1); check(replay.speed()==ReplaySpeed.X1,"normal speed restored");
                    result.setProperty("replayControls","true");
                    try (RecordingTask task=replay.startRecording(new com.tange.ai.tirtc.storage.StartRecordingOptions(videoId,audioId))) {
                        final int recordedBaseline=frames.v.get(), audioBaseline=frames.a.get();
                        replay.seek(selected.startTime());
                        await(() -> frames.v.get()>recordedBaseline+15&&frames.a.get()>audioBaseline+15,frames,"replay recording media");
                        try (RecordingFile file=task.stop()) { saveDelete(file,output.resolve("ti-cloud-storage-replay-recording.mp4")); }
                    }
                    try (SnapshotFile file=video.takeSnapshot()) {
                        save(file.path(),output.resolve("ti-cloud-storage-snapshot.jpg"),true); file.delete(); check(!Files.exists(file.path()),"snapshot deleted");
                    }
                    await(completed::get,frames,"natural replay completion");
                    frames.verify(result);
                    replay.stop();
                }
            }
            ExportOptions fullOptions=new ExportOptions(selected.startTime(),selected.endTime(),videoId,audioId);
            try (ExportTask task=client.exportRecording(device,fullOptions)) {
                ExportResult full=task.completion().toCompletableFuture().get(90,TimeUnit.SECONDS);
                try (RecordingFile file=full.file()) {
                    check(full.report().complete(),"full export covers the requested recording interval");
                    check(task.progress().fraction()==1,"full export final progress");
                    result.setProperty("fullExportComplete",Boolean.toString(full.report().complete()));
                    saveDelete(file,output.resolve("ti-cloud-storage-range-export.mp4"));
                }
            }
            // Query beyond the known recording end so earlier test uploads do not fill the gap.
            Instant gapStart=available.endTime(), gapEnd=gapStart.plusSeconds(60);
            List<RecordingRange> following=client.listRecordings(device,gapStart,gapEnd).get(90,TimeUnit.SECONDS);
            // The original query may clip the final recording range at its end argument.
            if(!following.isEmpty()) {
                gapStart=following.stream().map(RecordingRange::endTime).max(Comparator.naturalOrder()).get();
                gapEnd=gapStart.plusSeconds(60);
                following=client.listRecordings(device,gapStart,gapEnd).get(90,TimeUnit.SECONDS);
            }
            check(following.isEmpty(),"partial export fixture needs a confirmed empty following minute");
            Instant partialStart=available.endTime().minusSeconds(12);
            if(partialStart.isBefore(available.startTime())) partialStart=available.startTime();
            result.setProperty("partialGapFixtureConfirmed","true");
            try (ExportTask task=client.exportRecording(device,new ExportOptions(partialStart,gapEnd,videoId,audioId))) {
                ExportResult partial=task.completion().toCompletableFuture().get(90,TimeUnit.SECONDS);
                try (RecordingFile file=partial.file()) {
                    ExportReport report=partial.report();
                    check(!report.complete()&&!report.gaps().isEmpty()&&!report.segments().isEmpty(),"partial export provides coverage and gaps");
                    result.setProperty("partialExportComplete",Boolean.toString(report.complete()));
                    result.setProperty("partialExportGaps",Integer.toString(report.gaps().size()));
                    result.setProperty("partialExportSegments",Integer.toString(report.segments().size()));
                    result.setProperty("partialExportUnprocessedRanges",Integer.toString(report.unprocessedRanges().size()));
                    saveDelete(file,output.resolve("ti-cloud-storage-partial-export.mp4"));
                }
            }
            retainedTask=client.exportRecording(device,fullOptions);
            // Changing an application view must not alter the task's internal terminal.
            retainedTask.completion().toCompletableFuture().cancel(false);
            retainedTask.completion().toCompletableFuture().complete(null);
            retainedTask.completion().thenRun(() -> {}).toCompletableFuture().get(90,TimeUnit.SECONDS);
            retainedTask.close();
        }
        // The client and task have closed. The result has not yet been retrieved by the application.
        check(retainedTask!=null,"retained export exists");
        ExportResult retained=retainedTask.completion().toCompletableFuture().get(90,TimeUnit.SECONDS);
        try (RecordingFile file=retained.file()) {
            check(retained.report().complete(),"completed export survives client close");
            check(retainedTask.completion().toCompletableFuture().get().file()==file,"completion preserves unique file owner");
            saveDelete(file,output.resolve("ti-cloud-storage-export-after-close.mp4"));
        }
        result.setProperty("exportAfterClose","true"); result.setProperty("filesDeleted","true"); result.setProperty("closed","true"); write(output,result);
    }
    private static void saveDelete(RecordingFile file,Path target) throws Exception {
        save(file.path(),target,false); file.delete(); check(!Files.exists(file.path()),"temporary export or recording deleted");
    }
}
