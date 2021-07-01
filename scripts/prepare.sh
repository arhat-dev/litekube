#!/bin/sh

set -ex

setup_sudoer() {
  cat <<EOF > /etc/sudoers.d/100-keepalived
keepalived_script ALL=NOPASSWD: /usr/local/bin/entrypoint*
EOF
}

_prepare_debian() {
  apt-get update
  apt-get install -y keepalived sudo

  adduser --system --shell "$(which nologin)" \
    --disabled-password --no-create-home keepalived_script

  setup_sudoer

  rm -rf /var/lib/apt/lists/*
}

_prepare_alpine() {
  apk add --no-cache keepalived sudo

  adduser -s "$(which nologin)" -S -D -H keepalived_script

  setup_sudoer
}

case "$1" in
debian)
  _prepare_debian
  ;;
alpine)
  _prepare_alpine
  ;;
esac
