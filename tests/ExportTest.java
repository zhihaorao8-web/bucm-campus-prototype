import cn.bucm.campusprobe.*;
import java.io.*;
import org.apache.poi.hssf.usermodel.HSSFWorkbook;
import org.apache.poi.ss.usermodel.*;
import org.apache.poi.ss.util.CellRangeAddress;
public class ExportTest {
 static void check(boolean b){if(!b)throw new AssertionError();}
 static byte[] bytes(HSSFWorkbook b)throws Exception{ByteArrayOutputStream out=new ByteArrayOutputStream();b.write(out);b.close();return out.toByteArray();}
 static void reject(byte[] b)throws Exception{try{ExportWorkbook.read(b);throw new AssertionError();}catch(IOException expected){}}
 public static void main(String[] args)throws Exception{
  HSSFWorkbook book=new HSSFWorkbook();Sheet sheet=book.createSheet("合成课表");Row header=sheet.createRow(0);header.createCell(0).setCellValue("节次");String[] days={"一","二","三","四","五","六","日"};for(int i=0;i<7;i++)header.createCell(i+1).setCellValue("星期"+days[i]);
  header.createCell(8).setCellValue("合成学校2026-2027-1学期课表");Row row=sheet.createRow(1);row.createCell(0).setCellValue("上午");row.createCell(1).setCellValue("合成课程甲\n示例教师\n9-17([周])[01-02-03节]\n示东901教\n---------------------\n合成课程甲\n示例教师\n1-8([周])[01-02节]\n示例楼（东区）");
  sheet.addMergedRegion(new CellRangeAddress(1,2,1,1));sheet.createRow(2).createCell(1).setCellValue("不得重复读取合并区域内值");sheet.createRow(3).createCell(0).setCellValue("无课表课程");sheet.createRow(4).createCell(1).setCellValue("合成未排课课程");
  ExportWorkbook.Result result=ExportWorkbook.read(bytes(book));check(result.semesterId.equals("2026-2027-1"));check(result.sourceCells==1);check(result.candidates.size()==2);check(result.hasUnscheduledSection);check(result.candidates.get(0).weeks.equals("9-17"));check(result.candidates.get(0).place.equals("示东901教"));check(result.candidates.get(1).place.equals("示例楼（东区）"));check(result.candidates.get(0).time.isEmpty());
  book=new HSSFWorkbook();sheet=book.createSheet("合成明细");header=sheet.createRow(0);String[] labels={"课程名称","星期","周次","节次","上课地点"};for(int i=0;i<labels.length;i++)header.createCell(i).setCellValue(labels[i]);row=sheet.createRow(1);row.createCell(0).setCellValue("合成课程乙");row.createCell(1).setCellValue(6);row.createCell(2).setCellValue("1-9");row.createCell(3).setCellValue("09-10-11");result=ExportWorkbook.read(bytes(book));check(result.candidates.size()==1);check(result.candidates.get(0).day==6);check(result.candidates.get(0).place.isEmpty());
  reject(new byte[0]);reject("<html>login</html>".getBytes("UTF-8"));book=new HSSFWorkbook();sheet=book.createSheet("合成超限");sheet.createRow(2000).createCell(0).setCellValue("超限");reject(bytes(book));book=new HSSFWorkbook();sheet=book.createSheet("合成公式");sheet.createRow(0).createCell(0).setCellFormula("1+1");reject(bytes(book));
  check(SchoolExport.allowed("https://webvpn.bucm.edu.cn/export"));for(String url:new String[]{"http://bucm.edu.cn/export","https://bucm.edu.cn.evil.test/export","https://user@bucm.edu.cn/export","https://bucm.edu.cn:8443/export"})check(!SchoolExport.allowed(url));
  System.out.println("XLS checks passed (synthetic binary grid, merged cells, footer, records, missing locations, limits, formulas rejected, HTTPS domain checks)");
 }
}
