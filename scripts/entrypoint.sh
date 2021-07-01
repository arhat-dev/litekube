#!/bin/sh

set -ex

litestream_config_file="/data/litestream.yaml"
supervisord_config_file="/data/supervisord.conf"
supervisord_server_listen="localhost:19001"
supervisorctl_server_url="http://${supervisord_server_listen}"

master_lock_file="/data/.vrrp_master.lock"
main_db="/data/db.sqlite"
restore_db="/data/restore-db.sqlite"

instance_lock="/data/litekube.lock"

_retore_main_db() {
  # when _restore_latest was called, we are not in vrrp MASTER state

  if litestream restore -v \
    -config "${litestream_config_file}" \
    -if-replica-exists \
    "${main_db}" ; then
    # db did not exist, and restored successfully
    return
  fi

  # db already exists, retore to temporary db

  if [ -f "${restore_db}" ]; then
    echo "restore ongoing, operation canceled"
    return 1
  fi

  if ! litestream restore -v \
    -config "${litestream_config_file}" \
    -if-replica-exists \
    -o "${restore_db}" \
    "${main_db}"; then
    echo "restore failed"
    return 1
  fi

  # restored, move to main db
  # TODO: ensure main db is not open
  if ! mv "${restore_db}" "${main_db}"; then
    rm -f "${restore_db}" || true
    return 1
  fi
}

_run() {
  trap _cleanup EXIT

  kine_debug_flag=""
  if [ "${DEBUG_KINE}" = "true" ]; then
    kine_debug_flag="--debug"
  fi

  cat <<EOF >"${supervisord_config_file}"
[supervisord]
nodaemon = true
logfile = /dev/stderr
logfile_maxbytes = 0
pidfile = /var/lib/supervisord/pid

[supervisorctl]
serverurl = ${supervisorctl_server_url}

[inet_http_server]
port = ${supervisord_server_listen}

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[eventlistener:fatal-exit]
process_name=%(program_name)s
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
autostart = true
autorestart = true
startsecs = 0
startretries = 0
events = PROCESS_STATE_FATAL
command=$(which sh) -c
  'while true; do printf "READY\n"; read line; kill -SIGINT \$(cat /var/lib/supervisord/pid); printf "RESULT 2\n"; printf "OK"; done'

[program:replication]
process_name=%(program_name)s
autostart = false
autorestart = true
user = root
startsecs = 10
startretries = 10
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
command = /usr/local/bin/litestream replicate
  -config ${litestream_config_file}

[program:keepalived]
process_name=%(program_name)s
autostart = true
autorestart = true
user = root
startsecs = 5
startretries = 3
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
command = $(which keepalived) --dont-fork
  -f /data/keepalived.conf
  --log-console
  --log-detail

[program:kine]
process_name=%(program_name)s
autostart = false
autorestart = true
user = root
startsecs = 5
startretries = 3
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
command = /usr/local/bin/kine ${kine_debug_flag}
  --endpoint sqlite://${main_db}
  --ca-file /etcd-certs/ca.crt
  --cert-file /etcd-certs/server.crt
  --key-file /etcd-certs/server.key
  --listen-address tcp://localhost:12379
EOF

  exec supervisord --nodaemon -c "${supervisord_config_file}"
}

_ctl() {
  action="$1"
  program="$2"

  while ! supervisorctl -c "${supervisord_config_file}" "${action}" "${program}"; do
    echo "failed to ${action} ${program}: retrying in 1s"
    sleep 1
  done
}

_on_vrrp_master() {
  if [ ! -f "${litestream_config_file}" ]; then
    echo "on_vrrp_master: do nothing due to litestream config missing"
    return
  fi

  # was in backup state, restore to ensure data up to date
  while ! _retore_main_db; do
    echo "restore failed on becoming vrrp master: retrying in 1s..."
    sleep 1
  done

  echo "starting replication as vrrp master"
  _ctl start replication

  # data restored and being replicated, start kine
  echo "starting kine as vrrp master"
  _ctl start kine

  trap "_on_vrrp_backup" EXIT

  supervisorctl -c "${supervisord_config_file}" fg kine
}

_on_vrrp_backup() {
  if [ ! -f "${litestream_config_file}" ]; then
    echo "on_vrrp_backup: do nothing due to litestream config missing"
    return
  fi

  # stop kine first, avoid unexpected writes
  echo "stopping kine as vrrp backup"
  _ctl stop kine

  # stop replication gracefully
  echo "stopping replication as vrrp backup"
  _ctl stop replication
}

# shellcheck disable=SC1091
. /app/.venv/bin/activate

case "$1" in
_*)
  echo "do not use internal command"
  ;;
run)
  # shellcheck disable=SC3023
  (
    flock -x -n 200
    _run
  ) 200>"${instance_lock}"
  ;;
on_vrrp_master)
  # shellcheck disable=SC3023
  (
    flock -x -n 201
    _on_vrrp_master
  ) 201>"${master_lock_file}"
  ;;
on_vrrp_backup)
  _on_vrrp_backup
  ;;
*)
  # shellcheck disable=SC2068
  exec $@
  ;;
esac
