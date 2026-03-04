package com.runanywhere.agent.toolcalling

object SimpleExpressionEvaluator {

    fun evaluate(expression: String): Double {
        val tokens = tokenize(expression.replace(" ", ""))
        val parser = Parser(tokens)
        val result = parser.parseExpression()
        if (parser.pos < tokens.size) {
            throw IllegalArgumentException("Unexpected token: ${tokens[parser.pos]}")
        }
        return result
    }

    private fun tokenize(input: String): List<String> {
        val tokens = mutableListOf<String>()
        var i = 0
        while (i < input.length) {
            val c = input[i]
            when {
                c in "+-*/()" -> {
                    tokens.add(c.toString())
                    i++
                }
                c.isDigit() || c == '.' -> {
                    val sb = StringBuilder()
                    while (i < input.length && (input[i].isDigit() || input[i] == '.')) {
                        sb.append(input[i])
                        i++
                    }
                    tokens.add(sb.toString())
                }
                else -> i++ // skip unknown characters
            }
        }
        return tokens
    }

    private class Parser(private val tokens: List<String>) {
        var pos = 0

        fun parseExpression(): Double {
            var result = parseTerm()
            while (pos < tokens.size && tokens[pos] in listOf("+", "-")) {
                val op = tokens[pos++]
                val right = parseTerm()
                result = if (op == "+") result + right else result - right
            }
            return result
        }

        private fun parseTerm(): Double {
            var result = parseFactor()
            while (pos < tokens.size && tokens[pos] in listOf("*", "/")) {
                val op = tokens[pos++]
                val right = parseFactor()
                result = if (op == "*") result * right else {
                    if (right == 0.0) throw ArithmeticException("Division by zero")
                    result / right
                }
            }
            return result
        }

        private fun parseFactor(): Double {
            if (pos < tokens.size && tokens[pos] == "-") {
                pos++
                return -parseFactor()
            }
            if (pos < tokens.size && tokens[pos] == "+") {
                pos++
                return parseFactor()
            }
            if (pos < tokens.size && tokens[pos] == "(") {
                pos++ // consume '('
                val result = parseExpression()
                if (pos < tokens.size && tokens[pos] == ")") pos++ // consume ')'
                return result
            }
            if (pos < tokens.size) {
                return tokens[pos++].toDoubleOrNull()
                    ?: throw IllegalArgumentException("Invalid number: ${tokens[pos - 1]}")
            }
            throw IllegalArgumentException("Unexpected end of expression")
        }
    }
}
