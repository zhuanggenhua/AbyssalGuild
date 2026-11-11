#!/usr/bin/env python3
"""Bound a Godot test and reject diagnostics even when the engine exits zero.

Only Python's standard library is required. Linux and macOS both support the
isolated process session used to stop a timed-out engine and its descendants.
"""

import math
import os
import re
import signal
import subprocess
import sys


ANSI_ESCAPE = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")
FAILURE = re.compile(
    rb"(?:^|\s)(?:SCRIPT\s+ERROR\s*:|ERROR\s*:|FAIL\s*:|Assertion\s*failed)",
    re.IGNORECASE,
)


def stop_process_tree(process):
    """Terminate the session, then force-kill it if shutdown does not finish."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        output, _ = process.communicate(timeout=1)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            output, _ = process.communicate(timeout=1)
        except subprocess.TimeoutExpired as error:
            # Do not wait forever if a separately detached descendant retained
            # the pipe. The engine group was already killed; close our reader.
            output = error.output or b""
            process.stdout.close()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
    finally:
        # A child might have closed its output without exiting after SIGTERM.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    return output


def relay(output):
    if output:
        sys.stdout.buffer.write(output)
        sys.stdout.buffer.flush()


def main(command=None):
    command = sys.argv[1:] if command is None else command
    if not command:
        print("GODOT TEST FAILED: no engine command supplied.", file=sys.stderr)
        return 2
    raw_timeout = os.environ.get("GODOT_TEST_TIMEOUT", "90")
    try:
        timeout = float(raw_timeout)
        if not math.isfinite(timeout) or not 0 < timeout <= 3600:
            raise ValueError
    except ValueError:
        print("GODOT TEST FAILED: GODOT_TEST_TIMEOUT must be seconds in (0, 3600].", file=sys.stderr)
        return 2
    try:
        process = subprocess.Popen(
            command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    except OSError as error:
        print(f"GODOT TEST FAILED: could not start engine: {error}", file=sys.stderr)
        return 127
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        relay(stop_process_tree(process))
        print(f"GODOT TEST TIMEOUT: exceeded {timeout:g} seconds; engine stopped.", file=sys.stderr)
        return 124
    except KeyboardInterrupt:
        relay(stop_process_tree(process))
        print("GODOT TEST INTERRUPTED: engine stopped.", file=sys.stderr)
        return 130
    relay(output)
    if FAILURE.search(ANSI_ESCAPE.sub(b"", output)):
        print("GODOT TEST FAILED: engine/test error found in output.", file=sys.stderr)
        return process.returncode if process.returncode > 0 else 1
    if process.returncode < 0:
        return 128 - process.returncode
    return process.returncode


if __name__ == "__main__":
    sys.exit(main())
