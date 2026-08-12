//
//  SafeMathEvaluator.swift
//  RunAnywhereAI
//
//  Deterministic recursive-descent parser for simple arithmetic expressions,
//  backing the `calculate` tool. Replaces NSExpression(format:) which can
//  raise uncaught Objective-C exceptions (e.g. for "1 2", "(1+2", "1++2")
//  that Swift's do-catch cannot intercept. Supports the grammar:
//    expr    := term (("+" | "-") term)*
//    term    := factor (("*" | "/") factor)*
//    factor  := ("+" | "-") factor | primary
//    primary := number | "(" expr ")"
//

import Foundation

enum SafeMathEvaluator {
    static func evaluate(_ expression: String) -> Double? {
        var parser = Parser(input: expression)
        guard let value = parser.parseExpression() else { return nil }
        guard parser.isAtEnd else { return nil }
        guard value.isFinite else { return nil }
        return value
    }

    private struct Parser {
        let scalars: [Character]
        var index: Int = 0

        init(input: String) {
            self.scalars = Array(input)
        }

        var isAtEnd: Bool {
            mutating get {
                skipWhitespace()
                return index >= scalars.count
            }
        }

        mutating func skipWhitespace() {
            while index < scalars.count, scalars[index].isWhitespace {
                index += 1
            }
        }

        mutating func peek() -> Character? {
            skipWhitespace()
            return index < scalars.count ? scalars[index] : nil
        }

        mutating func advance() -> Character? {
            skipWhitespace()
            guard index < scalars.count else { return nil }
            let char = scalars[index]
            index += 1
            return char
        }

        mutating func match(_ char: Character) -> Bool {
            if peek() == char {
                _ = advance()
                return true
            }
            return false
        }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                _ = advance()
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                _ = advance()
                guard let rhs = parseFactor() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        mutating func parseFactor() -> Double? {
            if match("+") { return parseFactor() }
            if match("-") {
                guard let value = parseFactor() else { return nil }
                return -value
            }
            return parsePrimary()
        }

        mutating func parsePrimary() -> Double? {
            guard let next = peek() else { return nil }
            if next == "(" {
                _ = advance()
                guard let value = parseExpression() else { return nil }
                guard match(")") else { return nil }
                return value
            }
            return parseNumber()
        }

        mutating func parseNumber() -> Double? {
            skipWhitespace()
            let start = index
            var seenDot = false
            while index < scalars.count {
                let char = scalars[index]
                if char.isNumber {
                    index += 1
                } else if char == "." && !seenDot {
                    seenDot = true
                    index += 1
                } else {
                    break
                }
            }
            guard index > start else { return nil }
            return Double(String(scalars[start..<index]))
        }
    }
}
