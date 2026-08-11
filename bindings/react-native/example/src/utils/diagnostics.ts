export const logDiagnostic = (...args: unknown[]) => {
  // eslint-disable-next-line no-console -- diagnostics should not trigger RN LogBox warning UI
  console.log(...args);
};
