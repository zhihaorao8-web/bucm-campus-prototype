# AndroidX test runner's compile-time-only Error Prone annotations.
# This file applies to the test APK, never the app's R8 configuration.
# The runner uses reflection and shares selected support classes with the target.
# Keep the test harness stable while the target app remains fully R8-optimized.
-dontshrink
-dontoptimize
-dontobfuscate
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.MustBeClosed
