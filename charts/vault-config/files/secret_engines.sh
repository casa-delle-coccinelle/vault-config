#! /bin/bash

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
echo "## Secet Engines"

export VAULT_ADDR=
export VAULT_POD_SELECTOR="${VAULT_POD_SELECTOR:-app.kubernetes.io/instance=hc-vault}"
# Ensure you are running agains active pod
export VAULT_POD_SELECTOR="${VAULT_POD_SELECTOR,vault-active=true}"
export VAULT_POD_ADDRESS=
export VAULT_SECRET_ENGINES_PATH="/SecretEngines"
export VAULT_TOKEN=

function set_secret_engine(){
    secret_engine="$(basename "${1}")"
    secret_engine_params="$(cat "${1}")"
    
    if [ "$(vault secrets list | grep "^${secret_engine}/")" == "" ]; then
        # If we don't set parameters we want empty parameter placeholder and not empty string parameter
        # shellcheck disable=SC2086
        vault secrets enable ${secret_engine_params} "${secret_engine}"
    fi
    if [ "${secret_engine_params}" == "" ]; then
        # shellcheck disable=SC2086
        vault secrets tune ${secret_engine_params} "${secret_engine}"
    fi
}

function set_secret_engines(){
    for secret_engine in "${VAULT_SECRET_ENGINES_PATH}"/*; do
        set_secret_engine "${secret_engine}"
    done
}

function main(){
    select_init_pod_address
    login
    set_secret_engines
}

main
