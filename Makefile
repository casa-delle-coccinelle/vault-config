.PHONY: image-build
image-build:
	cd docker/vault-operator && bash build.sh ${REGISTRY}/${IMAGE_NAME}

.PHONY: k3d-setup
k3d-setup:
	bash .ci/k3d-setup.sh

.PHONY: clear-aws
clear-aws:
	bash ./.ci/clear-aws.sh || true

.PHONY: generate-aws-secret
generate-aws-secret:
	bash ./.ci/generate-aws-secret.sh

.PHONY: vault
vault:
	bash ./.ci/vault.sh

.PHONY: deploy-all
deploy-all: clear-aws generate-aws-secret k3d-setup vault

.PHONY: tear-down
tear-down: clear-aws
	k3d cluster delete vault-config

.PHONY: vault-reset
vault-reset:
	bash ./.ci/vault.sh clear
	bash ./.ci/vault.sh 

.PHONY: reset
reset: tear-down deploy-all
# vim:ft=make
#
