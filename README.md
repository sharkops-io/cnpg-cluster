# cnpg-cluster

A Helm chart for one [CloudNativePG](https://cloudnative-pg.io) Postgres cluster
with continuous backups: WAL archiving and scheduled base backups to
S3-compatible storage through the Barman Cloud plugin, plus the small fixes
that keep those backups restorable on quiet databases.

It needs the CloudNativePG operator and its Barman Cloud plugin already
installed in the cluster.

## Install

```sh
helm install mydb oci://ghcr.io/sharkops-io/charts/cnpg-cluster --version 0.7.1 \
  --set backup.minio.endpoint=https://s3.example.com \
  --set backup.minio.bucket=pg-backups
```

With helmfile:

```yaml
repositories:
  - name: sharkops-io
    url: ghcr.io/sharkops-io/charts
    oci: true

releases:
  - name: mydb
    namespace: myapp
    chart: sharkops-io/cnpg-cluster
    version: 0.7.1
    values:
      - db-values.yaml
```

## What it creates

| Object | Purpose |
|---|---|
| `Cluster` | The Postgres cluster (`cluster.instances`, storage size and class, major version) |
| `ObjectStore` + `ScheduledBackup` | Barman Cloud WAL archive and a daily base backup (`backup.schedule`, CNPG's 6-field cron) |
| `barman-credentials` Secret, or an `ExternalSecret` | The S3 key pair; set `backup.minio.externalSecret.enabled` to pull it from a secret store instead of values |
| WAL-switch `CronJob` (+ Role, RoleBinding, ServiceAccount, ConfigMap) | Forces a WAL switch after each backup so it can be restored ([plugin-barman-cloud#652](https://github.com/cloudnative-pg/plugin-barman-cloud/issues/652)) |
| `NetworkPolicy` (opt-in) | Admits only the listed app pods to port 5432 |

## Key values

| Value | Default | Notes |
|---|---|---|
| `cluster.instances` | `2` | Postgres instances (primary + standbys) |
| `cluster.storage.size` / `.class` | `10Gi` / `longhorn-postgres-replica-storage-besteffort` | |
| `cluster.postgresql.major` | `18` | |
| `cluster.postgresql.archiveTimeout` | `30min` | CNPG's 5min default archives a full segment every five minutes on any active cluster |
| `backup.schedule` | `0 2 0 * * *` | 6-field cron, seconds first |
| `backup.minio.endpoint` | `""` | S3-compatible endpoint URL. Set it for MinIO, RustFS, Ceph RGW, etc.; leave empty only for AWS S3 |
| `backup.minio.bucket` | `pg-backups` | |
| `backup.minio.externalSecret.enabled` / `.remoteKey` | `false` / `""` | Pull the S3 key pair from a secret store; `remoteKey` is required when enabled |
| `backup.retentionPolicy` | `7d` | |
| `walSwitch.schedule` | `0 1 * * *` | 5-field cron; keep it after `backup.schedule` if you change that |
| `networkPolicy.enabled` | `false` | `allowFromPods` lists the client pod selectors, same namespace only |

`values.yaml` explains the reasoning behind each default in its comments.

## Development

```sh
helm lint .
helm unittest --strict -f 'tests/*.yaml' .
```

CI runs both on every pull request through the shared
[sharkops-io/.github](https://github.com/sharkops-io/.github) workflows. A plain
`X.Y.Z` tag publishes that version to `oci://ghcr.io/sharkops-io/charts`.

## License

Apache License 2.0. See [LICENSE](LICENSE).
