package cn.bucm.campus_schedule;

import android.app.Activity;
import androidx.media3.common.*;
import androidx.media3.datasource.DataSource;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.hls.HlsMediaSource;
import io.flutter.view.TextureRegistry;
import cn.bucm.campusprobe.ClassroomMediaTransport;
import java.util.*;

/** Native decoder/control lifetime, separated from the official WebView flow.
 * The production caller validates every descriptor and supplies the restricted
 * ClassroomDataSource. Only isolated instrumentation supplies an asset factory;
 * no alternate source or diagnostic command is exposed to Flutter.
 */
final class ClassroomPlayerGroup {
    final Activity activity;
    final TextureRegistry textures;
    final DataSource.Factory dataSources;
    final String id=UUID.randomUUID().toString(),watermark;
    final LinkedHashMap<String,String> urls=new LinkedHashMap<>();
    final LinkedHashMap<String,Stream> streams=new LinkedHashMap<>();
    String main,small,error;
    boolean want;
    float speed=1;

    ClassroomPlayerGroup(Activity activity,TextureRegistry textures,Map<String,String> sources,
            String watermark,DataSource.Factory dataSources) {
        this.activity=activity;this.textures=textures;this.dataSources=dataSources;this.watermark=watermark;
        if(sources.isEmpty()||sources.size()>3||!Arrays.asList("ppt","teacher","student").containsAll(sources.keySet()))
            throw new IllegalArgumentException();
        urls.putAll(sources);
        main=urls.containsKey("ppt")?"ppt":urls.keySet().iterator().next();
        small=urls.containsKey("teacher")&&!main.equals("teacher")?"teacher":null;
        try {layout(main,small);}catch(RuntimeException failure){close();throw failure;}
    }
    void play(){want=true;if(ended())seek(0);}
    void setSpeed(float next) {
        if(!Arrays.asList(.75f,1f,1.25f,1.5f,2f).contains(next))throw new IllegalArgumentException();
        speed=next;for(Stream s:streams.values())s.player.setPlaybackSpeed(speed);
    }
    void layout(String nextMain,String nextSmall) {
        if(!urls.containsKey(nextMain)||(nextSmall!=null&&(!urls.containsKey(nextSmall)||nextMain.equals(nextSmall))))
            throw new IllegalArgumentException();
        long position=master()==null?0:master().player.getCurrentPosition();
        main=nextMain;small=nextSmall;
        for(String kind:new ArrayList<>(streams.keySet()))if(!kind.equals(main)&&!kind.equals(small)){streams.remove(kind).close();}
        for(String kind:Arrays.asList(main,small))if(kind!=null&&!streams.containsKey(kind))streams.put(kind,new Stream(kind,position));
        for(Stream s:streams.values()) {
            boolean audible=s==master();
            s.player.setAudioAttributes(new AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),audible);
            s.player.setVolume(audible?1:0);
        }
    }
    Stream master(){return streams.containsKey("teacher")?streams.get("teacher"):streams.containsKey("student")?streams.get("student"):streams.get(main);}
    void pause(){want=false;activity.getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);for(Stream s:streams.values())s.player.pause();}
    void seek(long ms){long end=duration();long target=Math.max(0,end>0?Math.min(ms,end):ms);for(Stream s:streams.values())s.player.seekTo(target);}
    long duration(){long result=Long.MAX_VALUE;for(Stream s:streams.values()){long d=s.player.getDuration();if(d>0)result=Math.min(result,d);}return result==Long.MAX_VALUE?0:result;}
    boolean ended(){for(Stream s:streams.values())if(s.player.getPlaybackState()==Player.STATE_ENDED)return true;return false;}
    Map<String,Object> snapshot() {
        boolean ready=error==null&&!streams.isEmpty();
        for(Stream s:streams.values())ready&=s.player.getPlaybackState()==Player.STATE_READY;
        Stream clock=master();
        if(clock!=null&&ready&&want)for(Stream s:streams.values())if(s!=clock&&Math.abs(s.player.getCurrentPosition()-clock.player.getCurrentPosition())>400)s.player.seekTo(clock.player.getCurrentPosition());
        for(Stream s:streams.values())s.player.setPlayWhenReady(ready&&want);
        if(ready&&want)activity.getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        else activity.getWindow().clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        Map<String,Object> result=new HashMap<>();
        result.put("session",id);result.put("main",main);result.put("small",small);result.put("available",new ArrayList<>(urls.keySet()));
        result.put("playing",ready&&want);result.put("wanted",want);result.put("buffering",!ready&&error==null&&!ended());
        result.put("position",clock==null?0:clock.player.getCurrentPosition());result.put("duration",duration());result.put("speed",(double)speed);
        result.put("watermark",watermark);result.put("error",error);
        List<Map<String,Object>> values=new ArrayList<>();
        for(Stream s:streams.values()){
            VideoSize size=s.player.getVideoSize();Map<String,Object> item=new HashMap<>();
            item.put("kind",s.kind);item.put("texture",s.surface.id());item.put("width",size.width);item.put("height",size.height);item.put("ratio",size.height>0?(double)size.width*size.pixelWidthHeightRatio/size.height:16./9.);values.add(item);
        }
        result.put("textures",values);return result;
    }
    void close(){pause();for(Stream s:streams.values())s.close();streams.clear();urls.clear();}

    final class Stream {
        final String kind;
        final ExoPlayer player;
        final TextureRegistry.SurfaceProducer surface;
        Stream(String kind,long position) {
            this.kind=kind;
            surface=textures.createSurfaceProducer();surface.setSize(1280,720);
            try {player=new ExoPlayer.Builder(activity).build();}
            catch(RuntimeException failure){surface.release();throw failure;}
            try {
                player.setVideoSurface(surface.getSurface());
                surface.setCallback(new TextureRegistry.SurfaceProducer.Callback(){
                    @Override public void onSurfaceAvailable(){player.setVideoSurface(surface.getSurface());}
                    @Override public void onSurfaceCleanup(){pause();player.clearVideoSurface();}
                });
                player.addListener(new Player.Listener(){
                    @Override public void onPlaybackStateChanged(int state){if(state==Player.STATE_ENDED)pause();}
                    @Override public void onPlayWhenReadyChanged(boolean playing,int reason){
                        if(!playing&&reason==Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS)pause();
                    }
                    @Override public void onVideoSizeChanged(VideoSize size){if(size.width>0&&size.height>0)surface.setSize(size.width,size.height);}
                    @Override public void onPlayerError(PlaybackException failure){
                        error="PLAYBACK";
                        Throwable reason=failure;
                        for(int i=0;i<8&&reason!=null;i++,reason=reason.getCause())if(reason instanceof ClassroomMediaTransport.Failure)error=((ClassroomMediaTransport.Failure)reason).code;
                        pause();
                    }
                });
                player.setMediaSource(new HlsMediaSource.Factory(dataSources).createMediaSource(MediaItem.fromUri(urls.get(kind))));
                player.setPlaybackSpeed(speed);player.seekTo(position);player.prepare();
            }catch(RuntimeException failure){surface.setCallback(null);player.release();surface.release();throw failure;}
        }
        void close(){surface.setCallback(null);player.release();surface.release();}
    }
}
