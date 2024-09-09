# Lab Kubernetes

- [K8s 101](#k8s-101)
- [Deployer une application en yaml](#deployer-une-application)
- [Déployer avec Helm, avec ingress et certificat TLS](#déployer-avec-helm)
- [Mettre en place un CD avec ArgoCD](#utiliser-argocd)
- [Cloisonner et Filtrer avec les Network Policies](#mettre-en-place-un-network-policy)


## K8s 101

### Vérifier les outils

```bash
kubectl version
helm version
```

### Récuperer un kubeconfig

L'animateur vous fournit les valeurs des variables `GRP` et `ENTROPY` :

```bash
chmod a+x init.sh
./init.sh <GRP> <ENTROPY>
```

```bash
kubectl cluster-info
kubectl get nodes
```

### Creer un deploiement

```bash
kubectl create deployment hello-world --replicas=2 --image=stefanprodan/podinfo:latest  --port=9898
```

```bash
kubectl get deploy/hello-world
kubectl describe deployments hello-world
kubectl get replicasets
```

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

## Deployer une application


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
```

Cleanup :
```bash
kubectl delete --all deployment
kubectl delete --all svc
kubectl delete --all pv
```


## Déployer avec Helm

Installer un ingress-controler traefik via Helm :

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik
```

Mettre à jour le record DNS  k8s-<GRP>.soat.work avec l’IP du LB crée

Installer l'application avec Helm :
```bash
helm version
helm repo add bitnami https://charts.bitnami.com/bitnami

helm search repo wordpress
```

La documentation des variables est ici : https://github.com/bitnami/charts/ 

On peut construire un fichier de variable [values.yaml](/values.yaml) ainsi (cf doc https://github.com/bitnami/charts/tree/master/bitnami/wordpress ) : remplacer `<GRP>` par la valeur adéquate.
```bash
 helm install  my-release -f values.yaml bitnami/wordpress --version 18.1.30
```

 Dashboard Traefik :

```bash
kubectl port-forward $(kubectl get pods --selector "app.kubernetes.io/name=traefik" --output=name | head -n 1) 9000:9000
```

Puis navigation sur http://127.0.0.1:9000/dashboard/#/ 

Créer cert-manager 
```bash
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.4/cert-manager.yaml 
```

Créer un cluster-issuer  : 
```bash
kubectl create -f cluster-issuer.yaml
```

Modifier le `grp` dans [mycert.yaml](/mycert.yaml) puis créer un certificat : 
```bash
kubectl create -f mycert.yaml
```

Au bout d’un moment 
```bash
+ kubectl get certificate
NAME                    READY   SECRET                  AGE
k8s-grp.soat.work   True    k8s-grp.soat.work   6m1s
```

## Utiliser ArgoCD

Installons `argocd` :
```bash
VERSION=$(curl -L -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v$VERSION/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

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

Ajout d’une application WEB en REPO:

```bash
argocd app create improvedguestbook --repo https://github.com/srnfr/improved-guestbook-k8s-example.git --path guestbook --dest-server https://kubernetes.default.svc --dest-namespace default

argocd app patch improvedguestbook --patch '{"spec": { "source": { "targetRevision": "redis-sentinel" } }}' --type merge
```

Ajout d’une application REDIS en HELM

```bash
​​argocd app create redis --project default \
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