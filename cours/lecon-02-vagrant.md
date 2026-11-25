# LEÇON 2 — Virtualisation et Vagrant

> Suite de `lecon-01-fondations.md`. Prérequis : savoir te déplacer dans un shell, lire `ls -l`, utiliser `ssh`, comprendre ce qu'est une IP et un port.
> Objectif : à la fin, tu sais écrire un `Vagrantfile`, créer/détruire des VM par commande, les provisionner automatiquement, les mettre en réseau et te connecter en SSH sans mot de passe. C'est **exactement** le socle de la partie 1 du projet.

---

## Où lancer Vagrant ? (important)

Une confusion classique : **Vagrant ne tourne pas « dans » une VM, il tourne sur la machine qui possède l'hyperviseur** — ici ton poste, qui a VirtualBox. C'est lui qui **crée** les VM. Les VM sont le *résultat*, pas l'endroit où on lance Vagrant.

J'ai vérifié ton environnement (je te donne l'état réel, tu n'as rien à installer) :

| Élément | État |
|---|---|
| Vagrant | **2.4.9 déjà installé** (`/usr/bin/vagrant`) |
| VirtualBox | **7.2.22** |
| Ton utilisateur | membre du groupe **`vboxusers`** → VirtualBox utilisable sans root |
| `sudo` sur le poste | absent, mais **inutile ici** |
| Dossier des VM VirtualBox | `/goinfre/mzouhir/vbox` (déjà configuré) |
| Espace `/home` | **2,4 Go libres seulement** (attention) |
| Espace `/goinfre` | **31 Go libres** |

Conclusion : **on travaille sur ton poste**. Le seul réglage à faire est de rediriger le stockage global de Vagrant vers `/goinfre`, sinon les « boxes » rempliront ton `/home` de 4,7 Go.

Faire tourner VirtualBox **dans** ta VM `general_VM` serait de la **virtualisation imbriquée** (VM dans VM) : plus lent, instable, et sans intérêt pour ce projet. On l'évite.

---

## 2.1 Le problème que Vagrant résout

Créer une VM à la main dans l'interface VirtualBox, c'est : choisir un ISO, installer l'OS, créer un utilisateur, configurer le réseau, installer des paquets, recommencer pour la 2e VM… Et si tu casses tout, tu recommences **à la main**. Ce n'est ni reproductible, ni versionnable, ni partageable.

**Vagrant** est un **orchestrateur de machines virtuelles** : tu décris ton infrastructure dans un fichier texte (`Vagrantfile`), et une commande crée, configure et démarre les VM. C'est de l'**Infrastructure as Code (IaC)** : ton infra est du code, versionné dans Git, reproductible à l'identique.

Le triptyque :

```
Vagrant  ──pilote──>  Provider (VirtualBox)  ──crée──>  VM
   │
   └── lit un Vagrantfile (description déclarative)
```

- **Vagrant** : le chef d'orchestre (installation, réseau, SSH, provisioning).
- **Provider** : le moteur de virtualisation (VirtualBox, libvirt/KVM, VMware, Hyper-V…). Vagrant ne virtualise rien lui-même.
- **Box** : une **image de VM préinstallée** (OS + utilisateur `vagrant` + SSH + Guest Additions). C'est le « moule » à partir duquel on crée les VM.

Analogie : la **box** est un modèle de gâteau, le **provider** est le four, et le **Vagrantfile** est la recette.

---

## 2.2 Vocabulaire (à connaître par cœur)

| Terme | Définition |
|---|---|
| **Box** | Image de VM prête à l'emploi (ex. `bento/ubuntu-22.04`), téléchargée depuis Vagrant Cloud |
| **Provider** | Moteur de virtualisation (`virtualbox` ici) |
| **Vagrantfile** | Fichier de description de l'infra (Ruby DSL), à la racine du projet |
| **Machine** | Une VM définie dans le Vagrantfile (`config.vm.define`) |
| **Hôte / guest** | `host` = ton poste ; `guest` = la VM |
| **Provisioning** | Scripts/commandes exécutés automatiquement *dans* la VM au premier démarrage (ou à la demande) |
| **Dossier synchronisé** | Dossier de l'hôte monté dans la VM (par défaut : le projet sur `/vagrant`) |
| **`.vagrant/`** | Dossier d'état créé à côté du Vagrantfile (IDs de VM, clé SSH générée). **Jamais commité.** |
| **`VAGRANT_HOME`** | Dossier global de Vagrant (`~/.vagrant.d` par défaut) : boxes, clé « insecure » |
| **Idempotent** | Qu'on peut rejouer sans effet de bord : `vagrant up` sur une VM déjà créée la démarre, il ne la recrée pas |

---

## 2.3 Installer / vérifier (déjà fait chez toi)

Rappel des commandes de vérification (utiles en soutenance et sur une autre machine) :

```bash
vagrant --version
VBoxManage --version
id | tr ',' '\n' | grep vboxusers
```

Sur une machine où Vagrant manquerait **et sans sudo**, on peut extraire le paquet `.deb` dans son dossier personnel :

```bash
mkdir -p ~/tools/vagrant && cd /tmp
curl -LO https://releases.hashicorp.com/vagrant/2.4.9/vagrant_2.4.9_linux_amd64.deb
dpkg-deb -x vagrant_2.4.9_linux_amd64.deb ~/tools/vagrant
export PATH="$HOME/tools/vagrant/usr/bin:$PATH"
```

Ici, **ne le fais pas** : Vagrant est déjà installé.

### Le réglage indispensable : `VAGRANT_HOME`

Par défaut, les boxes vont dans `~/.vagrant.d` → ton `/home` de 4,7 Go. On les envoie sur `/goinfre` :

```bash
export VAGRANT_HOME=/goinfre/mzouhir/.vagrant.d
```

Ajoute cette ligne à `~/.bashrc` pour qu'elle survive aux nouvelles sessions, puis vérifie :

```bash
echo $VAGRANT_HOME
```

> Note 42 : `/goinfre` est un espace local Scratch, **non sauvegardé** à long terme. C'est parfait pour des boxes (re-téléchargeables). Ton dépôt Git, lui, reste dans `/home`.

### Alternative : ton espace persistant `~/sgoinfre`

Sur cette machine, `~/sgoinfre` est un **lien symbolique** vers `/sgoinfre/goinfre/Perso/<login>`, qui t'appartient et qui est **persistant** (contrairement à `/goinfre`). C'est un montage **NFS** (réseau, Kerberos), donc plus lent que le disque local : environ **100 Mo/s** contre **~580 Mo/s** sur `/goinfre` (mesuré). Pour une box de ~700 Mo, cela reste acceptable.

```bash
mkdir -p ~/sgoinfre/vagrant_home
export VAGRANT_HOME=~/sgoinfre/vagrant_home
```

Avantages : tes boxes survivent aux nettoyages de `/goinfre`. Inconvénients : dépendance au réseau et au ticket Kerberos, extraction plus lente. Dans les deux cas, **les disques des VM restent sur `/goinfre`** (dossier par défaut de VirtualBox) : ne les mets jamais sur NFS, les performances d'exécution s'effondreraient.

---

## 2.4 Anatomie d'un Vagrantfile

Un Vagrantfile est du **Ruby**, mais tu n'écris pas de Ruby : tu utilises une **DSL** (un mini-langage de configuration). Règles :

- `Vagrant.configure("2")` : le `"2"` est la **version du format de configuration**, pas la version de Vagrant.
- `do |config| ... end` : un bloc ; `config` est l'objet à configurer.
- `#` commence un commentaire.
- Chaque directive est un appel de méthode : `config.vm.box = "..."`.

### Squelette commenté (exemple de cours — valeurs différentes de tes TP)

```ruby
Vagrant.configure("2") do |config|

  # Réglage commun : la box utilisée par toutes les machines
  config.vm.box = "bento/ubuntu-22.04"

  # Définition d'une machine nommée "demo"
  config.vm.define "demo" do |demo|
    demo.vm.hostname = "demo"                                  # hostname DANS la VM

    demo.vm.network "private_network", ip: "192.168.50.10"     # réseau host-only
    demo.vm.network "forwarded_port", guest: 8000, host: 8081  # NAT : hôte:8081 -> VM:8000

    demo.vm.provider "virtualbox" do |vb|
      vb.memory = 1024                 # Mo de RAM
      vb.cpus   = 1                    # vCPU
      vb.name   = "demo-vm"            # nom affiché dans VirtualBox
    end

    demo.vm.provision "shell", inline: <<-SHELL
      echo "provisionnement de $(hostname)"
    SHELL
  end
end
```

Décryptage :

| Ligne | Rôle |
|---|---|
| `config.vm.box` | Box de base (doit être téléchargée ou le sera au premier `up`) |
| `config.vm.define "demo"` | Déclare une machine ; sans ça, Vagrant crée une machine unique nommée `default` |
| `vm.hostname` | Nom d'hôte **interne** (visible avec `hostname`) |
| `vm.network "private_network", ip:` | Ajoute une carte **host-only** avec une IP fixe |
| `vm.network "forwarded_port", guest:, host:` | Redirection de port **NAT** |
| `vm.provider "virtualbox"` | Réglages spécifiques au provider |
| `vb.memory` / `vb.cpus` | Ressources allouées |
| `vb.name` | Nom de la VM dans l'interface VirtualBox (≠ hostname) |
| `vm.provision "shell", inline:` | Script shell exécuté dans la VM au provisioning |
| `<<-SHELL ... SHELL` | **Heredoc** Ruby : texte multi-lignes, indentable |

