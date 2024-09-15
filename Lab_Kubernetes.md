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

### Mise en place d'une application Guestbook

Cloner le Guestbook PHP dans votre environnement  Github CodeSpaces dans un répertoire différent de votre racine :
```shell
pwd 
cd .. 
git clone https://github.com/GoogleCloudPlatform/kubernetes-engine-samples 
cd kubernetes-engine-samples/quickstarts/guestbook
```

L'architecture de l'appli Guestbook est décrite ici : ![](https://cloud.google.com/static/kubernetes-engine/images/guestbook_diagram.svg)

Créer le deploiement `redis-leader` :
```shell
kubectl apply -f redis-leader-deployment.yaml
```
.. et son service ClusterIP
```shell
kubectl apply -f redis-leader-service.yaml
```
Puis les redis-follower 

Déployer le deploiment redis-follower manquant :
```shell
kubectl apply -f redis-follower-deployment.yaml
```

.. et son service

```shell
kubectl apply -f redis-follower-service.yaml


Puis le frontend :

```shell
kubectl apply -f frontend-deployment.yaml
```

Vérifier que les replicas sont bien déployés :
```shell
kubectl get pods -l app=guestbook -l tier=frontend
```

Exposer le service `frontend` (c'est un LoadBalancer) :
```shell
kubectl apply -f frontend-service.yaml
```



### Redaction d'une NetPol

Créez un Network Policy (NP) en ingress qui :
* s'applique au composant `redis-leader` 
* qui permet l'accès depuis les  seuls `redis-follower` et les `frontend` (i.e aucun autre Pod ne peut y accéder)

Pour cela, utiliser :
* le [Network Policy Editor Cilium](https://editor.cilium.io/)
* le visualisateur [Orca](https://orca.tufin.io/netpol/)

Aidez-vous des labels appliqués sur les Pods :
```bash
kubectl get pods --show-labels
```
Voici une solution :

```yaml
## np-allow-from-redis-and-frontend.yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: allow-from-redis-and-frontend
spec:
  policyTypes:
  - Ingress
  podSelector:
    matchLabels:
      app: redis
      role: leader
      tier: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: guestbook
          tier: frontend
    - podSelector:
        matchLabels:
          app: redis
          role: follower
          tier: backend         
```

Vérifions que ce YAML est syntaxiquement correct :  

```shell
kubectl apply -f np-allow-from-redis-and-frontend.yaml --dry-run=client
```

Pour info, une autre syntaxe aurait pu être (pas strictement identique en terme d'exactitude):
```yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: allow-from-redis-and-frontend
spec:
  policyTypes:
  - Ingress
  podSelector:
    matchLabels:
      app: redis
      role: leader
      tier: backend
  ingress:
  - from:
    - podSelector:
        matchExpressions:
          - {key: app, operator: In, values: [guestbook,redis]} 
```

### Application de la Network Policy

Appliquer cette politique
```shell
kubectl apply -f np-allow-from-redis-and-frontend.yaml
```

Vérifier qu'elle est bien appliquée
```shell
kubectl get netpol -A
```

```shell
kubectl describe netpol/allow-from-redis-and-frontend -n default
```
Pour note , dans le cas alternatif d'écriture de la NP, on aurait :
```
% kubectl describe netpol
Name:         allow-from-redis-and-frontend
Namespace:    default
Created on:   2022-09-28 12:02:13 +0200 CEST
Labels:       <none>
Annotations:  <none>
Spec:
  PodSelector:     app=redis,role=leader,tier=backend
  Allowing ingress traffic:
    To Port: <any> (traffic allowed to all ports)
    From:
      PodSelector: app in (guestbook,redis)
  Not affecting egress traffic
  Policy Types: Ingress
```

### Vérification

Identifier sur quel Node tourne le `redis-leader` afin de déterminer le Pod cilium qui tourne sur ce même Node :

```shell
kubectl get pods -o wide -A
```

Un admin sophistiqué aurait directement executé :
```shell
kubectl get pods -o wide -ndefault -l role=leader
kubectl get pods -o wide -nkube-system -l app.kubernetes.io/name=cilium-agent
```

Lancer `cilium monitor` sur le Pod Cilium dans une fenêtre séparée :
```shell
 kubectl exec -it cilium-xxxxx -n kube-system -- cilium monitor --type drop

Press Ctrl-C to quit
level=info msg="Initializing dissection cache..." subsys=monitor
```
Dans une autre fenêtre de console, vérifier que `redis-leader` n'est plus accessible en créeant un Pod `debug-blue` (dans un namespace différent):

```shell
kubectl create ns blue
kubectl run debug-blue -it --rm --restart=Never --image=nicolaka/netshoot --namespace=blue
debug-blue# nmap -p 6379 -P0 redis-leader.default.svc
```

Ce qui donne ceci dans la fenetre initiale :
```
xx drop (Policy denied) flow 0x0 to endpoint 1333, identity 56671->25124: 10.244.0.58:37754 -> 10.244.0.225:6379 tcp SYN
xx drop (Policy denied) flow 0x0 to endpoint 1333, identity 56671->25124: 10.244.0.58:37756 -> 10.244.0.225:6379 tcp SYN
xx drop (Policy denied) flow 0x0 to endpoint 1333, identity 7391->25124: 10.244.0.60:39208 -> 10.244.0.225:6379 tcp SYN
xx drop (Policy denied) flow 0x6e59a6c7 to endpoint 1333, identity 7391->25124: 10.244.0.212:43320 -> 10.244.0.225:6379 tcp SYN
^C
Received an interrupt, disconnecting from monitor...
```

Vérifier que le svc `redis-leader` est bien accessible depuis le Pod `redis-follower`
```shell
kubectl exec -it redis-follower-xxxx -- redis-cli -h redis-leader.default.svc -p 6379
```
