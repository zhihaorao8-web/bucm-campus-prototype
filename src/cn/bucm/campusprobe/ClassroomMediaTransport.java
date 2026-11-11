package cn.bucm.campusprobe;

import java.io.*;
import java.net.*;
import java.util.Locale;

/** Streaming school media only. Credentials stay in the caller's native boundary.
 * Original implementation; Media3 DataSource design reference:
 * https://developer.android.com/media/media3/exoplayer/customization
 */
public final class ClassroomMediaTransport implements Closeable {
    public interface Cookies { String get(String target); }
    public interface Connections { HttpURLConnection open(URL target) throws IOException; }
    public static final class Failure extends IOException {
        public final String code;
        public Failure(String code) { super(code); this.code=code; }
    }
    private static final long MAX_RESPONSE=64L*1024*1024;
    public static final String VPN_MEDIA="/https-8880/77726476706e69737468656265737421e1ef4a88737e6a457d05c7a99c406d3652/";
    public static final String VPN_MEDIA2="/https-8880/77726476706e69737468656265737421e1ef4a88757e6a457d05c7a99c406d3643/";
    public static final String VPN_MEDIA3="/https-8880/77726476706e69737468656265737421e1ef4a88747e6a457d05c7a99c406d3626/";
    private final Cookies cookies;
    private final Connections connections;
    private volatile boolean closed;
    private volatile HttpURLConnection connection;
    private volatile InputStream input;
    private long remaining=-1;
    private long received;
    private String resolved;

