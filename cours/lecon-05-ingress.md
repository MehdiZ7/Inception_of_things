# LEÇON 5 — Ingress et Traefik

> Suite de `lecon-04-objets-kubernetes.md`.
> Prérequis : cluster K3s mono-nœud `mzouhirS` (`192.168.56.110`) avec les trois Deployments (`app1` 1 réplica, `app2` 3 réplicas, `app3` 1 réplica) et leurs trois Services `ClusterIP`.
> Objectif : comprendre le routage HTTP **L7** par nom d'hôte, maîtriser Traefik tel que K3s l'installe, et **terminer la p2** (Ingress + route par défaut).

---

## Où on en est

La leçon 4 t'a appris à exposer des pods **dans** le cluster : un Service `ClusterIP` donne une IP virtuelle stable et un nom DNS, mais il ne sait pas lire une requête HTTP. Il répartit du TCP, point.

Or la p2 demande exactement l'inverse : **une seule IP (`192.168.56.110`), un seul port (80), et trois applications différentes selon l'en-tête `Host`**. C'est du routage applicatif, de la couche 7. Le Service ne peut pas le faire ; l'**Ingress** oui.

À l'instant où tu lis ça, ton cluster est déjà dans cet état :

- les trois Services répondent (`200` + `APP1`/`APP2`/`APP3`) depuis l'intérieur ;
- `curl http://192.168.56.110/` renvoie **`404`**.

Ce `404` n'est pas un bug : c'est Traefik qui écoute déjà sur le port 80 et qui te dit « aucune règle ne correspond ». Tu vas lui en donner trois.

---

## 5.1 Le problème : une IP, un port, trois applications

HTTP a une propriété qui rend tout ça possible : chaque requête porte un en-tête **`Host`**. C'est lui qui permet à des milliers de sites de partager la même IP et le même port 443. Un serveur HTTP lit `Host:` et décide quoi servir.

Sans proxy L7, tu n'as que trois solutions, toutes mauvaises pour la p2 :

| Solution | Pourquoi ça ne va pas |
|---|---|
| **3 × `NodePort`** | il faut un port différent par app (`:32406`, `:32293`…) or le sujet impose l'IP nue sur le port 80 |
| **3 × `LoadBalancer`** | ServiceLB tente de réserver le `hostPort: 80` pour chacun → conflit, un seul gagne |
| **`port-forward`** | manuel, un terminal par app, meurt avec la session : impossible à défendre |

L'Ingress règle les trois d'un coup : **un seul écouteur sur `:80`**, et une décision prise **par requête**, sur le `Host` (et éventuellement le chemin).

```
                 une seule entrée, un seul port
client ──────────────► 192.168.56.110:80
                            │
              ┌─────────────┼─────────────┐
        Host: app1.com   Host: app2.com   autre host
              │             │             │
           [app1]        [app2 ×3]      [app3]
```

---

## 5.2 Ingress ≠ Ingress Controller

C'est **la** confusion qui fait perdre le plus de temps.

| | Ingress | Ingress Controller |
|---|---|---|
| Nature | un **objet** Kubernetes (un fichier YAML appliqué) | un **programme** (un proxy) qui tourne dans le cluster |
| Rôle | décrire les règles de routage | lire ces règles et configurer le proxy en conséquence |
| Sans l'autre | ne fait **strictement rien** (objet stocké, ignoré) | tourne mais n'a aucune règle → renvoie 404 |
| Exemples | — | Traefik, ingress-nginx, HAProxy, Envoy Gateway |

Kubernetes ne fournit **aucun** contrôleur par défaut. Un cluster « nu » accepterait ton Ingress sans jamais router un seul paquet.

**K3s en installe un pour toi** : Traefik. C'est pour ça que tu as déjà un `404` sur `192.168.56.110:80` sans avoir rien installé. Tu n'as donc rien à installer dans cette leçon — juste à comprendre ce qui est là et à écrire des règles.

> Conséquence pratique : sur un autre cluster (kubeadm, minikube), il faudrait installer le contrôleur avant que le moindre Ingress fonctionne. C'est la première question à se poser en cas de 404 : « est-ce que le contrôleur tourne, et est-ce le bon ? ».

---

## 5.3 La chaîne complète, maillon par maillon

Voici le trajet réel d'une requête dans **ton** cluster, avec les valeurs que tu peux vérifier à l'écran :

