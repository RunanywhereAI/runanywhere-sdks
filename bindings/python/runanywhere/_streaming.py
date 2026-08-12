"""Bridge a blocking native streaming call (callback-per-token) to Python iterators."""

from __future__ import annotations

import asyncio
import concurrent.futures
import queue
import threading
from typing import AsyncIterator, Callable, Iterator

# native_call runs a blocking C loop, invoking on_token(str) once per token; on_token
# returns True to keep going and False to stop the loop early (mirrors the addon ABI).
NativeCall = Callable[[Callable[[str], "bool | None"]], None]

# Sentinels distinguishing normal completion from a worker exception on the token queue.
_DONE = object()
_ERROR = object()


class _Bridge:
    """Runs ``native_call`` on a worker thread and mediates the stop/exception protocol.

    Subclasses (sync / async) supply ``_deliver`` — how a token produced on the worker
    thread reaches the consumer — and drive their own queue draining. This base owns the
    worker lifecycle: the thread, the stop :class:`threading.Event`, exception capture and
    the ``on_token`` callback whose return value tells the C loop whether to keep emitting.
    """

    def __init__(self, native_call: NativeCall, on_stop: Callable[[], None] | None = None) -> None:
        self._native_call = native_call
        self._on_stop = on_stop
        self._stop = threading.Event()
        self._error: BaseException | None = None
        self._thread = threading.Thread(target=self._run, name="ra-stream", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def _run(self) -> None:
        """Worker body: drive the native call, then signal completion or the error."""
        try:
            self._native_call(self._on_token)
        except BaseException as exc:  # noqa: BLE001 — surfaced to the consumer verbatim
            self._error = exc
            self._on_error()
        else:
            self._on_done()

    def _on_token(self, token: str) -> bool:
        """Called by the native loop per token. Return False once stop was requested."""
        if self._stop.is_set():
            return False
        self._deliver(token)
        # Re-check: _deliver may block (backpressure); a stop during the block ends the loop.
        return not self._stop.is_set()

    def request_stop(self) -> None:
        """Signal the next ``on_token`` to return False so the C loop unwinds.

        Also invokes the optional ``on_stop`` hook (e.g. ``rac_*_component_cancel``)
        so decode stops promptly rather than waiting for the next token callback.
        """
        self._stop.set()
        if self._on_stop is not None:
            try:
                self._on_stop()
            except Exception:  # noqa: BLE001 — teardown must not raise
                pass

    def join(self, timeout: float | None = None) -> None:
        self._thread.join(timeout)

    def reraise_if_error(self) -> None:
        """Re-raise (in the consumer) any exception the worker captured."""
        if self._error is not None:
            raise self._error

    # --- subclass hooks -------------------------------------------------------
    def _deliver(self, token: str) -> None:  # pragma: no cover - overridden
        raise NotImplementedError

    def _on_done(self) -> None:  # pragma: no cover - overridden
        raise NotImplementedError

    def _on_error(self) -> None:  # pragma: no cover - overridden
        raise NotImplementedError


class _SyncBridge(_Bridge):
    """Backs :func:`iter_tokens`: tokens flow through a bounded ``queue.Queue``."""

    def __init__(
        self, native_call: NativeCall, maxsize: int, on_stop: Callable[[], None] | None = None
    ) -> None:
        super().__init__(native_call, on_stop=on_stop)
        self._q: queue.Queue = queue.Queue(maxsize=maxsize)

    def _deliver(self, token: str) -> None:
        # Blocking put == backpressure: the worker parks when the consumer lags. Poll with
        # a timeout so a stop requested during the park is observed promptly.
        while True:
            if self._stop.is_set():
                return
            try:
                self._q.put(token, timeout=0.05)
                return
            except queue.Full:
                continue

    def _on_done(self) -> None:
        self._q.put(_DONE)

    def _on_error(self) -> None:
        self._q.put(_ERROR)

    def get(self) -> object:
        return self._q.get()


def iter_tokens(
    native_call: NativeCall,
    *,
    maxsize: int = 64,
    on_stop: Callable[[], None] | None = None,
) -> Iterator[str]:
    """Consume a blocking native streaming call as a synchronous token generator.

    ``native_call`` is invoked on a worker thread; it calls the supplied
    ``on_token(str) -> bool`` once per token. Tokens cross to the consumer through a
    bounded :class:`queue.Queue` (``maxsize``) that provides backpressure. Each token is
    yielded in turn. If the generator is closed or the caller breaks out of the loop, a
    stop :class:`threading.Event` is set so the next ``on_token`` returns ``False`` and the
    native loop unwinds; ``on_stop`` (when provided) also fires so the C component can
    cancel promptly. The worker is then joined. Any exception raised inside
    ``native_call`` is re-raised here, in the consumer.
    """
    bridge = _SyncBridge(native_call, maxsize, on_stop=on_stop)
    bridge.start()
    try:
        while True:
            item = bridge.get()
            if item is _DONE:
                break
            if item is _ERROR:
                bridge.reraise_if_error()
                break
            yield item  # type: ignore[misc]
    finally:
        # Break/close/exception all land here: stop the C loop, drain so a parked worker
        # unblocks, then join. Draining avoids a deadlock where the worker is stuck on a
        # full queue while we wait on join.
        bridge.request_stop()
        while True:
            try:
                item = bridge._q.get_nowait()
            except queue.Empty:
                break
            if item is _DONE or item is _ERROR:
                break
        bridge.join()


class _AsyncBridge(_Bridge):
    """Backs :func:`aiter_tokens`: worker hands tokens to the loop via ``call_soon_threadsafe``.

    Backpressure is enforced by having the worker block on a
    :class:`concurrent.futures.Future` that the loop resolves only after the token has been
    accepted into the bounded :class:`asyncio.Queue`.
    """

    def __init__(
        self,
        native_call: NativeCall,
        maxsize: int,
        loop: asyncio.AbstractEventLoop,
        on_stop: Callable[[], None] | None = None,
    ) -> None:
        super().__init__(native_call, on_stop=on_stop)
        self._loop = loop
        self._q: asyncio.Queue = asyncio.Queue(maxsize=maxsize)

    def _deliver(self, token: str) -> None:
        # Hand the token to the loop and wait (on the worker thread) until it has been
        # enqueued — that wait is the backpressure. A stop aborts the wait.
        fut: concurrent.futures.Future = concurrent.futures.Future()
        self._loop.call_soon_threadsafe(self._enqueue, token, fut)
        while True:
            if self._stop.is_set():
                return
            try:
                fut.result(timeout=0.05)
                return
            except concurrent.futures.TimeoutError:
                continue

    def _enqueue(self, token: str, fut: concurrent.futures.Future) -> None:
        """Run on the loop thread: push into the asyncio.Queue, then release the worker.

        If the queue is full we reschedule ourselves so the worker stays parked (its
        Future unresolved) until the consumer drains — this is the async backpressure.
        """
        if fut.done():  # stop already aborted the worker's wait; drop the token
            return
        try:
            self._q.put_nowait(token)
        except asyncio.QueueFull:
            self._loop.call_soon(self._enqueue, token, fut)
            return
        fut.set_result(None)

    def _enqueue_sentinel(self, sentinel: object) -> None:
        """Run on the loop thread: push a terminal sentinel, rescheduling while the queue
        is full so it is never dropped.

        A bare ``put_nowait`` raises :class:`asyncio.QueueFull` inside the loop callback,
        where it is swallowed by the exception handler and the consumer waits on ``get()``
        forever. ``_enqueue`` already reschedules tokens for the same reason, and the sync
        bridge gets this for free from its blocking ``put``. Stop means the consumer is
        gone, so there is nobody left to hand the sentinel to.
        """
        if self._stop.is_set():
            return
        try:
            self._q.put_nowait(sentinel)
        except asyncio.QueueFull:
            self._loop.call_soon(self._enqueue_sentinel, sentinel)

    def _on_done(self) -> None:
        self._loop.call_soon_threadsafe(self._enqueue_sentinel, _DONE)

    def _on_error(self) -> None:
        self._loop.call_soon_threadsafe(self._enqueue_sentinel, _ERROR)

    async def get(self) -> object:
        return await self._q.get()


async def aiter_tokens(
    native_call: NativeCall,
    *,
    maxsize: int = 64,
    on_stop: Callable[[], None] | None = None,
) -> AsyncIterator[str]:
    """Async twin of :func:`iter_tokens` over the same blocking ``native_call``.

    The worker thread hands each token to the running event loop via
    ``loop.call_soon_threadsafe`` into a bounded :class:`asyncio.Queue`; the worker blocks
    on a :class:`concurrent.futures.Future` until the token is accepted, giving
    backpressure. On ``aclose`` (or breaking the ``async for``) the stop event is set — so
    the next ``on_token`` returns ``False`` — ``on_stop`` fires when provided, and the
    worker is joined. Exceptions raised in ``native_call`` are re-raised in the consumer.
    """
    loop = asyncio.get_running_loop()
    bridge = _AsyncBridge(native_call, maxsize, loop, on_stop=on_stop)
    bridge.start()
    try:
        while True:
            item = await bridge.get()
            if item is _DONE:
                break
            if item is _ERROR:
                bridge.reraise_if_error()
                break
            yield item  # type: ignore[misc]
    finally:
        bridge.request_stop()
        # Drain so a worker parked on a pending Future is released, then join off-loop so
        # we never block the event loop on thread teardown. Shield the join so a cancellation
        # arriving DURING teardown (client disconnect / shutdown) still completes it — otherwise
        # the worker could outlive this frame and a caller's generation guard could be released
        # while the native call is still running (two in-flight calls on one model handle).
        while not bridge._q.empty():
            try:
                bridge._q.get_nowait()
            except asyncio.QueueEmpty:
                break
        await asyncio.shield(loop.run_in_executor(None, bridge.join))
