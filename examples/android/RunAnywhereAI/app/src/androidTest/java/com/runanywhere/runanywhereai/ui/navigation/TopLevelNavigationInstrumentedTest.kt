package com.runanywhere.runanywhereai.ui.navigation

import androidx.compose.runtime.SideEffect
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class TopLevelNavigationInstrumentedTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun ordinaryDrawerVisionDoesNotRestoreSavedLiveCameraArgument() {
        lateinit var navController: NavHostController
        val renderedLiveCamera = AtomicReference<Boolean?>()

        composeRule.setContent {
            navController = rememberNavController()
            NavHost(navController = navController, startDestination = Chat) {
                composable<Chat> {}
                composable<Vision> { entry ->
                    val openLiveCamera = entry.toRoute<Vision>().openLiveCamera
                    SideEffect { renderedLiveCamera.set(openLiveCamera) }
                }
            }
        }

        composeRule.runOnIdle {
            navController.navigateTopLevel(Vision(openLiveCamera = true), restoreState = false)
        }
        composeRule.waitUntil { renderedLiveCamera.get() == true }

        composeRule.runOnIdle { navController.navigateTopLevel(Chat) }
        composeRule.waitForIdle()

        // Control: explicitly restoring state proves the saved destination still carries
        // the previous live-camera argument.
        composeRule.runOnIdle {
            navController.navigateTopLevel(Vision(), restoreState = true)
        }
        composeRule.waitUntil { renderedLiveCamera.get() == true }

        composeRule.runOnIdle { navController.navigateTopLevel(Chat) }
        composeRule.waitForIdle()

        // This is the drawer path: Vision() uses the route policy's default restore setting.
        composeRule.runOnIdle { navController.navigateTopLevel(Vision()) }
        composeRule.waitUntil { renderedLiveCamera.get() == false }

        assertEquals(false, renderedLiveCamera.get())
    }
}
