package cn.bucm.campus_schedule;

import android.net.Uri;
import android.webkit.CookieManager;
import androidx.media3.common.C;
import androidx.media3.datasource.BaseDataSource;
import androidx.media3.datasource.DataSpec;
import cn.bucm.campusprobe.ClassroomMediaTransport;
import java.io.IOException;

/** Original Media3 adapter. Each nested playlist, segment and key uses the same
 * boundary, including redirects. No DefaultDataSource fallback to file/http.
 * Reference: https://developer.android.com/media/media3/exoplayer/customization
 */
final class ClassroomDataSource extends BaseDataSource {
    private final String referer, agent;
    private ClassroomMediaTransport transport;
    private boolean started;
    ClassroomDataSource(String referer,String agent) {super(true);this.referer=referer;this.agent=agent;}
    @Override public long open(DataSpec spec)throws IOException {
        transferInitializing(spec);
        if(spec.httpMethod!=DataSpec.HTTP_METHOD_GET||spec.httpBody!=null||!spec.httpRequestHeaders.isEmpty()) throw new ClassroomMediaTransport.Failure("METHOD");
        if(Uri.parse(referer).getHost().equals("webvpn.bucm.edu.cn")&&!"webvpn.bucm.edu.cn".equals(spec.uri.getHost())) throw new ClassroomMediaTransport.Failure("UNTRUSTED");
        transport=new ClassroomMediaTransport(target->CookieManager.getInstance().getCookie(target));
        try {
            long length=transport.open(spec.uri.toString(),referer,agent,spec.position,spec.length);
            started=true;transferStarted(spec);
            return length<0?C.LENGTH_UNSET:length;
        } catch(IOException error) {close();throw error;}
    }
    @Override public int read(byte[] buffer,int offset,int length)throws IOException {
        if(transport==null)throw new ClassroomMediaTransport.Failure("NOT_OPEN");
        int n=transport.read(buffer,offset,length);if(n>0)bytesTransferred(n);return n;
    }
    @Override public Uri getUri(){return transport==null||transport.resolved()==null?null:Uri.parse(transport.resolved());}
    @Override public void close(){if(transport!=null){transport.close();transport=null;}if(started){started=false;transferEnded();}}
}
