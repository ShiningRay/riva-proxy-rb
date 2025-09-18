# Multi-stage build for riva-proxy-rb
# Builder image compiles native gems (grpc, etc.)
ARG RUBY_VERSION=3.4
FROM ruby:${RUBY_VERSION}-slim AS builder

# Install build tools and headers needed for native gems
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
     build-essential git pkg-config libssl-dev protobuf-compiler ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Ruby gems first to leverage Docker layer caching
COPY Gemfile Gemfile.lock ./
ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_WITHOUT="development:test"
RUN bundle install

# Bring in the full application
COPY . .

# Runtime image kept slim
FROM ruby:${RUBY_VERSION}-slim AS runner

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV APP_HOME=/app \
    BUNDLE_PATH=/bundle \
    BUNDLE_WITHOUT="development:test" \
    RACK_ENV=production

WORKDIR /app

# Copy installed gems and app contents from builder
COPY --from=builder /bundle /bundle
COPY --from=builder /app /app

# Create a non-root user
RUN useradd -m -u 10001 appuser
USER appuser

# Default listening port
EXPOSE 8080

# Configurable runtime options via environment variables
# You can override these when running the container
ENV HOST=0.0.0.0 \
    PORT=8080 \
    RIVA_HOST=localhost \
    RIVA_PORT=50051 \
    RIVA_TIMEOUT=30 \
    SSL_CERT= \
    SSL_KEY= \
    SSL_VERIFY_MODE=none

# By default, start the WebSocket proxy in WS mode. For WSS, override CMD to add
#   --ssl-cert $SSL_CERT --ssl-key $SSL_KEY --ssl-verify-mode $SSL_VERIFY_MODE
# Example:
#   docker run -p 8081:8081 -e HOST=0.0.0.0 -e PORT=8081 \
#     -v $(pwd)/certs/server.crt:/app/certs/server.crt \
#     -v $(pwd)/certs/server.key:/app/certs/server.key \
#     IMAGE_NAME \
#     sh -lc 'bundle exec ruby bin/websocket_proxy --host $HOST --port $PORT --ssl-cert /app/certs/server.crt --ssl-key /app/certs/server.key --ssl-verify-mode $SSL_VERIFY_MODE'

# Use shell form to expand environment variables in arguments
CMD bundle exec ruby bin/websocket_proxy --host $HOST --port $PORT