# Lab Kubernetes

- [K8s 101](#k8s-101)
- [Deployer une application en yaml](#deployer-une-application)
- [Déployer avec Helm, avec ingress et certificat TLS](#déployer-avec-helm)
- [Mettre en place un CD avec ArgoCD](#utiliser-argocd)
- [Cloisonner et Filtrer avec les Network Policies](#mettre-en-place-un-network-policy)


## K8s 101

### Vérifier les outils sur votre terminal

A priori dans Code Spaces : 

```bash
kubectl version
helm version
```

### Récuperer un kubeconfig

L'animateur vous fournit les valeurs des variables `GRP` et `ENTROPY` :

```bash
./init.sh <GRP> <ENTROPY>
```

```bash
kubectl cluster-info
kubectl get nodes -o wide
```

### Creer un deploiement

```bash
kubectl create deployment hello-world --replicas=2 --image=stefanprodan/podinfo:latest  --port=9898
```

```bash
kubectl get deploy/hello-world
kubectl describe deployments hello-world
kubectl get replicasets
kubectl get pods -o wide --show-labels
```

Tuer un pod avec `kubectl delete pod` pour constater qu'un nouveau est crée en remplacement.

### Scaler un deploiement
```bash
kubectl scale deploy/hello-world --replicas=5
```

### Exposer un deploiement

```bash
kubectl expose deployment hello-world --type=LoadBalancer --name=my-service
```

```bash
kubectl get svc
```
Visiter l'@IP publique (sur le port TCP/9898)

Vérifions que le Load-balancing fonctionne :
```bash
 for i in {1..100} ; do curl -s @IP_pub_svc:9898 | jq ".hostname" ; done | sort | uniq -c
```
## Changer l'image d'un déploiement

```bash
kubectl set image deployment/hello-world podinfo=stefanprodan/podinfo:5.2.1
```

```bash
kubectl rollout status deploy/hello-world 
```

```bash
kubectl rollout history deploy/hello-world
```

## Deployer une application stateful avec pv/pvc

L'application est composée :
- d'un front-end web
- d'une base de donénes MySQL
- d'un `secret` pour le mdp de la DB
- de `persistent volumes` pour le stockage
- d'un service CLusterIP (non publié en `LoadBalancer` ou `NodePort`)

Creation d'un secret :

```bash
kubectl create secret generic mysql-pass --from-literal=password=monMDP
kubectl get secret
kubectl get secret mysql-pass -o json | jq '.data | map_values(@base64d)'
```

Déployer maintenant le backend :

```bash
kubectl apply -f  https://kubernetes.io/examples/application/wordpress/mysql-deployment.yaml
kubectl get pods
kubectl get svc
kubectl get pv
```

Déployer la partie frontend :
```bash
kubectl apply -f https://kubernetes.io/examples/application/wordpress/wordpress-deployment.yaml 
kubectl get pods
kubectl get svc
kubectl get pv
```

Testons :
- visiter l'application
- effacer le `pod` wordpress-mysql
- "*drainer*" le `Node` (avec `kubectl drain --delete-emptydir-data`) qui porte le `pod` wordpress-mysql


Cleanup :
```bash
kubectl delete --all deployment
kubectl delete --all svc
kubectl delete --all pvc
kubectl delete --all pv
kubectl delete --all secret
```


## Déployer avec `Helm` un `Ingress`

Installer un ingress-controler traefik via Helm :

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik --set ingressRoute.dashboard.enabled=true
```

On peut visualiser l'installation du chart ainsi :
```bash
helm ls
```

Demander à l'animateur de mettre à jour le record DNS  grp<GRP>.soat.work avec l’IP du LB nouvellement crée

**Une fois cela fait**, si vous visiter http://grp<GRP>.soat.work , vous obtiendrez une page 404 (normal)

## Déployer le chart Wordpress avec `Helm`

Installer l'application avec Helm :

```bash
helm version
helm repo add bitnami https://charts.bitnami.com/bitnami

helm search repo wordpress
```

La documentation des variables est ici : https://github.com/bitnami/charts/ 

On peut construire un fichier de variable [values.yaml](/values.yaml) ainsi (cf doc https://github.com/bitnami/charts/tree/master/bitnami/wordpress ) : remplacer `<GRP>` par la valeur adéquate.

** Une fois cela fait**, procédez :

```bash
 helm install  my-release -f values.yaml bitnami/wordpress --version 18.1.30
```
Visiter 
- le site http://grp<GRP>.soat.work
- la page d'admin http://grp<GRP>.soat.work/wp-admin
- le login est "user" et le mot de passe est obtenu ainsi :
```bash
kubectl get secret --namespace default my-release-wordpress -o jsonpath="{.data.wordpress-password}" | base64 -d
```
- remarquez que le plugin Woprdpress Akismet est installé et activé, comme précisé dans ![values.yaml](/values.yaml).

## Dashboard de l'Ingress Controler (Traeffik)
 Consultons le dashboard `Traefik` :

```bash
kubectl port-forward $(kubectl get pods --selector "app.kubernetes.io/name=traefik" --output=name | head -n 1) 9000:9000
```

Puis navigation sur http://127.0.0.1:9000/dashboard/#/ 

## Obtenir et déployer un certificat TLS avec `cert-manager`

Créer cert-manager 

```bash
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.4/cert-manager.yaml 
```

Créer un `cluster-issuer`  : 
```bash
kubectl create -f cluster-issuer.yaml
```

Modifier le <GRP> dans [mycert.yaml](/mycert.yaml) puis créer un certificat : 
```bash
kubectl create -f mycert.yaml
```

Au bout d’un moment  :
```bash
kubectl get certificate
NAME                 READY   SECRET               AGE
grp0.soat.work       True    scw-k8s-cert         11s
grp0.soat.work-tls   True    grp0.soat.work-tls   3m46s
```
Visiter https://grp<GRP>.soat.work et constater le certificat TLS.


## Utiliser ArgoCD

Installons la CLI d'`argocd` :

```bash
VERSION=$(curl -L -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v$VERSION/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

Puis déployons le
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl port-forward svc/argocd-server -n argocd 8080:443 > /dev/null 2>&1 &
```

Visiter http://localhost:8080

Connexion
Login : admin
Pwd :
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

```bash
argocd login localhost:8080
```

Ajout d’une application Web en Repo:

```bash
argocd app create improvedguestbook --repo https://github.com/srnfr/improved-guestbook-k8s-example.git --path guestbook --dest-server https://kubernetes.default.svc --dest-namespace default

```

Ajout d’une application `Redis` en `Helm` :

```bash
​argocd app create redis --project default \
  --repo https://charts.bitnami.com/bitnami  \
  --helm-chart redis \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default --revision '18.1.6' --values-literal-file 'https://raw.githubusercontent.com/srnfr/kubernetes-examples/frontend-with-env/guestbook/redis-values.yaml'
```

Application des évolutions

```bash
argocd app patch improvedguestbook --patch '{"spec": { "source": { "targetRevision": "redis-sentinel" } }}' --type merge
```

## Mettre en place un Network Policy