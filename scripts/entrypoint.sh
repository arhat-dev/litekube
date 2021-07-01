#!/bin/sh

set -ex

litestream_config_file="/data/litestream.yaml"
supervisord_config_file="/data/supervisord.conf"
supervisord_server_url="http://localhost:9001"
master_flag_file="/data/.vrrp_master"
main_db="/data/db.sqlite"

instance_lock="/data/litekube.lock"

_lock() {
  # shellcheck disable=SC3023
  exec 100>"${instance_lock}"
  flock -x -n 100
}

_unlock() {
  flock -u 100
}

__create_master_flag_file() {
  while [ ! -f "${master_flag_file}" ]; do
    touch "${master_flag_file}" || true
    sleep 1
  done
}

__remove_master_flag_file() {
  while [ -f "${master_flag_file}" ]; do
    rm -f "${master_flag_file}" || true
    sleep 1
  done
}

_cleanup() {
  __remove_master_flag_file

  _unlock
}

_retore_latest() {
  if [ ! -f "${litestream_config_file}" ]; then
    # no litestream config, no restore
    echo "no litestream configuration, skipping restore"
    return
  fi

  litestream restore -v \
    -config "${litestream_config_file}" \
    -if-replica-exists \
    /data/db.sqlite
}

_run() {
  trap _cleanup EXIT

  _lock

  cat <<EOF >"${supervisord_config_file}"
[supervisord]
nodaemon = true
logfile = /dev/stderr
logfile_maxbytes = 0
pidfile = /var/lib/supervisord/pid

[supervisorctl]
serverurl = ${supervisord_server_url}

[eventlistener:fatal-exit]
process_name=%(program_name)s
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
autostart = true
autorestart = true
startsecs=0
startretries=0
events = PROCESS_STATE_FATAL
command=$(which sh) -c
  'while true; do printf "READY\n"; read line; kill -SIGINT \$(cat /var/lib/supervisord/pid); printf "RESULT 2\n"; printf "OK"; done'

[program:restore]
process_name=%(program_name)s
autostart = false
autorestart = true
user = litekube
startsecs = 1
startretries = 0
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
command = /usr/local/bin/litestream restore -v
  -config ${litestream_config_file}
  -o ${main_db}

[program:replicate]
process_name=%(program_name)s
autostart = false
autorestart = true
user = litekube
startsecs = 10
startretries = 10
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
command = /usr/local/bin/litestream replicate
  -config ${litestream_config_file}
  -o ${main_db}

[program:keepalived]
process_name=%(program_name)s
autostart = true
autorestart = true
user = litekube
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
autostart = true
autorestart = true
user = litekube
startsecs = 5
startretries = 3
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
stderr_logfile = /dev/stderr
stderr_logfile_maxbytes = 0
command = /usr/local/bin/kine
  --endpoint sqlite:///data/db.sqlite
  --ca-file /etcd-certs/ca.crt
  --cert-file /etcd-certs/server.crt
  --key-file /etcd-certs/server.key
  --listen-address tcp://localhost:12379
EOF

  __remove_master_flag_file

  # shellcheck disable=SC1091
  . /app/.venv/bin/activate

  exec supervisord --nodaemon -c "${supervisord_config_file}"
}

__start_replication() {
  if [ ! -f "${master_flag_file}" ]; then
    echo "master flag file not found, replication canceled"
    return
  fi

  while ! supervisorctl -c "${supervisord_config_file}" start replicate; do
    if [ ! -f "${master_flag_file}" ]; then
      echo "master flag file not found, replication canceled"
      return
    fi

    echo "failed to start replication: retrying in 1s"
    sleep 1
  done
}

__start_restore() {
  if [ -f "${master_flag_file}" ]; then
    echo "master flag file found, restore canceled"
    return
  fi

  while ! supervisorctl -c "${supervisord_config_file}" start restore; do
    if [ -f "${master_flag_file}" ]; then
      echo "master flag file found, restore canceled"
      return
    fi

    echo "failed to start restore: retrying in 1s"
    sleep 1
  done
}

_on_vrrp_master() {
  if [ ! -f "${litestream_config_file}" ]; then
    echo "on_vrrp_master: do nothing due to litestream config missing"
    return
  fi

  if [ -f "${master_flag_file}" ]; then
    echo "on_vrrp_master: already in master state"
    __start_replication
    return
  fi

  __create_master_flag_file

  while ! supervisorctl -c "${supervisord_config_file}" stop restore; do
    echo "failed to stop restore on vrrp master: retrying in 1s..."
    sleep 1
  done

  # was in backup state, restore to ensure data up to date
  while ! _retore_latest; do
    echo "restore failed on becoming vrrp master: retrying in 1s..."
    sleep 1
  done

  echo "starting litestream replication as vrrp master"
  __start_replication
}

_on_vrrp_backup() {
  if [ ! -f "${litestream_config_file}" ]; then
    echo "on_vrrp_backup: do nothing due to litestream config missing"
    return
  fi

  __remove_master_flag_file

  while ! supervisorctl -c "${supervisord_config_file}" stop replicate; do
    echo "failed to stop replication on vrrp backup: retrying in 1s..."
    sleep 1
  done

  while ! _retore_latest; do
    echo "initial restore failed on becoming vrrp backup: retrying in 1s..."
    sleep 1
  done

  echo "starting litestream restore as vrrp backup"
  __start_restore
}

_empty_restore() {
  if [ ! -f "${litestream_config_file}" ]; then
    # no litestream config, no restore
    echo "no litestream configuration, skipping restore"
    return
  fi

  litestream restore -v \
    -config "${litestream_config_file}" \
    -if-db-not-exists \
    -if-replica-exists \
    /data/db.sqlite
}

case "$1" in
restore)
  _empty_restore
  ;;
run)
  _run
  ;;
on_vrrp_master)
  _on_vrrp_master
  ;;
on_vrrp_backup)
  _on_vrrp_backup
  ;;
*)
  # shellcheck disable=SC2068
  exec $@
  ;;
esac
