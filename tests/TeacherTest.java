import cn.bucm.campusprobe.ScheduleParser;
public class TeacherTest {
  static void equal(String expected,String actual){if(!expected.equals(actual))throw new AssertionError(expected+" != "+actual);}
  public static void main(String[] args){
    equal("合成教师",ScheduleParser.parse("合成课程\n合成教师\n1-8(周)[01-02节]\n示例楼101室",1,"").teacher);
    equal("合成教师、示例教师",ScheduleParser.parse("合成课程\n任课教师：合成教师、示例教师\n1-8周\n第1-2节",1,"").teacher);
    equal("",ScheduleParser.parse("合成课程\n1-8(周)[01-02节]\n示例楼101室",1,"").teacher);
    equal("",ScheduleParser.parse("合成课程\n备注：示例\n1-8(周)[01-02节]",1,"").teacher);
    equal("",ScheduleParser.parse("合成课程\n合成教师\n附加说明\n1-8(周)[01-02节]",1,"").teacher);
    System.out.println("Synthetic teacher extraction checks passed");
  }
}
