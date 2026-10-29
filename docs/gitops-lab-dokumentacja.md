# AWS GitOps Lab — dokumentacja

## 1. Cel projektu

Celem projektu jest zbudowanie środowiska DevOps/GitOps na AWS, w którym aplikacja nginx jest budowana przez Jenkins, publikowana w Amazon ECR, a następnie wdrażana w klastrze Kubernetes przez Argo CD.

Główne technologie:

- **AWS** - infrastruktura chmurowa.
- **Terraform** - Infrastructure as Code.
- **Amazon EKS** - Kubernetes zarządzany przez AWS.
- **Jenkins** - automatyzacja procesu CI/CD.
- **Amazon ECR** - przechowywanie obrazów kontenerowych.
- **Argo CD** - wdrażanie aplikacji w modelu GitOps.
- **Helm** - zarządzanie konfiguracją aplikacji Kubernetes.
- **Podman** - budowanie obrazów kontenerowych.

Repozytorium: https://github.com/7kampe/gitops-demo.git

Region AWS używany w labie: `eu-central-1`.

## 2. Struktura repozytorium

Kod infrastruktury Terraform znajduje się w katalogu `terraform/`, wewnątrz repozytorium aplikacji.

```text
gitops-demo/
├── .gitignore
├── Containerfile
├── Jenkinsfile
├── argocd/
├── jenkins-agent/
├── nginx/
└── terraform/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

Opis elementów:

| Element | Przeznaczenie |
|---|---|
| `Containerfile` | Definicja obrazu aplikacji nginx |
| `Jenkinsfile` | Pipeline CI/CD |
| `argocd/` | Konfiguracja aplikacji Argo CD |
| `jenkins-agent/` | Definicja obrazu agenta Jenkins |
| `nginx/` | Helm chart aplikacji |
| `terraform/` | Kod infrastruktury AWS |
| `.gitignore` | Wykluczenie lokalnych plików i plików stanu |

## 3. Wymagania wstępne

Przed rozpoczęciem odtwarzania przygotuj:

- konto AWS z odpowiednimi uprawnieniami;
- AWS CLI;
- Terraform;
- `kubectl`;
- Helm;
- Git;
- Podman;
- konto GitHub z dostępem do repozytorium.

Sprawdź instalację:

```bash
aws --version
terraform version
kubectl version --client
helm version
git --version
podman --version
```

Sprawdź konto AWS:

```bash
aws sts get-caller-identity
aws configure get region
```

Upewnij się, że korzystasz z właściwego konta i regionu AWS.

## 4. Bezpieczeństwo i plik stanu Terraform

Terraform wykorzystuje plik stanu do powiązania konfiguracji z istniejącymi zasobami AWS.

Kod zapisany w GitHubie nie zastępuje pliku stanu. W tym labie stan był przechowywany lokalnie.

Plik stanu może zawierać identyfikatory zasobów oraz wrażliwe wartości. Nie należy publikować go w repozytorium.

W pliku `.gitignore` powinny znaleźć się co najmniej następujące reguły:

```gitignore
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfvars
*.tfvars.json
crash.log
crash.*.log
```

Nie należy publikować również:
- tokenów GitHub;
- haseł Jenkins;
- kluczy dostępowych AWS;
- plików konfiguracyjnych zawierających sekrety.

**Ważne:** jeśli plik stanu został wcześniej dodany do Git, samo umieszczenie go w `.gitignore` nie usuwa go z historii repozytorium.

W przypadku długotrwałego środowiska warto rozważyć zdalny backend Terraform, np. S3, z odpowiednią kontrolą dostępu i wersjonowaniem.

## 5. Odtwarzanie infrastruktury AWS

### 5.1. Pobranie repozytorium

```bash
git clone https://github.com/7kampe/gitops-demo.git
cd gitops-demo
```

Jeśli repozytorium jest już lokalnie:

```bash
git pull
```

### 5.2. Przejście do katalogu Terraform

```bash
cd terraform
```

Przed uruchomieniem Terraform przejrzyj pliki:

- `main.tf`;
- `variables.tf`;
- `outputs.tf`.

Sprawdź region, nazwę klastra, wersję Kubernetes, typ instancji, konfigurację sieci i wymagane zmienne.

### 5.3. Inicjalizacja i walidacja

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Przed zastosowaniem konfiguracji sprawdź plan i upewnij się, że Terraform korzysta z właściwego konta AWS oraz właściwego stanu.

Jeśli plan jest zgodny z oczekiwaniami:

```bash
terraform apply
```

Nie uruchamiaj `apply`, jeśli Terraform nie widzi właściwego stanu albo planuje niespodziewane utworzenie lub usunięcie zasobów.

## 6. Konfiguracja dostępu do EKS

W poprzedniej wersji labu klaster miał nazwę `gitops-lab` i działał w regionie `eu-central-1`.

Po utworzeniu klastra zaktualizuj kubeconfig:

```bash
aws eks update-kubeconfig \
  --region eu-central-1 \
  --name gitops-lab
