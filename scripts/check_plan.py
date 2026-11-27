"""Pure check selection: no SDK, downloads, devices or subprocess execution."""
from dataclasses import dataclass, field
from pathlib import Path
import posixpath
import re

MODULES = ('docs', 'schedule', 'storage', 'classroom', 'player', 'ui', 'adapter', 'tooling')
FLUTTER_TESTS = {
    'adapter': ('schedule', 'classroom_policy', 'library_seat_navigation', 'library_seat_queries'),
    'schedule': ('schedule', 'schedule_difference', 'schedule_freshness', 'schedule_search',
                 'today_focus', 'week_grid', 'week_stack', 'weekday_tabs', 'course_colors'),
    'storage': ('atomic_file', 'schedule_recovery', 'classroom_library',
                'classroom_playback_progress', 'appearance'),
    'classroom': ('classroom_model', 'classroom_matching', 'classroom_name_merge',
                  'classroom_import_collection', 'classroom_import_progress', 'classroom_coordinator',
                  'classroom_api_reader', 'classroom_direct_import', 'classroom_page',
                  'classroom_connection', 'classroom_recovery_page', 'classroom_read_progress',
                  'classroom_access', 'classroom_policy', 'classroom_session_cache',
                  'classroom_timeline', 'recording_badge', 'test_diagnostics'),
    'player': ('classroom_preparation', 'classroom_player', 'classroom_player_route', 'classroom_controls',
               'classroom_fullscreen', 'classroom_seek_surface', 'classroom_slider_preview',
               'classroom_small_window', 'classroom_playback_progress'),
    'ui': ('ui', 'settings', 'appearance', 'quiet_design', 'liquid_glass', 'atmosphere', 'artistic_title',
           'app_icons', 'navigation_motion', 'schedule_motion', 'course_interaction',
           'classroom_ui_polish', 'quote_service', 'library_seat_queries'),
}
DIRECT_TESTS = ('test/classroom_api_reader_test.dart', 'test/classroom_direct_import_test.dart')
DEBUG_FLOWS = {
    'schedule-import': {
        'host': ('adapter',), 'tests': ('schedule', 'schedule_difference', 'schedule_freshness', 'schedule_recovery'),
        'direct': False,
    },
    'classroom-import': {
        'host': ('classroom',), 'tests': ('classroom_model', 'classroom_matching', 'classroom_name_merge',
            'classroom_import_collection', 'classroom_import_progress', 'classroom_api_reader',
            'classroom_direct_import', 'classroom_coordinator'), 'direct': True,
    },
    'auth-recovery': {
        'host': ('classroom',), 'tests': ('classroom_access', 'classroom_read_progress',
            'classroom_connection', 'classroom_recovery_page', 'classroom_coordinator', 'classroom_api_reader',
            'classroom_name_merge', 'classroom_preparation'),
        'direct': True,
    },
    'playback-resume': {
        'host': ('player',), 'tests': ('classroom_preparation', 'classroom_player_route',
            'classroom_playback_progress', 'classroom_controls'), 'direct': False,
    },
    'storage-recovery': {'host': ('storage',), 'tests': FLUTTER_TESTS['storage'], 'direct': False},
}
JAVA_TESTS = {
    'schedule': ('ParserTest', 'CourseTimeTest', 'TeacherTest'),
    'adapter': ('ParserTest', 'ExportTest', 'CourseTimeTest', 'TeacherTest'),
    'player': ('ClassroomMediaTest',),
}
JAVA_SOURCES = {
    'ParserTest': ('ScheduleParser',),
    'TeacherTest': ('ScheduleParser',),
    'CourseTimeTest': ('ScheduleParser', 'CourseTimes', 'CourseImportPlan', 'AcademicTerm'),
    'ExportTest': ('ScheduleParser', 'SchoolExport', 'ExportWorkbook', 'AcademicTerm'),
    'ClassroomMediaTest': ('ClassroomMediaTransport',),
}
NODE_TESTS = {
    'adapter': ('extract-test', 'school-viewport-test', 'export-nav-test', 'coverage-check-test', 'library-seat-read-test', 'library-seat-write-test'),
    'classroom': ('classroom-test', 'recording-api-test', 'recording-api-bridge-test', 'classroom-entry-test'),
    'player': ('classroom-player-test',),
}
# These changes also require explicit Android verification; host checks cannot satisfy it.
DEVICE_NOTES = {
    'adapter': 'L3: Android school method channel; parser/dependency/R8 changes also need isolated release XLS validation.',
    'player': 'L3: native playback/transport changes need isolated synthetic media validation.',
}


