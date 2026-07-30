FROM python:3.12-slim AS builder

# Install uv for fast dependency management
COPY --from=ghcr.io/astral-sh/uv:0.11.8 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_SYSTEM_PYTHON=1 \
    UV_PROJECT_ENVIRONMENT=/usr/local

WORKDIR /app

# Install build-time system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       libpq-dev \
       libffi-dev \
       libxml2-dev \
       libxslt1-dev \
       libjpeg-dev \
       libz-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files first for better layer caching
COPY pyproject.toml uv.lock ./

# Install dependencies (no project code yet)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project --no-dev

# Copy project source
COPY . .

# Install the project itself
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev


FROM python:3.12-slim

# Install only runtime system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       libpq5 \
       libgdk-pixbuf-2.0-0 \
       liblcms2-2 \
       libopenjp2-7 \
       libtiff6 \
       libwebp7 \
       shared-mime-info \
       libmagic1 \
       media-types \
       curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd --gid 1000 saleor \
    && useradd --uid 1000 --gid saleor --shell /bin/bash --create-home saleor

WORKDIR /app

# Copy installed Python packages and project from builder
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder --chown=saleor:saleor /app /app

# Create required directories with proper ownership
RUN mkdir -p /app/media /app/static \
    && chown -R saleor:saleor /app

USER saleor

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DJANGO_SETTINGS_MODULE=saleor.settings

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8000/health/ || exit 1

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]