/**
 * Text Preprocessor for KittenTTS
 *
 * Port of the Python TextPreprocessor from the KittenTTS library.
 * Normalizes text before phonemization: expands numbers, currency,
 * abbreviations, dates, ordinals, etc. into speakable words.
 *
 * Reference: https://github.com/KittenML/KittenTTS/blob/main/kittentts/preprocess.py
 */

// ---------------------------------------------------------------------------
// Number → Words
// ---------------------------------------------------------------------------

const ONES = [
  '', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
  'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
  'seventeen', 'eighteen', 'nineteen',
];

const TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

const SCALE = ['', 'thousand', 'million', 'billion', 'trillion'];

const ORDINAL_EXCEPTIONS: Record<string, string> = {
  one: 'first', two: 'second', three: 'third', four: 'fourth',
  five: 'fifth', six: 'sixth', seven: 'seventh', eight: 'eighth',
  nine: 'ninth', twelve: 'twelfth',
};

const CURRENCY_SYMBOLS: Record<string, string> = {
  '$': 'dollar', '€': 'euro', '£': 'pound', '¥': 'yen',
  '₹': 'rupee', '₩': 'won', '₿': 'bitcoin',
};

function threeDigitsToWords(n: number): string {
  if (n === 0) return '';
  const parts: string[] = [];
  const hundreds = Math.floor(n / 100);
  const remainder = n % 100;
  if (hundreds) parts.push(`${ONES[hundreds]} hundred`);
  if (remainder < 20) {
    if (remainder) parts.push(ONES[remainder]);
  } else {
    const tensWord = TENS[Math.floor(remainder / 10)];
    const onesWord = ONES[remainder % 10];
    parts.push(onesWord ? `${tensWord}-${onesWord}` : tensWord);
  }
  return parts.join(' ');
}

export function numberToWords(n: number): string {
  if (!Number.isInteger(n)) n = Math.round(n);
  if (n === 0) return 'zero';
  if (n < 0) return `negative ${numberToWords(-n)}`;

  // "twelve hundred" style for 100-9999 non-multiples-of-1000
  if (n >= 100 && n <= 9999 && n % 100 === 0 && n % 1000 !== 0) {
    const hundreds = Math.floor(n / 100);
    if (hundreds < 20) return `${ONES[hundreds]} hundred`;
  }

  const parts: string[] = [];
  let remaining = n;
  for (let i = 0; i < SCALE.length && remaining > 0; i++) {
    const chunk = remaining % 1000;
    if (chunk) {
      const chunkWords = threeDigitsToWords(chunk);
      parts.push(SCALE[i] ? `${chunkWords} ${SCALE[i]}` : chunkWords);
    }
    remaining = Math.floor(remaining / 1000);
  }

  return parts.reverse().join(' ');
}

function floatToWords(value: string | number, decimalSep = 'point'): string {
  const text = typeof value === 'string' ? value : `${value}`;
  const negative = text.startsWith('-');
  const stripped = negative ? text.slice(1) : text;

  if (stripped.includes('.')) {
    const [intPart, decPart] = stripped.split('.');
    const intWords = intPart ? numberToWords(parseInt(intPart, 10)) : 'zero';
    const digitMap = ['zero', ...ONES.slice(1)];
    const decWords = decPart.split('').map(d => digitMap[parseInt(d, 10)]).join(' ');
    const result = `${intWords} ${decimalSep} ${decWords}`;
    return negative ? `negative ${result}` : result;
  }

  const result = numberToWords(parseInt(stripped, 10));
  return negative ? `negative ${result}` : result;
}

function ordinalSuffix(n: number): string {
  const word = numberToWords(n);
  const lastWord = word.split(/[\s-]/).pop()!;
  if (ORDINAL_EXCEPTIONS[lastWord]) {
    return word.slice(0, word.length - lastWord.length) + ORDINAL_EXCEPTIONS[lastWord];
  }
  if (lastWord.endsWith('y')) {
    return word.slice(0, word.length - 1) + 'ieth';
  }
  return word + 'th';
}

// ---------------------------------------------------------------------------
// Regex Patterns
// ---------------------------------------------------------------------------

