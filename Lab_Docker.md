
## Verifier l'installation de Docker

```bash
docker version
docker compose version
```

## Lancer interactivement un container

```bash
docker run -it ubuntu
```

Executer :  `uname -a; exit`

Faire de même avec l'image `alpine`


## Exposer un container

```bash
docker run -p80:80 -d --name websrv nginx
```

## Inspecter un container

```bash
docker inspect websrv
```

## "Se connecter" dans un container

```bash
docker exec -ti websrv
```

## Builder une image

```bash
cat Dockerfile
```

```bash
docker build -t monimg .
```

```bash
docker run -it monimg
```

## Utiliser un volume

```bash
docker run -v htmldata:/usr/local/share/nginx -p 80:80 -d nginx
```

```bash
docker volume ls
```

```bash
docker volume inspect html_data
```

```bash
echo "</h1> Hello !</h1>" > /var/lib/docker/volumes/html_data/data/index.html
```

## Lancer un docker-compose

```bash
docker compose create
```

```bash
docker compose up -d
```

```bash
docker compose down
```