```
navigateur / curl
   │   GET /   Host: app2.com
   ▼
[ hôte ] 192.168.56.110:80
   │   iptables : redirection du hostPort 80 (plugin portmap du CNI)
   ▼
[ svclb-traefik-xxxx ]   DaemonSet, un pod par nœud, 2 conteneurs (80 et 443)
   │   vers le Service traefik
   ▼
[ Service traefik ]      type LoadBalancer, EXTERNAL-IP 192.168.56.110
   │   port 80 → targetPort "web"
   ▼
[ pod traefik ] :8000    entrypoint "web"
   │   choisit le routeur : Host(`app2.com`) && PathPrefix(`/`)
   ▼
[ Service app2 ] :80     ClusterIP 10.43.x.x
   │   endpoints : 3 adresses de pods
   ▼
[ pod app2-xxxxx ] :80   sert /usr/share/nginx/html/index.html
```

Trois **liaisons** doivent tenir, sinon rien ne marche. Apprends-les par cœur, c'est l'ordre de diagnostic :

1. **Ingress → Service** : par **nom** (`backend.service.name`), dans le **même namespace**. Erreur ici → `404`.
2. **Service → Pods** : par **label** (`selector`). Erreur ici → **aucun endpoint** → `503`.
3. **Pod → processus** : par **`targetPort`**. Erreur ici → **`502`** (connexion refusée).

Une quatrième, implicite : **Service → port** (`backend.service.port.number` doit exister dans le Service). Erreur ici → `503` aussi.

### Qui écoute vraiment sur le port 80 ?

Ni ton nginx, ni un processus visible sur le nœud : c'est le pod `svclb-traefik-…` qui déclare un **`hostPort: 80`**. Kubernetes traduit ça en règles **iptables** (plugin `portmap`), donc `ss -ltn` sur le nœud peut ne **rien** montrer alors que le port répond. Ne conclus pas « rien n'écoute » sur la base de `ss` : teste avec `curl`.

Résumé de ce que K3s installe dans `kube-system` :

| Objet | Nom | Rôle |
|---|---|---|
| Job | `helm-install-traefik-crd` | installe les CRD Traefik (`IngressRoute`, `Middleware`…) |
| Job | `helm-install-traefik` | installe Traefik lui-même |
| Deployment | `traefik` | le contrôleur (le proxy) |
| Service | `traefik` | `LoadBalancer`, `EXTERNAL-IP` = IP du nœud |
| DaemonSet | `svclb-traefik-xxxx` | un pod par nœud qui prend le `hostPort` 80/443 |
| IngressClass | `traefik` (default) | le nom à mettre dans `ingressClassName` |

---

## 5.4 Anatomie d'un Ingress

L'API stable est `networking.k8s.io/v1`. Un Ingress complet et commenté :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apps-ingress
  namespace: default          # doit être le MÊME namespace que les Services ciblés
spec:
  ingressClassName: traefik   # quel contrôleur doit lire cette règle

  rules:
    # ── règle 1 : host explicite ────────────────────────────────
    - host: app1.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app1        # nom du Service
                port:
                  number: 80      # le PORT DU SERVICE (pas le targetPort !)

    # ── règle 2 : host explicite ────────────────────────────────
    - host: app2.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app2
                port:
                  number: 80

    # ── règle 3 : AUCUN host = attrape-tout (route par défaut) ──
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app3
                port:
                  number: 80
```

### Champ par champ

| Champ | Rôle | Piège |
|---|---|---|
| `ingressClassName` | désigne le contrôleur (`traefik` ici) | absent + pas de classe par défaut = Ingress ignoré |
| `metadata.namespace` | portée de l'objet | doit être celui des Services : `backend.service.name` est résolu **dans ce namespace** |
| `rules[].host` | filtre sur l'en-tête `Host` | **absent = tous les hosts** (c'est la clé de la p2) |
| `path` | préfixe ou chemin exact | dépend de `pathType` |
| `pathType` | `Prefix`, `Exact`, `ImplementationSpecific` | **obligatoire** en `v1` ; l'oublier = erreur de validation |
| `backend.service.name` | nom du Service | une faute de frappe → 404, pas d'erreur d'apply |
| `backend.service.port.number` | port **du Service** | mettre le `targetPort` ou le port du conteneur → 503 |

### `pathType`

| Valeur | Sens | Traduction Traefik |
|---|---|---|
| `Exact` | le chemin doit être **exactement** celui-ci | `Path(...)` |
| `Prefix` | le chemin commence par ce préfixe, **segment par segment** | `PathPrefix(...)` |
| `ImplementationSpecific` | laissé au contrôleur | dépend de Traefik |

`Prefix` avec `/` matche donc **tout**. C'est ce qu'on veut ici.

### Variante : le `defaultBackend`

Une alternative pour la route par défaut, **hors** de `rules` :

```yaml
spec:
  defaultBackend:
    service:
      name: app3
      port:
        number: 80
