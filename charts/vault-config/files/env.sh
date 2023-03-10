#! /bin/bash
#
# env.sh
# Copyright (C) 2022 user <user@zbook>
#
# Distributed under terms of the MIT license.
#

function log_output() {
    echo "[$(date -Is)] ${*}" >&2
}

function login(){
  # Authenticates with vault root token
  export VAULT_TOKEN

  log_output "Getting credentials from AWS secretsmanager"
  log_output "Getting root token ARN"
  token_ARN="$(
    aws \
      secretsmanager \
      list-secrets \
      --filters Key=name,Values="hc-vault/${INSTANCE}/root-token/key-1" | grep ARN | awk '{print $2}' | sed 's/,$//g' | sed 's/^"//g' | sed 's/"$//g' | head -1
  )"
  if [ "${token_ARN}" == "" ]; then
      echo "Token not found"
      exit 1
  else
      log_output "Token ARN: ${token_ARN}"
      VAULT_TOKEN="$(
        aws \
          secretsmanager \
          get-secret-value \
          --secret-id "${token_ARN}" | grep SecretString | awk '{print $2}' | sed 's/,$//g' | sed 's/^"//g' | sed 's/"$//g' | head -1
      )"
      log_output "Verifiyng vault token"
      vault token lookup | grep ^display_name
      e_code="${?}"

      if [ "${e_code}" != 0 ]; then
          log_output "Vault token is invalid"
          exit 2
      fi
  fi
}

function store_key() {
  key=${1}
  key_type=${2}
  id=${3}

  log_output "Storing key ${id} of type ${key_type}"
  log_output "Trying to create AWS secret for key ${id} of type ${key_type}"
  secret_arn="$(
    aws \
      secretsmanager \
      create-secret \
      --name "hc-vault/${INSTANCE}/${key_type}/key-${id}" 2>/dev/null | grep ARN | awk '{print $2}' | sed 's/,$//g' | sed 's/^"//g' | sed 's/"$//g'
  )"


  if [ "${secret_arn}" == "" ]; then
      log_output "Creation of AWS secret failed. Trying to use existing one."
      secret_arn="$(
        aws \
          secretsmanager \
          list-secrets \
          --filters Key=name,Values="hc-vault/${INSTANCE}/${key_type}/key-${id}" | grep ARN | awk '{print $2}' | sed 's/,$//g' | sed 's/^"//g' | sed 's/"$//g' | head -1
      )"
      if [ "${secret_arn}" == "" ]; then
          log_output "Can create OR reuse secret for key ${id} of type ${key_type}. Exiting"
          exit 3
      fi
  fi
  aws secretsmanager put-secret-value --secret-id "${secret_arn}" --secret-string "${key}"
  if ! aws secretsmanager put-secret-value --secret-id "${secret_arn}" --secret-string "${key}"; then
      log_output "Can't store key ${id} of type ${key_type} in AWS SecretsManager"
      exit 4
  fi
}

function get_vault_init_status(){
  vault_init_status=''
  resp_code=000

  log_output "Checking if vault instance has booted"
  while [ "${resp_code}" == "000" ]; do
    resp_code="$(curl -L -s "${VAULT_ADDR}" -o /dev/null -w "%{http_code}")"
    sleep 1
  done

  log_output "Checking vault init status"
  while [ "${vault_init_status}" == "" ]; do
    vault_init_status="$(vault status | grep ^Initialized | awk '{ print $2}')"
    sleep 1
  done

  log_output "Vault init status: ${vault_init_status}"
  echo "${vault_init_status}"
}

function ipvalid() {
    # Set up local variables
    local ip=${1:-NO_IP_PROVIDED}
    local IFS=.; local -a a=(${ip})
    # Start with a regex format test
    [[ $ip =~ ^[0-9]+(\.[0-9]+){3}$ ]] || return 1
    # Test values of quads
    local quad
    for quad in {0..3}; do
        [[ "${a[$quad]}" -gt 255 ]] && return 1
    done
    return 0
}


function select_init_pod_address(){
    log_output "Selecting vault pod for initialization"
    export VAULT_ADDR
    export VAULT_POD_ADDRESS

    while [ "${VAULT_ADDR}" == "" ]; do
        vault_first_pod="$(
            kubectl \
                --namespace "${VAULT_NAMESPACE}" \
                get pods \
                -l "${VAULT_POD_SELECTOR}" \
                --template '{{ range .items }}{{ .status.podIP }}{{ "\n" }}{{ end }}' | \
            sort -u | \
            head -n 1
        )"
        if ipvalid "${vault_first_pod}"; then
            VAULT_ADDR="http://${vault_first_pod}:8200"
            VAULT_POD_ADDRESS="${vault_first_pod}"
        fi
        sleep 1
    done
    log_output "Vault address: ${VAULT_ADDR}"
}

