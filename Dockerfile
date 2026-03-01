### FRONT BUILD START ###
FROM --platform=$BUILDPLATFORM node:16-alpine AS front
WORKDIR /app
ARG REACT_APP_SERVER_HOST='.'
ARG REACT_APP_TMDB_API_KEY=''
ARG PUBLIC_URL=''
ENV REACT_APP_SERVER_HOST=$REACT_APP_SERVER_HOST
ENV REACT_APP_TMDB_API_KEY=$REACT_APP_TMDB_API_KEY
ENV PUBLIC_URL=$PUBLIC_URL
COPY ./web/package.json ./web/yarn.lock ./
RUN yarn install
COPY ./web .
RUN yarn run build
### FRONT BUILD END ###

### BUILD TORRSERVER MULTIARCH START ###
FROM --platform=$BUILDPLATFORM golang:1.26.0-alpine AS builder
COPY . /opt/src
COPY --from=front /app/build /opt/src/web/build
WORKDIR /opt/src
ARG TARGETOS
ARG TARGETARCH
ENV GOOS=$TARGETOS
ENV GOARCH=$TARGETARCH
RUN apk add --update g++ \
    && go run gen_web.go \
    && cd server \
    && go mod tidy \
    && go clean -i -r -cache \
    && go build -ldflags '-w -s' -o "torrserver" ./cmd
### BUILD TORRSERVER MULTIARCH END ###

### UPX COMPRESSING START ###
FROM ubuntu AS compressed
COPY --from=builder /opt/src/server/torrserver ./torrserver
RUN apt update && apt install -y upx-ucl && upx --best --lzma ./torrserver
### UPX COMPRESSING END ###

### BUILD MAIN IMAGE START ###
FROM alpine
ENV TS_CONF_PATH="/opt/ts/config"
ENV TS_LOG_PATH="/opt/ts/log"
ENV TS_TORR_DIR="/opt/ts/torrents"
ENV TS_PORT=8090
ENV GODEBUG=madvdontneed=1
COPY --from=compressed ./torrserver /usr/bin/torrserver

RUN echo '#!/bin/sh' > /docker-entrypoint.sh && \
    echo 'set -e' >> /docker-entrypoint.sh && \
    echo '[ -n "$TS_PORT" ] && PORT_OPT="--port $TS_PORT"' >> /docker-entrypoint.sh && \
    echo '[ -n "$TS_HTTPAUTH" ] && AUTH_OPT="--httpauth $TS_HTTPAUTH"' >> /docker-entrypoint.sh && \
    echo '[ -n "$TS_CONF_PATH" ] && CONF_OPT="--confpath $TS_CONF_PATH"' >> /docker-entrypoint.sh && \
    echo '[ -n "$TS_TORR_DIR" ] && TORR_OPT="--torrpath $TS_TORR_DIR"' >> /docker-entrypoint.sh && \
    echo '[ -n "$TS_SSL" ] && SSL_OPT="--ssl $TS_SSL"' >> /docker-entrypoint.sh && \  # Добавил SSL
    echo 'exec /usr/bin/torrserver $PORT_OPT $AUTH_OPT $CONF_OPT $TORR_OPT $SSL_OPT "$@"' >> /docker-entrypoint.sh && \
    chmod +x /docker-entrypoint.sh
RUN apk add --no-cache --update ffmpeg
VOLUME /opt/ts
EXPOSE 8090
USER 1000:1000
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["--logpath", "/opt/ts/log"]
### BUILD MAIN IMAGE END ###
