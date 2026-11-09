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
  // Entirely synthetic school-format cell: one name, three distinct schedules.
  String block1="合成课程甲\n示例教师甲\n9-17(周)[01-02-03节]\n合成楼101室";
  String block2="合成课程甲\n示例教师乙\n4-8(周)[01-02-03节]\n合成楼202室";
  String block3="合成课程甲\n示例教师甲\n1-3(周)[01-02-03-04节]\n合成楼101室";
  List<ScheduleParser.Candidate> blocks=ScheduleParser.parseAll(block1+"\n---------------------\n"+block2+"\n---------------------\n"+block3,1,"上午");
  check(blocks.size()==3);
  String[] expectedWeeks={"9-17","4-8","1-3"};
  for(int i=0;i<3;i++) {
   c=blocks.get(i);check(c.name.equals("合成课程甲"));check(c.day==1);
   check(c.weeks.equals(expectedWeeks[i]));check(!ScheduleParser.weeks(c.weeks).isEmpty());
   check(c.periods.equals(i==2?"01-02-03-04":"01-02-03"));check(c.time.isEmpty());
   check(!c.raw.contains("---------------------"));
  }
  check(blocks.get(0).place.equals("合成楼101室"));check(blocks.get(1).place.equals("合成楼202室"));
  check(!blocks.get(0).raw.contains("示例教师乙"));
  check(ScheduleParser.parseAll(block1+"\r\n\r\n"+block2,3,"").size()==2);
  check(ScheduleParser.parseAll(block1+"\n---\n"+block1,1,"").size()==2); // No silent deduplication.
  check(ScheduleParser.parseAll("\n---\n",1,"").isEmpty());
  c=ScheduleParser.parse("合成课程乙\n2－10（周）（双周）[05-06节]",4,"");
  check(c.weeks.equals("2-10双"));check(ScheduleParser.weeks(c.weeks).size()==5);check(c.periods.equals("05-06"));
  c=ScheduleParser.parse("合成课程丙\n周次：1-8,10-16单",5,"第7-8节");
  check(c.weeks.equals("1-8,10-16单"));check(c.periods.equals("第7-8节"));check(c.time.isEmpty());
  c=ScheduleParser.parse("合成课程丁\n示例教师\n2-8(周)[05-06节]\n示例楼A区",2,"");
  check(c.place.equals("示例楼A区"));
  c=ScheduleParser.parse("合成课程丁\n示例教师\n12(周)[09节]\n示东901教",2,"");
  check(c.weeks.equals("12"));check(c.periods.equals("09"));check(c.place.equals("示东901教"));
  c=ScheduleParser.parse("合成课程丁\n示例教师\n9-17([周])[01-02-03节]\n示东901教",2,"");
  check(c.weeks.equals("9-17"));check(c.periods.equals("01-02-03"));check(c.place.equals("示东901教"));check(c.raw.contains("([周])"));
  c=ScheduleParser.parse("合成课程丁\n示例教师\n2-8(周)[05-06节]\n示例馆（东区）",2,"");
  check(c.place.equals("示例馆（东区）")); // Keep location punctuation exactly as published.
  c=ScheduleParser.parse("合成课程丁\n2-8周\n教室：示例楼（A区）",2,"");
  check(c.place.equals("示例楼（A区）"));
  c=ScheduleParser.parse("合成课程戊\n示例教师\n2-8(周)[05-06节]",2,"");
  check(c.place.isEmpty()); // Never substitute the preceding instructor for a missing location.
  c=ScheduleParser.parse("合成课程己\n示例教师\n2-8(周)[05-06节]\n备注：待安排",2,"");
  check(c.place.isEmpty());
  c=ScheduleParser.parse("合成课程庚\n示例教师\n2-8(周)[05-06节]\n备注：教室待安排",2,"");
  check(c.place.isEmpty());
  c=ScheduleParser.parse("合成课程辛\n示例教师\n2-8(周)[05-06节]\n示例楼A区\n额外说明",2,"");
  check(c.place.isEmpty()); // Ambiguous multiple trailing lines require review.
  System.out.println("Parser checks passed (school blocks, locations, ranges, parity, invalid weeks, no invented clock times)");
 }
}
