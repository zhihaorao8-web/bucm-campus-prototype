import cn.bucm.campusprobe.ClassroomMediaTransport;
import java.io.*;
import java.net.*;
import java.util.*;

/** No sockets or school session: fake HTTPS connections exercise actual requests. */
public final class ClassroomMediaTest {
    static final String MEDIA="https://qxkt4.bucm.edu.cn:8880/synthetic/index.m3u8";
    static final String QHZ="https://qhz.bucm.edu.cn/synthetic/segment.ts";
    static void check(boolean v){if(!v)throw new AssertionError();}
    static final class Fake extends HttpURLConnection {
        final byte[] bytes; int status=200; String location,type="video/mp2t",range;long size;
        boolean disconnected;
        Fake(String address,byte[] bytes)throws Exception{super(new URL(address));this.bytes=bytes;size=bytes.length;}
        public void connect(){} public void disconnect(){disconnected=true;} public boolean usingProxy(){return false;}
        public int getResponseCode(){return status;}
        public InputStream getInputStream(){return new ByteArrayInputStream(bytes);}
        public String getHeaderField(String n){return n.equals("Location")?location:n.equals("Content-Range")?range:null;}
        public String getContentType(){return type;}
        public long getContentLengthLong(){return size;}
    }
    interface Checked {void run()throws Exception;}
    static void failure(String code,Checked action)throws Exception {
        try{action.run();throw new AssertionError("Expected "+code);}
        catch(ClassroomMediaTransport.Failure e){check(e.code.equals(code));check(e.getCause()==null);check(e.getMessage().equals(code));}
    }
    static ClassroomMediaTransport transport(Fake... responses){
        Queue<Fake> queue=new ArrayDeque<>(Arrays.asList(responses));
        return new ClassroomMediaTransport(url->url.startsWith("https://qhz.")?"synthetic=qhz":"synthetic=media",url->{Fake f=queue.remove();check(f.getURL().equals(url));return f;});
    }
    public static void main(String[] args)throws Exception {
        check(ClassroomMediaTransport.allowed(MEDIA));check(ClassroomMediaTransport.allowed(QHZ));
        check(ClassroomMediaTransport.allowed("https://qxkt2.bucm.edu.cn:8880//synthetic//index.m3u8"));
        check(ClassroomMediaTransport.allowed("https://webvpn.bucm.edu.cn"+ClassroomMediaTransport.VPN_MEDIA2+"/synthetic//index.m3u8"));
        check(ClassroomMediaTransport.allowed("https://webvpn.bucm.edu.cn"+ClassroomMediaTransport.VPN_MEDIA+"synthetic/segment.ts"));
        check(ClassroomMediaTransport.allowed("https://qxkt2.bucm.edu.cn:8880/synthetic/index.m3u8"));
        check(ClassroomMediaTransport.allowed("https://webvpn.bucm.edu.cn"+ClassroomMediaTransport.VPN_MEDIA2+"synthetic/segment.ts"));
        check(!ClassroomMediaTransport.allowed("https://qxkt3.bucm.edu.cn:8880/synthetic/index.m3u8"));
        check(!ClassroomMediaTransport.allowed("https://webvpn.bucm.edu.cn"+ClassroomMediaTransport.VPN_MEDIA+"%2e%2e/other"));
        for(String bad:new String[]{"http://qxkt4.bucm.edu.cn:8880/x","https://qxkt4.bucm.edu.cn/x","https://qhz.bucm.edu.cn:8880/x","https://qhz.bucm.edu.cn.evil.test/x","https://u:p@qhz.bucm.edu.cn/x","https://webvpn.bucm.edu.cn/https/arbitrary/x","file:///x","https://qhz.bucm.edu.cn/a/../x","https://qhz.bucm.edu.cn/%2e%2e/x",MEDIA+"#secret"}) check(!ClassroomMediaTransport.allowed(bad));
        // Range ignored by server: skip the prefix and cap reads to requested size.
        Fake f=new Fake(MEDIA,new byte[]{0,1,2,3,4});
        ClassroomMediaTransport t=transport(f);
        check(t.open(MEDIA,"https://qhz.bucm.edu.cn/coursePlatform/","Synthetic",2,2)==2);
        check("bytes=2-3".equals(f.getRequestProperty("Range")));
        check(f.getRequestProperty("Referer")==null);
        check("synthetic=media".equals(f.getRequestProperty("Cookie")));
        check(!f.getInstanceFollowRedirects());
        byte[] b=new byte[20];check(t.read(b,0,20)==2&&b[0]==2&&b[1]==3);check(t.read(b,0,20)==-1);t.close();check(f.disconnected);failure("CANCELLED",()->t.read(b,0,1));
        // Redirect target gets its own credentials; source cookies never forwarded.
        Fake first=new Fake(MEDIA,new byte[0]);first.status=302;first.location=QHZ;
        Fake last=new Fake(QHZ,new byte[]{9});
        ClassroomMediaTransport redirected=transport(first,last);
        redirected.open(MEDIA,"https://qhz.bucm.edu.cn/coursePlatform/","Synthetic",0,-1);
        check("synthetic=qhz".equals(last.getRequestProperty("Cookie")));
        check(last.getRequestProperty("Referer").startsWith("https://qhz."));redirected.close();
        // Untrusted/downgrade redirects rejected before connection or cookie lookup.
        for(String target:new String[]{"http://qhz.bucm.edu.cn/x","https://evil.test/x"}) {
            Fake redir=new Fake(MEDIA,new byte[0]);redir.status=302;redir.location=target;
            ClassroomMediaTransport r=transport(redir);failure("UNTRUSTED",()->r.open(MEDIA,"","Synthetic",0,-1));check(redir.disconnected);
        }
        String vpn="https://webvpn.bucm.edu.cn"+ClassroomMediaTransport.VPN_MEDIA+"synthetic/index.m3u8";
        Fake escape=new Fake(vpn,new byte[0]);escape.status=302;escape.location=MEDIA;
        failure("UNTRUSTED",()->transport(escape).open(vpn,"https://webvpn.bucm.edu.cn/","Synthetic",0,-1));
        for(int code:new int[]{401,403,500}) {
            Fake denied=new Fake(MEDIA,new byte[0]);denied.status=code;
            ClassroomMediaTransport r=transport(denied);failure(code==401?"AUTHENTICATION":code==403?"FORBIDDEN":"HTTP",()->r.open(MEDIA,"","Synthetic",0,-1));
        }
        Fake html=new Fake(MEDIA,new byte[0]);html.type="text/html;charset=utf-8";
        failure("AUTHENTICATION",()->transport(html).open(MEDIA,"","Synthetic",0,-1));
        Fake partial=new Fake(MEDIA,new byte[]{2,3});partial.status=206;partial.range="bytes 2-3/5";
        ClassroomMediaTransport p=transport(partial);check(p.open(MEDIA,"","Synthetic",2,2)==2);p.close();
        partial.range="bytes 0-1/5";failure("RANGE",()->transport(partial).open(MEDIA,"","Synthetic",2,2));
        Fake truncated=new Fake(MEDIA,new byte[0]);truncated.size=20;
        ClassroomMediaTransport shortRead=transport(truncated);shortRead.open(MEDIA,"","Synthetic",0,-1);failure("TRUNCATED",()->shortRead.read(b,0,20));shortRead.close();
        Fake huge=new Fake(MEDIA,new byte[0]);huge.size=65L*1024*1024;failure("TOO_LARGE",()->transport(huge).open(MEDIA,"","Synthetic",0,-1));
        ClassroomMediaTransport network=new ClassroomMediaTransport(url->null,url->{throw new IOException("sensitive "+MEDIA);});
        failure("NETWORK",()->network.open(MEDIA,"","Synthetic",0,-1));
        failure("RANGE",()->transport().open(MEDIA,"","Synthetic",Long.MAX_VALUE,2));
        System.out.println("Classroom media transport synthetic checks passed; no network used.");
    }
}
