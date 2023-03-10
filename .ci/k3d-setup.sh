#! /bin/sh
#
# k3d-setup.sh
# Copyright (C) 2022 user <user@t470>
#
# Distributed under terms of the MIT license.
#

if [ ${#} -lt 1 ]; then
    deploy_prometheus=1
    deploy_metallb=1
    deploy_grafana=1
    deploy_nginx=1
    deploy_cert=1
else
    case "${1}" in
        prometheus )
            deploy_prometheus=1
            ;;
        metallb )
            deploy_metallb=1
            ;;
        grafana )
            deploy_grafana=1
            ;;
        nginx )
            deploy_nginx=1
            ;;
        cert-manager )
            deploy_cert=1
            ;;
    esac
fi

k3d cluster create --k3s-arg "--disable=traefik@server:0"  --k3s-arg "--disable=servicelb@server:0" --k3s-arg "--disable=metrics-server@server:0"  --k3s-arg "--disable-helm-controller@server:0" vault-config

kubectl cluster-info
sleep 1

while ! kubectl apply -f .ci/k3d/manifests/ ; do
    echo 'Retrying manifests application'
done

while [ ${deploy_prometheus} -ne 0 ]; do
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    if helm upgrade -n prometheus --install prometheus prometheus-community/kube-prometheus-stack -f .ci/k3d/helm-values/prometheus.yaml; then
        deploy_prometheus=0
    fi
    sleep 2
done

while [ ${deploy_metallb} -ne 0 ]; do
    deploy_metallb=0
    helm repo add metallb https://metallb.github.io/metallb
    helm repo update
    if ! helm upgrade -n metallb --install metallb metallb/metallb -f .ci/k3d/helm-values/metallb.yaml; then
        deploy_metallb=$((deploy_metallb+1))
    fi
    sleep 1
    if ! kubectl apply -f .ci/k3d/helm-values/metallb-advertisement.yaml; then
        deploy_metallb=$((deploy_metallb+1))
    fi
    if ! kubectl apply -f .ci/k3d/helm-values/metallb-address-pool.yaml; then
        deploy_metallb=$((deploy_metallb+1))
    fi
    sleep 1
done

while [ ${deploy_grafana} -ne 0 ]; do
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    if helm upgrade -n grafana --install grafana grafana/grafana -f .ci/k3d/helm-values/grafana.yaml; then
        deploy_grafana=0
    fi
    sleep 1
done

while [ ${deploy_nginx} -ne 0 ]; do
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    if helm upgrade -n ingress-nginx --install ingress-nginx ingress-nginx/ingress-nginx -f .ci/k3d/helm-values/ingress-nginx.yaml; then
        deploy_nginx=0
    fi
    sleep 1
done

while [ ${deploy_cert} -ne 0 ]; do
    deploy_cert=0
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.crds.yaml
    if ! helm upgrade -n cert-manager --install cert-manager jetstack/cert-manager --create-namespace; then
        deploy_cert=$((deploy_cert+1))
    fi
    sleep 1
    if ! kubectl apply -f .ci/k3d/helm-values/cert-manager-issuer.yaml; then
        deploy_cert=$((deploy_cert+1))
    fi
    sleep 1
done

