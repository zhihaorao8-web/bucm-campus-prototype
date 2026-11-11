"""Run offline synthetic checks without an Android SDK or school account."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import EXE, java_tools
from scripts.dependencies import dependencies
import os


def main():
    work = ROOT / 'build' / 'checks'
    work.mkdir(parents=True, exist_ok=True)
    classes = Path(tempfile.mkdtemp(prefix='run-', dir=work)).resolve()
    if not classes.is_relative_to(work.resolve()):
        raise SystemExit('Check output escaped the build directory.')
    java = java_tools()
    deps=os.pathsep.join(str(p) for p in dependencies())
    subprocess.run([str(java / ('javac' + EXE)), '--release', '8', '-encoding', 'UTF-8',
                    '-classpath',deps,'-d', str(classes),
                    str(ROOT / 'src/cn/bucm/campusprobe/ScheduleParser.java'),
                    str(ROOT / 'src/cn/bucm/campusprobe/SchoolExport.java'),
                    str(ROOT / 'src/cn/bucm/campusprobe/ClassroomMediaTransport.java'),
                    str(ROOT / 'src/cn/bucm/campusprobe/ExportWorkbook.java'),
                    str(ROOT / 'src/cn/bucm/campusprobe/CourseTimes.java'),
                    str(ROOT / 'src/cn/bucm/campusprobe/CourseImportPlan.java'),
                    str(ROOT / 'src/cn/bucm/campusprobe/AcademicTerm.java'),
                    *map(str,(ROOT/'tests').glob('*.java'))], check=True)
    for test in ('ParserTest','ExportTest','CourseTimeTest','TeacherTest','ClassroomMediaTest'):
        subprocess.run([str(java / ('java' + EXE)), '-cp', str(classes)+os.pathsep+deps,test], check=True)
    node = shutil.which('node')
    if not node:
        raise SystemExit('Node.js is required for DOM extraction checks.')
    subprocess.run([node, str(ROOT / 'tests/extract-test.cjs')], check=True)
    subprocess.run([node, str(ROOT / 'tests/export-nav-test.cjs')], check=True)
    subprocess.run([node, str(ROOT / 'tests/coverage-check-test.cjs')], check=True)
    subprocess.run([node, str(ROOT / 'tests/classroom-test.cjs')], check=True)
    for path in (ROOT / 'examples').glob('*.json'):
        sample = json.loads(path.read_text(encoding='utf-8'))
        if sample.get('synthetic') is not True:
            raise SystemExit('Examples must be explicitly synthetic: ' + path.name)
    print('Offline checks passed; no school endpoints or real accounts were used.')


if __name__ == '__main__':
    main()
