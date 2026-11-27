# Inception of Things (IoT)

> Projet d'administration système (42) : découvrir Kubernetes à travers **K3s**, **Vagrant**, **K3d** et **Argo CD**.
>
> Ce README est le document unique du projet. Il sera complété au fur et à mesure de l'avancement (p1, p2, p3, bonus).

---

## Sommaire

- [Présentation](#présentation)
- [Structure du dépôt](#structure-du-dépôt)
- [Prérequis](#prérequis)
- [Partie 1 — K3s & Vagrant](#partie-1--k3s--vagrant)
- [Partie 2 — K3s & trois applications](#partie-2--k3s--trois-applications)
- [Partie 3 — K3d & Argo CD](#partie-3--k3d--argo-cd-à-venir)
- [Bonus — GitLab](#bonus--gitlab-à-venir)
- [Sécurité](#sécurité)

---

## Présentation

Le projet consiste à construire, par étapes, une infrastructure Kubernetes reproductible :

1. **p1** : deux machines virtuelles créées par **Vagrant**, formant un cluster **K3s** serveur + agent.
2. **p2** : trois applications web exposées via un **Ingress** (routage HTTP par nom d'hôte) sur un cluster K3s.
3. **p3** : un cluster **K3d** (K3s dans Docker) et un déploiement **GitOps** avec **Argo CD** depuis un dépôt GitHub public.
4. **bonus** : une instance **GitLab** locale intégrée au cluster.

Le fil rouge : **tout est décrit par du code** (Vagrantfile, scripts, manifests YAML), versionné dans Git et reproductible.

---

## Structure du dépôt

```
.
├── README.md
├── p1/
│   ├── Vagrantfile
│   ├── confs/
│   │   ├── server.yaml
│   │   ├── worker.yaml
│   │   └── node-token        # généré, ignoré par Git
│   └── scripts/
│       ├── server.sh
│       └── worker.sh
├── p2/
│   ├── Vagrantfile
│   ├── confs/
│   │   └── server.yaml
│   ├── scripts/
│   │   ├── server.sh
│   │   └── deploy.sh
│   └── manifest/
│       ├── app1.yaml
│       ├── app2.yaml
│       ├── app3.yaml
│       └── ingress.yaml
├── p3/                       # à venir
├── bonus/                    # à venir
└── cours/                    # notes de cours (hors rendu)
```

Les dossiers `p1`, `p2` et `p3` (et `bonus`) sont à la **racine** du dépôt, comme demandé par le sujet. Chacun contient ses fichiers de configuration (`confs/`) et ses scripts (`scripts/`).

---

## Prérequis

- **Vagrant** (testé avec 2.4.9)
- **VirtualBox** (testé avec 7.2.x), utilisateur membre du groupe `vboxusers`
- Une box Ubuntu : `bento/ubuntu-24.04`
- De l'espace disque pour la box et les disques de VM (idéalement un espace scratch type `/goinfre`)

Remarque : le projet ne nécessite **pas** `sudo`. Selon la machine, le stockage global de Vagrant (`VAGRANT_HOME`) doit pointer vers un disque suffisamment grand, car les box peuvent être volumineuses.

---

## Partie 1 — K3s & Vagrant

### Objectif

Mettre en place un cluster Kubernetes léger composé de deux machines virtuelles, entièrement décrites et provisionnées par Vagrant :

- `mzouhirS` : nœud **serveur** K3s (control plane) — `192.168.56.110`
- `mzouhirSW` : nœud **agent** K3s (worker) — `192.168.56.111`

Le cluster doit être **reproductible** : `vagrant destroy -f && vagrant up` doit recréer un environnement fonctionnel sans intervention manuelle.

### Architecture

```
        Hôte (ton poste)
        ├── VirtualBox
        ├── vboxnet0 : 192.168.56.1/24
        │
        ├── VM mzouhirS   : 192.168.56.110   → k3s server (control plane)
        └── VM mzouhirSW  : 192.168.56.111   → k3s agent  (worker)
                     │
        réseau host-only 192.168.56.0/24
```

Chaque VM a deux cartes : **NAT** (`eth0`, accès Internet) et **host-only** (`eth1`, réseau du projet). K3s est forcé à utiliser `eth1` pour son IP de nœud et pour Flannel.

### Structure de `p1/`

```
p1/
├── Vagrantfile
├── confs/
│   ├── server.yaml       # config K3s du serveur (node-ip, flannel-iface)
│   ├── worker.yaml       # config K3s de l'agent (node-ip, server, token-file)
│   └── node-token        # généré au provisioning, ignoré par Git
└── scripts/
    ├── server.sh         # installation + configuration du serveur
    └── worker.sh         # installation + configuration de l'agent
```

Le fichier `confs/node-token` est un **secret** : généré au premier `vagrant up` et exclu du dépôt via `.gitignore`. Le dossier `.vagrant/` est également ignoré.

### Fonctionnement

**Vagrantfile**

- Deux machines déclarées avec `config.vm.define`.
- Hostnames `mzouhirS` / `mzouhirSW`, noms VirtualBox identiques et **uniques**.
- Réseau **host-only** avec IP fixes `.110` / `.111`.
- Ressources minimales : **1 vCPU** et **1024 Mo** de RAM par VM.
- Un script de provisioning par machine, le serveur étant déclaré **avant** le worker.

**Script serveur (`scripts/server.sh`)**

1. Installe les prérequis (`curl`).
2. Copie `confs/server.yaml` vers `/etc/rancher/k3s/config.yaml` (force `node-ip` et `flannel-iface`).
3. Installe K3s en mode **serveur**.
4. Rend `kubectl` utilisable par l'utilisateur `vagrant` :
   - copie du kubeconfig dans `/home/vagrant/.kube/config`,
   - permissions `600`,
   - export idempotent de `KUBECONFIG` dans `~/.bashrc`.
5. Publie le **token** dans `confs/node-token` (dossier synchronisé `/vagrant`) avec des droits restrictifs.
6. Redémarre K3s pour garantir la prise en compte de la configuration.

**Script worker (`scripts/worker.sh`)**

1. Installe les prérequis (`curl`).
2. Copie `confs/worker.yaml` vers `/etc/rancher/k3s/config.yaml` (force `node-ip`, `flannel-iface`, `server`, `token-file`).
3. Copie le token dans un fichier root-only (`/etc/rancher/k3s/agent-token`).
4. Installe K3s en mode **agent** sans blocage systemd, puis démarre le service.
5. Le worker rejoint automatiquement le cluster.

### Répartition des secrets

| Secret | Emplacement | Droits | Versionné ? |
|---|---|---|---|
| Token de jonction | `p1/confs/node-token` | `600` | **non** (`.gitignore`) |
| Kubeconfig admin | `/etc/rancher/k3s/k3s.yaml` (VM) | `600` root | non (dans la VM) |
| Kubeconfig utilisateur | `/home/vagrant/.kube/config` (VM) | `600` | non (dans la VM) |
| `.vagrant/` (état local) | projet | — | **non** (`.gitignore`) |

### Utilisation

```bash
cd p1
vagrant up            # crée, démarre et provisionne les deux VM
vagrant status
vagrant ssh mzouhirS
vagrant ssh mzouhirSW
```

Pour repartir de zéro :

```bash
vagrant destroy -f
vagrant up
```

**SSH sans mot de passe**

L'authentification se fait par **clé SSH** (pas de mot de passe) :

```bash
# méthode 1 : via Vagrant
vagrant ssh mzouhirS
vagrant ssh mzouhirSW

# méthode 2 : avec la clé générée par Vagrant
ssh -i .vagrant/machines/mzouhirS/virtualbox/private_key vagrant@192.168.56.110
ssh -i .vagrant/machines/mzouhirSW/virtualbox/private_key vagrant@192.168.56.111
```

`vagrant ssh-config <nom>` affiche l'utilisateur, le port et le chemin de la clé effectivement utilisés. Pour que la commande littérale `ssh vagrant@192.168.56.110` fonctionne sans `-i`, il faut configurer la clé côté poste (entrée `~/.ssh/config` ou `ssh-add`) ; ce n'est pas géré par le projet.

**kubectl**

Depuis le **serveur** (le worker ne pilote pas le cluster) :

```bash
vagrant ssh mzouhirS
kubectl get nodes -o wide
kubectl get pods -A
```

Le shell de `vagrant` exporte `KUBECONFIG` et utilise le kubeconfig copié dans `~/.kube/config`.

### Vérifications

```bash
# deux nœuds Ready, bonnes IP internes
kubectl get nodes -o wide

# pods système
kubectl get pods -n kube-system
```

Résultat attendu :

| Nœud | Statut | INTERNAL-IP | Rôle |
|---|---|---|---|
| `mzouhirs` | `Ready` | `192.168.56.110` | control-plane |
| `mzouhirsw` | `Ready` | `192.168.56.111` | \<none\> |

On doit également voir dans `kube-system` : `coredns`, `traefik`, `svclb-traefik` (un pod par nœud), `local-path-provisioner`, `metrics-server`.

### Dépannage de la p1

| Symptôme | Cause probable / piste |
|---|---|
| `vagrant up` bloqué à « Waiting for machine to boot / SSH address » | VM figée au boot. Vérifier la console (`VBoxManage controlvm <vm> screenshotpng`). Un écran bloqué sur `clk: Disabling unused clocks` pointe vers la paravirtualisation KVM ; forcer `--paravirtprovider none` peut débloquer. |
| `k3s-agent` reste en `activating` | Unité `Type=notify` avec attente infinie. Les scripts démarrent l'agent avec `INSTALL_K3S_SKIP_START=true` puis `systemctl start --no-block`. |
| Un seul nœud visible | `systemctl status k3s-agent` et `journalctl -u k3s-agent -e` : token, URL, hostname, port 6443. |
| `INTERNAL-IP = 10.0.2.15` | `node-ip` / `flannel-iface` absents ou faux. Corriger la config puis redémarrer K3s. |
| `Node password rejected` / duplicate hostname | Deux VM avec le même hostname, ou ancien `/etc/rancher/node/password`. Utiliser des hostnames uniques ; supprimer l'ancien nœud si nécessaire. |
| `Connection refused` sur `https://192.168.56.110:6443` | API non joignable : serveur arrêté, mauvaise IP/port, pare-feu. |
| `ssh vagrant@IP` demande un mot de passe | Utiliser `vagrant ssh` ou `ssh -i <clé>` ; voir la section SSH. |
| `/vagrant` vide dans la VM | Guest Additions absentes ou `vboxfs` en échec. |
| VM perdues après changement de poste | Les disques sont sur un espace scratch (`/goinfre`) non portable. Le code, lui, est dans Git : recréer avec `vagrant up`. |

---

## Partie 2 — K3s & trois applications

### Objectif

Un seul nœud K3s (`mzouhirS`, `192.168.56.110`) expose **trois applications web** sur le port 80, routées par nom d'hôte :

- `app1.com` → `app1` (1 réplica) ;
- `app2.com` → `app2` (3 réplicas) ;
- tout autre `Host` → `app3` (route par défaut).

Le routage HTTP (couche 7) est assuré par l'**Ingress** de **Traefik**, installé par défaut avec K3s. Les trois Services restent des `ClusterIP` : ils ne sont pas exposés directement.

### Architecture

```
        client (curl / navigateur)
          │  Host: app1.com | app2.com | autre
          ▼
   192.168.56.110:80  →  Traefik (Ingress Controller K3s)
          ├── app1.com  →  Service app1  →  Deployment app1  (1 pod)
          ├── app2.com  →  Service app2  →  Deployment app2  (3 pods)
          └── défaut    →  Service app3  →  Deployment app3  (1 pod)
```

### Structure de `p2/`

```
p2/
├── Vagrantfile
├── confs/
│   └── server.yaml          # node-ip + flannel-iface
├── scripts/
│   ├── server.sh            # installation de K3s serveur + kubeconfig
│   └── deploy.sh            # attente de l'API, apply des manifests, attente des rollouts
└── manifest/
    ├── app1.yaml            # ConfigMap + Service + Deployment app1
    ├── app2.yaml            # idem, avec replicas: 3
    ├── app3.yaml            # idem app3
    └── ingress.yaml         # règles Host + route par défaut
```

### Fonctionnement

**Vagrantfile**

- une seule VM `mzouhirS`, hostname `mzouhirS`, IP host-only `192.168.56.110` ;
- 1 vCPU, **2048 Mo** de RAM (K3s + Traefik + 5 pods) ;
- provisioning en deux temps : `server.sh` puis `deploy.sh`.

**Script serveur (`scripts/server.sh`)**

1. installe `curl` ;
2. copie `confs/server.yaml` dans `/etc/rancher/k3s/config.yaml` (`node-ip`, `flannel-iface`) ;
3. installe K3s en mode **serveur** ;
4. copie le kubeconfig dans `~vagrant/.kube/config` et exporte `KUBECONFIG` ;
5. redémarre K3s pour appliquer la configuration.

**Script de déploiement (`scripts/deploy.sh`)**

1. attend que l'API réponde ;
2. attend que le nœud soit `Ready` ;
3. applique tous les manifests de `manifest/` ;
4. attend la fin des rollouts des trois Deployments ;
5. attend que l'Ingress reçoive son adresse ;
6. affiche l'état final (`deploy`, `svc`, `ingress`).

**Manifests**

- chaque application a son **ConfigMap** (`index.html`), son **Service `ClusterIP`** et son **Deployment** ;
- `app2` a `replicas: 3`, `app1` et `app3` ont `replicas: 1` ;
- `ingress.yaml` définit deux règles `Host` (`app1.com`, `app2.com`) et une règle **sans `Host`** qui sert de route par défaut vers `app3`.

### Utilisation

```bash
cd p2
vagrant up
```

Pour tout reconstruire :

```bash
vagrant destroy -f
vagrant up
```

### Vérifications

Depuis la VM ou depuis l'hôte :

```bash
# état des objets
vagrant ssh mzouhirS -c 'kubectl get deploy,svc,ingress'

# les trois routes
curl -H 'Host: app1.com' http://192.168.56.110
curl -H 'Host: app2.com' http://192.168.56.110
curl http://192.168.56.110
```

Résultat attendu :

| Requête | Réponse |
|---|---|
| `Host: app1.com` | `Welcome from APP1` |
| `Host: app2.com` | `Welcome from APP2` |
| sans `Host` (ou autre) | `Welcome from APP3` |
| `kubectl get deploy app2` | `READY 3/3` |
| `kubectl get ingress` | `apps-ingress` avec l'adresse `192.168.56.110` |

Depuis un navigateur, ajouter les entrées dans `/etc/hosts` de ton poste :

```
192.168.56.110  app1.com
192.168.56.110  app2.com
```

### Dépannage de la p2

| Symptôme | Cause probable / piste |
|---|---|
| `404` sur `http://192.168.56.110/` | aucune règle par défaut, ou Ingress non appliqué (`kubectl get ingress`) |
| `503` sur un `Host` | Service backend absent, ou sans endpoints (`kubectl get endpointslices`) |
| `app1.com` renvoie `404` | faute de frappe dans l'en-tête `Host`, ou règle absente |
| `app2.com` ne répond pas | `app2` n'a pas ses 3 réplicas prêtes, ou le Service ne cible pas les pods |
| Ingress sans adresse | Traefik n'est pas prêt : `kubectl get pods -n kube-system` |
| `404` de Traefik malgré l'Ingress | `ingressClassName: traefik` manquant ou faux |
| Erreur au `vagrant up` sur `deploy.sh` | API pas encore prête ; relancer `vagrant provision` |

---

## Partie 3 — K3d & Argo CD (à venir)

À compléter : installation de K3d, namespaces `argocd` et `dev`, dépôt GitHub public, déploiement **GitOps** avec Argo CD, changement de version `v1` → `v2`.

---

## Bonus — GitLab (à venir)

À compléter : instance GitLab locale dans le cluster, namespace `gitlab`, intégration avec le déploiement GitOps.

---

## Sécurité

- Le token de jonction est stocké en `600` et **jamais** versionné.
- Le kubeconfig contient des certificats **admin** : il reste sur le serveur, avec des permissions restrictives.
- `.vagrant/` contient l'UUID des VM et des clés privées locales : il n'est pas versionné.
- Aucun mot de passe n'est utilisé pour SSH : uniquement des clés.
- Ne jamais ajouter un token au dépôt, même temporairement.

---

## Suite

Ce dépôt sera complété au fur et à mesure :

- [x] p1 — Vagrant + K3s (serveur + agent)
- [x] p2 — trois applications + Ingress
- [ ] p3 — K3d + Argo CD
- [ ] bonus — GitLab
