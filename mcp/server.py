#!/usr/bin/env python3
"""
LiteMaaS MCP Server

Runs on OpenShift. Provides MCP tools for querying and managing
LiteMaaS/LiteLLM via SSE transport over HTTP.

Environment variables:
  LITELLM_API_URL      Internal LiteLLM URL (default: http://litellm:4000)
  LITELLM_API_KEY      LiteLLM admin key
  LITEMAAS_ADMIN_KEY   LiteMaaS backend admin key
  DATABASE_URL         PostgreSQL connection string
  MCP_API_KEY          Key clients must send as Bearer token
  NAMESPACE            OCP namespace (default: litellm-rhpds)
"""

import asyncio
import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Any

import asyncpg
import httpx
from mcp.server import Server
from mcp.server.sse import SseServerTransport
from mcp.types import TextContent, Tool
from starlette.applications import Starlette
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response
from starlette.routing import Mount, Route

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)
log = logging.getLogger("litemaas-mcp")

# ── Config ────────────────────────────────────────────────────────────────────

LITELLM_URL  = os.environ.get("LITELLM_API_URL", "http://litellm:4000")
LITELLM_KEY  = os.environ.get("LITELLM_API_KEY", "")
ADMIN_KEY    = os.environ.get("LITEMAAS_ADMIN_KEY", "")
DATABASE_URL = os.environ.get("DATABASE_URL", "")
MCP_API_KEY  = os.environ.get("MCP_API_KEY", "")
NAMESPACE    = os.environ.get("NAMESPACE", "litellm-rhpds")

# ── Database helpers ──────────────────────────────────────────────────────────

_pool: asyncpg.Pool | None = None

async def get_pool() -> asyncpg.Pool:
    return _pool

async def _db(query: str, *args) -> list[dict]:
    async with _pool.acquire() as conn:
        rows = await conn.fetch(query, *args)
        return [dict(r) for r in rows]

# ── LiteLLM API helper ────────────────────────────────────────────────────────

