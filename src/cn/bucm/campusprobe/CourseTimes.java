package cn.bucm.campusprobe;

import java.util.*;
import java.util.regex.*;

/** User-supplied school clocks: split daytime breaks, show evening as one whole block. */
public final class CourseTimes {
    private static final String[] START={"08:30","09:15","10:30","11:15","13:30","14:15","15:30","16:15"};
    private static final String[] END={"09:15","10:00","11:15","12:00","14:15","15:00","16:15","17:00"};
    public static final class Segment {
        public final String start,end;
        Segment(String start,String end){this.start=start;this.end=end;}
        public int minutes(){return ScheduleParser.minutes(end)-ScheduleParser.minutes(start);}
    }
    public static final class Timing {
        public final List<Integer> periods;
        public final List<Segment> segments;
        private final int teachingMinutes;
        Timing(List<Integer> periods,List<Segment> segments,int minutes){this.periods=Collections.unmodifiableList(periods);this.segments=Collections.unmodifiableList(segments);teachingMinutes=minutes;}
        public String start(){return segments.get(0).start;}
        public String end(){return segments.get(segments.size()-1).end;}
        public int teachingMinutes(){return teachingMinutes;}
    }
    public static List<Integer> periods(ScheduleParser.Candidate c) {
        Matcher m=Pattern.compile("\\[([0-9\\s+,、-]+)节\\]").matcher(c.raw);
        boolean list=m.find();String expression=list?m.group(1):c.periods.replace("第","").replace("节","").trim();
        if(list&&m.find())throw new IllegalArgumentException("同一排课块有多组节次，无法自动导入");
        if(!expression.matches("[0-9]+(?:\\s*[-+,、]\\s*[0-9]+)*"))throw new IllegalArgumentException("无法识别节次");
        List<Integer> result=new ArrayList<>();
        String[] parts=expression.split("\\s*[-+,、]\\s*");
        if(!list&&parts.length==2&&expression.contains("-")) {
            int a=Integer.parseInt(parts[0]),b=Integer.parseInt(parts[1]);
            if(a>b||b-a>20)throw new IllegalArgumentException("节次范围无效");
            for(int n=a;n<=b;n++)result.add(n);
        } else for(String part:parts)result.add(Integer.parseInt(part));
        int previous=0;
        for(int period:result){if(period<=previous||period>12)throw new IllegalArgumentException("节次必须递增且在1至12之间");previous=period;}
        if(result.isEmpty())throw new IllegalArgumentException("缺少节次");return result;
    }
    public static Timing resolve(ScheduleParser.Candidate c) {
        List<Integer> periods=periods(c);List<Segment> segments=new ArrayList<>();
        int first=periods.get(0),last=periods.get(periods.size()-1);
        if((first<=4&&last>=5)||(first<=8&&last>=9))throw new IllegalArgumentException("学校不设置跨午休或晚餐的连排课");
        if(first>=9){segments.add(new Segment("18:00","20:25"));Timing result=new Timing(periods,segments,135);validateExplicitTime(c,result);return result;}
        for(int p:periods) {
            if(p>START.length)throw new IllegalArgumentException("第"+p+"节的准确时间尚待补充");
            String start=START[p-1],end=END[p-1];
            if(!segments.isEmpty()&&segments.get(segments.size()-1).end.equals(start)) {
                Segment previous=segments.remove(segments.size()-1);segments.add(new Segment(previous.start,end));
            } else segments.add(new Segment(start,end));
        }
        Timing result=new Timing(periods,segments,periods.size()*45);
        validateExplicitTime(c,result);
        return result;
    }
    private static void validateExplicitTime(ScheduleParser.Candidate c,Timing result){if(!c.time.isEmpty()&&!c.time.equals(result.start()+"-"+result.end()))throw new IllegalArgumentException("网页钟点时间与学校节次规则不一致");}
}
