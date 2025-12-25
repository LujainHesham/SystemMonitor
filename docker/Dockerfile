FROM ubuntu:22.04

# Set timezone (EET) and prevent interactive apt prompts
ENV DEBIAN_FRONTEND=noninteractive TZ=Africa/Cairo

# Install tzdata non-interactively first, then core dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends tzdata && \
    ln -fs /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    apt-get install -y --no-install-recommends \
        lm-sensors \
        smartmontools \
        htop \
        iotop \
        iproute2 \
        net-tools \
        bc \
        curl \
        wget \
        pciutils \
        usbutils \
        dmidecode \
        sysstat \
        jq \
        python3 \
        wkhtmltopdf \
        qrencode \
        xfonts-base \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy scripts
COPY scripts/monitor.sh /app/scripts/monitor.sh
COPY scripts/install.sh /app/scripts/install.sh

# Make script executable
RUN chmod +x /app/scripts/monitor.sh

# Create necessary directories
RUN mkdir -p /app/reports /app/logs /data

# Default environment variables (includes PDF/QR/HTTP server)
ENV GENERATE_HTML=true \
    BRIEF_MODE=false \
    RUN_INTERVAL_SECONDS=60 \
    CPU_SAMPLE_SECONDS=5 \
    VERBOSE=false \
    USE_WINDOWS_INTEGRATION=true \
    WINDOWS_TEMPS_CSV=/data/hwinfo_temps.csv \
    HOST_METRICS_JSON=/data/host_metrics.json \
    CSV_MAX_CORES=6 \
    CSV_DELIM=, \
    ENABLE_PDF=true \
    ENABLE_QR=true \
    ENABLE_HTTP_SERVER=true \
    HTTP_PORT=8088 \
    REPORT_BASE_URL=http://localhost:8088

EXPOSE 8088

CMD ["/app/scripts/monitor.sh", "--interval", "60"]