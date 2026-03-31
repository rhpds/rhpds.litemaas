#!/usr/bin/env python3
"""
LiteMaaS MCP Server — Streamable HTTP transport (MCP 2025-03-26)

Claude Code connects via HTTP MCP transport. Runs on OpenShift in-cluster
with direct PostgreSQL and LiteLLM access.

Environment variables:
  LITELLM_API_URL   Internal LiteLLM URL (default: http://litellm:4000)
  LITELLM_API_KEY   LiteLLM admin key
  DATABASE_URL      PostgreSQL connection string
  MCP_API_KEY       Bearer token (empty = no auth)
  NAMESPACE         OCP namespace (default: litellm-rhpds)
"""

import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import anyio
import asyncpg
import httpx
from mcp.server import Server
from mcp.server.streamable_http import StreamableHTTPServerTransport
from mcp.types import TextContent, Tool
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.types import ASGIApp, Receive, Scope, Send

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)
log = logging.getLogger("litemaas-mcp")

# ── Config ────────────────────────────────────────────────────────────────────

LITELLM_URL  = os.environ.get("LITELLM_API_URL", "http://litellm:4000")
LITELLM_KEY  = os.environ.get("LITELLM_API_KEY", "")
DATABASE_URL = os.environ.get("DATABASE_URL", "")
MCP_API_KEY  = os.environ.get("MCP_API_KEY", "")
NAMESPACE    = os.environ.get("NAMESPACE", "litellm-rhpds")

# ── Database helpers ──────────────────────────────────────────────────────────

_pool: asyncpg.Pool | None = None

async def _db(query: str, *args) -> list[dict]:
    async with _pool.acquire() as conn:
        rows = await conn.fetch(query, *args)
        return [dict(r) for r in rows]

# ── LiteLLM API helper ────────────────────────────────────────────────────────

async def _llm(method: str, path: str, **kwargs):
    async with httpx.AsyncClient(timeout=30, verify=False) as c:
        resp = await getattr(c, method)(
            f"{LITELLM_URL}{path}",
            headers={"Authorization": f"Bearer {LITELLM_KEY}"},
            **kwargs,
        )
        resp.raise_for_status()
        return resp.json()

# ── Kubernetes helper ─────────────────────────────────────────────────────────

_k8s = None

async def _init_k8s():
    global _k8s
    try:
        from kubernetes_asyncio import client, config
        config.load_incluster_config()
        _k8s = client.CoreV1Api()
    except Exception as e:
        log.warning(f"k8s client unavailable: {e}")

# ── Tool implementations ──────────────────────────────────────────────────────

async def tool_list_models(_args):
    rows = await _db("""
        SELECT name, provider, availability, restricted_access,
               context_length, supports_function_calling,
               input_cost_per_token, output_cost_per_token, tpm, rpm
        FROM models ORDER BY provider, name
    """)
    for r in rows:
        if r.get("input_cost_per_token"):
            r["input_$/1M"]  = round(float(r.pop("input_cost_per_token"))  * 1_000_000, 4)
            r["output_$/1M"] = round(float(r.pop("output_cost_per_token")) * 1_000_000, 4)
        else:
            r.pop("input_cost_per_token", None)
            r.pop("output_cost_per_token", None)
    return json.dumps(rows, indent=2, default=str)


async def tool_get_model_health(args):
    model = args.get("model", "")
    data = await _llm("get", "/health", params={"model": model} if model else {})
    return json.dumps({
        "healthy":   len(data.get("healthy_endpoints", [])),
        "unhealthy": len(data.get("unhealthy_endpoints", [])),
        "healthy_endpoints":   data.get("healthy_endpoints", []),
        "unhealthy_endpoints": data.get("unhealthy_endpoints", []),
    }, indent=2)


async def tool_list_users(_args):
    data = await _llm("get", "/user/list")
    users = [
        {
            "user_id":         u.get("user_id"),
            "email":           u.get("user_email"),
            "spend":           round(u.get("spend", 0), 4),
            "max_budget":      u.get("max_budget"),
            "budget_duration": u.get("budget_duration"),
            "tpm_limit":       u.get("tpm_limit"),
            "rpm_limit":       u.get("rpm_limit"),
        }
        for u in (data.get("users", data) if isinstance(data, dict) else data)
    ]
    return json.dumps(sorted(users, key=lambda x: x["spend"] or 0, reverse=True), indent=2, default=str)