    public ClassroomMediaTransport(Cookies cookies) {
        this(cookies, url -> (HttpURLConnection)url.openConnection());
    }
    public ClassroomMediaTransport(Cookies cookies, Connections connections) {
        this.cookies=cookies; this.connections=connections;
    }
    public static boolean allowed(String address) {
        try {
            if(address==null||address.length()>8192) return false;
            URI u=new URI(address);
            if(!"https".equals(u.getScheme())||u.getRawUserInfo()!=null||u.getRawFragment()!=null) return false;
            String host=u.getHost(), path=u.getRawPath();
            if(host==null||path==null||!path.startsWith("/")) return false;
            String lower=path.toLowerCase(Locale.ROOT);
            if(lower.contains("%2e")||lower.contains("%2f")||lower.contains("%5c")) return false;
            // Preserve empty path segments; reject traversal without rewriting.
            for(String part:path.split("/",-1))if(part.equals(".")||part.equals(".."))return false;
            return (("qxkt4.bucm.edu.cn".equals(host)||"qxkt2.bucm.edu.cn".equals(host)||"qxkt3.bucm.edu.cn".equals(host))&&u.getPort()==8880)||
                ("qhz.bucm.edu.cn".equals(host)&&(u.getPort()==-1||u.getPort()==443))||
                ("webvpn.bucm.edu.cn".equals(host)&&(u.getPort()==-1||u.getPort()==443)&&(path.startsWith(VPN_MEDIA)||path.startsWith(VPN_MEDIA2)||path.startsWith(VPN_MEDIA3)));
            // Exact public host/port mapping observed in the authorized session;
            // it is not a login token and does not allow arbitrary VPN targets.
        } catch(Exception error) { return false; }
    }
    private void checkOpen() throws Failure { if(closed) throw new Failure("CANCELLED"); }
    public long open(String address, String referer, String agent, long position, long length) throws IOException {
        if(connection!=null||input!=null) throw new Failure("ALREADY_OPEN");
        if(position<0||length==0||length< -1||length>MAX_RESPONSE||
           (length>0&&position>Long.MAX_VALUE-length)) throw new Failure("RANGE");
        if(referer!=null&&!referer.isEmpty()&&!officialPage(referer)) throw new Failure("UNTRUSTED");
        if(agent==null||agent.length()>1024||agent.contains("\r")||agent.contains("\n")) throw new Failure("HEADERS");
        String next=address;
        boolean vpn=address!=null&&address.startsWith("https://webvpn.bucm.edu.cn/");
        try {
            for(int redirects=0;redirects<=5;redirects++) {
                checkOpen();
                if(!allowed(next)||(vpn&&!"webvpn.bucm.edu.cn".equals(new URI(next).getHost()))) throw new Failure("UNTRUSTED");
                HttpURLConnection c=connections.open(new URL(next));
                connection=c;
                checkOpen();
                c.setInstanceFollowRedirects(false);
                c.setConnectTimeout(10000); c.setReadTimeout(15000);
                c.setRequestProperty("Accept-Encoding","identity");
                c.setRequestProperty("User-Agent",agent);
                // Always look up for this exact, validated target, including redirects.
                String session=cookies.get(next);
                if(session!=null&&!session.isEmpty()) c.setRequestProperty("Cookie",session);
                // Never forward a source-page URL across different origins.
                if(referer!=null&&sameOrigin(next,referer)) c.setRequestProperty("Referer",referer);
                if(position>0||length>0) c.setRequestProperty("Range","bytes="+position+"-"+(length>0?position+length-1:""));
                int status=c.getResponseCode();
                checkOpen();
                if(status==301||status==302||status==303||status==307||status==308) {
                    String location=c.getHeaderField("Location");
                    if(location==null) throw new Failure("REDIRECT");
                    next=new URL(new URL(next),location).toString();
                    c.disconnect();connection=null;
                    continue;
                }
                if(status==401) throw new Failure("AUTHENTICATION");
                if(status==403) throw new Failure("FORBIDDEN");
                if(status!=200&&status!=206) throw new Failure("HTTP");
                String type=c.getContentType();
                if(type!=null&&(type.toLowerCase(Locale.ROOT).contains("text/html")||type.toLowerCase(Locale.ROOT).contains("application/json"))) throw new Failure("AUTHENTICATION");
                String encoding=c.getContentEncoding();
                if(encoding!=null&&!encoding.equalsIgnoreCase("identity")) throw new Failure("ENCODING");
                long size=c.getContentLengthLong();
                if(size>MAX_RESPONSE) throw new Failure("TOO_LARGE");
                if(status==206) {
                    String range=c.getHeaderField("Content-Range");
                    if(range==null) throw new Failure("RANGE");
                    java.util.regex.Matcher match=java.util.regex.Pattern.compile("bytes (\\d+)-(\\d+)/(\\d+|\\*)").matcher(range);
                    if(!match.matches()) throw new Failure("RANGE");
                    long start=Long.parseLong(match.group(1)),end=Long.parseLong(match.group(2));
                    if(start!=position||end<start||end-start>=MAX_RESPONSE||
                        (!match.group(3).equals("*")&&Long.parseLong(match.group(3))<=end)||
                        (size>=0&&size!=end-start+1)) throw new Failure("RANGE");
                }
                input=c.getInputStream();
                if(status==200&&position>0) {
                    if(position>MAX_RESPONSE) throw new Failure("RANGE");
                    byte[] skip=new byte[8192];long left=position;
                    while(left>0) {checkOpen();int n=input.read(skip,0,(int)Math.min(left,skip.length));if(n<0) throw new Failure("RANGE");left-=n;}
                    if(size>=0) size-=position;
                }
                remaining=length>0?(size>=0?Math.min(length,size):length):size;
                resolved=next;
                checkOpen();
                return remaining;
            }
            throw new Failure("REDIRECT_LIMIT");
        } catch(Failure error) {close();throw error;}
        catch(Exception error) {boolean cancelled=closed;close();throw new Failure(cancelled?"CANCELLED":error instanceof javax.net.ssl.SSLException?"CERTIFICATE":"NETWORK");}
    }
    public int read(byte[] buffer,int offset,int count) throws IOException {
        checkOpen();
        if(count==0)return 0;
        if(input==null)throw new Failure("NOT_OPEN");
        if(remaining==0)return -1;
        try {
            int n=input.read(buffer,offset,remaining>0?(int)Math.min(count,remaining):count);
            if(n<0&&remaining>0) throw new Failure("TRUNCATED");
            if(n>0&&(received+=n)>MAX_RESPONSE) {close();throw new Failure("TOO_LARGE");}
            if(n>0&&remaining>0)remaining-=n;
            return n;
        } catch(Failure error){throw error;}
        catch(Exception error){throw new Failure(closed?"CANCELLED":"NETWORK");}
    }
    /** Internal use only: never return this address to Flutter or diagnostic logs. */
    public String resolved() { return resolved; }
    private static boolean officialPage(String address) {
        try {URI u=new URI(address);return "https".equals(u.getScheme())&&u.getRawUserInfo()==null&&u.getRawFragment()==null&&(u.getPort()==-1||u.getPort()==443)&&("qhz.bucm.edu.cn".equals(u.getHost())||"webvpn.bucm.edu.cn".equals(u.getHost()));}
        catch(Exception error){return false;}
    }
    private static boolean sameOrigin(String a,String b) {
        try {URL x=new URL(a),y=new URL(b);return x.getProtocol().equals(y.getProtocol())&&x.getHost().equals(y.getHost())&&(x.getPort()==-1?443:x.getPort())==(y.getPort()==-1?443:y.getPort());}
        catch(Exception error){return false;}
    }
    @Override public void close() {
        closed=true;
        HttpURLConnection c=connection;connection=null;
        if(c!=null)c.disconnect();
        InputStream stream=input;input=null;
        if(stream!=null)try{stream.close();}catch(IOException ignored){}
        resolved=null;remaining=-1;
    }
}
