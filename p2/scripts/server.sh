#!/bin/bash

set -e

apt update
apt install -y curl

mkdir -p /etc/rancher/k3s
cp /vagrant/confs/server.yaml /etc/rancher/k3s/config.yaml
curl -sfL https://get.k3s.io | sh -s - server

mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
chmod 600 /home/vagrant/.kube/config
grep -qxF 'export KUBECONFIG=$HOME/.kube/config' /home/vagrant/.bashrc \
|| echo 'export KUBECONFIG=$HOME/.kube/config' >> /home/vagrant/.bashrc


systemctl restart k3s