async def tool_get_spend_summary(args):
    conditions, params, i = ["spend > 0"], [], 1
    for field, col in [("date_from", '"startTime" >='), ("date_to", '"startTime" <=')]:
        if args.get(field):
            conditions.append(f"{col} ${i}")
            params.append(datetime.fromisoformat(args[field]))
            i += 1
    for field, col in [("model", "model ="), ("user_id", '"user" =')]:
        if args.get(field):
            conditions.append(f"{col} ${i}")
            params.append(args[field])
            i += 1
    rows = await _db(f"""
        SELECT model, COUNT(*) AS requests, SUM(total_tokens) AS total_tokens,
               CAST(SUM(spend) AS numeric(12,4)) AS total_spend,
               SUM(CASE WHEN status='failure' THEN 1 ELSE 0 END) AS failures
        FROM "LiteLLM_SpendLogs"
        WHERE {" AND ".join(conditions)}
        GROUP BY model ORDER BY total_spend DESC
    """, *params)
    return json.dumps(rows, indent=2, default=str)


async def tool_get_daily_stats(args):
    days = int(args.get("days", 7))
    rows = await _db(f"""
        SELECT DATE("startTime") AS date, COUNT(*) AS requests,
               SUM(total_tokens) AS total_tokens,
               CAST(SUM(spend) AS numeric(12,4)) AS total_spend,
               SUM(CASE WHEN status='failure' THEN 1 ELSE 0 END) AS failures
        FROM "LiteLLM_SpendLogs"
        WHERE "startTime" >= NOW() - INTERVAL '{days} days'
        GROUP BY DATE("startTime") ORDER BY date DESC
    """)
    return json.dumps(rows, indent=2, default=str)


async def tool_get_pod_status(_args):
    if not _k8s:
        return json.dumps({"error": "Kubernetes client not available"})
    pods = await _k8s.list_namespaced_pod(NAMESPACE)
    now = datetime.now(timezone.utc)
    return json.dumps([{
        "name":     p.metadata.name,
        "phase":    p.status.phase,
        "ready":    all(cs.ready for cs in p.status.container_statuses or []),
        "restarts": sum(cs.restart_count for cs in p.status.container_statuses or []),
        "age_h":    round((now - p.metadata.creation_timestamp).total_seconds() / 3600, 1),
    } for p in pods.items], indent=2)


async def tool_update_user_budget(args):
    data = await _llm("post", "/user/update", json={
        "user_id":         args["user_id"],
        "max_budget":      float(args["max_budget"]),
        "budget_duration": args.get("budget_duration", "daily"),
    })
    return json.dumps({"status": "ok", "response": data}, indent=2, default=str)


async def tool_list_virtual_keys(_args):
    rows = await _db("""
        SELECT key_alias, spend, max_budget, budget_duration,
               models, expires, created_at
        FROM "LiteLLM_VerificationToken"
        WHERE key_alias IS NOT NULL ORDER BY created_at DESC LIMIT 100
    """)
    return json.dumps(rows, indent=2, default=str)


HANDLERS = {
    "list_models":        tool_list_models,
    "get_model_health":   tool_get_model_health,
    "list_users":         tool_list_users,
    "get_spend_summary":  tool_get_spend_summary,
    "get_daily_stats":    tool_get_daily_stats,
    "get_pod_status":     tool_get_pod_status,
    "update_user_budget": tool_update_user_budget,
    "list_virtual_keys":  tool_list_virtual_keys,
}

TOOLS = [
    Tool(name="list_models",
         description="List all models in LiteMaaS — name, provider, availability, pricing ($/1M tokens), rate limits.",
         inputSchema={"type": "object", "properties": {}}),
    Tool(name="get_model_health",
         description="Check live health of a model. Leave model empty to check all.",
         inputSchema={"type": "object", "properties": {
             "model": {"type": "string", "description": "Model name (empty = all)"}}}),
    Tool(name="list_users",
         description="List all users with spend, budget, and rate limits. Sorted by spend descending.",
         inputSchema={"type": "object", "properties": {}}),
    Tool(name="get_spend_summary",
         description="Spend from LiteLLM logs grouped by model. Filter by date_from, date_to, model, user_id.",
         inputSchema={"type": "object", "properties": {
             "date_from": {"type": "string", "description": "ISO date YYYY-MM-DD"},
             "date_to":   {"type": "string", "description": "ISO date YYYY-MM-DD"},
             "model":     {"type": "string", "description": "Exact model name"},
             "user_id":   {"type": "string", "description": "LiteLLM user UUID"}}}),
    Tool(name="get_daily_stats",
         description="Daily token, request and spend totals for the past N days.",
         inputSchema={"type": "object", "properties": {
             "days": {"type": "integer", "description": "Number of days (default 7)"}}}),
    Tool(name="get_pod_status",
         description=f"Pod status in {NAMESPACE} — phase, readiness, restarts, age.",
         inputSchema={"type": "object", "properties": {}}),
    Tool(name="update_user_budget",
         description="Update a user's max_budget and budget_duration via LiteLLM API.",
         inputSchema={"type": "object", "required": ["user_id", "max_budget"], "properties": {
             "user_id":         {"type": "string", "description": "LiteLLM user UUID"},
             "max_budget":      {"type": "number", "description": "Budget in USD"},
             "budget_duration": {"type": "string", "description": "daily / weekly / monthly"}}}),
    Tool(name="list_virtual_keys",
         description="Virtual API keys with spend, budget, models and expiry (latest 100).",
         inputSchema={"type": "object", "properties": {}}),
]


