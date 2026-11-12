package cn.bucm.campus_schedule;

import android.media.*;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import static org.junit.Assert.*;
import static org.junit.Assume.*;

/** Explicit local listening comparison, never school audio or a production entry. */
public class AudioListeningProbe {
    @Test public void regularToneThroughAndroidOutput() {
        assumeTrue("Manual listening only", "true".equals(InstrumentationRegistry.getArguments().getString("campusListen")));
        assertEquals("cn.bucm.campus_schedule.mediatest",InstrumentationRegistry.getInstrumentation().getTargetContext().getPackageName());
        int rate=48000;
        AudioTrack track=new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).build())
                .setAudioFormat(new AudioFormat.Builder().setSampleRate(rate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(Math.max(rate/5,AudioTrack.getMinBufferSize(rate,AudioFormat.CHANNEL_OUT_MONO,AudioFormat.ENCODING_PCM_16BIT)*4)).build();
        try {
            short[] second=new short[rate];
            // 0.7 seconds of quiet tone, then 0.3 seconds silence; faded edges.
            for(int i=0;i<rate*7/10;i++){
                double fade=Math.min(1,Math.min(i/480.0,(rate*.7-i)/480.0));
                second[i]=(short)(32767*.10*fade*Math.sin(2*Math.PI*440*i/rate));
            }
            track.play();
            for(int i=0;i<30;i++)assertEquals(rate,track.write(second,0,rate,AudioTrack.WRITE_BLOCKING));
        } finally {track.stop();track.release();}
        // Completion proves delivery to AudioTrack, never subjective audibility.
    }
}
