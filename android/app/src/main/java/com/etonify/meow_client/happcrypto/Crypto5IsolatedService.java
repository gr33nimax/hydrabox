package com.etonify.meow_client.happcrypto;

import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.Parcelable;
import android.os.Process;
import android.os.ResultReceiver;
import android.util.Log;

public final class Crypto5IsolatedService extends Service {
    private static final String TAG_FINAL = "HAPP_CRYPT5_FINAL";
    private static final String TAG_ERROR = "HAPP_CRYPT5_ERROR";
    static final String EXTRA_INPUT = "input";
    static final String EXTRA_RECEIVER = "receiver";
    static final String EXTRA_DECODED = "decoded";
    static final String EXTRA_ERROR = "error";
    static final int RESULT_SUCCESS = 1;
    static final int RESULT_ERROR = 2;

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        final String input = intent == null ? null : intent.getStringExtra(EXTRA_INPUT);
        final ResultReceiver receiver = getParcelable(intent, EXTRA_RECEIVER, ResultReceiver.class);

        Thread worker = new Thread(() -> {
            Bundle bundle = new Bundle();
            try {
                String decoded = Crypto5Decoder.decode(input);
                Log.i(TAG_FINAL, decoded);
                bundle.putString(EXTRA_DECODED, decoded);
                if (receiver != null) {
                    receiver.send(RESULT_SUCCESS, bundle);
                }
            } catch (Throwable error) {
                String message = error.getMessage() == null ? error.toString() : error.getMessage();
                Log.e(TAG_ERROR, message, error);
                bundle.putString(EXTRA_ERROR, message);
                if (receiver != null) {
                    receiver.send(RESULT_ERROR, bundle);
                }
            } finally {
                stopSelfResult(startId);
                Process.killProcess(Process.myPid());
            }
        }, "crypto5-isolated-worker");
        worker.start();
        return START_NOT_STICKY;
    }

    @SuppressWarnings("deprecation")
    private static <T extends Parcelable> T getParcelable(Intent intent, String key, Class<T> clazz) {
        if (intent == null) {
            return null;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return intent.getParcelableExtra(key, clazz);
        }
        return (T) intent.getParcelableExtra(key);
    }
}
