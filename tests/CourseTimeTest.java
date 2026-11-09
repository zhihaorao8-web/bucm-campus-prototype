import cn.bucm.campusprobe.*;
import java.time.*;
import java.util.*;
public class CourseTimeTest {
 static void check(boolean b){if(!b)throw new AssertionError();}
 static ScheduleParser.Candidate course(String p){return ScheduleParser.parse("合成课程\n示例教师\n1-8(周)["+p+"节]\n合成楼101室",1,"");}
 static void reject(String p){try{CourseTimes.resolve(course(p));throw new AssertionError();}catch(IllegalArgumentException expected){}}
 public static void main(String[] args){
  CourseTimes.Timing t=CourseTimes.resolve(course("01-02"));check(t.start().equals("08:30"));check(t.end().equals("10:00"));check(t.segments.size()==1);check(t.teachingMinutes()==90);
  t=CourseTimes.resolve(course("01-02-03"));check(t.segments.size()==2);check(t.end().equals("11:15"));check(t.teachingMinutes()==135);check(t.segments.get(0).end.equals("10:00"));check(t.segments.get(1).start.equals("10:30"));
  t=CourseTimes.resolve(course("01-02-03-04"));check(t.end().equals("12:00"));check(t.teachingMinutes()==180);
  t=CourseTimes.resolve(course("05+06"));check(t.start().equals("13:30"));check(t.end().equals("15:00"));
  t=CourseTimes.resolve(course("07-08"));check(t.start().equals("15:30"));check(t.end().equals("17:00"));
  t=CourseTimes.resolve(course("01-03"));check(t.periods.equals(Arrays.asList(1,3)));check(t.teachingMinutes()==90); // Explicit list is not a range.
  ScheduleParser.Candidate range=ScheduleParser.parse("合成课程\n1-8周\n第1-3节",1,"");check(CourseTimes.resolve(range).periods.equals(Arrays.asList(1,2,3)));
  reject("00");reject("03-02");reject("01-01");reject("13");reject("03-04-05");reject("07-08-09");
  for(String evening:new String[]{"09","09-10","09-10-11","09-10-11-12","11-12","12"}){t=CourseTimes.resolve(course(evening));check(t.start().equals("18:00"));check(t.end().equals("20:25"));check(t.segments.size()==1);check(t.teachingMinutes()==135);}
  ScheduleParser.Candidate a=course("01-02"),b=course("01-02"),c=course("03-04");CourseImportPlan plan=CourseImportPlan.create(Arrays.asList(a,b,c),LocalDate.of(2026,9,7));check(plan.sourceCount==3);check(plan.entries.size()==2);check(plan.duplicates==1);check(plan.entries.get(0).occurrences==2);
  b.raw=b.raw.replace("示例教师","另一示例教师");check(CourseImportPlan.create(Arrays.asList(a,b),LocalDate.of(2026,9,7)).entries.size()==2);
  check(AcademicTerm.find("合成学校2026-2027-1学期课表").equals("2026-2027-1"));check(AcademicTerm.find("2027-2028学年第2学期").equals("2027-2028-2"));check(AcademicTerm.knownStart("2026-2027-1").equals(LocalDate.of(2026,9,7)));check(AcademicTerm.knownStart("2027-2028-1")==null);
  try{AcademicTerm.find("2026-2027-1及2026-2027-2");throw new AssertionError();}catch(IllegalArgumentException expected){}
  c=course("01-02");c.time="08:00-09:30";try{CourseImportPlan.create(Arrays.asList(a,c),LocalDate.of(2026,9,7));throw new AssertionError();}catch(IllegalArgumentException expected){}
  try{CourseImportPlan.create(Arrays.asList(a),LocalDate.of(2026,9,8));throw new AssertionError();}catch(IllegalArgumentException expected){}
  System.out.println("Course time checks passed (fixed daytime slots, teaching segments, breaks, explicit lists, validation and exact deduplication)");
 }
}
