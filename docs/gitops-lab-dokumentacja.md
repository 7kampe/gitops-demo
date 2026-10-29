# AWS GitOps Lab --- dokumentacja i szybkie odtworzenie

## 1. Cel projektu

Laboratorium pokazuje przepływ CI/CD i GitOps na AWS:

1.  Kod aplikacji i konfiguracja Helm są przechowywane w GitHub.
2.  Jenkins pobiera repozytorium i wykonuje pipeline z pliku
    `Jenkinsfile`.
3.  Helm sprawdza chart, a Podman buduje obraz kontenera.
4.  Jenkins wysyła obraz do Amazon ECR.
5.  Jenkins aktualizuje `nginx/values.yaml` i wypycha zmianę do gałęzi
    `main`.
6.  Argo CD wykrywa zmianę w Git i wdraża nową wersję do EKS.

## 2. Repozytorium i zasoby

-   Repozytorium GitHub: `https://github.com/7kampe/gitops-demo.git`
-   Gałąź: `main`
-   Region AWS: `eu-central-1` (Frankfurt)
-   Klaster EKS: `gitops-lab`
-   Namespace Argo CD: `argocd`
-   Namespace Jenkins: `jenkins`
-   Job Jenkins: `gitops-demo`
-   Szablon agenta Kubernetes: `gitops-agent`
-   Kontener narzędziowy agenta: `tools`
-   Konto serwisowe agenta: `jenkins-agent`
-   Rola IAM dla ECR: `gitops-jenkins-ecr`
-   Repozytorium ECR aplikacji: `gitops-demo`
-   Repozytorium ECR agenta: `gitops-jenkins-agent`
-   Aplikacja Argo CD: `nginx-demo`
-   Chart Helm aplikacji: katalog `nginx/`

W konfiguracji Terraform klaster używa Kubernetes `1.33`, węzła
`t3.medium`, publicznych podsieci i publicznego endpointu EKS. NAT
Gateway jest wyłączony. Jenkins ma wyłączoną trwałą pamięć
(`persistence.enabled=false`), aby nie wymagać PVC/EBS w tym labie.

## 3. Architektura

``` text
GitHub (main)
   | Jenkinsfile + Containerfile + nginx/ chart
   v
Jenkins job: gitops-demo
   |-- checkout
   |-- helm lint nginx
   |-- Podman build
   |-- AWS Pod Identity -> IAM role gitops-jenkins-ecr
   |-- push image
   |-- update nginx/values.yaml + git push
   v
GitHub (nowy tag obrazu w nginx/values.yaml)
   |
   v
Argo CD (Application: nginx-demo)
   |
   v
Amazon EKS -> Deployment nginx -> pody nginx
```

## 4. Najważniejsze elementy repozytorium

Oczekiwana struktura:

``` text
gitops-demo/
├── Containerfile
├── Jenkinsfile
├── argocd/
│   └── nginx-demo.yaml
├── jenkins-agent/
│   └── Containerfile
└── nginx/
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
```

-   `Containerfile` --- buduje obraz nginx z własną stroną.
-   `Jenkinsfile` --- definiuje pipeline.
-   `nginx/` --- chart Helm aplikacji.
-   `nginx/values.yaml` --- m.in. liczba replik, adres obrazu i tag.
-   `argocd/nginx-demo.yaml` --- zasób Argo CD typu `Application`.
-   `jenkins-agent/Containerfile` --- definicja obrazu narzędziowego
    agenta Jenkins.

### Ważna konfiguracja Jenkinsfile

W `Jenkinsfile` wartość `ECR_REGISTRY` musi zawierać właściwy 12-cyfrowy
AWS Account ID, np.:

``` groovy
ECR_REGISTRY = '<AWS_ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com'
```

Zamień placeholder na rzeczywisty numer konta przed commitem. Nie wpisuj
do repozytorium kluczy AWS ani tokenów.

Pipeline używa `${BUILD_NUMBER}` jako tagu obrazu, dzięki czemu każdy
build publikuje nowy tag i może wprowadzić zmianę do
`nginx/values.yaml`. Po buildzie `Success` sprawdź, czy nowy tag jest w
GitHub i czy Argo CD zsynchronizowało aplikację.

## 5. Szybkie odtworzenie po usunięciu klastra

Wykonuj kroki po kolei. Polecenia są przeznaczone dla Git Bash z
zainstalowanymi i skonfigurowanymi AWS CLI, Terraform, kubectl, Helm i
Git.

### A. Sprawdź dostęp do AWS i Terraform

``` bash
aws sts get-caller-identity
aws configure get region
cd aws-gitops-lab
terraform init
terraform plan
terraform apply
```

Sprawdź plan przed zatwierdzeniem. `terraform apply` może utworzyć
płatne zasoby AWS, w szczególności EKS i instancję EC2. Nie uruchamiaj
`terraform destroy`, jeśli chcesz zachować środowisko.

Po utworzeniu klastra skonfiguruj kubectl:

``` bash
aws eks update-kubeconfig --name gitops-lab --region eu-central-1
kubectl get nodes
```

