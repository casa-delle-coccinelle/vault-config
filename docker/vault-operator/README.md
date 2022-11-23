# Vault Operator Image
To be used with https://github.com/casa-delle-coccinelle/vault-operator
Image provides basic software kit to enable operator chart to configurte vault service.

## Builds
To manually build a new image use
```
docker build --tag vault-operator:${VERSION} --build-arg "KUBECTL_VERSION=${KUBECTL_VERSION}" --build-arg "VAULT_VERSION=${VAULT_VERSION}" -f Dockerfile .
```

To build and push an image, run
```
bash build.sh
```
