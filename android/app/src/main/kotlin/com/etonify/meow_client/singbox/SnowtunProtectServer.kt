package com.etonify.meow_client.singbox

import android.net.LocalServerSocket
import android.net.LocalSocket
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.system.Os
import android.util.Log
import java.io.File
import java.io.FileDescriptor
import java.io.IOException
import java.util.concurrent.atomic.AtomicLong

class SnowtunProtectServer(
    private val service: VpnService,
    val socketPath: String,
) {
    companion object {
        const val DEFAULT_SOCKET_PATH = "@com.etonify.meow_client.snowtun.protect"
        private const val TAG = "SnowtunProtectServer"
        private const val START_RETRY_COUNT = 8
        private const val START_RETRY_DELAY_MS = 150L
        private const val STOP_JOIN_TIMEOUT_MS = 500L
        private const val LOG_EVERY_REQUESTS = 256L
    }

    private val socketName = socketPath.removePrefix("@")
    private val protectRequests = AtomicLong()

    @Volatile
    private var running = false
    private var serverSocket: LocalServerSocket? = null
    private var worker: Thread? = null

    @Synchronized
    fun start() {
        if (running) return
        serverSocket = bindServerSocketWithRetry()
        running = true
        worker = Thread({ acceptLoop() }, "SnowtunProtectServer").apply {
            isDaemon = true
            start()
        }
        MeowDiagnostics.log(TAG, "started socket=$socketPath")
    }

    @Synchronized
    fun stop() {
        val socket = serverSocket
        val thread = worker
        if (!running && socket == null && thread == null) return
        running = false
        serverSocket = null
        worker = null
        runCatching { socket?.close() }
        thread?.interrupt()
        if (thread != null && thread != Thread.currentThread()) {
            runCatching { thread.join(STOP_JOIN_TIMEOUT_MS) }.onFailure {
                MeowDiagnostics.log(TAG, "failed to join worker during stop", it)
            }
        }
        MeowDiagnostics.log(TAG, "stopped socket=$socketPath")
    }

    private fun bindServerSocketWithRetry(): LocalServerSocket {
        var lastError: IOException? = null
        repeat(START_RETRY_COUNT) { attempt ->
            try {
                return LocalServerSocket(socketName)
            } catch (error: IOException) {
                lastError = error
                val isAddressInUse = error.message?.contains("Address already in use", ignoreCase = true) == true
                if (!isAddressInUse || attempt == START_RETRY_COUNT - 1) {
                    throw error
                }
                MeowDiagnostics.log(
                    TAG,
                    "start retry=${attempt + 1}/$START_RETRY_COUNT socket=$socketPath",
                    error,
                )
                Thread.sleep(START_RETRY_DELAY_MS)
            }
        }
        throw lastError ?: IOException("failed to bind $socketPath")
    }

    private fun acceptLoop() {
        while (running) {
            val client = try {
                serverSocket?.accept() ?: break
            } catch (error: IOException) {
                if (running) {
                    Log.w(TAG, "accept failed", error)
                    MeowDiagnostics.log(TAG, "accept failed", error)
                }
                break
            }
            handleClient(client)
        }
    }

    private fun handleClient(client: LocalSocket) {
        client.use { socket ->
            val input = socket.inputStream
            val output = socket.outputStream
            val marker = input.read()
            if (marker < 0) {
                return
            }
            val descriptors = socket.ancillaryFileDescriptors ?: emptyArray()
            var success = descriptors.isNotEmpty()
            for (descriptor in descriptors) {
                try {
                    if (!protectDescriptor(descriptor)) {
                        success = false
                    }
                } finally {
                    closeDescriptor(descriptor)
                }
            }
            output.write(if (success) 1 else 0)
            output.flush()
            val count = protectRequests.incrementAndGet()
            if (!success || count % LOG_EVERY_REQUESTS == 0L) {
                MeowDiagnostics.log(
                    TAG,
                    "protect request count=$count descriptors=${descriptors.size} " +
                        "success=$success ${fdSnapshot()}",
                )
            }
        }
    }

    private fun protectDescriptor(descriptor: FileDescriptor): Boolean {
        return runCatching {
            ParcelFileDescriptor.dup(descriptor).use { pfd ->
                service.protect(pfd.fd)
            }
        }.getOrElse { error ->
            Log.w(TAG, "protect failed", error)
            MeowDiagnostics.log(TAG, "protect failed", error)
            false
        }
    }

    private fun closeDescriptor(descriptor: FileDescriptor) {
        runCatching { Os.close(descriptor) }.onFailure {
            MeowDiagnostics.log(TAG, "failed to close ancillary fd", it)
        }
    }

    private fun fdSnapshot(): String {
        val count = runCatching { File("/proc/self/fd").list()?.size }.getOrNull()
        return if (count == null) "fdCount=unknown" else "fdCount=$count"
    }
}
