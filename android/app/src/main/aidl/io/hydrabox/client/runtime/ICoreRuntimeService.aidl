package io.hydrabox.client.runtime;

import io.hydrabox.client.runtime.ICoreRuntimeListener;

/** Versioned protobuf envelope over a same-UID binder boundary. */
interface ICoreRuntimeService {
    byte[] getContract();
    byte[] getSnapshot();
    byte[] submit(in byte[] commandBytes);
    byte[] executeUtility(in byte[] requestBytes);
    void registerListener(ICoreRuntimeListener listener);
    void unregisterListener(ICoreRuntimeListener listener);
    boolean isRuntimeDisconnected();
}
