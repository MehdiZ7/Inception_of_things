# Inception of Things — Cours guidé

> Professeur : ton assistant. Élève : toi.
> Objectif final : être capable de construire **seul** le projet IoT (p1, p2, p3, puis bonus) et de le **défendre** à l'oral.

---

## Mode d'emploi (à lire une fois)

1. Chaque leçon = un cours court + des **TP** (tu tapes les commandes) + des **questions**.
2. Tu écris tes réponses **directement dans ce fichier**, sous chaque question, à l'endroit prévu.
3. Tu envoies ensuite un message du type : *« Leçon 1 terminée, corrige-moi »*.
4. Je corrige dans le fichier (je réponds sous tes réponses), je signale les erreurs, puis je crée la leçon suivante.
5. On n'avance **que** quand la leçon est comprise. Une question ratée = on la retravaille.

Règles d'or :
- Tu ne copies-colles pas une commande sans la comprendre : avant de l'exécuter, essaie de dire ce qu'elle va faire.
- Tu **casses** des choses dans un dossier de test (`~/iot-lab`), jamais ailleurs.
- Tu me dis quand tu ne comprends pas, même une notion « basique ». Il n'y a pas de question bête.
- **Les TP ne contiennent volontairement aucune solution.** Le cours juste au-dessus te donne les outils ; à toi de choisir la bonne commande. C'est comme ça qu'on apprend.

### Note sur `sudo`

Certains TP demandent les droits administrateur. Sur ton poste tu n'as pas `sudo` : les étapes concernées sont marquées **[VM]** et seront faites sur ta machine virtuelle (ou plus tard, quand on y sera). Tout le reste se fait sans droits particuliers.

---

## Plan du cours (on le remplira au fur et à mesure)

- [x] **Leçon 1 — Les fondations** : terminal, fichiers, permissions, processus/services, réseau, SSH
- [ ] Leçon 2 — Virtualisation et Vagrant : créer ses machines par code (p1, étape 1)
- [ ] Leçon 3 — K3s : installer un cluster Kubernetes léger (fin p1)
- [ ] Leçon 4 — Objets Kubernetes : Pod, Deployment, Service, YAML, kubectl
- [ ] Leçon 5 — Ingress et Traefik : router par nom de domaine (p2)
- [ ] Leçon 6 — Docker : images, conteneurs, registries, tags
- [ ] Leçon 7 — K3d : K3s dans Docker, mapping de ports (p3, étape 1)
- [ ] Leçon 8 — Git, GitHub, GitOps et Argo CD (fin p3)
- [ ] Leçon 9 — Helm et GitLab (bonus)
- [ ] Leçon 10 — Révision soutenance : questions pièges et démo complète

---

# LEÇON 1 — Les fondations

---

## Objectifs de la leçon

À la fin, tu dois savoir :
- te déplacer et manipuler des fichiers en ligne de commande ;
- lire et modifier des permissions (`rwx`, `chmod`, `sudo`) ;
- observer et arrêter un processus, et comprendre un service systemd ;
- lire ta configuration réseau, tester un port et une connexion HTTP ;
- comprendre l'authentification SSH par clé et générer une paire de clés.

Pourquoi commencer ici ? Parce que **tout le projet se passe dans des machines Linux sans interface graphique**. Si tu ne maîtrises pas ces gestes, tu ne pourras pas diagnostiquer une VM qui ne répond pas, un script qui échoue, ou un cluster qui ne démarre pas. Ce sont les outils du quotidien de l'administrateur système.

---

## 1.1 Le terminal, c'est quoi exactement ?

Une **interface graphique** te propose des icônes. Un **terminal** est une fenêtre où tu écris des commandes en texte. Une commande est en réalité un **programme** situé quelque part sur le disque (souvent `/usr/bin`). Quand tu tapes `ls`, ton shell cherche un programme nommé `ls` dans les dossiers listés dans la variable `PATH`, l'exécute, puis t'affiche sa sortie.

Une commande a cette forme générale :

```
commande [options] [arguments]
```

- `ls -l /etc` : `ls` = commande, `-l` = option (affichage détaillé), `/etc` = argument (le dossier à lister).
- Une option courte commence par un tiret (`-l`), une option longue par deux (`--all`).