const RE_NUMBER = /(?<![a-zA-Z-])(-?\d[\d,]*\.?\d*)/g;
const RE_ORDINAL = /\b(\d+)(st|nd|rd|th)\b/gi;
const RE_CURRENCY = /([€$£¥₹₩₿])\s?([\d,]+\.?\d*)/g;
const RE_PERCENTAGE = /(\d+\.?\d*)\s*%/g;
const RE_TIME = /\b(\d{1,2}):(\d{2})\s*(am|pm|AM|PM)?\b/g;
const RE_DATE_MDY = /\b(\d{1,2})\/(\d{1,2})\/(\d{2,4})\b/g;
const RE_ABBREVIATION = /\b([A-Z]{2,5})\b/g;
const RE_DECADE = /\b(\d{1,4})0s\b/g;
const RE_FRACTION = /\b(\d+)\/(\d+)\b/g;
const RE_SCALE_SUFFIX = /\b(\d+\.?\d*)([KMBTkmbt])\b/g;
const RE_RANGE = /\b(\d+)\s*[-–—]\s*(\d+)\b/g;

const MONTHS = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const DECADE_MAP: Record<number, string> = {
  0: 'hundreds', 1: 'tens', 2: 'twenties', 3: 'thirties', 4: 'forties',
  5: 'fifties', 6: 'sixties', 7: 'seventies', 8: 'eighties', 9: 'nineties',
};

const SCALE_MAP: Record<string, string> = {
  k: 'thousand', m: 'million', b: 'billion', t: 'trillion',
};

// Common abbreviations that should be spelled out
const ABBREVIATION_MAP: Record<string, string> = {
  AI: 'A I', CEO: 'C E O', GPU: 'G P U', CPU: 'C P U',
  API: 'A P I', URL: 'U R L', HTML: 'H T M L', CSS: 'C S S',
  SQL: 'S Q L', USB: 'U S B', RAM: 'RAM', ROM: 'ROM',
  PDF: 'P D F', FAQ: 'F A Q', DIY: 'D I Y', ATM: 'A T M',
  VPN: 'V P N', DNS: 'D N S', FTP: 'F T P', SSH: 'S S H',
  TTS: 'T T S', STT: 'S T T', NLP: 'N L P', ML: 'M L',
  LLM: 'L L M', UK: 'U K', US: 'U S', EU: 'E U',
  UN: 'U N', NASA: 'NASA', FBI: 'F B I', CIA: 'C I A',
};

// ---------------------------------------------------------------------------
// Individual Expansion Functions
// ---------------------------------------------------------------------------

function expandCurrency(text: string): string {
  return text.replace(RE_CURRENCY, (_match, symbol: string, amount: string) => {
    const currName = CURRENCY_SYMBOLS[symbol] ?? symbol;
    const clean = amount.replace(/,/g, '');
    const num = parseFloat(clean);
    if (isNaN(num)) return _match;

    if (clean.includes('.')) {
      const [intPart, decPart] = clean.split('.');
      const dollars = numberToWords(parseInt(intPart, 10));
      const cents = parseInt(decPart.padEnd(2, '0').slice(0, 2), 10);
      if (cents === 0) {
        return `${dollars} ${currName}${num === 1 ? '' : 's'}`;
      }
      return `${dollars} ${currName}${parseInt(intPart, 10) === 1 ? '' : 's'} and ${numberToWords(cents)} cent${cents === 1 ? '' : 's'}`;
    }

    const words = numberToWords(num);
    return `${words} ${currName}${num === 1 ? '' : 's'}`;
  });
}

function expandPercentages(text: string): string {
  return text.replace(RE_PERCENTAGE, (_match, numStr: string) => {
    const words = numStr.includes('.') ? floatToWords(numStr) : numberToWords(parseInt(numStr, 10));
    return `${words} percent`;
  });
}

function expandOrdinals(text: string): string {
  return text.replace(RE_ORDINAL, (_match, numStr: string) => {
    return ordinalSuffix(parseInt(numStr, 10));
  });
}

function expandTime(text: string): string {
  return text.replace(RE_TIME, (_match, hours: string, minutes: string, period?: string) => {
    const h = parseInt(hours, 10);
    const m = parseInt(minutes, 10);
    let result = numberToWords(h);
    if (m === 0) {
      result += " o'clock";
    } else if (m < 10) {
      result += ` oh ${numberToWords(m)}`;
    } else {
      result += ` ${numberToWords(m)}`;
    }
    if (period) result += ` ${period.toUpperCase()}`;
    return result;
  });
}

