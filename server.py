#!/usr/bin/env python3
"""
Polymarket v2 MCP Server - FastMCP with D402 Transport Wrapper

Uses FastMCP from official MCP SDK with D402MCPTransport wrapper for HTTP 402.

Architecture:
- FastMCP for tool decorators and Context objects
- D402MCPTransport wraps the /mcp route for HTTP 402 interception
- Proper HTTP 402 status codes (not JSON-RPC wrapped)

Generated from OpenAPI: 

Environment Variables:
- POLYMARKET_V2_API_KEY: Server's internal API key (for paid requests)
- SERVER_ADDRESS: Payment address (IATP wallet contract)
- MCP_OPERATOR_PRIVATE_KEY: Operator signing key
- D402_TESTING_MODE: Skip facilitator (default: true)
"""

import os
import logging
import sys
from typing import Any, Callable, Dict, List, Optional, Sequence, Set, Tuple, Union
from datetime import datetime

import requests
from retry import retry
from dotenv import load_dotenv
import uvicorn

load_dotenv()

# Configure logging
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('polymarket-v2_mcp')

# FastMCP from official SDK
from mcp.server.fastmcp import FastMCP, Context
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.middleware.cors import CORSMiddleware

# D402 payment protocol - using Starlette middleware
from traia_iatp.d402.starlette_middleware import D402PaymentMiddleware
from traia_iatp.d402.mcp_middleware import require_payment_for_tool, get_active_api_key
from traia_iatp.d402.payment_introspection import extract_payment_configs_from_mcp
from traia_iatp.d402.types import TokenAmount, TokenAsset, EIP712Domain

# Configuration
STAGE = os.getenv("STAGE", "MAINNET").upper()
PORT = int(os.getenv("PORT", "8000"))
SERVER_ADDRESS = os.getenv("SERVER_ADDRESS")
if not SERVER_ADDRESS:
    raise ValueError("SERVER_ADDRESS required for payment protocol")

API_KEY = os.getenv("POLYMARKET_V2_API_KEY")
if not API_KEY:
    logger.warning(f"⚠️  POLYMARKET_V2_API_KEY not set - payment required for all requests")

logger.info("="*80)
logger.info(f"Polymarket v2 MCP Server (FastMCP + D402 Wrapper)")
logger.info(f"API: https://pma.d402.net")
logger.info(f"Payment: {SERVER_ADDRESS}")
logger.info(f"API Key: {'✅' if API_KEY else '❌ Payment required'}")
logger.info("="*80)

# Create FastMCP server
mcp = FastMCP("Polymarket v2 MCP Server", host="0.0.0.0")

logger.info(f"✅ FastMCP server created")

# ============================================================================
# TOOL IMPLEMENTATIONS
# ============================================================================
# Tool implementations will be added here by endpoint_implementer_crew
# Each tool will use the @mcp.tool() and @require_payment_for_tool() decorators


# D402 Payment Middleware
# The HTTP 402 payment protocol middleware is already configured in the server initialization.
# It's imported from traia_iatp.d402.mcp_middleware and auto-detects configuration from:
# - PAYMENT_ADDRESS or EVM_ADDRESS: Where to receive payments
# - EVM_NETWORK: Blockchain network (default: base-sepolia)
# - DEFAULT_PRICE_USD: Price per request (default: $0.001)
# - POLYMARKET_V2_API_KEY: Server's internal API key for payment mode
#
# All payment verification logic is handled by the traia_iatp.d402 module.
# No custom implementation needed!


# API Endpoint Tool Implementations

@mcp.tool()
@require_payment_for_tool(
    price=TokenAmount(
        amount="10000",  # 0.01 tokens
        asset=TokenAsset(
            address="0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
            decimals=6,
            network="sepolia",
            eip712=EIP712Domain(
                name="IATPWallet",
                version="1"
            )
        )
    ),
    description=""

)
async def health_check(
    context: Context
) -> Any:
    """
    GET /health

    Generated from OpenAPI endpoint: GET /health

    Args:
        context: MCP context (auto-injected by framework, not user-provided)


    Returns:
        API response (dict, list, or other JSON type)

    Example Usage:
        await health_check()

        Note: 'context' parameter is auto-injected by MCP framework
    """
    # Payment already verified by @require_payment_for_tool decorator
    # Get API key using helper (handles request.state fallback)
    api_key = get_active_api_key(context)

    try:
        url = f"https://pma.d402.net/health"
        params = {}
        headers = {}
        if api_key:
            headers["X-API-Key"] = api_key
            # Also send Bearer for robustness (most APIs use Bearer)
            headers["Authorization"] = f"Bearer {api_key}"

        response = requests.get(
            url,
            params=params,
            headers=headers,
            timeout=30
        )
        response.raise_for_status()

        return response.json()

    except Exception as e:
        logger.error(f"Error in health_check: {e}")
        return {"error": str(e), "endpoint": "/health"}


