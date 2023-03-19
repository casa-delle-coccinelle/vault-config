# vault-config
Helm chart for day-to-day vault operations

## Usage

To add chart repository run
```
  helm repo add casa-delle-coccinelle https://casa-delle-coccinelle.github.io/vault-config
```
If you had already added this repo earlier, run `helm repo update` to retrieve

To install the vault-config chart:
```
    helm install my-vault-config casa-delle-coccinelle/vault-config
```
To uninstall the chart:
```
    helm delete my-vault-config
```
## Setup

This setup is relying on AWS for data backend (dynamodb), for unseal keys and for root token storage (aws secretsmanager).
In addition to the functionalities provided by the Helm chart setup is using a sidecar image that does the actual operations. Operational scripts are set in additional configmaps.
Monitoring with prometheus is added (via a sidecar injected).

### Operational Scripts
#### Init Script
Initialize script has the following logic:
    * Check if vault is accessible (via curl)
    * When accessible:
        * Check if vault is already initialized
            * If initialized - finish
            * Else
                * Initialize vault
                * Parse and store root token
                * Parse and store recovery-keys
                * Cleanup keys from local storage

Script will try to generate a secret in AWS secrets manager, if it fails - will try to find the correct one based on said path. After that script will add current keys as new version in the secret.


##### Credentials (as AWS secrets)
Secrets are generated in the following pattern:
* recovery-keys: `hc-vault/${INSTANCE}/recovery-key/key-${id}`
* root-token: `hc-vault/${INSTANCE}/root-token/key-1`

`INSTANCE` is an ENV var, passed to operational script.

#### ACL Script
Depends on login step. Login step requires access to AWS secrets to pull root token and use it for opeartional purposes.
ACL script creates vault policies based on policy files mounted from a configmap (vault-acls)
ACL script does not check current policy status

#### Auth Script
Depends on login step. Login step requires access to AWS secrets to pull root token and use it for opeartional purposes.
Authentication script handles authentication methods.
Currently only `userpass` is implemented.
`userpass` implementation works in the following way:
* checks for env variables that follows `AUTH_USERPASS_${USERDEFINITION}`. Content of this env will be used for username. This is used to correlate user configuration. Only uppercase allowed for `USERDEFINITION`
    E.g.: `AUTH_USERPASS_USER1=username123` has ACL definition - `AUTH_USERPASS_username123_ACLS` and namespace definition - `AUTH_USERPASS_username123_SECRET_NAMESPACES=`
* Script checks for such username. If it does not exist:
    * Scripts check if any namespace is defined for this user (`AUTH_USERPASS_${USERNAME}_SECRET_NAMESPACES`). If there are namespaces defined - script checks if it is allowed to create/update secrets within this namespace. If not - user will not be created. If allowed - credentials are stored in secret, named `${INSTANCE}-vault-user` and user is created.
    * If no namespaces are defined script procedes to define a user
* Script always redefines ACLs for a user (if `AUTH_USERPASS_${USERNAME}_ACLS` is defined). There are no checks if current match defined. There is no possibility to partially add or remove ACLs for a user

#### DynamoDB backend
Script for DynamoDB reconfiguration. Currently only enables backups. Requires following variables:
* AWS_DEFAULT_REGION
* AWS_DYNAMODB_TABLE

### Storage
For storage setup is using DynamoDB - https://www.vaultproject.io/docs/configuration/storage/dynamodb
Point in time is enabled in operational scripts

## Development

To develelop you need k3d and make (best configure `alias make='make -e '`).

First time when developing, you will need foolowing two env variables:
    `AWS_ACCESS_KEY_ID`
    `AWS_SECRET_ACCESS_KEY`
Those credentials will be used to create and configure the storage backend and store aws secretsmanager secrets.

To build an image run `make image-build`. If you need to import ths image you need to do that manually. Check [this doc for more info](docker/vault-operator/README.md)

To deploy a full setup run `make deploy-all`.
You can find vault and the config tool in `hc-vault` namespace.
Deploy script adds in addition to hc vault some supporting software.
Scripts are adding prometheus and grafana to help you work on k8s integration topics (prometheus)
and to work with on the dashboard (grafana). If you add another integration make sure to add
that software to the build script. This would allow others to work with it in their dev environment.

To access urls in the setup use `make fix-traffic`.

To get the root token for your vault instance, use `make get-root-token`.

Currently prometheus may not get injected with vault secrtets. You may need to run `make inject-prometheus`.

If your browser complains about TLS certificates, run `make get-ca` and import that certificate toyour browser's trust store.



## Variables
| Variable | Description | Default |
|--|--|--|
| image.repository | Repository for container image | 926833232050.dkr.ecr.eu-central-1.amazonaws.com/vault |
| image.tag | Container tag | 1.9.2-0.1.0 |
| image.pullPolicy | Container pull policy | IfNotPresent |
| imagePullSecrets | Image pull secrets | IfNotPresent |
| vaultPodSelector | Pod selector querry for script to choose first var | app.kubernetes.io/instance=hc-vault |
| vaultServiceAccount | Service account for Vault | hc-vault |
| rbac.create | If RBAC configuration is used | true |
| env | Env variables | {} |
| secretEnv | Same as above, with secrets | {} |
| extraSecretEnvironmentVars | `env:` definitions passed to pods | {} |
| prometheusNamespace | Namespace in which grafana is selecting configmaps | prometheus |
| grafanaDashboardLabels | Labels on which grafana is selecting dashboards | grafana_dashboard: "1" |
| authmethods | Authentication methods configurations | userpass: {} |
| vaultSecretEngines | Secret engines for vault | [] |

### Examples

```yaml

imagePullSecrets:
  - name: awsecr-cred

basicAuthSecret: ""

vaultPodSelector: app.kubernetes.io/instance=hc-vault

env: 
  INSTANCE: hc-vault
  AWS_DEFAULT_REGION: eu-central-1
  AWS_DYNAMODB_TABLE: hc-vault
  VAULT_SA_NAME: hc-vault

extraSecretEnvironmentVars: 
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: vault-secret-env
        key: AWS_SECRET_ACCESS_KEY
  - name: AWS_ACCESS_KEY_ID
    valueFrom:
      secretKeyRef:
        name: vault-secret-env
        key: AWS_ACCESS_KEY_ID

authmethods:
  userpass:
  kubernetes:
    prometheus: |-
      {
        "namespace": "prometheus",
        "sa-name": "prometheus-kube-prometheus-prometheus",
        "acls":
          [
            "prometheus-metrics"
          ]
      }

vaultSecretEngines:
  - name: kv-v2
```
Additional example (fullblown conf) - [in the dev dir](../../.ci/k3d/hc-vault/vault-config.yaml)
### 