```

Elle fonctionne aussi. Différence à comprendre :

- **règle sans `host`** : une règle **normale**, mais de priorité minimale ; visible dans `kubectl describe ingress` au milieu des autres.
- **`defaultBackend`** : utilisé uniquement quand **aucune** règle de l'Ingress ne matche ; c'est le « catch-all » officiel de la spec.

Les deux sont acceptables techniquement. Pour la p2, je recommande la **règle sans `host`** : c'est ce que les correcteurs s'attendent à voir dans `describe ingress`, et ça montre que tu as compris que `host` est optionnel.

---

## 5.5 Ce que Traefik fait de tes règles

### Version et entrypoints

Dans ton cluster (vérifiable) :

- image `rancher/mirrored-library-traefik:3.7.15` → **Traefik v3** ;
- conteneur : `8000` (`web`), `8443` (`websecure`), `8080` (API/dashboard), `9100` (métriques) ;
- Service `traefik` : `80 → web`, `443 → websecure`, donc **le port 80 du nœud arrive sur le 8000 du conteneur**.

Les *entrypoints* sont les ports d'écoute internes de Traefik. Tu ne les configures pas dans l'Ingress : l'Ingress décrit seulement « quel host/chemin va vers quel Service ».

### Priorité des routeurs

Traefik applique les routeurs **du plus spécifique au plus général**. Par défaut, sa priorité est **la longueur de la règle** :

| Règle générée | Longueur | Priorité |
|---|---|---|
| `Host(\`app1.com\`) && PathPrefix(\`/\`)` | ~38 | **haute** |
| `Host(\`app2.com\`) && PathPrefix(\`/\`)` | ~38 | haute |
| `PathPrefix(\`/\`)` | 14 | **basse** |

Donc :

- `Host: app1.com` → les deux premiers routeurs matchent, le plus prioritaire gagne → `app1` ;
- `Host: 192.168.56.110` (IP tapée nue) → seul le troisième matche → `app3` ;
- `Host: nimporte.quoi` → seul le troisième → `app3`.

**L'ordre des règles dans le fichier YAML n'a aucune importance.** C'est la longueur de la règle calculée par Traefik qui décide, pas ta mise en page. Tu le vérifieras au TP 4.

> Si un jour deux routeurs ont des règles de même longueur pour le même host, le résultat n'est pas garanti. C'est une raison de plus pour ne pas dupliquer les hosts dans plusieurs Ingress.

### Dashboard

Traefik est installé avec `--api.dashboard=true`. Pour le voir, sans l'exposer sur Internet :

```bash
kubectl port-forward -n kube-system svc/traefik 8080:80
# puis http://localhost:8080/dashboard/
```

C'est un outil de diagnostic : tu y vois les routeurs, leur priorité, leurs services et leurs erreurs. Très pratique quand un 404 ne s'explique pas.

### Personnaliser / désinstaller

- Pour modifier la config de Traefik, on crée un `HelmChartConfig` dans `kube-system` (K3s le fusionne avec ses valeurs). Aucun n'existe dans ton cluster.
- Pour le désinstaller complètement : `--disable traefik` dans la config K3s. **À ne surtout pas faire** : il n'y aurait plus aucun contrôleur Ingress.

---

## 5.6 La route par défaut : le cœur de la p2

Le sujet dit :

> « When the HOST `app1.com` is used, the server must display `app1`. When the HOST `app2.com` is used, the server must display `app2`. **Otherwise, app3 will be selected by default.** »

« Otherwise » ne veut pas dire « `app3.com` ». Ça veut dire **tout le reste**, et « tout le reste » inclut des cas que tu dois tester :

| Requête | En-tête `Host` envoyé | Route attendue |
|---|---|---|
| `http://app1.com/` | `app1.com` | app1 |
| `http://app2.com/` | `app2.com` | app2 |
| `http://app3.com/` | `app3.com` | app3 |
| `http://nimporte.quoi/` | `nimporte.quoi` | app3 |
| `curl http://192.168.56.110/` | `192.168.56.110` | app3 |
| requête HTTP/1.0 sans `Host` | *(vide)* | app3 |

Les trois approches possibles :

| Approche | Verdict |
|---|---|
| `host: app3.com` | ❌ **faux** : l'IP nue et les hosts inconnus renvoient 404 |
| `spec.defaultBackend: app3` | ✅ correct, sémantique « aucun match » |
| **règle sans `host`** | ✅ **recommandé**, visible dans `describe`, priorité minimale |

### Pourquoi la règle sans `host` ne « mange » pas app1 et app2

Parce que Traefik génère **trois** routeurs, pas un. Celui d'app1 exige `Host=app1.com`, celui d'app3 n'exige rien. Une requête `app1.com` satisfait les deux, mais la priorité (longueur de règle) envoie vers app1. C'est exactement le mécanisme décrit au §5.5, et c'est pour ça que l'ordre du YAML est indifférent.

Si tu veux t'en convaincre visuellement : le dashboard Traefik affiche les trois routeurs avec leur priorité, et met en évidence celui qui a servi la requête.

---

## 5.7 Lire les codes HTTP : la table de diagnostic

C'est la compétence qui te fera gagner du temps — et qui impressionne en soutenance.

| Code | Signification pour Traefik | Où est le problème | Commande |
|---|---|---|---|
| **404** Not Found | aucun routeur n'a matché | **Ingress** : host mal orthographié, règle absente, mauvais namespace, `ingressClassName` faux | `kubectl describe ingress` |
| **503** Service Unavailable | routeur OK, mais **zéro serveur disponible** | **Service** : selector qui ne matche rien, pods pas `Ready`, port inexistant dans le Service | `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` |
| **502** Bad Gateway | endpoint trouvé, **connexion refusée** | **Pod** : rien n'écoute sur le `targetPort` (mauvais port, app down) | `kubectl exec` + `curl localhost:<port>` |
| **504** Gateway Timeout | endpoint trouvé, TCP accepté, **pas de réponse à temps** | **Application** : boucle infinie, deadlock, charge | `kubectl logs`, `top` |
| **200 mais mauvaise app** | routeur en trop ou priorité surprise | **règles** : deux hosts identiques, catch-all trop spécifique | dashboard Traefik |

Retiens la progression : **404 = Ingress, 503 = Service, 502/504 = Pod.** C'est plus rapide que de relire tout le YAML depuis le début.

---

## 5.8 Tester sans navigateur

Le navigateur est le pire outil de test : il met en cache, il masque les en-têtes, il suit les redirections. Utilise `curl`.

### Forcer l'en-tête `Host`

```bash
curl -i -H "Host: app1.com" http://192.168.56.110/
```

Simple, mais **différent** d'une vraie requête : l'URL reste l'IP, le nom n'est jamais résolu. Ça teste le routage, pas la résolution.

### Simuler une vraie résolution (`--resolve`)

```bash
curl -i --resolve app1.com:80:192.168.56.110 http://app1.com/
```

`--resolve` dit à curl « pour `app1.com` sur le port 80, utilise cette IP », sans toucher à `/etc/hosts`. La requête part avec `Host: app1.com` **et** l'URL est le nom. C'est la méthode la plus proche du navigateur, et elle ne laisse aucune trace dans le système.

### Le cas « IP nue »

```bash
curl -i http://192.168.56.110/
```

En HTTP/1.1, curl envoie `Host: 192.168.56.110`. C'est ce cas qui doit tomber sur `app3` grâce à la règle sans `host`. Si tu obtiens 404, ta route par défaut est fausse.

### Voir ce qui se passe

```bash
curl -sv http://192.168.56.110/ -H "Host: app2.com" 2>&1 | grep -E "^[<>]|Trying|Connected"
```

Tu y lis la requête exacte (dont `Host:`) et la réponse. En HTTP/2, l'en-tête s'appelle `:authority` — même sens, autre nom ; c'est le piège quand on compare un `curl` et un navigateur.

### Le navigateur, pour la soutenance

Ajoute sur **ta machine hôte** (pas dans la VM) :

```
192.168.56.110  app1.com
192.168.56.110  app2.com
```

Vérifie qu'il ne reste pas un ancien `127.0.0.1 app1.com`. Puis `http://app1.com/`. Le sujet demande explicitement le test au navigateur — prépare-le.

---

## 5.9 Les 3 réplicas d'app2 : qui fait le load balancing ?

Deux mécanismes se superposent dans Kubernetes, et c'est utile de savoir lequel agit :

1. **kube-proxy** programme des règles iptables pour les `ClusterIP` : il répartit sur les endpoints, mais de façon **aléatoire par connexion**.
2. **Traefik** ne passe pas par la `ClusterIP` : il surveille les `EndpointSlices` et construit lui-même la liste des serveurs, puis répartit en **weighted round-robin** (défaut v3).

Résultat : avec 3 réplicas derrière `app2.com`, tes requêtes tournent entre les 3 pods. Ce n'est pas observable à l'œil si les trois pages sont identiques — d'où l'astuce du TP 9 : compter les requêtes dans les logs de chaque pod.

À retenir pour la soutenance :

- 3 réplicas ≠ 3× plus de trafic ; c'est 3× la capacité **et** la tolérance à la panne ;
- si un pod meurt, Traefik retire son endpoint en quelques secondes : **aucune erreur visible**, juste moins de capacité. C'est ça, la haute disponibilité ;
- sans mécanisme de session (sticky), deux requêtes successives peuvent atterrir sur deux pods différents. La p2 n'en a pas besoin.

---

## 5.10 Plusieurs Ingress, et le routage par chemin

Deux Ingress peuvent coexister : Traefik fusionne leurs routeurs. Tant que les `host` sont distincts, aucun conflit. Deux règles **identiques** sur le même host = comportement non garanti → à éviter.

Alternative au routage par `Host` : le routage par **chemin** :

```yaml
rules:
  - host: demo.com
    http:
      paths:
        - path: /app1
          pathType: Prefix
          backend: { service: { name: app1, port: { number: 80 } } }
        - path: /app2
          pathType: Prefix
          backend: { service: { name: app2, port: { number: 80 } } }
```

Piège : le pod reçoit `/app1/index.html` et nginx cherche un sous-dossier `app1/` → **404 de nginx** (pas de Traefik !). Il faut un middleware qui retire le préfixe avant de transmettre (`StripPrefix`), ce qui est hors périmètre de la p2. C'est la raison pour laquelle le routage par `Host` est plus simple ici.

| | Par `Host` | Par chemin |
|---|---|---|
| Nécessite un nom DNS | oui (ou `--resolve` / `/etc/hosts`) | non |
| Marche avec l'IP nue | non (sauf catch-all) | oui |
| Réécriture nécessaire | non | souvent oui |
| Usage typique | plusieurs sites | plusieurs APIs d'un même site |

---

## 5.11 TLS, pour comprendre (pas pour la p2)

Un Ingress peut terminer le HTTPS :

```yaml
spec:
  tls:
    - hosts: [app1.com]
      secretName: app1-tls   # Secret de type kubernetes.io/tls (tls.crt + tls.key)
```

Si aucun `tls` n'est déclaré, Traefik sert quand même du HTTPS sur 443, avec son **certificat auto-signé** par défaut — d'où l'avertissement du navigateur. La p2 ne demande pas de TLS : n'en mets pas, ça n'apporterait que des questions en soutenance.

---

## 5.12 Ingress et les autres solutions d'exposition

| Moyen | Couche | Port | Routage par Host | Usage |
|---|---|---|---|---|
| `ClusterIP` | L4 | interne | non | communication interne |
| `NodePort` | L4 | 30000–32767 | non | debug, accès direct |
| `LoadBalancer` | L4 | 80/443 | non | un service exposé, une IP |
| **Ingress** | **L7** | 80/443 | **oui** | plusieurs services derrière une IP |
| `port-forward` | tunnel | local | non | debug ponctuel |
| Gateway API | L7 | 80/443 | oui | successeur de l'Ingress (hors sujet) |

---

## 5.13 Ce que la p2 attend exactement de toi

| Objet | Nombre | Détail |
|---|---|---|
| `Ingress` | **1** | `apps-ingress` |
| Règles | **3** | `app1.com` → app1, `app2.com` → app2, **sans host** → app3 |
| `ingressClassName` | 1 | `traefik` |
| Namespace | — | `default` (celui des Services) |

Preuves à garder pour la soutenance :

1. `kubectl get ingress` et `kubectl describe ingress apps-ingress` ;
2. les trois tests `curl` (app1.com, app2.com, IP nue) ;
3. `kubectl get endpoints app2` → 3 IP ;
4. le dashboard Traefik (optionnel mais très convaincant).

---

## 5.14 TP — À toi de jouer

> Aucune solution n'est donnée. Note tout dans `cours/journal-lecon5.txt`, y compris les erreurs : c'est ce journal que je corrigerai.
> Tous les tests se font depuis **ta machine hôte** sauf indication contraire. `192.168.56.110` est ton nœud.

### TP 1 — Cartographier Traefik dans ton cluster

1. Dans `kube-system`, repère les **cinq** objets liés à Traefik (deux Jobs, un Deployment, un Service, un DaemonSet). Note leurs noms.
2. Note la **version exacte** de l'image Traefik et la liste des ports du conteneur. À quoi sert chacun ?
3. `kubectl get ingressclass` : quel nom, est-il `(default)` ?
4. `kubectl get svc traefik -n kube-system -o wide` : type, `EXTERNAL-IP`, mapping des ports. Pourquoi l'`EXTERNAL-IP` est-elle une IP privée ?
5. `kubectl get ds -n kube-system` et décris le DaemonSet `svclb-*` : combien de pods, combien de conteneurs, quels `hostPort` ?
6. Depuis l'hôte : `curl -i http://192.168.56.110/`. Note le code, le corps, et l'en-tête `Server`.
7. Sur le nœud, `sudo ss -ltn | grep :80` : que vois-tu ? Explique pourquoi ce n'est pas contradictoire avec le point 6.
8. Écris dans ton journal la chaîne complète en 5 flèches, avec les vrais numéros de port.

### TP 2 — Premier Ingress : une seule règle

1. Écris `manifest/ingress.yaml` avec **une seule** règle : `app1.com` → Service `app1`, port 80, `ingressClassName: traefik`.
2. Applique-le, puis `kubectl get ingress` et `kubectl describe ingress`.
3. Teste `--resolve` sur `app1.com` : code ? contenu ?
4. Teste `-H "Host: app2.com"` et l'IP nue : quels codes ? Pourquoi ?
5. Teste `-H "Host: app1.com"` **sans** `--resolve` : ça marche aussi ? Quelle différence cela fait-il sur le nom résolu ?
6. Ajoute les entrées dans `/etc/hosts` de l'hôte et ouvre `http://app1.com/` au navigateur.
7. Supprime l'Ingress et vérifie que tout retombe en 404.

### TP 3 — 404, 503, 502 : provoquer chaque code

1. Remets l'Ingress du TP 2 (`app1.com` → app1).
2. Casse le `selector` du Service `app1` (une lettre de différence). Vérifie les endpoints, puis `curl` sur `app1.com`. Note le code et explique.
3. Répare le selector : le code revient à 200 sans toucher à l'Ingress. Pourquoi ?
4. Change le `targetPort` du Service vers un port où rien n'écoute (ex. 8080). Teste. Code ? Vérifie les endpoints : que contiennent-ils maintenant ?
5. Remets `targetPort: 80`. Puis, dans l'**Ingress**, change `backend.service.port.number` vers 8080 (un port qui n'existe pas dans le Service). Teste, puis remets 80.
6. Complète un tableau à trois colonnes : manipulation / code obtenu / maillon fautif.

