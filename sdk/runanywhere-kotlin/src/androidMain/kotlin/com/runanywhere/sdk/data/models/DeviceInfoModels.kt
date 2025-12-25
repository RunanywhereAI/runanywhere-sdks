package com.runanywhere.sdk.data.models

import android.os.Build

actual fun getPlatformAPILevel(): Int = Build.VERSION.SDK_INT

actual fun getPlatformOSVersion(): String = "Android ${Build.VERSION.RELEASE}"
