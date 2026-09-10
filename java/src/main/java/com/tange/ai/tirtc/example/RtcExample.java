package com.tange.ai.tirtc.example;

import com.tange.ai.tirtc.*;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.file.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.BooleanSupplier;

/** Headless RTC client using only the supported Java API. */
public final class RtcExample {
    public static void main(String[] args) throws Exception {
        Map<String,String> flags = flags(args);
        if (flags.containsKey("help")) { System.out.println("--endpoint --remote-id --cache-dir --output-dir [--audio-stream-id 10 --video-stream-id 11] [--upload-logs]"); return; }
        Path output = Paths.get(required(flags,"output-dir")).toAbsolutePath(); Files.createDirectories(output);
        Properties result = new Properties();
        int audioId = Integer.parseInt(flags.getOrDefault("audio-stream-id","10"));
        int videoId = Integer.parseInt(flags.getOrDefault("video-stream-id","11"));
        Frames frames = new Frames(); AtomicBoolean command = new AtomicBoolean(), message = new AtomicBoolean();
        ClientOptions options = options(flags,"TIRTC_APP_ID","TIRTC_ACCESS_KEY_ID","TIRTC_SECRET_KEY_ID");
        try (RtcClient client = new RtcClient(options);
             Connection connection = client.newConnection(new Connection.Listener() {
                 public void onStateChanged(ConnectionState state, TiRtcException error) { if (error != null) frames.failure.compareAndSet(null,error); }
                 public void onCommand(long id, ByteBuffer data) { command.set(true); }
                 public void onStreamMessage(int id, Duration time, ByteBuffer data) { message.set(true); }
             })) {
            frames.reentry = connection::disconnect;
            try (AudioOutput audio = new AudioOutput(connection,audioId,frames.audio());
                 VideoOutput video = new VideoOutput(connection,videoId,frames.video());
                 EncodedAudioOutput encodedAudio = new EncodedAudioOutput(connection,audioId,frames.encodedAudio());
                 EncodedVideoOutput encodedVideo = new EncodedVideoOutput(connection,videoId,frames.encodedVideo())) {
                connection.connect(required(flags,"remote-id")).get(90,TimeUnit.SECONDS);
                result.setProperty("connected","true");
                connection.subscribeAudio(audioId); connection.subscribeVideo(videoId);
                await(() -> frames.all(),frames,"four media outputs");
                connection.sendCommand(0x2001,"java-client-command".getBytes("UTF-8"));
                connection.sendStreamMessage(videoId,Duration.ofMillis(System.currentTimeMillis() & 0xffffffffL),"java-client-message".getBytes("UTF-8"));
                int beforeKey = frames.keys.get(); connection.requestVideoKeyframe(videoId);
                await(() -> command.get() && message.get() && frames.keys.get()>beforeKey,frames,"messages and requested keyframe");
                result.setProperty("command","true"); result.setProperty("streamMessage","true"); result.setProperty("keyFrame","true");
                try (RecordingTask recording = connection.startRecording(new StartRecordingOptions(videoId,audioId))) {
                    int beforeVideo = frames.v.get(), beforeAudio = frames.a.get(), key = frames.keys.get();
                    connection.requestVideoKeyframe(videoId);
                    await(() -> frames.v.get()>beforeVideo+30 && frames.a.get()>beforeAudio+30 && frames.keys.get()>key,frames,"recorded audio and video");
                    try (RecordingFile file = recording.stop()) { save(file.path(),output.resolve("rtc-recording.mp4"),false); file.delete(); check(!Files.exists(file.path()),"recording deleted"); }
                }
                try (SnapshotFile file = video.takeSnapshot()) { save(file.path(),output.resolve("rtc-snapshot.jpg"),true); file.delete(); check(!Files.exists(file.path()),"snapshot deleted"); }
                frames.verify(result);
                connection.unsubscribeVideo(videoId); connection.unsubscribeAudio(audioId);
            }
            if(flags.containsKey("upload-logs")) { check(!client.uploadLogs().isEmpty(),"log upload returned identifier"); result.setProperty("uploadLogs","true"); }
        }
        result.setProperty("filesDeleted","true"); result.setProperty("closed","true"); write(output,result);
    }
    static Map<String,String> flags(String[] args) {
        Map<String,String> flags = new HashMap<String,String>();
        for(int i=0;i<args.length;i++) {
            if(!args[i].startsWith("--")) throw new IllegalArgumentException("expected named option");
            String name=args[i].substring(2);
            if(name.equals("help")||name.equals("upload-logs")) flags.put(name,"true");
            else { if(++i==args.length) throw new IllegalArgumentException("missing option value"); flags.put(name,args[i]); }
        }
        return flags;
    }
    static String required(Map<String,String> flags,String name) { String value=flags.get(name); if(value==null||value.isEmpty()) throw new IllegalArgumentException("missing --"+name); return value; }
    static String env(String name) { String value=System.getenv(name); if(value==null||value.isEmpty()) throw new IllegalArgumentException("missing "+name); return value; }
    static ClientOptions options(Map<String,String> flags,String app,String key,String secret) {
        return ClientOptions.builder().appId(env(app)).accessKeyId(env(key)).accessKeySecret(env(secret))
                .endpoint(required(flags,"endpoint")).cacheDir(Paths.get(required(flags,"cache-dir")).toAbsolutePath()).build();
    }
    static void await(BooleanSupplier ready,Frames frames,String label) throws Exception {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(90);
        while(!ready.getAsBoolean()) { if(frames.failure.get()!=null) throw new IllegalStateException(label,frames.failure.get()); if(System.nanoTime()>deadline) throw new TimeoutException(label); Thread.sleep(20); }
        if(frames.failure.get()!=null) throw new IllegalStateException(label,frames.failure.get());
    }
    static void check(boolean condition,String label) { if(!condition) throw new IllegalStateException(label); }
    static void save(Path source,Path destination,boolean jpeg) throws Exception {
        byte[] header=new byte[12];
        try(java.io.InputStream input=Files.newInputStream(source)) { int read=0,n; while(read<header.length&&(n=input.read(header,read,header.length-read))>0) read+=n; check(read==header.length,"media header present"); }
        check(jpeg ? (header[0]&255)==255&&(header[1]&255)==216 : header[4]=='f'&&header[5]=='t'&&header[6]=='y'&&header[7]=='p',"media container header");
        Files.copy(source,destination,StandardCopyOption.REPLACE_EXISTING);
    }
    static void write(Path output,Properties result) throws Exception { try(OutputStream stream=Files.newOutputStream(output.resolve("result.properties"))) { result.store(stream,"Java Example observed results"); } }
    static final class Frames {
        final AtomicInteger a=new AtomicInteger(),v=new AtomicInteger(),ea=new AtomicInteger(),ev=new AtomicInteger(),keys=new AtomicInteger();
        final AtomicReference<Throwable> failure=new AtomicReference<Throwable>();
        final AtomicBoolean reentryRejected=new AtomicBoolean();
        volatile Runnable reentry;
        volatile ByteBuffer retained;
        volatile int retainedHash;
        boolean all() { return a.get()>0&&v.get()>1&&ea.get()>0&&ev.get()>0; }
        void error(TiRtcException error) { failure.compareAndSet(null,error); }
        AudioOutput.Listener audio() { return new AudioOutput.Listener() { public void onFrame(AudioFrame f) { a.incrementAndGet(); } public void onError(TiRtcException e) { error(e); } }; }
        VideoOutput.Listener video() { return new VideoOutput.Listener() {
            public void onFrame(VideoFrame f) {
                if(v.incrementAndGet()==1) {
                    if(!f.planes().isEmpty()) { retained=f.planes().get(0).data(); retainedHash=retained.hashCode(); }
                    if(reentry!=null) try { reentry.run(); failure.compareAndSet(null,new IllegalStateException("callback control accepted")); }
                    catch(TiRtcException e) { if(e.category()==ErrorCategory.IN_USE) reentryRejected.set(true); else error(e); }
                    // Subsequent frames demonstrate that an application listener exception does not kill dispatch.
                    throw new IllegalStateException("example listener exception containment check");
                }
            }
            public void onError(TiRtcException e) { error(e); }
        }; }
        EncodedAudioOutput.Listener encodedAudio() { return new EncodedAudioOutput.Listener() { public void onFrame(EncodedAudioFrame f) { ea.incrementAndGet(); } public void onError(TiRtcException e) { error(e); } }; }
        EncodedVideoOutput.Listener encodedVideo() { return new EncodedVideoOutput.Listener() { public void onFrame(EncodedVideoFrame f) { ev.incrementAndGet(); if(f.keyFrame()) keys.incrementAndGet(); } public void onError(TiRtcException e) { error(e); } }; }
        void verify(Properties result) {
            check(all(),"four frame types observed"); check(reentryRejected.get(),"callback controls rejected");
            check(retained!=null&&retained.isReadOnly()&&retained.hashCode()==retainedHash,"retained JNI frame snapshot unchanged");
            check(failure.get()==null,"no output errors");
            result.setProperty("decodedAudioFrames",Integer.toString(a.get())); result.setProperty("decodedVideoFrames",Integer.toString(v.get()));
            result.setProperty("encodedAudioFrames",Integer.toString(ea.get())); result.setProperty("encodedVideoFrames",Integer.toString(ev.get()));
            result.setProperty("callbackReentryRejected","true"); result.setProperty("retainedFrameValid","true"); result.setProperty("listenerExceptionContained","true");
        }
    }
}
