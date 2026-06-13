# ============================================================
# Bách Khoa Toàn Thư Ops — AI Agent
# Deploy target: GreenNode AgentBase (HTTP runtime)
# ============================================================

FROM python:3.11-slim

# --- Metadata ---
LABEL maintainer="Merchant Operations Team"
LABEL description="Ops Encyclopedia AI Agent — Internal Knowledge Base"
LABEL version="1.0.0"

# --- System deps ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# --- App user (non-root for security) ---
RUN useradd --create-home --shell /bin/bash appuser

# --- Working directory ---
WORKDIR /app

# --- Python dependencies (cached layer) ---
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# --- Application code ---
COPY agent.py .
COPY frontend.html .

# --- Persistent data directory ---
# Mount a volume here on AgentBase: /app/data
RUN mkdir -p /app/data/uploads \
    && chown -R appuser:appuser /app

# --- Switch to non-root ---
USER appuser

# --- Environment defaults ---
# Override these via AgentBase Dashboard > Environment Variables
ENV PORT=8080 \
    DB_PATH=/app/data/ops.db \
    UPLOAD_DIR=/app/data/uploads \
    MAX_FILE_SIZE_MB=20 \
    JWT_EXPIRES_IN=8h \
    NODE_ENV=production \
    MODEL=claude-opus-4-5 \
    MAX_TOKENS=4096 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# --- Expose port ---
EXPOSE 8080

# --- Health check (used by AgentBase for liveness probing) ---
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# --- Start ---
CMD ["python", "agent.py"]
