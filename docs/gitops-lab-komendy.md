# GitOps Lab - EKS, Helm, Argo CD, Jenkins i ECR

## 1. Środowisko i repozytorium

Przejście do repozytorium:

```bash
cd gitops-demo
```

Sprawdzenie stanu Git:

```bash
git status
git branch --show-current
git remote -v
```

---

## 2. Helm chart dla Nginx

### Utworzenie chartu

```bash
helm create nginx
```

Struktura:

```bash
find nginx -maxdepth 2 -type f
```

Walidacja:

```bash
helm lint nginx
helm template nginx ./nginx
```

Szybkie sprawdzenie generowanych zasobów:

```bash
helm template nginx ./nginx | grep -E "kind:|name:"
```

Sprawdzenie obrazu:

```bash
helm template nginx ./nginx | grep "image:"
```

---

## 3. Git

Dodanie Helm chartu:

```bash
git add nginx/
git commit -m "Add nginx helm chart"
git push origin main
```

Po zmianach `values.yaml`:

```bash
git add nginx/values.yaml
git commit -m "Configure nginx Helm values"
git push origin main
```

Aktualizacja obrazu:

```bash
git add nginx/values.yaml
git commit -m "Update image"
git push origin main
```

Jeżeli remote ma nowsze zmiany:

```bash
git pull
git push origin main
```

### Problem z `.git/index.lock`

Sprawdzenie procesów Git:

```bash
ps -ef | grep '[g]it'
```

Jeżeli żaden proces Git nie działa:

```bash
rm -f .git/index.lock
```

---

## 4. Kubernetes

### Podstawowe sprawdzenie klastra

```bash
kubectl config current-context
kubectl get nodes
kubectl get pods -A
kubectl get deployment,service
```

Więcej informacji:

```bash
kubectl get pods -A -o wide
```

### Deployment

```bash
kubectl get deployment nginx-demo -o yaml
kubectl get deployment nginx-demo --show-labels
```

Sprawdzenie etykiet Helm:

```bash
kubectl get deployment nginx-demo -o yaml | grep -E "app.kubernetes.io|argocd"
```

### Obrazy używane przez Pody

```bash
kubectl get pods -A -o yaml | grep "image:" -A3
```

---

## 5. Budowanie obrazu za pomocą Podman

Sprawdzenie:

```bash
podman --version
```

Uruchomienie maszyny Podman:

```bash
podman machine init
podman machine start
```

Test:

```bash
podman run hello-world
```

### Build aplikacji

Wersja 1.0:

```bash
podman build -t gitops-demo:1.0 .
```

Uruchomienie lokalne:

```bash
podman run -d \
  --name gitops-demo \
  -p 8081:80 \
  localhost/gitops-demo:1.0
```

Kolejna wersja:

```bash
podman build -t gitops-demo:2.0 .
```

---

## 6. AWS

Sprawdzenie aktualnej tożsamości AWS:

```bash
aws sts get-caller-identity
```

Region używany w labie:

```text
eu-west-1
```

---

## 7. Amazon ECR

### Repozytorium aplikacji

Utworzenie repozytorium:

```bash
aws ecr create-repository \
  --repository-name gitops-demo \
  --region eu-west-1
```

Logowanie z Podman do ECR:

```bash
aws ecr get-login-password --region eu-west-1 | \
podman login \
  --username AWS \
  --password-stdin \
  211007024623.dkr.ecr.eu-west-1.amazonaws.com
```

Tagowanie i push:

```bash
podman tag \
  localhost/gitops-demo:1.0 \
  211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-demo:1.0

podman push \
  211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-demo:1.0
```

Dla kolejnej wersji:

```bash
podman tag \
  localhost/gitops-demo:2.0 \
  211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-demo:2.0

podman push \
  211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-demo:2.0
```

GitOps flow:

```text
Build image
    ↓
Tag
    ↓
Push do ECR
    ↓
zmiana nginx/values.yaml
    ↓
git commit
    ↓
git push
    ↓
Argo CD
    ↓
Kubernetes Deployment
```

---

## 8. Argo CD

### Instalacja

```bash
kubectl create namespace argocd
kubectl apply \
  -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Sprawdzenie:

```bash
kubectl get pods -n argocd
```

---

## 9. Argo CD Application

Manifest laba:

```text
argocd/nginx-demo.yaml
```

Zastosowanie i sprawdzenie:

```bash
kubectl apply -f argocd/nginx-demo.yaml
kubectl get applications -n argocd
kubectl get application nginx-demo -n argocd -o yaml
```

Sprawdzenie polityki synchronizacji:

```bash
kubectl get application nginx-demo -n argocd -o yaml | \
grep syncPolicy -A5
```

---

## 10. Argo CD admin secret

Bezpieczny odczyt hasła:

```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
echo
```

> Nie zapisuj odszyfrowanych haseł w dokumentacji ani repozytorium Git.

---

## 11. Jenkins Helm repository

```bash
helm repo add jenkins https://charts.jenkins.io
helm repo update
helm search repo jenkins/jenkins
```

Domyślne wartości persistence:

```bash
helm show values jenkins/jenkins | grep "persistence:" -A12
```

---

## 12. Instalacja Jenkins

```bash
kubectl create namespace jenkins
helm install jenkins jenkins/jenkins \
  -n jenkins \
  --set persistence.enabled=false
```

Sprawdzenie:

```bash
kubectl get pods -n jenkins
```

---

## 13. Jenkins admin password

Preferowany sposób:

```bash
kubectl exec \
  --namespace jenkins \
  -it svc/jenkins \
  -c jenkins \
  -- /bin/cat /run/secrets/additional/chart-admin-password
