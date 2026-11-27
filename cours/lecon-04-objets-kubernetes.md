# LEÇON 4 — Les objets Kubernetes

> Suite de `lecon-03-k3s.md`. Prérequis : un cluster K3s à deux nœuds fonctionnel (p1) et `kubectl` utilisable depuis le serveur.
> Objectif : comprendre et manipuler les objets de base (Pod, ReplicaSet, Deployment, Service, Namespace, ConfigMap, Secret), écrire des manifests YAML, et préparer la **partie 2** du projet.

---

## Où on en est

Tu as un cluster qui **tourne** (p1). Mais un cluster vide ne sert à rien : il faut y **déployer des applications**. En Kubernetes, on ne lance pas des conteneurs « à la main » : on décrit des **objets** dans des fichiers YAML, et le cluster fait en sorte de les maintenir.

Cette leçon est le cœur de Kubernetes. La leçon 5 ajoutera la couche **Ingress** (routage HTTP par nom de domaine), qui est exactement ce que demande la p2.

---

## 4.1 Le modèle déclaratif

Un objet Kubernetes a une forme générale :

```yaml
apiVersion: <groupe/version>   # quelle API
kind: <Type>                   # quel type d'objet
metadata:
  name: <nom>
  labels: { ... }
spec:                          # l'état DÉSIRÉ
  ...
status:                        # l'état OBSERVÉ (rempli par le cluster, lecture seule)
  ...
```

- **`spec`** : ce que **tu** veux.
- **`status`** : ce que le cluster **constate**.
- Les contrôleurs comparent en boucle `spec` et `status` et corrigent l'écart. C'est la **réconciliation**.

**Impératif vs déclaratif :**

| Impératif | Déclaratif |
|---|---|
| `kubectl run`, `kubectl create deployment` | écrire un YAML puis `kubectl apply -f` |
| « fais ceci maintenant » | « voici l'état voulu » |
| non reproductible | versionnable dans Git |

`kubectl apply` est **idempotent** : l'appliquer 10 fois donne le même résultat. `kubectl create` échoue si l'objet existe déjà.

---

## 4.2 Écrire du YAML pour Kubernetes

Règles de base :

- indentation **avec des espaces** (jamais de tabulations) ;
- `clé: valeur`, listes avec `-` ;
- plusieurs documents dans un fichier, séparés par `---` ;
- commentaires avec `#`.

Les quatre clés de premier niveau : `apiVersion`, `kind`, `metadata`, `spec`.

**Où trouver `apiVersion` et `kind` ?** Dans `kubectl api-resources` (leçon 3) : la colonne `APIVERSION` donne `apiVersion`, la colonne `KIND` donne `kind`. Exemples :

| Objet | apiVersion | kind |
|---|---|---|
| Pod | `v1` | `Pod` |
| Service | `v1` | `Service` |
| Deployment | `apps/v1` | `Deployment` |
| ReplicaSet | `apps/v1` | `ReplicaSet` |
| Ingress | `networking.k8s.io/v1` | `Ingress` |
| Namespace | `v1` | `Namespace` |

**Labels et annotations** (dans `metadata`) :

