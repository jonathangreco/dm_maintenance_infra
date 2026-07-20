# Procedure de migration vers un nouveau compte AWS

## Objectif

Migrer l'infrastructure `darkmira-maintenance` depuis le compte AWS personnel actuel vers un nouveau compte AWS rattache a l'adresse mail de la societe.

L'objectif n'est pas de transferer le compte AWS existant, mais de recreer proprement l'infrastructure dans le nouveau compte, de reposer les secrets, de restaurer la base MySQL depuis l'export nocturne, puis de basculer le deploiement automatique GitHub vers le nouveau compte.

## Etat actuel du projet

Region AWS cible:

```text
eu-north-1
```

Compte AWS actuel reference dans le depot:

```text
387219500605
```

Les endroits ou cet identifiant de compte est actuellement code en dur:

```text
infra/backend.tf
.github/workflows/terraform-plan.yml
.github/workflows/terraform-apply.yml
infra/github-app-deploy.tf
```

Le projet utilise deux couches Terraform:

```text
bootstrap/
  Cree le bucket S3 de state Terraform et le role GitHub Actions pour Terraform.

infra/
  Cree le reseau, l'ALB, l'EC2 Docker, RDS MySQL, les logs CloudWatch,
  les backups MySQL S3, le scheduler nocturne et le role GitHub Actions
  de deploiement applicatif.
```

## Identites et droits AWS a recreer

Il n'y a pas d'utilisateur IAM applicatif long terme dans le projet. Le projet repose surtout sur des roles IAM.

### Role GitHub Actions Terraform

Fichier:

```text
bootstrap/github-oids-role.tf
```

Nom genere:

```text
darkmira-maintenance-dev-github-actions-terraform
```

Utilisation:

```text
.github/workflows/terraform-plan.yml
.github/workflows/terraform-apply.yml
```

Trust policy:

```text
GitHub OIDC
repo:jonathangreco/dm_maintenance_infra:ref:refs/heads/master
```

Droits:

```text
EC2, ALB, RDS, CloudWatch, Logs, Lambda, EventBridge Scheduler,
IAM necessaire aux roles/profiles Terraform, S3 state, S3 backups,
DynamoDB lockfile legacy.
```

Action migration:

```text
1. Reexecuter bootstrap/ dans le nouveau compte.
2. Recuperer le nouvel ARN du role.
3. Remplacer role-to-assume dans les workflows GitHub Terraform.
```

### Role EC2 applicatif

Fichier:

```text
infra/ec2.tf
```

Nom genere:

```text
darkmira-maintenance-dev-app-ec2-role
```

Utilisation:

```text
Instance EC2 applicative.
```

Droits:

```text
AmazonSSMManagedInstanceCore
ssm:GetParameter sur /darkmira-maintenance/dev/app/env
ssm:GetParameter sur /darkmira-maintenance/dev/ghcr/token
logs:CreateLogStream, logs:DescribeLogStreams, logs:PutLogEvents
s3:ListBucket sur le bucket de backups MySQL
s3:PutObject et s3:AbortMultipartUpload sur mysql/*
```

Action migration:

```text
Recree automatiquement par terraform apply dans infra/.
Il faut imperativement recreer les parametres SSM avant ou pendant le premier boot EC2,
sinon le user_data echouera au moment de generer /opt/darkmira-maintenance/.env.
```

### Role GitHub Actions de deploiement applicatif

Fichier:

```text
infra/github-app-deploy.tf
```

Nom genere:

```text
darkmira-maintenance-dev-github-actions-app-deploy
```

Trust policy actuelle:

```text
arn:aws:iam::387219500605:oidc-provider/token.actions.githubusercontent.com
repo:jonathangreco/dm_maintenance:ref:refs/heads/main
```

Utilisation:

```text
Depot applicatif jonathangreco/dm_maintenance, branche main.
Deploiement automatique via SSM SendCommand sur l'EC2.
```

Droits:

```text
ec2:DescribeInstances
ssm:SendCommand sur l'instance EC2 et AWS-RunShellScript
ssm:GetCommandInvocation
```

Action migration:

