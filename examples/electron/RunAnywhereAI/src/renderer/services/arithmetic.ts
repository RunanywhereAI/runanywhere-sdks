/**
 * Hand-written arithmetic evaluator for the demo `calculate` tool.
 *
 * CSP forbids `eval` / `new Function`, so a recursive descent over
 * `+ - * / % ( )` is the only safe path. Ported from the legacy renderer.
 */
export function evalArithmetic(src: string): number {
  let i = 0;

  const ws = (): void => {
    while (i < src.length && /\s/.test(src[i] ?? '')) i += 1;
  };

  const eat = (ch: string): boolean => {
    ws();
    if (src[i] === ch) {
      i += 1;
      return true;
    }
    return false;
  };

  const atom = (): number => {
    ws();
    if (eat('(')) {
      const value = expr();
      if (!eat(')')) throw new Error('missing )');
      return value;
    }
    const start = i;
    while (i < src.length && /[\d.]/.test(src[i] ?? '')) i += 1;
    if (i === start) throw new Error(`expected a number at ${start}`);
    const value = Number(src.slice(start, i));
    if (!Number.isFinite(value)) throw new Error(`not a number: ${src.slice(start, i)}`);
    return value;
  };

  const unary = (): number => {
    if (eat('-')) return -unary();
    if (eat('+')) return unary();
    return atom();
  };

  const term = (): number => {
    let value = unary();
    for (;;) {
      if (eat('*')) value *= unary();
      else if (eat('/')) value /= unary();
      else if (eat('%')) value %= unary();
      else return value;
    }
  };

  const expr = (): number => {
    let value = term();
    for (;;) {
      if (eat('+')) value += term();
      else if (eat('-')) value -= term();
      else return value;
    }
  };

  const result = expr();
  ws();
  if (i !== src.length) throw new Error(`unexpected input at ${i}`);
  if (!Number.isFinite(result)) throw new Error('result is not finite');
  return result;
}
