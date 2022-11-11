#! /bin/sh

source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
echo "## ACLS"

export VAULT_ADDR=
export VAULT_POD_SELECTOR="${VAULT_POD_SELECTOR:-app.kubernetes.io/instance=hc-vault}"
# Ensure you are running agains active pod
export VAULT_POD_SELECTOR="${VAULT_POD_SELECTOR,vault-active=true}"
export VAULT_POD_ADDRESS=
export VAULT_ACLS_PATH="/ACLs"
export VAULT_TOKEN=

function set_acl(){
    acl="${1}"
    acl_path="${VAULT_ACLS_PATH}/${1}"

    vault policy write ${acl} ${acl_path}
}

function set_acls(){
    for acl in $(ls -1 ${VAULT_ACLS_PATH}); do
        set_acl ${acl}
    done
}

function main(){
    select_init_pod_address
    login
    set_acls
}

main
