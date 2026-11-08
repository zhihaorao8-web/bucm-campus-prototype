package cn.bucm.campusprobe;
import android.content.*;
public class RestoreReceiver extends BroadcastReceiver {
 @Override public void onReceive(Context c,Intent i){ReminderReceiver.reschedule(c);}
}
