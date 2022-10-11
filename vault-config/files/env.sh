#! /bin/sh
#
# env.sh
# Copyright (C) 2022 user <user@zbook>
#
# Distributed under terms of the MIT license.
#

function login(){
  # Authenticates with vault root token
  token_ARN="$(
    aws \
      secretsmanager \
      list-secrets \
      --filters Key=name,Values="hc-vault/${INSTANCE}/root-token/key-1" | grep ARN | awk '{print $2}' | sed 's/,$//g' | sed 's/^"//g' | sed 's/"$//g' | head -1
  )"

  VAULT_TOKEN="$(
    aws \
      secretsmanager \
      get-secret-value \
      --secret-id "${token_ARN}" | grep SecretString | awk '{print $2}' | sed 's/,$//g' | sed 's/^"//g' | sed 's/"$//g' | head -1
  )"
  vault token lookup | grep ^display_name
}

function store_key() {
  key=${1}
  key_type=${2}
  id=${3}

  secret_arn="$(
    aws \
      secretsmanager \
      create-secret \
      --name hc-vault/${INSTANCE}/${key_type}/key-${id} 2>/dev/null | grep ARN | awk '{print $2}' | sed 's/,$//g' | sed 's/^"//g' | sed 's/"$//g'
  )"


  if [ "${secret_arn}" == "" ]; then
      secret_arn="$(
        aws \
          secretsmanager \
          list-secrets \
          --filters Key=name,Values="hc-vault/${INSTANCE}/${key_type}/key-${id}" | grep ARN | awk '{print $2}' | sed 's/,$//g' | sed 's/^"//g' | sed 's/"$//g' | head -1
      )"
  fi
  aws secretsmanager put-secret-value --secret-id "${secret_arn}" --secret-string "${key}"
}

function get_vault_init_status(){
  vault_init_status=''
  resp_code=000

  while [ "${resp_code}" == "000" ]; do
    resp_code="$(curl -s ${VAULT_ADDR} -o /dev/null -w "%{http_code}")"
    sleep 1
  done

  while [ "${vault_init_status}" == "" ]; do
    vault_init_status="$(vault status | grep ^Initialized | awk '{ print $2}')"
    sleep 1
  done
  echo ${vault_init_status}
}

function select_init_pod_address(){
    vault_first_pod="$(
        kubectl \
            --namespace hc-vault \
            get pods \
            -l "${VAULT_POD_SELECTOR}" \
            --template '{{ range .items }}{{ .status.podIP }}{{ "\n" }}{{ end }}' | \
        sort -u | \
        head -n 1
    )"
    VAULT_ADDR="http://${vault_first_pod}:8200"
    VAULT_POD_ADDRESS="${vault_first_pod}"

}

