ARG VAULT_VERSION=1.12.0
ARG KUBECTL_VERSION=v1.25.4

FROM hashicorp/vault:${VAULT_VERSION}

ARG KUBECTL_VERSION
ARG VAULT_VERSION
USER root

RUN apk add aws-cli curl bash jq
RUN echo "Install kubectl" && curl -L -s -O "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

USER vault
