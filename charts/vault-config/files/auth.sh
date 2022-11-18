#! /bin/sh

source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
echo "## AUTH"

export VAULT_ADDR=
export VAULT_POD_SELECTOR="${VAULT_POD_SELECTOR:-app.kubernetes.io/instance=hc-vault}"
# Ensure you are running agains active pod
export VAULT_POD_SELECTOR="${VAULT_POD_SELECTOR,vault-active=true}"
export VAULT_POD_ADDRESS=
export VAULT_USERPASS_PATH="/AuthMethods/userpass"
export VAULT_KUBERNETES_PATH="/AuthMethods/kubernetes"
export VAULT_TOKEN=
export VAULT_SA_NAME="${VAULT_SA_NAME:-hc-vault}"

function generate_secret(){
    user="${1}"
    vault_user_pass="${2}"
    namespace="${3}"
    
    log_output "Generating secret ${INSTANCE}-vault-user in namespace ${namespace}"
    kubectl \
      --namespace="${namespace}" \
      create \
      secret \
      generic \
      ${INSTANCE}-vault-user \
      --from-literal=USERNAME="${user}" \
      --from-literal=PASSWORD="${vault_user_pass}" \
      --dry-run=client -o yaml | kubectl --namespace="${namespace}" apply -f -

    if [ "${?}" != 0 ]; then
        log_output "Failed to create secret ${INSTANCE}-vault-user in namespace ${namespace}"
        return 1
    else
        return 0
    fi
}

function configure_user(){
    user="${1}"
    namespaces="$(jq -r '.namespaces[]' ${2} 2> /dev/null)"

    log_output "Configuring user ${user} in namespaces ${namespaces}"
    log_output "Checking if user ${user} exists"
    vault read auth/userpass/users/${user}
    user_exists="${?}"
    vault_user_pass="$(LC_ALL=C tr -dc "A-Za-z0-9!#$%&'()*+,-./:;<=>?@[\]^_\`\{|}~" </dev/urandom | head -c 25 ; echo)"

    if [ "${user_exists}" != "0" ]; then
        log_output "User ${user} does not exist. Populating credentials in namespaces"
        for namespace in ${namespaces}; do
            kubectl auth can-i create secret -n ${namespace} || (
                log_output "Can't generate secret in ${namespace}" && \
                return 1
            )
            kubectl auth can-i update secret -n ${namespace} || (
                log_output "Can't update secret in ${namespace}" && \
                return 1
            )
            generate_secret "${user}" "${vault_user_pass}" "${namespace}"
        done

        log_output "Configuring user ${user} in ${VAULT_ADDR}"
        vault write \
            auth/userpass/users/${user} \
            password="${vault_user_pass}"
        if [ "$?" != 0 ]; then
            log_output "Failed to configure credentials for user ${user} in ${VAULT_ADDR}"
            return 2
        fi
    fi
}

function userpass_handle(){

    log_output "Handling users from ${VAULT_USERPASS_PATH}"
    for user in $(ls -1 ${VAULT_USERPASS_PATH} 2>/dev/null); do
        configure_user "${user}" "${VAULT_USERPASS_PATH}/${user}"
        for acl in $(jq -r '.acls[]' "${VAULT_USERPASS_PATH}/${user}" 2> /dev/null); do
            log_output "Adding user ${user} to ACL ${acl}"
            vault write auth/userpass/users/${user}/policies policies="${acl}"
            if [ "${?}" != 0]; then
                log_output "Adding user ${user} to ACL ${acl} failed"
            fi
        done
    done
}

function userpass(){
    log_output "Enabling userpass auth"
    vault auth enable userpass 2>/dev/null || true
    userpass_handle || true
}

function kubernetes_handle(){
    log_output "Configuring k8s authentication"
    for sa in $(ls -1 ${VAULT_KUBERNETES_PATH}); do
        namespace="$(jq -r '.namespace' "${VAULT_KUBERNETES_PATH}/${sa}")"
        sa_name="$(jq -r '."sa-name"' "${VAULT_KUBERNETES_PATH}/${sa}")"
        acls="$(jq -r '.acls | join(",")' "${VAULT_KUBERNETES_PATH}/${sa}")"
        log_output "Configuring k8s auth for SA ${sa_name} in namespaces ${namespace} with ACLs ${acls}"
        vault write \
            auth/kubernetes/role/${sa} \
            bound_service_account_names=${sa_name} \
            bound_service_account_namespaces=${namespace} \
            policies="${acls}" \
            ttl=24h
        if [ "${?}" != 0 ]; then
            log_output "k8s auth for SA ${sa_name} in namespaces ${namespace} with ACLs ${acls} was not configured successfully"
        fi
    done
}

function kubernetes(){
    log_output "Configuring K8s auth"
    vault auth enable kubernetes 2>/dev/null || true

    echo "kubectl --namespace ${VAULT_NAMESPACE} create token ${VAULT_SA_NAME}"
    kubectl --namespace ${VAULT_NAMESPACE} create token ${VAULT_SA_NAME}
    VAULT_TOKEN="$(kubectl --namespace ${VAULT_NAMESPACE} create token ${VAULT_SA_NAME})"
    if [ "${VAULT_TOKEN}" == "" ]; then
        sleep 1000000
    fi
    vault write auth/kubernetes/config \
        kubernetes_host="https://${KUBERNETES_PORT_443_TCP_ADDR}:443" \
        token_reviewer_jwt="$(kubectl --namespace ${VAULT_NAMESPACE} create token ${VAULT_SA_NAME})" \
        kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
        issuer="https://kubernetes.default.svc.cluster.local" || true

    kubernetes_handle
}

function auth_methods(){
  userpass
  kubernetes
}

function main() {
  select_init_pod_address
  login
  auth_methods
}

main

