package com.tange.ai.tirtc.example;

import com.tange.ai.tirtc.*;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.security.SecureRandom;
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
        applyRawDumpCase(flags, false);
        if (flags.containsKey("help")) { System.out.println("--endpoint --remote-id --cache-dir --output-dir [--audio-stream-id 10 --video-stream-id 11] [--raw-dump --raw-dump-seconds 10 --raw-dump-copy-to ABSOLUTE_ZIP] [--upload-logs] [--case-id smoke.raw-dump-upload|integration.raw-dump-recovery]"); return; }
        Path output = Paths.get(required(flags,"output-dir")).toAbsolutePath(); Files.createDirectories(output);
        Properties result = new Properties();
        int audioId = Integer.parseInt(flags.getOrDefault("audio-stream-id","10"));
        int videoId = Integer.parseInt(flags.getOrDefault("video-stream-id","11"));
        int secondaryId = Integer.parseInt(flags.getOrDefault("secondary-video-stream-id",Integer.toString(videoId)));
        Frames secondary = new Frames();
        Frames frames = new Frames(); final MessageProof messages = new MessageProof(videoId, flags.containsKey("verify-message-echo"));
        ClientOptions options = options(flags,"TIRTC_APP_ID","TIRTC_ACCESS_KEY_ID","TIRTC_SECRET_KEY_ID");
        try (RtcClient client = new RtcClient(options);
             Connection connection = client.newConnection(new Connection.Listener() {
                 public void onStateChanged(ConnectionState state, TiRtcException error) { if (error != null) frames.failure.compareAndSet(null,error); }
                 public void onCommand(long id, ByteBuffer data) { messages.command(id,data); }
                 public void onStreamMessage(int id, Duration time, ByteBuffer data) { messages.stream(id,time,data); }
             })) {
            frames.reentry = connection::disconnect;
            try (AudioOutput audio = new AudioOutput(connection,audioId,frames.audio());
                 VideoOutput video = new VideoOutput(connection,videoId,frames.video());
                 EncodedAudioOutput encodedAudio = new EncodedAudioOutput(connection,audioId,frames.encodedAudio());
                 EncodedVideoOutput encodedVideo = new EncodedVideoOutput(connection,videoId,frames.encodedVideo());
                 VideoOutput secondVideo = secondaryId==videoId?null:new VideoOutput(connection,secondaryId,secondary.video());
                 EncodedVideoOutput secondEncoded = secondaryId==videoId?null:new EncodedVideoOutput(connection,secondaryId,secondary.encodedVideo())) {
                requireNoFrame(video); if(secondVideo!=null) requireNoFrame(secondVideo);
                result.setProperty("zeroFrameSnapshot","true");
                connection.connect(required(flags,"remote-id")).get(90,TimeUnit.SECONDS);
                result.setProperty("connected","true");
                connection.subscribeAudio(audioId); connection.subscribeVideo(videoId);
                if(secondVideo!=null) connection.subscribeVideo(secondaryId);
                RawDump rawDump=null;
                long rawDumpStarted=0;
                boolean rawDumpEnabled=flags.containsKey("raw-dump")||flags.containsKey("raw-dump-seconds");
                int rawDumpSeconds=Integer.parseInt(flags.getOrDefault("raw-dump-seconds","10"));
                if(rawDumpSeconds<=0||rawDumpSeconds>300) throw new IllegalArgumentException("--raw-dump-seconds must be 1..300");
                if(rawDumpEnabled) {
                    rawDump=connection.startRawDump(new RawDumpOptions(new int[]{audioId},new int[]{videoId}));
                    rawDumpStarted=System.nanoTime();
                }
                await(() -> frames.all(),frames,"four media outputs");
                if(secondVideo!=null) verifyRoutes(video,encodedVideo,frames,secondary,videoId,secondaryId,() -> connection.requestVideoKeyframe(videoId),result);
                if(rawDump!=null) {
                    if("integration.raw-dump-recovery".equals(flags.get("case-id"))) {
                        try { connection.startRawDump(new RawDumpOptions(new int[]{audioId},new int[]{videoId})); throw new IllegalStateException("duplicate raw dump start accepted"); }
                        catch(TiRtcException expected) { check(expected.category()==ErrorCategory.IN_USE,"duplicate raw dump start category"); }
                    }
                    long remaining=TimeUnit.SECONDS.toNanos(rawDumpSeconds)-(System.nanoTime()-rawDumpStarted);
                    if(remaining>0) TimeUnit.NANOSECONDS.sleep(remaining);
                    RawDumpArchive archive=rawDump.stop();
                    check(Files.isRegularFile(archive.path())&&!archive.captureId().isEmpty()&&!archive.sha256().isEmpty(),"raw dump archive");
                    result.setProperty("rawDumpCaptureId",archive.captureId());
                    result.setProperty("rawDumpPath",archive.path().toString());
                    result.setProperty("rawDumpSha256",archive.sha256());
                    if(flags.containsKey("raw-dump-copy-to")) {
                        Path copy=Paths.get(flags.get("raw-dump-copy-to"));
                        check(copy.isAbsolute(),"--raw-dump-copy-to must be absolute");
                        Files.createDirectories(copy.getParent()); Files.copy(archive.path(),copy,StandardCopyOption.REPLACE_EXISTING);
                        result.setProperty("rawDumpCopyPath",copy.toString());
                    }
                    if("integration.raw-dump-recovery".equals(flags.get("case-id"))) check(rawDump.stop()==archive,"repeated raw dump stop changed result");
                    rawDump.close();
                }
                for(int index=0;index<2;index++) {
                    connection.sendCommand(messages.commandId(index),messages.commandBytes(index));
                    if(messages.fixture) connection.sendStreamMessage(videoId,Duration.ofMillis(messages.timestamp(index)),messages.streamBytes(index,false));
                }
                int beforeKey = frames.keys.get(); connection.requestVideoKeyframe(videoId);
                await(() -> messages.complete() && frames.keys.get()>beforeKey,frames,"messages and requested keyframe");
                result.setProperty("command","true"); result.setProperty("streamMessage","true"); result.setProperty("keyFrame","true");
                try (RecordingTask recording = connection.startRecording(new StartRecordingOptions(videoId,audioId))) {
                    int beforeVideo = frames.v.get(), beforeAudio = frames.a.get(), key = frames.keys.get();
                    connection.requestVideoKeyframe(videoId);
                    await(() -> frames.v.get()>beforeVideo+30 && frames.a.get()>beforeAudio+30 && frames.keys.get()>key,frames,"recorded audio and video");
                    try (RecordingFile file = recording.stop()) { save(file.path(),output.resolve("rtc-recording.mp4"),false); file.delete(); check(!Files.exists(file.path()),"recording deleted"); }
                }
                try (SnapshotFile file = video.takeSnapshot()) { save(file.path(),output.resolve("rtc-snapshot.jpg"),true); file.delete(); check(!Files.exists(file.path()),"snapshot deleted"); }
                frames.verify(result);
                connection.unsubscribeVideo(videoId); if(secondVideo!=null) connection.unsubscribeVideo(secondaryId); connection.unsubscribeAudio(audioId);
            }
            if(flags.containsKey("upload-logs")) { check(!client.uploadLogs().isEmpty(),"log upload returned identifier"); result.setProperty("uploadLogs","true"); }
        }
        messages.write(result);
        result.setProperty("filesDeleted","true"); result.setProperty("closed","true"); write(output,result);
    }
    static void requireNoFrame(VideoOutput video) {
        try(SnapshotFile unexpected=video.takeSnapshot()) { throw new IllegalStateException("zero-frame snapshot accepted"); }
        catch(TiRtcException expected) { check(expected.category()==ErrorCategory.NO_FRAME,"zero-frame snapshot category"); }
    }
    static Map<String,Integer> routeCounts(Frames first,Frames second,int firstId,int secondId) {
        Map<String,Integer> values=new LinkedHashMap<String,Integer>();
        values.put("video:"+firstId,first.v.get());values.put("encoded_video:"+firstId,first.ev.get());
        values.put("video:"+secondId,second.v.get());values.put("encoded_video:"+secondId,second.ev.get());return values;
    }
    static void routeReceipt(Properties result,String phase,Map<String,Integer> counts) {
        for(Map.Entry<String,Integer> entry:counts.entrySet()) result.setProperty("routes."+phase+"."+entry.getKey(),entry.getValue().toString());
    }
    static void verifyRoutes(VideoOutput video,EncodedVideoOutput encoded,Frames first,Frames second,int firstId,int secondId,Runnable requestKey,Properties result) throws Exception {
        await(() -> first.v.get()>0&&first.ev.get()>0&&second.v.get()>0&&second.ev.get()>0,first,"both independent routes");
        Map<String,Integer> common=routeCounts(first,second,firstId,secondId);
        await(() -> first.v.get()>common.get("video:"+firstId)&&first.ev.get()>common.get("encoded_video:"+firstId)&&second.v.get()>common.get("video:"+secondId)&&second.ev.get()>common.get("encoded_video:"+secondId),first,"common route window");
        routeReceipt(result,"common_before",common);routeReceipt(result,"common_after",routeCounts(first,second,firstId,secondId));
        encoded.detach();video.detach();
        Map<String,Integer> isolated=routeCounts(first,second,firstId,secondId);
        await(() -> second.v.get()>isolated.get("video:"+secondId)&&second.ev.get()>isolated.get("encoded_video:"+secondId),second,"unaffected route continues");
        check(first.v.get()==isolated.get("video:"+firstId)&&first.ev.get()==isolated.get("encoded_video:"+firstId),"detached output callback barrier");
        routeReceipt(result,"isolated_before",isolated);routeReceipt(result,"isolated_after",routeCounts(first,second,firstId,secondId));
        video.attach(firstId);encoded.attach(firstId);Map<String,Integer> restored=routeCounts(first,second,firstId,secondId);requestKey.run();
        await(() -> first.v.get()>restored.get("video:"+firstId)&&first.ev.get()>restored.get("encoded_video:"+firstId)&&second.v.get()>restored.get("video:"+secondId)&&second.ev.get()>restored.get("encoded_video:"+secondId),first,"both routes after restoration");
        check(second.failure.get()==null,"independent output errors");
        routeReceipt(result,"restored_before",restored);routeReceipt(result,"restored_after",routeCounts(first,second,firstId,secondId));result.setProperty("multiRoute","true");
    }
    static final class MessageProof {
        static final byte[] PREFIX = new byte[]{116,105,114,116,99,45,115,116,114,101,97,109,45,118,49,0};
        final byte[] nonce = new byte[16]; final int streamId; final boolean fixture;
        final List<byte[]> commands = new ArrayList<byte[]>(), streams = new ArrayList<byte[]>();
        String failure;
        MessageProof(int streamId,boolean fixture) { this.streamId=streamId;this.fixture=fixture;new SecureRandom().nextBytes(nonce); }
        long commandId(int index) { return index==0?0x2001L:0xffffffffL; }
        long timestamp(int index) { return index==0?0L:0xffffffffL; }
        byte[] commandBytes(int index) { return ByteBuffer.allocate(20).put(nonce).put((byte)index).put((byte)0).put((byte)255).put((byte)128).array(); }
        byte[] streamBytes(int index,boolean response) { return ByteBuffer.allocate(PREFIX.length+1+16+4+3).put(PREFIX).put((byte)(response?1:0)).put(nonce).putInt(index).put((byte)0).put((byte)255).put((byte)128).array(); }
        static byte[] copy(ByteBuffer buffer) { ByteBuffer view=buffer.duplicate();byte[] bytes=new byte[view.remaining()];view.get(bytes);return bytes; }
        synchronized void command(long id,ByteBuffer buffer) {
            byte[] bytes=copy(buffer);int index=commands.size();
            if(index>=2||id!=commandId(index)||!Arrays.equals(bytes,commandBytes(index))) failure="command ID/order/binary mismatch";
            commands.add(bytes);
        }
        synchronized void stream(int id,Duration timestamp,ByteBuffer buffer) {
            byte[] bytes=copy(buffer);
            if(!fixture||bytes.length<PREFIX.length||!Arrays.equals(PREFIX,Arrays.copyOf(bytes,PREFIX.length)))return;
            int index=streams.size();
            if(index>=2||id!=streamId||timestamp.toMillis()!=timestamp(index)||!Arrays.equals(bytes,streamBytes(index,true))) failure="stream ID/timestamp/order/binary mismatch";
            streams.add(bytes);
        }
        synchronized boolean complete() { if(failure!=null)throw new IllegalStateException(failure);return commands.size()==2&&(!fixture||streams.size()==2); }
        static String hex(byte[] bytes) { StringBuilder out=new StringBuilder();for(byte b:bytes)out.append(String.format("%02x",b & 255));return out.toString(); }
        synchronized void write(Properties result) {
            check(complete(),"exact remote message delivery");result.setProperty("messagePeerMode",fixture?"stream-echo":"device");
            for(int index=0;index<commands.size();index++) {result.setProperty("command"+index+"Id",Long.toString(commandId(index)));result.setProperty("command"+index+"Bytes",hex(commands.get(index)));}
            for(int index=0;index<streams.size();index++) {result.setProperty("stream"+index+"Id",Integer.toString(streamId));result.setProperty("stream"+index+"Timestamp",Long.toString(timestamp(index)));result.setProperty("stream"+index+"Bytes",hex(streams.get(index)));}
        }
    }
    static Map<String,String> flags(String[] args) {
        Map<String,String> flags = new HashMap<String,String>();
        for(int i=0;i<args.length;i++) {
            if(!args[i].startsWith("--")) throw new IllegalArgumentException("expected named option");
            String name=args[i].substring(2);
            if(name.equals("help")||name.equals("upload-logs")||name.equals("raw-dump")||name.equals("verify-message-echo")) flags.put(name,"true");
            else {
                if(++i==args.length) throw new IllegalArgumentException("missing option value");
                // The Cloud bootstrap supplies one --video-channel-id per uploaded
                // route. The canonical Java Example keeps the first route as the
                // primary and receives the independently selected secondary route
                // through --secondary-video-channel-id.
                if(name.equals("video-channel-id")) flags.putIfAbsent(name,args[i]);
                else flags.put(name,args[i]);
            }
        }
        return flags;
    }
    static void applyRawDumpCase(Map<String,String> flags,boolean cloud) {
        String id=flags.get("case-id"); if(id==null) return;
        String smoke=cloud?"ti-cloud-storage.raw-dump.smoke-upload":"smoke.raw-dump-upload";
        String integration=cloud?"ti-cloud-storage.raw-dump.integration-recovery":"integration.raw-dump-recovery";
        if(!id.equals(smoke)&&!id.equals(integration)) throw new IllegalArgumentException("unknown --case-id "+id);
        flags.put("raw-dump","true"); flags.put("upload-logs","true");
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
