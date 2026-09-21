FROM alpine:3.23 AS build
ARG JOPLIN_VERSION
RUN apk add --no-cache nodejs npm
RUN NPM_CONFIG_PREFIX=/app/joplin npm install --omit=dev --no-audit --no-fund -g joplin@${JOPLIN_VERSION} \
    && find /app/joplin -type f \( -name '*.map' -o -name '*.md' -o -name '*.d.ts' \) -delete \
    && rm -rf /root/.npm /tmp/*

FROM alpine:3.23
COPY --from=build /app/joplin /app/joplin
RUN apk add --no-cache nodejs socat jq curl \
    && ln -s /app/joplin/bin/joplin /usr/bin/joplin

COPY entrypoint.sh /usr/bin/entrypoint.sh
COPY gateway.sh /usr/local/bin/gateway.sh
RUN chmod +x /usr/bin/entrypoint.sh /usr/local/bin/gateway.sh

EXPOSE 41185
ENTRYPOINT ["sh", "/usr/bin/entrypoint.sh"]
