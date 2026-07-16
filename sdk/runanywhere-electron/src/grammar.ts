// grammar.ts — convert a (subset of) JSON Schema to a GBNF grammar so llama.cpp
// can *constrain* decoding to valid JSON of the requested shape (guaranteed
// parseable output, not prompt-and-hope). Supports object/array/string/number/
// integer/boolean/null/enum and nesting — enough for structured extraction.

export interface JsonSchema {
  type?: 'object' | 'array' | 'string' | 'number' | 'integer' | 'boolean' | 'null';
  properties?: Record<string, JsonSchema>;
  required?: string[];
  items?: JsonSchema;
  enum?: Array<string | number | boolean>;
  /** Fixed literal value (JSON const) — matches exactly this value. */
  const?: string | number | boolean;
  /** Union: the value must match one of these schemas (alternation). */
  anyOf?: JsonSchema[];
}

const PRIMITIVES: Record<string, string> = {
  ws: 'ws ::= [ \\t\\n]*',
  string: 'string ::= "\\"" ( [^"\\\\] | "\\\\" ["\\\\/bfnrt] )* "\\""',
  integer: 'integer ::= "-"? ( "0" | [1-9] [0-9]* )',
  number: 'number ::= "-"? ( "0" | [1-9] [0-9]* ) ( "." [0-9]+ )? ( [eE] [-+]? [0-9]+ )?',
  boolean: 'boolean ::= "true" | "false"',
};

/** Wrap literal text `s` as a GBNF double-quoted literal (escaping \ and "). */
function lit(s: string): string {
  return '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}

export function jsonSchemaToGrammar(schema: JsonSchema): string {
  const rules: string[] = [];
  const used = new Set<string>();
  let n = 0;

  function build(s: JsonSchema): string {
    if (s.anyOf && s.anyOf.length) {
      const name = `any${n++}`;
      rules.push(`${name} ::= ${s.anyOf.map((sub) => build(sub)).join(' | ')}`);
      return name;
    }
    if (s.const !== undefined) {
      const name = `const${n++}`;
      rules.push(`${name} ::= ${lit(JSON.stringify(s.const))}`);
      return name;
    }
    if (s.enum && s.enum.length) {
      const name = `enum${n++}`;
      rules.push(`${name} ::= ${s.enum.map((v) => lit(JSON.stringify(v))).join(' | ')}`);
      return name;
    }
    switch (s.type) {
      case 'object': {
        const props = s.properties ?? {};
        const keys = Object.keys(props);
        const name = `obj${n++}`;
        used.add('ws');
        if (!keys.length) {
          rules.push(`${name} ::= "{" ws "}"`);
          return name;
        }
        const parts = keys.map((k) => `${lit('"' + k + '"')} ws ":" ws ${build(props[k])}`);
        rules.push(`${name} ::= "{" ws ${parts.join(' ws "," ws ')} ws "}"`);
        return name;
      }
      case 'array': {
        const item = s.items ? build(s.items) : 'string';
        if (!s.items) used.add('string');
        const name = `arr${n++}`;
        used.add('ws');
        rules.push(`${name} ::= "[" ws ( ${item} ( ws "," ws ${item} )* )? ws "]"`);
        return name;
      }
      case 'integer':
        used.add('integer');
        return 'integer';
      case 'number':
        used.add('number');
        return 'number';
      case 'boolean':
        used.add('boolean');
        return 'boolean';
      case 'null':
        return '"null"';
      case 'string':
      default:
        used.add('string');
        return 'string';
    }
  }

  const root = build(schema);
  const lines = [`root ::= ${root}`, ...rules];
  for (const p of used) lines.push(PRIMITIVES[p]);
  return lines.join('\n');
}
