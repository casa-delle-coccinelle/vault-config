#! /bin/bash

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
echo "## AUTH"

export VAULT_ADDR=
export VAULT_POD_SELECTOR="${VAULT_POD_SELECTOR:-app.kubernetes.io/instance=hc-vault}"
# Ensure you are running agains active pod
export VAULT_POD_SELECTOR="${VAULT_POD_SELECTOR,vault-active=true}"
export VAULT_POD_ADDRESS=
export VAULT_USERPASS_PATH="/AuthMethods/userpass"
export VAULT_KUBERNETES_PATH="/AuthMethods/kubernetes"
export VAULT_ENTITIES="/Entities"
export VAULT_GROUPS="/Groups"
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
      "${INSTANCE}-${user}-vault-user" \
      --from-literal=USERNAME="${user}" \
      --from-literal=PASSWORD="${vault_user_pass}" \
      --dry-run=client -o yaml | kubectl --namespace="${namespace}" apply -f -

    e_code="${?}"

    if [ "${e_code}" != 0 ]; then
        log_output "Failed to create secret ${INSTANCE}-vault-user in namespace ${namespace}"
        return 1
    else
        return 0
    fi
}

function configure_user(){
    user="${1}"
    namespaces="$(jq -r '.namespaces[]' "${2}" 2> /dev/null)"

    log_output "Configuring user ${user} in namespaces ${namespaces}"
    log_output "Checking if user ${user} exists"
    vault read "auth/userpass/users/${user}"
    user_exists="${?}"
    vault_user_pass="$(LC_ALL=C tr -dc "A-Za-z0-9!#$%&'()*+,-./:;<=>?@[\]^_\`\{|}~" </dev/urandom | head -c 25 ; echo)"

    if [ "${user_exists}" != "0" ]; then
        log_output "User ${user} does not exist. Populating credentials in namespaces"
        for namespace in ${namespaces}; do
            kubectl auth can-i create secret -n "${namespace}" || (
                log_output "Can't generate secret in ${namespace}" > /dev/null && \
                return 1
            )
            kubectl auth can-i update secret -n "${namespace}" > /dev/null || (
                log_output "Can't update secret in ${namespace}" && \
                return 1
            )
            generate_secret "${user}" "${vault_user_pass}" "${namespace}"
        done

        log_output "Configuring user ${user} in ${VAULT_ADDR}"
        vault write \
            "auth/userpass/users/${user}" \
            password="${vault_user_pass}"
        e_code="${?}"
        if [ "${e_code}" != 0 ]; then
            log_output "Failed to configure credentials for user ${user} in ${VAULT_ADDR}"
            return 2
        fi
    fi
}

