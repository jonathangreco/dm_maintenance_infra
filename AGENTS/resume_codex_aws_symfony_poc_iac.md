# Résumé pour reprise par Codex — AWS Symfony POC IaC

## Contexte général

L’objectif est de transformer un POC AWS manuel en déploiement **Infrastructure as Code** avec Terraform + GitHub Actions.

Le POC manuel a permis de valider :

```text
Internet
  → ALB public
  → EC2
  → Docker
  → Symfony
  → RDS MySQL privé
```

Le POC a aussi permis de comprendre/valider :

```text
ALB public
Security Group ALB : HTTP 80 depuis 0.0.0.0/0
Security Group App : port 8080 depuis le SG ALB
Security Group RDS : port 3306 depuis le SG App
EC2 peut joindre RDS
Symfony dans Docker peut lire RDS
ALB affiche la page Symfony
```

Maintenant, l’objectif est de reconstruire tout ça proprement avec Terraform.

---

## Choix retenus

- **IaC** : Terraform.
- **CI/CD** : GitHub Actions + OIDC AWS, sans clés AWS longues durées dans GitHub.
- **Stratégie** : ne pas importer l’infra manuelle existante ; recréer une nouvelle infrastructure propre avec Terraform.
- **Région AWS** : `eu-north-1`.
- **Projet** : `symfony-poc`.
- **Environnement** : `dev`.

---

## Arborescence du repo

Le repo GitHub existe déjà et contient l’arborescence suivante :

```text
aws-symfony-poc-iac/
├── README.md
├── .gitignore
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml
│       └── terraform-apply.yml
├── infra/
│   ├── backend.tf
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   ├── locals.tf
│   ├── outputs.tf
│   ├── network.tf
│   ├── security-groups.tf
│   ├── alb.tf
│   ├── ec2.tf
│   ├── rds.tf
│   ├── iam.tf
│   └── cloudwatch.tf
└── bootstrap/
    ├── versions.tf
    ├── providers.tf
    ├── variables.tf
    ├── state-bucket.tf
    ├── outputs.tf
    └── github-oidc-role.tf
```

---

## Ce qui a déjà été commencé

### Dossier `infra/`

Les fichiers suivants ont été proposés/remplis :

```text
infra/versions.tf
infra/providers.tf
infra/variables.tf
infra/terraform.tfvars.example
infra/locals.tf
infra/outputs.tf
infra/backend.tf
```

`infra/backend.tf` est volontairement commenté pour l’instant, car le bucket S3 de state n’existe pas encore.

Variables importantes déjà prévues :

```hcl
project_name = "symfony-poc"
environment  = "dev"
aws_region   = "eu-north-1"
owner        = "jonathan"

db_name      = "app"
db_username  = "app_user"
db_password  = sensitive
```

Important : ne jamais commiter de vrai `terraform.tfvars`.

---

## Dernier état / blocage actuel

On a commencé le dossier `bootstrap/`.

Objectif du bootstrap :

```text
Créer le bucket S3 Terraform state
Activer versioning
Activer chiffrement
Bloquer l’accès public
Ajouter une bucket policy refusant le trafic non HTTPS
```

Fichiers concernés :

```text
bootstrap/versions.tf
bootstrap/providers.tf
bootstrap/variables.tf
bootstrap/state-bucket.tf
bootstrap/outputs.tf
```

Lors de l’exécution de Terraform, erreur obtenue :

```text
Error: No valid credential sources found
```

Diagnostic : Terraform n’a pas d’identité AWS utilisable dans l’environnement où il est lancé.

Correction à faire avant de continuer :

```bash
aws sts get-caller-identity
```

doit fonctionner.

Options possibles :

```text
1. Lancer le bootstrap depuis AWS CloudShell
2. Ou configurer AWS CLI localement avec aws configure
3. Ou utiliser un profil AWS local existant
```

Conseil donné : utiliser **AWS CloudShell** pour le bootstrap initial, car il est authentifié via la session console AWS.

---

## Étapes restantes à faire

### Étape 1 — Corriger l’auth AWS locale ou CloudShell

But :

```text
Faire fonctionner aws sts get-caller-identity
```

Commandes :

```bash
aws sts get-caller-identity
```

Puis :

```bash
cd bootstrap
terraform init
terraform validate
terraform plan
terraform apply
```

À la fin, récupérer l’output contenant le bloc backend S3.

---

### Étape 2 — Activer le backend distant dans `infra/backend.tf`

Après `bootstrap apply`, copier l’output du backend dans :

```text
infra/backend.tf
```

Exemple attendu :

