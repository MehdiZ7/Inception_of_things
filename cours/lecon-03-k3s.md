# LEÇON 3 — K3s : un Kubernetes léger

> Suite de `lecon-02-vagrant.md`. Prérequis : savoir créer deux VM avec Vagrant, se connecter en SSH, lire `systemctl`/`journalctl`.
> Objectif : à la fin, tu sais installer un **cluster K3s à deux nœuds**, expliquer son architecture, utiliser `kubectl`, diagnostiquer un nœud qui ne rejoint pas, et tu as le squelette complet de la **partie 1** du projet.

---

## Ce qu'on va construire

```
        Hôte (ton poste)
        ├── vboxnet0 : 192.168.56.1/24
        │
        ├── VM mzouhirS   : 192.168.56.110  -> K3s SERVER (control plane)
        └── VM mzouhirSW  : 192.168.56.111  -> K3s AGENT  (worker)
                     │
        réseau host-only 192.168.56.0/24
```

On travaille dans un **dossier de labo**, pas dans `p1` :
`~/Documents/iot-lab/k3s-lab/` avec son propre `Vagrantfile`.

Rappels de l'environnement : les VM vont dans `/goinfre` (scratch, effaçable), la box dans `VAGRANT_HOME`, et **seul le code dans Git compte**. Les VM sont jetables.

---

## 3.1 Kubernetes en 10 minutes (le minimum vital)

**Kubernetes** est un **orchestrateur de conteneurs**. Tu lui donnes un **état désiré** (ex. « je veux 3 répliques de cette image ») et il fait en sorte de le maintenir en permanence. C'est une **boucle de réconciliation** :

```
état désiré (dans l'API)  <---- compare ---->  état observé (les nœuds)
                \                                   /
                 \--- le contrôleur corrige la différence
```

Deux familles de composants :

- **Control plane** (le cerveau) : API server, scheduler, controller-manager, base de données d'état (etcd ou SQLite).
- **Nœuds** (les muscles) : `kubelet` (agent), runtime de conteneurs, réseau.

Tout passe par l'**API Kubernetes** (port 6443). On ne configure pas les nœuds à la main : on envoie des objets déclaratifs (`kubectl apply`), et les contrôleurs agissent.

Les objets eux-mêmes (Pod, Deployment, Service, Ingress) seront vus en leçon 4. Ici, on installe et on administre le cluster.

---

## 3.2 K3s : ce que c'est, ce que ça embarque

**K3s** est une **distribution Kubernetes certifiée**, ultra-légère, créée par Rancher. Un seul binaire (~70 Mo) qui embarque :