### `inline` vs `path`

```ruby
# Script court, directement dans le Vagrantfile
config.vm.provision "shell", inline: "apt-get update -y"

# Script externe (recommandé pour tout ce qui est long)
config.vm.provision "shell", path: "scripts/install.sh"

# Avec arguments et variables d'environnement
config.vm.provision "shell", path: "scripts/setup.sh",
                    args: ["serveur", "192.168.56.110"],
                    env: { "ROLE" => "server" }
```

Le sujet impose une arborescence `scripts/` et `confs/` : tu utiliseras surtout `path:`.

### Plusieurs machines

```ruby
config.vm.define "alpha" do |m|
  # config de alpha
end

config.vm.define "beta" do |m|
  # config de beta
end
```

L'**ordre de déclaration** est l'ordre de démarrage : mets le serveur avant le worker.

---

## 2.5 Le cycle de vie : les commandes

### Projet

```bash
vagrant init <box>        # crée un Vagrantfile minimal dans le dossier courant
vagrant validate          # vérifie la syntaxe du Vagrantfile
vagrant status            # état de chaque machine
vagrant global-status     # toutes les VM Vagrant de la machine (tous projets)
```

### Machines

```bash
vagrant up                # crée (si besoin) + démarre + provisionne
vagrant up alpha          # une seule machine
vagrant ssh               # shell dans la machine (par défaut)
vagrant ssh alpha         # shell dans alpha
vagrant ssh -c "hostname" # exécute une commande et sort
vagrant ssh-config        # affiche user/port/clé utilisés pour se connecter
vagrant halt              # arrêt propre
vagrant suspend           # sauvegarde l'état en mémoire
vagrant resume            # reprend après suspend
vagrant reload            # redémarre (halt + up)
vagrant reload --provision  # redémarre ET rejoue le provisioning
vagrant provision         # rejoue le provisioning sans redémarrer
vagrant destroy           # détruit la VM (confirmation demandée)
vagrant destroy -f        # sans confirmation
```

### Boxes

```bash
vagrant box list
vagrant box add <box>              # télécharge une box
vagrant box add --provider virtualbox <box>
vagrant box outdated               # des mises à jour existent-elles ?
vagrant box update
vagrant box remove <box>
```

### Points de cycle de vie à ne pas confondre

| Commande | Redémarre ? | Rejoue le provisioning ? | Recrée la VM ? |
|---|---|---|---|
| `vagrant up` (VM existante) | oui (démarre) | **non** | non |
| `vagrant reload` | oui | **non** | non |
| `vagrant reload --provision` | oui | **oui** | non |
| `vagrant provision` | non | **oui** | non |
| `vagrant destroy` | — | — | supprime |
| `vagrant up` (après destroy) | oui | oui | **oui** |

C'est **le** piège du débutant : modifier un script de provisioning puis faire `vagrant up` ne l'exécute pas. Il faut `--provision`.

### Snapshots (sauvegarde d'état)

Un **snapshot** est une photographie de l'état d'une VM à un instant T : disque, et aussi mémoire/état d'exécution si la VM tourne. On peut y revenir plus tard. C'est l'outil idéal pour **expérimenter sans risque**.

```bash
vagrant snapshot save <nom>              # prend un snapshot (toutes les machines ou la VM courante)
vagrant snapshot save first <nom>        # snapshot d'une seule machine (multi-machine)
vagrant snapshot list                    # liste les snapshots
vagrant snapshot restore <nom>           # revient à cet état
vagrant snapshot delete <nom>            # supprime le snapshot
vagrant snapshot push                    # snapshot anonyme empilé (avant une manip)
vagrant snapshot pop                     # restaure ET supprime le dernier snapshot empilé
```

`push`/`pop` est très pratique : `push` avant une expérience, `pop` pour tout annuler.

Points importants :

1. Un snapshot **restaure tout** l'état capturé, y compris le contenu de `/tmp` et les fichiers créés **avant** le snapshot. Les fichiers créés **après** disparaissent au `restore`.
2. `snapshot restore` n'est pas `halt` : on revient à l'état sauvegardé (si la VM tournait, elle reprend dans cet état).
3. Sous VirtualBox, un snapshot crée un **disque différentiel** : il prend de la place au fil des modifications. Nettoie les snapshots inutiles.
4. Un snapshot **n'est pas une sauvegarde** : il vit avec le disque de la VM (dans `/goinfre`). `vagrant destroy` ou un changement de poste le supprime avec la VM.
5. En multi-machine, sans nom de VM, la commande s'applique à **toutes** les machines de l'environnement (même nom de snapshot).

---

## 2.6 Le réseau dans Vagrant

VirtualBox propose trois modes principaux. Vagrant les expose ainsi :

### 1. NAT (par défaut)

La VM sort vers Internet via l'hôte, mais **l'hôte ne peut pas l'atteindre directement**. Vagrant ajoute automatiquement une **redirection SSH** : `hôte:2222 -> VM:22` (puis 2200, 2201… pour les machines suivantes). D'où le fait que `vagrant ssh` fonctionne sans rien configurer.

```ruby
config.vm.network "forwarded_port", guest: 80, host: 8080
```
→ `http://127.0.0.1:8080` sur l'hôte atteint le port 80 de la VM.

### 2. Réseau privé (host-only)

Crée un réseau virtuel **entre l'hôte et les VM**, sans passer par Internet. C'est **ce que demande le sujet** :

```ruby
config.vm.network "private_network", ip: "192.168.56.110"
```

Sur VirtualBox, cela s'appuie sur une interface **host-only** de l'hôte (`vboxnet0`, `192.168.56.1/24`). Résultat : l'hôte peut joindre `192.168.56.110`, et les VM peuvent se joindre entre elles **si elles sont sur le même réseau host-only**.

### 3. Réseau public (bridged)

La VM est branchée sur le réseau physique, comme une machine de plus (elle obtient une IP du routeur). Rarement utilisé ici, et risqué sur un réseau d'école.

### Le SSH de Vagrant

Vagrant crée l'utilisateur `vagrant` (mot de passe `vagrant`) avec `sudo` **sans mot de passe**, et gère les clés SSH à ta place :

- Par défaut (`config.ssh.insert_key = true`), il **remplace** la clé « insecure » par une clé **générée par machine**, stockée dans `.vagrant/machines/<nom>/virtualbox/private_key`.
- `vagrant ssh-config` te montre l'utilisateur, le port et le fichier de clé réellement utilisés.
- Tu peux donc te connecter **sans passer par Vagrant** :
  ```bash
  ssh -i .vagrant/machines/<nom>/virtualbox/private_key -p <port> vagrant@127.0.0.1
  ```
  et, si la VM a une IP host-only, `ssh -i <clé> vagrant@192.168.56.110` (le port est alors 22).

C'est important pour p1 : « SSH sans mot de passe » se prouve en montrant une connexion par clé qui ne demande rien.

---

## 2.7 Le provisioning

Le provisioning, c'est **l'installation automatique** de ce dont la VM a besoin : paquets, fichiers de config, services. Il s'exécute **dans la VM**, en général en root (Vagrant utilise `sudo`).

Bonnes pratiques :

1. **Idempotence** : un script doit pouvoir être rejoué sans casser. Exemple : `mkdir -p`, `apt-get install -y` (déjà installé = ne fait rien), tester avant d'écrire.
2. **Un script par rôle** : `scripts/server.sh`, `scripts/worker.sh`.
3. **Rien d'interactif** : pas de question, pas de `read`.
4. **Journaliser** : `echo` des étapes, pour comprendre où ça bloque.
5. **Ordre** : le serveur doit être prêt (token généré) avant que le worker ne le rejoigne.

Débogage :

```bash
vagrant provision --debug        # trace complète
vagrant ssh -c "tail -n 50 /var/log/syslog"
vagrant ssh                      # puis relancer le script à la main
```

`run: "always"` force l'exécution à **chaque** provisioning (utile pour un script de démarrage, dangereux pour une installation) :

```ruby
config.vm.provision "shell", path: "scripts/start.sh", run: "always"
```

Point important : « à chaque fois » signifie **à chaque fois que Vagrant provisionne** (`up`, `reload`, `provision`), et **pas** à chaque redémarrage interne de l'OS (`sudo reboot` dans la VM ne déclenche rien). Pour un vrai « à chaque boot », il faut un service systemd.

Plusieurs provisioners peuvent coexister : le premier argument est un **nom** qui les distingue, et ils s'exécutent dans l'ordre de déclaration.

```ruby
config.vm.provision "setup", type: "shell", path: "scripts/setup.sh", args: ["demo"]
config.vm.provision "marqueur", type: "shell", run: "always", inline: "echo boot >> /tmp/boot.log"
```

Le premier ne s'exécute qu'une fois (sauf `--provision`) ; le second à chaque `up`/`reload`.