```

Sprawdź węzły:

```bash
kubectl get nodes
```

Sprawdź namespace’y i pody:

```bash
kubectl get namespaces
kubectl get pods -A
```

Węzły powinny osiągnąć stan `Ready`, zanim przejdziesz do konfiguracji aplikacji.

Jeśli nazwa klastra została zmieniona w Terraform, użyj aktualnej nazwy.

## 7. Jenkins

W poprzednim labie Jenkins działał w namespace `jenkins`.

Panel można udostępnić lokalnie poleceniem:

```bash
kubectl port-forward svc/jenkins -n jenkins 8081:8080
```

Następnie otwórz w przeglądarce:

`http://localhost:8081`

W poprzedniej konfiguracji hasło administratora można było odczytać poleceniem:

```bash
kubectl exec -n jenkins svc/jenkins -- \
  cat /run/secrets/chart-admin-password
```

Polecenie zadziała tylko wtedy, gdy Jenkins został zainstalowany w sposób zgodny z tą konfiguracją i sekret istnieje.

### 7.1. Konfiguracja joba

Job nazywał się `gitops-demo`.

Podstawowe ustawienia:

- Definition: `Pipeline script from SCM`;
- SCM: `Git`;
- Repository URL: `https://github.com/7kampe/gitops-demo.git`;
- Branch: `*/main`;
- Script Path: `Jenkinsfile`;
- Credential ID: `github-push`.

Token GitHub należy przechowywać w Jenkins Credentials. Nie wolno umieszczać go bezpośrednio w `Jenkinsfile` ani w repozytorium.

### 7.2. Agent Kubernetes

W poprzedniej konfiguracji używany był agent:

- namespace: `jenkins`;
- label: `gitops-agent`;
- service account: `jenkins-agent`;
- obraz z Amazon ECR: `gitops-jenkins-agent`;
- kontener narzędziowy: `tools`.

Pipeline odwoływał się do niego przez `container('tools')`.

Po odtworzeniu sprawdź zgodność konfiguracji Pod Template, nazwy obrazu, tagu i uprawnień IAM.

Tryb privileged i montowanie `/var/lib/containers` zwiększają uprawnienia kontenera. Używaj ich tylko w świadomie skonfigurowanym środowisku testowym.

## 8. Amazon ECR i uprawnienia IAM

W poprzednim labie używano dwóch repozytoriów ECR:

- `gitops-demo`;
- `gitops-jenkins-agent`.

Skonfigurowano także rolę IAM `gitops-jenkins-ecr` oraz EKS Pod Identity dla konta serwisowego `jenkins-agent` w namespace `jenkins`.

Część tych zasobów została utworzona ręcznie, a nie przez Terraform. Dlatego udany `terraform destroy` nie musi oznaczać, że wszystkie zostały usunięte.

Sprawdź repozytoria ECR:

```bash
aws ecr describe-repositories --region eu-central-1
```

Sprawdź rolę IAM:

```bash
aws iam get-role --role-name gitops-jenkins-ecr
```

Sprawdź klastry EKS:

```bash
aws eks list-clusters --region eu-central-1
```

Nie usuwaj ręcznie pozostałych zasobów IAM i ECR, dopóki nie upewnisz się, że nie są wykorzystywane przez inne projekty.

Przechowywane obrazy ECR mogą nadal generować koszty.

## 9. Argo CD

W poprzedniej konfiguracji Argo CD działał w namespace `argocd`.