```hcl
terraform {
  backend "s3" {
    bucket       = "symfony-poc-dev-tfstate-ACCOUNT_ID-eu-north-1"
    key          = "infra/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

Puis :

```bash
cd infra
terraform init
terraform validate
```

---

### Étape 3 — Créer le rôle GitHub Actions OIDC

Fichier :

```text
bootstrap/github-oidc-role.tf
```

But :

```text
Permettre à GitHub Actions d’assumer un rôle AWS sans secrets permanents.
```

À créer :

```text
aws_iam_openid_connect_provider
aws_iam_role pour GitHub Actions
aws_iam_role_policy ou aws_iam_policy dédiée Terraform
```

Le trust policy doit limiter au repo GitHub du projet.

Forme attendue du subject GitHub :

```text
repo:OWNER/REPO:ref:refs/heads/main
```

Ou éventuellement plus large au début :

```text
repo:OWNER/REPO:*
```

mais à resserrer ensuite.

---

### Étape 4 — GitHub Actions plan/apply

Fichiers :

```text
.github/workflows/terraform-plan.yml
.github/workflows/terraform-apply.yml
```

Objectif :

#### `terraform-plan.yml`

Sur pull request :

```text
checkout
configure-aws-credentials via OIDC
terraform fmt -check
terraform init
terraform validate
terraform plan
```

#### `terraform-apply.yml`

Sur push main ou déclenchement manuel :

```text
checkout
configure-aws-credentials via OIDC
terraform init
terraform apply -auto-approve
```

Préférer au début un `workflow_dispatch` manuel plutôt qu’un apply automatique.

Permissions GitHub nécessaires :

```yaml
permissions:
  id-token: write
  contents: read
```

---

### Étape 5 — Réseau Terraform

Fichier :

```text
infra/network.tf
```

Créer :

```text
VPC
Internet Gateway
2 subnets publics
2 subnets privés app
2 subnets privés db
route table publique
route table privée
associations de route tables
```

Pour limiter les coûts, éviter NAT Gateway au début.

Architecture souhaitée :

```text
Public subnets :
  ALB

Private app subnets :
  EC2 ou plus tard ECS

Private db subnets :
  RDS
```

---

### Étape 6 — Security Groups

Fichier :

```text
infra/security-groups.tf
```

Créer trois SG :

```text
sg-alb-public
  inbound TCP 80 depuis 0.0.0.0/0
  outbound all

sg-app-private
  inbound TCP 8080 depuis sg-alb-public
  éventuellement SSH 22 depuis IP admin temporairement
  outbound all

sg-rds-private
  inbound TCP 3306 depuis sg-app-private
  outbound minimal ou all pour POC
```

Ne pas ouvrir RDS publiquement.

---

### Étape 7 — ALB

Fichier :

```text
infra/alb.tf
```

Créer :

```text
Application Load Balancer public
Target Group HTTP port 8080
Listener HTTP 80
Health check /
Attachement EC2 target group plus tard
```

Output à ajouter :

```hcl
alb_dns_name
```

---

### Étape 8 — IAM EC2

Fichier :

```text
infra/iam.tf
```

Créer :

```text
IAM role EC2
Instance profile
Permissions minimales CloudWatch logs éventuellement
```

Au minimum prévoir un rôle EC2 pour la suite.

---

### Étape 9 — EC2

Fichier :

```text
infra/ec2.tf
```

Créer :

```text
EC2 applicative
subnet app
sg-app-private
iam_instance_profile
user_data pour installer Docker
```

Première version simple :

```text
Installer Docker
Activer Docker
Créer une page healthcheck simple ou lancer le conteneur de POC si image disponible
```

Attention : si EC2 est en subnet privé sans NAT, elle ne pourra pas télécharger Docker/images depuis Internet. Pour simplifier au début, soit :

```text
Option A : EC2 en subnet public mais protégée par SG
Option B : EC2 en subnet privé + NAT Gateway
Option C : passer rapidement à ECS/Fargate avec image ECR
```

Pour POC peu coûteux, accepter éventuellement EC2 publique temporaire mais avec SG strict.

---

### Étape 10 — RDS

Fichier :

```text
infra/rds.tf
```

Créer :

```text
DB subnet group privé
RDS MySQL
publicly_accessible = false
sg-rds-private
db_name
username
password sensitive
skip_final_snapshot = true pour POC uniquement
deletion_protection = false pour POC
```

Attention à ne jamais commiter le mot de passe.

---

### Étape 11 — CloudWatch

Fichier :

```text
infra/cloudwatch.tf
```

Créer :

```text
Log group /poc/symfony
retention courte : 1 à 3 jours
```

Plus tard, Docker/ECS enverra les logs dedans.

---

## Architecture finale Terraform visée

```text
Internet
  ↓
ALB public
  ↓ HTTP 8080
EC2 applicative
  ↓ Docker container Symfony
RDS MySQL privé
```

Puis évolution suivante :

```text
Internet
  ↓
ALB public
  ↓
ECS Fargate service
  ↓
RDS MySQL privé
```

---

## Points importants de sécurité

Ne pas commiter :

```text
terraform.tfvars
*.tfstate
.env
mots de passe
clés AWS
```

Ne pas stocker dans GitHub :

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

Préférer :

```text
GitHub Actions OIDC → AWS IAM Role temporaire
```

RDS doit rester :

```text
publicly_accessible = false
```

Le SG RDS doit accepter uniquement :

```text
3306 depuis le SG applicatif
```

---

## Ce que Codex doit faire maintenant

Priorité immédiate :

```text
1. Vérifier les fichiers existants du repo
2. Corriger/compléter bootstrap/
3. Aider à exécuter le bootstrap avec credentials AWS valides
4. Activer le backend S3 dans infra/backend.tf
5. Créer github-oidc-role.tf
6. Créer les workflows GitHub Actions
7. Ensuite seulement commencer network.tf
```

Ne pas créer directement toute l’infra d’un coup.

Travailler fichier par fichier, avec validation Terraform à chaque étape :

```bash
terraform fmt
terraform validate
terraform plan
```

Checkpoint actuel bloquant :

```text
Résoudre : No valid credential sources found
```