Oczekiwany wynik: co najmniej jeden węzeł w stanie `Ready`.

### B. Zainstaluj EKS Pod Identity Agent

Sprawdź, czy agent już działa:

``` bash
kubectl get pods -n kube-system | grep eks-pod-identity
```

Jeśli dodatku nie ma, utwórz go:

``` bash
aws eks create-addon \
  --cluster-name gitops-lab \
  --addon-name eks-pod-identity-agent \
  --region eu-central-1
```

Poczekaj, aż pody dodatku będą działały.

### C. Odtwórz namespace i Argo CD

``` bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd
```

Poczekaj, aż komponenty Argo CD będą gotowe. Z katalogu lokalnego
repozytorium `gitops-demo` zastosuj aplikację:

``` bash
kubectl apply -f argocd/nginx-demo.yaml
kubectl get applications -n argocd
kubectl get pods
```

Sprawdź, czy aplikacja `nginx-demo` osiągnie `Healthy` i `Synced`. Jeśli
Argo CD potrzebuje chwili na instalację CRD, odczekaj i ponów
sprawdzenie.

### D. Odtwórz Jenkinsa bez trwałego wolumenu

``` bash
helm repo add jenkins https://charts.jenkins.io
helm repo update
kubectl create namespace jenkins
helm install jenkins jenkins/jenkins -n jenkins --set persistence.enabled=false
kubectl get pods -n jenkins
```

Jeśli namespace już istnieje, nie twórz go ponownie --- przejdź do
instalacji. Jeśli release już istnieje, sprawdź go przez
`helm list -n jenkins`, zamiast instalować drugi raz.

Otwórz panel:

``` bash
kubectl port-forward svc/jenkins -n jenkins 8081:8080
```

Wejdź na `http://localhost:8081`. Hasło administratora:

``` bash
kubectl exec -n jenkins svc/jenkins -- cat /run/secrets/chart-admin-password
```

**Uwaga:** ponieważ `persistence.enabled=false`, konfiguracja Jenkinsa
(joby, credentials i ustawienia UI) nie przetrwa usunięcia poda/release.
Po reinstalacji trzeba ją odtworzyć.

### E. Odtwórz konto serwisowe i Pod Identity

``` bash
kubectl create serviceaccount jenkins-agent -n jenkins
```

Jeśli konto już istnieje, komunikat `AlreadyExists` jest w porządku.

Sprawdź, czy rola IAM istnieje:

``` bash
aws iam get-role --role-name gitops-jenkins-ecr --query "Role.Arn" --output text
```

Sprawdź istniejące powiązania:

``` bash
aws eks list-pod-identity-associations \
  --cluster-name gitops-lab \
  --region eu-central-1
```

Jeśli nie ma powiązania dla namespace `jenkins` i service account
`jenkins-agent`, utwórz je:

``` bash
aws eks create-pod-identity-association \
  --cluster-name gitops-lab \
  --namespace jenkins \
  --service-account jenkins-agent \
  --role-arn "$(aws iam get-role --role-name gitops-jenkins-ecr --query 'Role.Arn' --output text)" \
  --region eu-central-1
```

Rola `gitops-jenkins-ecr` musi mieć zaufanie do EKS Pod Identity
(`pods.eks.amazonaws.com`) oraz uprawnienia do logowania i pushowania do
repozytorium ECR `gitops-demo`. Jeśli rola lub polityka nie istnieje,
odtwórz ją zgodnie z zasadą najmniejszych uprawnień przed uruchomieniem
pipeline'u. Nie zapisuj kluczy AWS w Jenkinsie.

### F. Odtwórz konfigurację Jenkinsa w UI

1.  Zaloguj się do Jenkins.
2.  **Manage Jenkins → Credentials → System → Global credentials → Add
    Credentials**:
    -   Kind: `Username with password`
    -   Username: login GitHub
    -   Password: GitHub Personal Access Token (wklej wyłącznie w
        Jenkinsie)
    -   ID: `github-push`
3.  **Manage Jenkins → Clouds → Kubernetes → Configure**:
    -   Kubernetes URL: `https://kubernetes.default`
    -   Jenkins URL: `http://jenkins.jenkins.svc.cluster.local:8080`
4.  Utwórz Pod Template:
    -   Name: `gitops-agent`
    -   Namespace: `jenkins`
    -   Labels: `gitops-agent`
    -   Service Account: `jenkins-agent`
5.  Dodaj kontener:
    -   Name: `tools`
    -   Image:
        `<AWS_ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com/gitops-jenkins-agent:3.0`
    -   Working directory: `/home/jenkins/agent`
    -   Privileged: włączone (wymagane przez obecną konfigurację Podman
        w tym labie)
    -   EmptyDir volume zamontowany pod `/var/lib/containers`
    -   Jeśli jest opcja agent container / run in container, ustaw
        `tools` jako kontener wykonywania kroków.