### TP 4 — Deuxième app, et la preuve que l'ordre du YAML ne compte pas

1. Ajoute une règle `app2.com` → Service `app2`.
2. Teste les deux hosts, puis un host inconnu (`toto.local`) et l'IP nue. Note les 4 codes.
3. **Inverse l'ordre** des deux règles dans le fichier, réapplique, reteste. Que constates-tu ?
4. Explique, en une phrase, ce qui détermine l'ordre d'évaluation.
5. Vérifie dans le dashboard Traefik (`port-forward` sur le Service) la priorité affichée pour chaque routeur.

### TP 5 — La route par défaut (TP central de la p2)

1. Ajoute une **troisième règle sans `host`** vers le Service `app3`.
2. Réalise les **cinq** tests du §5.6 (app1.com, app2.com, app3.com, host inconnu, IP nue) et note les 5 contenus obtenus.
3. Vérifie que les deux premiers n'ont pas été « aspirés » par la route par défaut. Si oui, explique pourquoi (priorité).
4. Remplace la règle sans `host` par `host: app3.com`. Reteste les 5 cas. Lesquels cassent ? Note les codes.
5. Remets la version sans `host`.
6. Supprime la troisième règle et utilise `spec.defaultBackend` vers `app3`. Compare `kubectl describe ingress` avec la version précédente, puis refais les 5 tests.
7. Dans ton journal : tableau des trois approches (host app3.com / sans host / defaultBackend) × les 5 cas.

