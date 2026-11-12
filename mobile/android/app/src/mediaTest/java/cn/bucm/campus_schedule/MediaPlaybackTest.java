package cn.bucm.campus_schedule;

import android.content.Context;
import android.content.Intent;
import android.os.SystemClock;
import android.view.WindowManager;
import androidx.media3.common.Player;
import androidx.media3.datasource.AssetDataSource;
import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
import java.io.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

/** Real Media3 H264/AAC decoding, from generated assets in this test APK only. */
@RunWith(AndroidJUnit4.class)
public class MediaPlaybackTest {
    ActivityScenario<MainActivity> scenario;
    MainActivity activity;
    ClassroomPlayerGroup group;
    Context assets;
    final Set<String> rendered=new HashSet<>();

    private <T> T main(Callable<T> work) throws Exception {
        FutureTask<T> task=new FutureTask<>(work);
        InstrumentationRegistry.getInstrumentation().runOnMainSync(task);
        return task.get(10,TimeUnit.SECONDS);
    }
    private void await(String stage,Callable<Boolean> condition) throws Exception {
        long end=SystemClock.uptimeMillis()+20000;
        while(SystemClock.uptimeMillis()<end) {
            if(main(()->{group.snapshot();return condition.call();}))return;
            SystemClock.sleep(100);
        }
        fail("Timed out during synthetic media stage: "+stage+"; state="+main(()->group.snapshot()).toString());
    }
    private void observeFrames() {
        for(ClassroomPlayerGroup.Stream stream:group.streams.values()) {
            rendered.remove(stream.kind);
            stream.player.addListener(new Player.Listener(){
                @Override public void onRenderedFirstFrame(){rendered.add(stream.kind);}
            });
        }
    }
    private void create(String playlist) throws Exception {
        main(()->{
            Map<String,String> sources=new LinkedHashMap<>();
            for(String kind:Arrays.asList("ppt","teacher","student"))sources.put(kind,playlist);
            java.lang.reflect.Method accessor=FlutterActivity.class.getDeclaredMethod("getFlutterEngine");
            accessor.setAccessible(true);
            FlutterEngine engine=(FlutterEngine)accessor.invoke(activity);
            group=new ClassroomPlayerGroup(activity,engine.getRenderer(),sources,"SYNTHETIC WATERMARK",
                    ()->new AssetDataSource(assets));
            observeFrames();return null;
        });
    }
    private boolean ready() {
        for(ClassroomPlayerGroup.Stream stream:group.streams.values())if(stream.player.getPlaybackState()!=Player.STATE_READY)return false;
        return !group.streams.isEmpty()&&group.error==null;
    }
    private void assertSingleAudio() {
        int audible=0;
        for(ClassroomPlayerGroup.Stream stream:group.streams.values())if(stream.player.getVolume()>0)audible++;
        assertEquals(1,audible);
        assertEquals(1f,group.master().player.getVolume(),0);
    }
    private void assertNear(long position) {
        for(ClassroomPlayerGroup.Stream stream:group.streams.values())assertTrue("Unified seek drift",Math.abs(stream.player.getCurrentPosition()-position)<500);
    }

