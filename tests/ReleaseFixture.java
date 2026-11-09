import java.io.*;
import org.apache.poi.hssf.usermodel.HSSFWorkbook;
import org.apache.poi.ss.usermodel.*;

/** Generates an entirely synthetic binary workbook for optimized Android tests. */
public class ReleaseFixture {
    public static void main(String[] args) throws Exception {
        try(HSSFWorkbook book=new HSSFWorkbook()) {
            Sheet sheet=book.createSheet("SYNTHETIC_ONLY");
            Row header=sheet.createRow(0);
            String[] days={"一","二","三","四","五","六","日"};
            header.createCell(0).setCellValue("节次");
            for(int n=0;n<7;n++)header.createCell(n+1).setCellValue("星期"+days[n]);
            header.createCell(8).setCellValue("合成学校2026-2027-1学期课表");
            Row row=sheet.createRow(1);row.createCell(0).setCellValue("合成上午");
            row.createCell(1).setCellValue("合成课程甲\n示例教师\n1-16(周)[01-02-03节]\n示例楼101室");
            sheet.createRow(2).createCell(0).setCellValue("无课表课程");
            try(OutputStream out=new FileOutputStream(args[0])){book.write(out);}
        }
        System.out.println("Generated SYNTHETIC_ONLY release fixture");
    }
}
