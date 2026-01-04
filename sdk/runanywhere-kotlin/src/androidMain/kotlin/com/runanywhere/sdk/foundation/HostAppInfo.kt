package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.storage.AndroidPlatformContext

/**
 * Android implementation of getHostAppInfo
 */
actual fun getHostAppInfo(): HostAppInfo =
    try {
        val context = AndroidPlatformContext.getContext()
        val packageName = context.packageName
        val packageManager = context.packageManager
        val appInfo = context.applicationInfo
        val packageInfo = packageManager.getPackageInfo(packageName, 0)

        val appName = packageManager.getApplicationLabel(appInfo).toString()
        val versionName = packageInfo.versionName

        HostAppInfo(
            identifier = packageName,
            name = appName,
            version = versionName,
        )
    } catch (e: Exception) {
        // Return nulls if unable to get app info
        HostAppInfo(null, null, null)
    }
