/**
 * Electron PRELOAD.
 *
 * The ORDER of the two statements below is load-bearing: the catalog must be
 * staged BEFORE the SDK's preload is loaded, because registration is per process
 * and the SDK's `initialize()` seeds whatever is staged into the commons
 * registry. tsc emits a CommonJS `require` at the position of its import, so the
 * side-effect import really does run last — do NOT hoist it for tidiness.
 *
 * That side-effect import is the whole of the rest of this file: it publishes
 * `window.runanywhere` over contextBridge. This app adds no bridge of its own.
 */
import { registerCatalog } from '@runanywhere/electron';

import { CATALOG } from './catalog';

registerCatalog(CATALOG);

import '@runanywhere/electron/preload';