@mcp.tool()
@require_payment_for_tool(
    price=TokenAmount(
        amount="10000",  # 0.01 tokens
        asset=TokenAsset(
            address="0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
            decimals=6,
            network="sepolia",
            eip712=EIP712Domain(
                name="IATPWallet",
                version="1"
            )
        )
    ),
    description=""

)
async def api_status(
    context: Context
) -> Any:
    """
    GET /api/status

    Generated from OpenAPI endpoint: GET /api/status

    Args:
        context: MCP context (auto-injected by framework, not user-provided)


    Returns:
        API response (dict, list, or other JSON type)

    Example Usage:
        await api_status()

        Note: 'context' parameter is auto-injected by MCP framework
    """
    # Payment already verified by @require_payment_for_tool decorator
    # Get API key using helper (handles request.state fallback)
    api_key = get_active_api_key(context)

    try:
        url = f"https://pma.d402.net/api/status"
        params = {}
        headers = {}
        if api_key:
            headers["X-API-Key"] = api_key
            # Also send Bearer for robustness (most APIs use Bearer)
            headers["Authorization"] = f"Bearer {api_key}"

        response = requests.get(
            url,
            params=params,
            headers=headers,
            timeout=30
        )
        response.raise_for_status()

        return response.json()

    except Exception as e:
        logger.error(f"Error in api_status: {e}")
        return {"error": str(e), "endpoint": "/api/status"}


@mcp.tool()
@require_payment_for_tool(
    price=TokenAmount(
        amount="50000",  # 0.05 tokens
        asset=TokenAsset(
            address="0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
            decimals=6,
            network="sepolia",
            eip712=EIP712Domain(
                name="IATPWallet",
                version="1"
            )
        )
    ),
    description="Returns the latest 15m tick (with history context)"

)
async def get_latest_sentiment_tick_or_rollup(
    context: Context,
    asset: Optional[str] = None,
    period: str = "15m"
) -> Any:
    """
    Returns the latest 15m tick (with history context) or a computed rollup for the requested period.

    Generated from OpenAPI endpoint: GET /api/v1/sentiment/latest

    Args:
        context: MCP context (auto-injected by framework, not user-provided)
        asset: Crypto asset (optional)
        period: Time period. 15m returns raw ticks; 1h, 4h, 1d return computed rollups. (optional, default: "15m")

    Returns:
        API response (dict, list, or other JSON type)

    Example Usage:
        await get_latest_sentiment_tick_or_rollup(asset="BTC", period="15m")

        Note: 'context' parameter is auto-injected by MCP framework
    """
    # Payment already verified by @require_payment_for_tool decorator
    # Get API key using helper (handles request.state fallback)
    api_key = get_active_api_key(context)

    try:
        url = f"https://pma.d402.net/api/v1/sentiment/latest"
        params = {
            "asset": asset,
            "period": period
        }
        params = {k: v for k, v in params.items() if v is not None}
        headers = {}
        if api_key:
            headers["X-API-Key"] = api_key
            # Also send Bearer for robustness (most APIs use Bearer)
            headers["Authorization"] = f"Bearer {api_key}"

        response = requests.get(
            url,
            params=params,
            headers=headers,
            timeout=30
        )
        response.raise_for_status()

        return response.json()

    except Exception as e:
        logger.error(f"Error in get_latest_sentiment_tick_or_rollup: {e}")
        return {"error": str(e), "endpoint": "/api/v1/sentiment/latest"}


