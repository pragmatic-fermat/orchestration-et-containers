# Lab Kubernetes


- [K8s 101](#k8s-101)
- [Deployer une application en yaml](#deployer-une-application-stateful-avec-pv/pvc)
- [Déployer avec Helm, avec ingress/api gateway et certificat TLS](#déployer-une-appli-en-https)
- [Ajuster les ressources des Pods à chaud (VPA)](#ajuster-les-ressources-des-pods-à-chaud-vpa)
- [Répartir les Pods sur les nœuds (anti-affinité et topology spread)](#répartir-les-pods-sur-les-nœuds-anti-affinité-et-topology-spread)
- [Sécuriser les Pods avec la Pod Security Admission](#sécuriser-les-pods-avec-la-pod-security-admission)
- [Mettre en place un CD avec ArgoCD](#utiliser-argocd)
- [Cloisonner et Filtrer avec les Network Policies](#mettre-en-place-un-network-policy)
- [Service Mesh with Linkerd](#service-mesh-linkerd)
- [Gateway API](#gateway-api)

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
IP_PUB=$(kubectl get service my-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

for i in {1..100} ; do curl -s $IP_PUB:9898 | jq ".hostname" ; done | sort | uniq -c
```
### Changer l'image d'un déploiement

```bash
kubectl set image deployment/hello-world podinfo=stefanprodan/podinfo:5.2.1
```

```bash
kubectl rollout status deploy/hello-world 
```

```bash
kubectl rollout history deploy/hello-world
```

### Implementer un Readyness check

Suivant [la doc de podinfo](https://github.com/stefanprodan/podinfo) , pour désactiver la `readyness`, se connecter dans un Pod et jouer :

```bash
curl http://127.0.0.1/readyz/disable
```

Patcher le déploiement

```bash
kubectl patch deployment hello-world --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/readinessProbe", "value": {"exec": {"command": ["podcli", "check", "http", "localhost:9898/readyz"]}, "failureThreshold": 3, "initialDelaySeconds": 3, "periodSeconds": 5, "successThreshold": 1, "timeoutSeconds": 3}}]'
```

## Deployer une application stateful avec pv/pvc

L'application est composée :
- d'un front-end web
- d'une base de données MySQL
- d'un `secret` pour le mdp de la DB
- de `persistent volumes` pour le stockage
- d'un service CLusterIP (non publié en `LoadBalancer` ou `NodePort`)

Creation d'un secret :

```bash
kubectl create secret generic mysql-pass --from-literal=password=monMDP
```

```bash
kubectl get secret
kubectl get secret mysql-pass -o json | jq '.data | map_values(@base64d)'
```

Déployer maintenant le backend :

```bash
kubectl apply -f https://kubernetes.io/examples/application/wordpress/mysql-deployment.yaml
```

```bash
kubectl get pods
kubectl get svc
kubectl get pv
```

Déployer la partie frontend :
```bash
kubectl apply -f https://kubernetes.io/examples/application/wordpress/wordpress-deployment.yaml
```

```bash
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

## Déployer une appli en HTTPS

### Déployer  un Ingress avec helm (obsolète)

Installer un ingress-controler traefik avec helm :

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik --set ingressRoute.dashboard.enabled=true
```

On peut visualiser l'installation du chart ainsi :
```bash
helm ls
```
L'adresse IP publique du LoadBalancer associé au service traefik est visible :
```bash
kubectl get svc traefik
```

Demander à l'animateur de mettre à jour le record DNS  grp${GRP}.soat.work avec l’IP du LB nouvellement crée

**Une fois cela fait** , si vous visitez http://grp${GRP}.soat.work , vous obtiendrez une page 404 (normal)

## Déployer une API Gateway avec helm (new)

Préciser votre numéro de groupe dans la variable GRP 

```bash
GRP=X
```

et instancier une API Gateway

```bash
curl -s https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/gateway-api.yaml | sed "s/GRP/$GRP/" | kubectl apply -f -
```

### Déployer le chart Wordpress avec `Helm`

Installer l'application avec Helm :

```bash
helm version
```

La documentation du chart Helm Wordpress de Bitnami (y compris ses variables) est accessible [ici](https://github.com/bitnami/charts/) 

On peut construire un fichier de variable [values.yaml](/values.yaml) ainsi (cf doc https://github.com/bitnami/charts/tree/master/bitnami/wordpress ) : remplacer `<GRP>` par la valeur adéquate.

**Une fois cela fait** , procédez :

Si vous utilisez Gateway API 

```bash
rm -f values.yaml
curl -s https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/values-gateway-api.yaml -o values.yaml
```

*OU* si vous utilisez Nginx Ingress 

```bash
rm -f values.yaml
curl -s https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/values.yaml -o values.yaml
```

Pour configure le bon GRP :

```bash
sed -i "s/GRP/$GRP/" values.yaml
```

```bash
VER="18.1.30"
VER="29.2.0"
helm install my-release -f values.yaml \
 --version $VER \
 --set image.repository=bitnamilegacy/wordpress \
 --set volumePermissions.image.repository=bitnamilegacy/os-shell \
 --set metrics.image.repository=bitnamilegacy/apache-exporter \
 --set global.security.allowInsecureImages=true \
  --set mariadb.image.repository=bitnamilegacy/mariadb \
 --set mariadb.volumePermissions.image.repository=bitnamilegacy/os-shell \
 oci://registry-1.docker.io/bitnamicharts/wordpress
```

Visiter 
- le site http://grp${GRP}.soat.work
- la page d'admin http://grp${GRP}.soat.work/wp-admin
- le login est "user" et le mot de passe est obtenu ainsi :

```bash
kubectl get secret --namespace default my-release-wordpress -o jsonpath="{.data.wordpress-password}" | base64 -d
```
- remarquez que le plugin Woprdpress Akismet est installé et activé, comme précisé dans [values.yaml](/values.yaml).

### Dashboard de l'Ingress Controler (Traefik)
 Consultons le dashboard `Traefik` :

```bash
kubectl port-forward $(kubectl get pods --selector "app.kubernetes.io/name=traefik" --output=name | head -n 1) 8282:8080
```

Puis navigation sur http://127.0.0.1:8282/dashboard/#/ 

### Obtenir et déployer un certificat TLS avec `cert-manager`

Créer `cert-manager`

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.19.4 \
  --set crds.enabled=true \
  --set extraArgs="{--enable-gateway-api}"
  
```

Créer un `cluster-issuer`  : 

- Si Nginx ingress :

```bash
rm -f cluster-issuer.yaml
curl -s https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/cluster-issuer.yaml -o cluster-issuer.yaml
```

- Ou bien si Gateway API

```bash
rm -f cluster-issuer.yaml
curl -s https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/cluster-issuer-gateway.yaml -o cluster-issuer.yaml
```

Puis

```bash
kubectl create -f cluster-issuer.yaml
```

Modifier le ${GRP} dans [mycert.yaml](https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/mycert.yaml) puis créer un certificat : 
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
Visiter https://grp${GRP}.soat.work et constater le certificat TLS.


## Ajuster les ressources des Pods à chaud (VPA)

Jusqu'à présent, pour changer les `requests`/`limits` d'un déploiement, il fallait patcher le déploiement : cela crée un nouveau `ReplicaSet` et les pods sont recréés (rollout).

Depuis Kubernetes 1.33, la fonctionnalité `InPlacePodVerticalScaling` est activée par défaut (beta) : on peut modifier les ressources d'un pod en place, sans redémarrer le conteneur. Le **Vertical Pod Autoscaler** (VPA) sait exploiter ce mécanisme avec son mode `InPlaceOrRecreate` : il recommande puis applique les nouvelles ressources automatiquement.

Pour cela, il faut deux briques, toutes deux des projets officiels Kubernetes, sans aucune spécificité DigitalOcean : la même procédure fonctionne sur Scaleway, OVH, GKE...

- le `metrics-server` : agrège les métriques CPU/mémoire des pods. Il est nécessaire au VPA, au HPA et à `kubectl top`.
- le `vertical-pod-autoscaler` : calcule les recommandations et les applique.

Prérequis : un cluster en 1.33 minimum.

```bash
kubectl version
```

État des lieux (9 octobre 2026) : la fonctionnalité est GA depuis Kubernetes 1.35, mais **DOKS la désactive côté control plane**, même sur un cluster en 1.37 : l'API server rejette le champ `resizePolicy` avec une erreur `strict decoding error: unknown field`, et le resize à chaud (à la main comme via le VPA en mode `InPlaceOrRecreate`) retombe sur une recréation des pods. Aucune demande de feature publique n'existe chez DigitalOcean à ce jour. À retester dans les mois prochains, par exemple avec :

```bash
kubectl explain deployment.spec.template.spec.containers.resources --recursive | grep resize
```

Si la commande liste `resizePolicy`, la fonctionnalité est disponible et les sections suivantes marchent telles quelles. En attendant, la démo reste valable sur DOKS en mode recréation des pods.

### Installer le metrics server

La plupart des clusters managés (DOKS en particulier) l'embarquent déjà :

```bash
kubectl top nodes
```

Si la commande répond, rien à faire. Sinon, installons-le avec son chart officiel :

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade -i metrics-server metrics-server/metrics-server --namespace kube-system
```

Vérification (après une à deux minutes, le temps que les métriques arrivent) :

```bash
kubectl top nodes
kubectl top pods -A
```

### Installer le Vertical Pod Autoscaler

On utilise le chart officiel du projet :

```bash
helm repo add autoscalers https://kubernetes.github.io/autoscaler
helm repo update
helm upgrade -i vpa autoscalers/vertical-pod-autoscaler --version 0.13.0 --namespace vpa --create-namespace
```

```bash
kubectl get pods -n vpa
kubectl get crd verticalpodautoscalers.autoscaling.k8s.io
```

On doit trouver trois composants :

- `vpa-admission-controller` : webhook qui injecte les ressources recommandées à la création des pods
- `vpa-recommender` : calcule les recommandations à partir des métriques du `metrics-server`
- `vpa-updater` : applique les changements selon le mode choisi dans l'objet `VPA`

### Préparer un déploiement de démonstration

Reprenons `podinfo`, avec des ressources volontairement sous-dimensionnées.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-vpa
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-vpa
  template:
    metadata:
      labels:
        app: demo-vpa
    spec:
      containers:
      - name: podinfo
        image: stefanprodan/podinfo:latest
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 50m
            memory: 32Mi
          resizePolicy:
          - resourceName: cpu
            restartPolicy: NotRequired
          - resourceName: memory
            restartPolicy: NotRequired
```

```bash
kubectl apply -f https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/demo-vpa.yaml
```

Si votre cluster supporte le resize in place (la feature gate `InPlacePodVerticalScaling`, bêta activée par défaut depuis Kubernetes 1.33), on peut ajouter aux ressources du conteneur un bloc `resizePolicy` qui autorise CPU et mémoire à être redimensionnés sans redémarrage du conteneur :

```yaml
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 50m
              memory: 32Mi
            resizePolicy:
            - resourceName: cpu
              restartPolicy: NotRequired
            - resourceName: memory
              restartPolicy: NotRequired
```

Pour savoir si c'est supporté, interrogeons l'API :

```bash
kubectl explain deployment.spec.template.spec.containers.resources --recursive | grep resize
```

Certains clusters managés désactivent la gate (c'est le cas de DOKS, y compris en 1.37) : le champ `resizePolicy` est alors rejeté avec une erreur `strict decoding error: unknown field ... resizePolicy`, et les sections suivantes retombent sur un comportement de recréation des pods au lieu du resize à chaud.

Relevons l'état initial (heure de démarrage et ressources des pods) :

```bash
kubectl get pods -l app=demo-vpa -o custom-columns='NAME:.metadata.name,START:.status.startTime,RESTARTS:.status.containerStatuses[0].restartCount,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory'
```

### Le comportement historique : un rollout

Changeons les ressources côté déploiement :

```bash
kubectl set resources deployment/demo-vpa --limits=cpu=100m
kubectl rollout status deployment/demo-vpa
```

Relançons la commande précédente : les pods ont été recréés, l'heure de démarrage a changé. Remettons le déploiement dans son état initial :

```bash
kubectl set resources deployment/demo-vpa --limits=cpu=50m
kubectl rollout status deployment/demo-vpa
```

### Le resize à chaud, à la main

Patchons directement un pod (nécessite `kubectl` en 1.33 minimum) :

```bash
POD=$(kubectl get pods -l app=demo-vpa -o jsonpath='{.items[0].metadata.name}')
kubectl patch pod $POD --type=merge -p '{"spec":{"containers":[{"name":"podinfo","resources":{"limits":{"cpu":"200m"}}}]}}'
```

```bash
kubectl get pod $POD -o custom-columns='NAME:.metadata.name,START:.status.startTime,RESTARTS:.status.containerStatuses[0].restartCount,CPU_LIM:.spec.containers[0].resources.limits.cpu'
```

Le pod n'a pas redémarré (`RESTARTS` reste à 0, l'heure de démarrage est inchangée), mais sa limite CPU est passée à 200m. On peut le constater aussi dans les events :

```bash
kubectl describe pod $POD
```

Sur un cluster où la gate `InPlacePodVerticalScaling` est désactivée (voir plus haut), ce patch est rejeté par l'API server : le resize à chaud à la main n'est pas possible, il faut passer par un `rollout`.

### Laisser le VPA faire : mode Off puis InPlaceOrRecreate

Commençons par observer ce que recommande le VPA, sans rien appliquer (mode `Off`) :

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: demo-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: demo-vpa
  updatePolicy:
    updateMode: "Off"
```

```bash
kubectl apply -f https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/vpa-demo-vpa.yaml
```

Au bout de quelques minutes (le temps que le `recommender` analyse les métriques) :

```bash
kubectl describe vpa demo-vpa
```

La section `Recommendation` montre la cible (`target`) et les bornes (`lowerBound`/`upperBound`) calculées à partir de l'usage réel.

Passons maintenant en mode `InPlaceOrRecreate` :

```bash
kubectl patch vpa demo-vpa --type=merge -p '{"spec":{"updatePolicy":{"updateMode":"InPlaceOrRecreate"}}}'
```

Observons :

```bash
kubectl get pods -l app=demo-vpa -w
```

Sur un cluster qui supporte le resize in place, rien ne change : aucun pod redémarré, pas de nouveau `ReplicaSet`. Sur un cluster où la gate est désactivée, on voit au contraire les pods être recréés. Dans les deux cas, au bout de quelques minutes, les ressources des pods ont bien été augmentées :

```bash
kubectl get pods -l app=demo-vpa -o custom-columns='NAME:.metadata.name,START:.status.startTime,RESTARTS:.status.containerStatuses[0].restartCount,CPU_REQ:.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory,MEM_LIM:.spec.containers[0].resources.limits.memory'
```

Quelques précisions :

- sur un cluster où la gate `InPlacePodVerticalScaling` est active, augmenter les ressources se fait sans coupure ; une *diminution* de la mémoire nécessite le redémarrage du conteneur (le mode `InPlaceOrRecreate` retombe alors sur un comportement `Recreate`)
- sur un cluster où la gate est désactivée (DOKS par exemple), le mode `InPlaceOrRecreate` se comporte comme `Recreate` : les pods sont recréés avec les nouvelles ressources, on le voit dans la sortie de `kubectl get pods -w` (nouveaux pods, heure de démarrage réinitialisée)
- le resize in place se fait sur le même nœud : il faut de la capacité disponible sur celui-ci, sinon la modification échoue
- en mode `Off`, le VPA ne fait que recommander ; les modes `Initial` (ressources fixées à la création seulement) et `Recreate` (recréation des pods) restent disponibles

Cleanup :

```bash
kubectl delete vpa demo-vpa
kubectl delete deployment demo-vpa
```

## Répartir les Pods sur les nœuds (anti-affinité et topology spread)

Par défaut, le scheduler place les pods là où il y a de la place, sans garantir leur répartition. Si tous les replicas d'un déploiement atterrissent sur le même nœud et que celui-ci tombe, l'application disparaît d'un coup. Kubernetes offre deux mécanismes pour contrôler cette répartition :

- l'**anti-affinité de pods** : contrainte d'affinité classique entre pods, à déclarer sur chaque pod
- les **topology spread constraints** : un mécanisme dédié à la répartition, plus expressif, apparu pour ça

Observons d'abord les nœuds du cluster et leurs labels de topologie :

```bash
kubectl get nodes -L kubernetes.io/hostname -L topology.kubernetes.io/zone
```

Chaque nœud porte deux labels utiles : `kubernetes.io/hostname` (le nœud lui-même) et `topology.kubernetes.io/zone` (la zone de disponibilité). On peut répartir les pods sur l'un ou l'autre selon ce qu'on veut tolérer : la perte d'un nœud ou la perte d'une zone entière.

### Le comportement par défaut

Déployons six replicas sans contrainte, pour voir ce que donne le hasard :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-topology
spec:
  replicas: 6
  selector:
    matchLabels:
      app: demo-topology
  template:
    metadata:
      labels:
        app: demo-topology
    spec:
      containers:
      - name: podinfo
        image: stefanprodan/podinfo:latest
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
```

```bash
kubectl apply -f https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/demo-topology.yaml
```

```bash
kubectl get pods -l app=demo-topology -o custom-columns='NAME:.metadata.name,NODE:spec.nodeName'
```

Sur un petit cluster, il n'est pas rare de voir plusieurs pods (parfois tous) sur le même nœud.

### Répartir avec topologySpreadConstraints

Ajoutons une contrainte de répartition : au plus un pod d'écart (`maxSkew: 1`) entre les nœuds, sinon le pod reste en attente (`DoNotSchedule`) :

```yaml
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: demo-topology
```

Le manifeste `demo-topology-spread.yaml` du dépôt reprend le même déploiement avec cette contrainte ajoutée. Remplaçons le déploiement :

```bash
kubectl delete deployment demo-topology
kubectl apply -f https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/demo-topology-spread.yaml
```

Observons la répartition :

```bash
kubectl get pods -l app=demo-topology -o custom-columns='NAME:.metadata.name,NODE:spec.nodeName'
```

Les pods sont désormais équirépartis sur les nœuds disponibles. Quelques précisions :

- `topologyKey` choisit le domaine de répartition : `kubernetes.io/hostname` répartit entre les nœuds, `topology.kubernetes.io/zone` entre les zones (le bon réflexe sur un cluster multi-zones comme GKE, EKS ou Kosmos)
- `maxSkew` fixe l'écart maximum autorisé entre le domaine le plus chargé et le moins chargé ; 1 est la valeur courante
- `whenUnsatisfiable: DoNotSchedule` bloque le pod tant que la contrainte n'est pas satisfaisable ; `ScheduleAnyway` en fait une préférence (le scheduler essaie, mais place le pod quoi qu'il arrive)

Variante avec l'anti-affinité, qui force cette fois un seul pod par nœud :

```yaml
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: demo-topology
            topologyKey: kubernetes.io/hostname
```

Notons la différence de comportement si le cluster a moins de nœuds que de replicas : avec cette anti-affinité stricte, les pods surnuméraires restent en `Pending` (au plus un pod par nœud), alors que la topology spread constraint les laisse se placer avec le skew autorisé. La version `preferredDuringSchedulingIgnoredDuringExecution` de l'anti-affinité est l'équivalent souple de `ScheduleAnyway`.

En pratique : l'anti-affinité stricte pour les composants critiques qu'on veut isoler (un pods par nœud), les topology spread constraints pour la répartition générale des replicas.

Cleanup :

```bash
kubectl delete deployment demo-topology
```

## Sécuriser les Pods avec la Pod Security Admission

Historiquement, la sécurité des pods passait par la Pod Security Policy (PSP), supprimée de Kubernetes en 1.25 et remplacée par la **Pod Security Admission** (PSA). C'est un admission controller intégré, sans CRD ni webhook à installer : on configure la politique par des labels sur les namespaces.

Trois niveaux de sécurité :

- `privileged` : aucune restriction (niveau par défaut)
- `baseline` : bloque les usages connus pour élever les privilèges (hostNetwork, hostPath, privileged...)
- `restricted` : suit les bonnes pratiques durcies (pas de root, seccomp, pas d'escalade de privilèges)

Et trois modes d'application, combinables :

- `enforce` : rejette les pods non conformes
- `audit` : laisse passer mais journalise la violation dans les audit logs
- `warn` : laisse passer mais affiche un message d'avertissement à l'utilisateur

Créons un namespace configuré en `restricted` :

```bash
kubectl create namespace demo-psa
kubectl label namespace demo-psa \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
```

### Un pod non conforme est rejeté

Le fichier `demo-psa-non-conforme.yaml` déclare un pod qui autorise l'escalade de privilèges :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: psa-non-conforme
  namespace: demo-psa
spec:
  containers:
  - name: podinfo
    image: stefanprodan/podinfo:latest
    securityContext:
      allowPrivilegeEscalation: true
```

```bash
kubectl apply -f https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/demo-psa-non-conforme.yaml
```

L'API server refuse la création avec une erreur explicite qui détaille chaque règle violée :

```
Error from server (Forbidden): error when creating "demo-psa-non-conforme.yaml":
pods "psa-non-conforme" is forbidden: violates PodSecurity "restricted:latest":
allowPrivilegeEscalation != false (container "podinfo" must set securityContext.allowPrivilegeEscalation=false)...
```

### Un pod conforme passe

Le fichier `demo-psa-conforme.yaml` corrige ce qui bloque le niveau `restricted` : exécution sans root, seccomp `RuntimeDefault`, pas d'escalade de privilèges, capacités Linux toutes retirées :

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: psa-conforme
  namespace: demo-psa
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: podinfo
    image: stefanprodan/podinfo:latest
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
```

```bash
kubectl apply -f https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/demo-psa-conforme.yaml
```

```bash
kubectl get pod psa-conforme -n demo-psa
```

Le pod démarre. Remarquons que le pod se conforme au niveau `restricted` : c'est le niveau exigé par la plupart des chart Helm et opérateurs modernes, et le niveau par défaut que la Kubernetes community recommande pour les namespaces applicatifs.

Quelques précisions :

- la politique s'applique au moment de la création et à chaque mise à jour du pod ; les pods déjà en place ne sont jamais évincés
- les labels de version (`pod-security.kubernetes.io/enforce-version`) permettent de figer la politique sur une version de Kubernetes précise plutôt que `latest`, pour éviter les surprises lors des upgrades de cluster
- les namespaces du système (`kube-system`...) sont exemptés par défaut
- pour un pod issu d'un contrôleur (Deployment, DaemonSet...), c'est le template du pod qui est évalué : un Deployment non conforme est rejeté en entier dès le `kubectl apply`

Cleanup :

```bash
kubectl delete namespace demo-psa
```

## Utiliser ArgoCD

Installons la CLI d'`argocd` :

```bash
VERSION=$(curl -L -s https://raw.githubusercontent.com/argoproj/argo-cd/stable/VERSION)
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v$VERSION/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

Puis déployons ArgoCD dans le cluster 
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts

kubectl port-forward svc/argocd-server -n argocd 8080:443 > /dev/null 2>&1 &
```

Visiter http://localhost:8080

Connexion :
- Login : admin
- Pwd :

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

```bash
argocd login localhost:8080
```

Ajout d’une application Web en Repo:

```bash
argocd app create improvedguestbook --repo https://github.com/pragmatic-fermat/better-guestbook.git --path guestbook --dest-server https://kubernetes.default.svc --dest-namespace default
```

Ajout d’une application `Redis` en `Helm` :

```
argocd repo add registry-1.docker.io/bitnamicharts \
  --type helm --enable-oci \
  --name bitnami-oci
  
argocd app create redis --project default \
  --repo registry-1.docker.io/bitnamicharts \
  --helm-chart redis \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --revision '18.1.6' \
  --values-literal-file 'https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/redis-values.yaml'
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

Puis les redis-follower :

-  le deploiement redis-follower manquant
```shell
kubectl apply -f redis-follower-deployment.yaml
```

- et son service

```shell
kubectl apply -f redis-follower-service.yaml
```

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



### Redaction d'une NetPolicy

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

## Service Mesh Linkerd

### Installation

Au moment où je mets à jour ce lab, la dernière version stable de Linkerd est la 2.20 (annoncée en juin 2026) et la CLI edge la plus récente est la edge-26.10.1. Le projet amont ne publie plus lui-même de releases stable : celles-ci sont désormais fournies par des vendeurs (Buoyant Enterprise). Pour un atelier, j'utilise donc le canal edge, qui reste le canal officiel du projet.

Je récupère la CLI :
```
curl -sL https://run.linkerd.io/install-edge | sh
export PATH=$PATH:$HOME/.linkerd2/bin
linkerd version
```

Linkerd requiert les CRD Gateway API. Chez DigitalOcean ils sont déjà installés (avec Cilium), sinon :
```
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml
```

Installation du plan de contrôle :
```
linkerd check --pre
```

```
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
```

Vérifions le plan de contrôle, puis installons l'extension viz :
```
linkerd check
```

```
linkerd viz install | kubectl apply -f -
```

```
linkerd viz check
kubectl -n linkerd get deploy
linkerd viz dashboard &
```

Puis
```
kubectl apply -f https://run.linkerd.io/emojivoto.yml
```

```
kubectl -n emojivoto get all
```

### Visite du site web

```
kubectl -n emojivoto port-forward svc/web-svc 8181:80
```
Maintenant l'injection (des sidecar proxies) par Linkerd. La méthode recommandée est l'annotation `linkerd.io/inject: enabled`, sur le namespace ou sur chaque déploiement. Depuis la 2.20, le proxy tourne par défaut en conteneur d'init (native sidecar) :
```
kubectl annotate ns emojivoto linkerd.io/inject=enabled
kubectl -n emojivoto rollout restart deployment
```

L'équivalent en transformation de manifeste reste possible avec `linkerd inject`, qui ne fait qu'ajouter cette annotation :
```
kubectl get -n emojivoto deploy -o yaml \
  | linkerd inject - \
  | kubectl apply -f -
```

Puis
```
linkerd -n emojivoto check --proxy
```

Débugger dans (http://127.0.0.1:58756/namespaces/emojivoto)
 Namespace > emojivoto > deployment/web pourquoi “Poop” génère des échecs.

```
 kubectl describe po/web-66c469c7b9-lzq9v -nemojivoto
```
Permet de voir 2 containers dans le même pod

```
kubectl logs po/web-66c469c7b9-lzq9v web-svc -nemojivoto
```

Permet de voir les logs du container web-svc dans le pod web

## Gateway API

Chez DigitalOcean les CRD Gateway API sont déjà installés (avec Cillium)

Déployons une application demo
```
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.11/samples/bookinfo/platform/kube/bookinfo.yaml
```

Déployons une Gateway
```
kubectl apply -f https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/do-cilium-gateway.yml
```

Nous obtenons l'IP Publique et le nom DNS en nip.io  :
```
IPPUB=${kubectl get svc  cilium-gateway-cilium-gateway-http  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'}
FQDN="${IPPUB}.nip.io"
echo $FQDN
```

Déployons une route en insérant le FQDN :
```
curl -s https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/do-httproute.yaml | sed "s/FQDN/${FQDN}/" | kubectl apply -f -
```

Vérifions
```
kubectl get httproute
```
Puis 
```
curl --fail -s http://${FQDN}/details/1 | jq
```
Et
```
curl -v -H 'magic: foo' http://${FQDN}\?great\=example
```

Ajoutons maintenant le certificat
```
kubectl apply -f https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/cluster-issuer-gateway.yaml
curl -s https://raw.githubusercontent.com/pragmatic-fermat/orchestration-et-containers/refs/heads/main/certificate-bookinfo.yaml | sed "s/FQDN/${FQDN}/" | kubectl apply -f -
```

Vérifions
```
kubectl get certificate -n default
kubectl describe certificate bookinfo-gw-cert -n default
kubectl get secret bookinfo-gw-tls -n default
kubectl get httproute -n default
```

### Cleanup

Je retire d'abord les extensions, puis le plan de contrôle (après avoir supprimé les annotations d'injection et relancé les déploiements pour retirer les proxies du data plane) :
```
linkerd viz uninstall | kubectl delete -f -
linkerd uninstall | kubectl delete -f -
```
