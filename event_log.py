"""Lightweight helper to log informational events on Windows."""

from __future__ import annotations

import ctypes
import platform


EVENTLOG_INFORMATION_TYPE = 0x0004


def log_event(message: str, *, event_type: int = EVENTLOG_INFORMATION_TYPE, source: str = "PackageManagementScripts") -> None:
    """Write an informational entry to the Windows Application event log.

    The function is a no-op on non-Windows hosts or when the underlying
    Win32 APIs are unavailable. Errors are suppressed to avoid disrupting
    the calling script.
    """

    if platform.system() != "Windows":
        return

    try:
        advapi32 = ctypes.windll.advapi32
    except (AttributeError, OSError):
        return

    handle = advapi32.RegisterEventSourceW(None, source)
    if not handle:
        return

    try:
        strings = (ctypes.c_wchar_p * 1)(message)
        advapi32.ReportEventW(
            handle,
            event_type,
            0,
            0x1000,
            None,
            1,
            0,
            ctypes.cast(strings, ctypes.POINTER(ctypes.c_wchar_p)),
            None,
        )
    except OSError:
        pass
    finally:
        advapi32.DeregisterEventSource(handle)
