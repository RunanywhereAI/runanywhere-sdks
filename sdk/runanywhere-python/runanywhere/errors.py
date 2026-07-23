"""SDKException, the single throwable type the SDK raises (port of errors.ts)."""

from __future__ import annotations

from enum import IntEnum
from typing import NoReturn


class ErrorCode(IntEnum):
    """Canonical numeric error codes from idl/errors.proto (replicated, not generated)."""

    UNSPECIFIED = 0
    NOT_INITIALIZED = 100
    MODEL_NOT_FOUND = 110
    MODEL_LOAD_FAILED = 111
    GENERATION_FAILED = 130
    STORAGE_ERROR = 182
    INVALID_STATE = 231
    SERVICE_NOT_AVAILABLE = 232
    PROCESSING_FAILED = 234
    INVALID_INPUT = 251
    INVALID_ARGUMENT = 259
    CANCELLED = 380
    NOT_IMPLEMENTED = 800
    UNKNOWN = 804


class ErrorCategory(IntEnum):
    """Canonical error categories from idl/errors.proto."""

    UNSPECIFIED = 0
    NETWORK = 1
    VALIDATION = 2
    MODEL = 3
    COMPONENT = 4
    IO = 5
    AUTH = 6
    INTERNAL = 7
    CONFIGURATION = 8


def category_for_code(code: int) -> ErrorCategory:
    """Map an ErrorCode to its ErrorCategory.

    Verbatim port of the canonical range table in commons
    ``rac_error_proto.cpp::category_for_code()`` (also replicated in the
    Electron/RN/Web SDKs). Keep in sync.
    """
    if code == 0:
        return ErrorCategory.UNSPECIFIED
    if 100 <= code <= 109:
        return ErrorCategory.CONFIGURATION
    if 110 <= code <= 129:
        return ErrorCategory.MODEL
    if 130 <= code <= 149:
        return ErrorCategory.COMPONENT
    if 150 <= code <= 179:
        return ErrorCategory.NETWORK
    if (180 <= code <= 219) or (280 <= code <= 299):
        return ErrorCategory.IO
    if 220 <= code <= 229:
        return ErrorCategory.INTERNAL
    if 230 <= code <= 249:
        return ErrorCategory.COMPONENT
    if 250 <= code <= 279:
        return ErrorCategory.VALIDATION
    if 300 <= code <= 319:
        return ErrorCategory.COMPONENT
    if 320 <= code <= 349:
        return ErrorCategory.AUTH
    if 350 <= code <= 369:
        return ErrorCategory.IO
    if 370 <= code <= 379:
        return ErrorCategory.VALIDATION
    if 380 <= code <= 389:
        return ErrorCategory.INTERNAL
    if 400 <= code <= 499:
        return ErrorCategory.COMPONENT
    if 500 <= code <= 599:
        return ErrorCategory.CONFIGURATION
    if 600 <= code <= 699:
        return ErrorCategory.COMPONENT
    if 700 <= code <= 999:
        return ErrorCategory.INTERNAL
    return ErrorCategory.UNSPECIFIED


