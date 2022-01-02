# Original is at https://github.com/opensearch-project/opensearch-build/blob/main/release/docker/dockerfiles/opensearch.al2.dockerfile

# SPDX-License-Identifier: Apache-2.0
#
# The OpenSearch Contributors require contributions made to
# this file be licensed under the Apache-2.0 license or a
# compatible open source license.
#
# Modifications Copyright OpenSearch Contributors. See
# GitHub history for details.


# Copyright 2021 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.


# This dockerfile generates an AmazonLinux-based image containing an OpenSearch installation.
# It assumes that the working directory contains four files: an OpenSearch tarball (opensearch.tgz), log4j2.properties, opensearch.yml, opensearch-docker-entrypoint.sh, opensearch-onetime-setup.sh.
# Build arguments:
#   VERSION: Required. Used to label the image.
#   BUILD_DATE: Required. Used to label the image. Should be in the form 'yyyy-mm-ddThh:mm:ssZ', i.e. a date-time from https://tools.ietf.org/html/rfc3339. The timestamp must be in UTC.
#   UID: Optional. Specify the opensearch userid. Defaults to 1000.
#   GID: Optional. Specify the opensearch groupid. Defaults to 1000.
#   OPENSEARCH_HOME: Optional. Specify the opensearch root directory. Defaults to /usr/share/opensearch.


########################### Stage 0 ########################
FROM amazonlinux:2 AS linux_stage_0

ARG UPSTREAM_VERSION=1.2.3
ARG UPSTREAM_BRANCH=main


ARG UID=1000
ARG GID=1000
ARG OPENSEARCH_HOME=/usr/share/opensearch

# Update packages
# Install the tools we need: tar and gzip to unpack the OpenSearch tarball, and shadow-utils to give us `groupadd` and `useradd`.
RUN yum update -y && yum install -y tar gzip shadow-utils wget && yum clean all

# Create an opensearch user, group, and directory
RUN groupadd -g $GID opensearch && \
    adduser -u $UID -g $GID -d $OPENSEARCH_HOME opensearch && \
    mkdir /tmp/opensearch

# Download the minimal tarball from directly from OS
# amd64: https://artifacts.opensearch.org/releases/core/opensearch/1.0.0/opensearch-min-1.0.0-linux-x64.tar.gz
# arm64: https://artifacts.opensearch.org/releases/core/opensearch/1.0.0/opensearch-min-1.0.0-linux-arm64.tar.gz

RUN [[ "$(arch)" == "x86_64" ]] && export OS_ARCH="x64"; [[ "$(arch)" == "aarch64" ]] && export OS_ARCH="arm64"; echo "OS_ARCH: $OS_ARCH"; \
    wget --progress=dot:giga -O "/tmp/opensearch/opensearch.tgz" \
    https://artifacts.opensearch.org/releases/core/opensearch/${UPSTREAM_VERSION}/opensearch-min-${UPSTREAM_VERSION}-linux-${OS_ARCH}.tar.gz
RUN tar -xzf /tmp/opensearch/opensearch.tgz -C $OPENSEARCH_HOME --strip-components=1 && rm -rf /tmp/opensearch

# I hacked this to avoid plugins, mostly performance analyzer stuff
ADD opensearch-docker-entrypoint.sh $OPENSEARCH_HOME/

# This comes straight from the repo for now
ADD https://raw.githubusercontent.com/opensearch-project/opensearch-build/${UPSTREAM_BRANCH}/docker/release/config/opensearch/log4j2.properties $OPENSEARCH_DASHBOARDS_HOME/config/
ADD https://raw.githubusercontent.com/opensearch-project/opensearch-build/${UPSTREAM_BRANCH}/docker/release/config/opensearch/opensearch.yml $OPENSEARCH_HOME/config/
# Make it executable, since it's coming over http.
RUN chmod +x $OPENSEARCH_HOME/*.sh


########################### Stage 1 ########################
# Copy working directory to the actual release docker images
FROM amazonlinux:2

ARG UID=1000
ARG GID=1000
ARG OPENSEARCH_HOME=/usr/share/opensearch

# Copy from Stage0
COPY --from=linux_stage_0 $OPENSEARCH_HOME $OPENSEARCH_HOME
WORKDIR $OPENSEARCH_HOME

# Update packages
# Install the tools we need: tar and gzip to unpack the OpenSearch tarball, and shadow-utils to give us `groupadd` and `useradd`.
RUN yum update -y && yum install -y tar gzip shadow-utils && yum clean all

# Create an opensearch user, group
RUN groupadd -g $GID opensearch && \
    adduser -u $UID -g $GID -d $OPENSEARCH_HOME opensearch

# Setup OpenSearch, except: './opensearch-onetime-setup.sh && \'
RUN mkdir -p /usr/share/opensearch/data && chown -R $UID:$GID $OPENSEARCH_HOME && \
    echo "export JAVA_HOME=$OPENSEARCH_HOME/jdk" >> /etc/profile.d/java_home.sh

# Change user. WARNING: make sure fsGroup securityPolicy matches this.
USER $UID

# Expose ports for the opensearch service (9200 for HTTP and 9300 for internal transport) and performance analyzer (9600 for the agent and 9650 for the root cause analysis component)
EXPOSE 9200 9300 9600 9650

# No labels, that is done via Github Actions workflow directly

# CMD to run
CMD ["./opensearch-docker-entrypoint.sh"]