Le **shell** est le programme qui lit tes commandes. Sur Linux c'est en général `bash`. Il gère :
- les **variables** d'environnement (`echo $HOME`),
- les **redirections** : `>` (écrase un fichier), `>>` (ajoute), `<` (lit depuis un fichier),
- les **pipes** : `|` envoie la sortie d'une commande dans l'entrée d'une autre (`ls | wc -l`),
- les **jokers** : `*` (n'importe quoi), `?` (un caractère).

Ce qu'il faut retenir : **le terminal ne « devine » rien**. Si une commande échoue, elle te donne un message d'erreur, et ce message est ta meilleure piste.

---

## 1.2 Le système de fichiers Linux

Linux ne connaît pas de « C: » ou « D: ». Tout part d'une **racine unique** : `/`. Les dossiers importants :

| Chemin | Rôle |
|---|---|
| `/` | racine de tout |
| `/etc` | fichiers de **configuration** (`/etc/hosts`, `/etc/ssh/sshd_config`) |
| `/var` | données qui évoluent : logs dans `/var/log`, bases de données |
| `/home` | dossiers personnels (`/home/mzouhir`) |
| `/root` | dossier personnel de l'administrateur |
| `/tmp` | fichiers temporaires, effacés au redémarrage |
| `/usr/bin` | la plupart des programmes |
| `/usr/local/bin` | programmes installés manuellement |
| `/dev` | périphériques |
| `/proc` et `/sys` | informations du noyau, générées à la volée |

**Chemin absolu** : commence par `/` et est valable depuis n'importe où (`/etc/hosts`).
**Chemin relatif** : dépend de l'endroit où tu es (`confs/app.yaml`).
Raccourcis : `.` = ici, `..` = dossier parent, `~` = ton dossier personnel, `-` = dossier précédent.

---

## 1.3 Naviguer et manipuler

Commandes de base :

```bash
pwd                 # où suis-je ? (print working directory)
ls -la              # liste détaillée, fichiers cachés compris
cd /etc             # aller dans /etc
cd ..               # remonter d'un niveau
cd ~                # revenir chez moi
mkdir -p a/b/c      # créer une arborescence
touch fichier.txt   # créer un fichier vide
cp fichier.txt copie.txt
cp -r dossier dossier2
mv fichier.txt /tmp/
rm fichier.txt      # supprimer un fichier
rm -r dossier       # supprimer un dossier (attention)
cat fichier.txt     # afficher tout
less fichier.txt    # afficher page par page (q pour quitter)
head -n 5 fichier   # 5 premières lignes
tail -n 5 fichier   # 5 dernières lignes
tail -f /var/log/syslog  # suivre un fichier en direct (Ctrl+C pour sortir)
wc -l fichier.txt   # compter les lignes
grep motif fichier  # chercher une ligne
grep -r motif .     # chercher récursivement
find . -name "*.txt"  # chercher par nom
file fichier.txt    # type d'un fichier
```

Attention : `rm` ne met rien à la corbeille. Sur une VM de test, ce n'est pas grave ; sur ta machine, réfléchis avant d'appuyer sur Entrée.

---

## 1.4 Les permissions

Quand tu tapes `ls -l`, tu obtiens des lignes comme :

```
-rw-r--r-- 1 mzouhir mzouhir 1234 nov. 18 16:00 app1.yaml
drwxr-xr-x 2 mzouhir mzouhir 4096 nov. 18 15:59 scripts
```

Décortiquons `-rw-r--r--` :

- 1er caractère : **type** → `-` = fichier, `d` = dossier, `l` = lien symbolique.
- Les 9 suivants sont **3 groupes de 3** :
  - `rw-` : droits du **propriétaire** (user)
  - `r--` : droits du **groupe** (group)
  - `r--` : droits des **autres** (others)

Chaque lettre vaut un chiffre :
- `r` (lire) = **4**
- `w` (écrire) = **2**
- `x` (exécuter / entrer dans un dossier) = **1**

On additionne : `rwx` = 7, `rw-` = 6, `r-x` = 5, `r--` = 4, `---` = 0.

Donc `-rw-r--r--` = **644** : le propriétaire peut lire et écrire, les autres seulement lire.
`drwxr-xr-x` = **755** : le propriétaire peut tout faire, les autres lire et entrer.

Commandes :

```bash
chmod 644 fichier.txt     # rw- r-- r--
chmod 755 script.sh       # rwx r-x r-x
chmod +x script.sh        # ajoute le droit d'exécution
chown user:group fichier  # change propriétaire et groupe (root ou sudo)
sudo commande             # exécute en tant qu'administrateur (root)
```

Pourquoi `chmod +x script.sh` est essentiel ? Parce qu'un script shell n'est « exécutable » que s'il possède le bit `x`, sinon `./script.sh` renvoie *Permission denied*.

**`sudo`** : exécuter une commande avec les droits de root. Le mot de passe demandé est **le tien** (si ton utilisateur est dans le groupe `sudo`). Sur les VM Vagrant, l'utilisateur `vagrant` a `sudo` sans mot de passe.

---

## 1.5 Processus et services

Un **processus** est un programme en cours d'exécution, identifié par un **PID** (numéro). Chaque processus (sauf le premier) a un **parent** (PPID).

```bash
ps aux              # tous les processus de la machine
ps -ef              # variante
top                 # moniteur en temps réel (q pour quitter)
htop                # version plus lisible si installée
pgrep sleep         # trouver le PID d'un programme par son nom
kill <PID>          # demander l'arrêt (signal SIGTERM = arrêt propre)
kill -9 <PID>       # tuer de force (SIGKILL, dernier recours)
```

Au premier plan / en arrière-plan :

```bash
sleep 300           # bloque le terminal 300 s
sleep 300 &         # lance en arrière-plan, affiche un numéro de job
jobs                # liste les jobs du terminal
fg                  # ramène au premier plan
Ctrl+C              # interrompt le processus au premier plan
Ctrl+Z              # suspend le processus au premier plan
```

### Les services avec systemd

Sur Linux moderne, les services (serveur SSH, Docker, K3s...) sont gérés par **systemd**. Un service est un processus qui tourne en permanence, supervisé par le système.

```bash
systemctl status ssh          # état du service (actif ? erreurs ?)
systemctl start ssh
systemctl stop ssh
systemctl restart ssh
systemctl enable ssh          # démarrage automatique au boot
systemctl list-units --type=service --state=running
journalctl -u ssh -n 50       # les 50 dernières lignes de log du service
journalctl -u ssh -f          # suivre les logs en direct
sudo systemctl daemon-reload  # après modification d'un fichier .service
```

C'est central pour le projet : **K3s s'installe comme les services `k3s` (serveur) et `k3s-agent` (worker)**. Le premier réflexe en cas de problème sera `systemctl status k3s` et `journalctl -u k3s`.

---

## 1.6 Le réseau

### IP et interfaces

Une machine a une ou plusieurs **interfaces réseau**. Chacune a une **adresse IP**, un **masque** et éventuellement une **passerelle**.

```bash
ip a                # toutes les interfaces et leurs IP
ip a show lo        # l'interface loopback (127.0.0.1)
ip route            # table de routage, ligne "default" = passerelle
hostname -I         # tes adresses IP (sans les détails)
ping -c 4 1.1.1.1   # test de connectivité (4 paquets)
```

Notions clés :
- **127.0.0.1 / localhost** : la machine elle-même (« loopback »).
- **Adresses privées** : `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. Elles ne sont pas routables sur Internet. `192.168.56.x` est le réseau classique du host-only VirtualBox utilisé par le projet.
- **CIDR** : `192.168.56.0/24` contient les adresses de `192.168.56.1` à `192.168.56.254`.
- **Port** : une porte logique sur une IP. Plusieurs services peuvent tourner sur la même machine, chacun sur son port.

Ports à connaître pour le projet :

| Port | Usage |
|---|---|
| 22 | SSH |
| 80 | HTTP |
| 443 | HTTPS |
| 53 | DNS |
| 6443 | API Kubernetes |
| 8080 | souvent une UI web / Argo CD en port-forward |
| 8888 | l'application de p3 |

### Tester un service réseau

```bash
ss -tlnp            # ports TCP en écoute (l = listen, t = tcp, n = numérique, p = programme)
ss -tulpn           # + UDP
curl -I https://example.com       # en-têtes HTTP seulement
curl -v https://example.com       # détaillé (très utile pour debug)
curl http://127.0.0.1:8080        # appeler un service local
```

Si `curl` échoue, lis le message : *Connection refused* (rien n'écoute sur ce port), *Could not resolve host* (DNS), *Connection timed out* (pare-feu ou mauvaise IP).

### DNS et `/etc/hosts`

Le **DNS** traduit un nom (`app1.com`) en IP. En local, on peut court-circuiter le DNS avec le fichier `/etc/hosts` :

```bash
cat /etc/hosts
```
```
127.0.0.1   localhost
192.168.56.110  app1.com
```

Résolution d'un nom :
```bash
getent hosts example.com
dig example.com +short      # si dig est installé
```

C'est exactement le mécanisme utilisé en p2 pour tester tes applications. Et si tu ne veux pas toucher à `/etc/hosts`, tu peux mentir au serveur en envoyant l'en-tête HTTP `Host` :

```bash
curl -H "Host: app1.com" http://192.168.56.110
```

C'est **la commande clé de la partie 2 du projet**. Retiens-la.

---

## 1.7 SSH et les clés

**SSH** (Secure Shell) sert à ouvrir un shell sur une machine distante, chiffré.

```bash
ssh user@192.168.56.110          # connexion
ssh user@192.168.56.110 -p 2222  # autre port
ssh -v user@hote                 # mode debug
exit                             # quitter
```

Deux modes d'authentification :
1. **Par mot de passe** : simple mais vulnérable au bruteforce.
2. **Par clé** : le serveur connaît ta **clé publique** ; toi seul possèdes la **clé privée**. Le serveur te lance un défi que seule ta clé privée peut résoudre. Aucun mot de passe ne circule.

Vocabulaire :
- `~/.ssh/id_ed25519` : ta clé **privée**. **Ne la partage JAMAIS**, ne la commit jamais.
- `~/.ssh/id_ed25519.pub` : ta clé **publique**, à déposer sur les serveurs.
- `~/.ssh/authorized_keys` (sur le serveur) : liste des clés publiques autorisées à se connecter.

```bash
ssh-keygen -t ed25519 -C "moi@iot"    # génère la paire (Entrée pour le chemin, passphrase optionnelle)
cat ~/.ssh/id_ed25519.pub             # afficher la clé publique
ssh-copy-id user@192.168.56.110       # installer la clé publique sur le serveur
ssh user@192.168.56.110               # ne doit plus demander de mot de passe
```

Un fichier `~/.ssh/config` permet de créer des alias :

```
Host serveur
    HostName 192.168.56.110
    User vagrant
    IdentityFile ~/.ssh/id_ed25519
```
Ainsi `ssh serveur` suffit.

Pour le projet p1, l'exigence « SSH sans mot de passe sur les deux machines » repose sur ce mécanisme (Vagrant le fait en partie pour toi, mais tu dois vérifier et savoir l'expliquer).

---

## 1.8 TP — À toi de jouer

> Aucune solution n'est donnée. Fais les TP dans l'ordre et note tes essais dans un journal.

### TP 1 — Créer une arborescence de projet

1. Crée un dossier de travail `iot-lab` dans ton dossier personnel, puis place-toi dedans.
2. Crée l'arborescence suivante : `projet/confs`, `projet/scripts`, `projet/logs`.
3. Dans `projet/confs`, crée trois fichiers vides : `app1.yaml`, `app2.yaml`, `app3.yaml`.
4. Dans `projet/scripts`, crée un fichier `install.sh`.
5. Affiche l'arborescence du dossier `projet`.
6. Affiche le contenu du dossier `logs` en détail.

### TP 2 — Redirections et pipes

1. Écris trois lignes dans `projet/logs/test.log` : `ligne un`, `ligne deux`, `ligne trois`.
2. Affiche le fichier et vérifie qu'il contient bien 3 lignes.
3. Affiche uniquement les lignes qui contiennent `deux`.
4. Compte le nombre de fichiers `.yaml` présents dans le projet.

### TP 3 — Chercher dans les fichiers

1. Cherche **récursivement** le mot `ligne` dans le dossier `projet`. Sur quoi tombes-tu ?
2. Sauvegarde la sortie de la commande précédente dans un fichier `projet/resultat.txt`.
3. Affiche le fichier `resultat.txt`.

---

### TP 4 — Permissions

1. Dans `~/iot-lab/projet/scripts`, crée un script `hello.sh`. Contenu fourni (c'est le « matériel » de l'exercice, pas une solution) :

   ```bash
   #!/bin/bash
   echo "Bonjour depuis le script"
   ```

   Le `#!/bin/bash` s'appelle le **shebang** : il indique quel interpréteur lancer.

2. Essaie de l'exécuter directement (`./hello.sh`). Que se passe-t-il ?
3. Observe ses permissions actuelles.
4. Rends-le exécutable, puis relance-le.
5. Donne-lui des droits tels que **seul le propriétaire** puisse lire et écrire (rien pour les autres). Affiche le résultat et explique ce que tu obtiens en notation chiffrée.
6. Remets-lui des droits normaux de script exécutable.

### TP 5 — Propriétaire **[VM]**

> Cette partie exige `sudo` : fais-la sur ta machine virtuelle. Si tu n'en as pas encore, saute-la et reviens-y plus tard, on la refera.

1. Affiche les détails du fichier `hello.sh` : qui est propriétaire ? quel groupe ?
2. Change le propriétaire **et** le groupe du fichier pour `root`.
3. Essaie maintenant d'écrire dedans **sans** droits administrateur. Que se passe-t-il, et pourquoi ?
4. Remets-toi propriétaire du fichier.

> Savoir lire `ls -l` est un réflexe de survie : c'est exactement ce qui explique un script qui « ne marche plus ».

---

### TP 6 — Processus

1. Lance un processus `sleep 300` **en arrière-plan**. Note le numéro de job et le PID affichés.
2. Vérifie qu'il tourne bien.
3. Retrouve son PID par son nom.
4. Termine-le proprement, puis vérifie qu'il a bien disparu.
5. Lance `sleep 300` au premier plan, puis fais `Ctrl+Z`. Que se passe-t-il ? Reprends-le, puis interromps-le définitivement.

### TP 7 — Services

> Si une commande est refusée faute de droits, note-le et on la refera sur la VM.

1. Trouve le nom exact du service SSH de ta machine (il peut s'appeler `ssh` ou `sshd`).
2. Affiche les 20 dernières lignes de log de ce service.
3. Liste les services en cours d'exécution.
4. Choisis un service au hasard dans la liste, affiche son statut et explique en une phrase ce qu'il fait (aide-toi du nom).

---

### TP 8 — Ton réseau

1. Affiche tes interfaces réseau. Repère : quelle interface a une IP privée ? laquelle est le loopback ?
2. Affiche ta route par défaut.
3. Teste Internet par adresse IP, puis par nom de domaine. Quelle différence observes-tu, et qu'est-ce que cela prouve sur le DNS ?
4. Affiche les ports en écoute sur ta machine. Y en a-t-il un sur le port 22 ? sur 80 ? sur 443 ?
5. Lance le serveur HTTP intégré à Python sur le port 8888, depuis `~/iot-lab`. Puis, dans un **second terminal**, vérifie avec `curl` que le serveur répond et que le port 8888 écoute bien. (Interromps le serveur ensuite.)
6. Toujours dans le second terminal, demande une URL qui n'existe pas sur ce serveur. Que renvoie-t-il ? Quel code HTTP ?

---

### TP 9 — Clés SSH

1. Regarde si tu as déjà des clés dans `~/.ssh/`. Lesquelles sont présentes ?
2. Si tu n'en as pas, génère une paire de type `ed25519` avec le commentaire `iot-lab` (passphrase vide pour ce TP).
3. Affiche ta clé **publique** et observe son format : par quoi commence-t-elle, par quoi finit-elle ?
4. Vérifie l'existence de ta clé privée **sans l'afficher**, et observe ses permissions. Que valent-elles ? Est-ce normal ?
5. Crée un fichier `~/.ssh/config` avec un alias `labo` pointant vers `192.168.56.110`, utilisateur `vagrant`, et ta clé privée. Puis vérifie que SSH lit bien ce fichier (indice : l'option `-G` de `ssh` affiche la configuration effective).

---

## 1.9 Questions de la leçon 1

> Corrigé complet. Chaque verdict : **OK** (juste), **Partiel** (idée bonne mais incomplet), **À revoir** (erreur).

### Partie A — Terminal et fichiers

**A1.** Quelle est la différence entre un chemin absolu et un chemin relatif ? Donne un exemple de chaque.

**Ta réponse :**
> un chemin absolu est un chemin qui part de la racine tandi que un chemin relatif par dun dossier
> absolu /etc/var
> absolu ./var

**Verdict : Partiel.**

**Correction :**
- **Absolu** : commence par `/`, donc valable depuis n'importe quel dossier. Exemple : `/etc/hosts`.
- **Relatif** : interprété à partir du dossier courant. Exemple : `projet/confs` ou `./var`.

Ta définition est bonne. L'erreur est dans les exemples : `./var` est **relatif**, pas absolu (le `./` désigne le dossier courant). Et `./var` désignerait un dossier `var` **dans** le dossier où tu es, pas `./var` comme chemin de la racine.

---

**A2.** Que fait exactement la commande `mkdir -p projet/confs` par rapport à `mkdir projet/confs` ? Quand la première est-elle indispensable ?

**Ta réponse :**
> il va creer les dossier intermediaire qui n existe pas

**Verdict : OK.**

**Correction :**
`mkdir projet/confs` échoue (`No such file or directory`) si `projet` n'existe pas. `mkdir -p projet/confs` crée **toute la chaîne** manquante et ne renvoie pas d'erreur si le dossier existe déjà (comportement **idempotent**). C'est indispensable dès qu'un parent peut manquer, ce qui est le cas dans tous tes scripts de provisioning.

---

**A3.** Écris **une** commande qui compte le nombre de fichiers `.yaml` dans `~/iot-lab/projet/confs`.

**Ta réponse :**
> find ~/iot-lab/projet/confs -name "*.yaml" | wc - l

**Verdict : Partiel.**

**Correction :**
La logique est la bonne, mais `wc - l` est invalide : l'option doit être collée → `wc -l`. Chez toi le chemin réel est `~/Documents/iot-lab` :

```bash
find ~/Documents/iot-lab/projet/confs -name "*.yaml" | wc -l
```

Autres formes valables : `ls ~/Documents/iot-lab/projet/confs/*.yaml | wc -l`.

---

**A4.** Quelle est la différence entre `>` et `>>` ? Que se passe-t-il si tu utilises `>` sur un fichier qui contient déjà 10 lignes ?

**Ta réponse :**
> > va venir ecraser le fichier avec la nouvelle entree
> >> va venir mettre a la fin (append) la nouvelle entree.

**Verdict : OK.**

Le fichier de 10 lignes est **vidé** puis remplacé par la nouvelle sortie. `>>` conserve les 10 lignes et ajoute à la suite.

---

**A5.** Tu tapes `ls -la` dans `/etc`. Explique la différence entre le `.` et le `..` que tu vois dans la liste.

**Ta réponse :**
> . est le dossier parent.
> .. est le dossier parent du dossier parent

**Verdict : À revoir (inversé).**

**Correction :**
- `.` = le **dossier courant** (ici `/etc`).
- `..` = le **dossier parent** (ici `/`).

Moyen mnémotechnique : plus il y a de points, plus on remonte.

---

### Partie B — Permissions

**B1.** Traduis en notation chiffrée : `rwxr-xr-x`, `rw-r-----`, `rwx------`.

**Ta réponse :**
> 755 640 700

**Verdict : OK.**

**B2.** Que vaut `chmod 644 fichier` en lettres ? Qui peut écrire dedans ?

**Ta réponse :**
> rw-r--r--  seul le proprietaire du fichier peut ecrire dedans

**Verdict : OK.**

**B3.** Un script `deploy.sh` existe mais `./deploy.sh` renvoie *Permission denied*. Quelle commande corrige le problème, et pourquoi ?

**Ta réponse :**
> chmod +x deploy.sh car il donne le droit d execution du fichier en question

**Verdict : OK.**

**B4.** Quelle est la différence entre `chmod` et `chown` ?

**Ta réponse :**
> chmod permet de changer les droit sur le fichier. chown permet de changer le proprietaire/groupe du fichier

**Verdict : OK.**

**B5.** Tu vois `-rw-r--r-- 1 root root ... config.yaml` et tu n'arrives pas à le modifier sans `sudo`. Explique précisément pourquoi, en lisant les droits.

**Ta réponse :**
> le proprietaire est le seul qui a le droit d ecriture dessus et le proprietaire est root. on doit donc etre sudo pour pouvoir le modifier

**Verdict : OK.**

Le groupe (`root`) et les autres n'ont que `r--`, donc aucune écriture. Seul root (propriétaire, `rw-`) peut modifier, d'où `sudo`.

---

### Partie C — Processus et services

**C1.** Qu'est-ce qu'un PID ? Qu'est-ce qu'un PPID ?

**Ta réponse :**
> un PID est un processus.

**Verdict : À revoir.**

**Correction :**
- **PID** (*Process IDentifier*) : le **numéro unique** qui identifie un processus en cours d'exécution. Ce n'est pas le processus lui-même, c'est son identifiant.
- **PPID** (*Parent PID*) : le PID du processus **père** qui l'a lancé. Tu peux les voir avec `ps -ef` (colonnes `PID` et `PPID`).

---

**C2.** Quelle est la différence entre `kill <PID>` et `kill -9 <PID>` ? Pourquoi éviter `-9` par défaut ?

**Ta réponse :**
> kill PID permet de stoper proprement un programme tandis que kill -9 pid le tue avec un sigkill ce qui est a proscrire

**Verdict : OK.**

Précision : `kill <PID>` envoie **SIGTERM (15)**, que le programme peut intercepter pour nettoyer (fermer des fichiers, etc.). `kill -9` envoie **SIGKILL**, non interceptable : le programme ne peut rien faire, d'où le risque de corruption. À garder pour un processus bloqué.

---

**C3.** Tu as lancé `sleep 300` et ton terminal est bloqué. Cite **deux** façons de t'en sortir, et explique ce que fait chacune.

**Ta réponse :**
> ctrl + c envoi un sig kill
> ctrl + z envoi un sig int

**Verdict : À revoir (les deux signaux sont faux).**

**Correction :**
- `Ctrl+C` envoie **SIGINT (2)** : **interrompt** le processus. Ce n'est pas SIGKILL.
- `Ctrl+Z` envoie **SIGTSTP (20)** : **suspend** le processus, il ne meurt pas. Il apparaît en `Stopped` dans `jobs`, puis tu le reprends avec `fg` (avant-plan) ou `bg` (arrière-plan), ou tu le tues avec `kill %1`.

Deux façons correctes de « s'en sortir » :
1. `Ctrl+C` → le processus est interrompu.
2. `Ctrl+Z` puis `kill %1` → il est suspendu, puis tu le termines.

---

**C4.** Écris la commande qui affiche les 30 dernières lignes de log du service `k3s`. Puis la commande qui suit ces logs en direct.

**Ta réponse :**
> journalctl -u k3s -n 30
> journalctl -u k3s -f

**Verdict : OK.**

**C5.** Un service ne démarre pas au boot de la machine alors qu'il démarre très bien à la main. Quelle commande `systemctl` as-tu probablement oubliée ?

**Ta réponse :**
> systemctl enable

**Verdict : OK.**

`systemctl enable` crée le lien de démarrage automatique. Forme courante : `sudo systemctl enable --now k3s` (active + démarre tout de suite).

---

### Partie D — Réseau

**D1.** Quelle est la différence entre `127.0.0.1` et l'IP `192.168.56.110` ?

**Ta réponse :**
> le premier est l adresse localhost et le second est mon adresse ip de la machine sur mon reseau privee

**Verdict : OK.**

**D2.** Que signifie `/24` dans `192.168.56.0/24` ? Donne la première et la dernière adresse utilisable.

**Ta réponse :**
> il s agit d un masque CDIR . 192.168.56.1 192.168.56.244

**Verdict : Partiel.**

**Correction :**
`/24` = **24 bits** pour la partie réseau, donc 8 bits pour les hôtes → 2^8 − 2 = **254 adresses utilisables**.
- réseau : `192.168.56.0`
- première utilisable : `192.168.56.1`
- dernière utilisable : **`192.168.56.254`** (pas `.244`)
- broadcast : `192.168.56.255`

---

**D3.** Quel port utilise : SSH ? HTTP ? HTTPS ? l'API Kubernetes ?

**Ta réponse :**
> ssh : 22 http : 80 https 443 kubernetes 6443

**Verdict : OK.**

**D4.** Écris la commande qui liste les ports TCP en écoute avec le nom du programme qui les occupe.

**Ta réponse :**
> ss -tnlp

**Verdict : OK.** (`ss -tlnp` est la même chose, l'ordre des options est libre.)

**D5.** Tu lances `curl http://127.0.0.1:9999` et tu obtiens `Connection refused`. Qu'est-ce que cela t'apprend, et que vérifies-tu en premier ?

**Ta réponse :**
> je verifie sur le port 9999 est bien ouvert et utiliser par une application

**Verdict : OK.**

Précision : `Connection refused` = le noyau a répondu **RST** : soit rien n'écoute sur ce port, soit un pare-feu refuse explicitement. Premier réflexe : `ss -tlnp | grep 9999`.

---

**D6.** Explique avec tes mots ce que fait `curl -H "Host: app1.com" http://192.168.56.110`. Pourquoi est-ce utile dans ce projet ?

**Ta réponse :**
> il envoi a l adresse IP en question une demande avec en entete app1.com a la place de host pour avoir a eviter de toucher a /etc/hosts

**Verdict : OK.** Très bonne réponse.

---

**D7.** Tu obtiens `Could not resolve host: app1.com`. Quel est le problème, et comment le corriger temporairement sur ta machine ?

**Ta réponse :**
> modifier /etc/host afin de cours circuiter le DNS

**Verdict : OK.**

Le fichier s'appelle `/etc/hosts` (avec un **s**). Il faut y ajouter une ligne `192.168.56.110 app1.com`, ce qui nécessite `sudo` (donc à faire dans la VM).

---

### Partie E — SSH

**E1.** Quelle est la différence entre `id_ed25519` et `id_ed25519.pub` ? Laquelle peut être partagée sans risque ?

**Ta réponse :**
> .pub est la cle public. je peux la partager tandis que l autre est la cle privee. elle ne dois surtout pas etre partage

**Verdict : OK.**

**E2.** Sur le serveur, dans quel fichier sont stockées les clés publiques autorisées ?

**Ta réponse :**
> autorized_key

**Verdict : Partiel (orthographe).**

**Correction :** `~/.ssh/authorized_keys` — *authorized* avec un **h**, et *keys* au pluriel. Le chemin exact compte : une faute de frappe et le serveur ignore la clé.

**E3.** Écris les deux commandes : (1) générer une paire de clés ed25519 avec le commentaire `iot`, (2) installer la clé publique sur `vagrant@192.168.56.110`.

**Ta réponse :**
> ssh-keygen -t ed25519 -C "iot"
> ssh-copy-id vagrant@192.168.56.110

**Verdict : OK.**

**E4.** Pourquoi les permissions de `~/.ssh/id_ed25519` doivent-elles être `600` et pas `644` ?

**Ta réponse :**
> personne a part la personne a qui elle appartient ne doit pouvoir la consulter

**Verdict : OK.**

SSH refuse même de l'utiliser si d'autres personnes peuvent la lire.

---

### Partie F — Diagnostic (le plus important)

**F1.** La VM `192.168.56.110` ne répond pas au ping.

**Ta réponse :**
> ip a
> je verifie que mon reseau est bien UP

**Verdict : Partiel.**

**Correction (ordre complet) :**
1. La VM est-elle **allumée** ? (`VBoxManage list runningvms`)
2. **Sur l'hôte** : `ip a` → `vboxnet0` est-il UP avec `192.168.56.1/24` ? `VBoxManage showvminfo <vm> | grep -i nic` → une carte host-only existe-t-elle ?
3. **Dans la VM** (console) : `ip a` → la VM a-t-elle bien `192.168.56.110` sur la bonne interface ?
4. Puis `ping`, et enfin `ssh -v` pour voir où ça bloque.

Ton réflexe est bon, mais il ne regarde que l'hôte : la moitié des pannes est côté VM (mauvaise IP, mauvaise interface, carte absente).

---

**F2.** `ssh vagrant@192.168.56.110` demande un mot de passe alors qu'il ne devrait pas.

**Ta réponse :**
> ssh -G vagrant. je verifie que le systeme est bien configurer avec une cle ssh
> ou alors j ouvre .ssh/config pour verifier que vagrant est bien renseigner

**Verdict : Partiel.**

**Correction :**
`ssh -G` affiche la config **du client** (quel utilisateur, quelle clé, quel port), c'est utile mais ce n'est pas là que se joue l'échec d'authentification par clé. Le vrai test est `ssh -v` : il montre la clé proposée et la réponse du serveur.

À vérifier ensuite :
1. la clé publique est-elle dans `~/.ssh/authorized_keys` **du serveur** ?
2. permissions : `~/.ssh` = `700`, `authorized_keys` = `600`, clé privée = `600` (sinon sshd refuse) ;
3. côté serveur, `PasswordAuthentication` n'empêche pas la clé : c'est `PubkeyAuthentication` qui doit être `yes` ;
4. l'utilisateur existe-t-il bien sur le serveur ?

---

**F3.** Un serveur web devrait tourner sur le port 80, mais `curl http://127.0.0.1` échoue.

**Ta réponse :**
> ss -tlnp et je m assure que le port 80 est bien ouvert

**Verdict : OK.**

Compléments : `curl -v` pour le message exact, `systemctl status` du service, et vérifier le pare-feu.

---

**F4.** Un script `install.sh` s'exécute mais « rien ne se passe ».

**Ta réponse :**
> je verifie si les droit sont correct. j ouvre le script et m assure quil y a quelque chose dedans. cat install.sh

**Verdict : Partiel.**

**Correction :** le meilleur outil est la **trace** :
```bash
bash -x install.sh
```
Elle affiche chaque commande exécutée et son résultat. Vérifie aussi : le shebang, les redirections (`>/dev/null 2>&1` qui masquent tout), et le code de retour (`echo $?`). Ajouter `set -e` en tête du script évite qu'il continue silencieusement après une erreur.

---

### Partie G — Défi de synthèse (manipulation)

**G6.** En une ou deux phrases, explique pourquoi ce mini-serveur **n'est pas** encore « le projet ».

**Ta réponse :**
> ce n est pas un serveur car il n a pas de configuration reelle. on ne pas pas indiquer differente route. il n y a pas de reverse proxy

**Verdict : OK.** Exactement : il manque un **reverse proxy** (Traefik) qui lit des règles de routage HTTP (`Host`/chemin) et choisit l'application, plus l'orchestration de plusieurs applications. C'est précisément le rôle de l'Ingress en p2.

---

## Corrigé des TP

### TP 1 — Arborescence
Attendu : `~/Documents/iot-lab/projet/{confs,scripts,logs}`, trois `.yaml` vides, `install.sh` vide. **Validé.**

### TP 2 — Redirections et pipes
- `test.log` contient 3 lignes. **Validé.**
- Compter les `.yaml` : `find ~/Documents/iot-lab/projet -name "*.yaml" | wc -l` → **3**.
- Rappel : `>` écrase, `>>` ajoute, `|` enchaîne.

### TP 3 — Recherche
`grep -r "ligne" projet` renvoie trois lignes, du type `projet/logs/test.log:ligne un`. Redirigées dans `resultat.txt`. **Validé.** Les chemins sont relatifs parce que la commande a été lancée depuis `iot-lab` : c'est normal.

### TP 4 — Permissions
- Avant `chmod +x` : `-rw-r--r--` (644) → `./hello.sh` renvoie `Permission denied`.
- Après : `-rwxr-xr-x` (755) → le script s'exécute.
- Étape 5 : `600` = `-rw-------` → **lecture et écriture pour le propriétaire uniquement**, rien pour le groupe ni les autres.
- Étape 6 : retour à `755`.

### TP 5 — Propriétaire [VM]
- `chown root:root hello.sh` → propriétaire `root`, groupe `root`.
- Un `echo ... >> hello.sh` en tant que `mzouhir` échoue : tu n'es ni propriétaire ni dans le groupe autorisé en écriture (`rw-r--r--`).
- Retour : `sudo chown $USER:$USER hello.sh`.

### TP 6 — Processus
- `sleep 300 &` affiche un numéro de job et un PID ; `jobs` le liste ; `pgrep -a sleep` le retrouve.
- `kill <PID>` l'arrête proprement ; `pgrep sleep` ne renvoie plus rien.
- `Ctrl+Z` suspend (`Stopped`), `fg` reprend, puis `Ctrl+C` interrompt.

### TP 7 — Services
- Le service s'appelle `ssh` (Debian/Ubuntu) ou `sshd` (RHEL/Fedora).
- Logs : `journalctl -u ssh -n 20` (souvent `sudo` nécessaire).
- `systemctl list-units --type=service --state=running` liste les services actifs.

### TP 8 — Réseau
1. `lo` = loopback (`127.0.0.1`) ; `enp0s3` = IP privée `10.0.2.15/24` (carte **NAT**) ; `docker0` = `172.17.0.1/16` (pont Docker, aussi privé). Ta réponse ne citait que le loopback : il fallait nommer `enp0s3` comme interface privée.
2. Route par défaut : `default via 10.0.2.2 dev enp0s3` (passerelle NAT de VirtualBox). **Validé.**
3. DNS : `ping 1.1.1.1` (aucun DNS) vs `ping example.com` (DNS requis). Ta réponse est juste sur le fond : le nom est traduit par un DNS avant la connexion.
4. Ports : **22 oui**, **80 non**, **443 non** — et **631** (CUPS) écoute aussi, ce que tu avais omis. Ta phrase « uniquement le port 22 » était donc fausse.
5. `curl -I http://127.0.0.1:8888` → `HTTP/1.0 200 OK` (serveur `SimpleHTTP/0.6 Python`). **Validé.**
6. **Ta question « je ne devrais pas avoir plutôt une erreur 404 ? »** — non, et c'est une distinction essentielle :
   - tu as testé un **domaine inexistant** (`ksjdbfksdjbf.com`) → le nom n'est pas résolu, donc **aucune requête HTTP n'est envoyée** : c'est une erreur DNS (`Could not resolve host`).
   - une **404** signifie : le serveur a bien été joint, mais la **ressource demandée** n'existe pas. Pour l'obtenir : `curl -I http://127.0.0.1:8888/nimportequoi` (serveur existant + chemin inexistant).
   - Autres codes à connaître : `200` OK, `301/302` redirection, `403` interdit, `404` introuvable, `500` erreur serveur.

### TP 9 — Clés SSH
1. Aucune clé dans `~/.ssh` de la VM au départ. **Validé.**
2. `ssh-keygen -t ed25519 -C "iot-lab"` (ta clé porte le commentaire `test@iot` : le commentaire est libre, ce n'est pas grave).
3. La clé publique commence par `ssh-ed25519` et finit par le commentaire. **Validé.**
4. Clé privée en `600` = `-rw-------` : seul le propriétaire peut la lire et l'écrire. **Validé.**
5. `ssh -G labo` affiche la configuration effective (hostname, user, identityfile). **Validé.**

---

## Bilan de la leçon 1

| Partie | Résultat | Points à retravailler |
|---|---|---|
| A — Fichiers | 2 OK, 2 partiels, 1 faux | chemins relatifs, `.` vs `..`, syntaxe `wc -l` |
| B — Permissions | 5/5 | rien, excellent |
| C — Processus | 3 OK, 2 faux | PID/PPID, signaux `Ctrl+C` / `Ctrl+Z` |
| D — Réseau | 6 OK, 1 partiel | dernière adresse d'un `/24` |
| E — SSH | 3 OK, 1 partiel | orthographe `authorized_keys` |
| F — Diagnostic | 1 OK, 3 partiels | méthode complète (hôte **et** VM), `ssh -v`, `bash -x` |
| G — Synthèse | OK | bonne intuition du reverse proxy |

### À retenir absolument avant la leçon 2

1. `.` = dossier courant, `..` = dossier parent.
2. PID = identifiant d'un processus ; PPID = identifiant de son père.
3. `Ctrl+C` = SIGINT (interrompt) ; `Ctrl+Z` = SIGTSTP (suspend, puis `fg`/`bg`/`kill`).
4. `192.168.56.0/24` → `.1` à `.254`, broadcast `.255`.
5. Diag réseau = toujours **deux côtés** : l'hôte et la VM.
6. Pour un script muet : `bash -x script.sh`.
7. DNS cassé ≠ 404 : sans résolution, aucune requête HTTP n'existe.

---

Quand tu as relu ce corrigé : envoie-moi **« Leçon 2 »**. Je créerai `lecon-02-vagrant.md` (virtualisation, Vagrantfile, provisioning, réseau host-only, SSH sans mot de passe) — c'est-à-dire le début concret de la partie 1 du projet.