### Piège : `/tmp` est vidé au démarrage

Sur Ubuntu/Debian, systemd **nettoie `/tmp` à chaque boot** (`/usr/lib/tmpfiles.d/tmp.conf` contient `D /tmp 1777 root root -`). Conséquences :

- `vagrant halt` + `vagrant up` = **vrai redémarrage** → `/tmp` est vidé ;
- `vagrant suspend` + `vagrant up` = **reprise** de l'état en mémoire → `/tmp` est conservé ;
- un artefact écrit dans `/tmp` par un provisioner « once » **disparaît** après un `halt`/`up`, puisque ce provisioner ne sera pas rejoué.

Pour un état durable, écrire hors de `/tmp` (`/var/lib/...`, `/var/log/...`, `/home/vagrant/...`). Pour un artefact qui doit être recréé à chaque démarrage, utiliser `run: "always"`. Et pour rejouer un provisioner « once » sans recréer la VM : `vagrant provision`.

---

## 2.8 Le dossier du projet

```
mon-projet/
├── Vagrantfile
├── scripts/
│   ├── server.sh
│   └── worker.sh
├── confs/
└── .vagrant/        <- généré par Vagrant, NE PAS COMMITER
```

- `/vagrant` **dans la VM** = le dossier du projet sur l'hôte (dossier synchronisé). Pratique pour lire les `confs/` depuis la VM.
- Sur VirtualBox, ce partage utilise `vboxsf` (nécessite les **Guest Additions**, présentes dans les boxes `bento/*`).
- `.gitignore` doit contenir au minimum :
  ```
  .vagrant/
  *.log
  ```

Rappel du sujet : les dossiers `p1/`, `p2/`, `p3/`, `bonus/` doivent être **à la racine du dépôt**, avec `scripts/` et `confs/` à l'intérieur.

---

## 2.9 Pièges classiques (à relire avant les TP)

1. **Modifier le provisioning puis `vagrant up`** → rien ne se passe. Utilise `--provision`.
2. **`/home` plein** : les boxes vont dans `VAGRANT_HOME`. Vérifie-le avant de télécharger.
3. **Hostname ≠ nom VirtualBox** : `vm.hostname` (interne) et `vb.name` (interface) sont deux choses différentes. K3s utilisera le **hostname**.
4. **Deux machines sur le même réseau privé** : même sous-réseau (`192.168.56.x`) et IP différentes.
5. **`private_network` sans host-only disponible** : sur certaines machines, l'interface `vboxnet0` doit être UP. Si l'hôte ne joint pas la VM, c'est la première chose à vérifier.
6. **Dossier synchronisé cassé** : si `/vagrant` est vide, les Guest Additions manquent ou `vboxsf` a échoué.
7. **Box trop lourde** : une box Ubuntu fait ~700 Mo ; deux VM ajoutent plusieurs Go de disque.
8. **`insert_key`** : si tu veux te connecter avec `ssh vagrant@IP` en utilisant la clé « insecure », il faut `config.ssh.insert_key = false` (moins sûr, mais pratique en évaluation).
9. **Ne jamais commiter `.vagrant/`** ni de clé privée.
10. **Toujours pouvoir repartir de zéro** : `vagrant destroy -f && vagrant up` doit redonner un environnement fonctionnel sans intervention.
11. **Restructurer le Vagrantfile crée des orphelines** : si tu renommes ou supprimes un `config.vm.define`, l'ancienne machine reste dans VirtualBox et dans `.vagrant/machines/<ancien nom>`, mais `vagrant destroy` ne la voit plus (il ne détruit que les machines **définies** dans le Vagrantfile courant). Détruis avant de restructurer, ou nettoie à la main.
12. **`vb.name` doit être unique** : deux machines configurées avec le même `vb.name` provoquent une collision de nom dans VirtualBox au moment du `up`.
13. **VM figée au boot** : `vagrant status` dit `running`, mais `vagrant up` reste bloqué à « Waiting for machine to boot / SSH address… » et SSH ne répond jamais. Prends une capture de la console (`VBoxManage controlvm <vm> screenshotpng /tmp/vm.png`) : si l'écran est figé sur une ligne de noyau du type `clk: Disabling unused clocks`, c'est souvent la **paravirtualisation KVM** de VirtualBox. Correction : `vb.customize ["modifyvm", :id, "--paravirtprovider", "none"]` dans le bloc provider (ou `VBoxManage modifyvm <vm> --paravirtprovider none`), puis `vagrant reload`. Ce n'est pas un problème SSH : la VM n'a jamais fini de démarrer.

---

## 2.10 Tutoriel bonus — une VM graphique, réplique de `base-clean`

Objectif : obtenir une VM **Debian 13 avec bureau graphique**, Docker et dossier partagé, c'est-à-dire l'équivalent de ton snapshot **`base-clean`** (« Debian 13 + tools + Docker + Guest Additions + shared folder ») **plus un environnement de bureau**.

> Ce tutoriel est un bonus de confort. Il n'est **pas** nécessaire pour IoT, qui se fait en SSH. Ne l'utilise pas pour les VM du projet : 4 Go de RAM et un bureau alourdissent tout inutilement.

### Ce qu'il faut ajouter à `base-clean`

| Élément de `base-clean` | Déjà dans la box Debian 13 ? | À ajouter |
|---|---|---|
| Debian 13 | oui | — |
| Guest Additions | oui dans les boxes `bento/*` | vérifier |
| Dossier partagé `/vagrant` | oui (Vagrant) | — |
| Docker | non | provisioning |
| Outils divers | variable | à lister depuis `base-clean` |
| **Bureau graphique** | **non** | `xfce4` + `lightdm` |
| Affichage d'une fenêtre | non | `vb.gui = true` |

### Méthode A — cloner le snapshot, puis ajouter le bureau

C'est la voie la plus **fidèle** (tu retrouves exactement tes outils), mais ce n'est pas Vagrant.

1. Éteins la VM `general_VM` (pas de « save state »).
2. Clone l'état du snapshot `base-clean` dans une nouvelle VM :
   ```bash
   VBoxManage clonevm general_VM --snapshot base-clean --name base-clean-gui --register
   ```
3. Démarre-la :
   ```bash
   VBoxManage startvm base-clean-gui --type gui
   ```
4. Dans la console (texte), installe le bureau :
   ```bash
   sudo apt-get update
   sudo DEBIAN_FRONTEND=noninteractive apt-get install -y xfce4 lightdm
   sudo systemctl set-default graphical.target
   sudo reboot
   ```
5. Au redémarrage, tu obtiens l'écran de connexion graphique. Ton utilisateur et tes fichiers sont ceux de `base-clean`.

Limites : clone figé, non reproductible par code, réseau NAT seul (pas de host-only), et il faudra recommencer à la main si tu veux la même chose ailleurs.

### Méthode B — la voie Vagrant (reproductible, recommandée)

J'ai vérifié : la box **`bento/debian-13`** existe sur Vagrant Cloud (version `202510.26.0`) avec un provider **virtualbox** pour x86_64. C'est la base la plus proche de `base-clean`.

**1. Le `Vagrantfile`**

```ruby
Vagrant.configure("2") do |config|
  config.vm.box      = "bento/debian-13"
  config.vm.hostname = "base-clean-gui"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "base-clean-gui"
    vb.memory = 4096          # un bureau + Docker : 4 Go minimum
    vb.cpus   = 2
    vb.gui    = true          # ouvre la fenêtre VirtualBox au démarrage

    vb.customize ["modifyvm", :id, "--vram", "128"]                     # mémoire vidéo
    vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
    vb.customize ["modifyvm", :id, "--clipboard-mode", "bidirectional"] # presse-papiers
    vb.customize ["modifyvm", :id, "--draganddrop", "bidirectional"]
  end

  config.vm.provision "shell", path: "scripts/desktop.sh"
end
```

**2. Le script `scripts/desktop.sh`**

```bash
#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  xfce4 lightdm dbus-x11 xterm curl ca-certificates gnupg

# lightdm comme gestionnaire de connexion, sans question interactive
echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections
dpkg-reconfigure -f noninteractive lightdm || true

# Docker (comme base-clean)
curl -fsSL https://get.docker.com | sh
usermod -aG docker vagrant
systemctl enable --now docker

# démarrage sur le bureau
systemctl set-default graphical.target
systemctl enable lightdm

echo "OK: bureau + docker installes"
```

**3. Démarrer et vérifier**

```bash
vagrant up            # télécharge la box, provisionne, ouvre la fenêtre
vagrant ssh -c "systemctl get-default; systemctl is-active lightdm; docker --version; lsmod | grep vboxguest"
```

Attendu : `graphical.target`, `active`, une version de Docker, et `vboxguest` chargé (Guest Additions). Identifiants dans la fenêtre : `vagrant` / `vagrant`.

**4. Vérifier les Guest Additions**

Sans elles : pas de `/vagrant`, pas de redimensionnement automatique, pas de presse-papiers.

```bash
vagrant ssh -c "lsmod | grep vboxguest; ls /vagrant"
```