    @Before public void setUp() throws Exception {
        Context target=InstrumentationRegistry.getInstrumentation().getTargetContext();
        assertEquals("cn.bucm.campus_schedule.mediatest",target.getPackageName());
        assets=InstrumentationRegistry.getInstrumentation().getContext();
        JSONObject manifest=new JSONObject(new String(read("fixture.json"),java.nio.charset.StandardCharsets.UTF_8));
        assertTrue(manifest.getBoolean("synthetic"));assertEquals(1,manifest.getInt("schema"));
        JSONArray files=manifest.getJSONArray("files");assertTrue(files.length()>2);
        for(int i=0;i<files.length();i++) {
            JSONObject item=files.getJSONObject(i);String name=item.getString("file");
            assertTrue(name.equals("index.m3u8")||name.matches("segment-\\d{3}\\.ts"));
            StringBuilder digest=new StringBuilder();
            for(byte b:MessageDigest.getInstance("SHA-256").digest(read(name)))digest.append(String.format(Locale.ROOT,"%02x",b&255));
            assertEquals(item.getString("sha256"),digest.toString());
        }
        scenario=ActivityScenario.launch(new Intent(target,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        scenario.onActivity(value->activity=value);
    }
    private byte[] read(String name) throws Exception {
        try(InputStream in=assets.getAssets().open(name);ByteArrayOutputStream out=new ByteArrayOutputStream()) {
            byte[] bytes=new byte[8192];int count;while((count=in.read(bytes))!=-1)out.write(bytes,0,count);return out.toByteArray();
        }
    }
    @After public void tearDown() throws Exception {
        if(group!=null)main(()->{group.close();return null;});
        if(scenario!=null)scenario.close();
    }

    @Test public void decodePauseUnifiedSeekSpeedAndAudio() throws Exception {
        create("asset:///index.m3u8");
        await("both decoders and first frames",()->ready()&&rendered.containsAll(Arrays.asList("ppt","teacher")));
        main(()->{assertTrue(group.duration()>=59000&&group.duration()<=61000);assertSingleAudio();group.play();return null;});
        await("advancing",()->group.master().player.getCurrentPosition()>1000);
        long paused=main(()->{group.pause();assertFalse(group.want);return group.master().player.getCurrentPosition();});
        SystemClock.sleep(400);
        main(()->{assertNear(paused);assertEquals(0,activity.getWindow().getAttributes().flags&WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);group.seek(20000);return null;});
        await("unified middle seek",()->ready()&&Math.abs(group.master().player.getCurrentPosition()-20000)<500);
        main(()->{assertNear(20000);group.setSpeed(1.5f);for(ClassroomPlayerGroup.Stream stream:group.streams.values())assertEquals(1.5f,stream.player.getPlaybackParameters().speed,0);group.play();return null;});
        await("after speed change",()->group.master().player.getCurrentPosition()>21000);
        main(()->{group.pause();group.seek(-1000);return null;});
        await("zero clamp",()->ready()&&group.master().player.getCurrentPosition()<500);
        main(()->{assertNear(0);group.seek(Long.MAX_VALUE);return null;});
        // A paused HLS seek can settle on duration-1ms in READY; it does not
        // assert STATE_ENDED until playback reaches the end of the timeline.
        await("paused end clamp",()->ready()&&Math.abs(group.master().player.getCurrentPosition()-group.duration())<500);
        main(()->{assertFalse(group.want);assertNear(group.duration());group.play();return null;});
        await("natural end",()->group.ended());
        main(()->{assertFalse(group.want);group.play();return null;});
        await("restart after end",()->ready()&&group.want&&group.master().player.getCurrentPosition()>300&&group.master().player.getCurrentPosition()<3000);
    }

    @Test public void layoutKeepsPositionAndReleasesDroppedDecoders() throws Exception {
        create("asset:///index.m3u8");
        await("initial layout",this::ready);
        main(()->{group.seek(12000);return null;});
        await("saved position",()->ready()&&Math.abs(group.master().player.getCurrentPosition()-12000)<500);
        ClassroomPlayerGroup.Stream dropped=main(()->{ClassroomPlayerGroup.Stream old=group.streams.get("teacher");group.layout("ppt",null);return old;});
        main(()->{assertEquals(Player.STATE_IDLE,dropped.player.getPlaybackState());assertEquals(1,group.streams.size());assertSingleAudio();group.layout("student","teacher");observeFrames();return null;});
        await("restored and switched layout",()->ready()&&rendered.containsAll(Arrays.asList("student","teacher")));
        main(()->{
            assertNear(12000);assertSingleAudio();
            ClassroomPlayerGroup.Stream teacher=group.streams.get("teacher"),student=group.streams.get("student");
            group.layout("teacher","student");assertSame(teacher,group.streams.get("teacher"));assertSame(student,group.streams.get("student"));assertSingleAudio();
            try{group.layout("teacher","teacher");fail("Duplicate layout accepted");}catch(IllegalArgumentException expected){}
            group.close();assertTrue(group.streams.isEmpty());assertTrue(group.urls.isEmpty());
            assertEquals(Player.STATE_IDLE,teacher.player.getPlaybackState());assertEquals(Player.STATE_IDLE,student.player.getPlaybackState());return null;
        });
    }

    @Test public void missingLocalAssetReportsErrorAndStops() throws Exception {
        create("asset:///missing-synthetic.m3u8");
        main(()->{group.play();return null;});
        await("asset failure",()->group.error!=null);
        main(()->{assertEquals("PLAYBACK",group.error);assertFalse(group.want);for(ClassroomPlayerGroup.Stream stream:group.streams.values())assertFalse(stream.player.getPlayWhenReady());return null;});
    }
}
