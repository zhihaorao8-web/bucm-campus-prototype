package cn.bucm.campus_schedule;

import android.content.ActivityNotFoundException;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.BitmapFactory;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Explicit user-initiated login helper actions: bounded QR export to gallery
 * and allowlisted external scan client launching. Never logs images or paths.
 */
final class CampusLoginActions {
    private static final int MIN_BYTES = 67;
    private static final int MAX_BYTES = 2 * 1024 * 1024;
    private static final int MIN_DIMENSION = 64;
    private static final int MAX_DIMENSION = 2048;
    private static final byte[] PNG_SIGNATURE = new byte[] {
        (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    };
    private static final Map<String, String> SCAN_CLIENTS = Map.of(
        "wework", "com.tencent.wework",
        "wechat", "com.tencent.mm"
    );

    private CampusLoginActions() {}

    static void validatePng(byte[] bytes) {
        if (bytes == null || bytes.length < MIN_BYTES || bytes.length > MAX_BYTES) {
            throw new IllegalArgumentException("INVALID_QR_IMAGE");
        }
        for (int i = 0; i < PNG_SIGNATURE.length; i++) {
            if (bytes[i] != PNG_SIGNATURE[i]) {
                throw new IllegalArgumentException("INVALID_QR_IMAGE");
            }
        }
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inJustDecodeBounds = true;
        BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
        if (!"image/png".equals(options.outMimeType)
                || options.outWidth < MIN_DIMENSION
                || options.outHeight < MIN_DIMENSION
                || options.outWidth > MAX_DIMENSION
                || options.outHeight > MAX_DIMENSION) {
            throw new IllegalArgumentException("INVALID_QR_IMAGE");
        }
    }

    static void savePng(Context context, byte[] bytes) throws IOException {
        validatePng(bytes);
        final String name = "bucm-campus-qr-" + System.currentTimeMillis() + ".png";
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, bytes, name);
        } else {
            saveLegacyExternal(context, bytes, name);
        }
    }

    private static void saveViaMediaStore(Context context, byte[] bytes, String name)
            throws IOException {
        ContentResolver resolver = context.getContentResolver();
        ContentValues values = new ContentValues();
        values.put(MediaStore.Images.Media.DISPLAY_NAME, name);
        values.put(MediaStore.Images.Media.MIME_TYPE, "image/png");
        values.put(
            MediaStore.Images.Media.RELATIVE_PATH,
            Environment.DIRECTORY_PICTURES + "/CampusSchedule"
        );
        values.put(MediaStore.Images.Media.IS_PENDING, 1);
        Uri uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
        if (uri == null) {
            throw new IOException("MEDIASTORE_INSERT_FAILED");
        }
        try {
            try (OutputStream out = resolver.openOutputStream(uri)) {
                if (out == null) {
                    throw new IOException("MEDIASTORE_STREAM_FAILED");
                }
                out.write(bytes);
                out.flush();
            }
            ContentValues done = new ContentValues();
            done.put(MediaStore.Images.Media.IS_PENDING, 0);
            if (resolver.update(uri, done, null, null) <= 0) {
                throw new IOException("MEDIASTORE_FINALIZE_FAILED");
            }
        } catch (IOException | RuntimeException error) {
            try {
                resolver.delete(uri, null, null);
            } catch (Exception ignored) {
            }
            if (error instanceof IOException ioError) {
                throw ioError;
            }
            throw new IOException("MEDIASTORE_WRITE_FAILED");
        }
    }

    @SuppressWarnings("deprecation")
    private static void saveLegacyExternal(Context context, byte[] bytes, String name)
            throws IOException {
        File pictures = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_PICTURES
        );
        File directory = new File(pictures, "CampusSchedule");
        if (!directory.exists() && !directory.mkdirs() && !directory.isDirectory()) {
            throw new IOException("PICTURE_DIR_FAILED");
        }
        File target = new File(directory, name);
        try (FileOutputStream out = new FileOutputStream(target)) {
            out.write(bytes);
            out.flush();
            out.getFD().sync();
        } catch (IOException | RuntimeException error) {
            target.delete();
            if (error instanceof IOException ioError) {
                throw ioError;
            }
            throw new IOException("LEGACY_WRITE_FAILED");
        }
        MediaScannerConnection.scanFile(
            context.getApplicationContext(),
            new String[] {target.getAbsolutePath()},
            new String[] {"image/png"},
            null
        );
    }

    static Map<String, Boolean> availableScanClients(PackageManager pm) {
        Map<String, Boolean> result = new LinkedHashMap<>();
        for (Map.Entry<String, String> entry : SCAN_CLIENTS.entrySet()) {
            result.put(entry.getKey(), pm.getLaunchIntentForPackage(entry.getValue()) != null);
        }
        return result;
    }

    static String launchScanClient(Context context, String client) {
        String packageName = client == null ? null : SCAN_CLIENTS.get(client);
        if (packageName == null) {
            throw new IllegalArgumentException("UNTRUSTED_CLIENT");
        }
        Intent intent = context.getPackageManager().getLaunchIntentForPackage(packageName);
        if (intent == null) {
            return "not_installed";
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(intent);
            return "launched";
        } catch (ActivityNotFoundException | SecurityException ignored) {
            return "failed";
        }
    }
}