### TP 6 — Priorités et spécificité

1. Sur `app1.com`, ajoute une règle de chemin `/api` vers le Service `app3`, en gardant `/` vers `app1`.
2. Teste `app1.com/` et `app1.com/api` (ou `app1.com/api/`). Qui répond ?
3. Explique pourquoi `/api` gagne sur `/` pour la même host.
4. Ajoute l'annotation de priorité Traefik pour **inverser** le résultat, réapplique, reteste. Note le nom exact de l'annotation.
5. Retire l'annotation et la règle `/api`.

### TP 7 — Routage par chemin et middleware (avancé)

> Nécessite les CRD Traefik, présentes dans ton cluster (`kubectl get crd | grep traefik`).

1. Crée un Ingress sur le host `demo.com` avec deux chemins : `/app1` → app1, `/app2` → app2.
2. Teste. Que renvoie nginx ? Lis les logs du pod : quelle URL a-t-il reçue ?
3. Crée un `Middleware` Traefik de type `stripPrefix` sur `/app1`, et branche-le sur la route via une annotation. Reteste.
4. Compare avec le routage par `Host` : quel est le comportement le plus simple à maintenir ?
5. Supprime tout.

### TP 8 — Conflits entre Ingress

1. Crée un **second** Ingress, dans `default`, avec `host: app1.com` → Service `app3` (volontairement en conflit).
2. Teste `app1.com`. Observe ce qui se passe, et cherche les avertissements dans les logs de Traefik.
3. Affiche le dashboard : combien de routeurs pour `app1.com` ? Quelle priorité ?
4. Supprime le second Ingress et vérifie le retour à la normale.
5. Conclusion dans le journal : comment éviter ce type de conflit dans un vrai dépôt.

