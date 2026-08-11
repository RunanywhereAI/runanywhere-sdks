import { ErrorCategory } from '../errors';
export declare const errorCategoryWireString: (e: ErrorCategory) => string;
export declare const errorCategoryFromWireString: (s: string) => ErrorCategory | undefined;