@mcp.tool()
@require_payment_for_tool(
    price=TokenAmount(
        amount="50000",  # 0.05 tokens
        asset=TokenAsset(
            address="0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
            decimals=6,
            network="sepolia",
            eip712=EIP712Domain(
                name="IATPWallet",
                version="1"
            )
        )
    ),
    description="Returns recent ticks (period=15m) or computed roll"

)
async def get_sentiment_history(
    context: Context,
    asset: Optional[str] = None,
    period: str = "15m",
    limit: int = 48
) -> Any:
    """
    Returns recent ticks (period=15m) or computed rollups (1h, 4h, 1d) sorted newest first.

    Generated from OpenAPI endpoint: GET /api/v1/sentiment/history

    Args:
        context: MCP context (auto-injected by framework, not user-provided)
        asset: Crypto asset (optional)
        period: Time period. 15m returns raw ticks; 1h, 4h, 1d return computed rollups. (optional, default: "15m")
        limit: Max number of results (optional, default: 48)

    Returns:
        API response (dict, list, or other JSON type)

    Example Usage:
        await get_sentiment_history(asset="BTC", period="15m")

        Note: 'context' parameter is auto-injected by MCP framework
    """
    # Payment already verified by @require_payment_for_tool decorator
    # Get API key using helper (handles request.state fallback)
    api_key = get_active_api_key(context)

    try:
        url = f"https://pma.d402.net/api/v1/sentiment/history"
        params = {
            "asset": asset,
            "period": period,
            "limit": limit
        }
        params = {k: v for k, v in params.items() if v is not None}
        headers = {}
        if api_key:
            headers["X-API-Key"] = api_key
            # Also send Bearer for robustness (most APIs use Bearer)
            headers["Authorization"] = f"Bearer {api_key}"

        response = requests.get(
            url,
            params=params,
            headers=headers,
            timeout=30
        )
        response.raise_for_status()

        return response.json()

    except Exception as e:
        logger.error(f"Error in get_sentiment_history: {e}")
        return {"error": str(e), "endpoint": "/api/v1/sentiment/history"}


@mcp.tool()
@require_payment_for_tool(
    price=TokenAmount(
        amount="50000",  # 0.05 tokens
        asset=TokenAsset(
            address="0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
            decimals=6,
            network="sepolia",
            eip712=EIP712Domain(
                name="IATPWallet",
                version="1"
            )
        )
    ),
    description="Returns the most recent raw market data snapshot u"

)
async def get_latest_market_snapshot(
    context: Context,
    asset: Optional[str] = None
) -> Any:
    """
    Returns the most recent raw market data snapshot used to compute a sentiment tick.

    Generated from OpenAPI endpoint: GET /api/v1/sentiment/debug/latest-markets

    Args:
        context: MCP context (auto-injected by framework, not user-provided)
        asset: Crypto asset (optional)

    Returns:
        API response (dict, list, or other JSON type)

    Example Usage:
        await get_latest_market_snapshot(asset="BTC")

        Note: 'context' parameter is auto-injected by MCP framework
    """
    # Payment already verified by @require_payment_for_tool decorator
    # Get API key using helper (handles request.state fallback)
    api_key = get_active_api_key(context)

    try:
        url = f"https://pma.d402.net/api/v1/sentiment/debug/latest-markets"
        params = {
            "asset": asset
        }
        params = {k: v for k, v in params.items() if v is not None}
        headers = {}
        if api_key:
            headers["X-API-Key"] = api_key
            # Also send Bearer for robustness (most APIs use Bearer)
            headers["Authorization"] = f"Bearer {api_key}"

        response = requests.get(
            url,
            params=params,
            headers=headers,
            timeout=30
        )
        response.raise_for_status()

        return response.json()

    except Exception as e:
        logger.error(f"Error in get_latest_market_snapshot: {e}")
        return {"error": str(e), "endpoint": "/api/v1/sentiment/debug/latest-markets"}


# TODO: Add your API-specific functions here

# ============================================================================
# APPLICATION SETUP WITH STARLETTE MIDDLEWARE
# ============================================================================

