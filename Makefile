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

.PHONY: get-ca
get-ca:
	kubectl -n cert-manager get secret default-cluster-issuer-ca -o yaml | yq '.data."ca.crt"' | base64 --decode > .ci/ca.pem
	kubectl -n cert-manager get secret default-cluster-issuer-ca -o yaml | yq '.data."tls.crt"' | base64 --decode >> .ci/ca.pem
	kubectl -n cert-manager get secret default-cluster-issuer-ca -o yaml | yq '.data."tls.key"' | base64 --decode >> .ci/ca.pem
	echo "CA in .ci/ca.pem"

.PHONY: deploy-all
deploy-all: clear-aws generate-aws-secret k3d-setup vault get-ca inject-prometheus

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
	aws secretsmanager get-secret-value --secret-id hc-vault/vault-dev/root-token/key-1

.PHONY: fix-traffic
fix-traffic:
	kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8443:8443 1>/dev/null 2>/dev/null &
	kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:8080 1>/dev/null 2>/dev/null &
	grep -q grafana.vault.dev /etc/hosts || sudo bash -c "echo '127.0.0.1 grafana.vault.dev vault.vault.dev alert.vault.dev prom.vault.dev' >> /etc/hosts"

.PHONY: inject-prometheus
inject-prometheus:
	kubectl -n prometheus rollout restart statefulset prometheus-prometheus-kube-prometheus-prometheus

# vim:ft=make
#
