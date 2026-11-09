# Applied only to cn.bucm.campus_schedule.releasetest, not the published APK.
# A separately compiled AndroidX runner calls shared Kotlin/tracing methods which
# the app itself doesn't use. Preserve that cross-APK runtime contract for tests.
# HSSF/parser optimization remains identical to the published release.
-keep class kotlin.** { *; }
-keep class androidx.tracing.** { *; }
