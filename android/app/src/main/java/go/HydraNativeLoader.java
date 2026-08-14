package go;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Locale;

/**
 * Stable loading seam used by HydraCore's generated {@code go.Seq} binding.
 *
 * <p>The class intentionally has no Android dependencies. HydraBox configures
 * it before any generated gomobile class is initialized. A candidate is loaded
 * only when its canonical path is inside the configured no-backup root and its
 * bytes still match the signed manifest digest. Any verification/loading
 * failure is recorded and the embedded APK library is used instead.</p>
 */
public final class HydraNativeLoader {
    private static final Object LOCK = new Object();

    private static volatile Candidate candidate;
    private static volatile String loadedSource = "none";
    private static volatile boolean loaded;

    private HydraNativeLoader() {}

    public static void configure(
            String allowedRoot,
            String libraryPath,
            String expectedSha256,
            String failureMarkerPath) {
        if (loaded) {
            throw new IllegalStateException("HydraNativeLoader is already initialized");
        }
        candidate = Candidate.create(
                allowedRoot,
                libraryPath,
                expectedSha256,
                failureMarkerPath);
    }

    public static void clearCandidate() {
        if (loaded) {
            throw new IllegalStateException("HydraNativeLoader is already initialized");
        }
        candidate = null;
    }

    /** Called from the patched generated go.Seq static initializer. */
    public static void loadLibrary(String name) {
        if (loaded) {
            return;
        }
        synchronized (LOCK) {
            if (loaded) {
                return;
            }
            final Candidate selected = candidate;
            if (selected != null) {
                try {
                    loadVerified(selected);
                    loadedSource = "active";
                    loaded = true;
                    return;
                } catch (Throwable error) {
                    writeFailureMarker(selected.failureMarker, error);
                }
            }
            System.loadLibrary(name);
            loadedSource = "embedded";
            loaded = true;
        }
    }

    public static String loadedSource() {
        return loadedSource;
    }

    private static void loadVerified(Candidate selected) throws IOException {
        final File root = selected.allowedRoot.getCanonicalFile();
        final File library = selected.library.getCanonicalFile();
        final String rootPrefix = root.getPath() + File.separator;
        if (!library.getPath().startsWith(rootPrefix)) {
            throw new SecurityException("HydraCore candidate escapes the allowed root");
        }
        if (!library.isFile() || Files.isSymbolicLink(library.toPath())) {
            throw new SecurityException("HydraCore candidate is not a regular file");
        }
        final String actual = sha256(library);
        if (!constantTimeEquals(selected.expectedSha256, actual)) {
            throw new SecurityException("HydraCore candidate digest mismatch");
        }
        // Android 17 requires native files loaded by System.load() to be
        // read-only. Do this again immediately before loading, after hashing.
        if (!library.setReadable(true, false) || !library.setWritable(false, false)) {
            throw new SecurityException("HydraCore candidate cannot be made read-only");
        }
        if (library.canWrite()) {
            throw new SecurityException("HydraCore candidate remains writable");
        }
        System.load(library.getAbsolutePath());
    }

    private static String sha256(File file) throws IOException {
        final MessageDigest digest;
        try {
            digest = MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException impossible) {
            throw new AssertionError(impossible);
        }
        final byte[] buffer = new byte[1024 * 1024];
        try (FileInputStream input = new FileInputStream(file)) {
            while (true) {
                final int read = input.read(buffer);
                if (read < 0) {
                    break;
                }
                digest.update(buffer, 0, read);
            }
        }
        final StringBuilder result = new StringBuilder(64);
        for (byte value : digest.digest()) {
            result.append(String.format(Locale.ROOT, "%02x", value & 0xff));
        }
        return result.toString();
    }

    private static boolean constantTimeEquals(String expected, String actual) {
        final byte[] left = expected.getBytes(StandardCharsets.US_ASCII);
        final byte[] right = actual.getBytes(StandardCharsets.US_ASCII);
        return MessageDigest.isEqual(left, right);
    }

    private static void writeFailureMarker(File marker, Throwable error) {
        if (marker == null) {
            return;
        }
        try {
            final File parent = marker.getParentFile();
            if (parent != null && !parent.exists() && !parent.mkdirs()) {
                return;
            }
            final String safeType = error.getClass().getSimpleName();
            try (FileOutputStream output = new FileOutputStream(marker, false)) {
                output.write((safeType + "\n").getBytes(StandardCharsets.UTF_8));
                output.getFD().sync();
            }
        } catch (Throwable ignored) {
            // Loading fallback must not be blocked by diagnostics.
        }
    }

    private static final class Candidate {
        final File allowedRoot;
        final File library;
        final String expectedSha256;
        final File failureMarker;

        Candidate(File allowedRoot, File library, String expectedSha256, File failureMarker) {
            this.allowedRoot = allowedRoot;
            this.library = library;
            this.expectedSha256 = expectedSha256;
            this.failureMarker = failureMarker;
        }

        static Candidate create(
                String allowedRoot,
                String libraryPath,
                String expectedSha256,
                String failureMarkerPath) {
            if (allowedRoot == null || allowedRoot.trim().isEmpty()) {
                return null;
            }
            if (libraryPath == null || libraryPath.trim().isEmpty()) {
                return null;
            }
            final String digest = expectedSha256 == null
                    ? ""
                    : expectedSha256.trim().toLowerCase(Locale.ROOT);
            if (!digest.matches("^[0-9a-f]{64}$")) {
                return null;
            }
            final File marker = failureMarkerPath == null || failureMarkerPath.trim().isEmpty()
                    ? null
                    : new File(failureMarkerPath);
            return new Candidate(
                    new File(allowedRoot),
                    new File(libraryPath),
                    digest,
                    marker);
        }
    }
}
