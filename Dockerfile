# =======================================================================================
# DISCLAIMER:
# This setup is only for demo purposes and not intended to be used anywhere in production
# =======================================================================================
# 
# > Build the image <
# docker build \
#   -t databricks-jobs-observability \
#   --build-arg TOKEN=$DATABRICKS_TOKEN \
#   --build-arg HOST=$DATABRICKS_HOST \
#   .
# 
# 
# > Run the container <
# docker run \
#   -p 9090:9090 \
#   -p 3000:3000 \
#   databricks-jobs-observability
# 
# Open the browser
# - http://localhost:9090/ for the Prometheus UI
# - http://localhost:3000/ for Grafana (credentials are admin/admin)
# 
FROM ubuntu:20.04

ARG TOKEN
ARG HOST

ARG USERNAME=databricks
ARG USER_UID=1000
ARG USER_GID=$USER_UID

ARG PROMETHEUS_VERSION=2.32.1
ARG PROMETHEUS_CHECKSUM=f08e96d73330a9ee7e6922a9f5b72ea188988a083bbfa9932359339fcf504a74

RUN set -ex && \
    apt-get update && \
    apt-get install -y software-properties-common wget && \
    # grafana
    wget -q -O - https://packages.grafana.com/gpg.key | apt-key add - && \
    echo "deb https://packages.grafana.com/oss/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list && \
    apt-get update && \
    apt-get install -y grafana && \
    # clean up
    rm -fr /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    apt-get clean

RUN echo "\
apiVersion: 1\n\
\n\
datasources:\n\
  - name: Prometheus\n\
    type: prometheus\n\
    access: proxy\n\
    orgId: 1\n\
    uid: internal_prometheus\n\
    url: http://localhost:9090\n\
    withCredentials: false\n\
    isDefault: true\n\
    version: 1\n\
    editable: false\n"\
>> /usr/share/grafana/conf/provisioning/datasources/$USERNAME.yaml

WORKDIR /downloads
ARG PROMETHEUS_ARCHIVE=prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
RUN wget "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROMETHEUS_ARCHIVE}" && \
    echo "${PROMETHEUS_CHECKSUM} ${PROMETHEUS_ARCHIVE}" | sha256sum -c - && \
    mkdir -p /etc/prometheus && mkdir /prometheus && \
    tar -xvf $PROMETHEUS_ARCHIVE --strip-components 1 --exclude=prometheus.yml --directory /etc/prometheus && \
    ln -s /etc/prometheus/prometheus /usr/local/bin/prometheus && \
    ln -s /etc/prometheus/promtool /usr/local/bin/promtool && \
    echo "\
global:\n\
  scrape_interval: 15s\n\
  scrape_timeout: 10s\n\
  evaluation_interval: 15s\n\
scrape_configs:\n\
# - job_name: prometheus\n\
#   scrape_interval: 5s\n\
#   scrape_timeout: 1s\n\
#   metrics_path: /metrics\n\
#   scheme: http\n\
#   static_configs:\n\
#   - targets:\n\
#     - localhost:9090\n\
- job_name: databricks\n\
  scrape_interval: 30s\n\
  scrape_timeout: 5s\n\
  metrics_path: /api/2.0/jobs-observability/metrics\n\
  params:\n\
    granularity: ['workspace']\n\
  scheme: https\n\
  bearer_token: ${TOKEN}\n\
  static_configs:\n\
  - targets:\n\
    - ${HOST}\n"\
>> /etc/prometheus/prometheus.yml

RUN echo '#!/bin/bash\n\
prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus &  \n\
PID_LIST+=" $!"\n\
\n\
grafana-server \
    --homepath=/usr/share/grafana \
    --config=/usr/share/grafana/conf/defaults.ini & \n\
PID_LIST+=" $!"\n\
\n\
trap "kill $PID_LIST" SIGINT\n\
wait $PID_LIST\n'\
>> /usr/local/bin/entrypoint.sh && \
chmod +x /usr/local/bin/entrypoint.sh

RUN groupadd --gid $USER_GID $USERNAME && \
    useradd -s /bin/bash --uid $USER_UID --gid $USERNAME -m $USERNAME && \
    chown -R $USERNAME:$USERNAME \
        /usr/sbin/grafana-server /usr/share/grafana \
        /etc/prometheus/ /prometheus

WORKDIR /
USER $USERNAME
EXPOSE 3000 9090
ENTRYPOINT ["entrypoint.sh"]