Si elles manquent : `sudo apt-get install -y build-essential dkms linux-headers-$(uname -r)` puis installer l'ISO des Guest Additions (ou utiliser le plugin `vagrant-vbguest`). Sur les boxes `bento/*` elles sont normalement fournies.

### Trois façons d'accéder au bureau

| Méthode | Mise en place |
|---|---|
| **Console VirtualBox** | automatique avec `vb.gui = true` |
| **RDP (xrdp)** | dans la VM : `apt-get install -y xrdp`, puis `config.vm.network "forwarded_port", guest: 3389, host: 13389` ; côté hôte, client RDP vers `127.0.0.1:13389` |
| **X11 via SSH** | `ssh -X` depuis l'hôte, puis lancer une application graphique (pas une session complète) |

### Pièges de cette VM graphique

1. **RAM** : 512 Mo ou 1024 Mo ne suffisent pas pour XFCE + Docker ; prévois 4096 Mo.
2. **VRAM** : sans `--vram 128`, l'affichage peut être bloqué en basse résolution.
3. **Disque** : bureau + Docker ≈ 4 à 6 Go ; surveille `df -h /goinfre`.
4. **Premier `up` long** : téléchargement de la box + installation du bureau (plusieurs minutes).
5. **`vb.gui = true` seul ne crée pas un bureau** : sans `xfce4`/`lightdm`, la fenêtre n'affiche qu'un terminal texte.
6. **Ne modifie pas cette VM à la main dans l'interface** : tout doit rester dans le `Vagrantfile` et les scripts.
7. **Ce n'est pas pour IoT** : pour p1/p2/p3, reste sur des VM serveur sans bureau, en SSH.

---

## 2.11 Transformer cette VM en box réutilisable (ta « base-clean graphique »)

C'est le vrai intérêt de la démarche : **installer une fois, packager, réutiliser partout**. Une box personnelle t'évite de réinstaller XFCE et Docker à chaque nouveau projet.

### Le principe

```
Vagrantfile + provisioning  ──vagrant up──>  VM prête
        │
        └──vagrant package──>  fichier .box  ──vagrant box add──>  box réutilisable
                                                        │
                                        config.vm.box = "mzouhir/debian13-gui"
```

### Étape 1 — Construire la VM avec Vagrant (méthode B du 2.10)

Ne package **pas** directement `base-clean-gui` : cette VM n'a pas l'utilisateur `vagrant`, la clé SSH attendue, ni `sudo` sans mot de passe. Une box Vagrant doit contenir tout cela. En construisant la VM avec Vagrant, tout est déjà conforme.

### Étape 2 — Nettoyer avant l'export

```bash
vagrant ssh -c "sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && history -c"
```

Cela réduit la taille de la box et évite d'embarquer des logs ou l'historique.

### Étape 3 — Packager

```bash
vagrant halt
vagrant package --output debian13-gui.box
```

Puis l'ajouter comme box nommée et versionnée :

```bash
vagrant box add --name mzouhir/debian13-gui --box-version 1.0.0 debian13-gui.box
vagrant box list
```

### Étape 4 — L'utiliser dans n'importe quel projet

```ruby
Vagrant.configure("2") do |config|
  config.vm.box         = "mzouhir/debian13-gui"
  config.vm.box_version = "1.0.0"      # optionnel mais recommandé
end
```

`vagrant up` crée alors la VM **sans rejouer les installations** : elles sont déjà dans l'image.

### Étape 5 — Stockage et gestion

- Le `.box` peut être archivé dans `~/sgoinfre` (persistant) : c'est ton image de référence.
- `vagrant box add` **copie** la box dans `$VAGRANT_HOME/boxes` : prévois la place en double pendant l'import.
- Nettoyage des anciennes versions : `vagrant box prune`.
- Suppression : `vagrant box remove mzouhir/debian13-gui`.
- **Ne commit jamais** un `.box` dans Git : c'est un binaire de plusieurs Go.

### Bonnes pratiques

