FROM alpine:3.7

RUN apk add --no-cache curl ca-certificates bash \
    && curl -fsSL https://github.com/krallin/tini/releases/download/v0.18.0/tini-muslc-amd64 -o /usr/bin/tini \
    && curl -fsSL http://repo.xcalar.net/deps/caddy_0.11.0-103_linux_amd64.tar.gz | tar zxvf - -C /usr/bin/ \
    && chmod +x /usr/bin/tini

WORKDIR /app
ADD ["petname","petname.cgi","Caddyfile", "/app/"]


EXPOSE 2015
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/bin/caddy"]