class SDKException(Exception):
    """The single throwable type the SDK raises.

    Carries the canonical ``code`` / ``category`` for cross-SDK-uniform handling,
    mirroring the Swift / Kotlin / React-Native / Web / Electron SDKs so consumer
    code can read ``e.code`` / ``e.category`` / ``e.recovery_suggestion`` /
    ``e.field_path`` uniformly.
    """

    code: ErrorCode
    category: ErrorCategory
    #: Negative rac_result_t equivalent, when applicable.
    c_abi_code: int | None
    nested_message: str | None
    #: Structured validation field path (e.g. "ToolSpec.name"), when applicable.
    field_path: str | None

    def __init__(
        self,
        code: ErrorCode,
        message: str,
        *,
        category: ErrorCategory | None = None,
        c_abi_code: int | None = None,
        nested_message: str | None = None,
        field_path: str | None = None,
    ) -> None:
        super().__init__(message or "SDK error")
        self.message = message or "SDK error"
        self.code = code
        self.category = category if category is not None else category_for_code(int(code))
        if c_abi_code is not None:
            self.c_abi_code = c_abi_code
        elif 0 < int(code) <= 899:
            self.c_abi_code = -int(code)
        else:
            self.c_abi_code = None
        self.nested_message = nested_message
        self.field_path = field_path

    @property
    def recovery_suggestion(self) -> str | None:
        """Human-readable recovery hint for common codes, mirroring the other SDKs."""
        if self.code == ErrorCode.NOT_INITIALIZED:
            return "Initialize the SDK (RunAnywhere.initialize()) before using it."
        if self.code == ErrorCode.MODEL_NOT_FOUND:
            return "Ensure the model is downloaded and the path/id is correct."
        if self.code == ErrorCode.MODEL_LOAD_FAILED:
            return "Check the model file is valid and compatible."
        if self.code == ErrorCode.STORAGE_ERROR:
            return "Free up storage space and try again."
        return None

    @property
    def is_expected(self) -> bool:
        """Expected/routine errors (cancellation) that need not be logged as errors."""
        return self.code == ErrorCode.CANCELLED

    # -- factories -----------------------------------------------------------
    @staticmethod
    def of(
        code: ErrorCode,
        message: str,
        *,
        category: ErrorCategory | None = None,
        c_abi_code: int | None = None,
        nested_message: str | None = None,
        field_path: str | None = None,
    ) -> "SDKException":
        return SDKException(
            code,
            message,
            category=category,
            c_abi_code=c_abi_code,
            nested_message=nested_message,
            field_path=field_path,
        )

    @staticmethod
    def not_initialized(component: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.NOT_INITIALIZED,
            f"{component} not initialized" if component else "SDK not initialized",
            category=ErrorCategory.COMPONENT,
        )

    @staticmethod
    def invalid_input(details: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.INVALID_INPUT,
            f"Invalid input: {details}" if details else "Invalid input",
        )

    @staticmethod
    def validation_failed(*, field_path: str, message: str) -> "SDKException":
        return SDKException.of(
            ErrorCode.INVALID_ARGUMENT,
            message,
            category=ErrorCategory.VALIDATION,
            c_abi_code=-259,
            field_path=field_path,
        )

    @staticmethod
    def model_not_found(model_id: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.MODEL_NOT_FOUND,
            f"Model not found: {model_id}" if model_id else "Model not found",
        )

    @staticmethod
    def model_load_failed(
        model_id: str | None = None, cause: BaseException | None = None
    ) -> "SDKException":
        return SDKException.of(
            ErrorCode.MODEL_LOAD_FAILED,
            f"Failed to load model: {model_id}" if model_id else "Failed to load model",
            nested_message=str(cause) if cause is not None else None,
        )

    @staticmethod
    def generation_failed(
        details: str | None = None, cause: BaseException | None = None
    ) -> "SDKException":
        return SDKException.of(
            ErrorCode.GENERATION_FAILED,
            details if details is not None else "Generation failed",
            nested_message=str(cause) if cause is not None else None,
        )

    @staticmethod
    def invalid_state(details: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.INVALID_STATE,
            details if details is not None else "Invalid state",
            category=ErrorCategory.INTERNAL,
        )

    @staticmethod
    def not_implemented(feature: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.NOT_IMPLEMENTED,
            f"{feature} not implemented" if feature else "Not implemented",
        )

    @staticmethod
    def cancelled(message: str | None = None) -> "SDKException":
        return SDKException.of(
            ErrorCode.CANCELLED,
            message if message is not None else "Operation cancelled",
            category=ErrorCategory.INTERNAL,
        )

    @staticmethod
    def unknown(
        details: str | None = None, cause: BaseException | None = None
    ) -> "SDKException":
        return SDKException.of(
            ErrorCode.UNKNOWN,
            details if details is not None else "Unknown error",
            nested_message=str(cause) if cause is not None else None,
        )


def is_sdk_exception(e: object) -> bool:
    """Type guard: True iff ``e`` is an :class:`SDKException`."""
    return isinstance(e, SDKException)


def as_sdk_exception(e: object) -> SDKException:
    """Coerce any thrown value into an SDKException (matches RN/Web ``asSDKException``)."""
    if isinstance(e, SDKException):
        return e
    if isinstance(e, BaseException):
        return SDKException.unknown(str(e), e)
    if isinstance(e, str):
        return SDKException.unknown(e)
    return SDKException.unknown(str(e))


def raise_for_rac(rac_code: int, message: str | None = None) -> NoReturn:
    """Raise an :class:`SDKException` for a negative ``rac_result_t`` code.

    ``rac_code`` is the NEGATIVE rac_result_t returned by the native layer. The
    error code is ``ErrorCode(-rac_code)`` when that value is a known enum member,
    otherwise :attr:`ErrorCode.UNKNOWN`. The original ``rac_code`` is preserved as
    ``c_abi_code`` so callers can inspect the raw ABI value.
    """
    positive = -rac_code
    try:
        code = ErrorCode(positive)
    except ValueError:
        code = ErrorCode.UNKNOWN
    raise SDKException.of(
        code,
        message if message is not None else f"Native call failed (rac={rac_code})",
        c_abi_code=rac_code,
    )