1. **Versionne** tes boxes (`--box-version 1.0.0`, puis `1.1.0` quand tu modifies l'image).
2. **Documente** ce qu'elles contiennent (un `README` à côté du `.box`).
3. **Ne package pas** une VM qui contient des secrets (clés, tokens).
4. Pour IoT, garde les box officielles : une box personnalisée avec K3s préinstallé est pratique pour toi, mais l'évaluation attend une installation reproductible par `Vagrantfile` + scripts.

---

## 2.12 Changer de poste : réparer VirtualBox et Vagrant

À 42, tu changeras souvent de poste. `/goinfre` est un disque **local et scratch** (effaçable), alors que `/home` persiste. Résultat classique : les **disques des VM disparaissent**, mais le **registre VirtualBox** (`~/.config/VirtualBox/VirtualBox.xml`) et le dossier **`.vagrant/`** du projet restent. VirtualBox affiche alors les VM comme `<inaccessible>`, et Vagrant échoue avec `E_ACCESSDENIED` au lieu de recréer la machine.

### Où sont les identifiants ?

| Information | Où la trouver |
|---|---|
| UUID utilisé par Vagrant | `.vagrant/machines/<nom>/virtualbox/id` |
| Liste des VM et UUID | `VBoxManage list vms` (les mortes apparaissent `<inaccessible>`) |
| Nom d'origine + chemin du `.vbox` | `~/.config/VirtualBox/VirtualBox.xml`, balises `<MachineEntry>` |
| Dossier des VM | `VBoxManage list systemproperties \| grep "Default machine folder"` |

### Diagnostic : repérer les fantômes

```bash
# UUID et chemins enregistrés
grep -o '<MachineEntry[^>]*>' ~/.config/VirtualBox/VirtualBox.xml

# Pour chaque entrée, le .vbox existe-t-il encore ?
grep -o 'uuid="{[^}]*}" src="[^"]*"' ~/.config/VirtualBox/VirtualBox.xml | while read -r line; do
  uuid=$(sed -E 's/.*uuid="\{([^}]*)\}".*/\1/' <<<"$line")
  src=$(sed -E 's/.*src="([^"]*)".*/\1/' <<<"$line")
  if [ -f "$src" ]; then echo "OK       $uuid  $src"; else echo "FANTOME  $uuid  $src"; fi
done
```

Toute ligne `FANTOME` est une entrée morte à retirer.

### Réparation

```bash
# 1. retirer chaque entrée fantôme (une commande par UUID)
VBoxManage unregistervm <uuid>

# 2. oublier l'état Vagrant du projet
cd ~/chemin/du/projet
rm -rf .vagrant

# 3. recréer la VM (la box sera re-téléchargée si absente)
vagrant up
```

Vérification : `VBoxManage list vms` ne doit plus afficher `<inaccessible>`.

### Si `unregistervm` refuse

1. Ferme l'interface VirtualBox.
2. Aucune VM ne doit tourner ; tue le service résiduel : `pkill -f VBoxSVC`.
3. Réessaie. En dernier recours, via l'interface : sélectionner la VM → *Retirer* → supprimer les fichiers.
4. Ultime recours : éditer `~/.config/VirtualBox/VirtualBox.xml` **après sauvegarde** et supprimer les lignes `<MachineEntry .../>` mortes.

### La routine à appliquer à chaque changement de poste

1. `VBoxManage list vms` → repérer les `<inaccessible>`.
2. Lancer le diagnostic ci-dessus, puis `unregistervm` sur chaque fantôme.
3. `vagrant global-status --prune` (nettoie l'index global de Vagrant).
4. Dans chaque projet : `rm -rf .vagrant`.
5. `vagrant up` → la VM et, si besoin, la box sont recréées.
6. Vérifier `vagrant status`, puis `vagrant ssh -c hostname`.

### Prévention

1. **Git est la seule source de vérité** : `Vagrantfile`, `scripts/`, `confs/` doivent être commités. La VM, elle, est jetable.
2. **Boxes** : mets `VAGRANT_HOME` sur `~/sgoinfre/vagrant_home` (persistant entre postes) plutôt que sur `/goinfre`.
3. **Ne stocke jamais** un travail important uniquement dans une VM : il disparaît avec `/goinfre`.
4. **Snapshot ≠ sauvegarde portable** : un snapshot VirtualBox vit avec le disque de la VM.
5. Si tu sais que tu quittes un poste, `vagrant destroy -f` supprime proprement la VM et son entrée VirtualBox (mais ne protège pas d'un effacement brutal de `/goinfre`).

### Mémo

| Besoin | Commande |
|---|---|
| Lister les VM + UUID | `VBoxManage list vms` |
| Voir les chemins enregistrés | `grep MachineEntry ~/.config/VirtualBox/VirtualBox.xml` |
| Dossier des VM | `VBoxManage list systemproperties` |
| Retirer une entrée morte | `VBoxManage unregistervm <uuid>` |
| Oublier l'état du projet | `rm -rf .vagrant` |
| Nettoyer l'index Vagrant | `vagrant global-status --prune` |

---

## 2.13 TP — À toi de jouer

> Règle : **aucune solution n'est donnée**. Le cours ci-dessus contient tous les outils. Tiens un journal dans `cours/journal-lecon2.txt` : pour chaque TP, note les commandes utilisées, les sorties importantes et les erreurs rencontrées. Je te demanderai ce journal.

### TP 1 — Préparer l'environnement
1. Vérifie les versions de Vagrant et VirtualBox, et que ton utilisateur est bien dans `vboxusers`.
2. Choisis où stocker les boxes : `VAGRANT_HOME` sur `/goinfre/mzouhir/.vagrant.d` **ou** sur ton espace persistant `~/sgoinfre/vagrant_home` (voir 2.3). Fais-le pour la session **et** de façon persistante (dans `~/.bashrc`).
3. Vérifie l'espace libre de `/home` et de `/goinfre`.
4. Crée un dossier de projet `~/Documents/iot-vagrant/tp1` et place-toi dedans.

### TP 2 — Premier Vagrantfile
1. Génère un Vagrantfile minimal avec `vagrant init` en choisissant la box `bento/ubuntu-22.04`.
2. Ouvre le fichier : repère la version de configuration, la box, et les blocs commentés.
3. Vérifie sa syntaxe.
4. Supprime toutes les lignes de commentaires pour ne garder que le strict nécessaire (tu peux faire une copie de sauvegarde avant).

### TP 3 — Les boxes
1. Liste les boxes installées (il ne devrait y en avoir aucune).
2. Télécharge la box `bento/ubuntu-22.04` pour le provider `virtualbox`.
3. Liste à nouveau, puis affiche la taille occupée par `VAGRANT_HOME`.
4. Cherche s'il existe une version plus récente de la box.

### TP 4 — Premier démarrage
1. Démarre la machine.
2. Regarde son état, puis entre dedans en SSH.
3. Dans la VM, affiche : l'utilisateur courant, le hostname, les interfaces réseau, et le contenu de `/vagrant`.
4. Depuis la VM, teste si `sudo` fonctionne **sans mot de passe**.
5. Sors de la VM, puis affiche la configuration SSH que Vagrant utilise.

### TP 5 — SSH sans Vagrant
1. À partir de `vagrant ssh-config`, identifie : l'utilisateur, le port sur l'hôte, et le fichier de clé privée.
2. Connecte-toi à la VM **avec un `ssh` classique** (sans `vagrant ssh`), en utilisant ces informations.
3. Regarde les permissions du fichier de clé privée. Sont-elles correctes pour SSH ?
4. Depuis l'hôte, teste la connexion avec `vagrant` comme mot de passe (si l'authentification par mot de passe est autorisée). Que se passe-t-il ?

### TP 6 — Cycle de vie
1. Arrête la VM proprement, vérifie son état, redémarre-la.
2. Mets la VM en pause (`suspend`), vérifie l'état, puis reprends-la.
3. Redémarre-la avec `reload`.
4. Détruis-la, vérifie qu'elle n'existe plus, puis recrée-la.
5. Note dans ton journal : quelles commandes ont réinstallé l'OS, lesquelles ne l'ont pas fait ?

### TP 7 — Dossier synchronisé
1. Depuis l'hôte, crée un fichier `preuve.txt` dans le dossier du projet.
2. Depuis la VM, affiche-le via `/vagrant`.
3. Depuis la VM, crée un fichier dans `/vagrant` et vérifie qu'il apparaît sur l'hôte.
4. Explique (dans le journal) ce qui se passerait si les Guest Additions étaient absentes.

### TP 8 — Provisioning inline
1. Ajoute au Vagrantfile un provisioning **inline** qui écrit la date courante dans `/tmp/provision-date.txt`.
2. Applique la modification.
3. Vérifie le contenu du fichier dans la VM.
4. Sans rejouer le provisioning, redémarre la VM et vérifie si le fichier a changé. Que conclus-tu ?
5. Rejoue explicitement le provisioning et compare.

### TP 9 — Provisioning par script, arguments, idempotence
1. Crée `scripts/setup.sh` qui : affiche son rôle (reçu en argument), installe un paquet simple (par exemple `curl`), et écrit une ligne dans `/tmp/setup.log` à chaque exécution.
2. Branche-le dans le Vagrantfile avec un argument `demo`.
3. Rejoue le provisioning **trois fois** et compte les lignes de `/tmp/setup.log`.
4. Modifie le script pour qu'il devienne réellement idempotent (l'installation ne doit rien casser, et tu dois pouvoir expliquer pourquoi `apt-get install -y` est idempotent).
5. Ajoute un second provisioning qui s'exécute à **chaque** démarrage, et vérifie son comportement après deux `up`.

### TP 10 — Ressources et nom
1. Configure la VM pour 1 vCPU, 1024 Mo de RAM, et un nom `tp10-vm` dans VirtualBox.
2. Recrée la VM et vérifie dans VirtualBox (ou via `VBoxManage`) que le nom et les ressources sont appliqués.
3. Compare le hostname **interne** et le nom **VirtualBox** : sont-ils identiques ? Où as-tu défini chacun ?

### TP 11 — Réseau privé
1. Configure une `private_network` avec l'IP `192.168.56.110` et le hostname `mzouhirS` (adapte au tien).
2. Recrée la VM et vérifie l'IP **dans la VM**.
3. Depuis l'hôte, vérifie l'interface `vboxnet0`, puis pingue `192.168.56.110`.
4. Depuis l'hôte, connecte-toi en SSH sur cette IP avec la clé de la VM.
5. Si le ping échoue, diagnostique (interface host-only, IP dans la VM, pare-feu) et note la cause.

### TP 12 — Deux machines
1. Déclare deux VM : `mzouhirS` (`192.168.56.110`) et `mzouhirSW` (`192.168.56.111`), 1 vCPU / 1024 Mo chacune.
2. Démarre-les et vérifie que chacune a le bon hostname et la bonne IP.
3. Depuis `mzouhirS`, pingue `mzouhirSW`, et inversement.
4. Depuis l'hôte, pingue les deux.
5. Détruis uniquement `mzouhirSW`, puis recrée-la. Vérifie que `mzouhirS` n'a pas été touchée.

### TP 13 — Redirection de port
1. Ajoute une redirection `hôte:8888 -> VM:8000` sur une des machines.
2. Dans la VM, lance un serveur HTTP Python sur le port 8000, en servant `/vagrant`.
3. Depuis l'hôte, vérifie que le port écoute, puis récupère une page avec `curl`.
4. Demande une URL inexistante et observe le code HTTP.
5. Arrête le serveur et vérifie que le port n'écoute plus.

### TP 14 — Snapshots
1. Prends un snapshot de la VM, puis crée un fichier témoin dans `/tmp`.
2. Modifie la VM (installe un paquet ou supprime le fichier).
3. Liste les snapshots, restaure celui pris à l'étape 1, et vérifie que le fichier témoin est revenu et que la modification a disparu.
4. Supprime le snapshot.

### TP 15 — Mini-projet « p1 à blanc »
Reproduis le squelette de la partie 1 du sujet, **sans K3s** :
1. Deux VM, hostnames `<login>S` et `<login>SW`, IP `192.168.56.110` et `.111`, 1 vCPU et 1024 Mo. Donne à chacune un `vb.name` **unique**, idéalement identique à son hostname (`<login>S` et `<login>SW`) : deux VM ne peuvent pas porter le même nom dans VirtualBox.
2. Un script `scripts/common.sh` (ou deux scripts) qui installe un paquet commun et crée un fichier `/tmp/ready`.
3. Vérifie que les deux VM sont joignables depuis l'hôte et entre elles.
4. Vérifie que tu peux te connecter en SSH **sans mot de passe** depuis l'hôte, en utilisant la clé générée par Vagrant.
5. Détruis tout, puis recrée tout avec **une seule commande**, sans intervention manuelle.
6. Vérifie qu'après recréation, les IP, hostnames et le fichier `/tmp/ready` sont de nouveau là.

### TP 16 — Diagnostic guidé
Provoque volontairement chaque panne, observe le message, puis répare :
1. Une IP host-only en double sur les deux VM.
2. Un `vm.hostname` identique sur les deux VM.
3. Ta machine dont l'IP n'est pas dans le bon sous-réseau.
4. Un script de provisioning qui échoue (commande inexistante) : que fait `vagrant up` ? Comment le vois-tu ?
5. Un `vagrant up` après modification du script, sans `--provision`.
Note pour chaque cas : le symptôme, la commande de diagnostic, la cause, le correctif.

---

## Validation des TP 1–11 (contrôle du 19/11)

Contrôle effectué directement sur la machine, projet `~/Documents/iot-lab/iot_vagrant/tp1`.

| TP | Statut | Preuve / constat |
|---|---|---|
| 1 | Validé avec réserve | Vagrant 2.4.9 + VirtualBox 7.2.22 ; utilisateur dans `vboxusers` ; `VAGRANT_HOME` exporté dans `~/.bashrc` (valeur à revoir, signalée à part) |
| 2 | **Validé** | `vagrant validate` → « Vagrantfile validated successfully » |
| 3 | **Validé** | Box installée : `bento/ubuntu-22.04 (virtualbox, 202510.26.0, amd64)`, ~811 Mo |
| 4 | **Validé** | Dans la VM : `hostname` = `mzouhirS` ; `sudo -n true` OK (sans mot de passe) ; `/vagrant` monté et lisible |
| 5 | **Validé** | `ssh-config` : user `vagrant`, port **2200**, clé `.vagrant/machines/default/virtualbox/private_key` ; connexion `ssh` classique par IP avec cette clé : OK |
| 6 | **Validé** | Journal complet : `halt` → `poweroff`, `suspend` → `saved`, `up` (resume), `reload`, `destroy` → `not created`, puis `up` (réimport de la box) |
| 7 | **Validé** | `preuve.txt` créé sur l'hôte et vu dans `/vagrant` ; `preuve2.txt` créé dans `/vagrant` et vu sur l'hôte. Les fichiers sont vides, mais le partage est démontré |
| 8 | **Validé** | Journal : le témoin n'apparaît **pas** après `up` ni `reload`, puis apparaît après `reload --provision` (date du jour). Conclusion correcte |
| 9 | Validé (étapes 1–4) | Script conforme (rôle, `curl`, log) ; `wc -l /tmp/setup.log` → **3** après trois exécutions. Étape 5 (provisioning à chaque démarrage) non faite |
| 10 | **Validé** | `VBoxManage` : `name=tp10-vm`, `memory=1024`, `cpus=1`, `nic2=hostonly` (vboxnet0) |
| 11 | **Validé** | `eth1 = 192.168.56.110/24` ; `vboxnet0` UP (192.168.56.1/24) ; `ping 192.168.56.110` OK ; SSH par clé sur l'IP : OK |

### Détails des points validés

**TP 4** — la VM tourne, on y entre par `vagrant ssh`, l'utilisateur `vagrant` a `sudo` sans mot de passe, et le dossier synchronisé `/vagrant` expose bien le projet.

**TP 5** — le port SSH n'est pas 2222 mais **2200** : Vagrant a détecté une collision (le 2222 est déjà utilisé par la redirection de `general_VM`) et a choisi le port suivant. C'est le comportement normal de la détection de collision. La connexion sans Vagrant fonctionne :

```bash
ssh -i .vagrant/machines/default/virtualbox/private_key vagrant@192.168.56.110
```

**TP 10** — nom, RAM et CPU sont bien appliqués côté VirtualBox, et distincts du hostname interne (`mzouhirS`).

**TP 11** — la carte host-only est présente dans la VM (`eth1`), l'interface `vboxnet0` est UP côté hôte, le ping passe, et le SSH par clé sur `192.168.56.110` répond. C'est exactement le mécanisme attendu pour la p1.

**TP 6** — les quatre états ont été observés et documentés : `running`, `poweroff` (après `halt`), `saved` (après `suspend`, puis `up` fait un *resume*), `not created` (après `destroy`, puis `up` réimporte la box). C'est la preuve que la VM est reproductible.

**TP 7** — le dossier synchronisé fonctionne dans les deux sens : fichier créé sur l'hôte → visible dans `/vagrant` ; fichier créé dans `/vagrant` → visible sur l'hôte. Le fait que les fichiers soient vides n'a aucune importance : c'est la synchronisation qui était testée.

**TP 8** — l'expérience est concluante et bien interprétée : `vagrant up` et `vagrant reload` **ne rejouent pas** le provisioning, alors que `reload --provision` l'exécute (le témoin contenant la date apparaît).

**TP 9** — trois exécutions ont bien produit trois lignes dans `/tmp/setup.log`. Attention : ce fichier est dans `/tmp`, donc il est **perdu** à chaque `destroy`/recréation. À l'instant du contrôle il n'y avait plus qu'une ligne, parce que les TP 10 et 11 ont recréé la VM entre-temps. C'est normal et cela illustre au passage la différence entre l'état d'une VM et son disque.

### Questions posées dans le journal

**« Pourquoi je n'ai pas besoin de mettre le port dans `ssh vagrant@192.168.56.110` ? »**
Parce que cette adresse est une IP **host-only** : la VM est joignable **directement** sur son port 22 réel. Le port `2200` n'existe que pour le mode NAT, où l'hôte ne peut atteindre la VM qu'à travers une redirection (`127.0.0.1:2200 → VM:22`). Dès qu'une `private_network` est configurée, on se connecte à l'IP, sur le port standard. C'est exactement ce qui se passera en p1 avec `192.168.56.110` et `.111`.

**« Les Guest Additions sont-elles incluses dans la box bento ? »**
Oui. Les boxes `bento/*` embarquent les VirtualBox Guest Additions. C'est pour cela que le dossier `/vagrant` se monte (le log de `reload` affiche `Checking for guest additions in VM...` puis `Mounting shared folders...`). Sans elles, `vboxsf` ne fonctionnerait pas et `/vagrant` serait vide.

**« Le hostname vaut `vagrant` alors que le nom de la VM est `tp10-vm`, est-ce normal ? »**
Oui, et c'est une distinction essentielle : `vb.name` est le nom dans l'interface VirtualBox, `vm.hostname` est le nom à l'intérieur de l'OS. Si `vm.hostname` n'est pas défini, la box garde son hostname par défaut (`vagrant`). En p1, c'est le **hostname** qui compte, car K3s l'utilise comme nom du node.

---

## 2.14 Questions de la leçon 2

Réponds sous chaque question. Les TP n'ont pas de champ de réponse : c'est de la manipulation, tu consignes dans `cours/journal-lecon2.txt`.

### Partie A — Concepts

**A1.** Explique la différence entre Vagrant, le provider et la box, avec une analogie ou un exemple concret.

**Ta réponse :**
vagrant est un langage qui permet de donner une configuration d une vm. le provider est le logiciel qui permettra de creer la vm. la box est l image de base sur laquelle sera basee la vm

**Verdict : Partiel.**
**Correction :** Vagrant n'est pas un langage : c'est un **orchestrateur de VM**. Le `Vagrantfile` est écrit dans une DSL Ruby, mais Vagrant est l'outil qui pilote tout. Le provider (VirtualBox) est le moteur qui crée la VM ; la box est l'image de base préinstallée (OS + utilisateur `vagrant` + SSH + Guest Additions). Analogie : la box est le moule, le provider est le four, le Vagrantfile est la recette.

**A2.** Pourquoi dit-on que Vagrant fait de l'« Infrastructure as Code » ? Quels avantages concrets pour le projet ?

**Ta réponse :**
Vagrant permet de donnner l infrastructure d une Vm. l avantage est de pouvoir utiliser systematiquement la meme vm (versionning) peut importe le poste utiliser.

**Verdict : OK (avec une nuance).**
**Correction :** On ne reproduit pas « la même VM » mais la **même description d'infrastructure**. Avantages : versionnée dans Git, reproductible à l'identique, réutilisable sur n'importe quel poste, documentée par le code, et destructible/recréable sans risque. C'est exactement ce qui te permet de changer de poste sans perdre le travail : seul le code compte.

**A3.** Quelle est la différence entre une VM et un conteneur Docker ? Pourquoi le projet utilise-t-il des VM en p1 et des conteneurs en p3 ?

**Ta réponse :**
je n ai pas encore vu ce que faisait la partie 3. une vm creer un system d exploitation tandis que un conteneur docker partage le noyau linux avec le docker. un conteneur est donc moins gourmant et plus rapide a etre creer.

**Verdict : Partiel.**
**Correction :** La distinction est juste : un conteneur partage le **noyau de la machine hôte** (pas « avec Docker »), il est plus léger et démarre plus vite ; une VM a son propre noyau et une isolation plus forte. Pour le projet : p1/p2 utilisent des **VM** pour faire de l'administration système réelle (K3s via systemd, réseau host-only) ; p3 utilise **Docker/K3d** : K3s tourne dans des conteneurs, le cluster est jetable et rapide, et Argo CD y déploie des applications conteneurisées.

**A4.** Qu'est-ce qu'une box ? Où est-elle stockée sur ta machine, et pourquoi est-ce important ici ?

**Ta réponse :**
une box est l image du system exploitation qui sera utiliser. il sera stocker dans le goinfre. il est necessaire afin de pouvoir creer la vm

**Verdict : Partiel.**
**Correction :** Une box est une **image de VM préinstallée** : OS + utilisateur `vagrant` + serveur SSH + Guest Additions. Elle est stockée dans `$VAGRANT_HOME/boxes` — par défaut `~/.vagrant.d/boxes`, chez toi `/goinfre/mzouhir/.vagrand.d/boxes` (ou `~/sgoinfre/...` si tu changes). Elle est indispensable pour créer la VM, mais **ce n'est pas une sauvegarde** de ton travail : elle est re-téléchargeable.

**A5.** Que signifie « idempotent » ? Donne deux exemples de commandes idempotentes et une non idempotente.

**Ta réponse :**
idempotent veut dire qui peut etre execute plusieur fois sans changer le resultat.
mkdir -p /tmp/test est indempotent
echo "test" >> /tmp/test n est pas idempotent

**Verdict : Partiel.**
**Correction :** Définition et exemples corrects, mais il manquait **un deuxième exemple idempotent**. Idempotents : `mkdir -p /tmp/test`, `apt-get install -y curl`, `systemctl enable`, `kubectl apply -f`. Non idempotent : `echo x >> fichier`, `useradd`, `mkdir` sans `-p`.

### Partie B — Vagrantfile

**B1.** Que signifie le `"2"` dans `Vagrant.configure("2")` ?

**Ta réponse :**
ici il s agit de la version de la configuration choisis. a ne pas confondre avec la version de vagrant installer sur le poste

**Verdict : OK.** C'est bien la version du format de configuration, indépendante de la version du binaire Vagrant.

**B2.** Quelle est la différence entre `vm.hostname` et `vb.name` ? Lequel K3s utilisera-t-il pour nommer le node ?

**Ta réponse :**
vm.hostname est le hostname de la VM. vb.name est le nom de la VM dans le provider.on utilisera name pour nomer le node

**Verdict : À revoir.**
**Correction :** `vm.hostname` = nom **à l'intérieur** de l'OS ; `vb.name` = nom **d'affichage dans VirtualBox**. K3s utilise le **hostname**, pas `vb.name`. En p1, tes nodes s'appelleront donc `mzouhirS` et `mzouhirSW` parce que c'est le hostname, quel que soit le nom VirtualBox.

**B3.** À quoi sert `config.vm.define` ? Que se passe-t-il si tu ne l'utilises pas ?

**Ta réponse :**
il permet de nommer la VM dans le code afin de creer plusieur VM. si on ne l utilise pas, toute les configuration seron identique.

**Verdict : Partiel.**
**Correction :** `define` déclare et nomme une machine, ce qui permet d'en définir plusieurs. Sans `define`, Vagrant crée **une seule machine nommée `default`** (ce n'est pas « toutes les configurations identiques »).

