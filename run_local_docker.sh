#!/bin/bash

# Script to build and run the Polymarket v2 MCP Server locally in Docker

set -e  # Exit on error

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration (will be overridden by .env if present)
IMAGE_NAME="polymarket-v2-mcp-server"
CONTAINER_NAME="polymarket-v2-mcp-local"
HOST_PORT=${PORT:-8000}
CONTAINER_PORT=${PORT:-8000}

echo -e "${BLUE}🚀 Building and running Polymarket v2 MCP Server...${NC}"
echo

# Setup .env file for local development
# Step 1: Copy .env.example to .env (if .env doesn't exist)
if [ ! -f .env ]; then
    echo -e "${BLUE}📋 Setting up .env file for local development...${NC}"
    
    if [ -f .env.example ]; then
        echo -e "${BLUE}   Copying .env.example to .env...${NC}"
        cp .env.example .env
    else
        echo -e "${YELLOW}⚠️  .env.example not found, creating minimal .env template...${NC}"
        # Create minimal .env template
        cat > .env << EOF
# Polymarket v2 MCP Server Configuration
PORT=8000
STAGE=MAINNET
LOG_LEVEL=INFO

# API Authentication (server's internal key for payment mode)
POLYMARKET_V2_API_KEY=
# D402 Payment Protocol Configuration
SERVER_ADDRESS=
MCP_OPERATOR_PRIVATE_KEY=
MCP_OPERATOR_ADDRESS=
# Facilitator options:
#   - Remote (production): https://test-facilitator.d402.net
#   - Local (development): http://host.docker.internal:7070
D402_FACILITATOR_URL=https://test-facilitator.d402.net
D402_FACILITATOR_API_KEY=
DEFAULT_SETTLEMENT_TOKEN=0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
DEFAULT_SETTLEMENT_NETWORK=sepolia
D402_TESTING_MODE=false
NETWORK=sepolia
EOF
    fi
fi

# Step 2: Fix pyproject.toml to use local IATP path for account generation
# This is needed because uv run python requires a valid pyproject.toml
echo -e "${BLUE}🔧 Fixing pyproject.toml for local development...${NC}"

# Find local IATP path
IATP_PATH=""
if [ -d "/Users/eitanlavi/workspace/traia/IATP" ]; then
    IATP_PATH="/Users/eitanlavi/workspace/traia/IATP"
elif [ -d "$(dirname $(pwd))/IATP" ]; then
    IATP_PATH="$(dirname $(pwd))/IATP"
elif [ -d "$HOME/workspace/traia/IATP" ]; then
    IATP_PATH="$HOME/workspace/traia/IATP"
elif [ -n "$LOCAL_IATP_PATH" ] && [ -d "$LOCAL_IATP_PATH" ]; then
    IATP_PATH="$LOCAL_IATP_PATH"
fi

# Temporarily update pyproject.toml to use local IATP path (if /tmp/IATP is present)
if grep -q "file:///tmp/IATP" pyproject.toml 2>/dev/null; then
    if [ -n "$IATP_PATH" ] && [ -d "$IATP_PATH" ]; then
        echo -e "${BLUE}   Updating pyproject.toml to use: $IATP_PATH${NC}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|file:///tmp/IATP|file://$IATP_PATH|g" pyproject.toml
        else
            sed -i "s|file:///tmp/IATP|file://$IATP_PATH|g" pyproject.toml
        fi
    else
        echo -e "${RED}❌ Local IATP not found. Cannot generate accounts.${NC}"
        echo -e "${YELLOW}   Please set LOCAL_IATP_PATH environment variable or ensure IATP is at /Users/eitanlavi/workspace/traia/IATP${NC}"
        exit 1
    fi
fi

# Step 3: Generate Ethereum accounts for local development (workaround)
# Only generate if not already set with valid values
SKIP_GENERATION=false
if grep -q "^SERVER_ADDRESS=0x[0-9a-fA-F]\{40\}" .env && grep -q "^MCP_OPERATOR_PRIVATE_KEY=" .env; then
    echo -e "${GREEN}✅ SERVER_ADDRESS and MCP_OPERATOR_PRIVATE_KEY already set in .env${NC}"
    echo -e "${BLUE}   Skipping account generation (keeping existing values)${NC}"
    SKIP_GENERATION=true
else
    echo -e "${BLUE}🔐 Generating Ethereum accounts for local testing...${NC}"
fi

if [ "$SKIP_GENERATION" = "false" ]; then
# Generate accounts using Python (web3 library)
# Use uv run to ensure web3 is available from the project dependencies
uv run python << 'PYTHON_SCRIPT'
import sys
import secrets

