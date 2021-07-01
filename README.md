# litekube

HA Kubernetes using sqlite, litestream, kine

## Usage

1. Gain access to your Kubernetes master nodes
2. Choose a directory to store litekube's config and data, we will use `/var/lib/litekube` in this doc
3. Create litekube data directory `mkdir -p /var/lib/litekube`
4. Create litestream config in `/var/lib/litekube/litestream.yaml` (see [litestream.yaml](./litestream.yaml))
5. Create keepalived config in `/var/lib/litekube/keepalived.conf` (see [keepalived.conf](./keepalived.conf) for reference)
6. Update [manifests/litekube.yaml](./manifests/litekube.yaml): make sure etcd-certs and litekube-data volumes' hostPath are correct (but DO NOT change their mountPath)
   - etcd-certs dir SHOULD have `ca.crt`, `server.crt`, `server.key`
   - litekube-data dir SHOULD have `keepalived.conf`, `litestream.yaml`
7. Deploy litekube as a static pod: save the updated manifest to your kubelet static pod manifest dir (usually `/etc/kubernetes/manifests`)
