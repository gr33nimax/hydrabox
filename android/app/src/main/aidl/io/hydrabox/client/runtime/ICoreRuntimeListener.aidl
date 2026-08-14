package io.hydrabox.client.runtime;

/** Carries serialized hydrabox.runtime.v1.RuntimeEvent messages. */
oneway interface ICoreRuntimeListener {
    void onEvent(in byte[] eventBytes);
}