### TP 9 — Prouver le load balancing des 3 réplicas

1. Vérifie que `app2` a bien 3 endpoints.
2. Envoie **12 requêtes** sur `app2.com` depuis l'hôte, en une boucle.
3. Pour chacun des 3 pods d'app2, compte les lignes de log nginx correspondantes (`kubectl logs <pod> | wc -l` avant/après). La répartition est-elle équilibrée ?
4. Supprime **un** pod d'app2 pendant que tu envoies des requêtes : observes-tu des erreurs ? Combien de temps met le Service à retrouver 3 endpoints ?
5. Recommence en supprimant **deux** pods. Que se passe-t-il ? Pourquoi n'y a-t-il toujours pas d'erreur ?
6. Écris en trois phrases ce que tu dirais à un évaluateur qui demande « à quoi servent les 3 réplicas ? ».

### TP 10 — La p2 complète, comme pour la soutenance

1. Écris le fichier final `manifest/ingress.yaml` : `apps-ingress`, `ingressClassName: traefik`, trois règles (deux hosts + une sans host).
2. Applique-le sur un cluster **propre** : `kubectl delete -f manifest/` puis `kubectl apply -f manifest/`. Vérifie l'ordre de création et qu'aucun pod ne reste bloqué.
3. Réalise le scénario de soutenance dans l'ordre :
   - montre les nœuds (`kubectl get nodes`) ;
   - montre les 5 pods et leur nœud (`kubectl get pods -o wide`) ;
   - montre les 3 Services et les endpoints (`get svc`, `get endpoints`) ;
   - montre l'Ingress (`get ingress`, `describe ingress`) ;
   - exécute les 3 `curl` (app1.com, app2.com, IP nue) ;
   - ouvre les 3 pages au navigateur.
