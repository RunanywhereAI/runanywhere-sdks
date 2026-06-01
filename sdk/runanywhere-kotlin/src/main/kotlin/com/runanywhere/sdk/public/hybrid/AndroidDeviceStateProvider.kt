/*
  * Copyright 2026 RunAnywhere SDK
  * SPDX-License-Identifier: Apache-2.0
  *
  * Android impl of [DeviceStateProvider]. Backed by ConnectivityManager
  * (validated internet), BatteryManager (capacity percent), and
  * PowerManager (thermal status on API 29+, isPowerSaveMode fallback).
  *
  * Register once at app startup, after SDK init:
  *
  *     RACRouter.setDeviceStateProvider(
  *         AndroidDeviceStateProvider(applicationContext)
  *     )
  *
  * Requires the manifest permission `android.permission.ACCESS_NETWORK_STATE`.
  * Without it, [isOnline] gracefully degrades to `true` instead of throwing.
  */

package com.runanywhere.sdk.public.hybrid

import android.Manifest
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import androidx.annotation.RequiresPermission

class AndroidDeviceStateProvider(context: Context) : DeviceStateProvider {

    private val appContext: Context = context.applicationContext

    private val connectivity: ConnectivityManager? =
        appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    private val battery: BatteryManager? =
        appContext.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager

    private val power: PowerManager? =
        appContext.getSystemService(Context.POWER_SERVICE) as? PowerManager

    @RequiresPermission(Manifest.permission.ACCESS_NETWORK_STATE)
    override fun isOnline(): Boolean {
        val cm = connectivity ?: return true
        return try {
            val active = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(active) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } catch (_: SecurityException) {
            true
        }
    }

    override fun batteryPercent(): Int {
        val bm = battery ?: return 100
        val raw = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return when {
            raw < 0 -> 100
            raw > 100 -> 100
            else -> raw
        }
    }

    override fun isThermalThrottled(): Boolean {
        val pm = power ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return pm.currentThermalStatus >= PowerManager.THERMAL_STATUS_MODERATE
        }
        return pm.isPowerSaveMode
    }
}