def flutter_files(modules):
    return sorted({f'test/{name}_test.dart' for module in modules
                   for name in FLUTTER_TESTS.get(module, ())})


def validate_inventory(root):
    """Fail loudly when new/removed suites have not been assigned to a module."""
    assigned = set(flutter_files(MODULES)) | {'test/preview_capture_test.dart'}
    actual = {p.relative_to(root / 'mobile').as_posix()
              for p in (root / 'mobile/test').rglob('*_test.dart')}
    if assigned != actual:
        raise ValueError(f'Update Flutter module registry: unassigned={sorted(actual-assigned)}, missing={sorted(assigned-actual)}')
    for suffix, expected, helper in (
        ('.cjs', {n + '.cjs' for v in NODE_TESTS.values() for n in v}, set()),
        ('.java', {n + '.java' for n in JAVA_SOURCES}, {'ReleaseFixture.java'}),
    ):
        actual = {p.name for p in (root / 'tests').glob('*' + suffix)}
        if actual != expected | helper:
            raise ValueError(f'Update host module registry for {suffix}: {sorted(actual ^ (expected | helper))}')


def dart_dependencies(root):
    """Follow local import/export/part URIs, including conditional alternatives."""
    graph = {}
    for folder in ('mobile/lib', 'mobile/test'):
        for path in (root / folder).rglob('*.dart'):
            name = path.relative_to(root).as_posix()
            dependencies = set()
            for directive in re.findall(r'^\s*(?:import|export|part)\s+([^;]+);',
                                        path.read_text(encoding='utf-8'), re.M):
                for uri in re.findall(r"['\"]([^'\"]+)['\"]", directive):
                    if uri.startswith('package:campus_schedule/'):
                        dependencies.add('mobile/lib/' + uri.split('/', 1)[1])
                    elif ':' not in uri:
                        dependencies.add(posixpath.normpath(posixpath.join(posixpath.dirname(name), uri)))
            graph[name] = dependencies
    return graph


def affected_tests(graph, changed):
    affected = set(changed)
    while True:
        extra = {name for name, deps in graph.items() if deps & affected}
        if extra <= affected:
            break
        affected |= extra
    return {p.removeprefix('mobile/') for p in affected
            if p.startswith('mobile/test/') and p.endswith('_test.dart')
            and not p.endswith('/preview_capture_test.dart') and p in graph}


@dataclass
class Plan:
    modules: list[str] = field(default_factory=list)
    java: list[str] = field(default_factory=list)
    node: list[str] = field(default_factory=list)
    flutter: list[str] = field(default_factory=list)
    direct: list[str] = field(default_factory=list)
    docs: bool = False
    icons: bool = False
    examples: bool = False
    tooling: bool = False
    analyze: bool = False
    reasons: list[str] = field(default_factory=list)
    required_manual: list[str] = field(default_factory=list)


