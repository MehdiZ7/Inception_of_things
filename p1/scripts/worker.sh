#!/bin/bash

set -e

apt update
apt install -y curl

mkdir -p /etc/rancher/k3s
cp /vagrant/confs/worker.yaml /etc/rancher/k3s/config.yaml
install -m 600 /vagrant/confs/node-token /etc/rancher/k3s/agent-token

curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true sh -s - agent

systemctl start --no-block k3s-agent