function expandDates(text: string): string {
  return text.replace(RE_DATE_MDY, (_match, month: string, day: string, year: string) => {
    const m = parseInt(month, 10);
    const d = parseInt(day, 10);
    let y = parseInt(year, 10);
    if (y < 100) y += 2000;

    const monthName = (m >= 1 && m <= 12) ? MONTHS[m] : numberToWords(m);
    const dayOrd = ordinalSuffix(d);
    const yearWords = expandYear(y);
    return `${monthName} ${dayOrd}, ${yearWords}`;
  });
}

function expandYear(year: number): string {
  if (year >= 2000 && year < 2010) return numberToWords(year);
  if (year >= 2010 && year < 2100) {
    const century = Math.floor(year / 100);
    const rest = year % 100;
    return `${numberToWords(century)} ${rest < 10 ? `oh ${numberToWords(rest)}` : numberToWords(rest)}`;
  }
  if (year >= 1000 && year < 2000) {
    const century = Math.floor(year / 100);
    const rest = year % 100;
    if (rest === 0) return `${numberToWords(century)} hundred`;
    return `${numberToWords(century)} ${rest < 10 ? `oh ${numberToWords(rest)}` : numberToWords(rest)}`;
  }
  return numberToWords(year);
}

function expandDecades(text: string): string {
  return text.replace(RE_DECADE, (_match, base: string) => {
    const num = parseInt(base, 10);
    const decadeDigit = num % 10;
    const decadeWord = DECADE_MAP[decadeDigit] ?? '';
    if (num < 10) return decadeWord;
    const centuryPart = Math.floor(num / 10);
    return `${numberToWords(centuryPart)} ${decadeWord}`;
  });
}

function expandFractions(text: string): string {
  return text.replace(RE_FRACTION, (_match, numStr: string, denStr: string) => {
    const num = parseInt(numStr, 10);
    const den = parseInt(denStr, 10);
    if (den === 0) return _match;

    const numWords = numberToWords(num);
    let denomWord: string;
    if (den === 2) {
      denomWord = num === 1 ? 'half' : 'halves';
    } else if (den === 4) {
      denomWord = num === 1 ? 'quarter' : 'quarters';
    } else {
      denomWord = ordinalSuffix(den);
      if (num !== 1) denomWord += 's';
    }
    return `${numWords} ${denomWord}`;
  });
}

function expandScaleSuffixes(text: string): string {
  return text.replace(RE_SCALE_SUFFIX, (_match, numStr: string, suffix: string) => {
    const scaleWord = SCALE_MAP[suffix.toLowerCase()];
    if (!scaleWord) return _match;
    const words = numStr.includes('.') ? floatToWords(numStr) : numberToWords(parseInt(numStr, 10));
    return `${words} ${scaleWord}`;
  });
}

function expandRanges(text: string): string {
  return text.replace(RE_RANGE, (_match, start: string, end: string) => {
    return `${numberToWords(parseInt(start, 10))} to ${numberToWords(parseInt(end, 10))}`;
  });
}

function expandAbbreviations(text: string): string {
  return text.replace(RE_ABBREVIATION, (match) => {
    return ABBREVIATION_MAP[match] ?? match;
  });
}

function expandNumbers(text: string): string {
  return text.replace(RE_NUMBER, (match) => {
    const clean = match.replace(/,/g, '');
    if (clean.includes('.')) return floatToWords(clean);
    const n = parseInt(clean, 10);
    if (isNaN(n)) return match;
    return numberToWords(n);
  });
}

// ---------------------------------------------------------------------------
// Main Preprocessor
// ---------------------------------------------------------------------------

/**
 * Preprocess text for TTS: normalize numbers, currency, abbreviations,
 * dates, ordinals, etc. into speakable words.
 *
 * Order matters — currency/percentages before generic numbers, etc.
 */
export function preprocessText(text: string): string {
  // Unicode normalization
  text = text.normalize('NFKC');

  // Strip URLs and email addresses
  text = text.replace(/https?:\/\/\S+/g, '');
  text = text.replace(/www\.\S+/g, '');
  text = text.replace(/\b[\w.+-]+@[\w-]+\.[a-z]{2,}\b/gi, '');

  // Expand special patterns (order matters)
  text = expandCurrency(text);
  text = expandPercentages(text);
  text = expandTime(text);
  text = expandDates(text);
  text = expandDecades(text);
  text = expandFractions(text);
  text = expandScaleSuffixes(text);
  text = expandRanges(text);
  text = expandOrdinals(text);
  text = expandAbbreviations(text);
  text = expandNumbers(text);

  // Collapse whitespace
  text = text.replace(/\s+/g, ' ').trim();

  return text;
}
