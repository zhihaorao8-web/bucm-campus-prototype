package cn.bucm.campusprobe;

import java.io.*;
import java.util.*;
import java.math.BigDecimal;
import org.apache.poi.hssf.usermodel.HSSFWorkbook;
import org.apache.poi.ss.usermodel.*;
import org.apache.poi.ss.util.CellRangeAddress;

/** Reads downloaded XLS in memory. No formulas, external links, macros or network execution. */
public final class ExportWorkbook {
    public static final class Result {
        public final List<ScheduleParser.Candidate> candidates=new ArrayList<>();
        public int sheets,sourceCells;
        public boolean hasUnscheduledSection;
        public String semesterId="";
    }
    private static String value(Cell cell) throws IOException {
        if(cell==null)return "";
        String text;
        switch(cell.getCellType()) {
            case STRING:text=cell.getStringCellValue();break;
            case NUMERIC:text=BigDecimal.valueOf(cell.getNumericCellValue()).stripTrailingZeros().toPlainString();break;
            case BLANK:return "";
            default:throw new IOException("UNSUPPORTED_CELL_TYPE");
        }
        if(text.length()>6000)throw new IOException("CELL_TOO_LONG");return text.trim();
    }
    private static String at(Sheet sheet,int r,int c) throws IOException {Row row=sheet.getRow(r);return row==null?"":value(row.getCell(c));}
    private static int headerDay(String s) {return s.matches("^(?:星期|周|礼拜)[一二三四五六日天](?:\\s.*|[（(].*|[0-9].*)?$")?ScheduleParser.weekday(s):0;}
    public static Result read(byte[] data) throws IOException {
        if(data.length>SchoolExport.MAX_BYTES||!SchoolExport.format(data).equals("XLS二进制"))throw new IOException("NOT_XLS");
        Result result=new Result();
        try(HSSFWorkbook book=new HSSFWorkbook(new ByteArrayInputStream(data))) {
            if(book.getNumberOfSheets()>8)throw new IOException("TOO_MANY_SHEETS");
            result.sheets=book.getNumberOfSheets();
            for(Sheet sheet:book) {
                if(sheet.getLastRowNum()>=2000)throw new IOException("TOO_MANY_ROWS");
                for(Row row:sheet)if(row.getLastCellNum()>100)throw new IOException("TOO_MANY_COLUMNS");
                int header=-1;Map<Integer,Integer> days=new LinkedHashMap<>();
                StringBuilder metadata=new StringBuilder();
                for(int r=0;r<=sheet.getLastRowNum();r++) {
                    Map<Integer,Integer> found=new LinkedHashMap<>();
                    Row row=sheet.getRow(r);if(row==null)continue;
                    for(Cell cell:row){String text=value(cell);int day=headerDay(text);if(day>0)found.put(cell.getColumnIndex(),day);if(r<30)metadata.append(text).append('\n');}
                    if(found.size()>=5){if(header!=-1)throw new IOException("MULTIPLE_GRID_HEADERS");header=r;days=found;}
                }
                String semester=AcademicTerm.find(metadata.toString());
                if(!semester.isEmpty()){if(!result.semesterId.isEmpty()&&!result.semesterId.equals(semester))throw new IOException("MULTIPLE_SEMESTERS");result.semesterId=semester;}
                if(header>=0) {
                    for(Row row:sheet) {
                        if(row.getRowNum()<=header)continue;
                        boolean footer=false;
                        for(Cell cell:row)if(value(cell).matches("^(?:无课表课程|未排课课程)(?:信息)?[：:]?.*$"))footer=true;
                        if(footer){result.hasUnscheduledSection=true;break;}
                        for(Cell cell:row) {
                            Integer day=days.get(cell.getColumnIndex());if(day==null)continue;
                            boolean skip=false;
                            for(CellRangeAddress range:sheet.getMergedRegions())if(range.isInRange(cell.getRowIndex(),cell.getColumnIndex())) {
                                if(range.getFirstRow()!=cell.getRowIndex()||range.getFirstColumn()!=cell.getColumnIndex()||range.getLastColumn()!=range.getFirstColumn())skip=true;
                            }
                            String raw=value(cell);if(skip||raw.isEmpty()||raw.matches("^(?:无|暂无|[-—\\s]+)$"))continue;
                            result.sourceCells++;result.candidates.addAll(ScheduleParser.parseAll(raw,day,at(sheet,row.getRowNum(),0)));
                        }
                    }
                } else readRecords(sheet,result);
            }
        }
        if(result.candidates.isEmpty())throw new IOException("NO_COURSE_TABLE");
        return result;
    }
    private static void readRecords(Sheet sheet,Result result) throws IOException {
        for(Row row:sheet) {
            Map<String,Integer> columns=new HashMap<>();
            for(Cell cell:row)columns.put(value(cell).replaceAll("\\s+",""),cell.getColumnIndex());
            int name=find(columns,"课程名称","课程名"),day=find(columns,"星期","星期几"),weeks=find(columns,"周次","上课周次"),periods=find(columns,"节次","上课节次");
            if(name<0||day<0||weeks<0||periods<0)continue;
            int place=find(columns,"地点","上课地点","教室");
            for(int r=row.getRowNum()+1;r<=sheet.getLastRowNum();r++) {
                String title=at(sheet,r,name);if(title.isEmpty())continue;
                String dow=at(sheet,r,day);int weekday=ScheduleParser.weekday(dow);
                if(weekday==0&&dow.matches("[1-7]"))weekday=Integer.parseInt(dow);
                if(weekday==0)throw new IOException("INVALID_WEEKDAY");
                String w=at(sheet,r,weeks),p=at(sheet,r,periods),location=place<0?"":at(sheet,r,place);
                ScheduleParser.Candidate c=ScheduleParser.parse(title+"\n周次："+w+"\n第"+p+"节"+(location.isEmpty()?"":"\n地点："+location),weekday,"");
                result.sourceCells++;result.candidates.add(c);
            }
            return;
        }
    }
    private static int find(Map<String,Integer> columns,String... names){for(String name:names)if(columns.containsKey(name))return columns.get(name);return -1;}
}
