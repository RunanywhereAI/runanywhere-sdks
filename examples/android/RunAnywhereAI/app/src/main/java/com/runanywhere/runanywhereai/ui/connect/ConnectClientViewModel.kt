package com.runanywhere.runanywhereai.ui.connect

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.connect.ConnectHost
import com.runanywhere.sdk.public.connect.ConnectSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** App-scoped owner for the opt-in Android Connect client session. */
class ConnectClientViewModel(application: Application) : AndroidViewModel(application) {
    val session = ConnectSession(application)
    val state = session.state

    fun startDiscovery() {
        viewModelScope.launch {
            try {
                session.startBrowsing()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
            }
        }
    }

    fun connect(host: ConnectHost, onConnected: () -> Unit = {}) {
        viewModelScope.launch {
            try {
                session.connect(host)
                onConnected()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
            }
        }
    }

    fun disconnect() {
        session.disconnect()
    }

    fun cancelGeneration(requestId: String) {
        session.cancelGeneration(requestId)
    }

    override fun onCleared() {
        session.stop()
        super.onCleared()
    }
}
