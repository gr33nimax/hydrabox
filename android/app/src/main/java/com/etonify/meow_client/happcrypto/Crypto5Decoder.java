package com.etonify.meow_client.happcrypto;

import android.util.Base64;

import java.nio.charset.StandardCharsets;

import su.happ.proxyutility.util.ErrorCodeJNIWrapper;

final class Crypto5Decoder {
    private static final String PREFIX = "happ://crypt5/";

    private Crypto5Decoder() {}

    static String decode(String input) {
        String trimmed = input == null ? "" : input.trim();
        if (trimmed.isEmpty()) {
            throw new IllegalArgumentException("Введите ссылку happ://crypt5/...");
        }

        String payload = trimmed.startsWith(PREFIX) ? trimmed.substring(PREFIX.length()) : trimmed;
        if (payload.isEmpty()) {
            throw new IllegalArgumentException("Пустой payload crypt5.");
        }

        String stageF = reorderSix(payload);
        byte[] nativeBytes = new ErrorCodeJNIWrapper().decodeCrypto5Raw(stageF);
        String nativeUtf8 = new String(nativeBytes, StandardCharsets.UTF_8);
        String swapped = swapPairs(nativeUtf8);
        String decoded = looseBase64Decode(swapped);
        if (decoded.isEmpty()) {
            throw new IllegalStateException("Не удалось расшифровать crypt5.");
        }
        return decoded;
    }

    private static String reorderSix(String value) {
        StringBuilder sb = new StringBuilder(value.length());
        for (int i = 0; i < value.length(); i += 6) {
            int remaining = Math.min(6, value.length() - i);
            if (remaining == 6) {
                sb.append(value.charAt(i + 1));
                sb.append(value.charAt(i + 3));
                sb.append(value.charAt(i + 5));
                sb.append(value.charAt(i));
                sb.append(value.charAt(i + 2));
                sb.append(value.charAt(i + 4));
            } else {
                sb.append(value, i, i + remaining);
            }
        }
        return sb.toString();
    }

    private static String swapPairs(String value) {
        StringBuilder sb = new StringBuilder(value.length());
        for (int i = 0; i < value.length(); i += 2) {
            int remaining = Math.min(2, value.length() - i);
            if (remaining == 2) {
                sb.append(value.charAt(i + 1));
                sb.append(value.charAt(i));
            } else {
                sb.append(value, i, i + remaining);
            }
        }
        return sb.toString();
    }

    private static String looseBase64Decode(String value) {
        String decoded = tryBase64(value);
        if (decoded != null) {
            return decoded;
        }
        int end = value.length();
        while (end > 0 && value.charAt(end - 1) == '=') {
            end--;
            decoded = tryBase64(value.substring(0, end));
            if (decoded != null) {
                return decoded;
            }
        }
        return "";
    }

    private static String tryBase64(String value) {
        try {
            return new String(Base64.decode(value, Base64.NO_WRAP), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException ignored) {
        }
        try {
            return new String(
                Base64.decode(value, Base64.NO_WRAP | Base64.URL_SAFE),
                StandardCharsets.UTF_8
            );
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }
}
