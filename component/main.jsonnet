local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.solution_backup;
local instance = inv.parameters._instance;
local slug = std.substr(std.sha256(instance), 0, 8);

local nsName = params.namespace;
local objectPrefix = 'pvc-backup-' + slug;
local saName = 'solution-backup-manager';

local backupNs = params.backup_namespaces;
local encryption = params.backup_encryption_secret;

local s3 = params.s3;
local ob = params.objectbucket;
local sched = params.schedule;
local endpointResolved = s3.endpoint % { region: s3.region };

local namespace = (if params.createNamespace then kube.Namespace(nsName) else null) + {
  metadata+: {
    labels+: params.namespaceLabels,
    annotations+: params.namespaceAnnotations,
  },
};

local serviceAccount = kube.ServiceAccount(saName) {
  metadata+: { namespace: nsName },
};
local clusterRole = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'ClusterRole',
  metadata: {
    name: nsName + ':' + saName,
  },
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'namespaces' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
    {
      apiGroups: [ 'appcat.vshn.io' ],
      resources: [ 'objectbuckets' ],
      verbs: [ '*' ],
    },
    {
      apiGroups: [ 'k8up.io' ],
      resources: [ 'schedules' ],
      verbs: [ '*' ],
    },
  ],
};
local clusterRoleBinding = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'ClusterRoleBinding',
  metadata: {
    name: nsName + ':' + saName,
  },
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: clusterRole.metadata.name,
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: saName,
      namespace: nsName,
    },
  ],
};

local rawTemplate = |||
  local esp = import 'espejote.libsonnet';

  local inDelete(obj) = std.get(obj.metadata, 'deletionTimestamp', '') != '';
  local wantsBackup(ns) =
    local labels = std.get(ns.metadata, 'labels', {});
    !inDelete(ns)
    && std.get(labels, '%(optInLabel)s', 'false') == '%(optInValue)s'
    && std.objectHas(labels, '%(encryptionSecretNameLabel)s');

  local managedBy = { 'espejote.io/managed-by': '%(managedBy)s' };
  local credsSecretName = '%(credsSecretName)s';
  local bucketNamePrefix = '%(bucketNamePrefix)s';

  local encryptionSecretName(ns) =
    std.get(ns.metadata, 'labels', {})['%(encryptionSecretNameLabel)s'];

  local nsSlug(ns) = std.substr(std.sha256(ns.metadata.name), 0, 8);

  local makeObjectBucket(ns) = {
    apiVersion: 'appcat.vshn.io/v1',
    kind: 'ObjectBucket',
    metadata: {
     name: '%(objectPrefix)s',
     namespace: ns.metadata.name,
     labels: managedBy
    },
    spec: {
      parameters: {
        bucketName: bucketNamePrefix + nsSlug(ns),
        region: '%(region)s'
      },
      writeConnectionSecretToRef: {
        name: credsSecretName
      },
    },
  };

  local makeSchedule(ns) = {
    apiVersion: 'k8up.io/v1',
    kind: 'Schedule',
    metadata: {
      name: '%(objectPrefix)s',
      namespace: ns.metadata.name,
      labels: managedBy
    },
    spec: {
      backend: {
        repoPasswordSecretRef: {
          name: encryptionSecretName(ns),
          key: 'password'
        },
        s3: {
          endpoint: '%(endpoint)s',
          bucket: bucketNamePrefix + nsSlug(ns),
          accessKeyIDSecretRef: {
            name: credsSecretName,
            key: 'AWS_ACCESS_KEY_ID'
          },
          secretAccessKeySecretRef: {
            name: credsSecretName,
            key: 'AWS_SECRET_ACCESS_KEY'
          },
        },
      },
      backup: { schedule: '%(backupSchedule)s' },
      check: { schedule: '%(checkSchedule)s' },
      prune: { schedule: '%(pruneSchedule)s', retention: %(retention)s },
    },
  };

  local manageNs(ns) = [ makeObjectBucket(ns), makeSchedule(ns) ];

  local tn = esp.triggerName();
  if tn == 'namespace' then (
    local ns = esp.triggerData().resource;
    if ns != null && wantsBackup(ns) then manageNs(ns) else []
  ) else [
    obj
    for ns in esp.context().backup_namespaces
    if wantsBackup(ns)
    for obj in manageNs(ns)
  ]
|||;
local template = rawTemplate % {
  optInLabel: backupNs.label,
  optInValue: backupNs.value,
  managedBy: nsName + '.' + objectPrefix,
  objectPrefix: objectPrefix,
  credsSecretName: 'backup-bucket-creds-' + slug,
  bucketNamePrefix: ob.name_prefix + slug + '-',
  encryptionSecretNameLabel: encryption.label,
  region: s3.region,
  endpoint: endpointResolved,
  backupSchedule: sched.backup,
  checkSchedule: sched.check,
  pruneSchedule: sched.prune,
  retention: std.manifestJsonEx(sched.retention, '  '),
};

local managedResource = {
  apiVersion: 'espejote.io/v1alpha1',
  kind: 'ManagedResource',
  metadata: {
    name: objectPrefix,
    namespace: nsName,
  },
  spec: {
    serviceAccountRef: { name: saName },
    context: [
      {
        name: 'backup_namespaces',
        resource: {
          apiVersion: 'v1',
          kind: 'Namespace',
          namespace: '',
          labelSelector: {
            matchLabels: {
              [backupNs.label]: backupNs.value,
            },
          },
        },
      },
    ],
    triggers: [
      { name: 'namespace', watchContextResource: { name: 'backup_namespaces' } },
    ],
    template: template,
  },
};

{
  [if params.createNamespace then 'namespace']: namespace,
  serviceAccount: serviceAccount,
  clusterRole: clusterRole,
  clusterRoleBinding: clusterRoleBinding,
  managedResource: managedResource,
}
