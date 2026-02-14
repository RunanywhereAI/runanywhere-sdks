/**
 * Safe Math Expression Evaluator
 *
 * A secure alternative to eval() for math expression evaluation.
 * Uses a recursive descent parser with proper operator precedence.
 *
 * Supports:
 * - Numbers (integers and decimals)
 * - Operators: +, -, *, /
 * - Parentheses for grouping
 * - Unary minus (negative numbers)
 *
 * Security:
 * - No eval() or Function() usage
 * - Tokenizes and validates input
 * - Rejects invalid characters/expressions
 *
 * Example usage:
 *   safeEvaluateExpression("2 + 3 * 4")     // Returns 14
 *   safeEvaluateExpression("(2 + 3) * 4")   // Returns 20
 *   safeEvaluateExpression("-5 + 3")        // Returns -2
 */

/**
 * Tokenize the expression into numbers, operators, and parentheses
 */
const tokenize = (input: string): string[] => {
  // Remove all whitespace
  const cleaned = input.replace(/\s+/g, '');

  // Match numbers (including decimals) and operators/parentheses
  const tokens = cleaned.match(/(\d+\.?\d*|[()+\-*/])/g);

  if (!tokens) {
    throw new Error('Invalid expression: no valid tokens found');
  }

  // Validate that we consumed the entire input
  const reconstructed = tokens.join('');
  if (reconstructed !== cleaned) {
    throw new Error('Invalid expression: contains invalid characters');
  }

  return tokens;
};

/**
 * Safe math expression evaluator using recursive descent parsing
 *
 * Grammar:
 *   expression -> term (('+' | '-') term)*
 *   term       -> factor (('*' | '/') factor)*
 *   factor     -> '-' factor | '(' expression ')' | number
 *
 * @param input - Math expression string (e.g., "2 + 3 * 4")
 * @returns The numeric result
 * @throws Error if expression is invalid
 */
export const safeEvaluateExpression = (input: string): number => {
  if (!input || typeof input !== 'string') {
    throw new Error('Invalid expression: input must be a non-empty string');
  }

  const tokens = tokenize(input);
  let pos = 0;

  /**
   * Get the current token without advancing
   */
  const peek = (): string | undefined => tokens[pos];

  /**
   * Consume and return the current token
   */
  const consume = (): string | undefined => tokens[pos++];

  /**
   * Parse a factor: number, parenthesized expression, or unary minus
   */
  const parseFactor = (): number => {
    const token = peek();

    if (token === undefined) {
      throw new Error('Unexpected end of expression');
    }

    // Handle unary minus
    if (token === '-') {
      consume();
      return -parseFactor();
    }

    // Handle unary plus (optional, just skip it)
    if (token === '+') {
      consume();
      return parseFactor();
    }

    // Handle parenthesized expression
    if (token === '(') {
      consume(); // consume '('
      const value = parseExpression();
      if (peek() !== ')') {
        throw new Error('Missing closing parenthesis');
      }
      consume(); // consume ')'
      return value;
    }

    // Handle number
    if (/^\d+\.?\d*$/.test(token)) {
      consume();
      const value = parseFloat(token);
      if (!Number.isFinite(value)) {
        throw new Error(`Invalid number: ${token}`);
      }
      return value;
    }

    throw new Error(`Unexpected token: ${token}`);
  };

  /**
   * Parse a term: handles * and / with higher precedence
   */
  const parseTerm = (): number => {
    let value = parseFactor();

    while (peek() === '*' || peek() === '/') {
      const op = consume();
      const rhs = parseFactor();

      if (op === '*') {
        value *= rhs;
      } else if (op === '/') {
        if (rhs === 0) {
          throw new Error('Division by zero');
        }
        value /= rhs;
      }
    }

    return value;
  };

  /**
   * Parse an expression: handles + and - with lower precedence
   */
  const parseExpression = (): number => {
    let value = parseTerm();

    while (peek() === '+' || peek() === '-') {
      const op = consume();
      const rhs = parseTerm();

      if (op === '+') {
        value += rhs;
      } else if (op === '-') {
        value -= rhs;
      }
    }

    return value;
  };

  // Parse the entire expression
  const result = parseExpression();

  // Ensure all tokens were consumed
  if (pos !== tokens.length) {
    throw new Error(`Unexpected token at position ${pos}: ${tokens[pos]}`);
  }

  // Check for valid result
  if (!Number.isFinite(result)) {
    throw new Error('Result is not a finite number');
  }

  return result;
};

export default safeEvaluateExpression;
