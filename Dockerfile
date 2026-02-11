# Use Python 3.12 slim image as base
FROM python:3.12-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
RUN chmod +x /usr/local/bin/uv

# Create non-root user
RUN useradd -m -u 1000 appuser

# Create app directory and set ownership
RUN mkdir -p /app && chown -R appuser:appuser /app

# Set working directory
WORKDIR /app

# Switch to non-root user
USER appuser

# Copy project files
COPY --chown=appuser:appuser . .

# Copy IATP package if available (for local development only)
# This Dockerfile works for both local and remote deployments:
# 
# LOCAL DEPLOYMENT (via run_local_docker.sh):
#   - run_local_docker.sh detects local IATP path in pyproject.toml
#   - Copies IATP to .docker-iatp/IATP before building
#   - Temporarily modifies pyproject.toml to use file:///tmp/IATP
#   - Dockerfile finds .docker-iatp/IATP and copies it to /tmp/IATP
#   - uv install uses the local IATP from /tmp/IATP
#
# REMOTE DEPLOYMENT (Cloud Run, etc.):
#   - .docker-iatp/IATP does NOT exist in build context
#   - pyproject.toml has published version (traia-iatp>=0.1.27)
#   - Dockerfile skips IATP copy, uv install uses published package
#
RUN if [ -d .docker-iatp/IATP ]; then \
        cp -r .docker-iatp/IATP /tmp/IATP && \
        echo "Using local IATP package (local development mode)"; \
    else \
        echo "Using published IATP package (remote deployment mode)"; \
    fi

# Install Python dependencies
# - Local mode: pyproject.toml references file:///tmp/IATP (set by run_local_docker.sh)
# - Remote mode: pyproject.toml references traia-iatp>=0.1.27 (from template)
RUN uv venv .venv && \
    uv pip install -r pyproject.toml

# Set environment variables
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH=/app
ENV HOST=0.0.0.0
ENV PYTHONUNBUFFERED=1
ENV UV_SYSTEM_PYTHON=1
ENV STAGE=MAINNET
ENV LOG_LEVEL=INFO

# Health check - uses dedicated health endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:${PORT:-8080}/health || exit 1

# Expose port (uses PORT environment variable with default)
EXPOSE ${PORT:-8080}

# Run the application
CMD ["uv", "run", "python", "server.py"] 