| Composant | Rôle |
|---|---|
| **containerd** | Runtime de conteneurs (K3s n'utilise **pas** Docker) |
| **Flannel** | Réseau des pods (CNI), en mode VXLAN (UDP 8472) |
| **CoreDNS** | DNS interne du cluster |
| **Traefik** | Ingress Controller (routage HTTP) |
| **Klipper ServiceLB** | Implémentation des Services `LoadBalancer` |
| **local-path-provisioner** | Stockage local pour les volumes persistants |
| **metrics-server** | Métriques CPU/RAM (pour `kubectl top`) |

Conséquences importantes :

1. **Ce n'est pas du Docker** : `docker ps` ne montrera pas les conteneurs Kubernetes. On utilise `crictl` (`sudo k3s crictl ps`) ou `kubectl`.
2. Les composants du control plane ne sont **pas** des pods visibles : ils tournent dans le processus `k3s server`. Tu ne verras donc pas de `kube-apiserver` dans `kubectl get pods -A` (contrairement à un cluster `kubeadm`).
3. Flannel est **embarqué** : pas de pod `flannel` non plus.
4. Par défaut, la base d'état est **SQLite** (suffisant pour un lab) ; `etcd` est optionnel.

### K3s vs Kubernetes « classique » vs K3d

| | Kubernetes classique | **K3s** | **K3d** |
|---|---|---|---|
| Installation | `kubeadm`, plusieurs binaires | 1 binaire + script | Docker |
| Control plane | pods séparés | dans le processus `k3s` | dans des conteneurs |
| Base d'état | etcd | SQLite par défaut | SQLite |
| Ingress par défaut | aucun | **Traefik** | **Traefik** |
| Usage | production | edge, IoT, lab, production légère | dev local, clusters jetables |
| Nœuds | machines | machines | conteneurs Docker |

K3s est certifié : ce que tu apprends dessus est valable sur n'importe quel Kubernetes. K3d (leçon 7) exécute **K3s dans des conteneurs Docker**.

---

## 3.3 Architecture d'un cluster K3s

### Mode serveur (`k3s server`)

Un seul processus regroupe : kube-apiserver, scheduler, controller-manager, la base d'état, le kubelet et containerd. Il écoute sur **6443** (API), **10250** (kubelet), **8472/udp** (Flannel).

```bash
sudo systemctl status k3s
sudo journalctl -u k3s -e
```

### Mode agent (`k3s agent`)

Le worker exécute : kubelet, containerd, kube-proxy et Flannel. Il **ne pilote pas** le cluster, donc **il n'a pas de kubeconfig** : `kubectl` ne s'utilise que depuis le serveur.

```bash
sudo systemctl status k3s-agent
sudo journalctl -u k3s-agent -e
```

### Le nom du nœud

Le nom du nœud Kubernetes est le **hostname** de la machine (sauf `--node-name`). D'où l'exigence du sujet : `<login>S` et `<login>SW`. **Deux hostnames identiques = deux nœuds qui se marchent dessus.**

### L'IP interne du nœud

`kubectl get nodes -o wide` affiche une colonne **INTERNAL-IP**. C'est l'IP que le nœud annonce pour le réseau des pods (Flannel) et pour l'API. Sur une VM à deux cartes (NAT + host-only), il faut **forcer** la bonne, sinon le cluster « forme » mais les pods ne communiquent pas entre nœuds. C'est le §3.6.

---

## 3.4 Installer le serveur

Le script officiel télécharge le binaire, crée l'unité systemd **`k3s.service`**, démarre le serveur et génère le kubeconfig.

```bash
# sur la VM serveur, en root (ou via sudo -i)
curl -sfL https://get.k3s.io | sh -
```

Avec les options de notre réseau (voir §3.6 pour le nom d'interface) :

```bash
curl -sfL https://get.k3s.io | sh -s - server \
  --node-ip=192.168.56.110 \
  --flannel-iface=eth1
```

Ou, plus lisible et réutilisable, via le fichier de configuration :

```yaml
# /etc/rancher/k3s/config.yaml
node-ip: 192.168.56.110
flannel-iface: eth1
```

puis :

```bash
curl -sfL https://get.k3s.io | sh -s - server
```

### Vérifier

```bash
sudo systemctl status k3s
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
```

Attendu : un nœud `Ready`, et les pods de `kube-system` (`coredns`, `traefik`, `local-path-provisioner`, `metrics-server`, `svclb-traefik-...`) en `Running` (Traefik peut mettre une minute).

### Les fichiers importants

| Fichier | Rôle |
|---|---|
| `/usr/local/bin/k3s` | le binaire (avec des liens `kubectl`, `crictl`, `ctr`) |
| `/etc/systemd/system/k3s.service` | l'unité systemd du serveur |
| `/etc/rancher/k3s/config.yaml` | options de configuration (optionnel) |
| `/etc/rancher/k3s/k3s.yaml` | **kubeconfig** du serveur |
| `/var/lib/rancher/k3s/server/node-token` | **token** d'adhésion des agents |
| `/var/lib/rancher/k3s/` | état, données, manifests |

### kubectl sans root

Le kubeconfig n'est lisible que par root. Trois pièges à connaître :

1. Un provisioner Vagrant tourne **en root** : dans le script, `~` vaut `/root` et `$USER` vaut `root`. Écris donc les chemins en clair.
2. Le `kubectl` installé par K3s est un **lien vers le binaire `k3s`**. Sans `KUBECONFIG`, il lit `/etc/rancher/k3s/k3s.yaml` (root only) et **ignore** `~/.kube/config`.
3. Il faut donc copier **et** exporter `KUBECONFIG`.

```bash
# dans le provisioner (qui tourne en root)
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
chmod 600 /home/vagrant/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> /home/vagrant/.bashrc
```

Puis, en tant que `vagrant` (nouvelle session ou `source ~/.bashrc`) :

```bash
kubectl get nodes
```

Le fichier pointe vers `https://127.0.0.1:6443`, ce qui convient sur le serveur. Depuis une autre machine, il faudrait remplacer `127.0.0.1` par `192.168.56.110`.

Alternative : installer K3s avec `--write-kubeconfig-mode 644` (ou `640` + groupe), ce qui rend `/etc/rancher/k3s/k3s.yaml` lisible, mais c'est moins propre.

### Anatomie d'un kubeconfig

```yaml
apiVersion: v1
kind: Config
clusters:
  - name: default
    cluster:
      server: https://127.0.0.1:6443
      certificate-authority-data: <CA du serveur, base64>
users:
  - name: default
    user:
      client-certificate-data: <certificat client, base64>
      client-key-data: <clé privée client, base64>
contexts:
  - name: default
    context:
      cluster: default
      user: default
      namespace: default
current-context: default
```

- `clusters` = **où** : l'adresse de l'API et la CA qui permet de vérifier le certificat du serveur.
- `users` = **qui** : un certificat client et sa clé privée (l'identité administrateur de K3s).
- `contexts` = l'association cluster + user + namespace ; `current-context` = celle utilisée par défaut.

`kubectl config view` masque les secrets (`DATA+OMITTED`) : tu peux le montrer sans risque. `--raw` les affiche en clair : à éviter.

**Ne confonds pas les deux secrets** : le **node-token** sert aux **agents** pour rejoindre le cluster ; le **kubeconfig** sert à `kubectl` pour parler à l'API en administrateur. Le premier est une simple chaîne, le second contient des certificats.

---

## 3.5 Installer un agent (le worker)

Un agent **ne pilote pas** le cluster : il n'a donc **pas besoin de kubeconfig**. Il lui faut seulement trois choses :

1. l'**URL de l'API** du serveur : `https://192.168.56.110:6443` ;
2. le **token** d'adhésion ;
3. son **IP et son interface host-only** (`node-ip` / `flannel-iface`).

### Étape 1 — Récupérer le token (sur le serveur)

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

Le token tient sur **une seule ligne**, au format `K10...::server:...`. C'est un secret : ne le colle pas dans un journal ni dans Git.

### Étape 2 — Installer l'agent (sur le worker)

```bash
curl -sfL https://get.k3s.io | \
  K3S_URL=https://192.168.56.110:6443 \
  K3S_TOKEN=<le_token> \
  sh -s - agent --node-ip=192.168.56.111 --flannel-iface=eth1
```

Décryptage :

- `K3S_URL` et `K3S_TOKEN` sont des **variables d'environnement** lues par le script d'installation. Il les écrit dans `/etc/systemd/system/k3s-agent.service.env`, et l'unité systemd les recharge via `EnvironmentFile=`.
- `sh -s - agent ...` transmet le mode `agent` et les options au binaire `k3s`.
- `--node-ip` et `--flannel-iface` sont des **options du binaire** (comme pour le serveur).

Ordre obligatoire : le serveur doit être **installé et démarré avant**, sinon l'agent tourne en boucle avec `connection refused`.

Alternative lisible : mettre `node-ip` et `flannel-iface` dans `/etc/rancher/k3s/config.yaml` (le même chemin que sur le serveur) et ne garder que `K3S_URL`/`K3S_TOKEN` en variables.

### Étape 3 — Ce que l'installateur crée

| Élément | Rôle |
|---|---|
| `/etc/systemd/system/k3s-agent.service` | unité systemd de l'agent |
| `/etc/systemd/system/k3s-agent.service.env` | `K3S_URL` et `K3S_TOKEN` |
| `/etc/rancher/k3s/config.yaml` | options communes (`node-ip`, `flannel-iface`) |
| `/etc/rancher/node/password` | mot de passe du nœud, généré au premier join |
| `/var/lib/rancher/k3s/agent/` | état de l'agent (containerd, certificats, etc.) |
| service **`k3s-agent`** | activé au démarrage |

Le script fournit aussi un désinstalleur : `/usr/local/bin/k3s-agent-uninstall.sh`.

### Étape 4 — Vérifier

Sur le **worker** :

```bash
systemctl status k3s-agent
journalctl -u k3s-agent -e
curl -k https://192.168.56.110:6443     # l'API doit répondre (même 401/403)
```

Dans les logs, cherche `Starting k3s agent` puis `Successfully registered node`.

Sur le **serveur** :

```bash
sudo k3s kubectl get nodes -o wide
```

Attendu : deux nœuds `Ready`, avec les bonnes **INTERNAL-IP** (`.110` et `.111`).

### Étape 5 — Modifier la configuration après coup

```bash
sudo nano /etc/systemd/system/k3s-agent.service.env   # URL / token
sudo nano /etc/rancher/k3s/config.yaml                # node-ip / flannel-iface
sudo systemctl daemon-reload
sudo systemctl restart k3s-agent
```

Comme pour le serveur, la configuration n'est lue **qu'au démarrage** du service.

### Tout configurer dans `config.yaml` (sans variables d'environnement)

Le fichier `/etc/rancher/k3s/config.yaml` accepte les mêmes clés que les options du binaire, **sans** le `--`. Pour un agent :

```yaml
node-ip: 192.168.56.111
flannel-iface: eth1
server: https://192.168.56.110:6443
token-file: /etc/rancher/k3s/agent-token
```

Puis :

```bash
curl -sfL https://get.k3s.io | sh -s - agent
```

Pourquoi `sh -s - agent` et pas seulement `sh -` ? C'est la règle du script d'installation :

- sans argument de commande, il déduit `server` ou `agent` ; s'il voit `K3S_URL` sans `K3S_TOKEN` **ni** `K3S_TOKEN_FILE`, il **s'arrête en erreur** ;
- en passant explicitement `agent`, il installe l'unité `k3s-agent` **sans exiger** les variables d'environnement : le binaire lira `server` et `token-file` dans `config.yaml`.

Le fichier est lu **au démarrage** du service : après modification, `systemctl restart k3s-agent`.

### Sécuriser le token

Le token permet à un nœud de **rejoindre** le cluster : c'est un secret.

1. Préfère **`token-file`** à `token` : le secret reste dans un fichier dédié, et non dans un YAML que l'on pourrait copier ou afficher par erreur.
2. Permissions : propriétaire **root**, mode **600** (`install -m 600`, ou `umask 077` + `chmod 600`).
3. Ne l'affiche jamais : pas de `cat`, pas de `set -x` autour, pas de `echo` dans un log.
4. Ne le commit jamais.

Côté **serveur**, après installation :

```bash
umask 077
sudo cat /var/lib/rancher/k3s/server/node-token > /vagrant/confs/node-token
chmod 600 /vagrant/confs/node-token
```

Côté **worker** :

```bash
install -m 600 /vagrant/confs/node-token /etc/rancher/k3s/agent-token
```

Comme `/vagrant` est ton dossier de projet, ajoute **impérativement** dans `.gitignore` :

```
confs/node-token
```

Variante plus étanche : déclarer dans le Vagrantfile un dossier synchronisé **hors du dépôt** :

```ruby
config.vm.synced_folder "~/.iot-secrets", "/secrets", create: true
```

et échanger le token via `/secrets/node-token` : il n'est alors jamais dans le repo. Dans les deux cas, supprimer la copie partagée après la jonction réduit l'exposition.

Si le token fuite, considère-le comme compromis : pour un lab, le plus simple est de recréer le cluster ; en production, applique la procédure de rotation de K3s.

### Erreurs fréquentes de jonction

| Message | Cause / correctif |
|---|---|
| `connection refused` / `no route to host` | serveur arrêté, mauvaise URL, port 6443 bloqué |
| `token is not valid` / `401` | token erroné → corriger l'env puis redémarrer |
| `Node password rejected` / `duplicate hostname` | hostname identique à un autre nœud, ou ancien `/etc/rancher/node/password` → supprimer le nœud côté serveur (`kubectl delete node <nom>`), supprimer le fichier, redémarrer |
| l'agent boucle et n'apparaît pas | `node-ip`/`flannel-iface` faux, ou hostname en double |

### Sans partage manuel du token (pour la p1)

Dans un Vagrantfile, le dossier synchronisé `/vagrant` permet au serveur d'écrire le token et au worker de le lire :

```bash
# sur le serveur, dans le script de provisioning
sudo cat /var/lib/rancher/k3s/server/node-token > /vagrant/confs/node-token

# sur le worker
TOKEN=$(cat /vagrant/confs/node-token)
```

Le serveur doit être provisionné **avant** le worker (ordre des `define`), sinon le token n'existe pas encore.

---

## 3.6 Le piège des deux interfaces (`node-ip` / `flannel-iface`)

Chaque VM a **deux** cartes :

| Carte | Rôle | IP |
|---|---|---|
| `eth0` (NAT) | accès Internet | `10.0.2.15` |
| `eth1` (host-only) | réseau du projet | `192.168.56.110` / `.111` |

Sans précision, K3s peut choisir la carte **NAT** comme IP du nœud. Le cluster peut sembler fonctionner, mais :

- `INTERNAL-IP` affiche `10.0.2.15` ;
- le worker ne peut pas joindre cette IP (elle n'existe que dans son propre NAT) ;
- Flannel envoie le trafic des pods vers la mauvaise interface → **pas de communication entre pods de nœuds différents**.

### Les deux options

- **`--node-ip`** : l'IP que le nœud annonce (INTERNAL-IP) et utilise pour l'API.
- **`--flannel-iface`** : l'interface utilisée par Flannel pour le VXLAN.

Il faut les deux, cohérentes, sur l'interface **host-only**. Vérifie le nom exact avec `ip a` (souvent `eth1` sur les boxes `bento`, `enp0s8` avec les noms prédictibles).

### Vérification

```bash
sudo k3s kubectl get nodes -o wide
# INTERNAL-IP doit être 192.168.56.110 / .111, PAS 10.0.2.15
```

Si tu as déjà installé sans les options, corrige puis redémarre :

```bash
sudo systemctl restart k3s          # serveur
sudo systemctl restart k3s-agent    # worker
```

> **Le fichier de configuration n'est lu qu'au démarrage du service.** Relancer `curl ... | sh -s - server` sur un serveur déjà actif ne garantit pas un redémarrage (le script ne fait qu'un `start` si le service tourne déjà). Il faut un `systemctl restart k3s` explicite, sinon `INTERNAL-IP` reste sur l'ancienne valeur.

---

## 3.7 kubectl : les commandes utiles

```bash
kubectl get nodes -o wide                  # nœuds + IP internes
kubectl get pods -A                        # tous les namespaces
kubectl get pods -n kube-system -o wide    # pods système
kubectl describe node <nom>                # conditions, capacités, événements
kubectl get events -A --sort-by=.lastTimestamp
kubectl api-resources                      # tous les types d'objets
kubectl explain pod.spec                   # documentation intégrée
kubectl config view                        # kubeconfig effectif
kubectl top nodes                          # nécessite metrics-server (peut prendre 1-2 min)
```

Rappels :
- `-n <namespace>` cible un namespace ; `-A` = tous.
- `describe` est **la** commande de diagnostic (section `Events` en bas).
- `kubectl` en tant que root avec le lien K3s : `sudo k3s kubectl ...`.
- Les **Events** sont éphémères : durée de vie d'**une heure** par défaut. Sur un cluster inactif depuis longtemps, `get events` peut renvoyer « No resources found » : ce n'est pas une erreur. Déclenche une action (créer un pod) pour en voir apparaître. Pour trier sur un champ toujours rempli, utilise `--sort-by=.metadata.creationTimestamp`.

### Comprendre `api-resources`

`kubectl api-resources` liste **tous les types d'objets** que l'API du cluster connaît (les natifs + ceux ajoutés par des CRD, comme ceux de Traefik ou d'Argo CD plus tard). C'est le catalogue de ce que tu peux manipuler.

```bash
kubectl api-resources
```

Colonnes :

| Colonne | Signification |
|---|---|
| `NAME` | nom au **pluriel**, utilisé dans `kubectl get <name>` |
| `SHORTNAMES` | alias pratiques (`po`, `svc`, `deploy`, `ing`, `rs`…) |
| `APIVERSION` | groupe/version de l'API — c'est le `apiVersion` d'un manifeste |
| `NAMESPACED` | `true` = objet rangé dans un namespace ; `false` = objet de cluster (ex. `nodes`) |
| `KIND` | type singulier — c'est le `kind` d'un manifeste (`Pod`, `Deployment`…) |

Exemples de ton cluster :

```
pods          po     v1                           true   Pod
deployments   deploy apps/v1                      true   Deployment
services      svc    v1                           true   Service
ingresses     ing    networking.k8s.io/v1         true   Ingress
ingressroutes        traefik.io/v1alpha1          true   IngressRoute
nodes         no     v1                           false  Node
```

C'est **indispensable pour écrire un YAML** : le couple `apiVersion` + `kind` vient directement de ces colonnes. Et les `SHORTNAMES` expliquent pourquoi `kubectl get po` fonctionne.

Variantes utiles :

```bash
kubectl api-resources -o wide                 # ajoute VERBS et CATEGORIES
kubectl api-resources --namespaced=true       # seulement les objets de namespace
kubectl api-resources --namespaced=false      # seulement les objets de cluster
kubectl api-resources --api-group=apps        # seulement un groupe d'API
kubectl api-versions                          # liste les groupes/versions disponibles
```

À noter : `nodes` et `pods` apparaissent **deux fois**, une fois en `v1` (les vrais objets) et une fois en `metrics.k8s.io` (`NodeMetrics`, `PodMetrics`). `kubectl get nodes` utilise la version `v1`.

---

## 3.8 Ce que tu vois dans `kube-system`

Après installation, `kubectl get pods -A` montre entre autres :

| Pod | Rôle |
|---|---|
| `coredns-*` | DNS interne (`mon-service.mon-namespace.svc.cluster.local`) |
| `traefik-*` | Ingress Controller (utile en p2) |
| `svclb-traefik-*` | DaemonSet qui expose Traefik sur les ports 80/443 des nœuds |
| `local-path-provisioner-*` | volumes persistants locaux |
| `metrics-server-*` | métriques (`kubectl top`) |

Tu ne verras **pas** l'API server, le scheduler, etc. : ils sont dans le processus `k3s`, pas dans des pods. C'est aussi le cas de **Flannel** (embarqué dans k3s : il configure l'interface `flannel.1`, il n'y a pas de pod `flannel`) et de **kube-proxy**.

### Pourquoi `svclb-traefik` a un pod par nœud

Le Service `traefik` est de type **LoadBalancer**. Dans K3s, il est implémenté par **ServiceLB** (Klipper), qui crée un **DaemonSet** `svclb-traefik-<hash>` : un pod par nœud. Chaque pod **réserve les ports 80 et 443 sur l'IP de son nœud** (`hostPort`) et redirige vers le Service `traefik` (ClusterIP). C'est pour cela que `kubectl get svc -n kube-system traefik` affiche **les deux IP des nœuds** en EXTERNAL-IP : `http://192.168.56.110` et `http://192.168.56.111` arrivent tous deux à Traefik. Si tu ajoutes un nœud, un pod `svclb` apparaît automatiquement dessus ; si tu retires le nœud, il disparaît.

Le nom du DaemonSet contient un hash (`svclb-traefik-ec0b776b`), donc `kubectl get ds svclb-traefik` renvoie `NotFound` : utilise `kubectl get ds -n kube-system`.

Le pod `svclb` a **2 conteneurs** (`2/2`) : un par port exposé (80 et 443).

---

## 3.9 Exploitation : services, logs, arrêt, désinstallation

```bash
# état et logs
sudo systemctl status k3s
sudo journalctl -u k3s -e
sudo journalctl -u k3s-agent -e

# redémarrer
sudo systemctl restart k3s

# démarrage automatique au boot (déjà fait par le script)
sudo systemctl is-enabled k3s
```

Désinstallation propre (scripts fournis par K3s) :

```bash
/usr/local/bin/k3s-uninstall.sh          # sur le serveur
/usr/local/bin/k3s-agent-uninstall.sh    # sur l'agent
```

À connaître pour repartir de zéro proprement, sans `destroy`.

---

## 3.10 Diagnostic : le cluster ne forme pas

| Symptôme | Première vérification |
|---|---|
| `kubectl get nodes` : un seul nœud | `systemctl status k3s-agent` + `journalctl -u k3s-agent -e` |
| Agent en `CrashLoop` / redémarre | token faux, URL injoignable, hostname en double |
| `Node NotReady` | `kubectl describe node <nom>` (conditions, last heartbeat), logs k3s |
| `INTERNAL-IP` = `10.0.2.15` | `--node-ip` / `--flannel-iface` absents (§3.6) |
| API injoignable depuis le worker | `curl -k https://192.168.56.110:6443` sur le worker ; `ss -tlnp \| grep 6443` sur le serveur |
| Pods système en `Pending` | ressources, taints, `kubectl describe pod` |
| `kubectl` : `connection refused` | mauvais kubeconfig, mauvais port, service arrêté |

Test de reachability de l'API depuis le worker :

```bash
curl -k https://192.168.56.110:6443
# une réponse JSON (même 401/403) = l'API est joignable
```

---

## 3.11 Lien avec la p1

Le squelette de la p1 est exactement ce que tu viens de faire, réparti en deux scripts :

| Élément | Où |
|---|---|
| 2 VM, hostnames, IP, ressources | `Vagrantfile` (déjà validé en leçon 2) |
| installation du serveur + `node-ip`/`flannel-iface` | `scripts/server.sh` |
| publication du token | `/vagrant/confs/node-token` |
| installation de l'agent avec `K3S_URL`/`K3S_TOKEN` | `scripts/worker.sh` |
| vérification | `kubectl get nodes` → 2 × `Ready` |

Pièges déjà rencontrés, à ne pas répéter : ordre de démarrage, hostnames uniques, nom de carte (`eth1`), `/tmp` volatile, et `vb.name` unique.

---

## 3.12 Annexe — crictl et premier pod (TP12–TP13)

### Pourquoi `docker ps` ne montre rien

K3s **n'utilise pas Docker** : il embarque **containerd**. Donc :

- soit `docker` n'est pas installé → `command not found` ;
- soit il l'est, mais Docker et containerd sont **deux démons différents** : `docker ps` ne voit jamais les conteneurs de containerd.

Les conteneurs K3s vivent dans containerd, sous `/var/lib/rancher/k3s/agent/containerd`.

### `crictl`, l'outil pour voir les conteneurs de K3s

`crictl` parle le **CRI** (Container Runtime Interface) au containerd de K3s. K3s fournit un lien `/usr/local/bin/crictl -> k3s`, donc on utilise `sudo k3s crictl ...` (le wrapper connaît le bon socket).

```bash
sudo k3s crictl ps           # conteneurs en cours SUR CE NŒUD
sudo k3s crictl ps -a        # tous, y compris arrêtés
sudo k3s crictl pods         # sandboxes/pods SUR CE NŒUD
sudo k3s crictl images       # images téléchargées
sudo k3s crictl inspect <id> # détails d'un conteneur
```

Point crucial : **`crictl` est local au nœud**. Lancé sur le serveur, il ne montre pas les conteneurs du worker. `kubectl`, lui, voit tout le cluster.

### Pod vs conteneur

- **Pod** : unité Kubernetes, planifiée sur un nœud. Ses conteneurs partagent le **même réseau** (même IP, même `localhost`) et les mêmes volumes, et ont un cycle de vie commun.
- **Conteneur** : un processus OCI géré par containerd. Un pod contient **1 à N conteneurs**, plus une *sandbox* (pause) qui tient le namespace réseau.
- Exemple concret : `svclb-traefik-...` est **un** pod avec **deux** conteneurs (`lb-tcp-80`, `lb-tcp-443`).

Conséquence : les nombres de conteneurs et de pods ne sont pas égaux. Il faut tenir compte des pods multi-conteneurs, des Jobs `Completed` (conteneurs arrêtés) et du périmètre (nœud vs cluster).

### Déployer un premier pod

**Impératif** (rapide) :

```bash
kubectl run nginx --image=nginx
```

**Déclaratif** (ce qu'on fera en leçon 4) :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
    - name: nginx
      image: nginx:1.25
      ports:
        - containerPort: 80
```

```bash
kubectl apply -f pod.yaml
kubectl get pods -o wide            # STATUS Running + NODE
kubectl logs nginx                  # logs du conteneur
kubectl exec -it nginx -- sh        # puis : curl localhost
kubectl delete pod nginx
```

À retenir : un **Pod nu n'est pas auto-réparé**. S'il meurt ou si on le supprime, il disparaît. En pratique, on utilise un **Deployment** (leçon 4) qui maintient le nombre de réplicas.

---

## 3.13 TP — À toi de jouer

> Aucune solution n'est donnée. Consigne tout dans `cours/journal-lecon3.txt` : commandes, sorties utiles, erreurs et cause.
> Crée un dossier `~/Documents/iot-lab/k3s-lab` avec un Vagrantfile à deux VM, indépendant de `p1`.

### TP 1 — Préparer le labo
1. Crée `~/Documents/iot-lab/k3s-lab` et un `Vagrantfile` avec deux VM : `mzouhirS` (`192.168.56.110`) et `mzouhirSW` (`192.168.56.111`), 1 vCPU / 1024 Mo, noms VirtualBox uniques.
2. Démarre-les, vérifie les hostnames et les IP dans chaque VM.
3. Depuis l'hôte et depuis chaque VM, vérifie que tout le monde se joint sur `192.168.56.0/24`.
4. Note le **nom exact** de l'interface host-only dans chaque VM (`ip a`).

### TP 2 — Installer le serveur
1. Sur `mzouhirS`, installe K3s en mode serveur en forçant l'IP et l'interface host-only.
2. Vérifie l'état du service et les dernières lignes de log.
3. Depuis le serveur, liste les nœuds et les pods de tous les namespaces.
4. Vérifie la colonne `INTERNAL-IP` : est-elle correcte ?

### TP 3 — Explorer l'installation
1. Localise le binaire, l'unité systemd, le kubeconfig, le token et le dossier d'état.
2. Vérifie la taille et le format du token **sans le copier en clair** dans ton journal (c'est un secret) : il tient sur une seule ligne.
3. Regarde ce que contient le kubeconfig (adresse de l'API, certificats).
4. Explique dans ton journal la différence entre `/etc/rancher/k3s/k3s.yaml` et `~/.kube/config`.

### TP 4 — Maîtriser kubectl
1. Liste les nœuds en mode `wide`.
2. Liste tous les pods de tous les namespaces.
3. Décris le nœud serveur : relève ses conditions, son IP interne et ses capacités.
4. Affiche les événements triés par date.
5. Affiche la liste des types d'objets disponibles (`api-resources`) et la doc de `pod.spec` (les 20 premières lignes).

### TP 5 — kubectl sans root
1. Configure `kubectl` pour ton utilisateur `vagrant`.
2. Vérifie que `kubectl get nodes` fonctionne **sans** `sudo` et **sans** préfixe `k3s`.
3. Vérifie les permissions de `~/.kube/config`. Sont-elles acceptables ? Pourquoi ce fichier est-il sensible ?

### TP 6 — Rejoindre le worker
1. Récupère le token sur le serveur.
2. Installe K3s en mode agent sur `mzouhirSW`, avec l'URL de l'API et l'IP/interface host-only.
3. Depuis le serveur, vérifie que les deux nœuds sont `Ready` et que les `INTERNAL-IP` sont `.110` et `.111`.
4. Vérifie que le worker **n'a pas** de kubeconfig utilisable, et explique pourquoi.

### TP 7 — Le piège des interfaces
1. Sur le serveur, compare l'`INTERNAL-IP` des nœuds avec les IP réelles des VM.
2. Si l'une des IP est `10.0.2.x`, corrige la configuration (fichier ou options), redémarre les services concernés, et vérifie à nouveau.
3. Depuis le worker, teste la reachability de l'API du serveur sur le port 6443 avec `curl -k`.
4. Note ce qui se passerait pour la communication entre pods si `flannel-iface` était la mauvaise interface.

### TP 8 — Robustesse au redémarrage
1. Redémarre les deux VM (`vagrant reload`).
2. Vérifie que `k3s` et `k3s-agent` redémarrent automatiquement (`is-enabled`, `status`).
3. Vérifie que le cluster a retrouvé ses deux nœuds `Ready`.
4. Combien de temps le worker met-il à repasser `Ready` ?

### TP 9 — Casser le token
1. Sur le worker, arrête l'agent et relance-le avec un **mauvais** token (modifie la configuration ou la variable du service).
2. Observe `journalctl -u k3s-agent` et `kubectl get nodes` côté serveur.
3. Répare et vérifie le retour à `Ready`.
4. Note le message d'erreur exact et sa signification.

### TP 10 — Casser l'API
1. Arrête le service serveur.
2. Depuis le worker, teste `curl -k https://192.168.56.110:6443`, puis regarde l'état du nœud côté serveur (avant l'arrêt, puis après redémarrage).
3. Relance le serveur et observe combien de temps le cluster met à se stabiliser.
4. Explique pourquoi le worker reste `NotReady` quand l'API est absente.

### TP 11 — Explorer `kube-system`
1. Liste les pods de `kube-system` avec leur nœud (`-o wide`).
2. Identifie le rôle de chacun (CoreDNS, Traefik, svclb, local-path, metrics-server).
3. Explique pourquoi tu ne vois **pas** de pod `kube-apiserver` ni de pod `flannel`.
4. Affiche le DaemonSet `svclb-traefik` et explique pourquoi il y a un pod par nœud.

### TP 12 — crictl, pas Docker
1. Lance `docker ps` sur le serveur : que vois-tu, et pourquoi ?
2. Utilise `crictl` (via le binaire K3s) pour lister les conteneurs.
3. Compare le nombre de conteneurs avec le nombre de pods.
4. Explique la différence entre un **pod** et un **conteneur** dans ce contexte.

### TP 13 — Premier déploiement
1. Déploie un pod `nginx` (impératif ou manifeste, au choix).
2. Vérifie qu'il est `Running` et sur quel nœud il tourne.
3. Affiche ses logs et entre dedans pour tester `curl localhost`.
4. Supprime-le et vérifie qu'il a disparu.

### TP 14 — Tout reconstruire
1. Détruis les deux VM.
2. Recrée-les avec une seule commande.
3. Vérifie que le cluster se reforme **sans intervention manuelle** : deux nœuds `Ready`, bonnes IP internes.
4. Combien de temps prend l'ensemble ? Note les points qui pourraient échouer (ordre, token, interface).

### TP 15 — Diagnostic guidé
Provoque, observe, répare (une panne à la fois) :
1. Un hostname identique sur les deux VM.
2. Un token erroné.
3. Une `flannel-iface` incorrecte.
4. Un `node-ip` en `10.0.2.x`.
5. Le service serveur arrêté.
Pour chaque cas : symptôme, commande de diagnostic, cause, correctif.

---

## 3.14 Questions de la leçon 3

### Partie A — Concepts

**A1.** Qu'est-ce qu'un orchestrateur de conteneurs ? Explique la boucle de réconciliation avec tes mots.

**Ta réponse :**
un orchestateur de conteneur permet de gerer les des conteneur via une api.
on donne un etat attendu et l ochestrateur se charge lui meme de faire correspondre l etat actuel avec celui attendu. c est la boucle de reconciliation

**Verdict : OK.**
**Correction :** Bonne définition. L'orchestrateur compare en continu l'**état désiré** (dans l'API) et l'**état observé** (les nœuds) ; les contrôleurs corrigent l'écart. C'est bien la boucle de réconciliation.

**A2.** Quels composants forment le control plane, et quels composants tournent sur chaque nœud ?

**Ta réponse :**
API serverm schedulerm controller-manager nase de donnees detat,
sur chaque noeur tourne kubelet

**Verdict : Partiel.**
**Correction :** Control plane : **kube-apiserver**, **kube-scheduler**, **kube-controller-manager**, **cloud-controller-manager** et la **base d'état** (etcd ou SQLite) — dans K3s, tout cela tourne dans le processus `k3s server`. Sur chaque nœud : **kubelet**, **containerd** (runtime), **kube-proxy** et **Flannel** (CNI).

**A3.** Cite quatre composants embarqués par K3s et leur rôle.

**Ta réponse :**
containerd runtime de conteneurs
flannel reseau de pods
codeDNS DNS interne du cluster
traefik ingress controller
klipper ServiceLB implementation de services loadbalancer
metrics-server metrique CPU/ram

**Verdict : OK.** Six composants cités (il en fallait quatre), rôles justes. Orthographe : CoreDNS.

**A4.** Pourquoi `docker ps` ne montre-t-il pas les conteneurs Kubernetes dans K3s ? Que faut-il utiliser à la place ?

**Ta réponse :**
Docker n est pas utiliser dans k3s. cest containerd qui est utiliser.
sudo k3s crictl ps

**Verdict : OK.**
**Correction :** Exact. Docker et containerd sont deux démons distincts ; `docker ps` ne voit pas les conteneurs de containerd. `sudo k3s crictl ps` liste les conteneurs du nœud courant (`-a` inclut les arrêtés).

**A5.** Donne trois différences entre K3s et un Kubernetes « classique » installé avec kubeadm.

**Ta réponse :**
k3s tient en un binaire alors que l autre en a plusieur
base d etat fonctionne avec etcd tandis que k3s avec SQLITE
il n y a aucun ingress par defaut sur TRAEFIK

**Verdict : Partiel.**
**Correction :** Deux points justes (un binaire vs plusieurs ; SQLite vs etcd). Le troisième est faux : K3s **fournit Traefik par défaut** (ainsi que ServiceLB et local-path) ; c'est un Kubernetes `kubeadm` qui n'a **aucun** Ingress Controller par défaut. Autre différence : les composants du control plane sont embarqués dans un seul processus.

### Partie B — Installation

**B1.** Que fait exactement la commande `curl -sfL https://get.k3s.io | sh -` ? Cite au moins quatre effets.

**Ta réponse :**
il installe k3s en mode silencieux. suis les redirection. affiche un code
erreur en cas de fail. en fonction de la configuration donne, il installe l agent ou l e serveur

**Verdict : Partiel.**
**Correction :** Tu décris surtout les options de `curl` (`-s` silencieux, `-f` échec sur erreur HTTP, `-L` suit les redirections). Mais la question demande les **effets** : télécharge le script d'installation, pose le binaire `/usr/local/bin/k3s`, crée les liens `kubectl`/`crictl`/`ctr`, crée l'unité systemd (`k3s.service` ou `k3s-agent.service`), l'active et la démarre, écrit le fichier d'environnement ; en mode serveur, génère le kubeconfig et le token.

**B2.** Où se trouvent le kubeconfig du serveur et le token ? À quoi sert chacun ?

**Ta réponse :**
/var/lib/k3s/server
le token est l identite du serveur. il permet aux agent de se connecter
kubeconfig permet d acceder au commande kubectl

**Verdict : Partiel (chemins faux).**
**Correction :**
- kubeconfig : **`/etc/rancher/k3s/k3s.yaml`** — il contient les certificats admin qui permettent à `kubectl` de parler à l'API.
- token : **`/var/lib/rancher/k3s/server/node-token`** — secret qui permet à un agent de rejoindre le cluster.

**B3.** Pourquoi le kubeconfig n'est-il lisible que par root, et comment le rendre utilisable par l'utilisateur `vagrant` ?

**Ta réponse :**
il est installe par vagrant en mode root, il est donc lisible que par route.
en le deplacant dans /home/vagrant/root, en lui donner le bon chown et en creant une variable d env cela peut etre utiliser en mode vagrant

**Verdict : Partiel.**
**Correction :** Il est généré par le **serveur** (root) avec les certificats admin, en mode **600**. Le chemin n'est pas `/home/vagrant/root` mais **`/home/vagrant/.kube/config`**. Il faut : copier, `chown vagrant:vagrant`, `chmod 600`, puis **exporter `KUBECONFIG=$HOME/.kube/config`** (le `kubectl` de K3s ignore `~/.kube/config` sans cette variable).

**B4.** Quelle est la différence entre `k3s kubectl` et `kubectl` seul ? Dans quel cas le second échoue-t-il ?

**Ta réponse :**
c est la meme chose. sauf que kubectl seul echoue dans le cas ou il la precedente manipulation n a pas ete effectue

**Verdict : OK (avec une nuance).**
**Correction :** C'est le même binaire : `k3s kubectl` est la sous-commande, et le lien `kubectl` pointe vers `k3s`. `k3s kubectl` utilise par défaut `/etc/rancher/k3s/k3s.yaml` ; `kubectl` seul échoue si tu n'es pas root et que `KUBECONFIG` n'est pas défini (permission refusée sur le kubeconfig root).

**B5.** Que se passe-t-il si tu installes un agent sans fournir `K3S_URL` et `K3S_TOKEN` ?

**Ta réponse :**
il ne pourra pas se connecter au serveur. si le mot agent n est pas preciser pendant l installation, alors il installera un serveur

**Verdict : OK.**
**Correction :** Exact. Le script exige `K3S_TOKEN` (ou `K3S_TOKEN_FILE`) si `K3S_URL` est défini, et sans `agent` ni `K3S_URL` il installe un serveur.

### Partie C — Réseau et jonction

**C1.** Quel port utilise l'API Kubernetes ? Quel protocole/port utilise Flannel ?

**Ta réponse :**
api kubernetes utilise le port 6443
flannel le protocole udp sur le port 8472

**Verdict : OK.**

**C2.** À quoi servent `--node-ip` et `--flannel-iface` ? Que se passe-t-il si on les omet sur une VM à deux cartes ?

**Ta réponse :**
il permet de forcer l adresse ip d une noeud ainsi que le nom de la carte reseau

**Verdict : Partiel (il manque la conséquence).**
**Correction :** `--node-ip` fixe l'IP annoncée par le nœud (INTERNAL-IP) ; `--flannel-iface` fixe l'interface utilisée par le VXLAN. Si on les omet sur une VM à deux cartes, K3s peut choisir la carte NAT (`10.0.2.15`) : l'INTERNAL-IP est fausse et les pods de nœuds différents ne communiquent plus.

**C3.** Comment vérifies-tu que le nœud annonce la bonne IP interne ?

**Ta réponse :**
kubectl get nodes -o wide

**Verdict : OK.** La colonne `INTERNAL-IP` doit afficher `192.168.56.110` / `.111`.

**C4.** Comment prouver, depuis le worker, que l'API du serveur est joignable ?

**Ta réponse :**
en faisant un curl k de l adresse du serveur

**Verdict : OK.**
**Correction :** `curl -k https://192.168.56.110:6443` ; une réponse `401`/`403` (ou du JSON) prouve que l'API répond. `-k` ignore le certificat auto-signé.

**C5.** Deux VM ont le même hostname. Que se passe-t-il côté cluster, et pourquoi ?

**Ta réponse :**
il y aura un conflit et un probleme aura lieu

**Verdict : Partiel.**
**Correction :** Le nom du nœud est le hostname, et il doit être **unique**. Le second agent est rejeté (`Node password rejected` / duplicate hostname), ou il entre en conflit avec le nœud existant : le cluster devient instable, un nœud peut passer `NotReady` ou disparaître.

**C6.** Pourquoi le worker n'a-t-il pas de kubeconfig ? Où doit-on lancer `kubectl` ?

**Ta réponse :**
le worker n a pas besoin de gerer les noeud. il n a donc pas besoin de kubeconfig. on lance kubectl uniquement au niveau du server

**Verdict : OK.**

### Partie D — kubectl et exploitation

**D1.** Quelle commande liste les nœuds avec leur IP interne ? Quelle commande liste tous les pods de tous les namespaces ?

**Ta réponse :**
kubectl get nodes -A

**Verdict : À revoir.**
**Correction :** `kubectl get nodes -o wide` (la colonne INTERNAL-IP), et `kubectl get pods -A` pour tous les namespaces. `-A` ne s'applique pas aux nœuds : ce sont des objets de **cluster**, pas de namespace. `kubectl get nodes` seul suffit déjà à tous les voir.

**D2.** Quelle commande utiliser pour diagnostiquer un nœud `NotReady` ? Que regardes-tu dedans ?

**Ta réponse :**
kubectl get nodes -o wide

**Verdict : Partiel.**
**Correction :** `kubectl describe node <nom>` : regarde les **Conditions** (`Ready`, `MemoryPressure`, `DiskPressure`, `PIDPressure`) et la section **Events** en bas. `get nodes` sert à voir le statut, pas à diagnostiquer la cause.

**D3.** Quels pods trouve-t-on dans `kube-system` après une installation K3s par défaut ? Cite-en au moins quatre avec leur rôle.

**Ta réponse :**
on trouve les pods de flannel, metric , ... tout les service utilisable par k3s

**Verdict : À revoir.**
**Correction :** `coredns` (DNS interne), `traefik` (Ingress Controller), `svclb-traefik-*` (ServiceLB, un pod par nœud), `local-path-provisioner` (volumes persistants), `metrics-server` (métriques), plus les Jobs `helm-install-*`. **Flannel n'est pas un pod** : il est embarqué dans k3s.

**D4.** Pourquoi ne voit-on pas de pod `kube-apiserver` ni de pod `flannel` ?

**Ta réponse :**
ils sont dans le processus k3s et non pas de pods.

**Verdict : OK.**

**D5.** Quelles commandes affichent les logs du serveur et de l'agent ? Et comment redémarres-tu chaque service ?

**Ta réponse :**
sudo journalctl -u k3s -e
sudo journalctl -u k3s-agent -e
sudo systemctl restart k3s

**Verdict : Partiel.**
**Correction :** Logs corrects. Pour les redémarrages, il en manque un : `sudo systemctl restart k3s` **et** `sudo systemctl restart k3s-agent` (chacun sur sa machine).

**D6.** Comment désinstaller proprement K3s sur le serveur et sur l'agent ?

**Ta réponse :**
il faut lancer les script fourni par k3s dans /usr/local/bin/k3s...

**Verdict : Partiel.**
**Correction :** `/usr/local/bin/k3s-uninstall.sh` sur le serveur et `/usr/local/bin/k3s-agent-uninstall.sh` sur l'agent (deux scripts distincts).

### Partie E — Diagnostic

Pour chaque situation, donne le **symptôme attendu**, la **première commande** et la **cause probable** :

**E1.** `kubectl get nodes` ne montre qu'un seul nœud.

**Ta réponse :**
verifier le token.

**Verdict : Partiel.**
**Correction :** Symptôme : un seul nœud. Première commande : `systemctl status k3s-agent` puis `journalctl -u k3s-agent -e`. Causes possibles : agent arrêté, token erroné, URL injoignable, hostname en double. Le token n'est qu'une cause parmi d'autres.

**E2.** Le nœud worker est `NotReady` et redémarre en boucle.

**Ta réponse :**
verifie s il le script d initialisation

**Verdict : Partiel.**
**Correction :** `journalctl -u k3s-agent -e` et `systemctl status k3s-agent`. Causes : token/URL invalides, API injoignable, hostname en double ou `node password` rejeté, `node-ip`/`flannel-iface` incorrects.

**E3.** Les deux nœuds sont `Ready` mais `INTERNAL-IP` affiche `10.0.2.15` pour l'un d'eux.

**Ta réponse :**
verifie si on a bien donner node-ip

**Verdict : OK (à compléter).**
**Correction :** Vérifier `node-ip` **et** `flannel-iface`, corriger la configuration puis redémarrer `k3s`/`k3s-agent`, et contrôler avec `kubectl get nodes -o wide`.

**E4.** Depuis le worker, `curl -k https://192.168.56.110:6443` renvoie `Connection refused`.

**Ta réponse :**
verifier le tokem

**Verdict : À revoir.**
**Correction :** `Connection refused` signifie que l'API **n'écoute pas** ou n'est pas joignable : serveur arrêté, mauvaise IP/port, pare-feu. Ce n'est pas un problème de token. Vérifier sur le serveur `systemctl status k3s` et `ss -tlnp | grep 6443`.

**E5.** Le pod `coredns` est en `Pending`.

**Ta réponse :**
aucune idee

**Verdict : À revoir.**
**Correction :** `Pending` = pod **non planifié**. `kubectl describe pod -n kube-system <coredns>` → section Events (`FailedScheduling`). Causes : CPU/RAM insuffisants, taints/affinité, aucun nœud `Ready`, PVC non lié. Vérifier `kubectl get nodes` et `kubectl top nodes`.

### Partie F — Lien avec le projet

**F1.** Associe chaque exigence de la p1 à l'étape correspondante de cette leçon.

**Ta réponse :**
<!-- non répondu au moment de la correction -->

**Verdict : à connaître.**
**Réponse :**

| Exigence de la p1 | Étape de la leçon 3 |
|---|---|
| Deux VM, hostnames et IP `192.168.56.110/.111` | Vagrant (leçon 2) + `vm.hostname` / `private_network` |
| K3s en mode controller sur la 1re VM | §3.4 : installation serveur avec `node-ip`/`flannel-iface` |
| K3s en mode agent sur la 2e VM | §3.5 : installation agent avec `server`/`token-file` |
| Token partagé entre serveur et worker | §3.5 : `/vagrant/confs/node-token` + `token-file` |
| `kubectl` utilisable | §3.4 : kubeconfig dans `/home/vagrant/.kube/config` + `KUBECONFIG` |
| Vérification | §3.10 : `kubectl get nodes -o wide` → 2 × `Ready` |

**F2.** Pourquoi le serveur doit-il être installé avant le worker, et comment le worker récupère-t-il le token dans un Vagrantfile ?

**Ta réponse :**
<!-- non répondu au moment de la correction -->

**Verdict : à connaître.**
**Réponse :** Le token est **généré par l'installation du serveur** (`/var/lib/rancher/k3s/server/node-token`). Si le worker démarre avant, le token n'existe pas et il ne peut pas rejoindre le cluster. Dans un Vagrantfile, l'ordre des `config.vm.define` détermine l'ordre de provisioning : le script du serveur écrit le token dans le dossier synchronisé (`/vagrant/confs/node-token`), et le script du worker le lit pour alimenter `token-file`.

**F3.** Quelles vérifications ferais-tu en soutenance pour prouver que la p1 fonctionne ?

**Ta réponse :**
<!-- non répondu au moment de la correction -->

**Verdict : à connaître.**
**Réponse :** Depuis le serveur : `kubectl get nodes -o wide` (2 nœuds `Ready`, `INTERNAL-IP` = `192.168.56.110` et `.111`), `kubectl get pods -n kube-system` (pods `Running`), `systemctl status k3s` ; sur le worker : `systemctl status k3s-agent`, `journalctl -u k3s-agent -e`, `curl -k https://192.168.56.110:6443` ; depuis l'hôte : SSH sans mot de passe sur les deux VM ; enfin, `vagrant destroy -f && vagrant up` pour prouver la reproductibilité.

**F4.** Quels sont les deux pièges de cette leçon qui, s'ils sont mal gérés, font que « le cluster a l'air OK » mais ne fonctionne pas réellement ?

**Ta réponse :**
<!-- non répondu au moment de la correction -->

**Verdict : à connaître.**
**Réponse :**
1. **`node-ip` / `flannel-iface` absents ou faux** : les nœuds sont `Ready`, mais `INTERNAL-IP` vaut `10.0.2.15` et les pods de nœuds différents ne communiquent pas.
2. **Hostnames identiques** : conflit de nom de nœud (`Node password rejected` / duplicate hostname), un nœud peut être rejeté ou instable alors que l'installation semble avoir réussi.

---

## Mémo de la leçon

| Besoin | Commande |
|---|---|
| Installer le serveur | `curl -sfL https://get.k3s.io \| sh -s - server --node-ip=... --flannel-iface=...` |
| Installer l'agent | `K3S_URL=https://IP:6443 K3S_TOKEN=... curl -sfL https://get.k3s.io \| sh -s - agent ...` |
| État des services | `systemctl status k3s` / `systemctl status k3s-agent` |
| Logs | `journalctl -u k3s -e` / `journalctl -u k3s-agent -e` |
| Token | `sudo cat /var/lib/rancher/k3s/server/node-token` |
| kubeconfig | `sudo cat /etc/rancher/k3s/k3s.yaml` |
| Nœuds + IP | `kubectl get nodes -o wide` |
| Pods système | `kubectl get pods -n kube-system -o wide` |
| Diagnostic nœud | `kubectl describe node <nom>` |
| Conteneurs réels | `sudo k3s crictl ps` |
| Désinstaller | `/usr/local/bin/k3s-uninstall.sh` / `k3s-agent-uninstall.sh` |

---

Quand tu as terminé les TP et répondu aux questions : envoie-moi **« Leçon 3 terminée »** avec ton journal. Je corrigerai dans ce fichier, puis nous passerons à la **leçon 4 : les objets Kubernetes** (Pod, Deployment, ReplicaSet, Service, YAML, namespaces) — le cœur de la p2.