def _make_server() -> Server:
    server = Server("litemaas-mcp")

    @server.list_tools()
    async def _():
        return TOOLS

    @server.call_tool()
    async def _(name: str, arguments: dict):
        handler = HANDLERS.get(name)
        if not handler:
            raise ValueError(f"Unknown tool: {name}")
        log.info(f"tool={name}")
        try:
            text = await handler(arguments or {})
        except Exception as e:
            log.error(f"tool={name} error={e}")
            text = json.dumps({"error": str(e)})
        return [TextContent(type="text", text=text)]

    return server


# ── ASGI application ──────────────────────────────────────────────────────────

class LiteMaaSMCPApp:
    """
    Bare ASGI app — no Starlette routing overhead.
    Routes:
      GET  /health  — liveness check
      *    /mcp     — MCP Streamable HTTP transport
      *    /sse     — alias for /mcp (legacy path)
    """

    def _auth_ok(self, headers: dict) -> bool:
        if not MCP_API_KEY:
            return True
        return headers.get(b"authorization", b"").decode() == f"Bearer {MCP_API_KEY}"

    async def _send_json(self, send: Send, status: int, body: dict, extra_headers: list | None = None):
        data = json.dumps(body).encode()
        headers = [(b"content-type", b"application/json"),
                   (b"content-length", str(len(data)).encode())]
        if extra_headers:
            headers.extend(extra_headers)
        await send({"type": "http.response.start", "status": status, "headers": headers})
        await send({"type": "http.response.body", "body": data})

    async def _health(self, scope: Scope, receive: Receive, send: Send):
        db_ok = llm_ok = False
        try:
            await _db("SELECT 1")
            db_ok = True
        except Exception:
            pass
        try:
            async with httpx.AsyncClient(timeout=5, verify=False) as c:
                r = await c.get(f"{LITELLM_URL}/health/livenessz",
                                headers={"Authorization": f"Bearer {LITELLM_KEY}"})
                llm_ok = r.status_code < 500
        except Exception:
            pass
        status = "healthy" if (db_ok and llm_ok) else "degraded"
        code = 200 if status == "healthy" else 503
        await self._send_json(send, code, {"status": status, "database": db_ok, "litellm": llm_ok})

    async def _mcp(self, scope: Scope, receive: Receive, send: Send):
        headers = dict(scope.get("headers", []))
        if not self._auth_ok(headers):
            await self._send_json(send, 401,
                {"error": "unauthorized", "message": "Valid Bearer token required"},
                extra_headers=[(b"www-authenticate", b'Bearer realm="LiteMaaS MCP"')])
            return

        server = _make_server()
        transport = StreamableHTTPServerTransport(mcp_session_id=None, is_json_response_enabled=False)
        async with transport.connect() as (read, write):
            async with anyio.create_task_group() as tg:
                tg.start_soon(server.run, read, write, server.create_initialization_options())
                await transport.handle_request(scope, receive, send)
                tg.cancel_scope.cancel()

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if scope["type"] == "lifespan":
            await self._lifespan(scope, receive, send)
            return
        if scope["type"] != "http":
            return

        path = scope.get("path", "")
        if path == "/health":
            await self._health(scope, receive, send)
        elif path in ("/mcp", "/sse"):
            await self._mcp(scope, receive, send)
        else:
            await self._send_json(send, 404, {"error": "not found"})

    async def _lifespan(self, scope: Scope, receive: Receive, send: Send):
        global _pool
        await receive()  # startup
        log.info("Starting LiteMaaS MCP Server")
        _pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=8)
        await _init_k8s()
        log.info("Ready — Streamable HTTP on /mcp (alias /sse)")
        await send({"type": "lifespan.startup.complete"})
        await receive()  # shutdown
        await _pool.close()
        await send({"type": "lifespan.shutdown.complete"})


app = LiteMaaSMCPApp()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("server:app", host="0.0.0.0", port=8080, log_level="info")
