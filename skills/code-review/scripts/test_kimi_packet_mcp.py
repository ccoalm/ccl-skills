#!/usr/bin/env python3
"""Regression tests for the single-packet Kimi MCP server."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SERVER = Path(__file__).with_name("kimi_packet_mcp.py")


class PacketMcpTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.packet = Path(self.temp.name) / "packet.txt"
        self.packet.write_text("alpha\nbeta\ngamma\n", encoding="utf-8")
        digest = hashlib.sha256(self.packet.read_bytes()).hexdigest()
        self.process = subprocess.Popen(
            [sys.executable, str(SERVER), "--packet", str(self.packet), "--sha256", digest],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    def tearDown(self) -> None:
        if self.process.poll() is None:
            self.process.terminate()
        self.process.communicate(timeout=5)
        self.temp.cleanup()

    def request(self, request_id: int, method: str, params: dict | None = None) -> dict:
        assert self.process.stdin is not None
        assert self.process.stdout is not None
        payload = {"jsonrpc": "2.0", "id": request_id, "method": method}
        if params is not None:
            payload["params"] = params
        self.process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self.process.stdin.flush()
        return json.loads(self.process.stdout.readline())

    def initialize(self) -> None:
        response = self.request(
            1,
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "test", "version": "1"},
            },
        )
        self.assertEqual(response["result"]["protocolVersion"], "2025-06-18")

    def test_server_contract(self) -> None:
        self.initialize()
        response = self.request(2, "tools/list", {})

        self.assertEqual([tool["name"] for tool in response["result"]["tools"]], ["read_packet"])
        schema = response["result"]["tools"][0]["inputSchema"]
        self.assertEqual(schema["required"], ["byte_offset", "max_bytes"])
        self.assertFalse(schema["additionalProperties"])
        self.assertNotIn("path", schema["properties"])

        response = self.request(
            3,
            "tools/call",
            {"name": "read_packet", "arguments": {"byte_offset": 6, "max_bytes": 11}},
        )
        self.assertFalse(response["result"]["isError"])
        self.assertEqual(
            response["result"]["content"],
            [{"type": "text", "text": "PACKET_CHUNK 6:17/17\nbeta\ngamma\n"}],
        )

    def test_rejects_path_arguments_and_packet_mutation(self) -> None:
        self.initialize()
        response = self.request(
            2,
            "tools/call",
            {
                "name": "read_packet",
                "arguments": {"path": "/etc/passwd", "byte_offset": 0, "max_bytes": 10},
            },
        )
        self.assertTrue(response["result"]["isError"])

        self.packet.write_text("changed\n", encoding="utf-8")
        response = self.request(
            3,
            "tools/call",
            {"name": "read_packet", "arguments": {"byte_offset": 0, "max_bytes": 10}},
        )
        self.assertTrue(response["result"]["isError"])
        self.assertEqual(response["result"]["content"][0]["text"], "packet binding changed")

    def test_exact_end_offset_returns_an_empty_bound_chunk(self) -> None:
        self.initialize()
        response = self.request(
            2,
            "tools/call",
            {
                "name": "read_packet",
                "arguments": {"byte_offset": len(self.packet.read_bytes()), "max_bytes": 10},
            },
        )

        self.assertFalse(response["result"]["isError"])
        self.assertEqual(
            response["result"]["content"],
            [{"type": "text", "text": "PACKET_CHUNK 17:17/17\n"}],
        )

    def test_reports_minimum_chunk_size_for_a_utf8_code_point(self) -> None:
        packet = Path(self.temp.name) / "unicode.txt"
        packet.write_text("你", encoding="utf-8")
        digest = hashlib.sha256(packet.read_bytes()).hexdigest()
        request = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {
                "name": "read_packet",
                "arguments": {"byte_offset": 0, "max_bytes": 1},
            },
        }

        completed = subprocess.run(
            [sys.executable, str(SERVER), "--packet", str(packet), "--sha256", digest],
            input=json.dumps(request) + "\n",
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )

        self.assertEqual(completed.returncode, 0)
        response = json.loads(completed.stdout)
        self.assertTrue(response["result"]["isError"])
        self.assertEqual(
            response["result"]["content"][0]["text"],
            "packet chunk cannot make progress; retry with max_bytes >= 3",
        )

    def test_chunks_a_physical_line_larger_than_one_bounded_result(self) -> None:
        packet = Path(self.temp.name) / "oversized-line.txt"
        packet.write_text("x" * 48_001 + "\n", encoding="utf-8")
        digest = hashlib.sha256(packet.read_bytes()).hexdigest()
        requests = [
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {
                    "name": "read_packet",
                    "arguments": {"byte_offset": 0, "max_bytes": 46_000},
                },
            },
            {
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {
                    "name": "read_packet",
                    "arguments": {"byte_offset": 46_000, "max_bytes": 46_000},
                },
            },
        ]

        completed = subprocess.run(
            [sys.executable, str(SERVER), "--packet", str(packet), "--sha256", digest],
            input="\n".join(json.dumps(item) for item in requests) + "\n",
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )

        self.assertEqual(completed.returncode, 0)
        responses = [json.loads(line) for line in completed.stdout.splitlines()]
        first = responses[0]["result"]["content"][0]["text"]
        second = responses[1]["result"]["content"][0]["text"]
        self.assertTrue(first.startswith("PACKET_CHUNK 0:46000/48002\n"))
        self.assertTrue(second.startswith("PACKET_CHUNK 46000:48002/48002\n"))
        self.assertLessEqual(len(first.encode("utf-8")), 48_000)
        self.assertLessEqual(len(second.encode("utf-8")), 48_000)


if __name__ == "__main__":
    unittest.main()
