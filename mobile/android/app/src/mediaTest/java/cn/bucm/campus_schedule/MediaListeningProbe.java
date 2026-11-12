package cn.bucm.campus_schedule;

import android.os.SystemClock;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import static org.junit.Assert.*;
import static org.junit.Assume.*;

/** Explicit listening probe using the production group and synthetic HLS only. */
public class MediaListeningProbe extends MediaPlaybackTest {
    @Test public void continuousAacThroughProductionGroup() throws Exception {
        assumeTrue("Manual listening only", "true".equals(InstrumentationRegistry.getArguments().getString("campusListen")));
        create("asset:///index.m3u8");
        await("listening first frames",()->ready()&&rendered.contains("ppt")&&rendered.contains("teacher"));
        main(()->{group.play();return null;});
        await("listening advancing",()->group.master().player.getCurrentPosition()>1000);
        long start=main(()->group.master().player.getCurrentPosition());
        long end=SystemClock.uptimeMillis()+30000;
        while(SystemClock.uptimeMillis()<end){
            main(()->{
                assertTrue((Boolean)group.snapshot().get("playing"));
                assertNull(group.error);
                assertNotNull(group.streams.get("teacher").player.getAudioFormat());
                assertNull(group.streams.get("ppt").player.getAudioFormat());
                return null;
            });
            SystemClock.sleep(200);
        }
        main(()->{assertTrue(group.master().player.getCurrentPosition()-start>=28000);return null;});
        // Passage and decoded-track checks do not assert subjective audio quality.
    }
}
