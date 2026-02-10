package com.runanywhere.agent.toolcalling

import com.runanywhere.agent.kernel.ActionExecutor
import com.runanywhere.agent.kernel.Decision

object UIActionTools {

    fun registerAll(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registerTap(registry, ctx, executor)
        registerType(registry, ctx, executor)
        registerEnter(registry, ctx, executor)
        registerSwipe(registry, ctx, executor)
        registerBack(registry, ctx, executor)
        registerHome(registry, ctx, executor)
        registerOpenApp(registry, ctx, executor)
        registerLongPress(registry, ctx, executor)
        registerOpenUrl(registry, ctx, executor)
        registerWebSearch(registry, ctx, executor)
        registerOpenNotifications(registry, ctx, executor)
        registerOpenQuickSettings(registry, ctx, executor)
        registerWait(registry, ctx, executor)
        registerDone(registry, ctx, executor)
    }

    private fun registerTap(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_tap",
                description = "Tap a UI element by its index number from the screen elements list",
                parameters = listOf(
                    ToolParameter(
                        name = "index",
                        type = ToolParameterType.INTEGER,
                        description = "The index number of the element to tap",
                        required = true
                    )
                )
            )
        ) { args ->
            val index = (args["index"] as? Number)?.toInt()
                ?: return@register "Error: index parameter required"
            val decision = Decision("tap", elementIndex = index)
            val result = executor.execute(decision, ctx.indexToCoords)
            result.message
        }
    }

    private fun registerType(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_type",
                description = "Type text into the currently focused or editable text field",
                parameters = listOf(
                    ToolParameter(
                        name = "text",
                        type = ToolParameterType.STRING,
                        description = "The text to type",
                        required = true
                    )
                )
            )
        ) { args ->
            val text = args["text"]?.toString()
                ?: return@register "Error: text parameter required"
            val decision = Decision("type", text = text)
            val result = executor.execute(decision, ctx.indexToCoords)
            result.message
        }
    }

    private fun registerEnter(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_enter",
                description = "Press Enter/Submit to confirm input, submit a search query, or press a submit button",
                parameters = emptyList()
            )
        ) { _ ->
            val result = executor.execute(Decision("enter"), ctx.indexToCoords)
            result.message
        }
    }

    private fun registerSwipe(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_swipe",
                description = "Swipe/scroll the screen in a direction to reveal more content",
                parameters = listOf(
                    ToolParameter(
                        name = "direction",
                        type = ToolParameterType.STRING,
                        description = "Direction to swipe: up, down, left, or right",
                        required = true,
                        enumValues = listOf("up", "down", "left", "right")
                    )
                )
            )
        ) { args ->
            val dir = args["direction"]?.toString() ?: "up"
            val mapped = when (dir) {
                "up" -> "u"
                "down" -> "d"
                "left" -> "l"
                "right" -> "r"
                else -> dir
            }
            val decision = Decision("swipe", direction = mapped)
            val result = executor.execute(decision, ctx.indexToCoords)
            result.message
        }
    }

    private fun registerBack(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_back",
                description = "Press the Back button to go to the previous screen",
                parameters = emptyList()
            )
        ) { _ ->
            val result = executor.execute(Decision("back"), ctx.indexToCoords)
            result.message
        }
    }

    private fun registerHome(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_home",
                description = "Press the Home button to go to the home screen",
                parameters = emptyList()
            )
        ) { _ ->
            val result = executor.execute(Decision("home"), ctx.indexToCoords)
            result.message
        }
    }

    private fun registerOpenApp(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_open_app",
                description = "Open an app by name. Always use this instead of searching for app icons. Examples: YouTube, Chrome, WhatsApp, Settings, Clock, Maps, Spotify, Camera, Gmail",
                parameters = listOf(
                    ToolParameter(
                        name = "app_name",
                        type = ToolParameterType.STRING,
                        description = "The name of the app to open",
                        required = true
                    )
                )
            )
        ) { args ->
            val appName = args["app_name"]?.toString()
                ?: return@register "Error: app_name parameter required"
            val decision = Decision("open", text = appName)
            val result = executor.execute(decision, ctx.indexToCoords)
            result.message
        }
    }

    private fun registerLongPress(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_long_press",
                description = "Long press a UI element by its index number",
                parameters = listOf(
                    ToolParameter(
                        name = "index",
                        type = ToolParameterType.INTEGER,
                        description = "The index number of the element to long press",
                        required = true
                    )
                )
            )
        ) { args ->
            val index = (args["index"] as? Number)?.toInt()
                ?: return@register "Error: index parameter required"
            val decision = Decision("long", elementIndex = index)
            val result = executor.execute(decision, ctx.indexToCoords)
            result.message
        }
    }

    private fun registerOpenUrl(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_open_url",
                description = "Open a URL in the default browser",
                parameters = listOf(
                    ToolParameter(
                        name = "url",
                        type = ToolParameterType.STRING,
                        description = "The URL to open",
                        required = true
                    )
                )
            )
        ) { args ->
            val url = args["url"]?.toString()
                ?: return@register "Error: url parameter required"
            val decision = Decision("url", url = url)
            val result = executor.execute(decision, ctx.indexToCoords)
            result.message
        }
    }

    private fun registerWebSearch(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_web_search",
                description = "Perform a web search using Google",
                parameters = listOf(
                    ToolParameter(
                        name = "query",
                        type = ToolParameterType.STRING,
                        description = "The search query",
                        required = true
                    )
                )
            )
        ) { args ->
            val query = args["query"]?.toString()
                ?: return@register "Error: query parameter required"
            val decision = Decision("search", query = query)
            val result = executor.execute(decision, ctx.indexToCoords)
            result.message
        }
    }

    private fun registerOpenNotifications(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_open_notifications",
                description = "Open the notification shade",
                parameters = emptyList()
            )
        ) { _ ->
            val result = executor.execute(Decision("notif"), ctx.indexToCoords)
            result.message
        }
    }

    private fun registerOpenQuickSettings(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_open_quick_settings",
                description = "Open the quick settings panel",
                parameters = emptyList()
            )
        ) { _ ->
            val result = executor.execute(Decision("quick"), ctx.indexToCoords)
            result.message
        }
    }

    private fun registerWait(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_wait",
                description = "Wait for the screen to finish loading or for an animation to complete",
                parameters = emptyList()
            )
        ) { _ ->
            val result = executor.execute(Decision("wait"), ctx.indexToCoords)
            result.message
        }
    }

    private fun registerDone(registry: ToolRegistry, ctx: UIActionContext, executor: ActionExecutor) {
        registry.register(
            ToolDefinition(
                name = "ui_done",
                description = "Signal that the task/goal has been completed successfully",
                parameters = listOf(
                    ToolParameter(
                        name = "reason",
                        type = ToolParameterType.STRING,
                        description = "Brief explanation of why the task is complete",
                        required = false
                    )
                )
            )
        ) { _ ->
            "Goal complete"
        }
    }
}
