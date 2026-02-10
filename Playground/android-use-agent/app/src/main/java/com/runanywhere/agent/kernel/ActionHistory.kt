package com.runanywhere.agent.kernel

data class ActionRecord(
    val step: Int,
    val action: String,
    val target: String?,
    val result: String?,
    val success: Boolean
)

class ActionHistory {
    private val history = mutableListOf<ActionRecord>()
    private var stepCounter = 0

    fun record(action: String, target: String? = null, result: String? = null, success: Boolean = true) {
        stepCounter++
        history.add(ActionRecord(stepCounter, action, target, result, success))
    }

    fun formatForPrompt(): String {
        if (history.isEmpty()) return ""

        val lines = history.takeLast(8).map { record ->
            val targetStr = record.target?.let { " \"$it\"" } ?: ""
            val resultStr = record.result?.let { " -> $it" } ?: ""
            val status = if (record.success) "OK" else "FAILED"
            "Step ${record.step}: ${record.action}$targetStr $status$resultStr"
        }

        return "\n\nPREVIOUS_ACTIONS:\n${lines.joinToString("\n")}"
    }

    fun getLastActionResult(): String? {
        return history.lastOrNull()?.let { record ->
            val targetStr = record.target?.let { "\"$it\"" } ?: ""
            val resultStr = record.result ?: ""
            "${record.action} $targetStr -> $resultStr"
        }
    }

    fun isRepetitive(action: String, target: String?): Boolean {
        if (history.isEmpty()) return false

        // Check if the last 2 actions are the same (exact consecutive repeat)
        val recentActions = history.takeLast(2)
        if (recentActions.size >= 2) {
            val allSame = recentActions.all { it.action == action && it.target == target }
            if (allSame) return true
        }

        // Check for alternating patterns in last 4 actions (A→B→A→B)
        val last4 = history.takeLast(4)
        if (last4.size >= 4) {
            val a = last4[0]; val b = last4[1]; val c = last4[2]; val d = last4[3]
            if (a.action == c.action && a.target == c.target &&
                b.action == d.action && b.target == d.target) {
                return true
            }
        }

        // Check if the same action+target appears 3+ times in last 6 actions
        val last6 = history.takeLast(6)
        val sameCount = last6.count { it.action == action && it.target == target }
        if (sameCount >= 3) return true

        return false
    }

    fun getLastAction(): ActionRecord? = history.lastOrNull()

    fun hadRecentFailure(): Boolean {
        return history.takeLast(2).any { !it.success }
    }

    fun clear() {
        history.clear()
        stepCounter = 0
    }

    fun size(): Int = history.size

    fun recordToolCall(toolName: String, arguments: String, result: String, success: Boolean) {
        stepCounter++
        history.add(ActionRecord(
            step = stepCounter,
            action = "tool:$toolName",
            target = arguments,
            result = result,
            success = success
        ))
    }
}