**B4.** Quelle est la différence entre `provision "shell", inline:` et `provision "shell", path:` ? Lequel est préférable pour un script de 50 lignes, et pourquoi ?

**Ta réponse :**
le premier permet de taper directement les ligne de commande dans le vagrantfile
le second permet d indiquer le chemin d un script qui sera executer au lancement

**Verdict : Partiel.**
**Correction :** La distinction est juste, mais il manquait la recommandation : pour 50 lignes, `path:` est préférable (lisibilité du Vagrantfile, réutilisation, versionnement séparé, et le sujet impose un dossier `scripts/`).

**B5.** Dans un bloc `config.vm.provider "virtualbox"`, à quoi servent `memory` et `cpus` ? Pourquoi le sujet conseille-t-il des valeurs minimales ?

**Ta réponse :**
il permet de donner les valeurs de memoire et cpus au provider pour la creation de la VM.
ici le travail est minime pour cette exercice donc pas besoin de beaucoup de puissance.

**Verdict : OK.** Le sujet impose aussi des ressources minimales pour ne pas saturer l'hôte et rester dans l'esprit « léger » de K3s.

**B6.** Comment déclare-t-on deux machines dans un même Vagrantfile, et qu'est-ce qui détermine leur ordre de démarrage ?

**Ta réponse :**
pour declarer deux machines dans un meme vagrant file il faut deux define. leur ordre de declaration defini leur ordre de demarage

