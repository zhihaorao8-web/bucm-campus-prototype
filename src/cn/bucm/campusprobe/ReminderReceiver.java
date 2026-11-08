package cn.bucm.campusprobe;

import android.app.*;
import android.content.*;
import android.os.Build;
import org.json.*;
import java.time.*;
import java.util.*;

public class ReminderReceiver extends BroadcastReceiver {
    public static boolean exactAllowed(Context c){return Build.VERSION.SDK_INT<31||((AlarmManager)c.getSystemService(Context.ALARM_SERVICE)).canScheduleExactAlarms();}
    static void schedule(Context c,long when,PendingIntent intent){
        AlarmManager am=(AlarmManager)c.getSystemService(Context.ALARM_SERVICE);
        if(exactAllowed(c))am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,when,intent);
        else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,when,intent);
    }
    public static class Occurrence {public long start,end;public String label,place;}
    static SharedPreferences prefs(Context c){return c.getSharedPreferences("MainActivity",0);}
    public static ArrayList<Occurrence> occurrences(Context c){
        ArrayList<Occurrence> list=new ArrayList<>();try{
            SharedPreferences p=prefs(c);JSONArray a=new JSONArray(p.getString("lessons","[]"));LocalDate term=LocalDate.parse(p.getString("term",LocalDate.now().toString()));
            for(int i=0;i<a.length();i++){JSONObject o=a.getJSONObject(i);for(int week:ScheduleParser.weeks(o.getString("weeks"))){
                LocalDate date=term.plusDays((week-1)*7+o.getInt("day")-1);Occurrence event=new Occurrence();event.label=o.getString("name");event.place=o.optString("place");
                event.start=date.atStartOfDay(ZoneId.of("Asia/Shanghai")).plusMinutes(ScheduleParser.minutes(o.getString("start"))).toInstant().toEpochMilli();event.end=date.atStartOfDay(ZoneId.of("Asia/Shanghai")).plusMinutes(ScheduleParser.minutes(o.getString("end"))).toInstant().toEpochMilli();list.add(event);
            }}
        }catch(Exception e){list.clear();}list.sort((a,b)->Long.compare(a.start,b.start));return list;
    }
    static PendingIntent pending(Context c,int id,Occurrence o){Intent i=new Intent(c,ReminderReceiver.class);if(o!=null)i.putExtra("name",o.label).putExtra("place",o.place).putExtra("end",o.end);return PendingIntent.getBroadcast(c,id,i,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);}
    public static void reschedule(Context c){
        AlarmManager am=(AlarmManager)c.getSystemService(Context.ALARM_SERVICE);SharedPreferences p=prefs(c);int old=p.getInt("alarmCount",0);
        for(int i=0;i<old;i++)am.cancel(pending(c,i,null));
        if(!p.getBoolean("remind",false))am.cancel(pending(c,10000,null));
        int n=0;if(p.getBoolean("remind",false)&&p.getBoolean("termVerified",false)){long now=System.currentTimeMillis();for(Occurrence o:occurrences(c)){long trigger=o.start-600000;if(trigger>now&&n<120){schedule(c,trigger,pending(c,n++,o));}}}
        p.edit().putInt("alarmCount",n).apply();
    }
    public static void test(Context c){
        Occurrence o=new Occurrence();o.label="课前提醒测试";o.place="通知已送达 · 本次测试不修改课表";o.end=System.currentTimeMillis()+3600000;
        schedule(c,System.currentTimeMillis()+60000,pending(c,10000,o));
        prefs(c).edit().putLong("testScheduledAt",System.currentTimeMillis()).putString("lastReminderError","").commit();
    }
    public static void testNow(Context c){Intent i=new Intent(c,ReminderReceiver.class).putExtra("name","即时通知测试").putExtra("place","本次测试不修改课表").putExtra("end",System.currentTimeMillis()+3600000);new ReminderReceiver().onReceive(c,i);}
    @Override public void onReceive(Context c,Intent i){
        prefs(c).edit().putLong("lastAlarmReceivedAt",System.currentTimeMillis()).commit();
        if(!prefs(c).getBoolean("remind",false)||i.getLongExtra("end",0)<System.currentTimeMillis()){prefs(c).edit().putString("lastReminderError","提醒已关闭或消息已过期").commit();return;}
        NotificationManager nm=(NotificationManager)c.getSystemService(Context.NOTIFICATION_SERVICE);nm.createNotificationChannel(new NotificationChannel("classes","课前提醒",NotificationManager.IMPORTANCE_DEFAULT));
        PendingIntent open=PendingIntent.getActivity(c,0,new Intent(c,MainActivity.class),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        Notification n=new Notification.Builder(c,"classes").setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle(i.getStringExtra("name")).setContentText("即将上课 · "+i.getStringExtra("place")).setContentIntent(open).setAutoCancel(true).build();
        try{if(!nm.areNotificationsEnabled()){prefs(c).edit().putString("lastReminderError","系统禁止本应用通知").commit();return;}nm.notify((int)(System.currentTimeMillis()&0x7fffffff),n);prefs(c).edit().putLong("lastNotificationSentAt",System.currentTimeMillis()).putString("lastReminderError","").commit();}catch(SecurityException e){prefs(c).edit().putString("lastReminderError","通知权限被拒绝").commit();}
        // Refresh the rolling window so an entire term is not limited to 120 alarms.
        reschedule(c);
    }
}
