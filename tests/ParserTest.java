import cn.bucm.campusprobe.ScheduleParser;
import java.util.*;
public class ParserTest {
 static void check(boolean b){if(!b)throw new AssertionError();}
 static void reject(String w){try{ScheduleParser.weeks(w);throw new AssertionError(w);}catch(IllegalArgumentException expected){}}
 public static void main(String[] args){
  check(ScheduleParser.weeks("1-8,10-16双").equals(new TreeSet<Integer>(Arrays.asList(2,4,6,8,10,12,14,16))));
  check(ScheduleParser.weeks("1-16(单周)").size()==8);
  reject("");reject("0-16");reject("16-1");reject("1-31");reject("1-16单双");reject("abc");
  ScheduleParser.Candidate c=ScheduleParser.parse("中医基础理论\n1-16周(单)\n第3-4节\n教室：教学楼101",2,"上午");
  check(c.name.equals("中医基础理论"));check(c.day==2);check(c.weeks.equals("1-16单"));check(c.periods.equals("3-4"));check(c.place.equals("教学楼101"));check(c.time.isEmpty());
  check(ScheduleParser.weekday("星期日")==7);check(ScheduleParser.minutes("23:59")==1439);
  try{ScheduleParser.minutes("24:00");throw new AssertionError();}catch(IllegalArgumentException expected){}
  check(ScheduleParser.parse("错误页面",1,"").weeks.isEmpty());
  c=ScheduleParser.parse("测试课程 测试课程   \t 张老师教师 \t 教学楼502室 \t 测试课程",1,"");
  check(c.name.equals("测试课程"));check(c.place.equals("教学楼502室"));
  System.out.println("Parser checks passed (ranges, parity, invalid weeks, no invented clock times)");
 }
}