Aplikacja nazywała się `nginx-demo` i korzystała z Helm chartu w katalogu `nginx` repozytorium GitHub.

Po odtworzeniu klastra i instalacji Argo CD sprawdź:

```bash
kubectl get pods -n argocd
kubectl get applications -n argocd
```

Aplikacja powinna być zsynchronizowana z repozytorium i osiągnąć stan `Healthy`, jeśli konfiguracja i zasoby zostały prawidłowo odtworzone.

## 10. Przepływ CI/CD

Pipeline realizuje następujący przepływ:

1. Pobranie kodu z GitHub.
2. Weryfikacja zawartości repozytorium.
3. Walidacja Helm chartu przez `helm lint`.
4. Budowanie obrazu aplikacji przez Podman.
5. Logowanie do Amazon ECR.
6. Publikacja obrazu z tagiem powiązanym z numerem buildu.
7. Aktualizacja tagu obrazu w `nginx/values.yaml`.
8. Commit i push zmiany do GitHub.
9. Wykrycie zmiany przez Argo CD i synchronizacja aplikacji.

W poprzednim uruchomieniu labu pipeline zakończył się sukcesem. Po odtworzeniu należy osobno zweryfikować wynik buildu, obecność obrazu w ECR i stan aplikacji w Argo CD.

## 11. Sprzątanie środowiska

Przed usunięciem infrastruktury:

1. Zapisz kod w GitHub.
2. Sprawdź konto AWS:

   ```bash
   aws sts get-caller-identity
   ```

3. Przejdź do katalogu Terraform z właściwym stanem.
4. Sprawdź plan usuwania:

   ```bash
   terraform plan -destroy
   ```

5. Upewnij się, że plan dotyczy wyłącznie zasobów labu.
6. Dopiero wtedy uruchom:

   ```bash
   terraform destroy
   ```

7. Sprawdź, czy klaster nadal istnieje:

   ```bash
   aws eks list-clusters --region eu-central-1
   ```

8. Zweryfikuj pozostałe zasoby ręczne, w szczególności ECR i IAM.

Nie kasuj plików stanu ani kopii zapasowych, dopóki nie potwierdzisz, że nie są już potrzebne.

## 12. Rozwiązywanie problemów

### Terraform zgłasza `No state file found`

- Sprawdź katalog roboczy.
- Sprawdź backend i workspace.
- Upewnij się, że stan nie pozostał w poprzednim katalogu.
- Nie uruchamiaj `apply` ani `destroy`, jeśli stan nie jest właściwy.
- Nie kopiuj plików stanu w ciemno.

### `kubectl` nie łączy się z klastrem

- Sprawdź `aws sts get-caller-identity`.
- Zweryfikuj nazwę klastra i region.
- Odśwież kubeconfig.
- Upewnij się, że klaster istnieje i użytkownik ma uprawnienia.

### Jenkins nie może wypchnąć obrazu do ECR

- Sprawdź region i nazwę repozytorium.
- Zweryfikuj Pod Identity i rolę IAM.
- Sprawdź logi buildu i uprawnienia agenta.
- Nie zapisuj kluczy AWS w repozytorium.

### Argo CD nie synchronizuje aplikacji

- Sprawdź, czy commit trafił do właściwej gałęzi.
- Sprawdź URL repozytorium i ścieżkę Helm chartu.
- Zweryfikuj stan aplikacji w Argo CD.
- Upewnij się, że wymagany tag obrazu istnieje w ECR.

## 13. Checklista końcowa

- [ ] Kod Terraform znajduje się w `terraform/`.
- [ ] `.gitignore` wyklucza pliki stanu i lokalne pliki zmiennych.
- [ ] W repozytorium nie ma tokenów, haseł ani kluczy.
- [ ] Terraform używa właściwego stanu, konta AWS i regionu.
- [ ] `terraform init`, `terraform validate` i `terraform plan` działają poprawnie.
- [ ] Węzły EKS są w stanie `Ready`.
- [ ] Jenkins build kończy się sukcesem.
- [ ] Argo CD pokazuje aplikację jako `Healthy` i `Synced`.
- [ ] Po `destroy` sprawdzono ręcznie utworzone zasoby i możliwe dalsze koszty.
