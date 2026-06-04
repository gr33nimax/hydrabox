package su.happ.proxyutility.util;

import java.nio.charset.StandardCharsets;

public final class ErrorCodeJNIWrapper {
    static {
        System.loadLibrary("error-code");
    }

    private native byte[] jniGetErrorMessageFromString2(String errorString);

    public byte[] decodeCrypto5Raw(String errorString) {
        return jniGetErrorMessageFromString2(errorString);
    }

    public String decodeCrypto5Utf8(String errorString) {
        return new String(decodeCrypto5Raw(errorString), StandardCharsets.UTF_8);
    }
}
