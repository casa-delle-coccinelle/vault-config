#! /bin/sh

export VAULT_VERSION=1.12.0
export KUBECTL_VERSION=v1.25.4
export VERSION="$(grep ^version: ../../charts/vault-config/Chart.yaml | awk '{print $2}')"


docker build --tag vault-operator:${VERSION} --build-arg "KUBECTL_VERSION=${KUBECTL_VERSION}" --build-arg "VAULT_VERSION=${VAULT_VERSION}" -f Dockerfile .

if [ "${#}" == 1 ]; then
    docker tag "vault-operator:${VERSION}" "${1}:${VERSION}"
    docker push "${1}:${VERSION}"
fi