try:
    from web3 import Web3
    
    # Generate server address (EOA for local testing)
    # This is a workaround - in production, SERVER_ADDRESS comes from IATP wallet contract
    server_private_key = "0x" + secrets.token_hex(32)
    server_account = Web3().eth.account.from_key(server_private_key)
    server_address = server_account.address
    
    # Generate operator private key and address
    # This is a workaround - in production, these come from IATP wallet contract
    operator_private_key = "0x" + secrets.token_hex(32)
    operator_account = Web3().eth.account.from_key(operator_private_key)
    operator_address = operator_account.address
    
    # Write to temporary file
    with open('.env.generated', 'w') as f:
        f.write(f"SERVER_ADDRESS={server_address}\n")
        f.write(f"MCP_OPERATOR_PRIVATE_KEY={operator_private_key}\n")
        f.write(f"MCP_OPERATOR_ADDRESS={operator_address}\n")
    
    print(f"Generated SERVER_ADDRESS: {server_address}")
    print(f"Generated MCP_OPERATOR_ADDRESS: {operator_address}")
    sys.exit(0)
except ImportError:
    print("ERROR: web3 library not found. Install it with: pip install web3", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Failed to generate accounts: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
fi

# Step 4: Fill in generated values into .env
if [ $? -eq 0 ] && [ -f .env.generated ]; then
    # Load generated values
    source .env.generated
    
    # Update .env file with generated values (macOS-compatible sed)
    # Use a temporary file approach for portability
    if grep -q "^SERVER_ADDRESS=" .env; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^SERVER_ADDRESS=.*|SERVER_ADDRESS=$SERVER_ADDRESS|" .env
        else
            sed -i "s|^SERVER_ADDRESS=.*|SERVER_ADDRESS=$SERVER_ADDRESS|" .env
        fi
    else
        echo "SERVER_ADDRESS=$SERVER_ADDRESS" >> .env
    fi
    
    if grep -q "^MCP_OPERATOR_PRIVATE_KEY=" .env; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^MCP_OPERATOR_PRIVATE_KEY=.*|MCP_OPERATOR_PRIVATE_KEY=$MCP_OPERATOR_PRIVATE_KEY|" .env
        else
            sed -i "s|^MCP_OPERATOR_PRIVATE_KEY=.*|MCP_OPERATOR_PRIVATE_KEY=$MCP_OPERATOR_PRIVATE_KEY|" .env
        fi
    else
        echo "MCP_OPERATOR_PRIVATE_KEY=$MCP_OPERATOR_PRIVATE_KEY" >> .env
    fi
    
    if grep -q "^MCP_OPERATOR_ADDRESS=" .env; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|^MCP_OPERATOR_ADDRESS=.*|MCP_OPERATOR_ADDRESS=$MCP_OPERATOR_ADDRESS|" .env
        else
            sed -i "s|^MCP_OPERATOR_ADDRESS=.*|MCP_OPERATOR_ADDRESS=$MCP_OPERATOR_ADDRESS|" .env
        fi
    else
        echo "MCP_OPERATOR_ADDRESS=$MCP_OPERATOR_ADDRESS" >> .env
    fi
    
    rm -f .env.generated
    echo -e "${GREEN}✅ Generated Ethereum accounts and updated .env${NC}"
else
    if [ "$SKIP_GENERATION" = "false" ]; then
        echo -e "${RED}❌ Failed to generate accounts. Please install web3: pip install web3${NC}"
        echo -e "${YELLOW}   Or set SERVER_ADDRESS, MCP_OPERATOR_PRIVATE_KEY, and MCP_OPERATOR_ADDRESS manually in .env${NC}"
        exit 1
    fi
fi

# Step 4: Ensure D402_TESTING_MODE is set (preserves user's manual edits)
# This runs whether accounts were generated or not
if ! grep -q "^D402_TESTING_MODE=" .env; then
    echo -e "${BLUE}📋 Setting D402_TESTING_MODE...${NC}"
    echo "D402_TESTING_MODE=false" >> .env
    echo -e "${YELLOW}   Set D402_TESTING_MODE=false (default for local dev)${NC}"
else
    echo -e "${GREEN}✅ D402_TESTING_MODE already set in .env (keeping existing value)${NC}"
fi

# Step 5: Prompt for API key if required (only if not already set)
if ! grep -q "^POLYMARKET_V2_API_KEY=[^[:space:]]" .env; then
    if [ -t 0 ]; then
        echo ""
        echo -e "${YELLOW}📝 Please enter your Polymarket v2 API key:${NC}"
        echo -e "${YELLOW}   (This is the server's internal API key used when clients pay via 402)${NC}"
        read -p "POLYMARKET_V2_API_KEY: " API_KEY_VALUE
        if [ -n "$API_KEY_VALUE" ]; then
            if grep -q "^POLYMARKET_V2_API_KEY=" .env; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' "s|^POLYMARKET_V2_API_KEY=.*|POLYMARKET_V2_API_KEY=$API_KEY_VALUE|" .env
                else
                    sed -i "s|^POLYMARKET_V2_API_KEY=.*|POLYMARKET_V2_API_KEY=$API_KEY_VALUE|" .env
                fi
            else
                echo "POLYMARKET_V2_API_KEY=$API_KEY_VALUE" >> .env
            fi
            echo -e "${GREEN}✅ API key saved to .env${NC}"
        else
            echo -e "${YELLOW}⚠️  No API key provided. You can set it later in .env${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Non-interactive mode: Please set POLYMARKET_V2_API_KEY in .env manually${NC}"
    fi
else
    echo -e "${GREEN}✅ POLYMARKET_V2_API_KEY already set in .env${NC}"
fi

echo ""
echo -e "${GREEN}✅ .env file configured for local development!${NC}"
echo -e "${BLUE}📋 Review .env file if needed before continuing...${NC}"
if [ -t 0 ]; then
    echo -e "${YELLOW}Press Enter to continue, or Ctrl+C to cancel...${NC}"
    read
fi

# Load environment variables from .env file
echo -e "${BLUE}📋 Loading environment variables from .env file...${NC}"
set -a  # Export all variables
source .env
set +a  # Stop exporting

# Update port variables after loading .env
HOST_PORT=${PORT:-8000}
CONTAINER_PORT=${PORT:-8000}

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed. Please install Docker first.${NC}"
    exit 1
fi

# Stop and remove existing container if it exists
if docker ps -a | grep -q $CONTAINER_NAME; then
    echo -e "${YELLOW}🛑 Stopping existing container...${NC}"
    docker stop $CONTAINER_NAME >/dev/null 2>&1 || true
    docker rm $CONTAINER_NAME >/dev/null 2>&1 || true
fi

# Build the Docker image
echo -e "${BLUE}🔨 Building Docker image...${NC}"

# Check if pyproject.toml uses local IATP path (for local development)
if grep -q "file://" pyproject.toml 2>/dev/null; then
    # Extract IATP path from pyproject.toml (macOS-compatible, no Perl regex)
    IATP_PATH_FROM_TOML=$(grep "file://" pyproject.toml | sed -E 's|.*file://([^"]+).*|\1|' | head -1)
    
    # If path is /tmp/IATP (Docker path), find the actual local IATP path
    if [ "$IATP_PATH_FROM_TOML" = "/tmp/IATP" ] || [ ! -d "$IATP_PATH_FROM_TOML" ]; then
        # Try to find local IATP path (common locations)
        if [ -d "/Users/eitanlavi/workspace/traia/IATP" ]; then
            IATP_PATH="/Users/eitanlavi/workspace/traia/IATP"
        elif [ -d "$(dirname $(pwd))/IATP" ]; then
            IATP_PATH="$(dirname $(pwd))/IATP"
        elif [ -d "$HOME/workspace/traia/IATP" ]; then
            IATP_PATH="$HOME/workspace/traia/IATP"
        elif [ -n "$LOCAL_IATP_PATH" ] && [ -d "$LOCAL_IATP_PATH" ]; then
            IATP_PATH="$LOCAL_IATP_PATH"
        else
            IATP_PATH=""
        fi
    else
        IATP_PATH="$IATP_PATH_FROM_TOML"
    fi
    
    if [ -n "$IATP_PATH" ] && [ -d "$IATP_PATH" ]; then
        echo -e "${BLUE}📦 Using local IATP package: $IATP_PATH${NC}"
        # Copy IATP into build context for Docker (exclude .venv to save space!)
        mkdir -p .docker-iatp
        
        # Use rsync if available (much better), otherwise cp with find
        if command -v rsync &> /dev/null; then
            rsync -a --exclude='.venv' --exclude='__pycache__' --exclude='.git' --exclude='build' --exclude='dist' --exclude='*.egg-info' "$IATP_PATH/" .docker-iatp/IATP/
            echo -e "${BLUE}   Copied IATP to build context (excluded .venv, ${GREEN}saved ~900MB${BLUE})${NC}"
        else
            # Fallback: use cp but warn about size
            cp -r "$IATP_PATH" .docker-iatp/IATP
            # Try to remove .venv after copy
            rm -rf .docker-iatp/IATP/.venv .docker-iatp/IATP/__pycache__ .docker-iatp/IATP/.git 2>/dev/null
            echo -e "${BLUE}   Copied IATP to build context (cleaned .venv after copy)${NC}"
        fi
        # Temporarily update pyproject.toml to use Docker path
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i.bak 's|file://.*IATP|file:///tmp/IATP|g' pyproject.toml
        else
            sed -i.bak 's|file://.*IATP|file:///tmp/IATP|g' pyproject.toml
        fi
        docker build --no-cache -t $IMAGE_NAME .
        BUILD_EXIT_CODE=$?
        # Restore original pyproject.toml
        mv pyproject.toml.bak pyproject.toml
        rm -rf .docker-iatp
        if [ $BUILD_EXIT_CODE -ne 0 ]; then
            exit $BUILD_EXIT_CODE
        fi
    else
        echo -e "${YELLOW}⚠️  Local IATP path not found${NC}"
        echo -e "${YELLOW}   Falling back to published version (may fail if not published)${NC}"
        # If pyproject.toml has /tmp/IATP, replace with published version
        if grep -q "file:///tmp/IATP" pyproject.toml 2>/dev/null; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i.bak 's|file:///tmp/IATP|traia-iatp>=0.1.27|g' pyproject.toml
            else
                sed -i.bak 's|file:///tmp/IATP|traia-iatp>=0.1.27|g' pyproject.toml
            fi
            docker build --no-cache -t $IMAGE_NAME .
            BUILD_EXIT_CODE=$?
            mv pyproject.toml.bak pyproject.toml
            if [ $BUILD_EXIT_CODE -ne 0 ]; then
                exit $BUILD_EXIT_CODE
            fi
        else
            docker build --no-cache -t $IMAGE_NAME .
        fi
    fi
else
    # Using published version, normal build
    docker build --no-cache -t $IMAGE_NAME .
fi

# Run the container
echo -e "${BLUE}🏃 Starting container...${NC}"
# Use --env-file to load all variables from .env file
docker run -d \
    --name $CONTAINER_NAME \
    -p $HOST_PORT:$CONTAINER_PORT \
    --env-file .env \
    $IMAGE_NAME

# Wait for the server to start
echo -e "${YELLOW}⏳ Waiting for server to start...${NC}"
sleep 3

# Check if container is running
if ! docker ps | grep -q $CONTAINER_NAME; then
    echo -e "${RED}❌ Container failed to start. Checking logs:${NC}"
    docker logs $CONTAINER_NAME
    exit 1
fi

# Get container info
CONTAINER_ID=$(docker ps -q -f name=$CONTAINER_NAME)
CONTAINER_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONTAINER_ID)

