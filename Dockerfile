FROM alpine:3.22

# renovate: datasource=repology depName=alpine_3_22/nut versioning=loose
ENV NUT_VERSION="2.8.2-r2"

RUN apk add --no-cache nut="${NUT_VERSION}" shadow && \
    [ -d /etc/nut ] && find /etc/nut/ -type f -exec mv {} {}.sample \; || false && \
    mkdir -p /var/run/nut && \
    chown nut:nut /var/run/nut && \
    chmod 700 /var/run/nut && \
    # fix some missing links to .so files, which are required to run 'nut-scanner' utility
    find /usr/lib/ -type f -name 'libusb*' -exec ln -sf {} /usr/lib/libusb-1.0.so \; || false && \
    find /usr/lib/ -type f -name 'libnetsnmp*' -exec ln -sf {} /usr/lib/libnetsnmp.so \; || false && \
    find /usr/lib/ -type f -name 'libupsclient*' -exec ln -sf {} /usr/lib/libupsclient.so \; || false && \
    find /usr/lib/ -type f -name 'libneon*' -exec ln -sf {} /usr/lib/libneon.so \; || false

COPY entrypoint.sh /entrypoint.sh

RUN chmod 755 /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 3493
