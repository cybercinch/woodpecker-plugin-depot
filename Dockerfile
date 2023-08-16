FROM alpine:3.16
ARG DEPOT_VERSION=2.30.0

RUN apk update && \
    apk add --no-cache bash \
                       curl \
                       docker-cli

RUN curl -L https://depot.dev/install-cli.sh | DEPOT_INSTALL_DIR=/usr/local/bin sh -s ${DEPOT_VERSION}
ADD files/docker-entrypoint.sh /docker-entrypoint.sh

ENV PLUGIN_REPOHOST=docker.io \
    PLUGIN_PLATFORMS="linux/amd64,linux/arm64" \
    PLUGIN_DOCKERFILE="Dockerfile"
CMD ["/docker-entrypoint.sh"]