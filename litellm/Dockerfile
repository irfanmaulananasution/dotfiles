FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "fastapi>=0.136.3,<0.140.7" && \
    pip install --no-cache-dir litellm[proxy] && \
    pip install --no-cache-dir \
        openai \
        opentelemetry-api \
        opentelemetry-sdk \
        opentelemetry-exporter-otlp \
        prisma \
        psycopg2-binary

COPY docker-entrypoint.sh /app/entrypoint.sh
COPY config.yaml /app/config.yaml
COPY monkey_patch.py /app/monkey_patch.py
COPY otel_utils.py /app/otel_utils.py
RUN chmod +x /app/entrypoint.sh

ENV OTEL_ENDPOINT=http://phoenix:4317

EXPOSE 4000

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["--port", "4000", "--config", "/app/config.yaml"]
