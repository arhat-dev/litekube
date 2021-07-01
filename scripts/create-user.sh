#!/bin/sh

set -ex

case "$1" in
debian)
  addgroup --system --gid 1000 litekube
  adduser --system --shell "$(which nologin)" \
    --disabled-password --no-create-home \
    --uid 1000 --gid 1000 litekube
  ;;
alpine)
  addgroup -S -g 1000 litekube
  adduser -s "$(which nologin)" -S -D -H -u 1000 -G litekube litekube
  ;;
esac
