package cn.bucm.campusprobe;

import java.util.*;
import java.util.regex.*;

/** Conservative parser: returns candidates, never invents period-to-clock mappings. */
public final class ScheduleParser {
    private static final Pattern SCHOOL_SCHEDULE_LINE = Pattern.compile(
        "[0-9][0-9,、\\s-]*\\(周\\)(?:\\((?:单|双)(?:周)?\\))?\\[[0-9\\s,-]+节\\]"
    );

    public static final class Candidate {
        public String name="", teacher="", place="", raw="", weeks="", periods="", time="";
        public int day;
    }
    private static String normalize(String text) {
        return text.replace('（','(').replace('）',')').replace('－','-').replace('～','-').replace('—','-').replace('，',',');
    }
    public static int weekday(String s) {
        String[] names={"一","二","三","四","五","六","日"};
        for(int i=0;i<7;i++) if(s.matches("(?s).*?(?:星期|周|礼拜)\\s*"+names[i]+".*")) return i+1;
        if(s.contains("星期天")||s.contains("周天")) return 7;
        return 0;
    }
    /** Split only explicit block boundaries; same-name schedules remain separate. */
    public static List<Candidate> parseAll(String text,int day,String rowLabel) {
        List<Candidate> result=new ArrayList<>();
        for(String block:text.split("(?m)^\\s*[-_=─━—]{3,}\\s*$|\\r?\\n[\\t ]*\\r?\\n+")) {
            if(!block.trim().isEmpty())result.add(parse(block,day,rowLabel));
        }
        return result;
    }
    public static Candidate parse(String text,int day,String rowLabel) {
        Candidate c=new Candidate(); c.day=day;c.raw=text.trim();
        String s=normalize(text).replace("([周])","(周)");
        String[] lines=s.split("[\\r\\n]+");
        for(String line:lines) {line=line.trim();if(!line.isEmpty()){c.name=line.split("\\t+| {2,}")[0].trim();break;}}
        String[] words=c.name.split("\\s+");
        if(words.length>=2&&words[0].equals(words[1]))c.name=words[0];
        Matcher w=Pattern.compile("([0-9][0-9\\s,、\\-]*)(?:\\(周\\)|周)(?:\\s*[(]?(单|双)(?:周)?[)]?)?").matcher(s);
        if(w.find()) c.weeks=w.group(1).trim()+(w.group(2)==null?"":w.group(2));
        if(c.weeks.isEmpty()) {
            w=Pattern.compile("(?:周次|教学周)\\s*[:：]?\\s*([0-9][0-9\\s,、\\-]*)(单|双)?").matcher(s);
            if(w.find())c.weeks=w.group(1).trim()+(w.group(2)==null?"":w.group(2));
        }
        Matcher p=Pattern.compile("(?:第\\s*)?([0-9]+(?:\\s*[-,、]\\s*[0-9]+)*)\\s*节").matcher(s);
        if(p.find())c.periods=p.group(1);else c.periods=rowLabel;
        Matcher t=Pattern.compile("([012]?\\d:[0-5]\\d)\\s*[-至]\\s*([012]?\\d:[0-5]\\d)").matcher(s);
        if(t.find())c.time=t.group(1)+"-"+t.group(2);
        for(String line:lines) if(line.matches(".*(?:地点|教室|上课地点)\\s*[:：].*"))c.place=line.replaceFirst("^.*?(?:地点|教室)\\s*[:：]","").trim();
        if(c.place.isEmpty())for(String word:s.split("\\s+"))if(word.matches("[^:：]+[0-9]+室"))c.place=word;
        if(c.place.isEmpty()) {
            // School blocks place the unlabelled location after the schedule line.
            // Require one remaining line and location wording; do not guess from instructors or notes.
            for(int i=0;i<lines.length;i++) {
                if(!SCHOOL_SCHEDULE_LINE.matcher(lines[i].trim()).matches())continue;
                String location="";int count=0;
                for(int j=i+1;j<lines.length;j++)if(!lines[j].trim().isEmpty()){location=lines[j].trim();count++;}
                boolean locationFormat=location.matches(".*(?:楼|室|馆|场|区|厅).*")||location.matches("[\\p{IsHan}]{1,4}[0-9]{2,4}教");
                if(count==1&&locationFormat&&!location.matches("^(?:备注|说明|教师|周次|课程|时间)[:：].*"))c.place=location;
            }
        }
        if(!c.place.isEmpty()) {
            for(String original:text.split("[\\r\\n]+")) {
                String value=original.replaceFirst("^.*?(?:地点|教室)\\s*[:：]","").trim();
                if(normalize(value).equals(c.place)){c.place=value;break;}
            }
        }
        // Keep teacher text; accept a label or the sole line before the schedule.
        for(String line:lines)if(line.trim().matches("^(?:教师|任课教师|授课教师)\\s*[:：].+"))
            c.teacher=line.trim().replaceFirst("^(?:教师|任课教师|授课教师)\\s*[:：]\\s*", "");
        if(c.teacher.isEmpty()) {
            List<String> before=new ArrayList<>();
            boolean schoolScheduleLine = false;
            for(String line:lines) {
                line=line.trim();
                if(line.matches(".*[0-9].*(?:\\(周\\)|周次|教学周|周).*")) {
                    schoolScheduleLine = SCHOOL_SCHEDULE_LINE.matcher(line).matches();
                    break;
                }
                if(!line.isEmpty())before.add(line);
            }
            String teacher = before.size() == 2 ? before.get(1) : "";
            // The school inserts a parenthesized course annotation before the teacher.
            if (schoolScheduleLine && before.size() == 3
                && before.get(1).matches("\\(\\p{IsHan}{2}[0-9]{2}\\)")
                && before.get(2).matches("\\p{IsHan}{2,4}")
                && !before.get(2).matches("无|暂无|教师|任课教师|授课教师")
                && !before.get(2).equals(c.name)) {
                teacher = before.get(2);
            }
            if (!teacher.matches(".*(?:地点|教室|备注|说明|学期|节次|第.*节).*")) c.teacher = teacher;
        }
        return c;
    }
    public static SortedSet<Integer> weeks(String input) {
        if(input==null||input.trim().isEmpty())throw new IllegalArgumentException("请填写实际周次");
        String s=input.replace("周","").replace("第","").replace("(","").replace(")","").replace("（","").replace("）","").replace(" ","").replace('，',',').replace('、',',').replace('－','-').replace('～','-').replace('—','-');
        boolean odd=s.contains("单"),even=s.contains("双");
        if(odd&&even)throw new IllegalArgumentException("单双周不能同时指定");
        s=s.replace("单","").replace("双","");
        if(!s.matches("\\d+(?:-\\d+)?(?:,\\d+(?:-\\d+)?)*"))throw new IllegalArgumentException("周次格式示例：1-16单 或 1-8,10-16");
        SortedSet<Integer> result=new TreeSet<>();
        for(String part:s.split(",")) {
            String[] range=part.split("-");int a=Integer.parseInt(range[0]),b=range.length==1?a:Integer.parseInt(range[1]);
            if(a<1||b>30||a>b)throw new IllegalArgumentException("周次必须在1至30之间，且起始不大于结束");
            for(int n=a;n<=b;n++)if((!odd||n%2==1)&&(!even||n%2==0))result.add(n);
        }
        if(result.isEmpty())throw new IllegalArgumentException("所选周次没有实际课程");
        return result;
    }
    public static int minutes(String s) {
        if(!s.matches("(?:[01]?\\d|2[0-3]):[0-5]\\d"))throw new IllegalArgumentException("时间格式为 HH:mm");
        String[] a=s.split(":");return Integer.parseInt(a[0])*60+Integer.parseInt(a[1]);
    }
}
