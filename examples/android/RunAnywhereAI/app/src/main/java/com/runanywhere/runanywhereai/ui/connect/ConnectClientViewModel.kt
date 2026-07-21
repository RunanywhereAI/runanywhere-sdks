package com.runanywhere.runanywhereai.ui.connect

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.connect.ConnectHost
import com.runanywhere.sdk.public.connect.ConnectSession
import kotlinx.coroutines.launch

/** App-scoped owner for the opt-in Android Connect client session. */
class ConnectClientViewModel(application: Application) : AndroidViewModel(application) {
    val session = ConnectSession(application)
    val state = session.state

    fun startDiscovery() {
        viewModelScope.launch { runCatching { session.startBrowsing() } }
    }

    fun connect(host: ConnectHost, onConnected: () -> Unit = {}) {
        viewModelScope.launch {
            if (runCatching { session.connect(host) }.isSuccess) onConnected()
        }
    }

    fun disconnect() {
        session.disconnect()
    }

    override fun onCleared() {
        session.stop()
        super.onCleared()
    }
}
