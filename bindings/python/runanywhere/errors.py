"""SDKException, the single throwable type the SDK raises (port of errors.ts)."""

from __future__ import annotations

from typing import Any, NoReturn

from ._generated_errors import ErrorCategory, ErrorCode


def category_for_code(code: int) -> ErrorCategory:
    """Map a signed C ABI code or positive proto code to its canonical category."""
    magnitude = abs(int(code))
    if magnitude == 0:
        return ErrorCategory.UNSPECIFIED
    if 100 <= magnitude <= 109:
        return ErrorCategory.CONFIGURATION
    if 110 <= magnitude <= 129:
        return ErrorCategory.MODEL
    if 130 <= magnitude <= 149 or 220 <= magnitude <= 229:
        return ErrorCategory.INTERNAL
    if 150 <= magnitude <= 179:
        return ErrorCategory.NETWORK
    if 180 <= magnitude <= 219 or 280 <= magnitude <= 299 or 350 <= magnitude <= 369:
        return ErrorCategory.IO
    if 230 <= magnitude <= 249 or 300 <= magnitude <= 319:
        return ErrorCategory.COMPONENT
    if 250 <= magnitude <= 279 or 370 <= magnitude <= 379:
        return ErrorCategory.VALIDATION
    if 320 <= magnitude <= 349:
        return ErrorCategory.AUTH
    if 380 <= magnitude <= 389 or 700 <= magnitude <= 999:
        return ErrorCategory.INTERNAL
    if 400 <= magnitude <= 499:
        return ErrorCategory.COMPONENT
    if 500 <= magnitude <= 599:
        return ErrorCategory.CONFIGURATION
    if 600 <= magnitude <= 699:
        return ErrorCategory.COMPONENT
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
    def from_proto(err: Any) -> "SDKException":
        """Build an SDKException from an ``SDKError`` proto submessage.

        Mirrors the proto-backed constructor every other SDK exposes
        (Swift ``SDKException(proto:)``): the carried failure now lives in the
        structured ``SDKError`` rather than a loose success/message/code triad.
        """
        try:
            code = ErrorCode(err.code)
        except ValueError:
            code = ErrorCode.UNKNOWN
        try:
            category = ErrorCategory(err.category)
        except ValueError:
            category = ErrorCategory.UNSPECIFIED
        field_path = err.param if err.HasField("param") else None
        return SDKException.of(
            code,
            err.message,
            category=category,
            c_abi_code=err.c_abi_code if err.HasField("c_abi_code") else None,
            nested_message=err.nested_message if err.HasField("nested_message") else None,
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
            category=ErrorCategory.VALIDATION,
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
            category=ErrorCategory.MODEL,
        )

    @staticmethod
    def model_load_failed(
        model_id: str | None = None, cause: BaseException | None = None
    ) -> "SDKException":
        return SDKException.of(
            ErrorCode.MODEL_LOAD_FAILED,
            f"Failed to load model: {model_id}" if model_id else "Failed to load model",
            category=ErrorCategory.MODEL,
            nested_message=str(cause) if cause is not None else None,
        )

    @staticmethod
    def generation_failed(
        details: str | None = None, cause: BaseException | None = None
    ) -> "SDKException":
        return SDKException.of(
            ErrorCode.GENERATION_FAILED,
            details if details is not None else "Generation failed",
            category=ErrorCategory.INTERNAL,
            nested_message=str(cause) if cause is not None else None,
        )

    @staticmethod
    def storage_error(
        details: str | None = None, cause: BaseException | None = None
    ) -> "SDKException":
        return SDKException.of(
            ErrorCode.STORAGE_ERROR,
            details if details is not None else "Storage error",
            category=ErrorCategory.IO,
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
            category=ErrorCategory.INTERNAL,
        )

    @staticmethod
    def unsupported_capability(name: str, reason: str) -> "SDKException":
        """A public v4 operation that is honestly absent on this platform/build.

        Thrown at preflight, before any work starts. The same ``name``/``reason``
        pair also appears in :func:`runanywhere.capabilities`'s ``unavailable`` list,
        so callers can discover the gap without triggering the exception first.
        """
        return SDKException.of(
            ErrorCode.FEATURE_NOT_AVAILABLE,
            f"{name} is not supported: {reason}",
            category=ErrorCategory.CONFIGURATION,
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
            category=ErrorCategory.INTERNAL,
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
        category=category_for_code(rac_code),
        c_abi_code=rac_code,
    )