**Verdict : OK.**

### Partie C — Cycle de vie

**C1.** Quelle est la différence entre `vagrant up` et `vagrant reload` ?

**Ta réponse :**
vagrant up lance la machine tandis que vagrant reload fait vagrand halt + vagrant up

**Verdict : OK (avec une nuance).** `reload` = halt + up, mais **sans rejouer le provisioning** (sauf `--provision`). `up` sur une machine déjà provisionnée ne le rejoue pas non plus.

**C2.** Tu modifies un script de provisioning. Cite **deux** commandes qui garantissent qu'il sera rejoué.

**Ta réponse :**
vagrant provision
vagrant reload --provision

**Verdict : OK.**

**C3.** Que fait `vagrant destroy` exactement ? Que se passe-t-il ensuite si tu fais `vagrant up` ?

**Ta réponse :**
il detruit la totaliter des vm creer.
en faisant vagrant up on relance les machine avec un nouveau provisionnement

**Verdict : Partiel.**
**Correction :** `destroy` détruit les machines **de l'environnement courant** (celles définies dans le Vagrantfile), pas toutes les VM du poste. Ensuite, `vagrant up` réimporte la box, recrée les disques et rejoue le provisioning : c'est la reconstruction complète.

**C4.** À quoi sert le dossier `.vagrant/` ? Pourquoi ne faut-il jamais le commiter ?

**Ta réponse :**
il contient un lien symbolique vers l image des machines virtuel. inutile de le commiter car il ne peut fonctionner que sur le poste ou les vm ont ete creer.

**Verdict : Partiel.**
**Correction :** `.vagrant/` contient l'**état local** : l'UUID de la VM, la clé privée générée, le marqueur de provisioning, les infos de dossiers synchronisés. Ce n'est **pas** un lien vers l'image. On ne le commit pas parce qu'il est spécifique au poste et devient invalide ailleurs (UUID et chemins morts).

**C5.** Quelle commande affiche toutes les VM Vagrant de la machine, tous projets confondus, et pourquoi son résultat peut devenir obsolète ?

**Ta réponse :**
vagrant list vms.
il peut devenir obsolete si les vms ne sont plus presente mais toujours register dans vboxmanager

**Verdict : À revoir (commande fausse).**
**Correction :** la commande est **`vagrant global-status`** (il n'existe pas de `vagrant list vms`). L'idée sur l'obsolescence est bonne : c'est un cache, à nettoyer avec `vagrant global-status --prune`.

### Partie D — Réseau

**D1.** Explique le mode NAT de VirtualBox. Pourquoi `vagrant ssh` fonctionne-t-il sans configuration réseau particulière ?

**Ta réponse :**
NAT fait une redirection de port afin de pouvoir se connecter a internet
vagrant creer une cle ssh prive et publique et nous permet de nous connecter en ssh sans configuration particuliere

**Verdict : Partiel.**
**Correction :** Le NAT fait de la **traduction d'adresses** : la VM sort vers Internet via l'hôte, mais l'hôte ne peut pas l'atteindre directement. Vagrant ajoute donc automatiquement une **redirection de port** `hôte:2222 → VM:22` (puis 2200, 2201… en cas de collision) et gère une paire de clés SSH. C'est la combinaison des deux qui rend `vagrant ssh` transparent.

**D2.** Quelle directive Vagrant crée un réseau host-only avec une IP fixe ? Sur quelle interface de l'hôte cela s'appuie-t-il sous VirtualBox ?

**Ta réponse :**
config.vm.networ "private_network", ip :".."
cela s appuie sur l interface loopback

**Verdict : À revoir (seconde partie fausse).**
**Correction :** La directive est `config.vm.network "private_network", ip: "..."` (typo dans `networ`). Elle s'appuie sur une interface **host-only** de VirtualBox — `vboxnet0` avec `192.168.56.1/24` — et **pas** sur le loopback.

**D3.** Quelle est la différence entre `private_network` et `public_network` ?

**Ta réponse :**
public_network est accessible en ligne ?

**Verdict : À revoir.**
**Correction :** `private_network` = réseau **host-only** entre l'hôte et les VM (pas d'accès au réseau physique). `public_network` = mode **bridged** : la VM est branchée sur le réseau physique comme une machine de plus, elle obtient une IP du routeur et est visible sur le LAN. « Accessible en ligne » n'est pas la définition.

**D4.** Tu veux exposer le port 80 de la VM sur le port 8080 de l'hôte. Écris la directive Vagrant correspondante.

**Ta réponse :**
vm.config.network "forwarded_port", guest: 80, host: 8080

**Verdict : À revoir (syntaxe).**
**Correction :** `config.vm.network "forwarded_port", guest: 80, host: 8080` (ou `machine.vm.network` à l'intérieur d'un `define`). `vm.config.network` n'existe pas.

**D5.** Pourquoi le sujet demande-t-il `192.168.56.110` et `192.168.56.111` plutôt que des IP en `10.x` ? Que faut-il pour que deux VM se joignent sur ce réseau ?

**Ta réponse :**
il s agit du reseau local est non pas du reaseau ouvert sur internet. pour que les deux vm puisse se joindre elle doit etre sur le meme sous reseau

**Verdict : OK (à compléter).**
**Correction :** Ce sont des adresses **privées** (RFC 1918) du réseau host-only classique de VirtualBox (`192.168.56.0/24`), non routables sur Internet. Pour que les deux VM se joignent : même réseau host-only, **IP distinctes** dans le même `/24`, et l'interface `vboxnet0` de l'hôte UP.

**D6.** Depuis l'hôte, `ping 192.168.56.110` échoue alors que `vagrant ssh` fonctionne. Cite trois causes possibles.

**Ta réponse :**
le private network n est pas configurer.
les deux private network ne sont pas sur le meme sous reseau

**Verdict : Partiel (deux causes sur trois, et la seconde est hors sujet).**
**Correction :** Causes possibles : (1) pas de `private_network` sur la VM, ou mauvaise IP ; (2) interface **host-only de l'hôte** DOWN ou absente (`vboxnet0`) ; (3) pare-feu (VM ou hôte) qui bloque l'ICMP ; (4) l'hôte n'est pas sur le même sous-réseau. La seconde réponse que tu as donnée concerne deux VM entre elles, pas l'hôte vers la VM.


### Partie E — SSH

