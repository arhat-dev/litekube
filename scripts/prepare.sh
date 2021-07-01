#!/bin/sh

set -ex

_prepare_debian() {
  addgroup --system --gid 1000 litekube
  adduser --system --shell "$(which nologin)" \
    --disabled-password --no-create-home \
    --uid 1000 --gid 1000 litekube
  apt-get update
  apt-get install -y keepalived
  rm -rf /var/lib/apt/lists/*
}

_prepare_alpine() {
  addgroup -S -g 1000 litekube
  adduser -s "$(which nologin)" -S -D -H -u 1000 -G litekube litekube
  apk add --no-cache keepalived
}

case "$1" in
debian)
  _prepare_debian
  ;;
alpine)
  _prepare_alpine
  ;;
esac
