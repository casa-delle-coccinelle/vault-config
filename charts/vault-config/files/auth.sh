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

    kubectl \
      --namespace="${namespace}" \
      create \
      secret \
      generic \
      ${INSTANCE}-vault-user \
      --from-literal=USERNAME="${user}" \
      --from-literal=PASSWORD="${vault_user_pass}" \
      --dry-run=client -o yaml | kubectl --namespace="${namespace}" apply -f -
}

function userpass_handle(){
  
    for user in $(ls -1 ${VAULT_USERPASS_PATH} 2>/dev/null); do

        vault read auth/userpass/users/${user}
        user_exists="${?}"
        vault_user_pass="$(LC_ALL=C tr -dc "A-Za-z0-9!#$%&'()*+,-./:;<=>?@[\]^_\`\{|}~" </dev/urandom | head -c 25 ; echo)"

        if [ "${user_exists}" != "0" ]; then
            for namespace in $(jq -r '.namespaces[]' "${VAULT_USERPASS_PATH}/${user}" 2> /dev/null); do
                kubectl auth can-i create secret -n ${namespace} || return 1
                kubectl auth can-i update secret -n ${namespace} || return 1
                generate_secret "${user}" "${vault_user_pass}" "${namespace}"
            done

            vault write \
                auth/userpass/users/${user} \
                password="${vault_user_pass}"
        fi
        for acl in $(jq -r '.acls[]' "${VAULT_USERPASS_PATH}/${user}" 2> /dev/null); do
            vault write auth/userpass/users/${user}/policies policies="${acl}"
        done
    done
}

function userpass(){
  vault auth enable userpass || true
  userpass_handle || true
}

function kubernetes_handle(){
    for sa in $(ls -1 ${VAULT_KUBERNETES_PATH}); do
        namespace="$(jq -r '.namespace' "${VAULT_KUBERNETES_PATH}/${sa}")"
        sa_name="$(jq -r '."sa-name"' "${VAULT_KUBERNETES_PATH}/${sa}")"
        acls="$(jq -r '.acls | join(",")' "${VAULT_KUBERNETES_PATH}/${sa}")"
        vault write \
            auth/kubernetes/role/${sa} \
            bound_service_account_names=${sa_name} \
            bound_service_account_namespaces=${namespace} \
            policies="${acls}" \
            ttl=24h
    done
}

function kubernetes(){
  vault auth enable kubernetes

  SA_TOKEN_SECRET="$(kubectl get sa ${VAULT_SA_NAME} -o template='{{ with (index .secrets 0) }}{{ .name }}{{ end }}')"
  kubectl secrets "${SA_TOKEN_SECRET}" -o template='{{ .data.token }}' | base64 -w 0 > /tmp/token_value
  vault write auth/kubernetes/config \
      kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
      token_reviewer_jwt="$(cat /tmp/token_value)" \
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

