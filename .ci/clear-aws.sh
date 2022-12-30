#! /bin/bash

export SECRETS_PREFIX=hc-vault/hc-vault
export DYNAMO_TABLE=hc-vault-table-test-cluster-nfs


aws secretsmanager delete-secret --secret-id "${SECRETS_PREFIX}/root-token/key-1" --force-delete-without-recovery

aws secretsmanager delete-secret --secret-id "${SECRETS_PREFIX}/recovery-key/key-1" --force-delete-without-recovery;

aws dynamodb delete-table --table-name "${DYNAMO_TABLE}" 
