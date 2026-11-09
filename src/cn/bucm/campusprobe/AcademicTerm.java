package cn.bucm.campusprobe;
import java.util.*;
import java.util.regex.*;
import java.time.*;
/** Semester identity comes from school content; the anchor date is user supplied. */
public final class AcademicTerm {
 public static String find(String text){
  Set<String> found=new LinkedHashSet<>();
  Matcher m=Pattern.compile("(?<![0-9])(20[0-9]{2})\\s*[-－—–]\\s*(20[0-9]{2})\\s*[-－—–]\\s*([12])(?![0-9])").matcher(text);
  while(m.find())add(found,m.group(1),m.group(2),m.group(3));
  m=Pattern.compile("(20[0-9]{2})\\s*[-－—–]\\s*(20[0-9]{2})\\s*学年(?:度)?\\s*第?\\s*([12一二])\\s*学期").matcher(text);
  while(m.find())add(found,m.group(1),m.group(2),m.group(3).replace("一","1").replace("二","2"));
  if(found.size()>1)throw new IllegalArgumentException("导出文件含多个学期，无法自动确定");
  return found.isEmpty()?"":found.iterator().next();
 }
 private static void add(Set<String> values,String a,String b,String semester){if(Integer.parseInt(b)!=Integer.parseInt(a)+1)throw new IllegalArgumentException("学校学年标识无效");values.add(a+"-"+b+"-"+semester);}
 public static LocalDate knownStart(String semester){return "2026-2027-1".equals(semester)?LocalDate.of(2026,9,7):null;}
}
