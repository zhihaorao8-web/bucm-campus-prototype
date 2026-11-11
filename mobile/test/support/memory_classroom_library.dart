import 'package:campus_schedule/data/classroom_library.dart';
import 'package:campus_schedule/domain/schedule.dart';

class MemoryClassroomLibrary extends ClassroomLibrary {
  MemoryClassroomLibrary([this.archive]);
  final ClassroomArchive? archive;
  @override
  Future<ClassroomArchive?> lookup(Course course) async => archive;
}
