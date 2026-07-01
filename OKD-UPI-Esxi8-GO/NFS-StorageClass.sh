# On bastion (Rocky Linux 9) — set up NFS server
dnf install -y nfs-utils
mkdir -p /exports/okd-storage
chmod 777 /exports/okd-storage

# Export to your cluster network
echo "/exports/okd-storage 192.168.100.0/24(rw,sync,no_subtree_check,no_root_squash)" \
  >> /etc/exports

systemctl enable --now nfs-server
exportfs -rav

# Firewall
firewall-cmd --permanent --add-service=nfs
firewall-cmd --permanent --add-service=rpc-bind
firewall-cmd --permanent --add-service=mountd
firewall-cmd --reload

##

# On bastion — install via Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

# Deploy — adjust nfs.server and nfs.path to match your bastion IP and export path
helm install nfs-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --namespace nfs-provisioner \
  --create-namespace \
  --set nfs.server=192.168.100.10 \
  --set nfs.path=/exports/okd-storage \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=true

# Verify
oc get storageclass
oc get pods -n nfs-provisioner

###
oc describe replicaset -n nfs-provisioner

# Also check events in the namespace
oc get events -n nfs-provisioner --sort-by='.lastTimestamp'
```

```

## Fix — Grant the Required SCC

```bash
# Grant hostmount-anyuid SCC to the NFS provisioner service account
# This allows it to mount NFS and run as any UID
oc adm policy add-scc-to-user hostmount-anyuid \
  -z nfs-provisioner-nfs-subdir-external-provisioner \
  -n nfs-provisioner

# Verify it was applied
oc get rolebinding -n nfs-provisioner | grep scc
```

## Restart the Deployment

```bash
oc rollout restart deployment/nfs-provisioner-nfs-subdir-external-provisioner \
  -n nfs-provisioner

# Watch pod come up
watch -n 5 'oc get pods -n nfs-provisioner'
```

## Verify It's Working

```bash
# Pod should show Running
oc get pods -n nfs-provisioner

# Quick test — create a PVC and verify it binds
cat << 'EOF' | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-client
  resources:
    requests:
      storage: 1Gi
EOF

# Should show Bound within 30 seconds
oc get pvc test-pvc -n default

# Clean up test
oc delete pvc test-pvc -n default
```

Run the `oc describe replicaset` command first and share the output if the SCC fix doesn't resolve it — the exact error message in the events will tell us if there's a secondary issue.

