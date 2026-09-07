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

        response = self.request(
            4,
            "tools/call",
            {
                "name": "search_packet",
                "arguments": {"query": "alpha", "byte_offset": 0, "limit": 1},
            },
        )
        self.assertTrue(response["result"]["isError"])
        self.assertEqual(response["result"]["content"][0]["text"], "unknown tool")

    def search_exchange(self, text: str, arguments: list[object]) -> list[dict]:
        packet = Path(self.temp.name) / "search.txt"
        packet.write_text(text, encoding="utf-8")
        digest = hashlib.sha256(packet.read_bytes()).hexdigest()
        requests = [{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}]
        requests.extend(
            {
                "jsonrpc": "2.0",
                "id": index,
                "method": "tools/call",
                "params": {"name": "search_packet", "arguments": item},
            }
            for index, item in enumerate(arguments, 2)
        )
        completed = subprocess.run(
            [sys.executable, str(SERVER), "--packet", str(packet), "--sha256", digest,
             "--allow-search"],
            input="\n".join(json.dumps(item) for item in requests) + "\n",
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return [json.loads(line)["result"] for line in completed.stdout.splitlines()]

    def test_search_opt_in_tool_surface(self) -> None:
        response = self.search_exchange("alpha", [])[0]
        self.assertEqual(
            [tool["name"] for tool in response["tools"]],
            ["read_packet", "search_packet"],
        )
        schema = response["tools"][1]["inputSchema"]
        self.assertEqual(schema["required"], ["query", "byte_offset", "limit"])
        self.assertEqual(set(schema["properties"]), {"query", "byte_offset", "limit"})
        self.assertFalse(schema["additionalProperties"])

    def test_search_literal_utf8_matches_use_byte_offsets_and_bounded_pagination(self) -> None:
        responses = self.search_exchange("é alpha\n你.* 你.*\nalpha\n", [
            {"query": "你.*", "byte_offset": 0, "limit": 1},
            {"query": "你.*", "byte_offset": 14, "limit": 1},
            {"query": ".*", "byte_offset": 0, "limit": 100},
            {"query": "missing", "byte_offset": 0, "limit": 1},
            {"query": "alpha", "byte_offset": 27, "limit": 1},
        ])
        expected = [
            {"matches": [{"byte_offset": 9, "line": 2}], "next_byte_offset": 14, "total_bytes": 27},
            {"matches": [{"byte_offset": 15, "line": 2}], "next_byte_offset": None, "total_bytes": 27},
            {"matches": [{"byte_offset": 12, "line": 2}, {"byte_offset": 18, "line": 2}], "next_byte_offset": None, "total_bytes": 27},
            {"matches": [], "next_byte_offset": None, "total_bytes": 27},
            {"matches": [], "next_byte_offset": None, "total_bytes": 27},
        ]
        for response, result in zip(responses[1:], expected, strict=True):
            self.assertFalse(response["isError"])
            self.assertEqual(json.loads(response["content"][0]["text"]), result)

    def test_search_rejects_invalid_arguments_and_offsets(self) -> None:
        valid = {"query": "a", "byte_offset": 0, "limit": 1}
        invalid = [None, [], {}, {**valid, "path": "/etc/passwd"},
                   {**valid, "query": ""}, {**valid, "query": 1},
                   {**valid, "query": "你" * 341 + "xy"}, {**valid, "query": "\ud800"},
                   {**valid, "byte_offset": -1}, {**valid, "byte_offset": True},
                   {**valid, "byte_offset": False},
                   {**valid, "byte_offset": 1.5}, {**valid, "limit": 0},
                   {**valid, "limit": 101}, {**valid, "limit": True},
                   {**valid, "limit": 1.5}, {**valid, "byte_offset": 1},
                   {**valid, "byte_offset": 4}]
        responses = self.search_exchange("你", invalid)
        self.assertEqual(len(responses), len(invalid) + 1)
        for arguments, response in zip(invalid, responses[1:], strict=True):
            with self.subTest(arguments=arguments):
                self.assertTrue(response["isError"])

    def test_search_is_case_sensitive_and_non_overlapping(self) -> None:
        responses = self.search_exchange("AaAAaaaa\n", [
            {"query": "aa", "byte_offset": 0, "limit": 100},
            {"query": "AA", "byte_offset": 0, "limit": 100},
        ])
        expected = [[{"byte_offset": 4, "line": 1}, {"byte_offset": 6, "line": 1}],
                    [{"byte_offset": 2, "line": 1}]]
        for response, matches in zip(responses[1:], expected, strict=True):
            self.assertFalse(response["isError"])
            self.assertEqual(json.loads(response["content"][0]["text"]), {
                "matches": matches, "next_byte_offset": None, "total_bytes": 9,
            })

    def test_search_accepts_the_maximum_query_byte_length(self) -> None:
        query = "你" * 341 + "x"
        response = self.search_exchange(query, [
            {"query": query, "byte_offset": 0, "limit": 1},
        ])[1]
        self.assertFalse(response["isError"])
        self.assertEqual(json.loads(response["content"][0]["text"]), {
            "matches": [{"byte_offset": 0, "line": 1}],
            "next_byte_offset": None,
            "total_bytes": 1024,
        })

    def test_search_limits_results_without_returning_an_oversized_line(self) -> None:
        responses = self.search_exchange("x" * 48_001 + "\n", [
            {"query": "x", "byte_offset": 0, "limit": 100},
            {"query": "x", "byte_offset": 100, "limit": 1},
        ])
        first = json.loads(responses[1]["content"][0]["text"])
        self.assertEqual(first, {
            "matches": [{"byte_offset": offset, "line": 1} for offset in range(100)],
            "next_byte_offset": 100,
            "total_bytes": 48_002,
        })
        second = json.loads(responses[2]["content"][0]["text"])
        self.assertEqual(second["matches"], [{"byte_offset": 100, "line": 1}])
        for response in responses[1:]:
            self.assertFalse(response["isError"])
            self.assertLessEqual(len(response["content"][0]["text"].encode("utf-8")), 48_000)

    def test_search_rechecks_exact_packet_binding_after_each_call(self) -> None:
        self.process.terminate()
        self.process.communicate(timeout=5)
        digest = hashlib.sha256(self.packet.read_bytes()).hexdigest()
        self.process = subprocess.Popen(
            [sys.executable, str(SERVER), "--packet", str(self.packet), "--sha256", digest,
             "--allow-search"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        self.initialize()
        params = {"name": "search_packet", "arguments": {"query": "alpha", "byte_offset": 0, "limit": 1}}
        self.assertFalse(self.request(2, "tools/call", params)["result"]["isError"])
        self.packet.write_text("ALPHA\nbeta\ngamma\n", encoding="utf-8")
        response = self.request(3, "tools/call", params)["result"]
        self.assertTrue(response["isError"])
        self.assertEqual(response["content"][0]["text"], "packet binding changed")

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
