#! /bin/bash

SECRET_FILE=./.ci/k3d/manifests/hc-vault-dynamodb-backend-secret.yaml

echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
echo "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
if [ ! -f "${SECRET_FILE}" ]; then
    kubectl -n hc-vault create secret generic hc-vault-dynamodb-backend \
        --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
        --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
        --dry-run=client \
        -o yaml > "${SECRET_FILE}"
fi
