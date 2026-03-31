#!/usr/bin/env python3
"""
LiteMaaS MCP Server — Streamable HTTP transport (MCP 2025-03-26)

Uses StreamableHTTPSessionManager for proper session state management.
Claude Code connects via HTTP MCP transport.

Environment variables:
  LITELLM_API_URL   Internal LiteLLM URL (default: http://litellm:4000)
  LITELLM_API_KEY   LiteLLM admin key
  DATABASE_URL      PostgreSQL connection string
  NAMESPACE         OCP namespace (default: litellm-rhpds)
"""

import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import asyncpg
import httpx
from mcp.server import Server
from mcp.server.streamable_http_manager import StreamableHTTPSessionManager
from mcp.types import TextContent, Tool
from starlette.requests import Request
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

# ── Database ──────────────────────────────────────────────────────────────────

_pool: asyncpg.Pool | None = None

async def _db(query: str, *args) -> list[dict]:
    async with _pool.acquire() as conn:
        return [dict(r) for r in await conn.fetch(query, *args)]


def _check_auth(scope) -> bool:
    """Auth via query param ?token=MCP_API_KEY (works with all MCP HTTP clients)."""
    if not MCP_API_KEY:
        return True
    qs = scope.get("query_string", b"").decode()
    for part in qs.split("&"):
        if part.startswith("token="):
            return part[6:] == MCP_API_KEY
    # Also accept Authorization: Bearer header as fallback
    headers = dict(scope.get("headers", []))
    auth = headers.get(b"authorization", b"").decode()
    return auth == f"Bearer {MCP_API_KEY}"

# ── LiteLLM API ───────────────────────────────────────────────────────────────

async def _llm(method: str, path: str, **kwargs):
    async with httpx.AsyncClient(timeout=30, verify=False) as c:
        resp = await getattr(c, method)(
            f"{LITELLM_URL}{path}",
            headers={"Authorization": f"Bearer {LITELLM_KEY}"},
            **kwargs,
        )
        resp.raise_for_status()
        return resp.json()

# ── Kubernetes ────────────────────────────────────────────────────────────────

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
        SELECT model_name,
               model_info->>'mode'              AS mode,
               litellm_params->>'model'         AS backend,
               litellm_params->>'custom_llm_provider' AS provider,
               CAST(model_info->>'input_cost_per_token'  AS double precision) AS input_cost,
               CAST(model_info->>'output_cost_per_token' AS double precision) AS output_cost,
               CAST(model_info->>'max_tokens' AS integer) AS max_tokens,
               model_info->>'supports_function_calling' AS function_calling
        FROM "LiteLLM_ProxyModelTable"
        ORDER BY model_name
    """)
    result = []
    for r in rows:
        m = {
            "model":    r["model_name"],
            "mode":     r["mode"],
            "backend":  r["backend"],
            "provider": r["provider"],
        }
        if r.get("input_cost") is not None:
            m["input_$/1M"]  = round(float(r["input_cost"])  * 1_000_000, 4)
            m["output_$/1M"] = round(float(r["output_cost"]) * 1_000_000, 4)
        if r.get("max_tokens"):
            m["max_tokens"] = r["max_tokens"]
        if r.get("function_calling"):
            m["function_calling"] = r["function_calling"] == "true"
        result.append(m)
    return json.dumps(result, indent=2, default=str)


async def tool_get_model_health(args):
    model = args.get("model", "")
    data = await _llm("get", "/health", params={"model": model} if model else {})
    return json.dumps({
        "healthy":             len(data.get("healthy_endpoints", [])),
        "unhealthy":           len(data.get("unhealthy_endpoints", [])),
        "healthy_endpoints":   data.get("healthy_endpoints", []),
        "unhealthy_endpoints": data.get("unhealthy_endpoints", []),
    }, indent=2)


async def tool_list_users(_args):
    rows = await _db("""
        SELECT user_id, user_email, spend, max_budget,
               budget_duration, tpm_limit, rpm_limit, created_at
        FROM "LiteLLM_UserTable"
        WHERE user_id != 'default_user'
        ORDER BY spend DESC NULLS LAST
        LIMIT 200
    """)
    users = [
        {
            "user_id":         r["user_id"],
            "email":           r["user_email"],
            "spend":           round(float(r["spend"] or 0), 4),
            "max_budget":      float(r["max_budget"]) if r["max_budget"] else None,
            "budget_duration": r["budget_duration"],
            "tpm_limit":       r["tpm_limit"],
            "rpm_limit":       r["rpm_limit"],
        }
        for r in rows
    ]
    return json.dumps(users, indent=2, default=str)


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
         description="Check live health of a model via LiteLLM. Leave model empty to check all.",
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


def _build_mcp_server() -> Server:
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


# ── App ───────────────────────────────────────────────────────────────────────

mcp_server = _build_mcp_server()
session_manager = StreamableHTTPSessionManager(app=mcp_server, json_response=False)


async def _send_json(send: Send, status: int, body: dict):
    data = json.dumps(body).encode()
    await send({"type": "http.response.start", "status": status,
                "headers": [(b"content-type", b"application/json"),
                            (b"content-length", str(len(data)).encode())]})
    await send({"type": "http.response.body", "body": data})


class LiteMaaSApp:
    """Bare ASGI app — routes /health and /mcp without Starlette path munging."""

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
        await _send_json(send, 200 if status == "healthy" else 503,
                         {"status": status, "database": db_ok, "litellm": llm_ok})

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
            if not _check_auth(scope):
                await _send_json(send, 401,
                    {"error": "unauthorized", "message": "Valid ?token= required"})
            else:
                await session_manager.handle_request(scope, receive, send)
        else:
            await _send_json(send, 404, {"error": "not found"})

    async def _lifespan(self, scope: Scope, receive: Receive, send: Send):
        global _pool
        await receive()  # startup event
        log.info("Starting LiteMaaS MCP Server")
        _pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=8)
        await _init_k8s()
        async with session_manager.run():
            log.info("Ready — StreamableHTTP session manager on /mcp")
            await send({"type": "lifespan.startup.complete"})
            await receive()  # shutdown event
        await _pool.close()
        await send({"type": "lifespan.shutdown.complete"})


app = LiteMaaSApp()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("server:app", host="0.0.0.0", port=8080, log_level="info")
