package cn.bucm.campus_schedule;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyPermanentlyInvalidatedException;
import android.security.keystore.KeyProperties;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.InvalidKeyException;
import java.security.Key;
import java.security.KeyStore;
import java.security.ProviderException;
import java.security.UnrecoverableKeyException;
import java.util.Arrays;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import org.json.JSONException;
import org.json.JSONObject;

/** A single opt-in credential pair, encrypted before it reaches disk. */
final class CampusCredentialStore {
    static final class Credentials {
        final String account;
        final String password;

        Credentials(String account, String password) {
            this.account = account;
            this.password = password;
        }

        @Override
        public String toString() {
            return "Credentials(redacted)";
        }
    }

    private static final String KEY_ALIAS = "campus_login_credentials_v1";
    private static final String KEY_STORE = "AndroidKeyStore";
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final String FILE_NAME = "campus-login-v1.enc";
    private static final byte VERSION = 1;
    private static final int GCM_TAG_BITS = 128;
    private static final int GCM_TAG_BYTES = 16;
    private static final int MAX_FILE_BYTES = 16 * 1024;
    private final AtomicFile file;

    CampusCredentialStore(Context context) {
        file = new AtomicFile(new File(context.getNoBackupFilesDir(), FILE_NAME));
    }

    private static boolean isValid(String account, String password) {
        return account != null && !account.trim().isEmpty() && account.length() <= 128
                && password != null && !password.isEmpty() && password.length() <= 1024;
    }

    synchronized void save(String account, String password) throws Exception {
        if (!isValid(account, password)) {
            throw new IllegalArgumentException("INVALID_CREDENTIALS");
        }
        String normalizedAccount = account.trim();
        Cipher cipher = initEncryptCipher();
        byte[] iv = cipher.getIV();
        if (iv == null || iv.length < 1 || iv.length > 32) {
            throw new GeneralSecurityException("INVALID_IV");
        }
        byte[] plain = new JSONObject()
                .put("account", normalizedAccount)
                .put("password", password)
                .toString()
                .getBytes(StandardCharsets.UTF_8);
        byte[] encrypted;
        try {
            encrypted = cipher.doFinal(plain);
        } finally {
            Arrays.fill(plain, (byte) 0);
        }
        FileOutputStream output = file.startWrite();
        try {
            output.write(VERSION);
            output.write(iv.length);
            output.write(iv);
            output.write(encrypted);
            file.finishWrite(output);
        } catch (Exception error) {
            file.failWrite(output);
            throw error;
        }
    }

    synchronized Credentials read() throws Exception {
        File base = file.getBaseFile();
        if (!base.isFile()) {
            return null;
        }
        long length = base.length();
        if (length <= 2 + GCM_TAG_BYTES || length > MAX_FILE_BYTES) {
            file.delete();
            return null;
        }
        byte[] data = file.readFully();
        if (data.length <= 2 + GCM_TAG_BYTES || data[0] != VERSION) {
            file.delete();
            return null;
        }
        int ivLength = data[1] & 0xFF;
        if (ivLength < 1 || ivLength > 32 || data.length <= 2 + ivLength + GCM_TAG_BYTES) {
            file.delete();
            return null;
        }
        KeyStore store = keyStore();
        if (!store.containsAlias(KEY_ALIAS)) {
            file.delete();
            return null;
        }
        Key key = store.getKey(KEY_ALIAS, null);
        if (!(key instanceof SecretKey)) {
            file.delete();
            deleteKeyQuietly();
            return null;
        }
        byte[] plain = null;
        try {
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_BITS, data, 2, ivLength));
            plain = cipher.doFinal(data, 2 + ivLength, data.length - 2 - ivLength);
            JSONObject json = new JSONObject(new String(plain, StandardCharsets.UTF_8));
            Object rawAccount = json.opt("account");
            Object rawPassword = json.opt("password");
            String account = rawAccount instanceof String ? (String) rawAccount : null;
            String password = rawPassword instanceof String ? (String) rawPassword : null;
            if (!isValid(account, password)) {
                file.delete();
                return null;
            }
            return new Credentials(account.trim(), password);
        } catch (GeneralSecurityException | ProviderException | JSONException | IllegalArgumentException error) {
            file.delete();
            if (error instanceof KeyPermanentlyInvalidatedException
                    || error instanceof InvalidKeyException
                    || error instanceof UnrecoverableKeyException
                    || error instanceof ProviderException) {
                deleteKeyQuietly();
            }
            return null;
        } finally {
            if (plain != null) {
                Arrays.fill(plain, (byte) 0);
            }
        }
    }

    synchronized boolean hasSaved() {
        try {
            File base = file.getBaseFile();
            if (!base.isFile()) {
                return false;
            }
            long length = base.length();
            if (length <= 2 + GCM_TAG_BYTES || length > MAX_FILE_BYTES) {
                return false;
            }
            return keyStore().containsAlias(KEY_ALIAS);
        } catch (Exception ignored) {
            return false;
        }
    }

    synchronized void clear() throws Exception {
        // Destroying the key also invalidates any stale ciphertext.
        Exception keyError = null;
        try {
            KeyStore store = keyStore();
            if (store.containsAlias(KEY_ALIAS)) {
                store.deleteEntry(KEY_ALIAS);
            }
        } catch (Exception error) {
            keyError = error;
        } finally {
            file.delete();
        }
        if (file.getBaseFile().exists()) {
            throw new IOException("CREDENTIAL_FILE_REMAINS");
        }
        if (keyError != null) {
            throw keyError;
        }
    }

    private Cipher initEncryptCipher() throws Exception {
        try {
            return createEncryptCipher(getOrCreateKey());
        } catch (GeneralSecurityException | ProviderException error) {
            deleteKeyQuietly();
            return createEncryptCipher(generateKey());
        }
    }

    private static Cipher createEncryptCipher(SecretKey key) throws Exception {
        Cipher cipher = Cipher.getInstance(TRANSFORMATION);
        cipher.init(Cipher.ENCRYPT_MODE, key);
        return cipher;
    }

    private SecretKey getOrCreateKey() throws Exception {
        KeyStore store = keyStore();
        if (store.containsAlias(KEY_ALIAS)) {
            Key existing = store.getKey(KEY_ALIAS, null);
            if (existing instanceof SecretKey) {
                return (SecretKey) existing;
            }
            deleteKeyQuietly();
        }
        return generateKey();
    }

    private static SecretKey generateKey() throws Exception {
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEY_STORE);
        generator.init(new KeyGenParameterSpec.Builder(
                KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build());
        return generator.generateKey();
    }

    private static void deleteKeyQuietly() {
        try {
            KeyStore store = keyStore();
            if (store.containsAlias(KEY_ALIAS)) {
                store.deleteEntry(KEY_ALIAS);
            }
        } catch (Exception ignored) {
        }
    }

    private static KeyStore keyStore() throws Exception {
        KeyStore store = KeyStore.getInstance(KEY_STORE);
        store.load(null);
        return store;
    }
}