**E1.** Quel utilisateur Vagrant crée-t-il dans la VM, avec quel mot de passe, et quel droit particulier a-t-il ?

**Ta réponse :**
il creer l utilisateur vagrant, sans mot de passe avec les droit sudo

**Verdict : À revoir (précision importante).**
**Correction :** L'utilisateur est `vagrant`, son **mot de passe est `vagrant`** (pas « sans mot de passe »), et il a `sudo` **sans mot de passe** (NOPASSWD). C'est le sudo qui ne demande rien, pas l'utilisateur qui n'a pas de mot de passe.

**E2.** Qu'est-ce que la clé « insecure » de Vagrant ? Que fait `config.ssh.insert_key = true` ?

**Ta réponse :**
aucune idee

**Verdict : À revoir.**
**Correction :** La clé « insecure » est une paire de clés **publique et connue**, livrée avec Vagrant (`~/.vagrant.d/insecure_private_key`), utilisée pour le tout premier accès SSH. Avec `config.ssh.insert_key = true` (défaut), Vagrant **remplace** cette clé par une paire générée par machine, stockée dans `.vagrant/machines/<nom>/<provider>/private_key`. Avec `false`, il conserve la clé insecure (moins sûr, mais pratique pour `ssh vagrant@IP`).

**E3.** Où se trouve la clé privée générée pour une machine, et quelle commande permet de connaître le port et la clé utilisés ?

**Ta réponse :**
vagrant ssh config

**Verdict : À revoir (commande fausse et clé non indiquée).**
**Correction :** La commande est **`vagrant ssh-config`** (avec un tiret). Elle affiche `User`, `HostName`, `Port` et `IdentityFile`. La clé privée est dans `.vagrant/machines/<nom>/<provider>/private_key` (ici `virtualbox`).

**E4.** Comment prouverais-tu à un évaluateur que l'on peut se connecter en SSH **sans mot de passe** sur les deux VM, sans utiliser `vagrant ssh` ?

**Ta réponse :**
ssh vagrant@ip -p

**Verdict : Partiel.**
**Correction :** Il manque **la clé**. Depuis l'hôte, avec l'IP host-only et le port 22 :
```bash
ssh -i .vagrant/machines/<nom>/virtualbox/private_key vagrant@192.168.56.110
```
ou via le NAT :
```bash
ssh -i .vagrant/machines/<nom>/virtualbox/private_key -p 2200 vagrant@127.0.0.1
```
Sans `-i`, SSH n'utilise pas la clé de la VM et demande un mot de passe.


### Partie F — Diagnostic

**F1.** `vagrant up` échoue avec un message sur le provider. Quelle est la première chose à vérifier ?

**Ta réponse :**
que l ont est bien dans le bon dossier.
vagrant validate

**Verdict : Partiel.**
**Correction :** D'abord **lire le message** et vérifier que le provider fonctionne : `VBoxManage --version` (VirtualBox installé et accessible). Être dans le bon dossier sert à trouver le Vagrantfile, mais `vagrant validate` ne teste que la syntaxe, pas le provider.

**F2.** `vagrant up` réussit mais `/vagrant` est vide dans la VM. Quelle est la cause probable ?

**Ta réponse :**
guest addition n est pas present sur le poste

**Verdict : Partiel.**
**Correction :** Les Guest Additions manquent **dans la VM / dans la box** (ou `vboxsf` a échoué), pas sur le poste. Vérifie `lsmod | grep vboxguest` dans la VM et le log de `vagrant reload` (`Mounting shared folders...`).

**F3.** Le provisioning a échoué mais `vagrant up` s'est terminé. Comment le détectes-tu, et comment relances-tu uniquement le provisioning ?

**Ta réponse :**
vagrant provision

**Verdict : Partiel.**
**Correction :** Détection : le message du provisioner en erreur et le **code retour non nul** de `vagrant up` (`echo $?`), puis vérifier l'artefact attendu. Relance : `vagrant provision` (ou `vagrant reload --provision`).

**F4.** Les deux VM ont la même IP. Que s'est-il passé, et quelle est la conséquence ?

**Ta réponse :**
impossible de joindre les deux ip

**Verdict : Partiel.**
**Correction :** Cause : la même `private_network` a été copiée sur les deux VM (même IP). Conséquence : conflit ARP/routage, les paquets arrivent à une seule des deux (souvent de façon intermittente), l'autre est injoignable. Vérifier `ip a` dans chacune.

**F5.** `vagrant ssh` fonctionne, mais `ssh vagrant@192.168.56.110` demande un mot de passe. Donne au moins deux explications possibles.

**Ta réponse :**
il suffit de valider sans mot de passe. je ne sais pas 

**Verdict : À revoir.**
**Correction :** Causes possibles : (1) la clé publique du client n'est **pas dans `~/.ssh/authorized_keys`** du serveur ; (2) tu utilises la **mauvaise clé** : avec `insert_key = true`, la clé insecure a été remplacée, il faut passer `-i .vagrant/machines/<nom>/virtualbox/private_key` ; (3) permissions incorrectes (clé privée `600`, `~/.ssh` `700`, `authorized_keys` `600`) ; (4) `PubkeyAuthentication no` côté serveur ; (5) mauvais utilisateur, IP ou port.

### Partie G — Lien avec le projet

**G1.** En quoi le Vagrantfile de la p1 est-il une traduction directe des exigences du sujet ? Associe chaque exigence à une directive.

**Ta réponse :**
<!-- non répondu au moment de la correction -->

**Verdict : à connaître.**
**Réponse :**

| Exigence du sujet | Directive Vagrant |
|---|---|
| Deux machines | deux blocs `config.vm.define` |
| Nom = login (+ S/SW) | `vm.hostname` et `vb.name` (uniques) |
| IP `192.168.56.110` / `.111` sur l'interface primaire | `vm.network "private_network", ip: ...` |
| SSH sans mot de passe | utilisateur `vagrant` + clé gérée par Vagrant (`config.ssh.insert_key`), `vagrant ssh` |
| K3s en mode controller / agent | `vm.provision "shell", path: "scripts/server.sh"` / `worker.sh` |
| 1 CPU et 512–1024 Mo | `vb.cpus` et `vb.memory` |
| Machines lancées par Vagrant | `Vagrantfile` + `vagrant up` |
| `kubectl` installé | dans le script de provisioning du serveur |
| Pratiques modernes | scripts dans `scripts/`, fichiers de conf dans `confs/` |

**G2.** Pourquoi le serveur doit-il être provisionné avant le worker en p1 (pense à K3s) ?

**Ta réponse :**
<!-- non répondu au moment de la correction -->

**Verdict : à connaître.**
**Réponse :** Le worker a besoin, pour rejoindre le cluster, de l'**URL de l'API du serveur** (`https://192.168.56.110:6443`) et du **token** généré par l'installation du serveur (`/var/lib/rancher/k3s/server/node-token`). Si le worker démarre avant, le token n'existe pas et l'agent ne peut pas s'enregistrer. L'ordre de déclaration des `define` détermine l'ordre de démarrage ; en pratique, le script du serveur écrit le token dans un dossier partagé (`/vagrant/confs/`) que le worker lit ensuite.

**G3.** Qu'est-ce qui, dans ton mini-projet du TP15, devra être remplacé par l'installation de K3s en p1 ?

**Ta réponse :**
<!-- non répondu au moment de la correction -->

**Verdict : à connaître.**
**Réponse :** Le `scripts/common.sh` du TP15 (`apt update`, `curl`, `touch /tmp/ready`) est un simple marqueur. En p1, il est remplacé par **deux scripts distincts** :
- `server.sh` : installation de K3s en mode serveur (avec `--node-ip=192.168.56.110` et l'interface Flannel forcée), puis mise à disposition du `kubeconfig` et de `kubectl` ;
- `worker.sh` : installation de K3s en mode agent avec `K3S_URL=https://192.168.56.110:6443` et `K3S_TOKEN=<token>`.

Les noms, hostnames, IP et ressources des deux VM restent identiques ; seule la partie installation change. La vérification n'est plus un fichier témoin mais `kubectl get nodes` (deux nodes `Ready`). Les détails seront vus en leçon 3.

---

## Mémo des commandes de la leçon

| Besoin | Commande |
|---|---|
| Créer un projet | `vagrant init <box>` |
| Vérifier la syntaxe | `vagrant validate` |
| Démarrer | `vagrant up` |
| État | `vagrant status` |
| Entrer dans la VM | `vagrant ssh [nom]` |
| Voir user/port/clé | `vagrant ssh-config [nom]` |
| Arrêter | `vagrant halt` |
| Suspendre / reprendre | `vagrant suspend` / `vagrant resume` |
| Rejouer le provisioning | `vagrant provision` ou `vagrant reload --provision` |
| Détruire | `vagrant destroy -f` |
| Lister les boxes | `vagrant box list` |
| Ajouter une box | `vagrant box add <box>` |
| Voir les ports | `vagrant port [nom]` |

---

Quand tu as terminé les TP et répondu aux questions : envoie-moi **« Leçon 2 terminée »** avec ton journal. Je corrigerai dans ce fichier, puis nous passerons à la **leçon 3 : K3s** (installation serveur + agent, token, `kubectl`, et fin de la p1).