def make_plan(root, modules=(), changed=None, legacy=False, direct=False, all_checks=False):
    validate_inventory(root)
    selected = set(modules)
    reasons, manual = [], set()
    impacted = set()
    if legacy:
        selected |= {'schedule', 'adapter', 'classroom', 'player'}
    if all_checks:
        selected.update(MODULES)
    if changed is not None:
        graph = dart_dependencies(root)
        impacted = affected_tests(graph, changed)
        for path in changed:
            if path.endswith('.md'):
                selected.add('docs')
            elif path.startswith(('mobile/lib/', 'mobile/test/')) and path.endswith('.dart'):
                if path in graph and (path in impacted or affected_tests(graph, {path})):
                    # Dart imports determine the tests; broad module presets are unnecessary here.
                    if path.startswith('mobile/lib/'):
                        reasons.append(f'Dart import dependents: {path}')
                    continue
                selected.update(MODULES)
                reasons.append(f'Unmapped/deleted Dart file: {path}; select all host checks')
            elif (path.startswith('src/cn/bucm/campusprobe/') and path.endswith('.java')
                  and Path(path).stem in {name for values in JAVA_SOURCES.values() for name in values}):
                module = 'player' if path.endswith('/ClassroomMediaTransport.java') else 'adapter'
                selected.add(module)
                manual.add(DEVICE_NOTES[module])
            elif path.startswith('assets/') and path.endswith(('.js', '.cjs')):
                module = ('player' if path.endswith('/classroom-player.js') else
                          'classroom' if Path(path).name in ('classroom.js', 'classroom-entry.js', 'recording-api-bridge.js', 'recording-api.cjs')
                          else 'adapter' if Path(path).name in ('extract.js', 'school-viewport.js', 'export-nav.js', 'coverage-check.js', 'library-seat-read.js', 'library-seat-write.js') else None)
                if module:
                    selected.add(module)
                else:
                    selected.update(MODULES)
                    reasons.append(f'Unknown JavaScript asset: {path}; select all host checks')
            else:
                selected.update(MODULES)
                reasons.append(f'Unknown/shared configuration: {path}; select all host checks')
                if path.startswith(('mobile/android/', 'mobile/integration_test/')) or path in ('dependencies.lock.json', 'AndroidManifest.xml', 'mobile/pubspec.yaml', 'mobile/pubspec.lock'):
                    manual.update(DEVICE_NOTES.values())
                    manual.add('L4: review normal-package APK/build/signing requirements; this runner never builds or installs APKs.')
        # Host adapters are outside the Dart import graph; include their consumers.
        if 'adapter' in selected:
            impacted |= affected_tests(graph, {'mobile/lib/platform/school_adapter.dart'})
        if 'classroom' in selected:
            impacted |= affected_tests(graph, {'mobile/lib/platform/classroom_api_reader.dart'})
        if 'player' in selected:
            impacted |= affected_tests(graph, {'mobile/lib/platform/classroom_player.dart'})
    flutter = set(flutter_files(selected)) | impacted
    if legacy:
        flutter.clear()
    plan = Plan(
        modules=sorted(selected),
        java=sorted({test for m in selected for test in JAVA_TESTS.get(m, ())}),
        node=sorted({test + '.cjs' for m in selected for test in NODE_TESTS.get(m, ())}),
        flutter=sorted(flutter),
        docs='docs' in selected,
        icons=legacy or bool(selected & {'ui', 'tooling'}),
        examples=legacy or bool(selected & {'schedule', 'adapter', 'tooling'}),
        tooling='tooling' in selected,
        analyze=not legacy and bool(flutter),
        reasons=reasons,
        required_manual=sorted(manual),
    )
    # Changed direct-related files always get the enabled configuration. Explicit
    # presets keep it opt-in, except --all, which includes both configurations.
    if not legacy and (direct or all_checks or (changed is not None and
            (set(DIRECT_TESTS) & flutter or 'classroom' in selected or 'adapter' in selected))):
        plan.direct = list(DIRECT_TESTS)
    return plan


def make_flow_plan(root, flow, direct=False):
    """Named synthetic debugging chains; same runner, no device/login actions."""
    spec = DEBUG_FLOWS[flow]
    plan = make_plan(root, modules=spec['host'], direct=direct or spec['direct'])
    plan.flutter = sorted({f'test/{name}_test.dart' for name in spec['tests']})
    if not set(plan.flutter) <= set(flutter_files(MODULES)):
        raise ValueError('Update debug flow: missing/unregistered test file.')
    plan.analyze = bool(plan.flutter or plan.direct)
    plan.reasons = [f'Synthetic debug flow: {flow}; explicit scope, not a replacement for changed/release checks.']
    return plan
