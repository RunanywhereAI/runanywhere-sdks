/**
 * CommonJS entry for the model catalog.
 *
 * The SDK's forked utility host resolves the catalog by `require()`ing a path
 * (`RUNANYWHERE_CATALOG_PATH`), so a CommonJS module must exist on disk even
 * though the catalog itself is authored in TypeScript. This file is that
 * artifact: it re-exports the real table so there is exactly one definition.
 *
 * Emitted to `out/main/shared/model-catalog.cjs.cjs` by the main-process tsc
 * project; `src/main/paths.ts` points the host at it.
 *
 * When the SDK gains the ability to accept a serializable catalog object over the
 * message channel, this file and the `catalogPath` wiring can both go away.
 */
import { CATALOG, LICENSES } from './model-catalog';

export { CATALOG, LICENSES };
