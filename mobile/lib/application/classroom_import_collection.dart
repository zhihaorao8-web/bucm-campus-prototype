import '../config/classroom_limits.dart';
import '../data/classroom_library.dart';
import '../domain/classroom.dart';

/// In-memory collection only. The page still owns navigation and guarded save.
class ClassroomImportCollection {
  List<ClassroomCourse>? _matches;
  final _pages = <RecordingPage>[];
  final _sources = <ClassroomArchive>[];
  final _completed = <String, ClassroomArchive>{};
  int _index = 0;
  List<ClassroomCourse>? get matches => _matches;
  List<RecordingPage> get pages => List.unmodifiable(_pages);
  Map<String, ClassroomArchive> get completed => Map.unmodifiable(_completed);
  int get sourceIndex => _index;
  bool get complete => _matches != null && _index == _matches!.length;
  ClassroomCourse get nextSource => _matches![_index];

  void clearPages() => _pages.clear();
  void reset() {
    _pages.clear();
    _matches = null;
    _sources.clear();
    _index = 0;
  }

  void prepare(List<ClassroomCourse> matches) {
    if (_matches == null) {
      _matches = List.unmodifiable(matches);
      _index = 0;
      _sources.clear();
    } else if (matches.map((c) => c.id).join('\u0000') !=
        _matches!.map((c) => c.id).join('\u0000')) {
      throw const FormatException('同名课程目录已变化');
    }
    while (_index < _matches!.length && _completed.containsKey(nextSource.id)) {
      _sources.add(_completed[nextSource.id]!);
      _index++;
    }
  }

  /// Return a page to navigate to, or null when this source is complete.
  int? addPage(RecordingPage page, DateTime now) {
    if (page.page != _pages.length + 1) return _pages.length + 1;
    if (page.total > ClassroomLimits.records ||
        _pages.length >= ClassroomLimits.pages) {
      throw const FormatException();
    }
    _pages.add(page);
    if (page.hasNext) return page.page + 1;
    final saved = ClassroomArchive(List.unmodifiable(_pages), now);
    _completed[page.course.id] = saved;
    _sources.add(saved);
    _index++;
    _pages.clear();
    return null;
  }

  ClassroomArchive merge(DateTime now) {
    if (!complete) throw const FormatException('同名课程目录不完整');
    return ClassroomArchive.merge([..._sources], now);
  }
}
