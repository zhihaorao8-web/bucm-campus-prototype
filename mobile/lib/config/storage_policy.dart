/// Stable on-disk names and size limits. Names/schema/key semantics are upgrade
/// contracts: moving a value here is not a data migration.
abstract final class StoragePolicy {
  static const scheduleFile = 'schedule-v1.json';
  static const appearanceFile = 'appearance-v1.json';
  static const libraryFile = 'classroom-library-v1.json';
  static const progressFile = 'classroom-progress-v1.json';
  // Retired single-course association: delete on session clear, never read.
  static const obsoleteLinksFile = 'classroom-links-v1.json';
  static const scheduleBytes = 8 * 1024 * 1024;
  static const libraryBytes = 8 * 1024 * 1024;
  static const progressBytes = 2 * 1024 * 1024;
  static const appearanceBytes = 65536;
  static const progressEntries = 2000;
}
