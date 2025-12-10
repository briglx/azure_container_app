# FROM openjdk:21-slim-bullseye
FROM mcr.microsoft.com/openjdk/jdk:21-ubuntu

# hadolint ignore=SC2016
RUN echo 'alias ll='"'"'ls $LS_OPTIONS -al'"'"'' >> ~/.bashrc

# Install dependencies
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
        jq \
        vim \
    && rm -rf /var/lib/apt/lists/*

ARG RELEASE_VERSION=0.0.0
ARG APP_INSTALLER_FILE=installer.bin
ARG APP_FILE=/opt/myapp/myapp
ARG APP_SETUP_ARGS="-install-license license.key"
ARG APP_ALIAS=myapp

# Set environment variables
ENV RELEASE_VERSION=${RELEASE_VERSION} \
    APP_INSTALLER_FILE=${APP_INSTALLER_FILE} \
    APP_FILE=${APP_FILE} \
    APP_SETUP_ARGS=${APP_SETUP_ARGS} \
    APP_ALIAS=${APP_ALIAS} \
    DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR /app

# Copy application files
COPY .artifact_cache/* /app

# Install binary + setup + symlink
RUN set -eux; \
    chmod +x "/app/${APP_INSTALLER_FILE}"; \
    "/app/${APP_INSTALLER_FILE}"; \
    rm -f "/app/${APP_INSTALLER_FILE}"; \
    "${APP_FILE}" ${APP_SETUP_ARGS}; \
    ln -s "${APP_FILE}" "/usr/local/bin/${APP_ALIAS}"

COPY ./pipeline_app/entrypoint.sh ./pipeline_app/build_args.sh /app/

# ENTRYPOINT [ "./entrypoint.sh" ]
CMD ["tail", "-f", "/dev/null"]
