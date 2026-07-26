#!/usr/bin/env python3
"""Start CodeGraphContext MCP against the database selected by the project wrapper."""

from __future__ import annotations

import asyncio
import os
from collections import OrderedDict
from dataclasses import replace
from pathlib import Path
from typing import Any

import codegraphcontext.server as server_module
from codegraphcontext.utils.tool_limits import get_tool_result_limit


_resolve_context = server_module.resolve_context
_VERBOSE_RESULT_FIELDS = {
    "call_args",
    "source",
    "docstring",
    "caller_docstring",
    "called_docstring",
    "file_is_dependency",
    "file_relative_path",
    "full_call_name",
    "imports",
    "relevance_score",
    "search_type",
    "target_file_path",
    "type",
}
_PATH_RESULT_FIELDS = (
    "path",
    "caller_file_path",
    "called_file_path",
    "target_file_path",
    "file_relative_path",
)


def _resolve_context_with_runtime_path(*args, **kwargs):
    context = _resolve_context(*args, **kwargs)
    runtime_db_path = os.environ.get("CGC_RUNTIME_DB_PATH")
    if not runtime_db_path:
        raise RuntimeError("CGC_RUNTIME_DB_PATH is required by the project MCP entrypoint")
    runtime_db_type = os.environ.get("CGC_RUNTIME_DB_TYPE") or context.database
    return replace(
        context,
        database=runtime_db_type,
        db_path=runtime_db_path,
    )


def _result_path(item: Any) -> str:
    if not isinstance(item, dict):
        return ""
    for key in _PATH_RESULT_FIELDS:
        value = item.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def _module_bucket(path: str) -> str:
    for part in Path(path).parts:
        if part in {"pastera", "pastera-agent", "pasteraTests", "pasteraAgentTests", "windows"}:
            return part
    return "_other"


def _project_relative_path(path: str) -> str:
    candidate = Path(path)
    if not candidate.is_absolute():
        return path
    try:
        return str(candidate.relative_to(Path.cwd()))
    except ValueError:
        return path


def _diverse_relationship_slice(items: list[Any], limit: int) -> list[Any]:
    if not items or not any(_result_path(item) for item in items):
        return items[:limit]

    selected = []
    for test_rows in (False, True):
        groups: OrderedDict[str, list[Any]] = OrderedDict()
        for item in items:
            path = _result_path(item)
            normalized_path = path.replace("\\", "/")
            is_test = (
                "/pasteraTests/" in normalized_path
                or "/pasteraAgentTests/" in normalized_path
                or normalized_path.startswith("pasteraTests/")
                or normalized_path.startswith("pasteraAgentTests/")
            )
            if is_test != test_rows:
                continue
            groups.setdefault(_module_bucket(path), []).append(item)

        while groups and len(selected) < limit:
            empty_groups = []
            for group_name, rows in groups.items():
                selected.append(rows.pop(0))
                if not rows:
                    empty_groups.append(group_name)
                if len(selected) >= limit:
                    break
            for group_name in empty_groups:
                groups.pop(group_name, None)

        if len(selected) >= limit:
            break
    return selected


def _compact_tree(
    value: Any,
    list_limit: int,
    *,
    diversify_relationships: bool = False,
) -> tuple[Any, bool]:
    if isinstance(value, dict):
        compacted = {}
        truncated = False
        for key, item in value.items():
            if key in _VERBOSE_RESULT_FIELDS:
                continue
            if (
                isinstance(item, str)
                and (key == "path" or key.endswith("_path"))
            ):
                item = _project_relative_path(item)
            if item is None:
                continue
            compacted_item, item_truncated = _compact_tree(
                item,
                list_limit,
                diversify_relationships=diversify_relationships,
            )
            compacted[key] = compacted_item
            truncated = truncated or item_truncated
        return compacted, truncated
    if isinstance(value, list):
        compacted_items = []
        truncated = len(value) > list_limit
        selected_items = (
            _diverse_relationship_slice(value, list_limit)
            if diversify_relationships
            else value[:list_limit]
        )
        for item in selected_items:
            compacted_item, item_truncated = _compact_tree(
                item,
                list_limit,
                diversify_relationships=diversify_relationships,
            )
            compacted_items.append(compacted_item)
            truncated = truncated or item_truncated
        return compacted_items, truncated
    return value, False


def _compact_find_code_result(result: dict[str, Any]) -> dict[str, Any]:
    if "error" in result:
        return result
    details = result.get("results") or {}
    ranked = details.get("ranked_results") or []
    limit = get_tool_result_limit("find_code") or 12
    compacted_ranked, nested_truncated = _compact_tree(ranked, limit)
    total_matches = details.get("total_matches", len(ranked))
    truncated = nested_truncated or total_matches > len(compacted_ranked)
    return {
        "success": result.get("success", True),
        "query": result.get("query"),
        "results": {
            "ranked_results": compacted_ranked,
            "total_matches": total_matches,
        },
        "result_limit": limit,
        "truncated": truncated,
        "source_omitted": True,
        "confirmation_hint": "Read the selected path and line range from the worktree.",
    }


def _compact_relationship_result(result: dict[str, Any]) -> dict[str, Any]:
    if "error" in result:
        return result
    details = result.get("results") or {}
    if isinstance(details, dict) and "error" in details:
        return {
            "error": details["error"],
            "query_type": result.get("query_type"),
            "target": result.get("target"),
        }
    limit = get_tool_result_limit("analyze_code_relationships") or 8
    payload = details.get("results", details) if isinstance(details, dict) else details
    compacted_payload, truncated = _compact_tree(
        payload,
        limit,
        diversify_relationships=True,
    )
    compacted = {
        "success": result.get("success", True),
        "query_type": result.get("query_type"),
        "target": result.get("target"),
        "results": compacted_payload,
        "summary": details.get("summary") if isinstance(details, dict) else None,
        "result_limit": limit,
    }
    compacted = {key: value for key, value in compacted.items() if value is not None}
    if truncated:
        compacted["truncated"] = True
    compacted["source_omitted"] = True
    compacted["confirmation_hint"] = (
        "Confirm candidate relationships with rg and targeted source reads."
    )
    return compacted


class ProjectMCPServer(server_module.MCPServer):
    """Apply project-only output compaction after upstream read-only queries."""

    async def handle_tool_call(self, tool_name: str, args: dict[str, Any]) -> dict[str, Any]:
        result = await super().handle_tool_call(tool_name, args)
        if tool_name == "find_code":
            return _compact_find_code_result(result)
        if tool_name == "analyze_code_relationships":
            return _compact_relationship_result(result)
        return result


def main() -> None:
    # CodeGraphContext 0.5.1's watch command honors CGC_RUNTIME_DB_PATH, while
    # MCPServer resolves the per-repo default path again. Keep both processes
    # on the same per-worktree FalkorDB without modifying the installed package.
    server_module.resolve_context = _resolve_context_with_runtime_path

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    server = None
    try:
        server = ProjectMCPServer(loop=loop, cwd=Path.cwd())
        backend = getattr(server.db_manager, "get_backend_type", lambda: "unknown")()
        if backend != "falkordb":
            raise RuntimeError(
                f"CodeGraphContext selected unexpected backend '{backend}'; "
                "refusing to serve queries from a fallback database"
            )
        loop.run_until_complete(server.run())
    finally:
        if server is not None:
            server.shutdown()
        loop.close()


if __name__ == "__main__":
    main()
