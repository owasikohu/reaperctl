#!/usr/bin/env python3
"""Execute synchronous Lua in REAPER through the local file bridge."""
import argparse
import json
import math
import os
from pathlib import Path
import sys
import time
import uuid


def execute(script, directory, timeout):
    request_id = uuid.uuid4().hex
    request = directory / f"request-{request_id}.lua"
    response = directory / f"response-{request_id}.json"
    temporary = directory / f"request-{request_id}.tmp"
    try:
        source = script.read_text(encoding="utf-8-sig")
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        deadline = time.monotonic() + timeout
        expires = math.ceil(time.time() + timeout)
        with temporary.open("x", encoding="utf-8", newline="\n") as stream:
            stream.write(f"-- expires: {expires}\n{source}")
        temporary.replace(request)
        while True:
            try:
                payload = json.loads(response.read_text(encoding="utf-8"))
            except FileNotFoundError:
                pass
            else:
                if (not isinstance(payload, dict) or payload.get("id") != request_id
                        or type(payload.get("ok")) is not bool
                        or ("result" if payload["ok"] else "error") not in payload):
                    raise ValueError("Invalid bridge response")
                response.unlink()
                return payload, 0 if payload["ok"] else 1
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return {"id": request_id, "ok": False, "error": "timeout",
                        "message": "No response before timeout; execution may have started. "
                                   "Inspect REAPER before retrying edits."}, 124
            time.sleep(min(0.05, remaining))
    except (OSError, ValueError) as exc:
        return {"id": request_id, "ok": False, "error": str(exc)}, 1
    finally:
        # Removing an unclaimed request cancels it. Never remove running work.
        for path in (temporary, request):
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass


def positive_seconds(value):
    value = float(value)
    if not math.isfinite(value) or value <= 0:
        raise argparse.ArgumentTypeError("timeout must be finite and positive")
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("exec", help="execute a UTF-8 Lua file")
    command.add_argument("script", type=Path)
    command.add_argument("--timeout", type=positive_seconds, default=10.0)
    command.add_argument("--ipc-dir", type=Path, default=Path(
        os.environ.get("REAPER_AGENT_DIR", str(Path(__file__).resolve().parent / ".reaper-agent"))))
    args = parser.parse_args()
    try:
        payload, status = execute(args.script, args.ipc_dir.resolve(), args.timeout)
    except KeyboardInterrupt:
        payload, status = {"ok": False, "error": "interrupted", "message":
                           "Execution may have started; inspect REAPER before retrying."}, 130
    print(json.dumps(payload, ensure_ascii=False, allow_nan=False))
    return status


if __name__ == "__main__":
    sys.exit(main())
