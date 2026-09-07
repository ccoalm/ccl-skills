#!/usr/bin/env python3
"""Expose one SHA-256-bound review packet through pathless stdio MCP tools."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any


TOOL_NAME = "read_packet"
SEARCH_TOOL_NAME = "search_packet"
MAX_PAGE_BYTES = 48_000
MAX_CHUNK_BYTES = 46_000
MAX_QUERY_BYTES = 1_024
MAX_SEARCH_RESULTS = 100


def packet_bytes(path: Path, expected_sha256: str) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise ValueError("packet binding changed")
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected_sha256:
        raise ValueError("packet binding changed")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError("packet is not UTF-8") from exc
    return data


def tool_definition() -> dict[str, Any]:
    return {
        "name": TOOL_NAME,
        "description": (
            "Read UTF-8 chunks from the one controller-frozen review packet. "
            "Continue at the byte offset after the returned PACKET_CHUNK header "
            "until its end equals the declared total."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "byte_offset": {"type": "integer", "minimum": 0},
                "max_bytes": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": MAX_CHUNK_BYTES,
                },
            },
            "required": ["byte_offset", "max_bytes"],
            "additionalProperties": False,
        },
    }


def tool_result(text: str, *, error: bool = False) -> dict[str, Any]:
    return {"content": [{"type": "text", "text": text}], "isError": error}


def search_tool_definition() -> dict[str, Any]:
    return {
        "name": SEARCH_TOOL_NAME,
        "description": (
            "Find non-overlapping, case-sensitive literal substrings in the one "
            "controller-frozen review packet. No regex or filesystem paths. "
            "Query is at most 1024 UTF-8 bytes; byte_offset must be a UTF-8 "
            "boundary. Returns byte offsets and 1-based line numbers, with "
            "next_byte_offset for more matches or null when exhausted. "
            "Use read_packet at a match offset to inspect its context."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "minLength": 1, "maxLength": MAX_QUERY_BYTES},
                "byte_offset": {"type": "integer", "minimum": 0},
                "limit": {"type": "integer", "minimum": 1, "maximum": MAX_SEARCH_RESULTS},
            },
            "required": ["query", "byte_offset", "limit"],
            "additionalProperties": False,
        },
    }


def search_packet(path: Path, expected_sha256: str, arguments: Any) -> dict[str, Any]:
    if not isinstance(arguments, dict) or set(arguments) != {"query", "byte_offset", "limit"}:
        return tool_result("invalid packet search arguments", error=True)
    query = arguments.get("query")
    byte_offset = arguments.get("byte_offset")
    limit = arguments.get("limit")
    if (
        not isinstance(query, str)
        or not isinstance(byte_offset, int)
        or isinstance(byte_offset, bool)
        or byte_offset < 0
        or not isinstance(limit, int)
        or isinstance(limit, bool)
        or not 1 <= limit <= MAX_SEARCH_RESULTS
    ):
        return tool_result("invalid packet search arguments", error=True)
    try:
        needle = query.encode("utf-8")
    except UnicodeEncodeError:
        return tool_result("invalid packet search arguments", error=True)
    if not 1 <= len(needle) <= MAX_QUERY_BYTES:
        return tool_result("invalid packet search arguments", error=True)
    try:
        data = packet_bytes(path, expected_sha256)
    except (OSError, ValueError):
        return tool_result("packet binding changed", error=True)
    if byte_offset > len(data):
        return tool_result("packet search starts beyond end", error=True)
    try:
        data[:byte_offset].decode("utf-8")
    except UnicodeDecodeError:
        return tool_result("packet search starts inside a UTF-8 character", error=True)

    matches = []
    cursor = byte_offset
    while len(matches) < limit:
        found = data.find(needle, cursor)
        if found < 0:
            break
        matches.append({"byte_offset": found, "line": data.count(b"\n", 0, found) + 1})
        cursor = found + len(needle)
    rendered = json.dumps(
        {
            "matches": matches,
            "next_byte_offset": cursor if data.find(needle, cursor) >= 0 else None,
            "total_bytes": len(data),
        },
        separators=(",", ":"),
    )
    if len(rendered.encode("utf-8")) > MAX_PAGE_BYTES:
        return tool_result("packet search exceeds result bound", error=True)
    return tool_result(rendered)


def read_chunk(path: Path, expected_sha256: str, arguments: Any) -> dict[str, Any]:
    if not isinstance(arguments, dict) or set(arguments) != {"byte_offset", "max_bytes"}:
        return tool_result("invalid packet chunk arguments", error=True)
    byte_offset = arguments.get("byte_offset")
    max_bytes = arguments.get("max_bytes")
    if (
        not isinstance(byte_offset, int)
        or isinstance(byte_offset, bool)
        or byte_offset < 0
        or not isinstance(max_bytes, int)
        or isinstance(max_bytes, bool)
        or not 1 <= max_bytes <= MAX_CHUNK_BYTES
    ):
        return tool_result("invalid packet chunk arguments", error=True)
    try:
        data = packet_bytes(path, expected_sha256)
    except (OSError, ValueError):
        return tool_result("packet binding changed", error=True)
    if byte_offset > len(data):
        return tool_result("packet chunk starts beyond end", error=True)
    try:
        data[:byte_offset].decode("utf-8")
    except UnicodeDecodeError:
        return tool_result("packet chunk starts inside a UTF-8 character", error=True)

    end = min(byte_offset + max_bytes, len(data))
    while end > byte_offset:
        try:
            chunk = data[byte_offset:end].decode("utf-8")
            break
        except UnicodeDecodeError:
            end -= 1
    else:
        if byte_offset != len(data):
            minimum = 1
            while byte_offset + minimum <= len(data):
                try:
                    data[byte_offset : byte_offset + minimum].decode("utf-8")
                    break
                except UnicodeDecodeError:
                    minimum += 1
            return tool_result(
                f"packet chunk cannot make progress; retry with max_bytes >= {minimum}",
                error=True,
            )
        chunk = ""
    header = f"PACKET_CHUNK {byte_offset}:{end}/{len(data)}\n"
    rendered = header + chunk
    if len(rendered.encode("utf-8")) > MAX_PAGE_BYTES:
        return tool_result("packet chunk exceeds result bound", error=True)
    return tool_result(rendered)


def response(request_id: Any, *, result: Any = None, error: Any = None) -> dict[str, Any]:
    payload: dict[str, Any] = {"jsonrpc": "2.0", "id": request_id}
    if error is not None:
        payload["error"] = error
    else:
        payload["result"] = result
    return payload


def handle(
    message: Any, path: Path, expected_sha256: str, *, allow_search: bool = False
) -> dict[str, Any] | None:
    if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
        return response(None, error={"code": -32600, "message": "Invalid Request"})
    request_id = message.get("id")
    method = message.get("method")
    if request_id is None:
        return None
    if method == "initialize":
        params = message.get("params") if isinstance(message.get("params"), dict) else {}
        protocol = params.get("protocolVersion", "2024-11-05")
        return response(
            request_id,
            result={
                "protocolVersion": protocol,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "ccl-review-packet", "version": "1"},
            },
        )
    if method == "ping":
        return response(request_id, result={})
    if method == "tools/list":
        definitions = [tool_definition()]
        if allow_search:
            definitions.append(search_tool_definition())
        return response(request_id, result={"tools": definitions})
    if method == "tools/call":
        params = message.get("params")
        if isinstance(params, dict) and allow_search and params.get("name") == SEARCH_TOOL_NAME:
            return response(
                request_id,
                result=search_packet(path, expected_sha256, params.get("arguments")),
            )
        if not isinstance(params, dict) or params.get("name") != TOOL_NAME:
            return response(request_id, result=tool_result("unknown tool", error=True))
        return response(
            request_id,
            result=read_chunk(path, expected_sha256, params.get("arguments")),
        )
    return response(request_id, error={"code": -32601, "message": "Method not found"})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packet", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument(
        "--allow-search", action="store_true", help="also expose bounded literal packet search"
    )
    args = parser.parse_args()
    if not len(args.sha256) == 64 or any(ch not in "0123456789abcdef" for ch in args.sha256):
        parser.error("--sha256 must be a lowercase SHA-256 digest")
    path = Path(args.packet)
    try:
        packet_bytes(path, args.sha256)
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2

    for raw_line in sys.stdin:
        try:
            message = json.loads(raw_line)
            payload = handle(message, path, args.sha256, allow_search=args.allow_search)
        except (json.JSONDecodeError, UnicodeError):
            payload = response(None, error={"code": -32700, "message": "Parse error"})
        if payload is not None:
            print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