# Output connection information
echo
echo -e "${GREEN}✅ Polymarket v2 MCP Server is running!${NC}"
echo
echo -e "${BLUE}📍 Connection Information:${NC}"
echo -e "   Local URL:        ${GREEN}http://localhost:${HOST_PORT}/mcp${NC}"
echo -e "   Container IP:     ${GREEN}${CONTAINER_IP}:${CONTAINER_PORT}${NC}"
echo -e "   Container Name:   ${GREEN}${CONTAINER_NAME}${NC}"
echo -e "   Container ID:     ${GREEN}${CONTAINER_ID:0:12}${NC}"
echo
echo -e "${BLUE}📝 Useful commands:${NC}"
echo -e "   View logs:        ${YELLOW}docker logs -f ${CONTAINER_NAME}${NC}"
echo -e "   Stop server:      ${YELLOW}docker stop ${CONTAINER_NAME}${NC}"
echo -e "   Remove container: ${YELLOW}docker rm ${CONTAINER_NAME}${NC}"
echo -e "   Shell access:     ${YELLOW}docker exec -it ${CONTAINER_NAME} /bin/bash${NC}"
echo
echo -e "${BLUE}🔌 MCP Server Endpoint:${NC}"
echo -e "   ${GREEN}http://localhost:${HOST_PORT}/mcp${NC}"
echo

# Check if the server is responding
echo -e "${YELLOW}🔍 Checking server health...${NC}"
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${HOST_PORT}/mcp" | grep -q "200\|404\|405"; then
    echo -e "${GREEN}✅ Server is responding!${NC}"
else
    echo -e "${YELLOW}⚠️  Server may still be starting up. Check logs with: docker logs -f ${CONTAINER_NAME}${NC}"
fi

# Cleanup: Restore pyproject.toml to use /tmp/IATP (git-committed version)
echo -e "${BLUE}🧹 Cleaning up...${NC}"
if grep -q "file:///Users/eitanlavi/workspace/traia/IATP" pyproject.toml 2>/dev/null; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|file:///Users/eitanlavi/workspace/traia/IATP|file:///tmp/IATP|g" pyproject.toml
    else
        sed -i "s|file:///Users/eitanlavi/workspace/traia/IATP|file:///tmp/IATP|g" pyproject.toml
    fi
    echo -e "${GREEN}✅ Restored pyproject.toml to git state${NC}"
fi 