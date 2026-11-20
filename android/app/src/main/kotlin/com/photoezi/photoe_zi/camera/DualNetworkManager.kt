package com.photoezi.photoe_zi.camera

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper

/**
 * Dual Network Manager.
 *
 * Allows concurrent operation between:
 * 1. Camera Wi-Fi AP (Canon / Fujifilm hotspot without internet)
 * 2. Cellular network (LTE / 5G for background Google Drive uploads)
 */
class DualNetworkManager(
    private val context: Context,
    private val onNetworkStatusChanged: (Map<String, Any?>) -> Unit
) {
    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    private var cellularNetwork: Network? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isCellularRequested = false

    fun enableCellularRouting() {
        if (connectivityManager == null || isCellularRequested) return
        isCellularRequested = true

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                super.onAvailable(network)
                cellularNetwork = network
                notifyStatus()
            }

            override fun onLost(network: Network) {
                super.onLost(network)
                if (cellularNetwork == network) {
                    cellularNetwork = null
                    notifyStatus()
                }
            }
        }

        try {
            connectivityManager.requestNetwork(request, networkCallback!!)
        } catch (_: Exception) {}
        notifyStatus()
    }

    fun disableCellularRouting() {
        isCellularRequested = false
        networkCallback?.let {
            try {
                connectivityManager?.unregisterNetworkCallback(it)
            } catch (_: Exception) {}
        }
        networkCallback = null
        cellularNetwork = null
        notifyStatus()
    }

    fun getNetworkStatus(): Map<String, Any?> {
        val hasCellular = cellularNetwork != null
        val activeNetwork = connectivityManager?.activeNetwork
        val caps = activeNetwork?.let { connectivityManager?.getNetworkCapabilities(it) }
        val isWifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true

        return mapOf(
            "isWifiActive" to isWifi,
            "isCellularActive" to hasCellular,
            "isDualNetworkActive" to (isWifi && hasCellular),
            "statusDescription" to if (isWifi && hasCellular) {
                "Dual-Network Active: Camera Wi-Fi + Cellular Cloud Sync"
            } else if (isWifi) {
                "Camera Wi-Fi Active"
            } else if (hasCellular) {
                "Cellular Active"
            } else {
                "Standard Network"
            }
        )
    }

    private fun notifyStatus() {
        val status = getNetworkStatus()
        mainHandler.post {
            onNetworkStatusChanged(status)
        }
    }

    fun destroy() {
        disableCellularRouting()
    }
}