```text
1. Remplacer l'ancien account id dans infra/github-app-deploy.tf.
2. Idealement, ne plus coder l'ARN du provider OIDC en dur et reutiliser
   un data source ou une variable du nouveau compte.
3. Appliquer infra/.
4. Mettre a jour le secret ou la variable GitHub du depot applicatif avec
   le nouvel ARN:
   arn:aws:iam::<NEW_ACCOUNT_ID>:role/darkmira-maintenance-dev-github-actions-app-deploy
```

### Roles du scheduler nocturne

Fichier:

```text
infra/night-scheduler.tf
```

Noms generes:

```text
darkmira-maintenance-dev-night-scheduler-lambda-role
darkmira-maintenance-dev-night-scheduler-eventbridge-role
```

Utilisation:

```text
Arret/demarrage nocturne EC2 + RDS.
Backup MySQL avant arret via SSM command /opt/darkmira-maintenance/backup-mysql.sh.
Refresh applicatif apres redemarrage EC2.
```

Droits:

```text
Lambda logs CloudWatch
ec2:StartInstances / ec2:StopInstances / ec2:DescribeInstances
rds:DescribeDBInstances / rds:StartDBInstance / rds:StopDBInstance
ssm:SendCommand / ssm:GetCommandInvocation
EventBridge Scheduler: lambda:InvokeFunction
```

Action migration:

```text
Recrees automatiquement par terraform apply si night_shutdown_enabled = true.
```

## Secrets et parametres a recreer

### GitHub repository secrets

Dans le depot infra `dm_maintenance_infra`:

```text
TF_VAR_DB_PASSWORD
```

Ce secret alimente:

```text
TF_VAR_db_password
```

Il doit contenir le mot de passe admin RDS correspondant a:

```text
db_username = "app_user"
db_name     = "app"
```

Dans le depot applicatif `dm_maintenance`, verifier le secret ou la variable qui contient l'ARN du role de deploiement applicatif. Il doit pointer vers le nouveau compte:

```text
arn:aws:iam::<NEW_ACCOUNT_ID>:role/darkmira-maintenance-dev-github-actions-app-deploy
```

### SSM Parameter Store

Les parametres SSM utilises par l'EC2 sont:

```text
/darkmira-maintenance/dev/app/env
/darkmira-maintenance/dev/ghcr/token
```

Le parametre `/darkmira-maintenance/dev/app/env` est un `SecureString` contenant le fichier d'environnement applicatif complet:

```env
APP_SECRET=...
DATABASE_URL=mysql://app_user:<DB_PASSWORD>@<NEW_RDS_ENDPOINT>:3306/app?serverVersion=8.0
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-4.1-mini
OPENAI_MAX_TOKENS=800
OPENAI_TEMPERATURE=0.1
CODE_AGENT=codex
CODEX_MODEL=gpt-5.3-codex
AUTOFIX_GIT_USER_NAME=Darkmira Bot
AUTOFIX_GIT_USER_EMAIL=bot@darkmira.fr
GITHUB_TOKEN=...
MAILBOX_MAX_RESULTS=25
GMAIL_OAUTH_CLIENT_ID=...
GMAIL_OAUTH_CLIENT_SECRET=...
GMAIL_OAUTH_REFRESH_TOKEN=...
GMAIL_OAUTH_REDIRECT_URI=...
```

Le parametre `/darkmira-maintenance/dev/ghcr/token` est un `SecureString` contenant uniquement le token GitHub utilise pour:

```text
docker login ghcr.io --username jonathangreco
```

Le token doit avoir acces en lecture aux images:

```text
ghcr.io/jonathangreco/darkmira-maintenance-app:prod
ghcr.io/jonathangreco/darkmira-maintenance-nginx:prod
```

Commandes de creation dans le nouveau compte:

```bash
aws ssm put-parameter \
  --profile <NEW_AWS_PROFILE> \
  --region eu-north-1 \
  --name /darkmira-maintenance/dev/app/env \
  --type SecureString \
  --value file://env.prod \
  --overwrite

aws ssm put-parameter \
  --profile <NEW_AWS_PROFILE> \
  --region eu-north-1 \
  --name /darkmira-maintenance/dev/ghcr/token \
  --type SecureString \
  --value '<GHCR_TOKEN>' \
  --overwrite
```