- **labels** : paires clé/valeur utilisées pour **sélectionner** des objets (`app: nginx`, `tier: frontend`). Ce sont les « étiquettes » que les Services et Deployments utilisent pour trouver leurs pods.
- **annotations** : métadonnées non sélectives (description, URL, configuration d'un outil).

---

## 4.3 Pod

Le **Pod** est la plus petite unité déployable. Il regroupe **un ou plusieurs conteneurs** qui partagent :

- le **même réseau** (même IP, même `localhost`, mêmes ports) ;
- les **mêmes volumes** ;
- un **cycle de vie commun**.

Un pod est **éphémère** : s'il meurt, il n'est pas réparé (sauf s'il est géré par un ReplicaSet/Deployment). Il ne faut donc pas gérer des pods à la main en production.

### Exemple de manifeste

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  containers:
    - name: nginx
      image: nginx:1.25
      ports:
        - containerPort: 80
```

```bash
kubectl apply -f pod.yaml                    # crée ou met à jour le pod décrit
kubectl get pods -o wide                     # statut, nœud et IP du pod
kubectl describe pod nginx                   # détails du pod + Events
kubectl logs nginx                           # logs (vide tant qu'il n'y a pas de requête)
kubectl exec -it nginx -- sh                 # shell dans le conteneur (puis : curl localhost)
kubectl exec nginx -- curl -s localhost      # exécute une commande sans shell interactif
kubectl port-forward pod/nginx 8080:80       # expose le port 80 du pod sur localhost:8080
kubectl delete pod nginx                     # supprime le pod
```

### Multi-conteneurs

Un pod peut contenir plusieurs conteneurs. Le cas classique est le **sidecar** : un conteneur principal + un conteneur auxiliaire (logs, proxy, synchronisation). Ils partagent `localhost` et les volumes.

En coulisses, chaque pod possède une **sandbox** (conteneur « pause ») qui tient le namespace réseau ; c'est pour cela que `crictl` montre parfois plus de conteneurs que de pods.

---

## 4.4 Labels et sélecteurs

C'est le mécanisme de **liaison** de Kubernetes.

```yaml
metadata:
  labels:
    app: web
    tier: frontend
```

Un label est une simple paire **clé=valeur** que **tu inventes** (les clés `app`, `tier`, `env` sont des conventions, rien de réservé). En YAML on écrit `app: web` ; sur la ligne de commande, on écrit `app=web`. C'est exactement le même label.

Rien n'oblige tous les pods à avoir les mêmes labels. Exemple concret avec trois pods :

| Pod | `app` | `tier` |
|---|---|---|
| `web1` | `web` | `frontend` |
| `web2` | `web` | `frontend` |
| `api1` | `api` | `backend` |

Résultats des filtres :

| Commande | Résultat |
|---|---|
| `kubectl get pods -l app=web` | `web1`, `web2` |
| `kubectl get pods -l tier=frontend` | `web1`, `web2` |
| `kubectl get pods -l app=web,tier=frontend` | `web1`, `web2` (ET : les deux labels) |
| `kubectl get pods -l 'tier in (frontend,backend)'` | les trois |
| `kubectl get pods -l 'app notin (web)'` | `api1` |

Sélectionner :

```bash
kubectl get pods -l app=web                        # pods dont le label app vaut web
kubectl get pods -l 'tier in (frontend,backend)'   # pods dont tier vaut frontend OU backend
kubectl get pods --show-labels                     # affiche les labels de chaque pod
kubectl get pods -L app,tier                       # ajoute une colonne par label
kubectl label pod nginx env=dev                    # ajoute le label env=dev à un pod
```

Un **sélecteur** peut être :

- **d'égalité** : `app=web`, `tier!=cache` ;
- **ensembliste** : `env in (dev,prod)`, `env notin (test)`.

Les objets de plus haut niveau (ReplicaSet, Deployment, Service) utilisent `spec.selector` pour trouver leurs pods. **Règle d'or** : le sélecteur doit correspondre aux labels du template de pod, sinon l'objet ne « voit » pas ses pods. C'est la source d'erreur n°1 des débutants.

---

## 4.5 ReplicaSet

Un **ReplicaSet** garantit qu'il existe **N pods identiques**. Si un pod meurt, il en recrée un. C'est le mécanisme d'**auto-réparation**.

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:              # le pod modèle
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
```

```bash
kubectl get rs                                  # liste les ReplicaSets
kubectl scale rs/web --replicas=5               # passe le ReplicaSet à 5 pods
kubectl delete pod <un-pod-du-rs>               # supprime un pod ; le ReplicaSet le recrée
```

On utilise rarement un ReplicaSet directement : on passe par un **Deployment**, qui le gère pour nous.

---

## 4.6 Deployment

Le **Deployment** est l'objet de référence pour déployer une application. Il gère un **ReplicaSet**, qui gère les **Pods**.

Il apporte :

- **réplicas** ;
- **mise à jour progressive** (*rolling update*) sans coupure ;
- **historique des versions** et **rollback** ;
- **stratégie** (`RollingUpdate` ou `Recreate`).

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.25
          ports:
            - containerPort: 80
```

Commandes utiles :

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3   # crée un Deployment à 3 réplicas
kubectl get deploy,rs,pods                                       # voit Deployment, ReplicaSet et Pods
kubectl scale deployment/web --replicas=5                        # passe à 5 réplicas
kubectl set image deployment/web web=nginx:1.27                  # change l'image du conteneur web
kubectl rollout status deployment/web                            # suit la mise à jour en cours
kubectl rollout history deployment/web                           # liste les révisions
kubectl rollout undo deployment/web                              # revient à la révision précédente
```

### 4.6.1 Qui crée quoi : Deployment → ReplicaSet → Pods

Un Deployment ne crée **pas** directement des pods. Il crée un **ReplicaSet**, qui crée les pods :

```
Deployment "web"  (template : nginx:1.25, replicas: 3)
   └── ReplicaSet "web-7d9c8b6f5"        <- hash du template
          ├── Pod "web-7d9c8b6f5-abcde"
          ├── Pod "web-7d9c8b6f5-fghij"
          └── Pod "web-7d9c8b6f5-klmno"
```

Le nom du ReplicaSet = nom du Deployment + **hash du template de pod**. Ce détail explique tout le reste :

- modifier le **template** (image, commande, variables, volumes…) change le hash → le Deployment crée un **nouveau ReplicaSet** et effectue un rollout ;
- modifier uniquement `replicas` ou `strategy` **ne change pas** le template → **aucun nouveau ReplicaSet**, le RS courant est simplement scalé (aucun pod n'est recréé) ;
- un pod **n'est jamais modifié sur place** : changer l'image d'un Deployment ne remplace pas le conteneur d'un pod existant, il **crée d'autres pods** puis supprime les anciens ;
- les anciens ReplicaSets ne sont pas supprimés : ils restent à **0 réplica** pour permettre le rollback. `revisionHistoryLimit` vaut **10** par défaut ; au-delà, les plus vieux sont élagués.

```bash
kubectl get rs                                # ancien RS à 0/0, nouveau RS à N/N
kubectl get pods -l app=web --show-labels     # le label pod-template-hash distingue les versions
kubectl get deploy web -o wide                # READY, UP-TO-DATE, AVAILABLE
kubectl describe deployment web               # StrategyType + RollingUpdateStrategy + Conditions + Events
```

Dans `kubectl get deploy`, **UP-TO-DATE** = nombre de pods qui utilisent déjà le template courant. Pendant un `Recreate`, cette valeur passe par **0**.

### 4.6.2 La stratégie `RollingUpdate` (défaut)

Le Deployment remplace les pods **progressivement**, en créant les nouveaux **avant** de supprimer les anciens. Deux paramètres encadrent l'opération :

| Paramètre | Rôle | Défaut |
|---|---|---|
| **`maxSurge`** | combien de pods **en plus** du nombre désiré on autorise pendant l'update | `25%` |
| **`maxUnavailable`** | combien de pods **en moins** du nombre désiré peuvent être indisponibles | `25%` |

Règles exactes :

- les valeurs peuvent être un nombre absolu (`1`) ou un pourcentage des réplicas désirées (`25%`) ;
- un pourcentage de **`maxSurge` est arrondi au supérieur**, un pourcentage de **`maxUnavailable` arrondi à l'entier inférieur** ;
- **les deux ne peuvent pas être à `0`** (l'API refuse) : sinon aucun pod ne pourrait être créé ni supprimé ;
- avec `maxUnavailable: 0`, il faut `maxSurge` > 0 (c'est la configuration « zéro coupure »).

Avec les valeurs par défaut (`25% / 25%`) :

| Réplicas désirées | `maxSurge` effectif | `maxUnavailable` effectif | Pods max pendant l'update | Pods disponibles min |
|---|---|---|---|---|
| 1 | 1 | 0 | 2 | 1 |
| 2 | 1 | 0 | 3 | 2 |
| 3 | 1 | 0 | 4 | 3 |
| 5 | 2 | 1 | 7 | 4 |
| 10 | 3 | 2 | 13 | 8 |

Exemple concret avec **3 réplicas** et les valeurs par défaut :

```
départ          : 3 anciens pods prêts
création        : 3 anciens + 1 nouveau  (total 4 = 3 + maxSurge 1)
nouveau prêt    : 2 anciens + 1 nouveau  (total 3 = 3 - maxUnavailable 0)
création        : 2 anciens + 2 nouveaux (total 4)
nouveau prêt    : 1 ancien  + 2 nouveaux (total 3)
création        : 1 ancien  + 3 nouveaux (total 4)
nouveau prêt    : 0 ancien  + 3 nouveaux (total 3)  -> terminé
```

À aucun moment il n'y a moins de **3 pods prêts**. Le contrôleur peut regrouper les étapes, mais il ne franchit jamais les bornes `[réplicas - maxUnavailable, réplicas + maxSurge]`.

Configuration « zéro coupure » explicite :

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1          # 1 pod de plus au maximum
      maxUnavailable: 0    # on ne supprime un ancien qu'une fois le nouveau prêt
```

Autres réglages utiles :

- **`minReadySeconds`** (défaut `0`) : un pod doit rester `Ready` pendant N secondes avant d'être compté comme disponible ;
- **`progressDeadlineSeconds`** (défaut `600`) : si aucun progrès pendant 10 min, la condition `Progressing` passe à `False` avec la raison `ProgressDeadlineExceeded`.

**Point crucial : « prêt » ≠ « Running ».** Un pod est compté comme disponible seulement quand il est **`Ready`** (`1/1`). Sans `readinessProbe`, Kubernetes le considère prêt dès que le conteneur démarre — même si l'application n'écoute pas encore. C'est la cause classique de quelques `502` pendant un rolling update pourtant « sans coupure ».

### 4.6.3 La stratégie `Recreate`

```yaml
spec:
  strategy:
    type: Recreate
```

Comportement, dans cet ordre strict :

1. le Deployment **réduit l'ancien ReplicaSet à 0 réplica** ;
2. il **attend que tous les anciens pods aient disparu** ;
3. seulement ensuite, il **crée** le nouveau ReplicaSet et ses pods.

`maxSurge` et `maxUnavailable` **ne s'appliquent pas** à `Recreate`.

Déroulé observable :

| Étape | Ce que tu vois | Service |
|---|---|---|
| avant | ancien RS `3/3`, nouveau RS `0/0` | 3 endpoints, répond |
| arrêt | pods en `Terminating`, puis ils disparaissent | endpoints de moins en moins nombreux |
| trou | **aucun pod** pour ce label, nouveau RS `0/0` | **0 endpoint → connexion refusée** |
| redémarrage | nouveaux pods `Pending` → `ContainerCreating` → `Running` → `Ready` | endpoints qui reviennent un à un |
| fin | nouveau RS `3/3`, ancien RS `0/0` | 3 endpoints, répond |

La **durée de la coupure** = arrêt des anciens pods + téléchargement de l'image + démarrage de l'application + passage `Ready`. L'arrêt d'un pod est gracieux : `SIGTERM` au PID 1, puis `SIGKILL` après `terminationGracePeriodSeconds` (**30 s** par défaut) si le processus ne s'arrête pas avant.

Quand choisir `Recreate` :

- deux versions **ne peuvent pas coexister** : migration de base incompatible, singleton avec verrou, volume `ReadWriteOnce`, `hostPort`, licence ;
- tu **acceptes** une coupure (maintenance planifiée).

Quand l'éviter :

- application web **stateless** : `RollingUpdate` est fait pour ça ;
- si la nouvelle image est cassée, `Recreate` provoque une **panne totale** (plus aucun pod), alors qu'un `RollingUpdate` bloqué laisse les **anciens pods continuer à servir**.

Attention : changer **seulement** `strategy` ne recrée aucun pod. La stratégie ne s'applique qu'au **prochain changement de template** (image, commande…).

### 4.6.4 Comparaison

| Critère | `RollingUpdate` | `Recreate` |
|---|---|---|
| Anciens et nouveaux pods ensemble | oui, temporairement | **non, jamais** |
| Coupure de service | non (si `Ready` correct) | **oui**, pendant tout le redémarrage |
| Pods max pendant l'update | `réplicas + maxSurge` | `réplicas` (anciens **ou** nouveaux) |
| Paramètres | `maxSurge`, `maxUnavailable` | aucun |
| Vitesse | plus lente (progression contrôlée) | dépend du pull + démarrage |
| Usage typique | web, API, stateless | migration, singleton, verrou, volume exclusif |
| Image cassée | rollout bloqué, anciens pods toujours là | **panne totale** |

### 4.6.5 Cycle de vie d'un pod pendant une mise à jour

**Création d'un nouveau pod**

1. `Pending` : le scheduler choisit un nœud ;
2. `ContainerCreating` : pull de l'image, montage des volumes ;
3. `Running` : le conteneur a démarré — mais `READY` peut encore être `0/1` ;
4. `Ready` (`1/1`) : les sondes passent → le pod entre dans les **endpoints** du Service.

**Suppression d'un ancien pod**

1. le pod reçoit un `deletionTimestamp` → état `Terminating` ;
2. il est **retiré des endpoints** (le Service cesse de lui envoyer du trafic) ;
3. `SIGTERM` au PID 1 de chaque conteneur ;
4. attente de `terminationGracePeriodSeconds` (30 s par défaut) ;
5. `SIGKILL` si le processus est toujours vivant ;
6. le pod disparaît.

Nuance importante : le retrait des endpoints n'est **pas instantané** dans tout le cluster (kube-proxy, Traefik). Un `preStop` avec une petite attente (`sleep 5`) permet d'éviter des erreurs transitoires.

**Ne pas confondre deux choses :**

| Situation | Ce qui se passe |
|---|---|
| mise à jour d'image | **nouveau pod** (nouveau RS), l'ancien est **supprimé** |
| crash d'un conteneur | **même pod**, colonne `RESTARTS` incrémentée, redémarrage du conteneur |

### 4.6.6 Observer une mise à jour en direct

Ouvre **plusieurs terminaux** sur le serveur (`vagrant ssh mzouhirS`) :

```bash
# terminal 1 : cycle de vie des pods
kubectl get pods -l app=web -w

# terminal 2 : ReplicaSets (les vieux passent à 0, le nouveau monte)
kubectl get rs -w

# terminal 3 : progression du rollout (bloque jusqu'à la fin ou l'échec)
kubectl rollout status deployment/web
```

Pour mesurer une éventuelle coupure, il faut interroger l'application **en continu**. Le plus fiable est de passer par un Service (vu en 4.7) :

```bash
# Service temporaire pour joindre les pods par leur nom
kubectl expose deployment web --port=80 --target-port=80

# pod jetable qui envoie une requête toutes les 500 ms
kubectl run probe --image=curlimages/curl --restart=Never --command -- sleep 3600
kubectl exec -it probe -- sh -c \
  'while true; do curl -s -o /dev/null -w "%{http_code}\n" http://web; sleep 0.5; done'
```

- `RollingUpdate` : uniquement des `200` (à condition que les pods soient réellement `Ready`) ;
- `Recreate` : une série de `000` (connexion refusée ou timeout) entre la disparition des anciens et l'arrivée des nouveaux, puis retour des `200`.

Évite `kubectl port-forward` pour mesurer : il cible **un seul pod** ; quand ce pod est supprimé, le tunnel casse, ce qui simule une coupure même en `RollingUpdate`.

Autres commandes d'analyse :

```bash
kubectl describe deployment web                # StrategyType, RollingUpdateStrategy, Conditions
kubectl rollout history deployment/web         # révisions ; CHANGE-CAUSE = annotation change-cause
kubectl annotate deployment/web kubernetes.io/change-cause="passage a nginx:1.27"
kubectl rollout restart deployment/web         # force un nouveau RS (même image) pour redémarrer les pods
```

### 4.6.7 Pièges et points importants

- `spec.selector` est **immuable** après création (dans `apps/v1`) ;
- le sélecteur doit correspondre aux labels du template, sinon le Deployment ne « voit » pas ses pods ;
- changer d'image crée une **nouvelle révision** → nouveau ReplicaSet. Changer pour **le même tag** ne déclenche **rien** (template identique) : utilise des tags réellement différents (`1.25` → `1.27` → `1.26`) ;
- avec un tag figé, `imagePullPolicy` vaut `IfNotPresent` : si tu réécris le **même tag** dans le registry, les nœuds peuvent garder l'ancienne image en cache. En p3, les tags `v1` / `v2` règlent le problème ;
- `rollout undo` **réutilise** l'ancien ReplicaSet (il le remonte) : il ne reconstruit pas d'image et crée une **nouvelle** révision ;
- supprimer un pod géré par un Deployment le fait **recréer** par le ReplicaSet ; supprimer le ReplicaSet le fait recréer par le Deployment ;
- supprimer le Deployment supprime **en cascade** ses ReplicaSets et ses pods (`--cascade=orphan` pour les garder) ;
- un `kubectl apply` qui ne modifie pas le template **ne touche pas** aux pods.

---

## 4.7 Service

> C'est la section la plus importante de la leçon pour la p2. Lis les sous-parties **dans l'ordre** : les types de Service sont une **poupée russe**. On ne peut pas comprendre `NodePort` sans avoir compris `ClusterIP`, ni `LoadBalancer` sans avoir compris `NodePort`.

### 4.7.1 Le problème que le Service résout

Un pod a une IP **éphémère** : elle est attribuée par le réseau du cluster (Flannel) à sa création, et **change** dès qu'il est recréé. Un rolling update remplace tous les pods → toutes les IP changent. Un client ne peut donc pas viser une IP de pod.

Un **Service** apporte deux choses :

1. une **adresse stable** : son IP ne change pas quand les pods changent ;
2. une **répartition de charge** entre plusieurs pods identiques.

### 4.7.2 Trois idées fausses à éliminer

| Idée fausse | Réalité |
|---|---|
| « le Service attribue une IP à un pod » | **Non.** Le pod a déjà son IP, donnée par Flannel (`10.42.x.x`). Le Service a **sa propre** IP, virtuelle et stable (`10.43.x.x`). Elle n'appartient à aucun pod. |
| « le Service relie l'API au pod » | **Non.** Le trafic des applications ne passe jamais par le serveur d'API Kubernetes. Le Service est un point d'entrée vers un **groupe** de pods, pas vers un seul. |
| « un Service = un pod » | **Non.** Un Service peut cibler **0, 1 ou N pods**. Ce nombre varie dans le temps, sans que le Service change. |

Point clé : **le Service n'est pas un processus**. Ce sont des **règles de routage** (iptables / IPVS) écrites par `kube-proxy` sur chaque nœud. Personne n'« écoute » sur l'IP du Service : les paquets qui y sont destinés sont **réécrits** vers un pod.

### 4.7.3 Deux réseaux distincts

K3s utilise deux plages séparées, et c'est visible dans toutes les commandes :

| Réseau | Plage par défaut | Contenu | Où le voir |
|---|---|---|---|
| réseau des **pods** | `10.42.0.0/16` | IP réelles des pods (attribuées par Flannel) | `kubectl get pods -o wide` |
| réseau des **Services** | `10.43.0.0/16` | IP **virtuelles** des Services | `kubectl get svc` |

Une IP `10.42.x.x` est un pod. Une IP `10.43.x.x` est un Service. Les deux ne se mélangent jamais.

### 4.7.4 Lire un `kubectl describe svc` ligne par ligne

Voici un exemple réel (les valeurs changent chez toi) :

```
Name:                     web
Namespace:                default
Selector:                 app=web
Type:                     NodePort
IP:                       10.43.45.227
Port:                     <unset>  80/TCP
TargetPort:               80/TCP
NodePort:                 <unset>  30139/TCP
Endpoints:                10.42.1.10:80,10.42.1.9:80,10.42.0.14:80
Session Affinity:         None
External Traffic Policy:  Cluster
```

| Ligne | Signification |
|---|---|
| `Selector: app=web` | **le seul lien** entre le Service et les pods : tous les pods portant le label `app=web` sont membres du Service |
| `Type: NodePort` | le type de Service (voir 4.7.7) |
| `IP: 10.43.45.227` | l'**IP du Service** (ClusterIP) : stable, interne, dans le réseau des Services |
| `Port: 80/TCP` | le port **du Service** : ce que le client appelle |
| `TargetPort: 80/TCP` | le port **du conteneur** : là où le paquet est réellement livré |
| `NodePort: 30139/TCP` | un port ouvert sur **chaque nœud**, qui mène à ce Service |
| `Endpoints: ...` | la **liste actuelle** des pods membres, au format `IP_du_pod:targetPort` |
| `Session Affinity: None` | chaque requête peut aller vers un pod différent |
| `External Traffic Policy: Cluster` | le trafic externe peut viser n'importe quel pod (voir 4.7.10) |

La liste des endpoints est **vivante** : supprime un pod → son IP disparaît ; le ReplicaSet en recrée un → une nouvelle IP apparaît. Le `10.43.45.227`, lui, ne change **jamais**.

### 4.7.5 Les trois ports : `port`, `targetPort`, `nodePort`

```
        client
          │  appelle le port 80 du Service
          ▼
   Service web  ── ClusterIP 10.43.45.227:80
          │        (règles kube-proxy, pas un processus)
          │  réécrit vers IP_pod:80  (targetPort)
          ├──────────► pod A  10.42.1.10:80
          ├──────────► pod B  10.42.1.9:80
          └──────────► pod C  10.42.0.14:80
```

| Champ | Rôle | Exemple |
|---|---|---|
| **`port`** | port exposé par le **Service** (ce que le client utilise) | `80` |
| **`targetPort`** | port écouté par le **conteneur** (où le paquet arrive) | `80` |
| **`nodePort`** | port ouvert sur **chaque nœud** (uniquement `NodePort` / `LoadBalancer`) | `30139` |

`port` et `targetPort` peuvent être **différents**. Exemple : Service sur `8080`, conteneur sur `80` → le client appelle `8080`, nginx reçoit sur `80`.

### 4.7.6 Le seul lien : `selector` → endpoints

Le Service ne « connaît » pas les pods par leur nom. Il les trouve **par leurs labels** :

```yaml
spec:
  selector:
    app: web        # tous les pods avec ce label sont membres du Service
```

Kubernetes remplit alors automatiquement la liste des endpoints. Chaque endpoint = **IP du pod + `targetPort`**.

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web   # liste moderne (recommandée)
kubectl get endpoints web                                       # ancienne ressource, dépréciée depuis K8s 1.33
kubectl describe svc web                                        # affiche aussi les endpoints
```

> **Important** : `Endpoints` n'est **pas** un objet que tu crées à la main. Il est généré à partir du Service.
> Donc une erreur `Error from server (NotFound): endpoints "web" not found` signifie presque toujours : **le Service `web` n'existe pas** (pas encore créé, autre nom, autre namespace, ou supprimé). Un Service **sans `selector`** ne génère pas d'endpoints automatiquement non plus.

| Situation | `kubectl get endpointslices` |
|---|---|
| Service absent | rien (et `get endpoints` renvoie `NotFound`) |
| Service présent, sélecteur correct | une liste avec les IP des pods |
| Service présent, sélecteur faux | liste **vide** → aucune requête ne peut aboutir |
| Service sans `selector` | pas d'endpoints automatiques |

### 4.7.7 Les types de Service, en poupée russe

Chaque type **ajoute** une couche au précédent :

```
ClusterIP  ──►  NodePort  ──►  LoadBalancer
  interne        + porte          + load balancer
                 sur chaque       devant (dans K3s :
                 nœud             ServiceLB)
```

#### 1. `ClusterIP` (le défaut)

Une IP interne, joignable **uniquement depuis l'intérieur du cluster**.

- depuis un pod : `curl http://web` fonctionne (CoreDNS résout `web` → `10.43.x.x`) ;
- depuis ton PC : impossible, cette IP n'existe pas sur ton réseau ;
- **elle n'est pas pingable** : `ping 10.43.x.x` échoue, alors que `curl` fonctionne. C'est la preuve que ce n'est pas une interface réseau, seulement des règles TCP/UDP.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP        # valeur par défaut, on peut l'omettre
  selector:
    app: web
  ports:
    - port: 80           # port du Service
      targetPort: 80     # port du conteneur
```

#### 2. `NodePort`

**`NodePort` = `ClusterIP` + une porte ouverte sur chaque nœud.**

Kubernetes réserve un port (par défaut dans la plage **`30000–32767`**) et l'ouvre sur **toutes les machines du cluster**, au même numéro :

```
depuis ton PC ──► 192.168.56.110:30139 ──┐
depuis ton PC ──► 192.168.56.111:30139 ──┼──► Service web 10.43.45.227:80 ──► un des 3 pods
depuis la VM  ──► 192.168.56.110:30139 ──┘
```

Points importants :

- **les deux nœuds répondent**, même le worker qui n'héberge aucun pod de `app=web` : c'est `kube-proxy` sur le worker qui reçoit le paquet et le transfère vers un pod, éventuellement situé sur le serveur ;
- le **même numéro** est utilisé sur tous les nœuds (`30139` partout) ;
- un NodePort est **unique** dans le cluster : deux Services ne peuvent pas prendre `30139` ;
- on peut le laisser choisir automatiquement, ou l'imposer avec `nodePort:` dans le YAML ;
- c'est l'entrée **depuis l'extérieur** la plus simple : pas besoin de `port-forward`.

```yaml
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - port: 80           # port du Service
      targetPort: 80     # port du conteneur
      nodePort: 30139    # facultatif : 30000-32767 (sinon automatique)
```

#### 3. `LoadBalancer`

**`LoadBalancer` = `NodePort` + un load balancer devant.**

Dans un cloud, Kubernetes demande une IP publique au fournisseur. Dans **K3s**, il n'y a pas de cloud : c'est **ServiceLB (Klipper)** qui fait le travail. Il crée un pod `svclb-...` sur chaque nœud ; ce pod écoute sur les IP des nœuds et relaie vers le Service. L'IP externe du Service est donc l'IP des nœuds.

C'est pour cela que tu vois des pods `svclb-traefik-...` dans `kube-system` : **Traefik est exposé par un Service de type `LoadBalancer`**. On y revient en 4.7.12.

```yaml
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
```

#### 4. `ExternalName`

Cas particulier : ni routage ni pods, juste un **alias DNS** vers un nom externe.

```yaml
spec:
  type: ExternalName
  externalName: db.exemple.com
```

Un pod qui appelle `mon-alias` est redirigé par le DNS vers `db.exemple.com`. Aucune IP de Service n'est créée.

#### 5. Le Service « headless » (`clusterIP: None`)

Pas d'IP virtuelle : le DNS renvoie **directement les IP des pods**. Utile quand le client doit connaître chaque instance individuellement (bases de données, clusters). Pas nécessaire pour ce projet.

#### Tableau récapitulatif

| Type | Joignable depuis | IP de Service | Port sur les nœuds | Load balancer |
|---|---|---|---|---|
| `ClusterIP` | l'intérieur du cluster | oui (`10.43.x.x`) | non | non |
| `NodePort` | l'extérieur, via `IP_nœud:nodePort` | oui | oui | non |
| `LoadBalancer` | l'extérieur, via une IP externe | oui | oui | oui (ServiceLB dans K3s) |
| `ExternalName` | — (alias DNS) | non | non | non |
| headless | l'intérieur, via le DNS | non (`None`) | non | non |

### 4.7.8 DNS interne

Un Service est joignable par son nom, grâce à CoreDNS :

| Forme | Utilisable depuis | Exemple |
|---|---|---|
| `<service>` | le **même** namespace | `web` |
| `<service>.<namespace>` | n'importe quel namespace | `web.dev` |
| `<service>.<namespace>.svc.cluster.local` | partout (nom complet) | `web.dev.svc.cluster.local` |

Depuis un pod du namespace `default`, `web` ne résout que le Service `web` de `default`. Pour joindre celui de `dev`, il faut `web.dev` ou le nom complet.

### 4.7.9 Tester les trois niveaux

Trois commandes, trois étages différents. Chacune prouve quelque chose de précis.

```bash
# 1) Depuis l'intérieur du cluster : le Service par son nom (DNS + ClusterIP)
kubectl run tmp --image=curlimages/curl --rm -it --restart=Never -- curl -s http://web

# 2) Depuis le nœud serveur : le NodePort sur son IP host-only
curl -s http://192.168.56.110:<nodePort>

# 3) Depuis le nœud worker, qui n'héberge peut-être aucun pod web
curl -s http://192.168.56.111:<nodePort>
```

Attendu : les trois renvoient la page. Si (3) fonctionne alors qu'aucun pod `web` n'est sur le worker, tu as la preuve que le NodePort est ouvert **sur chaque nœud**.

> La méthode complète pour créer le pod client de (1), l'utiliser plusieurs fois et le supprimer est décrite en **§4.8.8**.

Et pour voir la liste des destinations changer en direct :

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web -w   # une IP disparaît / réapparaît
kubectl get pods -o wide -w                                        # les pods et leurs IP
```

### 4.7.10 Deux réglages affichés dans le `describe`

**`Session Affinity: None`** : chaque requête peut tomber sur un pod différent. Avec `ClientIP`, un même client reste collé au même pod pendant un moment.

**`External Traffic Policy`** :

| Valeur | Trafic externe envoyé vers | IP source du client |
|---|---|---|
| `Cluster` (défaut) | **n'importe quel** pod du Service | réécrite (SNAT) : les logs voient l'IP d'un nœud |
| `Local` | **uniquement les pods du nœud** appelé | conservée |

Conséquence de `Local` : si aucun pod n'est sur le nœud appelé, la connexion est refusée. Il faut donc un pod par nœud (DaemonSet) pour que ça fonctionne partout.

### 4.7.11 Commandes utiles

```bash
kubectl get svc                                    # nom, type, ClusterIP, ports
kubectl get svc -o wide                            # + selector
kubectl describe svc web                           # selector, type, endpoints, politiques
kubectl get endpointslices -l kubernetes.io/service-name=web   # pods réellement ciblés
kubectl get pods -o wide                           # IP réelles des pods (10.42.x.x)
kubectl get pods --show-labels                     # labels utilisés par le selector
```

### 4.7.12 Ce qu'il faut retenir pour la p2

Dans la p2, tu ne vas **pas** exposer trois NodePorts. Tu vas :

- créer **trois Services `ClusterIP`** (un par application) ;
- créer **un Ingress** qui lit le nom de domaine (`Host: app1.com`) et choisit le bon Service ;
- laisser **Traefik**, exposé par un Service `LoadBalancer`, être l'unique porte d'entrée.

La différence fondamentale :

| Objet | Niveau | Ce qu'il sait lire |
|---|---|---|
| **Service** | couche 4 (TCP/IP) | seulement `IP:port` — il **ne voit pas** le nom de domaine |
| **Ingress** | couche 7 (HTTP) | le `Host`, le chemin (`/api`), la méthode… |

C'est pour cette raison qu'un Service seul ne peut pas router `app1.com` et `app2.com` vers deux applications différentes : les deux arrivent sur la **même** IP et le **même** port. L'Ingress, lui, lit l'en-tête `Host` avant de choisir. C'est le sujet de la leçon 5.

Dernier lien : `app2` en **3 réplicas** ne change **rien** au Service ni à l'Ingress. Tu mets `replicas: 3` dans le Deployment ; le Service récupère automatiquement **3 endpoints**. C'est tout l'intérêt du découplage.

### 4.7.13 Pièges classiques

| Symptôme | Cause probable |
|---|---|
| `endpoints "web" not found` | le Service `web` n'existe pas (ou pas dans ce namespace) |
| endpoints vides | le `selector` du Service ne correspond à aucun label de pod |
| `Connection refused` sur le Service | `targetPort` faux (le conteneur n'écoute pas sur ce port) |
| joignable en ClusterIP, pas en NodePort | mauvaise IP de nœud, port hors plage, ou pare-feu |
| `curl` OK mais `ping` KO sur le ClusterIP | **normal** : l'IP du Service est virtuelle |
| deux Services avec le même `nodePort` | le second est refusé (port unique dans le cluster) |

---

## 4.8 Namespaces

> Cette section est indispensable pour le TP 10, mais aussi pour la p3 : le sujet impose les namespaces **`argocd`** et **`dev`**. Un namespace mal compris = des objets créés « au mauvais endroit » et des Services injoignables.

### 4.8.1 À quoi sert un namespace

Un **namespace** est un **cloisonnement logique de l'API Kubernetes**. C'est un peu un « dossier » dans lequel on range des objets :

```
cluster
├── namespace default       -> tes objets quand tu ne précises rien
├── namespace dev           -> l'application de la p3
├── namespace argocd        -> Argo CD
├── namespace kube-system   -> les composants du cluster
└── ...
```

Ce qu'un namespace apporte :

1. **des noms locaux** : deux namespaces peuvent contenir chacun un Service `web`, un Deployment `web`, un Secret `db`… sans se marcher dessus ;
2. **une organisation** : séparer les environnements (`dev`, `prod`), les équipes, les applications ;
3. **un support** pour les **quotas** (`ResourceQuota`), les **droits** (`RBAC`) et les **politiques réseau** (`NetworkPolicy`).

Ce qu'un namespace **n'est pas** :

- **ce n'est pas une frontière de sécurité forte** : par défaut, un pod de `default` peut joindre un Service de `dev`. Ce sont `NetworkPolicy` et `RBAC` qui restreignent, pas le namespace ;
- **ce n'est pas une isolation réseau** : tous les pods partagent le même réseau du cluster (`10.42.0.0/16`) ;
- **ce n'est pas un dossier physique** : c'est une étiquette sur les objets dans l'API.

**Attention** : supprimer un namespace supprime **tous les objets qu'il contient** (pods, Services, Deployments, ConfigMaps, Secrets, PVC…). C'est pratique pour nettoyer un labo, dangereux en production.

### 4.8.2 Les namespaces par défaut

```bash
kubectl get namespaces                    # liste les namespaces et leur statut
kubectl describe namespace kube-system    # détails et quotas éventuels
```

| Namespace | Rôle |
|---|---|
| **`default`** | les objets de l'utilisateur quand aucun namespace n'est précisé |
| **`kube-system`** | les composants du cluster : CoreDNS, Traefik, metrics-server, local-path-provisioner, `svclb-...` |
| **`kube-public`** | informations publiques, lisibles par tous (dont la ConfigMap `cluster-info`) |
| **`kube-node-lease`** | objets `Lease` : battements de cœur des nœuds (détection rapide d'un nœud mort) |

Un namespace peut être dans deux états :

| Statut | Signification |
|---|---|
| `Active` | utilisable |
| `Terminating` | en cours de suppression ; on ne peut plus y créer d'objets |

### 4.8.3 Objets « namespaced » et objets « cluster-scoped »

C'est la distinction la plus importante de cette section.

| Type | Objets | Le `-n` a-t-il un effet ? |
|---|---|---|
| **Namespaced** (dans un namespace) | Pod, Service, Deployment, ReplicaSet, StatefulSet, DaemonSet, Job, ConfigMap, Secret, PVC, Ingress, ServiceAccount, Role, RoleBinding | **oui** |
| **Cluster-scoped** (global au cluster) | Node, Namespace, PersistentVolume, StorageClass, ClusterRole, ClusterRoleBinding, IngressClass, CRD | **non, il est ignoré** |

Conséquences concrètes :

- un **Pod appartient à un seul namespace** ; il n'existe pas « dans deux namespaces » ;
- `kubectl get nodes -n dev` affiche **tous** les nœuds : `Node` est cluster-scoped, `-n` ne filtre rien ;
- un **Ingress** est namespaced, et **son backend doit être un Service du même namespace**.

```bash
kubectl api-resources --namespaced=true     # liste les types rangés dans un namespace
kubectl api-resources --namespaced=false    # liste les types globaux au cluster
```

### 4.8.4 Les quatre façons de choisir le namespace

| Méthode | Exemple | Portée |
|---|---|---|
| **option `-n`** | `kubectl get pods -n dev` | la commande seulement |
| **`-A`** | `kubectl get pods -A` | tous les namespaces (lecture) |
| **contexte courant** | `kubectl config set-context --current --namespace=dev` | toutes les commandes suivantes |
| **dans le YAML** | `metadata.namespace: dev` | l'objet décrit |

Vérifier le namespace courant :

```bash
kubectl config view --minify -o jsonpath='{..namespace}'; echo
# vide = default, sinon le nom du namespace courant
```

Créer le namespace et y déployer un manifeste :

```bash
kubectl create namespace dev                 # crée le namespace
kubectl apply -f app.yaml -n dev             # applique dans dev (le namespace doit exister)
kubectl get all -n dev                       # pods, services, deployments... de dev
```

**Règles de priorité et pièges :**

- si le YAML contient `metadata.namespace: dev`, l'objet va dans `dev` **même si ton contexte est `default`** ;
- si le YAML ne contient pas de namespace, c'est le **`-n`** qui s'applique, sinon le **namespace du contexte courant** ;
- si le YAML dit `namespace: dev` et que tu passes `-n default`, **kubectl refuse** avec une erreur du type : *« the namespace from the provided object does not match the namespace »* ;
- appliquer dans un namespace **inexistant** échoue : *« namespaces "dev" not found »*.

### 4.8.5 Créer, décrire, supprimer

```bash
kubectl create namespace dev                 # création impérative
kubectl get namespace dev                    # statut
kubectl describe namespace dev               # labels, annotations, quotas
kubectl delete namespace dev                 # supprime le namespace ET tout son contenu
```

Version déclarative (utile dans un dépôt Git, comme pour la p2/p3) :

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
```

À la suppression, le namespace passe en `Terminating` le temps que ses objets soient nettoyés, puis disparaît. Les objets **cluster-scoped** (par exemple un `PersistentVolume`) ne sont pas supprimés avec lui.

### 4.8.6 Les noms sont locaux au namespace

C'est la conséquence directe du cloisonnement. Ces deux objets coexistent sans conflit :

```yaml
# dans default
metadata:
  name: web
  namespace: default

# dans dev
metadata:
  name: web
  namespace: dev
```

Ils ont **le même nom** mais sont **deux objets différents**, avec **deux ClusterIP différentes**.

```bash
kubectl get svc web -n default        # ClusterIP de default
kubectl get svc web -n dev            # ClusterIP de dev
kubectl get svc -A                    # les deux, côte à côte
```

En revanche, les objets **cluster-scoped** ont des noms **globalement uniques** : deux namespaces ne peuvent pas porter le même nom, deux nœuds non plus.

### 4.8.7 DNS et traversée des namespaces

C'est le cœur du TP 10. CoreDNS enregistre chaque Service sous la forme :

```
<service>.<namespace>.svc.cluster.local
```

Donc le Service `web` de `dev` a pour nom complet **`web.dev.svc.cluster.local`**.

Quand un pod démarre, Kubernetes écrit dans son `/etc/resolv.conf` une liste de **domaines de recherche**. Par exemple, pour un pod du namespace `dev` :

```
search dev.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.43.0.10
options ndots:5
```

Le résolveur essaie ces suffixes **dans l'ordre** quand on lui donne un nom incomplet. D'où les résultats suivants :

| Depuis un pod de… | Nom demandé | Requête réellement tentée | Résultat |
|---|---|---|---|
| `dev` | `web` | `web.dev.svc.cluster.local` | ✅ |
| `default` | `web` | `web.default.svc.cluster.local` | ❌ (aucun `web` dans `default`) |
| `default` | `web.dev` | `web.dev.default.svc.cluster.local` puis **`web.dev.svc.cluster.local`** | ✅ |
| n'importe où | `web.dev.svc.cluster.local.` | nom complet **absolu** (point final) | ✅ |

Pourquoi `web.dev` fonctionne depuis `default` : le deuxième domaine de recherche est **`svc.cluster.local`**, donc `web.dev` devient `web.dev.svc.cluster.local`. C'est pour cela que la forme `<service>.<namespace>` est la plus pratique entre namespaces.

À l'inverse, le **nom court ne traverse jamais** un namespace : depuis `default`, `web` cherche `web.default…`, pas `web.dev…`.

> **Piège : `<service>.<namespace>` peut sortir du cluster.**
> `web.dev` est aussi un **vrai nom de domaine public** (le site de Google). Si le Service `web` n'existe pas dans `dev`, la requête peut partir sur le DNS d'Internet et tu obtiendras le vrai site `web.dev` : un `301` vers HTTPS, **corps vide**, et un code de sortie `0` qui ne prouve rien.
> Pour un test fiable, utilise le **nom complet absolu avec un point final** :
> ```sh
> curl -s http://web.dev.svc.cluster.local.
> ```
> et vérifie que l'IP contactée est bien une IP de Service (`10.43.x.x`) :
> ```sh
> curl -sv http://web.dev.svc.cluster.local. 2>&1 | grep Trying
> ```
> Sur les images Alpine (musl), le point final est aussi le moyen de forcer une requête **absolue** : sans lui, un nom qui contient moins de `ndots` points peut n'être essayé qu'avec les domaines de recherche.

Vérifier concrètement depuis un pod :

```bash
kubectl exec -it <pod> -- cat /etc/resolv.conf                  # voir les search domains
kubectl exec -it <pod> -- curl -s http://web.dev.svc.cluster.local.   # test fiable
kubectl exec -it <pod> -- curl -sv http://web.dev.svc.cluster.local. 2>&1 | grep Trying  # IP 10.43.x.x attendue
```

Et se souvenir que **résoudre ne veut pas dire être autorisé** : par défaut, le trafic entre namespaces est permis. Le namespace organise, il ne protège pas.

### 4.8.8 Comment tester depuis un pod (le pod client)

Les TP demandent de tester un Service « depuis un pod de `default` ». Voici la méthode complète.

**Pourquoi un pod ?** Ni ton poste ni les VM ne sont dans le réseau du cluster. Et surtout, **le nœud n'utilise pas CoreDNS** : si tu tapes `curl http://web` directement sur `mzouhirS`, tu obtiens `Could not resolve host: web`. Ce n'est pas une panne : le nom `web` n'existe que **dans** le DNS du cluster. Pour l'utiliser, il faut exécuter la commande **depuis un pod**, qui reçoit automatiquement le bon `/etc/resolv.conf`.

#### Méthode 1 — un pod client qui reste vivant (recommandée pour plusieurs tests)

**1. Créer le pod client**

```bash
kubectl run client \
  --image=curlimages/curl \
  --restart=Never \
  -n default \
  --command -- sleep 3600
```

| Option | Rôle |
|---|---|
| `client` | nom du pod |
| `--image=curlimages/curl` | image légère qui contient `curl` et `sh` |
| `--restart=Never` | crée un **Pod nu** (pas un Deployment) : il ne revient pas après suppression |
| `-n default` | le place dans `default`, **même si ton contexte courant est `dev`** |
| `--command -- sleep 3600` | garde le conteneur vivant 1 h ; sans ça, il s'arrête dès `curl` terminé |

**2. Attendre qu'il soit prêt**

```bash
kubectl get pod client -n default
# attendu : READY 1/1, STATUS Running
```

Si ce n'est pas le cas :

```bash
kubectl describe pod client -n default   # regarder les Events en bas
```

**3. Entrer dedans**

```bash
kubectl exec -it client -n default -- sh
```

L'invite devient quelque chose comme `/ $` : tu es dans le réseau du cluster, avec le `/etc/resolv.conf` du namespace `default`.

**4. Lancer les tests**

```sh
curl -s http://web
curl -s http://web.dev
curl -s http://web.dev.svc.cluster.local
```

**5. Voir l'IP réellement contactée**

```sh
curl -sv http://web      2>&1 | grep Trying
curl -sv http://web.dev  2>&1 | grep Trying
```

Deux `Trying` différents = deux Services différents, malgré le même nom.

**6. Sortir et supprimer le pod client**

```sh
exit
```

```bash
kubectl delete pod client -n default
```

#### Méthode 2 — un seul test, pod supprimé automatiquement

```bash
kubectl run test-dns \
  --image=curlimages/curl \
  --rm -it --restart=Never \
  -n default \
  -- curl -s http://web.dev
```

`--rm` supprime le pod dès que la commande se termine. Pratique pour un test unique, moins pratique pour enchaîner plusieurs `curl`.

#### Lire les résultats

| Sortie | Signification |
|---|---|
| une page HTML nginx | ✅ le Service répond |
| `curl: (6) Could not resolve host: web` | aucun Service `web` dans le namespace du pod |
| `curl: (6) Could not resolve host: web.dev.svc.cluster.local` | soit le Service n'existe pas, soit il manque le **point final** (résolveur musl) → teste `web.dev.svc.cluster.local.` |
| code `0` mais **corps vide** et IP publique dans `Trying` | tu as joint **Internet**, pas le cluster (ex. le vrai site `web.dev`) |
| `curl: (7) Failed to connect` | le nom résout, mais aucun pod prêt derrière le Service (sélecteur faux, endpoints vides) |
| `curl: (28) Timeout` | réseau/pare-feu, ou aucune réponse |

#### Les deux pièges

- **`-n` oublié** : `kubectl run` crée le pod dans le **namespace du contexte courant**. Si tu as fait `set-context --namespace=dev`, ton « pod de default » finit dans `dev` et le test ne prouve rien. Toujours mettre `-n default` (ou `-n dev`) explicitement.
- **commande trop courte** : `kubectl run client --image=curlimages/curl -- curl http://web` sans `sleep` : le pod exécute `curl` puis s'arrête, et tu ne peux plus faire `exec` dedans.

> À retenir : pour tester un nom DNS ou un ClusterIP, il faut être **dans** le cluster. Le nœud, lui, ne connaît pas les noms des Services.

### 4.8.9 Quotas et droits : ce que le namespace rend possible

Le namespace est le « grain » de plusieurs mécanismes :

| Mécanisme | Effet | Portée |
|---|---|---|
| **`ResourceQuota`** | limite le total de CPU/RAM/pods du namespace | le namespace |
| **`LimitRange`** | valeurs par défaut/max pour chaque conteneur | le namespace |
| **`Role` / `RoleBinding`** | droits d'un utilisateur **dans un namespace** | le namespace |
| **`NetworkPolicy`** | autorise/bloque le trafic entre pods | un namespace (avec sélecteurs) |

Exemple de quota (à ne pas appliquer maintenant, juste pour comprendre) :

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dev-quota
  namespace: dev
spec:
  hard:
    pods: "10"
    requests.cpu: "2"
    requests.memory: 2Gi
```

Si le quota est dépassé, la création du pod est refusée avec *« exceeded quota »*.

### 4.8.10 Le lien avec le projet

**Partie 2** : tu peux tout mettre dans `default`, mais retiens la règle : **un Ingress et les Services qu'il cible doivent être dans le même namespace**. Un Ingress de `default` ne peut pas pointer vers un Service de `dev`.

**Partie 3** : le sujet impose deux namespaces :

| Namespace | Contenu |
|---|---|
| **`argocd`** | Argo CD (l'outil GitOps) |
| **`dev`** | l'application déployée automatiquement depuis ton dépôt GitHub |

Argo CD vit dans `argocd` et déploie dans `dev` : c'est un cas typique de communication **entre** namespaces. Traefik, lui, surveille les Ingress de **tous** les namespaces, donc un Ingress créé dans `dev` fonctionne sans configuration supplémentaire.

### 4.8.11 Pièges classiques

| Symptôme | Cause probable |
|---|---|
| `No resources found` alors que « tout est déployé » | les objets sont dans un autre namespace : `kubectl get all -A` |
| un `apply` crée l'objet au mauvais endroit | ton contexte courant a changé (`set-context --namespace`) ou le YAML n'a pas de `metadata.namespace` |
| erreur « namespace from the provided object does not match » | `metadata.namespace` et `-n` se contredisent |
| `namespaces "dev" not found` | le namespace n'existe pas encore : `kubectl create namespace dev` |
| `web` injoignable depuis un autre namespace | nom court : utilise `web.dev` ou le nom complet |
| Ingress en `404`/`503` | son backend est dans un autre namespace, ou le Service n'existe pas dans le sien |
| suppression d'un namespace très lente | des objets bloquent le nettoyage (finalizers) ; `kubectl get ns` le montre en `Terminating` |

---

## 4.9 ConfigMap et Secret

> Ces deux objets servent à **sortir la configuration de l'image**. Le ConfigMap pour le non-sensible, le Secret pour le sensible. Les TP 11 et 12 vont te faire manipuler les **deux modes d'injection** (variables d'environnement et fichiers), qui n'ont **pas** le même comportement quand la configuration change.

### 4.9.1 Pourquoi séparer la configuration de l'image

Une même image applicative doit pouvoir tourner en `dev`, en `staging` et en `prod` **sans être reconstruite**. Ce qui change d'un environnement à l'autre (URL de base de données, mot de passe, mode debug, page d'accueil) ne doit pas être « cuit » dans l'image Docker.

| Ce qui est dans l'image | Ce qui est dans un ConfigMap / Secret |
|---|---|
| le code, les binaires, les bibliothèques | la configuration qui varie |
| **immuable** (un tag = un contenu) | **modifiable** sans rebuild |
| versionné avec l'application | versionné séparément (ou injecté) |

Les deux objets sont des **paires clé/valeur**, rangées dans un **namespace** (comme les Pods et les Services). La différence :

| | ConfigMap | Secret |
|---|---|---|
| Données | non sensibles | sensibles |
| Encodage | texte | **base64** |
| Affiché par `kubectl get -o yaml` | en clair | en base64 (décodable) |
| Chiffrement au repos | non | **pas par défaut** (option selon le cluster) |
| Usage typique | `index.html`, `APP_MODE`, URL | mot de passe, token, certificat TLS |

### 4.9.2 ConfigMap : les façons de le créer

**1. À partir de littéraux (ligne de commande)**

```bash
kubectl create configmap web-config \
  --from-literal=APP_MODE=dev \
  --from-literal=APP_PORT=8080
```

Deux clés : `APP_MODE=dev` et `APP_PORT=8080`.

**2. À partir d'un fichier**

```bash
kubectl create configmap web-html --from-file=index.html
```

La **clé** devient le **nom du fichier** (`index.html`) et la **valeur** son contenu. On peut renommer la clé :

```bash
kubectl create configmap web-html --from-file=page=index.html   # clé "page"
```

**3. À partir d'un fichier d'environnement**

```bash
# app.env
APP_MODE=dev
APP_PORT=8080
```

```bash
kubectl create configmap web-config --from-env-file=app.env
```

Chaque ligne `CLÉ=valeur` devient une clé du ConfigMap.

**4. En YAML déclaratif (recommandé, versionnable dans Git)**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-html
  namespace: default
data:
  index.html: |
    <!doctype html>
    <html>
      <body><h1>Bonjour depuis le ConfigMap</h1></body>
    </html>
  APP_MODE: dev
```

- `data` : valeurs **UTF-8** (texte) ;
- `binaryData` : valeurs **binaires**, encodées en base64 (image, archive…) ;

```yaml
binaryData:
  logo.png: iVBORw0KGgoAAAANSUhEUg...
```

Règles à connaître :

- le nom suit les règles DNS (minuscules, chiffres, `-`) ;
- les clés acceptent lettres, chiffres, `-`, `_`, `.` ;
- toutes les valeurs sont des **chaînes** : `APP_PORT: "8080"` (pas `8080` nu) ;
- taille maximale ~**1 MiB** par objet (limite du stockage d'état) ;
- `immutable: true` empêche toute modification : pour changer, il faut supprimer et recréer (utile pour éviter les dérives).

Inspecter :

```bash
kubectl get configmap                       # liste
kubectl describe configmap web-html         # clés et tailles
kubectl get configmap web-html -o yaml      # contenu complet
kubectl edit configmap web-html             # modifier à la volée
```

### 4.9.3 Consommer un ConfigMap en variables d'environnement

Deux mécanismes, à ne pas confondre.

**a) Une clé précise : `configMapKeyRef`**

```yaml
env:
  - name: APP_MODE
    valueFrom:
      configMapKeyRef:
        name: web-config      # nom du ConfigMap
        key: APP_MODE         # clé à lire
        optional: false       # true = pas d'erreur si absent
```

**b) Toutes les clés d'un coup : `envFrom`**

```yaml
envFrom:
  - configMapRef:
      name: web-config
    prefix: WEB_              # facultatif : APP_MODE devient WEB_APP_MODE
```

**Le point crucial : les variables sont figées au démarrage du conteneur.** Si tu modifies le ConfigMap ensuite, le conteneur **ne voit rien changer**. Il faut recréer les pods :

```bash
kubectl rollout restart deployment/web      # redémarre les pods proprement
# ou
kubectl delete pod <pod>                    # le ReplicaSet en recrée un
```

Si une clé demandée n'existe pas et que `optional` n'est pas à `true`, le pod reste bloqué en **`CreateContainerConfigError`**. Diagnostic :

```bash
kubectl get pods
kubectl describe pod <pod>     # Events : "configmap ... not found" ou "key ... not found"
```

### 4.9.4 Consommer un ConfigMap en fichiers (volume)

C'est le mode utilisé pour fournir un fichier de configuration ou une page HTML.

```yaml
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html   # répertoire de destination
          readOnly: true
  volumes:
    - name: html
      configMap:
        name: web-html
        defaultMode: 0444                    # permissions des fichiers (lecture seule)
        items:                               # facultatif : choisir les clés projetées
          - key: index.html
            path: index.html
```

Règles de fonctionnement :

- **chaque clé devient un fichier** dont le nom est la clé ;
- sans `items`, **toutes** les clés sont projetées ; avec `items`, seulement celles listées ;
- `defaultMode` règle les permissions (par défaut `0644`) ;
- le volume est **read-only** par conception ;
- `optional: true` évite le blocage si le ConfigMap n'existe pas.

**Mise à jour à chaud** : kubelet rafraîchit le volume périodiquement (généralement **moins de 2 minutes**). Le fichier change **sans redémarrer le pod**. En coulisses, Kubernetes remplace un lien symbolique (`..data`) de façon atomique : les lecteurs voient soit l'ancien, soit le nouveau, jamais un fichier à moitié écrit.

**Exception majeure : `subPath`.** Si tu montes **un seul fichier** avec `subPath`, la mise à jour **ne se propage pas** :

```yaml
volumeMounts:
  - name: html
    mountPath: /usr/share/nginx/html/index.html
    subPath: index.html      # <-- le fichier ne sera JAMAIS mis à jour
```

C'est un piège classique : `subPath` crée un lien vers le fichier au démarrage, sans le mécanisme de rafraîchissement.

Autre nuance : même si le fichier change sur le disque, **l'application doit le relire**. Nginx relit ses fichiers statiques à chaque requête, donc ça fonctionne. Une application qui charge sa config une fois en mémoire au démarrage ne verra rien.

### 4.9.5 Cas concret : `index.html` fourni par un ConfigMap

Manifeste complet (ConfigMap + Deployment) :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: web-html
data:
  index.html: |
    <!doctype html>
    <html>
      <body><h1>Version 1 - depuis le ConfigMap</h1></body>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-cm
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-cm
  template:
    metadata:
      labels:
        app: web-cm
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
              readOnly: true
      volumes:
        - name: html
          configMap:
            name: web-html
            items:
              - key: index.html
                path: index.html
```

Tester :

```bash
kubectl apply -f web-cm.yaml
kubectl get configmap,pods

# le fichier est bien présent dans le conteneur
kubectl exec deploy/web-cm -- cat /usr/share/nginx/html/index.html

# nginx sert bien ce contenu
kubectl exec deploy/web-cm -- curl -s localhost
```

Modifier et observer :

```bash
kubectl edit configmap web-html      # change "Version 1" en "Version 2"
# attends 1 à 2 minutes (rafraîchissement kubelet)
kubectl exec deploy/web-cm -- cat /usr/share/nginx/html/index.html
kubectl exec deploy/web-cm -- curl -s localhost
```

Puis teste la variante `subPath` : le fichier **ne changera pas**. C'est exactement la comparaison demandée dans le TP 11.

### 4.9.6 Limites et bonnes pratiques

- **1 MiB maximum** : un ConfigMap n'est pas un système de fichiers ; pour de gros fichiers, utilise un volume persistant ou une image.
- **namespaced** : le ConfigMap doit être dans le **même namespace** que le pod qui le consomme.
- **pas de secrets** : un ConfigMap est lisible par quiconque peut lire le namespace. Pour un mot de passe, utilise un Secret.
- **versionné dans Git** : c'est tout l'intérêt du déclaratif. Un ConfigMap se commit sans problème (contrairement à un Secret).
- **modifier un ConfigMap ne redémarre pas les pods** : en mode `env`, il faut un `rollout restart` ; en mode volume, le fichier se met à jour mais l'application doit le relire.
- **immutable** : pour une configuration qui ne doit jamais dériver, `immutable: true` évite les modifications accidentelles.

### 4.9.7 Secret : le même modèle, pour le sensible

Un Secret est un ConfigMap « spécial » :

- mêmes mécanismes de consommation (`env`, `envFrom`, volume) ;
- mêmes règles de mise à jour (env figé, volume rafraîchi, `subPath` figé) ;
- mêmes limites de taille ;
- **mais** les valeurs sont encodées en **base64** et l'objet est traité à part par Kubernetes (RBAC, audit, chiffrement au repos optionnel).

#### Les types de Secret

| Type | Usage |
|---|---|
| `Opaque` (défaut) | clé/valeur générique (mot de passe, token) |
| `kubernetes.io/dockerconfigjson` | identifiants d'un registry Docker privé (`imagePullSecrets`) |
| `kubernetes.io/tls` | certificat + clé privée TLS |
| `kubernetes.io/basic-auth` | utilisateur / mot de passe |
| `kubernetes.io/ssh-auth` | clé SSH |
| `kubernetes.io/service-account-token` | token d'un ServiceAccount (géré par le cluster) |

#### Créer un Secret

```bash
# à partir de littéraux
kubectl create secret generic db --from-literal=password=s3cr3t

# à partir d'un fichier (la clé = nom du fichier)
kubectl create secret generic db --from-file=password.txt

# identifiants Docker (utile en p3 si image privée)
kubectl create secret docker-registry regcred \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<user> \
  --docker-password=<token>

# certificat TLS
kubectl create secret tls mon-tls --cert=tls.crt --key=tls.key
```

En YAML :

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db
type: Opaque
stringData:                 # en clair : Kubernetes encode en base64 tout seul
  password: s3cr3t
# équivalent en base64 :
# data:
#   password: czNjcjN0
```

`stringData` est une commodité en **écriture** : après application, `kubectl get -o yaml` montre toujours `data` en base64.

#### Lire et décoder

```bash
kubectl get secret db                       # NAME / TYPE / DATA / AGE (valeurs masquées)
kubectl describe secret db                  # liste les clés, pas les valeurs
kubectl get secret db -o yaml               # data en base64
kubectl get secret db -o jsonpath='{.data.password}' | base64 -d; echo   # décode
```

#### Consommer un Secret

```yaml
# une clé précise
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db
        key: password

# toutes les clés
envFrom:
  - secretRef:
      name: db
```

```yaml
# en volume
volumes:
  - name: db-secret
    secret:
      secretName: db
      defaultMode: 0400
```

Chaque clé devient un fichier dans le volume, exactement comme pour un ConfigMap.

#### Base64 n'est **pas** du chiffrement

C'est le point à retenir absolument :

- base64 est un **encodage** réversible par n'importe qui : `echo czNjcjN0 | base64 -d` donne `s3cr3t` ;
- Kubernetes **ne chiffre pas** les Secrets au repos par défaut ; K3s propose l'option `--secrets-encryption` pour l'activer ;
- toute personne ayant le droit de lire le Secret (RBAC) ou d'entrer dans le pod (`kubectl exec`) peut lire la valeur ;
- un Secret stocké dans Git est donc **en clair** pour un attaquant, même s'il « ressemble » à du charabia.

Bonnes pratiques :

- **ne jamais commiter** un Secret dans Git ;
- utiliser **Sealed Secrets**, **SOPS**, **External Secrets** ou **Vault** pour versionner des secrets chiffrés ;
- limiter les droits RBAC sur `get`/`list` des Secrets ;
- préférer un **volume** à une variable d'environnement quand c'est possible : les variables fuient plus facilement (logs, `ps`, dumps de crash) ;
- `immutable: true` fonctionne aussi sur les Secrets.

### 4.9.8 ConfigMap vs Secret : récapitulatif

| Critère | ConfigMap | Secret |
|---|---|---|
| Sensibilité | non | oui |
| Encodage | texte | base64 |
| `env` / `envFrom` | oui | oui |
| Volume | oui | oui |
| Mise à jour à chaud (volume répertoire) | oui (~2 min) | oui (~2 min) |
| Mise à jour des variables d'env | non (restart) | non (restart) |
| `subPath` mis à jour | non | non |
| Commit Git | oui | **non** (sauf chiffrement) |
| Chiffré au repos | non | pas par défaut |

### 4.9.9 Pièges classiques

| Symptôme | Cause probable |
|---|---|
| pod en `CreateContainerConfigError` | ConfigMap/Secret absent, mauvaise clé, ou mauvais namespace |
| les variables ne changent pas après modification | comportement normal : il faut recréer les pods |
| le fichier monté ne change pas | montage avec `subPath` |
| le fichier change sur le disque mais l'app sert l'ancien contenu | l'application a chargé la config en mémoire ; il faut la recharger |
| `kubectl apply` refuse le Secret | `data` attend du base64 : utilise `stringData` pour du texte clair |
| Secret introuvable dans Git | normal : on ne commit pas de Secret |
| « too large » | dépasse la limite ~1 MiB |

### 4.9.10 Liens avec le projet

- **p2** : un ConfigMap peut personnaliser la page servie par une des applications (utile pour différencier `app1` / `app2` / `app3` à l'écran).
- **p3** : les ConfigMaps font partie des manifests versionnés dans le dépôt GitHub déployé par Argo CD. **Les Secrets, eux, ne doivent pas y être** : c'est un des points de sécurité à savoir expliquer en soutenance.

---

## 4.10 Ingress (aperçu — détail en leçon 5)

Un **Service** expose du trafic **L4** (TCP/IP) : il ne sait pasrouter selon un nom de domaine. Pour du **HTTP L7**, on utilise un **Ingress** :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
spec:
  ingressClassName: traefik
  rules:
    - host: app1.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app1
                port:
                  number: 80
```

Un Ingress **ne fait rien seul** : il faut un **Ingress Controller** (Traefik dans K3s) qui lit les objets Ingress et configure le routage. C'est exactement ce qui permettra, en p2, de router `app1.com` / `app2.com` / « le reste » vers les bonnes applications.

On verra en leçon 5 : `ingressClassName`, `Host`, chemins, **route par défaut**, et le test avec `curl -H "Host: ..."`.

---

## 4.11 Cycle de vie d'un déploiement

```bash
kubectl apply -f app.yaml          # créer / mettre à jour (idempotent)
kubectl get all                    # vue d'ensemble
kubectl scale deployment/web --replicas=5
kubectl set image deployment/web web=nginx:1.27
kubectl rollout status deployment/web
kubectl rollout history deployment/web
kubectl rollout undo deployment/web
kubectl delete -f app.yaml
kubectl delete all -l app=web      # supprimer par label
```

`kubectl apply` :
- si l'objet n'existe pas → création ;
- s'il existe → mise à jour vers l'état décrit ;
- s'il a été modifié à la main → correction (dérive).

---

## 4.12 Débogage

**Un pod ne démarre pas**

```bash
kubectl get pods
kubectl describe pod <nom>        # regarder Events en bas
kubectl logs <nom>
kubectl logs <nom> -c <conteneur> # pod multi-conteneurs
```

| État | Signification | Piste |
|---|---|---|
| `Pending` | pas encore planifié | ressources insuffisantes, taints, aucun nœud `Ready` |
| `ContainerCreating` | image en cours de téléchargement | attendre, vérifier le réseau |
| `ImagePullBackOff` / `ErrImagePull` | image introuvable | nom/tag de l'image, registry, accès |
| `CrashLoopBackOff` | le conteneur redémarre en boucle | `kubectl logs`, commande de démarrage |
| `Running` mais pas de réponse | problème applicatif ou réseau | logs, Service/endpoints |

**Un Service ne répond pas**

```bash
kubectl get endpointslices -l kubernetes.io/service-name=<service>   # vide = sélecteur faux
kubectl describe svc <service>
kubectl get pods --show-labels
```

**Erreur de sélecteur** : le `spec.selector` du Service/Deployment ne correspond pas aux `labels` des pods. C'est la panne la plus fréquente.

---

## 4.13 Lien avec la p2

La p2 demande :

- **trois applications** web dans un cluster K3s ;
- **app2 avec 3 réplicas** ;
- accès selon le **nom d'hôte** (`app1.com`, `app2.com`, sinon `app3`) ;
- donc : trois **Deployments**, trois **Services**, et un **Ingress** avec des règles `Host` + une route par défaut.

Les leçons 4 (objets) et 5 (Ingress/Traefik) couvrent exactement cela. Dans les TP de cette leçon, tu prépareras les trois Deployments et les trois Services ; l'Ingress sera ajouté en leçon 5.

---

## 4.14 TP — À toi de jouer

> Aucune solution n'est donnée. Travaille dans le namespace `default` sauf indication contraire, et note tes essais dans `cours/journal-lecon4.txt`.

### TP 1 — Premier Pod déclaratif
1. Écris un manifeste de Pod `nginx` (image `nginx:1.25`, port 80) et applique-le.
2. Vérifie qu'il est `Running` et sur quel nœud.
3. Affiche son `describe`, ses logs, puis entre dedans et teste `curl localhost`.
4. Supprime-le et vérifie qu'il a disparu.

### TP 2 — Pod multi-conteneurs
1. Crée un Pod avec deux conteneurs : `nginx` et `busybox` (ce dernier en boucle d'attente).
2. Vérifie que les deux conteneurs tournent (`READY 2/2`).
3. Depuis `busybox`, teste `wget`/`curl` sur `localhost:80`.
4. Explique pourquoi cela fonctionne sans réseau supplémentaire.
5. Supprime le Pod.

### TP 3 — Labels et sélecteurs
1. Crée trois pods avec des labels différents (`app=web`, `tier=frontend` sur certains).
2. Liste-les avec leurs labels.
3. Filtre par label (`-l`), puis par sélecteur ensembliste (`in`).
4. Ajoute un label à un pod existant et vérifie le résultat.

### TP 4 — ReplicaSet
1. Crée un ReplicaSet avec `replicas: 3`.
2. Vérifie le nombre de pods.
3. Supprime un pod : que se passe-t-il ?
4. Passe à 5 réplicas, puis à 2.
5. Supprime le ReplicaSet et explique ce qui arrive aux pods.

### TP 5 — Deployment
1. Crée un Deployment `web` avec 2 réplicas.
2. Vérifie les objets créés (`deploy`, `rs`, `pods`) et leurs labels.
3. Passe à 5 réplicas.
4. Change l'image vers une autre version (`nginx:1.27`), suis le rollout, puis affiche l'historique.
5. Fais un rollback et vérifie l'image utilisée.
6. Supprime un pod du Deployment : est-il recréé ?

### TP 6 — Stratégie de mise à jour
> Garde le Deployment `web` du TP5. Utilise la méthode d'observation du **§4.6.6** (plusieurs terminaux + sonde `curl`).
> À chaque changement d'image, utilise un tag **réellement différent** (`1.25` → `1.27` → `1.26`), sinon aucun rollout ne se déclenche.

1. Règle `replicas` à **3**, puis relève l'état de départ : `deploy`, `rs`, `pods`, hash du ReplicaSet courant, `StrategyType` et `RollingUpdateStrategy` lus dans `kubectl describe`.
2. Mets en place la sonde `curl` du §4.6.6 (Service temporaire + pod `probe`) et vérifie qu'au repos tu obtiens bien des `200`.
3. Passe la stratégie à **`Recreate` sans changer l'image** : que se passe-t-il pour les pods ? Explique pourquoi.
4. Change maintenant l'image et observe **en parallèle** `kubectl get pods -w`, `kubectl get rs -w` et `kubectl rollout status`.
5. Pendant l'opération, note précisément : nombre de pods à chaque instant, états observés (`Terminating`, `Pending`, `ContainerCreating`, `Running`), codes HTTP de la sonde, et **durée de la coupure**.
6. Remets **`RollingUpdate`** avec `maxSurge: 1` et `maxUnavailable: 0`, puis change encore l'image. Compare : nombre maximum de pods, ordre des événements, coupure ou non.
7. Refais un changement d'image avec `maxSurge: 0` et `maxUnavailable: 1`. Quelle différence observes-tu sur le nombre de pods et sur les endpoints ?
8. Dans ton journal : les valeurs par défaut lues dans `describe`, l'effet exact des deux paramètres, et **dans quel cas tu choisirais `Recreate`**.

### TP 7 — Service ClusterIP
> Écris le Service en **YAML** (pas `kubectl expose`) : c'est le format qu'utilisera la p2.

1. Déploie une application `web` avec **3 réplicas** (`nginx`).
2. Écris un Service `web` de type `ClusterIP`, `port: 80`, `targetPort: 80`, avec le bon `selector`. Applique-le.
3. Compare trois vues : `kubectl get svc`, `kubectl describe svc web` et `kubectl get endpointslices -l kubernetes.io/service-name=web`. Combien d'endpoints ? À quels pods correspondent-ils (`kubectl get pods -o wide`) ?
4. Depuis un pod temporaire `curlimages/curl`, teste le Service par son nom court (`http://web`) puis par son nom complet (`http://web.default.svc.cluster.local`). Même résultat ?
5. Supprime un pod de l'application et observe `kubectl get endpointslices -l kubernetes.io/service-name=web -w` : que disparaît, que réapparaît ? Le Service répond-il toujours pendant l'opération ?
6. Teste `ping <ClusterIP>` depuis un pod : que se passe-t-il, et pourquoi ?
7. Dans ton journal : pourquoi le client n'a-t-il pas besoin de connaître l'IP des pods, et pourquoi le ClusterIP ne change-t-il jamais ?

### TP 8 — Casser le sélecteur
1. Modifie le `selector` du Service pour qu'il ne corresponde plus aux labels des pods.
2. Vérifie les **endpointslices** et teste le Service : que se passe-t-il ?
3. Répare le sélecteur et vérifie que tout revient.
4. Note la commande de diagnostic qui t'a permis de voir le problème.

### TP 9 — NodePort et port-forward
1. Change le Service en `type: NodePort` (garde `port: 80` / `targetPort: 80`).
2. Repère le `NodePort` attribué (`kubectl get svc`) et teste depuis le **serveur** : `curl http://192.168.56.110:<nodePort>`.
3. Teste depuis le **worker** : `curl http://192.168.56.111:<nodePort>`. Fonctionne-t-il alors qu'aucun pod n'y tourne ? Explique.
4. Depuis **ton poste (hôte)**, teste `curl http://192.168.56.110:<nodePort>` (sans `vagrant ssh`).
5. Impose un `nodePort` fixe (par exemple `30080`), applique, vérifie. Puis tente d'en imposer un **déjà pris** : que dit l'API ?
6. Utilise `kubectl port-forward svc/web 8080:80` depuis le serveur et compare : qui écoute, sur quelle interface, accessible depuis où ?
7. Tableau comparatif dans ton journal : ClusterIP / NodePort / port-forward (depuis où ? stable ? load balancé ?).

### TP 10 — Namespaces et DNS
> Garde le Service `web` du TP 7 dans `default` : il sert de comparaison.

1. Crée le namespace `dev`, vérifie son statut (`get ns`) et décris-le.
2. Écris un manifeste **multi-documents** (Deployment `web` à 2 réplicas + Service `web` ClusterIP) avec `metadata.namespace: dev`. Applique-le.
3. Où apparaissent les objets ? Compare `kubectl get all`, `kubectl get all -n dev` et `kubectl get all -A`. Explique chaque résultat.
4. Compare les deux Services `web` : `kubectl get svc web -n default` et `kubectl get svc web -n dev`. Même nom ? Même ClusterIP ? Pourquoi est-ce possible ?
5. Depuis un pod de `default` (méthode **§4.8.8**), teste `http://web`, `http://web.dev` et **`http://web.dev.svc.cluster.local.`** (note le **point final**). Pour chacun, relève le code HTTP, l'IP réellement contactée (`curl -sv ... 2>&1 | grep Trying`) et le corps de la réponse. **Vérifie que l'IP est en `10.43.x.x`** : une IP publique signifie que tu as quitté le cluster (piège du vrai site `web.dev`). Que désignent-ils ?
6. Lance un pod temporaire **dans `dev`** (§4.8.8, avec `-n dev`) et teste `http://web`. Que désigne-t-il cette fois ? Compare avec le résultat de la question 5.
7. Affiche `/etc/resolv.conf` du pod client et explique, avec la liste `search`, pourquoi `web` et `web.dev` ne désignent pas la même chose.
8. Teste le conflit : applique le manifeste de `dev` en ajoutant `-n default`. Note l'erreur exacte. Puis refais l'application sans `-n`.
9. Supprime le namespace `dev`. Que deviennent le Deployment, le Service et les pods ? Vérifie avec `kubectl get all -n dev` et `kubectl get ns`.
10. En trois phrases : à quoi sert un namespace, pourquoi ce n'est pas une frontière de sécurité, et comment joindre un Service d'un autre namespace.

### TP 11 — ConfigMap
> Objectif : maîtriser les **deux modes d'injection** et voir lequel se met à jour à chaud. Tu peux tout faire dans `default`.

1. Crée localement un fichier `index.html` avec un contenu reconnaissable. Crée un ConfigMap `web-html` **à partir de ce fichier** (mode impératif). Inspecte `kubectl get configmap web-html -o yaml` : quelle est la clé ? le contenu ?
2. Supprime-le, puis réécris le même ConfigMap en **YAML déclaratif** (`data: index.html: |`). Applique. Compare `kubectl describe` et `get -o yaml`.
3. Déploie nginx avec un volume ConfigMap monté **en répertoire** sur `/usr/share/nginx/html` (sans `subPath`). Vérifie le fichier dans le pod (`cat`) puis `curl -s localhost`.
4. Modifie le contenu du ConfigMap. Chronomètre : combien de temps avant que `cat` montre le nouveau contenu ? `curl` renvoie-t-il la nouvelle page ?
5. Supprime le pod. Le pod recréé a-t-il le nouveau contenu ? Explique.
6. Crée un second ConfigMap avec `APP_MODE=dev` et `APP_PORT=8080`, injecte-le avec `envFrom` dans un pod `busybox` (`sleep 3600`). Vérifie avec `printenv`.
7. Modifie ce ConfigMap : les variables changent-elles dans le pod ? Recrée le pod (`kubectl delete pod`) et vérifie à nouveau.
8. Monte maintenant `index.html` en **fichier unique** avec `subPath`. Modifie le ConfigMap et observe. Explique la différence avec le montage en répertoire.
9. Tableau dans ton journal : volume répertoire / volume `subPath` / variables d'environnement → « mis à jour à chaud ? », « après recréation du pod ? ».

### TP 12 — Secret
1. Crée un Secret `db` avec `--from-literal=password=s3cr3t`. Puis crée un second Secret `db-yaml` en YAML avec `stringData`. Compare le résultat de `kubectl get secret ... -o yaml`.
2. Décode la valeur : `kubectl get secret db -o jsonpath='{.data.password}' | base64 -d; echo`. Explique pourquoi base64 n'est **pas** du chiffrement.
3. Injecte `password` en variable `DB_PASSWORD` via `secretKeyRef` dans un pod `busybox`. Vérifie avec `printenv DB_PASSWORD`.
4. Monte le Secret en volume et lis le fichier dans le pod.
5. Modifie le Secret : la variable d'environnement change-t-elle ? le fichier monté change-t-il ? (mêmes règles que le ConfigMap)
6. Compare `kubectl describe secret db` et `kubectl get secret db -o yaml` : que voit-on dans chaque cas ?
7. Explique les conséquences : pour Git, pour le RBAC, et pourquoi un volume est souvent préféré à une variable d'environnement.

### TP 13 — Débogage guidé
Provoque, observe et répare (une panne à la fois) :
1. `ImagePullBackOff` (image inexistante).
2. `CrashLoopBackOff` (commande qui échoue au démarrage).
3. `Pending` (demande de ressources impossibles).
Pour chaque cas : symptôme, commande de diagnostic, cause, correctif.

### TP 14 — Manifeste multi-documents
1. Écris un seul fichier YAML contenant un Deployment **et** un Service (séparés par `---`).
2. Applique-le d'un coup.
3. Vérifie que les deux objets existent.
4. Supprime-le d'un coup avec `kubectl delete -f`.

### TP 15 — Préparer la p2
1. Crée **trois** Deployments (`app1`, `app2`, `app3`) avec des images web simples.
2. Donne à `app2` **3 réplicas**, les autres 1.
3. Crée un Service `ClusterIP` pour chacun.
4. Vérifie les endpoints et teste chaque Service depuis un pod temporaire.
5. Ne crée pas encore d'Ingress : ce sera la leçon 5.

---

## 4.15 Questions de la leçon 4

### Partie A — Concepts

**A1.** Quelle est la différence entre impératif et déclaratif ? Pourquoi `kubectl apply` est-il idempotent ?

**Ta réponse :**

**Impératif** : on donne des ordres un par un (`kubectl run`, `kubectl create deployment`, `kubectl scale`). Le cluster exécute, mais rien ne conserve la description de l'état voulu : si un pod meurt, l'ordre n'existe plus.

**Déclaratif** : on décrit l'état final dans un fichier YAML versionnable, et le cluster converge en boucle vers cet état (réconciliation).

`kubectl apply` est idempotent parce que le serveur **calcule un diff** entre le manifeste envoyé et l'objet existant, puis n'applique que la différence. Appliqué 10 fois, on obtient le même objet final ; s'il n'y a rien à changer, la commande répond `unchanged`. À l'inverse, `kubectl create` échoue au deuxième passage avec `AlreadyExists`.

**A2.** Quelles sont les quatre clés de premier niveau d'un manifeste, et que contient chacune ?

**Ta réponse :**

| Clé | Contenu |
|---|---|
| `apiVersion` | le groupe et la version d'API qui sert l'objet (`v1`, `apps/v1`, `networking.k8s.io/v1`) |
| `kind` | le type d'objet (`Pod`, `Deployment`, `Service`, `Ingress`) |
| `metadata` | l'identité : `name`, `namespace`, `labels`, `annotations` |
| `spec` | l'état **désiré**, propre à chaque type d'objet |

La cinquième clé, `status`, existe dans l'objet mais n'est jamais écrite par toi : c'est le cluster qui la remplit.

**A3.** Quelle est la différence entre `spec` et `status` ?

**Ta réponse :**

`spec` est **ce que tu veux** : il est écrit par toi (ou ton `apply`) et c'est la seule partie que tu as le droit de modifier.
`status` est **ce que le cluster constate** : nombre de réplicas réellement prêtes, adresse IP attribuée, conditions (`Ready`, `Available`), événements.

Les contrôleurs comparent en boucle les deux et agissent sur l'écart : c'est la réconciliation. Un `status` qui ne correspond pas au `spec` est le premier indice de diagnostic (ex. `replicas: 3` dans le `spec` mais `readyReplicas: 1` dans le `status`).

**A4.** Quelle est la différence entre un label et une annotation ?

**Ta réponse :**

| | Label | Annotation |
|---|---|---|
| Rôle | **identifier et sélectionner** des objets | porter de l'information pour des outils |
| Utilisé par | `selector` des Services/Deployments/RS | personne automatiquement |
| Format | clé/valeur court (max 63 caractères), indexé | clé/valeur libre, jusqu'à ~256 Ko |
| Exemple | `app: web`, `tier: frontend` | `kubectl.kubernetes.io/last-applied-configuration`, `nginx.ingress.kubernetes.io/rewrite-target` |

Un label sert à **être trouvé** par un sélecteur ; une annotation sert à **être lu** (par un humain, un contrôleur d'Ingress, Helm, Argo CD…). Changer un label peut casser un Service, changer une annotation non.

**A5.** Comment trouves-tu l'`apiVersion` et le `kind` d'un objet à écrire ?

**Ta réponse :**

Trois méthodes, dans l'ordre :

1. `kubectl api-resources` : liste tous les types avec leur `APIVERSION`, leur `KIND` et l'abréviation (`kubectl api-resources | grep -i ingress`).
2. `kubectl explain <objet>` : donne la doc **du champ** et l'`apiVersion` attendue (`kubectl explain ingress.spec.rules`).
3. Prendre un objet existant comme modèle : `kubectl get <objet> <nom> -o yaml`, ou la documentation officielle.

Règle : l'`apiVersion` ne se devine pas, elle dépend de la version du cluster. En cas de doute, `kubectl explain` est la source de vérité locale.

### Partie B — Pod et labels

**B1.** Qu'est-ce qu'un Pod ? Qu'est-ce que ses conteneurs partagent ?

**Ta réponse :**

Un Pod est la **plus petite unité déployable** de Kubernetes : un ou plusieurs conteneurs qui sont **toujours planifiés ensemble sur le même nœud** et qui partagent :

- le **réseau** : une seule IP de pod, un seul espace de ports, donc `localhost` fonctionne entre conteneurs ;
- **IPC** et le nom d'hôte ;
- les **volumes** déclarés au niveau du Pod.

Ils ne partagent **pas** le système de fichiers de l'image : chaque conteneur garde son rootfs. Un Pod est immuable : on ne modifie pas ses conteneurs, on le remplace.

**B2.** Pourquoi un Pod seul n'est-il pas « auto-réparé » ?

**Ta réponse :**

Parce qu'un Pod n'a **aucun contrôleur** au-dessus de lui. Personne ne surveille son nombre de réplicas. Si tu le supprimes, s'il crashe définitivement, ou si son nœud tombe, il n'est jamais recréé.

C'est exactement le rôle du ReplicaSet (et du Deployment qui le pilote) : maintenir un nombre de pods. Un Pod nu est donc réservé aux tests et aux TP ; en production tout passe par un contrôleur.

**B3.** Qu'est-ce qu'un sidecar, et comment communique-t-il avec le conteneur principal ?

**Ta réponse :**

Un **sidecar** est un conteneur secondaire du même Pod dont le rôle est d'assister le conteneur principal : reverse proxy (Envoy), collecteur de logs (Fluent Bit), exportateur de métriques, synchroniseur de fichiers (git-sync).

Il communique par deux canaux, parce qu'il partage le Pod :

- **le réseau** : `localhost:<port>` (même IP, même espace de ports) ;
- **un volume partagé** : `emptyDir` ou ConfigMap, pour échanger des fichiers.

C'est le pattern « un conteneur = une responsabilité », sans payer un second Pod.

**B4.** Écris le sélecteur qui cible les pods ayant `app=web` et `tier` valant `front` ou `back`.

**Ta réponse :**

`app=web,tier in (front,back)`

En YAML, dans un `selector.matchLabels` ce n'est pas exprimable ; il faut `matchExpressions` :

```yaml
selector:
  matchExpressions:
    - key: app
      operator: In
      values: [web]
    - key: tier
      operator: In
      values: [front, back]
```

En ligne de commande, le `-l` accepte la forme courte : `kubectl get pods -l 'app=web,tier in (front,back)'`.

**B5.** Que se passe-t-il si le `selector` d'un Service ne correspond à aucun pod ?

**Ta réponse :**

Le Service obtient une `ClusterIP` mais **aucun endpoint** : `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` renvoie une liste vide, et `kubectl describe svc` affiche `Endpoints: <none>`.

Conséquence : toute connexion vers la ClusterIP est **refusée** (ou timeout). Ce n'est pas une erreur de Service mais de **sélecteur** : soit le label ne correspond pas, soit les pods ne sont pas `Ready` (ils sortent des endpoints tant que la readiness probe échoue).

### Partie C — ReplicaSet et Deployment

**C1.** Quel est le rôle d'un ReplicaSet ?

**Ta réponse :**

Un ReplicaSet garantit qu'un nombre précis de pods **correspondant à un sélecteur** tourne à tout instant. S'il y en a moins, il en crée ; s'il y en a plus, il en supprime.

Il ne fait **que** ça : pas de mise à jour progressive, pas d'historique. C'est le moteur, le Deployment est le pilote.

**C2.** Quelle est la différence entre un ReplicaSet et un Deployment ?

**Ta réponse :**

| | ReplicaSet | Deployment |
|---|---|---|
| Rôle | maintenir N pods | gérer **des versions** de l'application |
| Mise à jour | aucune (on remplace le RS à la main) | `RollingUpdate` automatique, nouveau RS par révision |
| Historique / rollback | non | `rollout history` / `rollout undo` |
| Propriétaire | créé par un Deployment | créé par toi |

En pratique on n'écrit jamais un ReplicaSet directement : on écrit un Deployment, qui crée et garde le ReplicaSet.

**C3.** Tu supprimes un pod géré par un Deployment. Que se passe-t-il et pourquoi ?

**Ta réponse :**

Le ReplicaSet compte les pods qui matchent son sélecteur, constate `2` au lieu de `3`, et **crée immédiatement un nouveau pod** (nom différent, même labels).

C'est la réconciliation : l'état constaté diverge du `spec.replicas`, le contrôleur corrige. Le pod supprimé est recréé sur le nœud que le scheduler choisit — pas forcément le même.

**C4.** Décris ce que fait une mise à jour `RollingUpdate`. Quels sont les deux paramètres qui la contrôlent ?

**Ta réponse :**

`RollingUpdate` remplace les pods **par petits groupes** au lieu de tout couper : un nouveau ReplicaSet monte, l'ancien descend, jusqu'à ce que l'ancien soit à 0. Le service reste disponible pendant l'opération.

Deux paramètres :

- **`maxSurge`** : combien de pods **en plus** du nombre désiré on autorise temporairement (défaut 25 %) ;
- **`maxUnavailable`** : combien de pods peuvent être **indisponibles** simultanément (défaut 25 %).

`maxSurge: 1` + `maxUnavailable: 0` = jamais moins de pods que voulu, mais un pod de plus à un moment donné.

**C5.** Quelles commandes utilisent pour suivre un déploiement, voir son historique et revenir en arrière ?

**Ta réponse :**

```bash
kubectl rollout status deployment/web      # suivre en direct
kubectl rollout history deployment/web     # révisions
kubectl rollout history deployment/web --revision=2   # détail d'une révision
kubectl rollout undo deployment/web        # revenir à la précédente
kubectl rollout undo deployment/web --to-revision=1   # revenir à une précise
kubectl rollout restart deployment/web     # redémarre sans changer l'image
```

`--to-revision=0` dans `undo` signifie « la précédente ».

**C6.** Pourquoi `spec.selector` est-il immuable dans un Deployment `apps/v1` ?

**Ta réponse :**

Parce que le sélecteur définit **l'ensemble des pods possédés** par le Deployment. Le modifier reviendrait à changer l'identité du Deployment : il pourrait « adopter » les pods d'un autre workload, ou en abandonner, et deux Deployments avec des sélecteurs qui se recouvrent se battraient pour les mêmes pods (un pod ne peut avoir qu'un seul propriétaire).

L'API refuse donc la modification : il faut supprimer et recréer le Deployment. Les labels du `template` restent, eux, modifiables — mais le sélecteur doit continuer à les couvrir.

### Partie D — Service et réseau

**D1.** Pourquoi un Service est-il nécessaire, alors que les pods ont déjà une IP ?

**Ta réponse :**

Parce que l'IP d'un pod est **éphémère** : elle change à chaque recréation, redéploiement ou déplacement sur un autre nœud. Coder une IP de pod en dur, c'est coder une adresse qui sera fausse dans 10 minutes.

Le Service apporte :

- une **IP virtuelle stable** (ClusterIP) et un **nom DNS** ;
- la **répartition** du trafic sur les pods prêts (load balancing) ;
- la **découverte** automatique des pods via les labels (endpoints) ;
- un découplage : le client ne connaît que le Service, pas les pods.

**D2.** Cite les quatre types de Service et leur usage.

**Ta réponse :**

| Type | Usage |
|---|---|
| `ClusterIP` | défaut ; joignable uniquement **dans** le cluster (DNS interne) |
| `NodePort` | ouvre un port (30000–32767) sur **chaque nœud** ; joignable depuis l'extérieur par `IP_du_nœud:port` |
| `LoadBalancer` | demande une IP externe au fournisseur ; dans K3s c'est ServiceLB qui l'implémente |
| `ExternalName` | pas de proxy : un simple alias DNS (CNAME) vers un nom externe |

Variante à connaître : le Service **headless** (`clusterIP: None`) ne donne pas d'IP virtuelle et renvoie directement les IP des pods via le DNS (utilisé par les StatefulSets).

**D3.** Quelle est la différence entre `port`, `targetPort` et `nodePort` ?

**Ta réponse :**

| Champ | Où | Sens |
|---|---|---|
| `port` | Service | le port **du Service**, celui que le client appelle (`http://web:80`) |
| `targetPort` | Service | le port **du conteneur** vers lequel le Service redirige (80 pour nginx) |
| `nodePort` | Service (NodePort/LoadBalancer) | le port ouvert sur **chaque nœud** (30000–32767) |

Chaîne complète : `client → nodePort → port du Service → targetPort du pod`. Si `targetPort` ne correspond à rien qui écoute dans le conteneur, le Service a des endpoints mais toutes les connexions échouent.

**D4.** Quelle commande montre les pods réellement ciblés par un Service, et que signifie une liste vide ?

**Ta réponse :**

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web
# ou, plus court (API dépréciée mais lisible) :
kubectl get endpoints web
```

Une liste vide (ou `Endpoints: <none>` dans `describe svc`) signifie que **le sélecteur du Service ne cible aucun pod prêt**. Deux causes, dans cet ordre :

1. le `selector` ne correspond à aucun label de pod (faute de frappe, label oublié dans le template) ;
2. les pods existent mais ne sont pas `Ready` (readiness probe en échec, image non démarrée).

C'est **la** commande de diagnostic d'un Service qui ne répond pas.

**D5.** Quel est le nom DNS complet d'un Service `web` dans le namespace `dev` ?

**Ta réponse :**

`web.dev.svc.cluster.local` (nom complet, avec le point final si on veut empêcher la résolution par les suffixes de recherche).

Les formes abrégées :

- `web` — seulement depuis le namespace `dev` ;
- `web.dev` — depuis n'importe quel namespace ;
- `web.dev.svc.cluster.local` — sans ambiguïté, y compris face à un vrai domaine public qui s'appellerait `web.dev`.

**D6.** Comment un Service `LoadBalancer` est-il implémenté dans K3s ?

**Ta réponse :**

K3s n'a pas de cloud provider : il embarque **ServiceLB** (ex-« Klipper »). Quand un Service `LoadBalancer` est créé, ServiceLB déploie un DaemonSet `svclb-<service>` **sur chaque nœud**, avec des `hostPort` sur les ports demandés.

Ces pods redirigent le trafic vers la `ClusterIP` du Service, et l'`EXTERNAL-IP` affichée est simplement **l'IP du nœud**. C'est pour ça que dans ta p2, `kubectl get svc -n kube-system traefik` montre `192.168.56.110` en EXTERNAL-IP : ce n'est pas une IP publique, c'est ton nœud.

### Partie E — Namespaces, ConfigMap, Secret

**E1.** Qu'est-ce qu'un namespace ? Cite trois namespaces par défaut.

**Ta réponse :**

Un namespace est une **partition logique** du cluster : il isole les **noms** (deux Services `web` peuvent coexister) et sert de périmètre aux quotas, au RBAC et aux politiques réseau.

Les namespaces présents par défaut sur un cluster K3s :

- `default` — là où vont tes objets quand tu ne précises rien ;
- `kube-system` — les composants du cluster (CoreDNS, Traefik, metrics-server) ;
- `kube-public` — lisible par tous (utilisé pour le bootstrap) ;
- `kube-node-lease` — les leases de heartbeat des nœuds.

`kube-system` n'est pas « plus privilégié » en soi, mais y écrire est une mauvaise idée.

**E2.** Deux Services `web` existent dans deux namespaces différents. Est-ce un conflit ? Comment les distingue-t-on ?

**Ta réponse :**

Non, ce n'est pas un conflit : le nom d'un objet est unique **dans son namespace**, pas dans le cluster. Deux Services `web` peuvent avoir la même `ClusterIP`… non, justement pas : chacun reçoit **sa propre** ClusterIP, mais le même **nom**.

On les distingue par :

- le namespace : `kubectl get svc web -n default` / `-n dev` ;
- le DNS : `web.default.svc.cluster.local` vs `web.dev.svc.cluster.local` ;
- la forme courte, qui ne marche que depuis le namespace courant.

C'est pour ça qu'« appliquer un manifeste dans le mauvais namespace » crée silencieusement un deuxième objet au lieu d'une erreur.

**E3.** À quoi servent un ConfigMap et un Secret ? Comment les injecte-t-on dans un pod (deux méthodes) ?

**Ta réponse :**

Un **ConfigMap** porte de la configuration **non sensible** (fichier HTML, `app.conf`, variables), un **Secret** porte des données **sensibles** (mot de passe, token, certificat) avec un traitement particulier (encodage base64, montage `tmpfs`, RBAC plus strict, possibilité d'encryption at rest).

Deux méthodes d'injection, identiques pour les deux objets :

1. **variables d'environnement** : `env` + `configMapKeyRef`/`secretKeyRef`, ou `envFrom` pour tout injecter d'un coup. Lu **au démarrage** du conteneur → jamais mis à jour à chaud.
2. **volume monté** : `volumes[].configMap`/`secret` + `volumeMounts`. Un volume **répertoire** est rafraîchi par kubelet (délai d'une minute environ) ; un montage `subPath` ne l'est **jamais**.

**E4.** Un Secret Kubernetes est-il chiffré ? Qu'est-ce que cela implique pour Git ?

**Ta réponse :**

Non. Un Secret est seulement **encodé en base64**, ce qui est une **représentation**, pas un chiffrement : `base64 -d` suffit à le lire. Seule la fonction *encryption at rest* du serveur d'API (désactivée par défaut) chiffre les Secrets dans etcd, et elle ne protège pas contre quelqu'un qui a le droit de lire le Secret.

Conséquences pour Git :

- ne **jamais** committer un Secret en clair, même base64 (un `git log` le garde éternellement) ;
- utiliser Sealed Secrets, SOPS, ou un gestionnaire externe (Vault) ;
- préférer un **volume** à une variable d'environnement : la variable fuit dans `kubectl describe pod`, dans les crash reports et dans les logs, pas le fichier.

### Partie F — Débogage et p2

**F1.** Un pod est en `ImagePullBackOff`. Que vérifies-tu ?

**Ta réponse :**

Dans l'ordre :

1. le nom et le **tag** de l'image (`nginx:1.25` existe, `nginx:1.25.0-alpine` peut ne pas exister) ;
2. `kubectl describe pod <pod>` → section `Events` : `Failed to pull image`, `manifest unknown`, `unauthorized` ;
3. le registre : accès réseau depuis le nœud (proxy, DNS) ;
4. si le registre est **privé** : `imagePullSecrets` présent sur le Pod/ServiceAccount ;
5. `imagePullPolicy` et la présence de l'image en cache sur le nœud.

**F2.** Un pod est en `CrashLoopBackOff`. Quelle commande te donne la cause, et que regardes-tu ?

**Ta réponse :**

```bash
kubectl describe pod <pod>          # section Events + Last State (Exit Code, Reason)
kubectl logs <pod> --previous       # la sortie du conteneur qui vient de mourir
```

On regarde :

- **l'Exit Code** : `1` = erreur applicative, `137` = `SIGKILL` (souvent OOMKilled), `139` = segfault ;
- la **commande** (`command`/`args`) : binaire inexistant, mauvais chemin ;
- une **config manquante** (fichier, variable, Secret absent) ;
- une **sonde** (liveness) qui tue le conteneur trop tôt ;
- la mémoire : `describe` affiche `OOMKilled` dans `Last State`.

**F3.** Un pod est en `Pending`. Cite trois causes possibles.

**Ta réponse :**

Un pod `Pending` n'a pas trouvé de nœud où s'installer. Trois causes classiques :

1. **ressources** : `requests` (CPU/mémoire) supérieurs à ce qui est libre sur les nœuds ;
2. **contraintes de placement** : `nodeSelector`, `affinity`/`anti-affinity` impossibles à satisfaire, ou `taint` sans `toleration` ;
3. **stockage** : `PersistentVolumeClaim` non lié (`Pending` lui aussi) — le pod attend son volume.

Diagnostic : `kubectl describe pod <pod>` → `Events` contient la phrase exacte (`Insufficient cpu`, `node(s) had untolerated taint`, `pod has unbound immediate PersistentVolumeClaims`).

**F4.** Un Service ne répond pas mais les pods sont `Running`. Quelle est la première chose à vérifier ?

**Ta réponse :**

Les **endpoints** : `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` (ou `kubectl describe svc`).

Si la liste est vide → `selector` qui ne matche rien, ou pods pas `Ready`. Si elle est pleine mais que ça ne répond pas, alors c'est le `targetPort` (rien n'écoute dans le conteneur), l'application elle-même (`kubectl logs`), ou une NetworkPolicy.

C'est l'ordre : **Service → endpoints → port → application**. Ça évite de chercher un bug dans le YAML du Deployment quand c'est un label.

**F5.** Pour la p2, quels objets devras-tu créer pour les trois applications, et lequel manque encore après cette leçon ?

**Ta réponse :**

Il faut **neuf objets** :

- 3 × `ConfigMap` (une page HTML par app) ;
- 3 × `Deployment` (`app1` 1 réplica, `app2` **3** réplicas, `app3` 1 réplica) ;
- 3 × `Service` en `ClusterIP` sur le port 80.

Il manque l'**Ingress** : c'est le seul objet qui sait router selon l'en-tête `Host` (`app1.com`, `app2.com`, et la route par défaut vers `app3`). C'est exactement la leçon 5.

---

## Mémo de la leçon

| Besoin | Commande |
|---|---|
| Appliquer un manifeste | `kubectl apply -f fichier.yaml` |
| Créer un Deployment | `kubectl create deployment <nom> --image=<img> --replicas=N` |
| Voir l'ensemble | `kubectl get all` |
| Détails / diagnostic | `kubectl describe <type> <nom>` (`pod`, `node`, `svc`…) |
| Logs | `kubectl logs <pod> [-f] [-c conteneur]` |
| Entrer dans un pod | `kubectl exec -it <pod> -- sh` |
| Accès local à un pod | `kubectl port-forward pod/<pod> 8080:80` (ou `svc/<service>`) |
| Scaler | `kubectl scale deployment/<nom> --replicas=N` |
| Changer l'image | `kubectl set image deployment/<nom> <conteneur>=<image>` |
| Suivre un rollout | `kubectl rollout status deployment/<nom>` |
| Historique / rollback | `kubectl rollout history` / `kubectl rollout undo` |
| Exposer un Deployment | `kubectl expose deployment <nom> --port=80 --target-port=80` |
| Créer un ConfigMap | `kubectl create configmap <nom> --from-file=<fichier>` / `--from-literal=clé=valeur` |
| Créer un Secret | `kubectl create secret generic <nom> --from-literal=clé=valeur` |
| Décoder un Secret | `kubectl get secret <nom> -o jsonpath='{.data.<clé>}' \| base64 -d; echo` |
| Voir les endpoints | `kubectl get endpointslices -l kubernetes.io/service-name=<service>` |
| Filtrer par label | `kubectl get pods -l app=web` |
| Namespace | `kubectl get pods -n <ns>` / `-A` |
| Supprimer | `kubectl delete -f fichier.yaml` |

---

Quand tu as terminé les TP et répondu aux questions : envoie-moi **« Leçon 4 terminée »** avec ton journal. Je corrigerai dans ce fichier, puis nous passerons à la **leçon 5 : Ingress et Traefik** (routage par `Host`, route par défaut, réplicas — la p2).
