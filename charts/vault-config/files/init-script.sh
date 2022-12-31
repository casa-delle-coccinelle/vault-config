#! /bin/bash
#Based on https://github.com/hashicorp/best-practices/blob/master/packer/config/vault/scripts/setup_vault.sh

# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/env.sh"
echo "## INIT SCRIPT"

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-central-1}"
export INSTANCE="${INSTANCE:-hc-vault}"
export RECOVERY_KEYS_PATH=/tmp/recovery-keys/keys.init
export VAULT_ADDR=
export VAULT_POD_SELECTOR="${VAULT_POD_SELECTOR:-app.kubernetes.io/instance=hc-vault}"
export VAULT_POD_ADDRESS=
export RECOVERY_TRESHOLD="${RECOVERY_TRESHOLD:-1}"
export RECOVERY_SHARES="${RECOVERY_SHARES:-1}"
export ROOT_TOKEN


function init_vault(){
    log_output "Initializing Vault"

    vault operator init -recovery-shares "${RECOVERY_SHARES}" -recovery-threshold "${RECOVERY_TRESHOLD}" | tee "${RECOVERY_KEYS_PATH}" > /dev/null
}

function parse_recovery_keys(){
    counter=1
    
    recovery_keys="$( grep '^Recovery Key' "${RECOVERY_KEYS_PATH}" | awk '{print $4}' )"
    for key in ${recovery_keys} ; do
      store_key "${key}" recovery-key "${counter}"
      counter=$((counter + 1))
    done
}

function parse_root_token(){
    ROOT_TOKEN=$( grep '^Initial Root' "${RECOVERY_KEYS_PATH}" | awk '{print $4}')
    store_key "${ROOT_TOKEN}" root-token 1
}

function wait_vault_status(){
    status=""

    log_output "Waiting for vault to unseal"
    while [ "${status}" != "false" ]; do
        sleep 1
        status="$(vault status | grep ^Sealed | awk '{print $2}')"
    done
    log_output "Vault is unsealed"
}

function main() {
  select_init_pod_address
  if [ "$(get_vault_init_status)" == 'false' ]; then
    mkdir -p "$(dirname ${RECOVERY_KEYS_PATH})"
    init_vault
    parse_root_token
    parse_recovery_keys
    echo "Remove keys from disk"
    shred "${RECOVERY_KEYS_PATH}"
    wait_vault_status
  else
    echo "Vault has already been initialized, skipping."
  fi
}

main

