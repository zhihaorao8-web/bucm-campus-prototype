package cn.bucm.campusprobe;

import java.io.*;
import java.net.*;

/** In-memory official export download. Never persists credentials or request URLs. */
public final class SchoolExport {
    public interface Cookies { String get(String url); }
    public static final int MAX_BYTES=4*1024*1024;
    public static boolean allowed(String value) {
        try {URI u=new URI(value);String h=u.getHost();return "https".equalsIgnoreCase(u.getScheme())&&u.getRawUserInfo()==null&&h!=null&&(h.equals("bucm.edu.cn")||h.endsWith(".bucm.edu.cn"))&&(u.getPort()==-1||u.getPort()==443);}
        catch(Exception e){return false;}
    }
    public static byte[] download(String address,String agent,Cookies cookies) throws IOException {
        String next=address;
        for(int redirects=0;redirects<=5;redirects++) {
            if(!allowed(next))throw new IOException("UNTRUSTED_EXPORT");
            HttpURLConnection c=(HttpURLConnection)new URL(next).openConnection();
            c.setInstanceFollowRedirects(false);c.setConnectTimeout(15000);c.setReadTimeout(20000);
            c.setRequestProperty("User-Agent",agent);
            String session=cookies.get(next);if(session!=null&&!session.isEmpty())c.setRequestProperty("Cookie",session);
            c.setRequestProperty("Accept-Encoding","identity");
            try {
                int code=c.getResponseCode();
                if(code==301||code==302||code==303||code==307||code==308) {
                    String location=c.getHeaderField("Location");
                    if(location==null)throw new IOException("EXPORT_REDIRECT");
                    next=new URL(new URL(next),location).toString();continue;
                }
                if(code!=200)throw new IOException("EXPORT_HTTP");
                if(c.getContentLengthLong()>MAX_BYTES)throw new IOException("EXPORT_TOO_LARGE");
                try(InputStream in=c.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()) {
                    byte[] block=new byte[8192];int n;
                    while((n=in.read(block))!=-1){if(out.size()+n>MAX_BYTES)throw new IOException("EXPORT_TOO_LARGE");out.write(block,0,n);}
                    return out.toByteArray();
                }
            } finally {c.disconnect();}
        }
        throw new IOException("EXPORT_REDIRECT_LIMIT");
    }
    public static String format(byte[] bytes) {
        if(bytes.length>=8&&(bytes[0]&255)==0xd0&&(bytes[1]&255)==0xcf)return "XLS二进制";
        if(bytes.length>=4&&bytes[0]=='P'&&bytes[1]=='K')return "XLSX/ZIP";
        String start=new String(bytes,0,Math.min(bytes.length,4096),java.nio.charset.StandardCharsets.UTF_8).toLowerCase(java.util.Locale.ROOT);
        if(start.contains("<html")||start.contains("<table"))return "HTML表格";
        if(start.contains("<workbook")||start.contains(":workbook"))return "XML工作簿";
        return "未知格式";
    }
}
