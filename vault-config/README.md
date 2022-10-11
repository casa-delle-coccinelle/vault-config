# vault-config
Helm chart for day-to-day vault operations

## Usage

To add chart repository run
```
  helm repo add dimitar-ivanov-bosch-si-com https://dimitar-ivanov-bosch-si-com.github.io/vault-config
```
If you had already added this repo earlier, run `helm repo update` to retrieve

To install the vault-config chart:
```
    helm install my-vault-config dimitar-ivanov-bosch-si-com/vault-config
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

### Database
_MAKE SURE THAT YOU HAVE CHANGED THE STORAGE BACKEND FOR THIS VAULT INSTANCE_
You can change the name of the storage backend by changing `server.extraEnvironmentVars.AWS_DYNAMODB_TABLE`

### Secrets
_MAKE SURE THAT YOU HAVE CHANGED THE INSTANCE ENVIRONMENT VARIABLE FOR THIS VAULT INSTANCE_
Instance environment variable can be change in the k8s manifest - configmap `vault-init-script-env`
List secrets with `aws secretsmanager list-secrets | grep ARN`. Identify yours. _BE CAREFUL NOT TO REMOVE THE WRONG CREDENTIAL. THIS STEP IS NOT REVERSIBLE_
Delete a secret with the following command (deletion is immediate. Other methods require a waiting period of 7-30 days) - `aws secretsmanager delete-secret --force-delete-without-recovery --secret-id ${SECRET_ARN}`

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



