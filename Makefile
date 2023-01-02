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

.PHONY: get-root-token
get-root-token:
	aws secretsmanager get-secret-value --secret-id hc-vault/hc-vault-table-test-cluster-nfs/root-token/key-1

.PHONY: fix-traffic
fix-traffic:
	sudo sysctl net.ipv4.ip_unprivileged_port_start=79
	kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 443:443 &
	kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 80:80 &
	grep -q grafana.vault.dev /etc/hosts || sudo bash -c "echo '127.0.0.1 grafana.vault.dev vault.vault.dev alert.vault.dev prom.vault.dev' >> /etc/hosts"


# vim:ft=make
#