4. Chronomètre-toi : la démo complète doit tenir en moins de 5 minutes, sans hésitation sur les commandes.
5. Note dans le journal les 3 phrases d'explication que tu diras pour la route par défaut.

### TP 11 — Reconstruction totale (le test que fera l'évaluateur)

1. `vagrant destroy -f`, puis `vagrant up`.
2. Vérifie que le cluster remonte seul : nœud `Ready`, Traefik `Running`.
3. Applique les manifests (`kubectl apply -f manifest/`).
4. Refais les 5 tests du §5.6.
5. Si quelque chose ne remonte pas automatiquement, note précisément quoi : c'est ce qui te fera perdre des points le jour J.

---

## 5.15 Erreurs fréquentes

| Erreur | Symptôme | Cause | Correctif |
|---|---|---|---|
| `host: app3.com` au lieu d'une règle sans host | IP nue → 404 | route par défaut mal comprise | retirer `host` de la 3ᵉ règle |
| `pathType` oublié | `kubectl apply` refuse le manifeste | champ obligatoire en `v1` | ajouter `pathType: Prefix` |
| `backend.service.port.number` = `targetPort` | 503 | port inexistant dans le Service | mettre le `port` du Service (80) |
| Ingress et Services dans deux namespaces | 404 | le backend est résolu dans le namespace de l'Ingress | tout mettre dans `default` |
| `ingressClassName` absent et classe par défaut ambiguë | 404, Ingress ignoré | aucune classe par défaut | `ingressClassName: traefik` |
| Selector du Service faux | 503, endpoints vides | label | corriger le selector |
| Pod pas `Ready` | 503 | readiness probe | `describe pod` |
| Rien n'écoute dans le conteneur | 502 | mauvais port, app crashée | `exec` + `curl localhost` |
| Deux Ingress sur le même host | comportement erratique | conflit de routeurs | un seul Ingress par host |
| Test avec le navigateur seul | faux négatifs | cache, redirections, `:authority` | toujours valider avec `curl` |

