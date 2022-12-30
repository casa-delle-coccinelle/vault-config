#! /bin/bash

if [ "${1}" == "clear" ]; then
	helm -n hc-vault delete hc-vault-config
	helm -n hc-vault delete hc-vault
else
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm upgrade -n hc-vault --install hc-vault hashicorp/vault -f ./.ci/k3d/hc-vault/vault.yaml
    helm upgrade -n hc-vault --install hc-vault-config ./charts/vault-config -f ./.ci/k3d/hc-vault/vault-config.yaml
fi
