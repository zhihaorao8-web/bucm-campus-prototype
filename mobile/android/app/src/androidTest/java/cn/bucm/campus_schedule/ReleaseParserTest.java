package cn.bucm.campus_schedule;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
import java.io.*;
import java.time.LocalDate;
import cn.bucm.campusprobe.*;

/** Exercises the R8-optimized app parser, never a school session or a network request. */
@RunWith(AndroidJUnit4.class)
public class ReleaseParserTest {
    @Test public void optimizedBinaryXlsKeepsTeacherWeeksAndSegments() throws Exception {
        assertEquals("cn.bucm.campus_schedule.releasetest", InstrumentationRegistry.getInstrumentation().getTargetContext().getPackageName());
        byte[] fixture;
        try(InputStream in=InstrumentationRegistry.getInstrumentation().getContext().getAssets().open("synthetic-timetable.xls");
            ByteArrayOutputStream out=new ByteArrayOutputStream()) {
            byte[] block=new byte[4096];int count;
            while((count=in.read(block))!=-1)out.write(block,0,count);
            fixture=out.toByteArray();
        }
        ExportWorkbook.Result result=ExportWorkbook.read(fixture);
        assertEquals("2026-2027-1",result.semesterId);
        assertEquals(1,result.sourceCells);assertEquals(1,result.candidates.size());
        assertTrue(result.hasUnscheduledSection);
        ScheduleParser.Candidate course=result.candidates.get(0);
        assertEquals("示例教师",course.teacher);assertEquals("1-16",course.weeks);
        assertEquals("示例楼101室",course.place);
        CourseImportPlan plan=CourseImportPlan.create(result.candidates,LocalDate.of(2026,9,7));
        assertEquals(2,plan.entries.get(0).timing.segments.size());
        assertEquals("08:30",plan.entries.get(0).timing.start());
        assertEquals("11:15",plan.entries.get(0).timing.end());
    }
}
