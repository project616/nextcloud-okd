FROM redis-base:latest
#FROM docker.io/redis:3.2.0-alpine

MAINTAINER fmount <fmount9@autistici.org>

ADD scripts/run_redis.sh /tmp/run_redis.sh

RUN apk update && apk add vim curl jq util-linux bash
RUN chmod +x /tmp/run_redis.sh

RUN mkdir -p /var/lib/redis

EXPOSE 6379 16379

HEALTHCHECK --interval=30s --timeout=5s --retries=15\
  CMD redis-cli -h 127.0.0.1 "ping" == "PONG" || exit 1

ONBUILD RUN apk update

#ENTRYPOINT ["/tmp/run_redis.sh"]
ENTRYPOINT ["sh -c"]
