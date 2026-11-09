# Preserve the tiny parser boundary for release instrumentation and the native adapter.
-keep class cn.bucm.campusprobe.** { *; }
# POI creates BIFF records reflectively; constructors must survive optimization.
-keep class org.apache.poi.hssf.record.** { *; }
-keep class org.apache.poi.poifs.filesystem.** { *; }
# Log4j service discovery depends on implementation names and constructors.
-keep,allowoptimization class org.apache.logging.log4j.spi.** { *; }
-keep,allowoptimization class org.apache.logging.log4j.simple.** { *; }

# Compile-time annotations and optional OSGi discovery are not Android features.
-dontwarn aQute.bnd.annotation.baseline.BaselineIgnore
-dontwarn aQute.bnd.annotation.spi.ServiceConsumer
-dontwarn aQute.bnd.annotation.spi.ServiceProvider
-dontwarn edu.umd.cs.findbugs.annotations.Nullable
-dontwarn edu.umd.cs.findbugs.annotations.SuppressFBWarnings
-dontwarn org.osgi.framework.Bundle
-dontwarn org.osgi.framework.BundleContext
-dontwarn org.osgi.framework.FrameworkUtil
-dontwarn org.osgi.framework.ServiceReference
-dontwarn org.osgi.framework.wiring.BundleRevision
-dontwarn org.osgi.annotation.bundle.Export
-dontwarn org.osgi.annotation.versioning.Version
# Desktop drawing/formatting is not used: ExportWorkbook reads raw string/numeric cells.
# Keep this list explicit: missing classes on an actual import path still fail the build.
-dontwarn java.awt.Color
-dontwarn java.awt.Dimension
-dontwarn java.awt.Rectangle
-dontwarn java.awt.color.ColorSpace
-dontwarn java.awt.geom.AffineTransform
-dontwarn java.awt.geom.Dimension2D
-dontwarn java.awt.geom.Path2D
-dontwarn java.awt.geom.PathIterator
-dontwarn java.awt.geom.Point2D
-dontwarn java.awt.geom.Rectangle2D
-dontwarn java.awt.image.BufferedImage
-dontwarn java.awt.image.ColorModel
-dontwarn java.awt.image.ComponentColorModel
-dontwarn java.awt.image.DirectColorModel
-dontwarn java.awt.image.IndexColorModel
-dontwarn java.awt.image.PackedColorModel
