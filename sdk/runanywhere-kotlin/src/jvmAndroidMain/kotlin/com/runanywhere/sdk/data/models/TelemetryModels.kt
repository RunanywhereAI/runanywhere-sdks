package com.runanywhere.sdk.data.models

import java.util.UUID

actual fun generateUUID(): String = UUID.randomUUID().toString()