6.  Zapisz konfigurację chmury.
7.  Utwórz job `gitops-demo` typu **Pipeline**:
    -   Definition: `Pipeline script from SCM`
    -   SCM: `Git`
    -   Repository URL: `https://github.com/7kampe/gitops-demo.git`
    -   Credentials: `github-push` (jeśli job korzysta z tego
        credential)
    -   Branch Specifier: `*/main`
    -   Script Path: `Jenkinsfile`
8.  Zapisz job i kliknij **Build Now**.

Upewnij się, że numer konta AWS w obrazie agenta i w `Jenkinsfile` jest
poprawny. Obraz `gitops-jenkins-agent:3.0` musi już istnieć w ECR; jeśli
nie istnieje, najpierw trzeba go zbudować i wypchnąć zgodnie z
instrukcją obrazu agenta.

## 6. Test końcowy

Po udanym buildzie sprawdź:

``` bash
kubectl get applications -n argocd
kubectl get pods
kubectl get deployment nginx -o jsonpath="{.spec.template.spec.containers[0].image}"
```

Oczekiwane: - Jenkins build: `SUCCESS` - Argo CD application: `Healthy`
i `Synced` - pody nginx: `Running` - obraz deploymentu ma tag
odpowiadający ostatniemu buildowi.

Jeżeli deployment ma inną nazwę niż `nginx`, sprawdź
`kubectl get deployments` i użyj właściwej nazwy.

## 7. Typowe problemy

### Jenkins pod czeka na PVC (`Pending`)

Sprawdź:

``` bash
kubectl get pvc -n jenkins
helm get values jenkins -n jenkins
```

W tym labie Jenkins powinien być zainstalowany z
`--set persistence.enabled=false`. Jeśli poprzedni release miał domyślne
PVC, odinstaluj release, sprawdź i usuń stary PVC tylko wtedy, gdy
akceptujesz utratę zapisanych w nim danych, a następnie zainstaluj
ponownie z persistence wyłączonym.

### Agent Jenkins nie startuje

Sprawdź namespace, etykietę `gitops-agent`, nazwę kontenera `tools`,
service account `jenkins-agent`, adres obrazu i dostępność obrazu agenta
w ECR. Sprawdź też:

``` bash
kubectl get pods -n jenkins
kubectl describe pod <NAZWA_PODA> -n jenkins
```

### AWS ECR zwraca błąd dostępu

Sprawdź, czy Pod Identity Agent działa, czy istnieje powiązanie
namespace/service account z rolą, oraz czy rola ma wymagane uprawnienia
ECR. Test `aws sts get-caller-identity` wykonany wewnątrz kontenera
`tools` powinien zwracać rolę `gitops-jenkins-ecr`.

### Build kończy się `nothing to commit`

To znaczy, że `nginx/values.yaml` nie zmienił się względem bieżącego
commita. Używaj unikalnego tagu, np. numeru buildu (`BUILD_NUMBER`), i
sprawdź, czy `sed` aktualizuje dokładnie linię `tag` w
`nginx/values.yaml`.

### Argo CD nie aktualizuje aplikacji

Sprawdź:

``` bash
kubectl get applications -n argocd
kubectl describe application nginx-demo -n argocd
```

Zweryfikuj `repoURL`, `targetRevision: main`, `path: nginx` w
`argocd/nginx-demo.yaml`, a także czy Jenkins wypchnął zmianę do GitHub.

## 8. Koszty i sprzątanie

-   `t3.medium` oraz EKS generują koszty, gdy lab działa.
-   NAT Gateway jest wyłączony, aby ograniczyć koszty.
-   Jenkins nie używa trwałego PVC, więc jego konfiguracja nie jest
    trwała.
-   Obrazy ECR i ręcznie utworzone zasoby IAM/ECR mogą pozostać po
    usunięciu klastra i nadal wymagać osobnego sprzątnięcia.
-   Przed `terraform destroy` sprawdź, jakie zasoby należą do Terraform.
    Zasoby utworzone ręcznie (np. repozytoria ECR, rola IAM, Pod
    Identity association) niekoniecznie zostaną usunięte przez
    Terraform.
-   Po zakończeniu pracy, jeśli nie potrzebujesz środowiska, rozważ
    `terraform destroy` po dokładnym sprawdzeniu planu. To usuwa zasoby
    zarządzane przez Terraform, ale nie musi usuwać wszystkiego, co
    utworzono poza nim.

## 9. Checklist po odtworzeniu

-   [ ] `kubectl get nodes` pokazuje węzeł `Ready`
-   [ ] EKS Pod Identity Agent działa
-   [ ] Argo CD działa w namespace `argocd`
-   [ ] `nginx-demo` jest `Healthy` / `Synced`
-   [ ] Jenkins działa bez PVC
-   [ ] Service account `jenkins-agent` istnieje
-   [ ] Pod Identity association wskazuje właściwą rolę IAM
-   [ ] Jenkins credentials `github-push` są skonfigurowane
-   [ ] Pod Template `gitops-agent` ma kontener `tools` i EmptyDir
-   [ ] Job `gitops-demo` wskazuje na `Jenkinsfile` w gałęzi `main`
-   [ ] Jenkins build kończy się `SUCCESS`
-   [ ] Argo CD wdraża tag obrazu z ostatniego buildu
