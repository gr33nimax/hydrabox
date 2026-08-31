package io.hydrabox.platform.android

import android.os.Binder
import android.os.IBinder
import android.os.Parcel
import io.hydrabox.core.contract.RuntimeCommand
import io.hydrabox.core.contract.RuntimeEvent
import io.hydrabox.core.contract.RuntimeSnapshot
import io.hydrabox.core.contract.RuntimeTransport
import io.hydrabox.core.contract.RuntimeWire

/** Binder endpoint: bytes cross the process boundary, contract values do not. */
class BinderRuntimeEndpoint(
    private val runtime: RuntimeTransport,
) : Binder() {
    private val listeners = mutableSetOf<IBinder>()

    init {
        runtime.subscribe { event -> publish(event) }
    }

    override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean = when (code) {
        SUBMIT -> {
            runtime.submit(RuntimeWire.decodeCommand(requireNotNull(data.createByteArray())))
            reply?.writeNoException()
            true
        }
        SNAPSHOT -> {
            reply?.writeNoException()
            reply?.writeByteArray(RuntimeWire.encode(runtime.snapshot()))
            true
        }
        REGISTER -> {
            listeners += requireNotNull(data.readStrongBinder())
            reply?.writeNoException()
            true
        }
        UNREGISTER -> {
            listeners -= requireNotNull(data.readStrongBinder())
            reply?.writeNoException()
            true
        }
        else -> super.onTransact(code, data, reply, flags)
    }

    private fun publish(event: RuntimeEvent) {
        val bytes = RuntimeWire.encode((event as? RuntimeEvent.Snapshot)?.snapshot ?: return)
        listeners.toList().forEach { listener ->
            val data = Parcel.obtain()
            try {
                data.writeByteArray(bytes)
                listener.transact(EVENT, data, null, IBinder.FLAG_ONEWAY)
            } finally {
                data.recycle()
            }
        }
    }

    companion object {
        const val SUBMIT = IBinder.FIRST_CALL_TRANSACTION
        const val SNAPSHOT = SUBMIT + 1
        const val REGISTER = SUBMIT + 2
        const val UNREGISTER = SUBMIT + 3
        const val EVENT = SUBMIT + 4
    }
}

class BinderRuntimeTransport(
    private val remote: IBinder,
) : RuntimeTransport {
    override fun submit(command: RuntimeCommand) = transact(BinderRuntimeEndpoint.SUBMIT) {
        writeByteArray(RuntimeWire.encode(command))
    }

    override fun snapshot(): RuntimeSnapshot {
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        return try {
            remote.transact(BinderRuntimeEndpoint.SNAPSHOT, data, reply, 0)
            reply.readException()
            RuntimeWire.decodeSnapshot(requireNotNull(reply.createByteArray()))
        } finally {
            data.recycle()
            reply.recycle()
        }
    }

    override fun subscribe(listener: (RuntimeEvent) -> Unit): AutoCloseable {
        val callback = object : Binder() {
            override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
                if (code != BinderRuntimeEndpoint.EVENT) return super.onTransact(code, data, reply, flags)
                listener(RuntimeEvent.Snapshot(snapshot().lastEventSequence, RuntimeWire.decodeSnapshot(requireNotNull(data.createByteArray()))))
                return true
            }
        }
        transact(BinderRuntimeEndpoint.REGISTER) { writeStrongBinder(callback) }
        return AutoCloseable { transact(BinderRuntimeEndpoint.UNREGISTER) { writeStrongBinder(callback) } }
    }

    private fun transact(code: Int, write: Parcel.() -> Unit) {
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        try {
            data.write()
            remote.transact(code, data, reply, 0)
            reply.readException()
        } finally {
            data.recycle()
            reply.recycle()
        }
    }
}