def create_app_with_middleware():
    """
    Create Starlette app with d402 payment middleware.
    
    Strategy:
    1. Get FastMCP's Starlette app via streamable_http_app()
    2. Extract payment configs from @require_payment_for_tool decorators
    3. Add Starlette middleware with extracted configs
    4. Single source of truth - no duplication!
    """
    logger.info("🔧 Creating FastMCP app with middleware...")
    
    # Get FastMCP's Starlette app
    app = mcp.streamable_http_app()
    logger.info(f"✅ Got FastMCP Starlette app")
    
    # Extract payment configs from decorators (single source of truth!)
    tool_payment_configs = extract_payment_configs_from_mcp(mcp, SERVER_ADDRESS)
    logger.info(f"📊 Extracted {len(tool_payment_configs)} payment configs from @require_payment_for_tool decorators")
    
    # D402 Configuration
    facilitator_url = os.getenv("FACILITATOR_URL") or os.getenv("D402_FACILITATOR_URL")
    operator_key = os.getenv("MCP_OPERATOR_PRIVATE_KEY")
    network = os.getenv("NETWORK", "sepolia")
    testing_mode = os.getenv("D402_TESTING_MODE", "false").lower() == "true"
    
    # Log D402 configuration with prominent facilitator info
    logger.info("="*60)
    logger.info("D402 Payment Protocol Configuration:")
    logger.info(f"  Server Address: {SERVER_ADDRESS}")
    logger.info(f"  Network: {network}")
    logger.info(f"  Operator Key: {'✅ Set' if operator_key else '❌ Not set'}")
    logger.info(f"  Testing Mode: {'⚠️  ENABLED (bypasses facilitator)' if testing_mode else '✅ DISABLED (uses facilitator)'}")
    logger.info("="*60)
    
    if not facilitator_url and not testing_mode:
        logger.error("❌ FACILITATOR_URL required when testing_mode is disabled!")
        raise ValueError("Set FACILITATOR_URL or enable D402_TESTING_MODE=true")
    
    if facilitator_url:
        logger.info(f"🌐 FACILITATOR: {facilitator_url}")
        if "localhost" in facilitator_url or "127.0.0.1" in facilitator_url or "host.docker.internal" in facilitator_url:
            logger.info(f"   📍 Using LOCAL facilitator for development")
        else:
            logger.info(f"   🌍 Using REMOTE facilitator for production")
    else:
        logger.warning("⚠️  D402 Testing Mode - Facilitator bypassed")
    logger.info("="*60)
    
    # Add CORS middleware first (processes before other middleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # Allow all origins
        allow_credentials=True,
        allow_methods=["*"],  # Allow all methods
        allow_headers=["*"],  # Allow all headers
        expose_headers=["mcp-session-id"],  # Expose custom headers to browser
    )
    logger.info("✅ Added CORS middleware (allow all origins, expose mcp-session-id)")
    
    # Add D402 payment middleware with extracted configs
    app.add_middleware(
        D402PaymentMiddleware,
        tool_payment_configs=tool_payment_configs,
        server_address=SERVER_ADDRESS,
        requires_auth=True,  # Extracts API keys + checks payment
        internal_api_key=API_KEY,  # Server's internal key (for Mode 2: paid access)
        testing_mode=testing_mode,
        facilitator_url=facilitator_url,
        facilitator_api_key=os.getenv("D402_FACILITATOR_API_KEY"),
        server_name="polymarket-v2-mcp-server"  # MCP server ID for tracking
    )
    logger.info("✅ Added D402PaymentMiddleware")
    logger.info("   - Auth extraction: Enabled")
    logger.info("   - Dual mode: API key OR payment")
    
    # Add health check endpoint (bypasses middleware)
    @app.route("/health", methods=["GET"])
    async def health_check(request: Request) -> JSONResponse:
        """Health check endpoint for container orchestration."""
        return JSONResponse(
            content={
                "status": "healthy",
                "service": "polymarket-v2-mcp-server",
                "timestamp": datetime.now().isoformat()
            }
        )
    logger.info("✅ Added /health endpoint")
    
    return app

if __name__ == "__main__":
    logger.info("="*80)
    logger.info(f"Starting Polymarket v2 MCP Server")
    logger.info("="*80)
    logger.info("Architecture:")
    logger.info("  1. D402PaymentMiddleware intercepts requests")
    logger.info("     - Extracts API keys from Authorization header")
    logger.info("     - Checks payment → HTTP 402 if no API key AND no payment")
    logger.info("  2. FastMCP processes valid requests with tool decorators")
    logger.info("="*80)
    
    # Create app with middleware
    app = create_app_with_middleware()
    
    # Run with uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=PORT,
        log_level=os.getenv("LOG_LEVEL", "info").lower()
    )
