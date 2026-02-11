# Polymarket v2 MCP Server Implementation Guide

You are working on implementing the Polymarket v2 MCP (Model Context Protocol) server. The basic structure has been set up, and your task is to implement the actual API integration.

## API Information

- **API Name**: Polymarket v2
- **Documentation**: []()
- **Website**: [https://pma.d402.net](https://pma.d402.net)
- **Authentication**: Required - API key via `POLYMARKET_V2_API_KEY` environment variable
## 🔒 HTTP 402 Payment Protocol - Dual-Mode Operation

This MCP server implements the **HTTP 402 Payment Required** protocol using the **traia_iatp.d402** module with dual-mode support:

### Mode 1: Authenticated (Free Access)

When a client provides their own Polymarket v2 API key:

```
Request Headers:
  Authorization: Bearer CLIENT_API_KEY

Flow:
  1. Client connects with their Polymarket v2 API key
  2. MCP server uses client's API key to call Polymarket v2 API
  3. No payment required
  4. Client pays Polymarket v2 directly (not the MCP server)
```

**Use Case**: Clients who already have a Polymarket v2 subscription/API key

### Mode 2: Payment Required (Paid Access)

When a client doesn't have their own API key but pays via x402/d402 protocol:

```
Request Headers:
  X-PAYMENT: <base64_encoded_x402_payment>

X402 Payment Header Format (created by x402.clients.base.create_payment_header()):
  {
    "x402Version": 1,
    "scheme": "exact",
    "network": "base-sepolia",
    "payload": {
      "signature": "0x...",
      "authorization": {
        "from": "0xCLIENT_ADDRESS",
        "to": "0xSERVER_ADDRESS",
        "value": "1000",  // atomic units (wei)
        "validAfter": "1700000000",
        "validBefore": "1700000300",
        "nonce": "hex..."
      }
    }
  }

Flow:
  1. Client creates EIP-3009 transferWithAuthorization signature
  2. Client sends Payment header with encoded payment payload
  3. MCP server verifies payment using traia_iatp.d402.facilitator
  4. MCP server uses its INTERNAL Polymarket v2 API key to call the API
  5. Client pays the MCP server (not Polymarket v2)
```

**Use Case**: Pay-per-use clients without their own Polymarket v2 subscription

### D402 Protocol Integration

This server uses the **traia_iatp.d402** module which implements:
- EIP-3009 transferWithAuthorization for gasless payments
- Payment verification via IATP Settlement Facilitator
- On-chain transaction verification
- Multiple token support (USDC, TRAIA, etc.)

**Dependencies** (already in pyproject.toml):
- `traia-iatp>=0.1.27` - Provides d402 module
- `web3>=6.15.0` - For blockchain verification

### Implementation Pattern for Tools

**For auto-generated tools** (from OpenAPI), the endpoint implementer will generate code like this:

```python
from traia_iatp.d402.mcp_middleware import EndpointPaymentInfo, verify_endpoint_payment

@mcp.tool()
async def your_tool_name(context: Context, param1: str) -> Dict[str, Any]:
    """Your tool description."""
    
    # Get client's API key (if provided)
    api_key = get_session_api_key(context)
    
    # If no API key, verify payment for this specific endpoint
    if not api_key:
        # Each endpoint has specific payment requirements
        endpoint_payment = EndpointPaymentInfo(
            settlement_token_address="0xUSDC...",  # From endpoint config
            settlement_token_network="base-sepolia",  # From endpoint config
            payment_price_float=0.001,  # From endpoint config
            payment_price_wei="1000",  # From endpoint config
            server_address="0xSERVER..."  # Server's payment address
        )
        
        # Verify payment matches this endpoint's requirements
        if not verify_endpoint_payment(context, endpoint_payment):
            return {
                "error": "Payment required or insufficient",
                "code": 402,
                "required_payment": {
                    "token": "0xUSDC...",
                    "network": "base-sepolia",
                    "amount": 0.001
                }
            }
    
    # Dual-mode: determine which API key to use
    if api_key:
        # MODE 1: Use client's API key (free for client)
        api_key_to_use = api_key
    else:
        # MODE 2: Use server's internal API key (client paid)
        api_key_to_use = os.getenv("POLYMARKET_V2_API_KEY")
    
    # Call API
    headers = {"Authorization": f"Bearer {api_key_to_use}"}
    response = requests.get("https://pma.d402.net/endpoint", headers=headers)
    return response.json()
```

**Key points**:
1. Each tool verifies payment against **its specific endpoint requirements**
2. Different endpoints can have different tokens, networks, and prices
3. Payment amount/token/network are verified per-endpoint
4. The middleware just extracts payment payload globally

### Middleware Chain

The server has TWO middleware in sequence:

1. **AuthMiddleware**: Extracts client's API key from Authorization header
2. **D402MCPMiddleware**: Extracts and validates payment payload from Payment header

### How Per-Endpoint Payment Works

Unlike FastAPI where middleware can be applied per-route, FastMCP has global middleware.
Therefore:

1. **D402MCPMiddleware**: Extracts payment payload globally, stores in `context.state.payment_payload`
2. **Each Tool**: Calls `verify_endpoint_payment()` with its specific requirements
   - Verifies payment token matches endpoint's settlement token
   - Verifies payment amount meets endpoint's price
   - Verifies payment network matches endpoint's network

**Result**: Different endpoints can accept different tokens, on different networks, at different prices!

### Environment Variables

**Required**:
- `POLYMARKET_V2_API_KEY`: Server's internal Polymarket v2 API key (used when clients pay via 402)
- `SERVER_ADDRESS`: MCP server's payment address (where 402 payments are sent)

**Required for Settlement (Production)**:
- `MCP_OPERATOR_PRIVATE_KEY`: Private key for signing settlement attestations (proof of service completion)
- `MCP_OPERATOR_ADDRESS`: Public address corresponding to operator private key (for verification)

**Optional**:
- `D402_FACILITATOR_URL`: Custom d402 facilitator URL (default: "https://facilitator.d402.net")
- `D402_FACILITATOR_API_KEY`: API key for private facilitator
- `D402_TESTING_MODE`: Set to "true" for local testing without settlement (default: "false")

**Example .env file**:
```bash
# API Authentication (server's internal key for payment mode)
POLYMARKET_V2_API_KEY=your_polymarket-v2_api_key_here

# Server Payment Address (where 402 payments are received)
SERVER_ADDRESS=0x1234567890123456789012345678901234567890

# Operator Keys (for signing settlement attestations)
MCP_OPERATOR_PRIVATE_KEY=0x1234567890abcdef...  # Keep secure!
MCP_OPERATOR_ADDRESS=0x9876543210fedcba...      # Derived from private key

# Optional: Custom facilitator
D402_FACILITATOR_URL=https://facilitator.d402.net
D402_FACILITATOR_API_KEY=facilitator_api_key

# Optional: Testing mode (skip settlement for local dev)
D402_TESTING_MODE=false  # Set to 'true' for testing without facilitator
```

**About Operator Keys**:
- The operator signs settlement attestations after completing each paid request
- Attestation proves: service was completed + output hash is valid
- Can use the same key as SERVER_ADDRESS or a separate signing key
- Required for on-chain settlement via IATP Settlement Layer

**Note on Endpoint-Specific Configuration**:
Each endpoint's payment requirements (token, network, price) are embedded in the tool code.
These come from the endpoint configuration in the database/OpenAPI schema.


## Implementation Checklist

### 1. Update Deployment Configuration

**IMPORTANT**: Update the `deployment_params.json` file with all implemented capabilities:

```json
{
  "mcp_server": {
    "capabilities": [
      // Replace these with your actual implemented tool names
      "search_polymarket_v2",
      "get_polymarket_v2_info",
      // Add all other tools you implement
    ]
  },
  "tags": ["polymarket v2", "api", /* add relevant tags like "search", "data", etc. */]
}
```

### 2. Study the API Documentation

First, thoroughly review the API documentation at  to understand:
- Available endpoints
- Request/response formats
- Rate limits
- Error handling
- Authentication method (API key placement in headers, query params, etc.)- Specific features and capabilities to expose as tools

### 3. Implement API Client Functions

Add functions to call the Polymarket v2 API with retry support. Example pattern:

```python
from retry import retry

# Using requests library with retry decorator
@retry(tries=2, delay=1, backoff=2, jitter=(1, 3))
def call_polymarket_v2_api(endpoint: str, params: Dict[str, Any], api_key: str) -> Dict[str, Any]:
    """Call Polymarket v2 API endpoint with automatic retry."""
    base_url = "https://api.example.com/v1"  # TODO: Get actual base URL from docs
    
    headers = {
"Authorization": f"Bearer {api_key}",  # Or "X-API-Key": api_key
"Content-Type": "application/json"
    }
    
    # Will retry once on any requests.RequestException
    try:
        response = requests.get(f"{base_url}/{endpoint}", 
                              params=params, 
                              headers=headers,
                              timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        raise Exception(f"Polymarket v2 API error: {str(e)}")
```

#### Retry Configuration Explained

- `tries=2`: Total attempts (1 original + 1 retry)
- `delay=1`: Wait 1 second before retry
- `backoff=2`: Multiply delay by 2 for subsequent retries (if more than 2 tries)
- `jitter=(1, 3)`: Add random delay between 1-3 seconds to avoid thundering herd

### 4. Create MCP Tools

Replace the `example_tool` placeholder with actual tools. **Each tool you implement MUST be added to the `capabilities` array in `deployment_params.json`**.

#### Search/Query Tool
```python
@mcp.tool()
async def search_polymarket_v2(
    context: Context,
    query: str,
    limit: int = 10
) -> Dict[str, Any]:
    """
    Search Polymarket v2 for [specific data type].
    
    Args:
        context: MCP context (injected automatically)
        query: Search query
        limit: Maximum number of results
        
    Returns:
        Dictionary with search results
    """
    api_key = get_session_api_key(context)
    if not api_key:
        return {"error": "No API key found. Please authenticate with Authorization: Bearer YOUR_API_KEY"}
    
    try:
        # The call_polymarket_v2_api function already has retry logic
        results = call_polymarket_v2_api(
            "search",  # TODO: Use actual endpoint
            {"q": query, "limit": limit},
api_key)
        return {
            "status": "success",
            "results": results
        }
    except Exception as e:
        return {"error": str(e)}
```

#### Get/Fetch Tool
```python
@mcp.tool()
async def get_polymarket_v2_info(
    context: Context,
    item_id: str
) -> Dict[str, Any]:
    """
    Get detailed information about a specific item.
    
    Args:
        context: MCP context (injected automatically)
        item_id: ID of the item to fetch
        
    Returns:
        Dictionary with item details
    """
    # Similar implementation pattern
```

#### Create/Update Tool (if applicable)
```python
@mcp.tool()
async def create_polymarket_v2_item(
    context: Context,
    name: str,
    data: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Create a new item in Polymarket v2.
    
    Args:
        context: MCP context (injected automatically)
        name: Name of the item
        data: Additional data for the item
        
    Returns:
        Dictionary with creation result
    """
    # Implementation here
```

### 5. Best Practices

1. **Error Handling**: Always wrap API calls in try-except blocks and return user-friendly error messages
2. **Input Validation**: Validate parameters before making API calls
3. **Rate Limiting**: Respect API rate limits, implement delays if needed
4. **Response Formatting**: Return consistent response structures across all tools
5. **Logging**: Use the logger for debugging but don't log sensitive data like API keys
6. **Documentation**: Write clear docstrings for each tool explaining parameters and return values
7. **Retry Strategy**: Use the `@retry` decorator on API client functions for resilience

#### Retry Best Practices

- **Only use retry for external API calls** - Don't add retry to internal functions, database operations, or file operations
- **Apply retry to API client functions**, not MCP tool functions directly
- **Use `tries=2`** (1 original attempt + 1 retry) to balance reliability and responsiveness
- **Add jitter** to prevent thundering herd when multiple clients retry simultaneously
- **Don't retry on authentication errors** - use conditional retry if needed:
  ```python
  from retry import retry
  import requests
  
  def retry_on_server_error(exception):
      """Only retry on server errors (5xx), not client errors (4xx)"""
      if isinstance(exception, requests.HTTPError):
          return 500 <= exception.response.status_code < 600
      return True  # Retry on other exceptions like network errors
  
  @retry(tries=2, delay=1, backoff=2, jitter=(1, 3), exceptions=retry_on_server_error)
  def call_api_with_smart_retry(endpoint, params, api_key):
      # API implementation
      pass
  ```
- **Log retry attempts** for debugging:
  ```python
  @retry(tries=2, delay=1, logger=logger)
  def call_polymarket_v2_api(...):
      # Implementation
  ```

#### When to Use Retry

**✅ DO use retry for:**
- HTTP requests to external APIs
- Network operations that can fail temporarily
- Remote service calls that may experience transient errors

**❌ DON'T use retry for:**
- MCP tool functions (they should handle errors gracefully instead)
- Local file operations
- Database queries (unless specifically needed for connection issues)
- Authentication/validation logic
- Data processing or computation functions

### 6. Testing

After implementing tools, test them:

1. Run the server locally:
   ```bash
   ./run_local_docker.sh
   ```

2. Use the health check script:
   ```bash
   python mcp_health_check.py
   ```

3. Test with CrewAI:
   ```python
from traia_iatp.mcp.traia_mcp_adapter import create_mcp_adapter_with_auth
   
   # Authenticated connection
   with create_mcp_adapter_with_auth(
       url="http://localhost:8000/mcp/",
       api_key="your-api-key"
   ) as tools:
       # Test your tools
       for tool in tools:
           print(f"Tool: {tool.name}")
   ```

### 7. Update Documentation

After implementing the tools:

1. **Update README.md**:
   - List all implemented tools with descriptions
   - Add usage examples for each tool
   - Include any specific setup instructions

2. **Update deployment_params.json**:
   - Ensure ALL tool names are in the `capabilities` array
   - Add relevant tags based on functionality
   - Verify authentication settings match implementation

3. **Add Tool Examples** in README.md:
   ```python
   # Example usage of each tool
   result = await tool.search_polymarket_v2(query="example", limit=5)
   ```

### 8. Pre-Deployment Checklist

Before marking the implementation as complete:

- [ ] All placeholder code has been replaced with actual implementation
- [ ] All tools are properly documented with docstrings
- [ ] Error handling is implemented for all API calls
- [ ] `deployment_params.json` contains all tool names in capabilities
- [ ] README.md has been updated with usage examples
- [ ] Server runs successfully with `./run_local_docker.sh`
- [ ] Health check passes
- [ ] At least one tool works end-to-end

### 9. Common Polymarket v2 Use Cases

Based on the API documentation, consider implementing tools for these common use cases:

1. **TODO**: List specific use cases based on Polymarket v2 capabilities
2. **TODO**: Add more relevant use cases
3. **TODO**: Include any special features of this API

### 10. Example API Calls

Here are some example API calls from the Polymarket v2 documentation that you should implement:

```
TODO: Add specific examples from the API docs
```

## Need Help?

- Check the Polymarket v2 API documentation: 
- Review the MCP specification: https://modelcontextprotocol.io
- Look at other MCP server examples in the Traia-IO organization

Remember: The goal is to make Polymarket v2's capabilities easily accessible to AI agents through standardized MCP tools. 