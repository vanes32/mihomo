# Этап сборки бинарника
FROM --platform=$BUILDPLATFORM busybox:uclibc AS downloader
ARG TARGETARCH

# Скачиваем бинарник прямо через wget из busybox
RUN mkdir /out && \
    if [ "$TARGETARCH" = "arm64" ]; then \
        wget -O /out/mihomo.gz https://github.com/MetaCubeX/mihomo/releases/download/v1.19.18/mihomo-linux-arm64-v1.19.18.gz; \
    elif [ "$TARGETARCH" = "arm" ]; then \
        wget -O /out/mihomo.gz https://github.com/MetaCubeX/mihomo/releases/download/v1.19.18/mihomo-linux-armv7-v1.19.18.gz; \
    elif [ "$TARGETARCH" = "amd64" ]; then \
        wget -O /out/mihomo.gz https://github.com/MetaCubeX/mihomo/releases/download/v1.19.18/mihomo-linux-amd64-compatible-v1.19.18.gz; \
    else \
        echo "Unsupported architecture: $TARGETARCH" && exit 1; \
    fi && \
    gunzip /out/mihomo.gz && \
    chmod +x /out/mihomo

# Минимальный финальный образ
FROM alpine:3.18

# Установка минимальных пакетов
RUN apk add --no-cache iptables

# Установка переменной окружения
ENV DISABLE_NFTABLES=1

# Копируем бинарник и скрипт
COPY --from=downloader /out/mihomo /mihomo

# Стартовый скрипт
CMD ["/bin/sh", "-c", "./mihomo"]
