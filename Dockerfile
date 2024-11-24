FROM alpine:3.20

# renovate: datasource=repology depName=alpine_3_20/nut versioning=loose
ENV NUT_VERSION="2.8.2-r0"

RUN apk add --no-cache nut="${NUT_VERSION}" && \
    [ -d /etc/nut ] && find /etc/nut/ -type f -exec mv {} {}.sample \; || false

COPY entrypoint.sh /entrypoint.sh

RUN chmod 755 /entrypoint.sh

RUN mkdir -p /var/run/nut && \
    chown nut:nut /var/run/nut && \
    chmod 700 /var/run/nut

USER nut

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 3493
