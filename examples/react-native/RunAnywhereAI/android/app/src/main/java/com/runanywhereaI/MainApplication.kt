package com.runanywhereaI

import android.app.Application
import com.facebook.react.PackageList
import com.facebook.react.ReactApplication
import com.facebook.react.ReactHost
import com.facebook.react.ReactNativeApplicationEntryPoint.loadReactNative
import com.facebook.react.defaults.DefaultReactHost.getDefaultReactHost
import com.facebook.soloader.SoLoader
import com.facebook.react.soloader.OpenSourceMergedSoMapping
import com.margelo.nitro.NitroModulesPackage
import com.margelo.nitro.runanywhere.RunAnywhereCorePackage
import com.margelo.nitro.runanywhere.llama.RunAnywhereLlamaPackage
import com.margelo.nitro.runanywhere.onnx.RunAnywhereONNXPackage
import com.margelo.nitro.runanywhere.rag.RunAnywhereRAGPackage

class MainApplication : Application(), ReactApplication {
  override val reactHost: ReactHost by lazy {
    getDefaultReactHost(
      context = applicationContext,
      packageList =
        PackageList(this).packages.apply {
          add(NitroModulesPackage())
          add(RunAnywhereCorePackage())
          add(RunAnywhereLlamaPackage())
          add(RunAnywhereONNXPackage())
          add(RunAnywhereRAGPackage())
        },
    )
  }

  override fun onCreate() {
    super.onCreate()
    SoLoader.init(this, OpenSourceMergedSoMapping)
    loadReactNative(this)
  }
}
