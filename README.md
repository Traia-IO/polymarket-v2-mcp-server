# Polymarket v2 MCP Server

This is an MCP (Model Context Protocol) server that provides with authentication via Bearer tokens access to the Polymarket v2 API. It enables AI agents and LLMs to interact with Polymarket v2 through standardized tools.

## Features

- 🔧 **MCP Protocol**: Built on the Model Context Protocol for seamless AI integration
- 🌐 **Full API Access**: Provides tools for interacting with Polymarket v2 endpoints
- 🔐 **Secure Authentication**: Supports API key authentication via Bearer tokens
- 💳 **HTTP 402 Payment Protocol**: Dual-mode operation (authenticated or paid access)
- 🔗 **D402 Integration**: Uses traia_iatp.d402 for blockchain payment verification
- 🐳 **Docker Support**: Easy deployment with Docker and Docker Compose
- ⚡ **Async Operations**: Built with FastMCP for efficient async handling

## API Documentation

- **Polymarket v2 Website**: [https://pma.d402.net](https://pma.d402.net)
- **API Documentation**: []()

## Available Tools

This server provides the following tools:

- **`example_tool`**: Placeholder tool (to be implemented)

*Note: Replace `example_tool` with actual Polymarket v2 API tools based on the documentation.*

## Installation

### Using Docker (Recommended)

1. Clone this repository:
   ```bash
   git clone https://github.com/Traia-IO/polymarket-v2-mcp-server.git
   cd polymarket-v2-mcp-server
   ```

2. Set your API key:
   ```bash
   export POLYMARKET_V2_API_KEY="your-api-key-here"
   ```

3. Run with Docker:
   ```bash
   ./run_local_docker.sh
   ```

### Using Docker Compose

1. Create a `.env` file with your configuration:
   ```env
# Server's internal API key (for payment mode)
   POLYMARKET_V2_API_KEY=your-api-key-here
   
   # Server payment address (for HTTP 402 protocol)
   SERVER_ADDRESS=0x1234567890123456789012345678901234567890
   
   # Operator keys (for signing settlement attestations)
   MCP_OPERATOR_PRIVATE_KEY=0x1234567890abcdef...
   MCP_OPERATOR_ADDRESS=0x9876543210fedcba...
   
   # Optional: Testing mode (skip settlement for local dev)
   D402_TESTING_MODE=false
PORT=8000
   ```

2. Start the server:
   ```bash
   docker-compose up
   ```

### Manual Installation

1. Install dependencies using `uv`:
   ```bash
   uv pip install -e .
   ```

2. Run the server:
   ```bash
POLYMARKET_V2_API_KEY="your-api-key-here" uv run python -m server
   ```

## Usage

### Health Check

Test if the server is running:
```bash
python mcp_health_check.py
```

### Using with CrewAI

```python
from traia_iatp.mcp.traia_mcp_adapter import create_mcp_adapter_with_auth

# Connect with authentication
with create_mcp_adapter_with_auth(
    url="http://localhost:8000/mcp/",
    api_key="your-api-key"
) as tools:
    # Use the tools
    for tool in tools:
        print(f"Available tool: {tool.name}")
        
    # Example usage
    result = await tool.example_tool(query="test")
    print(result)
```

## Authentication & Payment (HTTP 402 Protocol)

This server supports **two modes of operation**:

### Mode 1: Authenticated Access (Free)

Clients with their own Polymarket v2 API key can use the server for free:

```bash
# Request with client's API key
curl -X POST http://localhost:8000/mcp \
  -H "Authorization: Bearer CLIENT_POLYMARKET_V2_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"method":"tools/call","params":{"name":"example_tool","arguments":{"query":"test"}}}'
```

**Flow**:
1. Client provides their Polymarket v2 API key
2. Server uses client's API key to call Polymarket v2 API
3. No payment required
4. Client pays Polymarket v2 directly

### Mode 2: Payment Required (Paid Access)

Clients without an API key can pay-per-use via HTTP 402 protocol:

```bash
# Request with payment proof (x402/d402 protocol)
curl -X POST http://localhost:8000/mcp \
  -H "X-PAYMENT: <base64_encoded_x402_payment>" \
  -H "Content-Type: application/json" \
  -d '{"method":"tools/call","params":{"name":"example_tool","arguments":{"query":"test"}}}'
```

**Flow**:
1. Client makes initial request without payment
2. Server returns HTTP 402 with PaymentRequirements (token, network, amount)
3. Client creates EIP-3009 transferWithAuthorization payment signature
4. Client base64-encodes payment and sends in X-PAYMENT header
5. Server verifies payment via traia_iatp.d402.mcp_middleware
6. Server uses its INTERNAL Polymarket v2 API key to call the API
7. Client receives result

### D402 Protocol Details

This server uses the **traia_iatp.d402** module for payment verification:

- **Payment Method**: EIP-3009 transferWithAuthorization (gasless)
- **Supported Tokens**: USDC, TRAIA, or any ERC20 token
- **Default Price**: $0.001 per request (configurable via `DEFAULT_PRICE_USD`)
- **Networks**: Base Sepolia, Sepolia, Polygon, etc.
- **Facilitator**: d402.org (public) or custom facilitator

### Environment Variables for Payment Mode

```bash
# Required
POLYMARKET_V2_API_KEY=your_internal_polymarket-v2_api_key  # Server's API key (for payment mode)
SERVER_ADDRESS=0x1234567890123456789012345678901234567890  # Server's payment address

# Required for Settlement (Production)
MCP_OPERATOR_PRIVATE_KEY=0x1234...  # Private key for signing settlement attestations
MCP_OPERATOR_ADDRESS=0x5678...      # Operator's public address (for verification)

# Optional
D402_FACILITATOR_URL=https://facilitator.d402.net  # Facilitator service URL
D402_FACILITATOR_API_KEY=your_key  # For private facilitator
D402_TESTING_MODE=false  # Set to 'true' for local testing without settlement
```

**Operator Keys**:
- **MCP_OPERATOR_PRIVATE_KEY**: Used to sign settlement attestations (proof of service completion)
- **MCP_OPERATOR_ADDRESS**: Public address corresponding to the private key
- Required for on-chain settlement via IATP Settlement Layer
- Can be the same as SERVER_ADDRESS or a separate operator key

**Note on Per-Endpoint Configuration**:
Each endpoint's payment requirements (token address, network, price) are embedded in the tool code.
They come from the endpoint configuration when the server is generated.

### How It Works

1. **Client Decision**:
   - Has Polymarket v2 API key? → Mode 1 (Authenticated)
   - No API key but willing to pay? → Mode 2 (Payment)

2. **Server Response**:
   - Mode 1: Uses client's API key (free for client)
   - Mode 2: Uses server's API key (client pays server)

3. **Business Model**:
   - Mode 1: No revenue (passthrough)
   - Mode 2: Revenue from pay-per-use (monetize server's API subscription)


## Development

### Testing the Server

1. Start the server locally
2. Run the health check: `python mcp_health_check.py`
3. Test individual tools using the CrewAI adapter

### Adding New Tools

To add new tools, edit `server.py` and:

1. Create API client functions for Polymarket v2 endpoints
2. Add `@mcp.tool()` decorated functions
3. Update this README with the new tools
4. Update `deployment_params.json` with the tool names in the capabilities array

## Deployment

### Deployment Configuration

The `deployment_params.json` file contains the deployment configuration for this MCP server:

```json
{
  "github_url": "https://github.com/Traia-IO/polymarket-v2-mcp-server",
  "mcp_server": {
    "name": "polymarket-v2-mcp",
    "description": "Polymarket api mcp server for btc and eth",
    "server_type": "streamable-http",
"requires_api_key": true,
    "api_key_header": "Authorization",
"capabilities": [
      // List all implemented tool names here
      "example_tool"
    ]
  },
  "deployment_method": "cloud_run",
  "gcp_project_id": "traia-mcp-servers",
  "gcp_region": "us-central1",
  "tags": ["polymarket v2", "api"],
  "ref": "main"
}
```

**Important**: Always update the `capabilities` array when you add or remove tools!

### Google Cloud Run

This server is designed to be deployed on Google Cloud Run. The deployment will:

1. Build a container from the Dockerfile
2. Deploy to Cloud Run with the specified configuration
3. Expose the `/mcp` endpoint for client connections

## Environment Variables

- `PORT`: Server port (default: 8000)
- `STAGE`: Environment stage (default: MAINNET, options: MAINNET, TESTNET)
- `LOG_LEVEL`: Logging level (default: INFO)
- `POLYMARKET_V2_API_KEY`: Your Polymarket v2 API key (required)
## Troubleshooting

1. **Server not starting**: Check Docker logs with `docker logs <container-id>`
2. **Authentication errors**: Ensure your API key is correctly set in the environment
3. **API errors**: Verify your API key has the necessary permissions3. **Tool errors**: Check the server logs for detailed error messages

## Contributing

1. Fork the repository
2. Create a feature branch
3. Implement new tools or improvements
4. Update the README and deployment_params.json
5. Submit a pull request

## License

[MIT License](LICENSE)