async def _llm(method: str, path: str, **kwargs) -> Any:
    headers = {"Authorization": f"Bearer {LITELLM_KEY}"}
    async with httpx.AsyncClient(timeout=30, verify=False) as c:
        resp = await getattr(c, method)(
            f"{LITELLM_URL}{path}", headers=headers, **kwargs
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
        log.info("k8s in-cluster client ready")
    except Exception as e:
        log.warning(f"k8s client not available (running locally?): {e}")

# ── Tool implementations ──────────────────────────────────────────────────────

async def tool_list_models(_args: dict) -> str:
    rows = await _db("""
        SELECT name, provider, availability, restricted_access,
               context_length, supports_function_calling,
               input_cost_per_token, output_cost_per_token, tpm, rpm
        FROM models ORDER BY provider, name
    """)
    for r in rows:
        if r["input_cost_per_token"]:
            r["input_$/1M"]  = round(float(r.pop("input_cost_per_token"))  * 1_000_000, 4)
            r["output_$/1M"] = round(float(r.pop("output_cost_per_token")) * 1_000_000, 4)
        else:
            r.pop("input_cost_per_token", None)
            r.pop("output_cost_per_token", None)
    return json.dumps(rows, indent=2, default=str)


async def tool_get_model_health(args: dict) -> str:
    model = args.get("model", "")
    params = {"model": model} if model else {}
    data = await _llm("get", "/health", params=params)
    healthy   = data.get("healthy_endpoints", [])
    unhealthy = data.get("unhealthy_endpoints", [])
    result = {
        "healthy":   len(healthy),
        "unhealthy": len(unhealthy),
        "healthy_endpoints":   healthy,
        "unhealthy_endpoints": unhealthy,
    }
    return json.dumps(result, indent=2)


async def tool_list_users(_args: dict) -> str:
    data = await _llm("get", "/user/list")
    users = []
    for u in data.get("users", data if isinstance(data, list) else []):
        users.append({
            "user_id":        u.get("user_id"),
            "email":          u.get("user_email"),
            "spend":          round(u.get("spend", 0), 4),
            "max_budget":     u.get("max_budget"),
            "budget_duration":u.get("budget_duration"),
            "tpm_limit":      u.get("tpm_limit"),
            "rpm_limit":      u.get("rpm_limit"),
        })
    users.sort(key=lambda x: x["spend"] or 0, reverse=True)
    return json.dumps(users, indent=2, default=str)


async def tool_get_spend_summary(args: dict) -> str:
    conditions = ["spend > 0"]
    params: list = []
    i = 1

    if args.get("date_from"):
        conditions.append(f'"startTime" >= ${i}')
        params.append(datetime.fromisoformat(args["date_from"]))
        i += 1
    if args.get("date_to"):
        conditions.append(f'"startTime" <= ${i}')
        params.append(datetime.fromisoformat(args["date_to"]))
        i += 1
    if args.get("model"):
        conditions.append(f"model = ${i}")
        params.append(args["model"])
        i += 1
    if args.get("user_id"):
        conditions.append(f'"user" = ${i}')
        params.append(args["user_id"])
        i += 1

    where = "WHERE " + " AND ".join(conditions)
    rows = await _db(f"""
        SELECT model,
               COUNT(*) AS requests,
               SUM(total_tokens) AS total_tokens,
               SUM(prompt_tokens) AS prompt_tokens,
               SUM(completion_tokens) AS completion_tokens,
               CAST(SUM(spend) AS numeric(12,4)) AS total_spend,
               SUM(CASE WHEN status='failure' THEN 1 ELSE 0 END) AS failures
        FROM "LiteLLM_SpendLogs"
        {where}
        GROUP BY model
        ORDER BY total_spend DESC
    """, *params)
    return json.dumps(rows, indent=2, default=str)


async def tool_get_daily_stats(args: dict) -> str:
    days = int(args.get("days", 7))
    rows = await _db(f"""
        SELECT DATE("startTime") AS date,
               COUNT(*) AS requests,
               SUM(total_tokens) AS total_tokens,
               CAST(SUM(spend) AS numeric(12,4)) AS total_spend,
               SUM(CASE WHEN status='failure' THEN 1 ELSE 0 END) AS failures
        FROM "LiteLLM_SpendLogs"
        WHERE "startTime" >= NOW() - INTERVAL '{days} days'
        GROUP BY DATE("startTime")
        ORDER BY date DESC
    """)
    return json.dumps(rows, indent=2, default=str)


async def tool_get_pod_status(_args: dict) -> str:
    if _k8s is None:
        return json.dumps({"error": "Kubernetes client not available"})
    pods = await _k8s.list_namespaced_pod(NAMESPACE)
    result = []
    now = datetime.now(timezone.utc)
    for p in pods.items:
        restarts = 0
        ready = False
        if p.status.container_statuses:
            restarts = sum(cs.restart_count for cs in p.status.container_statuses)
            ready    = all(cs.ready for cs in p.status.container_statuses)
        age_h = round((now - p.metadata.creation_timestamp).total_seconds() / 3600, 1)
        result.append({
            "name":     p.metadata.name,
            "phase":    p.status.phase,
            "ready":    ready,
            "restarts": restarts,
            "age_h":    age_h,
        })
    return json.dumps(result, indent=2)


async def tool_update_user_budget(args: dict) -> str:
    payload = {
        "user_id":         args["user_id"],
        "max_budget":      float(args["max_budget"]),
        "budget_duration": args.get("budget_duration", "daily"),
    }
    data = await _llm("post", "/user/update", json=payload)
    return json.dumps({"status": "ok", "response": data}, indent=2, default=str)


async def tool_list_virtual_keys(_args: dict) -> str:
    rows = await _db("""
        SELECT key_alias,
               spend,
               max_budget,
               budget_duration,
               models,
               expires,
               created_at
        FROM "LiteLLM_VerificationToken"
        WHERE key_alias IS NOT NULL
        ORDER BY created_at DESC
        LIMIT 100
    """)
    return json.dumps(rows, indent=2, default=str)


# ── MCP server setup ──────────────────────────────────────────────────────────

mcp = Server("litemaas-mcp")

TOOLS = [
    Tool(
        name="list_models",
        description=(
            "List all models in LiteMaaS — name, provider, availability, "
            "pricing ($/1M tokens), rate limits, and restricted_access flag."
        ),
        inputSchema={"type": "object", "properties": {}},
    ),
    Tool(
        name="get_model_health",
        description=(
            "Check live health of a model via LiteLLM. Returns healthy and "
            "unhealthy backend endpoints. Leave model empty to check all."
        ),
        inputSchema={
            "type": "object",
            "properties": {
                "model": {"type": "string", "description": "Model name (empty = all models)"},
            },
        },
    ),
    Tool(
        name="list_users",
        description=(
            "List all LiteMaaS users with their spend, budget, and rate limits. "
            "Sorted by spend descending."
        ),
        inputSchema={"type": "object", "properties": {}},
    ),
    Tool(
        name="get_spend_summary",
        description=(
            "Summarise spend from LiteLLM logs, grouped by model. "
            "Optionally filter by date range, model name, or user_id."
        ),
        inputSchema={
            "type": "object",
            "properties": {
                "date_from": {"type": "string", "description": "ISO date YYYY-MM-DD"},
                "date_to":   {"type": "string", "description": "ISO date YYYY-MM-DD"},
                "model":     {"type": "string", "description": "Exact model name"},
                "user_id":   {"type": "string", "description": "LiteLLM user UUID"},
            },
        },
    ),
    Tool(
        name="get_daily_stats",
        description="Daily token, request and spend totals for the past N days.",
        inputSchema={
            "type": "object",
            "properties": {
                "days": {"type": "integer", "description": "Number of days (default 7)"},
            },
        },
    ),
    Tool(
        name="get_pod_status",
        description=f"List all pods in the {NAMESPACE} namespace with phase, readiness, restarts and age.",
        inputSchema={"type": "object", "properties": {}},
    ),
    Tool(
        name="update_user_budget",
        description="Update a user's max_budget and budget_duration via LiteLLM API.",
        inputSchema={
            "type": "object",
            "required": ["user_id", "max_budget"],
            "properties": {
                "user_id":         {"type": "string",  "description": "LiteLLM user UUID"},
                "max_budget":      {"type": "number",  "description": "Budget in USD"},
                "budget_duration": {"type": "string",  "description": "daily / weekly / monthly"},
            },
        },
    ),
    Tool(
        name="list_virtual_keys",
        description="List virtual API keys with spend, budget, models and expiry (latest 100).",
        inputSchema={"type": "object", "properties": {}},
    ),
]

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


@mcp.list_tools()
async def list_tools():
    return TOOLS


@mcp.call_tool()
async def call_tool(name: str, arguments: dict):
    handler = HANDLERS.get(name)
    if not handler:
        raise ValueError(f"Unknown tool: {name}")
    log.info(f"tool={name} args={arguments}")
    try:
        text = await handler(arguments or {})
    except Exception as e:
        log.error(f"tool={name} error={e}")
        text = json.dumps({"error": str(e)})
    return [TextContent(type="text", text=text)]


# ── Auth middleware ───────────────────────────────────────────────────────────

class AuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/health":
            return await call_next(request)
        if MCP_API_KEY:
            auth = request.headers.get("Authorization", "")
            if not auth.startswith("Bearer ") or auth[7:] != MCP_API_KEY:
                return Response("Unauthorized", status_code=401)
        return await call_next(request)


# ── Starlette app ─────────────────────────────────────────────────────────────

sse = SseServerTransport("/messages")


async def handle_sse(request: Request):
    async with sse.connect_sse(
        request.scope, request.receive, request._send
    ) as (read, write):
        await mcp.run(read, write, mcp.create_initialization_options())


async def health(request: Request):
    db_ok  = False
    llm_ok = False
    try:
        await _db("SELECT 1")
        db_ok = True
    except Exception:
        pass
    try:
        async with httpx.AsyncClient(timeout=5, verify=False) as c:
            r = await c.get(
                f"{LITELLM_URL}/health/livenessz",
                headers={"Authorization": f"Bearer {LITELLM_KEY}"},
            )
            llm_ok = r.status_code < 500
    except Exception:
        pass
    status = "healthy" if (db_ok and llm_ok) else "degraded"
    code   = 200 if status == "healthy" else 503
    return JSONResponse(
        {"status": status, "database": db_ok, "litellm": llm_ok}, status_code=code
    )


@asynccontextmanager
async def lifespan(app):
    global _pool
    log.info("Starting LiteMaaS MCP Server")
    _pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=8)
    await _init_k8s()
    log.info("Ready")
    yield
    await _pool.close()
    log.info("Stopped")


app = Starlette(
    lifespan=lifespan,
    routes=[
        Route("/health",   health),
        Route("/sse",      handle_sse),
        Mount("/messages", app=sse.handle_post_message),
    ],
)
app.add_middleware(AuthMiddleware)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")
