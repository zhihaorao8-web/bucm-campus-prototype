package cn.bucm.campusprobe;

import java.util.*;
import java.time.*;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;

/** Full-batch validation before any local write; exact duplicates retain occurrence counts. */
public final class CourseImportPlan {
    public static final class Entry {
        public final ScheduleParser.Candidate course;
        public final CourseTimes.Timing timing;
        public final String key;
        public int occurrences=1;
        Entry(ScheduleParser.Candidate c,CourseTimes.Timing t,String k){course=c;timing=t;key=k;}
    }
    public final List<Entry> entries;
    public final int sourceCount,duplicates;
    private CourseImportPlan(List<Entry> entries,int count){this.entries=Collections.unmodifiableList(entries);sourceCount=count;duplicates=count-entries.size();}
    public static CourseImportPlan create(List<ScheduleParser.Candidate> courses,LocalDate termMonday) {
        if(termMonday==null||termMonday.getDayOfWeek()!=DayOfWeek.MONDAY)throw new IllegalArgumentException("学期第1周起点必须为周一");
        if(courses.isEmpty())throw new IllegalArgumentException("没有可导入的排课");
        Map<String,Entry> unique=new LinkedHashMap<>();
        for(int i=0;i<courses.size();i++) {
            ScheduleParser.Candidate c=courses.get(i);
            try {
                if(c.name.trim().isEmpty()||c.day<1||c.day>7)throw new IllegalArgumentException("缺少课程名或星期无效");
                SortedSet<Integer> weeks=ScheduleParser.weeks(c.weeks);CourseTimes.Timing timing=CourseTimes.resolve(c);
                String identity=termMonday+"\u0000"+c.day+"\u0000"+c.name+"\u0000"+weeks+"\u0000"+timing.periods+"\u0000"+c.place+"\u0000"+c.raw.replace("\r\n","\n").trim();
                String key=hash(identity);Entry found=unique.get(key);
                if(found!=null)found.occurrences++;else unique.put(key,new Entry(c,timing,key));
            }catch(IllegalArgumentException e){throw new IllegalArgumentException("第"+(i+1)+"段排课："+e.getMessage());}
        }
        return new CourseImportPlan(new ArrayList<>(unique.values()),courses.size());
    }
    private static String hash(String text){try{byte[] digest=MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));StringBuilder out=new StringBuilder();for(byte b:digest)out.append(String.format(Locale.ROOT,"%02x",b&255));return out.toString();}catch(java.security.NoSuchAlgorithmException e){throw new IllegalStateException(e);}}
}
