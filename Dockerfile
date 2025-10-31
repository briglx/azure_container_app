FROM debian:12

ARG ARTIFACT_PATH=/app
ENV ARTIFACT_PATH=${ARTIFACT_PATH}
ARG RELEASE_VERSION=0.0.0
ENV RELEASE_VERSION=${RELEASE_VERSION}

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

RUN echo 'alias ll='"'"'ls $LS_OPTIONS -al'"'"'' >> ~/.bashrc

# Install Java and other dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
 && rm -rf /var/lib/apt/lists/*

# Install Java
RUN apt-get update && apt-get install -y openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy application files
RUN curl -L "${ARTIFACT_PATH}" -o /app/artifact.zip \
   && unzip /app/artifact.zip -d /app/ \
   && rm /app/artifact.zip

RUN chmod +x /app/*.bin
RUN ./*.bin 
ENTRYPOINT [ "/bin/bash" ]