```

Alternatywnie:

```bash
kubectl get secret jenkins -n jenkins -o yaml
```

> Nie zapisuj rzeczywistego hasła w dokumentacji.

---

## 14. Storage/PVC troubleshooting

```bash
kubectl get pvc -A
kubectl get pv
kubectl get storageclass
kubectl get pvc -n jenkins -o wide
kubectl describe pvc -n jenkins
kubectl get storageclass -o yaml
```

Ustawienie `gp2` jako domyślnej StorageClass, jeśli jest to potrzebne w środowisku laba:

```bash
kubectl patch storageclass gp2 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

---

## 15. AWS EBS CSI Driver

Sprawdzenie add-on:

```bash
aws eks describe-addon \
  --cluster-name gitops-lab \
  --addon-name aws-ebs-csi-driver \
  --region eu-west-1
```

Sprawdzenie podów i logów:

```bash
kubectl get pods -n kube-system | grep ebs
kubectl logs \
  -n kube-system \
  -l app.kubernetes.io/name=aws-ebs-csi-driver \
  --all-containers=true \
  --tail=50
kubectl get pods \
  -n kube-system \
  -l app.kubernetes.io/name=aws-ebs-csi-driver \
  -o wide
```

Service account role:

```bash
aws eks describe-addon \
  --cluster-name gitops-lab \
  --addon-name aws-ebs-csi-driver \
  --query addon.serviceAccountRoleArn \
  --region eu-west-1
```

OIDC issuer klastra:

```bash
aws eks describe-cluster \
  --name gitops-lab \
  --region eu-west-1 \
  --query cluster.identity.oidc.issuer
```

---

## 16. Terraform

```bash
terraform version
terraform fmt
terraform plan
terraform apply
```

Usunięcie infrastruktury:

```bash
terraform destroy
```

Po ponownym `terraform apply`:

```bash
kubectl get nodes
kubectl config current-context
```

---

## 17. Jenkins Agent

Build customowego obrazu:

```bash
podman build \
  -t gitops-jenkins-agent:3.0 \
  -f jenkins-agent/Containerfile .
```

Repozytorium ECR:

```bash
aws ecr create-repository \
  --repository-name gitops-jenkins-agent \
  --region eu-west-1
```

Tag i push:

```bash
podman tag \
  localhost/gitops-jenkins-agent:3.0 \
  211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-jenkins-agent:3.0

podman push \
  211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-jenkins-agent:3.0
```

Commit zmian:

```bash
git add Jenkinsfile jenkins-agent/Containerfile
git commit -m "Add Jenkins agent image"
git push origin main
```

---

## 18. EKS Pod Identity dla Jenkins Agent

ServiceAccount:

```bash
kubectl create serviceaccount jenkins-agent -n jenkins
```

Sprawdzenie i instalacja Pod Identity Agent:

```bash
kubectl get pods -n kube-system | grep eks-pod-identity
aws eks create-addon \
  --cluster-name gitops-lab \
  --addon-name eks-pod-identity-agent \
  --region eu-west-1
```

Sprawdzenie istniejących associations:

```bash
aws eks list-pod-identity-associations \
  --cluster-name gitops-lab \
  --region eu-west-1
```

Sprawdzenie IAM role:

```bash
aws iam get-role \
  --role-name gitops-jenkins-ecr \
  --output text
```

Powiązanie roli z ServiceAccount:

```bash
aws eks create-pod-identity-association \
  --cluster-name gitops-lab \
  --namespace jenkins \
  --service-account jenkins-agent \
  --role-arn "$(aws iam get-role \
    --role-name gitops-jenkins-ecr \
    --query 'Role.Arn' \
    --output text)" \
  --region eu-west-1
```

---

## 19. Jenkins Agent troubleshooting

```bash
kubectl get pods -n jenkins
kubectl describe pod <agent-pod> -n jenkins
```

Wejście do kontenera `tools`:

```bash
kubectl exec \
  -it \
  -n jenkins \
  <agent-pod> \
  -c tools \
  -- sh
```

Test obrazu lokalnie:

```bash
podman run \
  --rm \
  -it \
  211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-jenkins-agent:3.0 \
  bash
```

---

## 20. Kompletny GitOps workflow z laba

```text
Developer
   │
   ├── zmiana kodu
   │
   ▼
Podman build
   │
   ▼
Amazon ECR
   │
   ▼
zmiana Helm values.yaml
   │
   ▼
Git commit + push
   │
   ▼
Git repository
   │
   ▼
Argo CD
   │
   ▼
Helm render
   │
   ▼
Amazon EKS
   │
   ▼
Nginx Pods
```

Rozszerzenie o Jenkins:

```text
Git
 │
 ▼
Jenkins
 │
 ├── Jenkins Agent on EKS
 │
 ├── Pod Identity → AWS IAM
 │
 ├── Podman build
 │
 ▼
Amazon ECR
 │
 ▼
Git / Helm values
 │
 ▼
Argo CD
 │
 ▼
EKS Deployment
```

## Najważniejsza sekwencja do zapamiętania

```bash
# Build
podman build -t gitops-demo:2.0 .

# Tag
podman tag \
  localhost/gitops-demo:2.0 \
  211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-demo:2.0

# Push
podman push \
  211007024623.dkr.ecr.eu-west-1.amazonaws.com/gitops-demo:2.0

# Helm
helm lint nginx
helm template nginx ./nginx

# GitOps change
git add nginx/values.yaml
git commit -m "Update image to 2.0"
git push origin main

# Verify Argo CD
kubectl get applications -n argocd

# Verify deployment
kubectl get pods -A
kubectl get pods -A -o yaml | grep "image:" -A3
```