## Images et containers

Images configurees actuellement:

```text
ghcr.io/jonathangreco/darkmira-maintenance-app:prod
ghcr.io/jonathangreco/darkmira-maintenance-nginx:prod
```

Services Docker Compose lances sur l'EC2:

```text
app
nginx
messenger-worker
scheduler
```

Chemin runtime sur l'EC2:

```text
/opt/darkmira-maintenance
```

Fichier compose genere:

```text
/opt/darkmira-maintenance/docker-compose.prod.yml
```

Fichier env genere:

```text
/opt/darkmira-maintenance/.env
```

Si le nouveau compte GitHub ou l'organisation change, modifier dans `infra/dev.tfvars`:

```hcl
app_container_image = "ghcr.io/<ORG_OR_USER>/darkmira-maintenance-app:prod"
app_nginx_image     = "ghcr.io/<ORG_OR_USER>/darkmira-maintenance-nginx:prod"
ghcr_username       = "<ORG_OR_USER>"
```

Si le nom projet doit changer cote AWS, modifier `project_name`, mais attention: cela change les noms de toutes les ressources Terraform.

## Procedure de migration

### 1. Preparatifs

Creer le nouveau compte AWS avec l'adresse mail de la societe.

Activer MFA sur le root account et creer au minimum:

```text
1 utilisateur/role admin humain pour bootstrap initial.
1 profil AWS CLI local ou une session AWS CloudShell authentifiee.
```

Verifier l'identite du nouveau compte:

```bash
aws sts get-caller-identity --profile <NEW_AWS_PROFILE>
```

Noter:

```text
NEW_ACCOUNT_ID=<id du nouveau compte>
```

### 2. Bootstrap Terraform dans le nouveau compte

Depuis `bootstrap/`:

```bash
cd bootstrap
terraform init
terraform validate
terraform plan
terraform apply
```

Recuperer les outputs:

```bash
terraform output terraform_state_bucket_name
terraform output github_actions_role_arn
terraform output infra_backend_configuration
terraform output github_actions_oidc_provider_arn
```

### 3. Mettre a jour le backend Terraform infra

Remplacer `infra/backend.tf` par l'output `infra_backend_configuration`.

La valeur actuelle contient l'ancien compte:

```text
darkmira-maintenance-dev-tfstate-387219500605-eu-north-1
```

Elle doit devenir:

```text
darkmira-maintenance-dev-tfstate-<NEW_ACCOUNT_ID>-eu-north-1
```

Puis reinitialiser le backend:

```bash
cd ../infra
terraform init -reconfigure
```

Ne pas migrer le state de l'ancien compte vers le nouveau: on veut recreer une infrastructure neuve.

### 4. Mettre a jour GitHub Actions Terraform

Dans:

```text
.github/workflows/terraform-plan.yml
.github/workflows/terraform-apply.yml
```

Remplacer:

```text
arn:aws:iam::387219500605:role/darkmira-maintenance-dev-github-actions-terraform
```

par:

```text
arn:aws:iam::<NEW_ACCOUNT_ID>:role/darkmira-maintenance-dev-github-actions-terraform
```

Verifier que le depot GitHub autorise par `bootstrap/variables.tf` correspond bien au depot infra:

```text
jonathangreco/dm_maintenance_infra
```

et que la branche correspond bien a la branche de deploiement:

```text
master
```

### 5. Corriger le role GitHub de deploiement applicatif

Dans `infra/github-app-deploy.tf`, remplacer:

```text
arn:aws:iam::387219500605:oidc-provider/token.actions.githubusercontent.com
```

par:

```text
arn:aws:iam::<NEW_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com
```

Verifier aussi que le repo applicatif et la branche sont corrects:

```text
repo:jonathangreco/dm_maintenance:ref:refs/heads/main
```

### 6. Reposer les secrets GitHub

Dans le depot infra:

```text
TF_VAR_DB_PASSWORD=<nouveau mot de passe RDS>
```

Dans le depot applicatif:

```text
AWS_ROLE_TO_ASSUME=arn:aws:iam::<NEW_ACCOUNT_ID>:role/darkmira-maintenance-dev-github-actions-app-deploy
AWS_REGION=eu-north-1
```

Adapter les noms exacts aux secrets deja utilises dans les workflows du depot applicatif.

### 7. Creer les parametres SSM

Avant le premier `terraform apply` complet de `infra/`, preparer au minimum:

```text
/darkmira-maintenance/dev/ghcr/token
```

Pour `/darkmira-maintenance/dev/app/env`, il faut connaitre l'endpoint RDS final. Deux options:

```text
Option A: creer un env temporaire avec un DATABASE_URL placeholder,
laisser le premier boot echouer, puis corriger SSM et relancer le deploy.

Option B: appliquer d'abord l'infra, recuperer l'endpoint RDS,
creer le parametre SSM final, puis remplacer l'EC2 ou relancer le user_data/deploy.
```

Option recommandee: creer l'infra, recuperer l'endpoint RDS, puis creer le SSM final et relancer le deploiement.

### 8. Creer l'infrastructure dans le nouveau compte

Depuis `infra/`:

```bash
terraform validate
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

Recuperer l'endpoint RDS:

```bash
aws rds describe-db-instances \
  --profile <NEW_AWS_PROFILE> \
  --region eu-north-1 \
  --db-instance-identifier darkmira-maintenance-dev-mysql \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text
```

Mettre a jour `env.prod` avec:

```text
DATABASE_URL=mysql://app_user:<DB_PASSWORD>@<NEW_RDS_ENDPOINT>:3306/app?serverVersion=8.0
```

Puis creer ou remplacer `/darkmira-maintenance/dev/app/env`.

### 9. Restaurer la base depuis l'export nocturne

Les exports MySQL nocturnes sont envoyes dans le bucket S3 cree par:

```text
infra/mysql-backups.tf
```

Le nom du bucket est disponible via:

```bash
terraform output mysql_backup_bucket_name
```

Dans l'ancien compte, identifier le dernier dump:

```bash
aws s3 ls s3://<OLD_BACKUP_BUCKET>/mysql/ \
  --profile <OLD_AWS_PROFILE> \
  --region eu-north-1
```

Telecharger le dernier dump:

```bash
aws s3 cp \
  s3://<OLD_BACKUP_BUCKET>/mysql/<LATEST_DUMP>.sql \
  ./latest.sql \
  --profile <OLD_AWS_PROFILE> \
  --region eu-north-1
```

Uploader le dump dans le bucket du nouveau compte:

```bash
aws s3 cp \
  ./latest.sql \
  s3://<NEW_BACKUP_BUCKET>/mysql/restore/latest.sql \
  --profile <NEW_AWS_PROFILE> \
  --region eu-north-1 \
  --server-side-encryption AES256
```

Restaurer depuis l'EC2 applicative du nouveau compte. L'EC2 a deja acces a RDS et contient les outils MySQL/MariaDB installes par le user_data.

Ouvrir une session SSM sur la nouvelle EC2:

```bash
aws ssm start-session \
  --profile <NEW_AWS_PROFILE> \
  --region eu-north-1 \
  --target <NEW_EC2_INSTANCE_ID>
```

Puis executer sur l'EC2:

```bash
set -euo pipefail

aws s3 cp s3://<NEW_BACKUP_BUCKET>/mysql/restore/latest.sql /tmp/latest.sql
cd /opt/darkmira-maintenance

eval "$(python3 - <<'PY'
import shlex
from urllib.parse import unquote, urlparse

database_url = None

with open(".env", encoding="utf-8") as handle:
    for raw_line in handle:
        line = raw_line.strip()
        if line.startswith("DATABASE_URL="):
            database_url = line.split("=", 1)[1].strip().strip("'\"")
            break

if not database_url:
    raise SystemExit("DATABASE_URL is missing from /opt/darkmira-maintenance/.env")

parsed = urlparse(database_url)

print("DB_HOST=" + shlex.quote(parsed.hostname or ""))
print("DB_PORT=" + shlex.quote(str(parsed.port or 3306)))
print("DB_USER=" + shlex.quote(unquote(parsed.username or "")))
print("DB_PASSWORD=" + shlex.quote(unquote(parsed.password or "")))
PY
)"

mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" < /tmp/latest.sql
rm -f /tmp/latest.sql
```

Apres restauration, lancer les migrations Symfony:

```bash
aws ssm send-command \
  --profile <NEW_AWS_PROFILE> \
  --region eu-north-1 \
  --instance-ids <NEW_EC2_INSTANCE_ID> \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["/opt/darkmira-maintenance/deploy-release.sh"]'
```

### 10. Verifier les containers

Sur l'EC2:

```bash
sudo docker compose \
  --env-file /opt/darkmira-maintenance/.env \
  -f /opt/darkmira-maintenance/docker-compose.prod.yml \
  ps
```

Les services attendus sont:

```text
app
nginx
messenger-worker
scheduler
```

Verifier les logs CloudWatch:

```text
/darkmira-maintenance/dev/ec2
/darkmira-maintenance/dev/docker
/aws/lambda/darkmira-maintenance-dev-night-scheduler
```

### 11. Verifier le deploiement automatique

Dans le depot applicatif:

```text
1. Verifier que le workflow de deploy utilise le nouvel ARN AWS.
2. Lancer un workflow_dispatch ou pousser une image de test.
3. Verifier que GitHub assume le role du nouveau compte.
4. Verifier que SSM execute /opt/darkmira-maintenance/deploy-release.sh.
5. Verifier que les images GHCR sont bien tirees par l'EC2.
```

En cas d'erreur GHCR:

```text
Verifier /darkmira-maintenance/dev/ghcr/token.
Le token doit etre valide et avoir read:packages sur les packages GHCR.
```

En cas d'erreur OIDC:

```text
Verifier le subject GitHub dans la trust policy:
repo:<owner>/<repo>:ref:refs/heads/<branch>
```

### 12. Bascule finale

Avant bascule:

```text
1. Stopper temporairement les ecritures sur l'ancien environnement si possible.
2. Lancer un dernier backup MySQL sur l'ancien EC2:
   /opt/darkmira-maintenance/backup-mysql.sh
3. Restaurer ce dernier dump sur le nouveau RDS.
4. Lancer /opt/darkmira-maintenance/deploy-release.sh sur le nouvel EC2.
5. Tester l'URL ALB du nouveau compte.
```

Basculer ensuite le DNS applicatif vers le nouvel ALB.

Apres bascule:

```text
1. Surveiller CloudWatch logs.
2. Verifier les jobs messenger et scheduler.
3. Verifier l'envoi d'emails / OAuth Gmail.
4. Verifier les appels OpenAI.
5. Verifier les actions GitHub faites par GITHUB_TOKEN.
6. Verifier que le scheduler nocturne fait bien le backup puis stop/start.
```

## Nettoyage de l'ancien compte

Ne supprimer l'ancien compte qu'apres plusieurs jours de validation.

Avant destruction:

```text
1. Conserver une copie locale ou S3 societe du dernier dump MySQL.
2. Exporter les parametres SSM necessaires de maniere securisee.
3. Verifier que plus aucun workflow GitHub ne pointe vers l'ancien account id.
4. Verifier qu'aucun DNS ne pointe vers l'ancien ALB.
```

Puis detruire l'infra ancienne:

```bash
cd infra
terraform plan -destroy -var-file=dev.tfvars
terraform destroy -var-file=dev.tfvars
```

Garder le bucket Terraform state ancien tant que l'audit de migration n'est pas termine.

## Points a corriger dans le code avant migration definitive

Pour rendre les prochaines migrations plus propres:

```text
1. Remplacer l'account id code en dur dans infra/github-app-deploy.tf par une
   variable ou un data source aws_caller_identity.
2. Ajouter un output Terraform pour l'ARN du role github-actions-app-deploy.
3. Ajouter un output Terraform pour l'endpoint RDS.
4. Eviter de commiter infra/dev.tfvars s'il contient des donnees personnelles
   comme une cle SSH ou une IP admin.
5. Eventuellement parametrer APP_DIR si le nom runtime doit changer.
```
