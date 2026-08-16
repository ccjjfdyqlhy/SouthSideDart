"""Wire protocol for the standalone core backend.

The current transport is intentionally simple: newline-delimited JSON over
stdin/stdout. Each request is ``{"id": ..., "method": ..., "params": {...}}``
and each response is ``{"id": ..., "result": ...}`` or
``{"id": ..., "error": {"code": ..., "message": ...}}``.
"""

from __future__ import annotations

import json
from typing import Any


def encode_response(request_id: Any, result: Any = None) -> str:
    return json.dumps({'id': request_id, 'result': result}, ensure_ascii=False)


def encode_error(
    request_id: Any,
    message: str,
    code: int = 1,
) -> str:
    return json.dumps(
        {'id': request_id, 'error': {'code': code, 'message': message}},
        ensure_ascii=False,
    )


def parse_request(line: str) -> dict[str, Any] | None:
    try:
        data = json.loads(line)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    return data
