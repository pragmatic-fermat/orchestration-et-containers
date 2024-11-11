# Demos Docker

Objectif : un aperçu des fonctionnalités de `docker`
- [Vérifier l'installation](#1verifier-linstallation-de-docker)
- [Lancer interactivement un container](#2lancer-interactivement-un-container)
- [Exposer un container](#3exposer-sur-le-réseau-un-container)
- [Inspecter un container](#4inspecter-un-container)
- [Se "*connecter*" dans un container](#5se-connecter-dans-un-container)
- [Builder une image](#6builder-une-image)
- [Utiliser un volume](#7utiliser-un-volume)
- [Lancer un `docker-compose`](#8lancer-un-docker-compose)



## 1.Verifier l'installation de Docker

Le moteur d'execution Docker est bien présent :
```bash
docker version
```

Le plugin `compose` est également bien installé :
```bash
docker compose version
```

Vous constatez que le programme `atop` n'est pas installé sur le host (c-a-d le Linux) :
```bash
atop
```

Inspectons justement ce Host (c-a-d serveur Linux sur lequel nous executrons plus tard des containeurs :
```bash
uname -a
lsb_release -a
cat /etc/debian_version
hostname
```

## 2.Lancer interactivement un container

```bash
docker run -it ubuntu
```
L'image `ubuntu` est téléchargée depuis hub.docker.io puis le container est crée : c'est un shell interactif sur la base d'une système de fichier ubuntu.

Executons :  
- `uname -a`
- `lsb_release -a`
- `hostname`
- `atop`

On peut même installer à l'intérieur du container ce fameux programme `atop` à l'aide du gestionnaire de package `apt`

- `apt update ; apt install -y atop`
- `atop -V`
- `exit`

Lancer à nouveau un container :
```bash
docker run -it ubuntu
```
- `hostname`
- `atop`
- `exit`

Vous constatez que atop n'est pas installé sur le host :
```bash
atop
```

Faire de même avec l'image `alpine` (le gestionnaire de package est `apk`)

## 3.Exposer sur le réseau un container

```bash
docker run -p80:80 -d --name websrv nginx
```
Dans notre environnement Code Spaces, un popup apparait :
![pop](/img/github4.png)

On peut visiter l'URL... du type https://didactic-train-v6vqr47g7rg6299p-80.app.github.dev/
(on peut la retrouver en cliquant sur la barre du bas sur l'icone en forme de pylone radio)


Lançons d'autres containers :
```bash
docker run -p81:80 -d --name websrv2 nginx
docker run -p82:9898 -d stefanprodan/podinfo
```

Nettoyons : arrêtons tous les containeurs
```bash
docker stop $(docker ps -a -q)
```

## 4.Inspecter un container

```bash
docker inspect websrv
```

Avec le parser JSON jq, on peut programmatiquement extraire les attributs du container :

```bash
docker inspect websrv | jq ".[].Created"
docker inspect websrv | jq ".[].NetworkSettings.Networks.bridge.IPAddress"
```

## 5."*Se connecter*" dans un container

C'est un abus de langage : on devrait plutot dire *"lancer un shell dans le contexte d'execution du container"* 
```bash
docker exec -ti websrv bash
```
En sortir (i.e `exit`)

## 6.Builder une image

Dans l'environnement CodeSpace, l'arborescence du repo est installée.
Inspectons le fichier Dockerfile :

```bash
cat ./Dockerfile
```

Construisons une image sur la base de ce Dockerfile :

```bash
docker build -t monimg .
```

Nous l'executions maintenant :
```bash
docker run -it monimg
```
Constatez que `atop` est installé nativement dans cette image.

## 7.Utiliser un volume


```bash
echo '</h1> Hello !</h1>' > ./html_data/index.html
```

```bash
docker run -v /workspaces/orchestration-et-containers/html_data:/usr/share/nginx/html -p 80:80 -d nginx
```

```bash
docker volume ls
```

```bash
docker volume inspect html_data
```
```bash
echo '</h1> Bye !</h1>' > ./html_data/index.html
```
Nettoyons :
```bash
docker stop $(docker ps -a -q)
```

## 8.Lancer un `docker-compose`

```bash
cat docker-compose.yml
```

```bash
docker compose create
```

```bash
docker compose up -d
```

```bash
docker compose down
```
