#!/bin/sh

_restore() {
  if [ ! -f /data/litestream.yaml ]; then
    # no litestream config, no restore
    exit 0
  fi

  litestream restore -v \
    -config /data/litestream.yaml \
    -if-db-not-exists \
    -if-replica-exists \
    /data/db.sqlite
}

_run() {
  s_config_file="$(mktemp)"

  if [ -f /data/litestream.yaml ]; then
    cat <<EOF >> "${s_config_file}"
[program:litestream]
autostart=true
autorestart=true
user=litekube
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
command=/usr/local/bin/litestream replicate -config /data/litestream.yaml
EOF
  fi

  cat <<EOF >> "${s_config_file}"
[program:kine]
autostart=true
autorestart=true
user=litekube
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
command=/usr/local/bin/kine \
  --endpoint /data/db.sqlite \
  --ca-file /etcd-certs/ca.crt \
  --cert-file /etcd-certs/server.crt \
  --key-file /etcd-certs/server.key \
  --listen-address tcp://localhost:2379
EOF

  # shellcheck disable=SC1091
  . /litekube/.venv/bin/activate

  exec supervisord --nodaemon --configuration "${s_config_file}"
}

case "$1" in
restore)
  _restore
  ;;
run)
  _run
  ;;
*)
  # shellcheck disable=SC2068
  exec $@
  ;;
esac
