package io.hydrabox.client.runtime;

/** Isolated candidate probe; request and response are protobuf messages. */
interface ICoreProbeService {
    byte[] runProbe(in byte[] requestBytes);
}
