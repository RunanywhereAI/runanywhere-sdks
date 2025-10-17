package com.runanywhere.sdk.data.models

import java.io.File

actual fun fileExists(path: String): Boolean = File(path).exists()
