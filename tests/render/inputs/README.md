# Test inputs

These YAML files simulate in-cluster state offline and feed `espejote render
--input`. Each file is a single document with `triggers`, `context`, and
`libraries`; the `context.resources` arrays are pre-filtered to match what a
real cluster's selectors would return (offline, `espejote` does not re-apply
the ManagedResource's labelSelector against `context[].resources`).

Opt-in label (defaults instance): `vshn.ch/solution-base-backup: "true"`.
Encryption-secret label (defaults instance):
`vshn.ch/solution-base-backup-encryption-secret`, value = the name of the Secret
holding the restic repo password under key `password`. There is NO default —
a namespace without this label is not backed up.

- `labeled-general.yaml` — general reconciliation, one opted-in namespace
  `test-app` with both the opt-in + encryption-secret labels. Renders the
  AppCat `ObjectBucket` claim and the k8up `Schedule`.
- `labeled-trigger-namespace.yaml` — `namespace` watch trigger fires for the
  opted-in namespace (both labels); context also lists it. Renders the pair
  for that ns only.
- `labeled-with-encryption-secret-label.yaml` — general reconciliation, opted
  in AND carrying the encryption-secret label with a custom Secret name. The
  Schedule's `repoPasswordSecretRef.name` resolves to that custom name
  (`my-custom-encryption`).
- `labeled-without-encryption-label.yaml` — opted in via the opt-in label but
  WITHOUT the encryption-secret label. There is no default, so nothing renders.
- `unlabeled.yaml` — general reconciliation, no namespace opted in (empty
  `backup_namespaces` context). Renders nothing.
- `trigger-namespace-unlabeled.yaml` — `namespace` watch trigger fires for a
  namespace without the opt-in label; context empty. Renders nothing (the
  `wantsBackup(ns)` guard returns false).

No cluster, no kubectl: only `espejote` (from PATH, not vendored) reads them.
