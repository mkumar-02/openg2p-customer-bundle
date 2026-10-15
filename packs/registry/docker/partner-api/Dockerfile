ARG RP_VERSION={{RP_VERSION}}
FROM openg2p/openg2p-registry-partner-api:${RP_VERSION}

ENV REGISTRY_EXTENSION_MODULE={{EXTENSION_MODULE}}

COPY {{EXTENSION_DIR}}/ /app/{{EXTENSION_DIR}}/
RUN pip install --no-cache-dir /app/{{EXTENSION_DIR}}