function userpass_handle(){

    log_output "Handling users from ${VAULT_USERPASS_PATH}"
    for user_path in "${VAULT_USERPASS_PATH}"/*; do
        if [ ! -e "${user_path}" ]; then
            log_output "No userpass users defined. Skipping ..."
            return
        fi
        user="$(basename "${user_path}")"
        configure_user "${user}" "${user_path}"
        acls="$(jq -r '.acls | join(",")' "${sa_path}" 2>/dev/null )"
        log_output "Adding user ${user} to ACL(s) ${acls}"
        vault write "auth/userpass/users/${user}/policies" policies="${acls}"
        e_code="${?}"
        if [ "${e_code}" != "0" ] ; then
            log_output "Adding user ${user} to ACL ${acls} failed"
        fi
    done
}

function userpass(){
    log_output "Enabling userpass auth"
    vault auth enable userpass 2>/dev/null || true
    userpass_handle || true
}

function kubernetes_handle(){
    log_output "Configuring k8s authentication"
    for sa_path in "${VAULT_KUBERNETES_PATH}"/*; do
        if [ ! -e "${sa_path}" ]; then
            log_output "No k8s auth configured. Skipping ..."
            return
        fi
        sa="$(basename "${sa_path}")"
        namespace="$(jq -r '.namespace' "${sa_path}")"
        sa_name="$(jq -r '."sa-name"' "${sa_path}")"
        acls="$(jq -r '.acls | join(",")' "${sa_path}" 2>/dev/null )"
        log_output "Configuring k8s auth for SA ${sa_name} in namespaces ${namespace} with ACLs ${acls}"
        vault write \
            "auth/kubernetes/role/${sa}" \
            "bound_service_account_names=${sa_name}" \
            "bound_service_account_namespaces=${namespace}" \
            policies="${acls}" \
            ttl=24h
        e_code="${?}"
        if [ "${e_code}" != 0 ]; then
            log_output "k8s auth for SA ${sa_name} in namespaces ${namespace} with ACLs ${acls} was not configured successfully"
        fi
    done
}

function kubernetes(){
    log_output "Configuring K8s auth"
    vault auth enable kubernetes 2>/dev/null || true

    vault write auth/kubernetes/config \
        kubernetes_host="https://${KUBERNETES_PORT_443_TCP_ADDR}:443" \
        token_reviewer_jwt="$(kubectl --namespace "${VAULT_NAMESPACE}" create token "${VAULT_SA_NAME}")" \
        kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
        issuer="https://kubernetes.default.svc.cluster.local"
    kubernetes_handle
}

function auth_methods(){
    userpass
    kubernetes
}

function entity_handle(){
    entity_file="${1}"
    log_output "Reading entity from entity file ${entity_file}"

    entity="$(jq -r .name "${entity_file}")"
    log_output "Collecting entity aliases for entity ${entity} in file ${entity_file}"

    entity_aliases="$(jq -r '.aliases | length' "${entity_file}")"
    log_output "Found ${entity_aliases} aliases for entity ${entity}"

    acls="$(jq -r '.acls | join(",")' "${entity_file}" 2>/dev/null )"
    log_output "Found ACL(s) ${acls} for entity ${entity}"

    log_output "Creating entity ${entity}"
    vault write identity/entity name="${entity}" policies="${acls}"

    entity_id="$(vault read "identity/entity/name/${entity}" -format=json | jq -r ".data.id")"
    log_output "Entity ${entity} has id ${entity_id} in ${VAULT_ADDR}"


    for i in $( seq 0 $(("${entity_aliases}" - 1)) ); do
        entity_alias="$(jq -r ".aliases[${i}].name" "${entity_file}")"
        entity_alias_authmethod="$(jq -r ".aliases[${i}].authMethod" "${entity_file}")"
        entity_alias_authmethod_accessor="$(vault auth list -format=json | jq -r ".[\"${entity_alias_authmethod}/\"].accessor")"
        log_output "Configuring entity alias ${entity_alias} for entity ${entity} with auth method ${entity_alias_authmethod}(${entity_alias_authmethod_accessor})"
        vault write identity/entity-alias name="${entity_alias}" \
            canonical_id="${entity_id}" \
            mount_accessor="${entity_alias_authmethod_accessor}" || true
    done
}

function vault_groups_handle(){
    vault_group_file="${1}"
    log_output "Reading group from group file ${vault_group_file}"
    
    group="$(jq -r .name "${vault_group_file}")"
    log_output "Group ${group} found"

    acls="$(jq -r '.acls | join(",")' "${vault_group_file}" 2>/dev/null )"
    log_output "ACL(s) ${acls} found for group ${group}"
    
    vault write identity/group name="${group}" policies="${acls}"
    log_output "Group ${group} created in ${VAULT_ADDR}"

    for entity in $(jq -r .entities[] "${vault_group_file}"); do
        log_output "Getting entity ${entity}'s ID"
        entity_id="$(vault read "identity/entity/name/${entity}" -format=json | jq -r ".data.id")"
        log_output "Adding entity ${entity} with ID ${entity_id} to group ${group}"
        vault write identity/group name="${group}" member_entity_ids="${entity_id}"
    done
}

function entities(){
    log_output "Reading entities from ${VAULT_ENTITIES}"
    for entity_file in "${VAULT_ENTITIES}"/*; do
        if [ ! -e "${entity_file}" ]; then
            log_output "No entities configured. Skipping..."
            return
        fi
        log_output "Handling identity from file ${entity_file}"
        entity_handle "${entity_file}"
    done
}

function vault_groups(){
    log_output "Reading groups definitions from ${VAULT_GROUPS}"
   
    for groups_file in "${VAULT_GROUPS}"/*; do
        if [ ! -e "${groups_file}" ]; then
            log_output "No groups configured. Skipping..."
            return
        fi
        log_output "Handling groups from file ${groups_file}"
        vault_groups_handle "${groups_file}"
    done

}

function main() {
  select_init_pod_address
  login
  auth_methods
  entities
  vault_groups
}

main
sleep 5000000
