#!/bin/bash

set -e

export KUBECONFIG=/home/vagrant/.kube/config

if [ ! -r "$KUBECONFIG" ]; then
  echo "ERROR : $KUBECONFIG can't be found" >&2
  exit 1
fi

echo ">>> Waiting for k3s API ..."
for i in $(seq 1 60); do
  if kubectl get nodes >/dev/null 2>&1; then
    echo "    API available ($i try)."
    break
  fi
  sleep 2
done

echo ">>> Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=180s

echo ">>> Applying manifest..."
kubectl apply -f /vagrant/manifest/

echo ">>> Waiting for rollout..."
kubectl rollout status deployment/app1 --timeout=180s
kubectl rollout status deployment/app2 --timeout=180s
kubectl rollout status deployment/app3 --timeout=180s

echo ">>> Waiting for ingress adress..."
for i in $(seq 1 30); do
  addr=$(kubectl get ingress apps-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "$addr" ]; then
    echo "    Ingress ready on $addr"
    break
  fi
  sleep 2
done

echo ">>> Final state :"
kubectl get deploy,svc,ingress