---

## 5.16 Questions de la leçon 5

**Q1.** Quelle est la différence entre un objet Ingress et un Ingress Controller ?

**Ta réponse :**

<!-- écris ici -->

**Q2.** Pourquoi un Service `ClusterIP` ne peut-il pas router selon le nom de domaine ?

**Ta réponse :**

<!-- écris ici -->

**Q3.** Quels sont les cinq maillons de la chaîne entre le navigateur et le pod, dans ton cluster K3s ?

**Ta réponse :**

<!-- écris ici -->

**Q4.** À quoi sert `pathType` et que signifie `Prefix` avec `path: /` ?

**Ta réponse :**

<!-- écris ici -->

**Q5.** Comment obtenir « sinon app3 » de trois façons différentes, et laquelle est la meilleure pour la p2 ?

**Ta réponse :**

<!-- écris ici -->

**Q6.** Pourquoi une règle sans `host` ne capture-t-elle pas les requêtes destinées à `app1.com` ?

**Ta réponse :**

<!-- écris ici -->

**Q7.** Comment Traefik calcule-t-il la priorité de ses routeurs, et que se passe-t-il si l'ordre du YAML change ?

**Ta réponse :**

<!-- écris ici -->

**Q8.** Un client reçoit 404 : quel maillon est en cause ? Et pour 503 ? Et pour 502 ?

**Ta réponse :**

<!-- écris ici -->

**Q9.** Quelle commande affiche les pods réellement ciblés par un Service ?

**Ta réponse :**

<!-- écris ici -->

**Q10.** Que se passe-t-il si `backend.service.port.number` vaut 8080 alors que le Service n'expose que 80 ?

**Ta réponse :**

<!-- écris ici -->

**Q11.** L'Ingress et les Services doivent-ils être dans le même namespace ? Pourquoi ?

**Ta réponse :**

<!-- écris ici -->

**Q12.** Pourquoi l'`EXTERNAL-IP` du Service `traefik` est-elle `192.168.56.110` ?

**Ta réponse :**

<!-- écris ici -->

**Q13.** Qui fait le load balancing des 3 réplicas d'app2 : kube-proxy, Traefik, ou les deux ? Explique.

**Ta réponse :**

<!-- écris ici -->

**Q14.** Comment testes-tu proprement `app1.com` sans modifier `/etc/hosts` ?

**Ta réponse :**

<!-- écris ici -->

**Q15.** Quels objets as-tu créés en tout pour la p2, et lequel est le seul qui sait lire un en-tête `Host` ?

**Ta réponse :**

<!-- écris ici -->

---

## Mémo de la leçon

| Besoin | Commande |
|---|---|
| Voir les Ingress | `kubectl get ingress` |
| Détail des règles | `kubectl describe ingress <nom>` |
| État du contrôleur | `kubectl get pods,svc,ds -n kube-system \| grep -i traefik` |
| Classe d'Ingress | `kubectl get ingressclass` |
| Logs Traefik | `kubectl logs -n kube-system deploy/traefik` |
| Dashboard | `kubectl port-forward -n kube-system svc/traefik 8080:80` → `http://localhost:8080/dashboard/` |
| Endpoints d'un Service | `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` |
| Tester un host | `curl -i --resolve app1.com:80:192.168.56.110 http://app1.com/` |
| Forcer l'en-tête seul | `curl -i -H "Host: app1.com" http://192.168.56.110/` |
| Tester l'IP nue | `curl -i http://192.168.56.110/` |
| Appliquer un dossier | `kubectl apply -f manifest/` |
| Tout supprimer | `kubectl delete -f manifest/` |

---

## Et après

Quand tu as terminé les TP et répondu aux questions : envoie-moi **« Leçon 5 terminée »** avec `cours/journal-lecon5.txt`. Je corrigerai ici, puis nous attaquerons la **p3** : `k3d`, un script d'installation complet, deux namespaces (`argocd`, `dev`) et le GitOps avec Argo CD — où le routage par hostname que tu viens d'apprendre resservira tel quel.
