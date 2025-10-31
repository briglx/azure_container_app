FROM openjdk:21-slim-bullseye

ARG RELEASE_VERSION=0.0.0
ARG APP_INSTALLER_FILE=installer.bin
ARG APP_FILE=/opt/myapp/myapp
ARG APP_SETUP_ARGS="-install-license license.key"

# Set environment variables
ENV RELEASE_VERSION=${RELEASE_VERSION} \
    APP_INSTALLER_FILE=${APP_INSTALLER_FILE} \
    APP_FILE=${APP_FILE} \
    APP_SETUP_ARGS=${APP_SETUP_ARGS} \
    DEBIAN_FRONTEND=noninteractive 

RUN echo 'alias ll='"'"'ls $LS_OPTIONS -al'"'"'' >> ~/.bashrc

# Set working directory
WORKDIR /app

# Copy application files
COPY temp/* /app

# Install binary
RUN chmod +x /app/${APP_INSTALLER_FILE}
RUN ./$APP_INSTALLER_FILE
RUN rm -f /app/${APP_INSTALLER_FILE}

# Run setup task
RUN ${APP_FILE} $APP_SETUP_ARGS

ENTRYPOINT [ "/bin/bash" ]
# ENTRYPOINT [ "${APP_FILE}" ]
# CMD ["--help"]