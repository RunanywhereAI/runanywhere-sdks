package com.runanywhere.sdk.data.models

import android.os.Build
import java.util.UUID

actual fun getPlatformAPILevel(): Int = Build.VERSION.SDK_INT
