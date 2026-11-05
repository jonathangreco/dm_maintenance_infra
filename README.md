# AWS Symfony POC IaC

Ce dépôt contient l'infrastructure as code de Darkmira Service (application PHP/Symfony) et de Darkmira Analyseur (tâches Fargate).

## Objectif

Recréer progressivement une infrastructure AWS capable d'héberger une application Symfony dockerisée.

Architecture cible progressive :

```text
Internet
  -> Application Load Balancer public
  -> EC2 applicative
  -> Docker / Symfony
  -> RDS PostgreSQL 17 privé
  -> ECS Fargate : tâches de Darkmira Analyseur, dossiers d'étape sur S3
```

## Runtime applicatif EC2

L'EC2 installe Docker au boot, rend `infra/docker-compose.prod.yml.tftpl`
(`app`, `nginx`, `analyzer-worker`, `mail-worker`, `mailer`) et lance
`deploy.sh release` (migrations comprises). Chaque service charge
`/opt/darkmira-maintenance/.env`.

Le paramètre SSM SecureString `/darkmira-maintenance/dev/app/env` porte
**les secrets seulement** (jamais dans Terraform) :

```text
APP_SECRET=<32 octets aléatoires en hexadécimal>
APP_SECRETS_ENCRYPTION_KEY=<32 octets en base64 : openssl rand -base64 32>
DATABASE_URL="postgresql://app_user:<mot de passe RDS>@<endpoint RDS>:5432/app?serverVersion=17&charset=utf8"
LOCK_DSN="postgresql+advisory://app_user:<mot de passe RDS>@<endpoint RDS>:5432/app"
```

`user_data` y ajoute ce que Terraform connaît : images, `AWS_REGION`,
`DEFAULT_URI` (adresse HTTP de l'ALB), `TRUSTED_PROXIES` (CIDR du VPC),
`MAILER_DSN` (Mailpit), `MAILER_FROM`, `ANALYZER_ECS_*`, `ANALYZER_BUCKET`,
`DOCUMENTS_BUCKET`.

Sans domaine, aucun e-mail ne part : Mailpit les garde. Les lire :
`ssh -L 8025:localhost:8025 ec2-user@<ip publique>`, puis
http://localhost:8025.

### Premier déploiement

1. Images : depuis `~/www/darkmira_analyseur`, `make prepare-image` ; puis,
   depuis `~/www/Darkmira_service`, `docker login ghcr.io` et `make publish`.
2. `terraform -chdir=infra apply -var-file=dev.tfvars` (mot de passe RDS par
   `TF_VAR_db_password`). La base MySQL de l'ancien POC est remplacée par
   PostgreSQL : ses données sont perdues.
3. Secret de registre des tâches : remplacer le placeholder du secret
   Secrets Manager `<project>-<env>/agent-runner/registry` par
   `{"username":"jonathangreco","password":"<PAT read:packages>"}`.
4. Paramètre SSM `app/env` (ci-dessus), avec l'endpoint RDS de
   `terraform output`.
5. Sur l'EC2 : `/opt/darkmira-maintenance/deploy-release.sh`, puis
   `docker compose --env-file .env -f docker-compose.prod.yml run --rm app php bin/console app:create-super-admin`.

Le token GHCR de l'EC2 est lu depuis :

```text
/darkmira-maintenance/dev/ghcr/token
```

``` AWS command to regenerate Github Token
aws ssm put-parameter \
--region eu-north-1 \
--name /darkmira-maintenance/dev/ghcr/token \
--type SecureString \
--value 'TON_TOKEN_GITHUB' \
--overwrite
```

## Variables d'environnement, SSM et Docker

Les variables d'environnement applicatives ne sont pas stockees directement dans Terraform ni injectees directement par AWS dans Docker. Le flux reel est :

```text
AWS SSM Parameter Store
  -> EC2 user_data
  -> /opt/darkmira-maintenance/.env
  -> docker compose --env-file .env
  -> environment du service Docker
  -> variables visibles dans le container
```

### Parametres SSM utilises

Les noms des parametres SSM sont configures dans `infra/dev.tfvars` :

```hcl
app_env_ssm_parameter_name    = "/darkmira-maintenance/dev/app/env"
ghcr_token_ssm_parameter_name = "/darkmira-maintenance/dev/ghcr/token"
```

Le parametre `/darkmira-maintenance/dev/app/env` doit etre un `SecureString` contenant les secrets de Darkmira Service (voir « Runtime applicatif EC2 ») :

```env
APP_SECRET=...
APP_SECRETS_ENCRYPTION_KEY=...
DATABASE_URL=...
LOCK_DSN=...
```

Le parametre `/darkmira-maintenance/dev/ghcr/token` contient seulement le token GitHub utilise pour `docker login ghcr.io`.

### Droits IAM de l'EC2

Terraform attache un role IAM a l'instance EC2. Ce role autorise uniquement la lecture des parametres SSM necessaires :

```text
ssm:GetParameter sur /darkmira-maintenance/dev/app/env
ssm:GetParameter sur /darkmira-maintenance/dev/ghcr/token
```

L'EC2 peut donc recuperer ces secrets sans cle AWS locale.

### Creation du fichier .env sur l'EC2

Au boot, le script `infra/user_data_app.sh.tftpl` recupere le parametre applicatif depuis SSM avec decryption :

```bash
aws ssm get-parameter \
  --region eu-north-1 \
  --name /darkmira-maintenance/dev/app/env \
  --with-decryption \
  --query "Parameter.Value" \
  --output text > /opt/darkmira-maintenance/.env
```

Puis le script ajoute des variables gerees par l'infra :

```env
APP_IMAGE=...
NGINX_IMAGE=...
NGINX_PORT=...
AWS_REGION=...
CLOUDWATCH_DOCKER_LOG_GROUP=...
```

Le fichier final utilise par Docker est donc :

```text
/opt/darkmira-maintenance/.env
```

### Injection dans Docker Compose

Le script de deploy lance Docker Compose avec ce fichier :

```bash
docker compose --env-file /opt/darkmira-maintenance/.env -f /opt/darkmira-maintenance/docker-compose.prod.yml up -d
```

Dans `infra/docker-compose.prod.yml.tftpl`, les variables sont ensuite transmises aux services via `environment` :

```yaml
environment:
  APP_SECRET: ${APP_SECRET:?APP_SECRET is required}
  DATABASE_URL: ${DATABASE_URL:?DATABASE_URL is required}
  GITHUB_TOKEN: ${GITHUB_TOKEN:?GITHUB_TOKEN is required}
```

Une fois le container demarre, ces variables sont visibles depuis le container :

```bash
sudo docker compose --env-file .env -f docker-compose.prod.yml exec app printenv APP_ENV
sudo docker compose --env-file .env -f docker-compose.prod.yml exec app printenv DATABASE_URL
```

Attention : `printenv` peut afficher des secrets. Ne pas copier-coller une sortie complete dans un canal public.

### Cas particulier du token GHCR

Le token GHCR n'est pas injecte dans le container applicatif. Il est lu depuis SSM uniquement au moment du deploy pour authentifier Docker :

```bash
GHCR_TOKEN="$(aws ssm get-parameter \
  --region eu-north-1 \
  --name /darkmira-maintenance/dev/ghcr/token \
  --with-decryption \
  --query "Parameter.Value" \
  --output text)"

printf '%s' "$GHCR_TOKEN" | docker login ghcr.io \
  --username jonathangreco \
  --password-stdin
```

Si le deploy echoue avec `Get "https://ghcr.io/v2/": denied: denied`, le token SSM `/darkmira-maintenance/dev/ghcr/token` est probablement invalide, expire, ou sans acces `read:packages`.

### Mettre a jour les variables applicatives

Pour remplacer le fichier d'environnement applicatif dans SSM :

```bash
aws ssm put-parameter \
  --region eu-north-1 \
  --name /darkmira-maintenance/dev/app/env \
  --type SecureString \
  --value file://env.prod \
  --overwrite
```

Ensuite, relancer `/opt/darkmira-maintenance/deploy.sh refresh` ou `/opt/darkmira-maintenance/deploy-release.sh`. Ces scripts regenerent `/opt/darkmira-maintenance/.env` depuis SSM avant de relancer Docker Compose.

## Darkmira Analyseur (ECS Fargate)

Activé par `enable_agent_runner = true`. Une définition de tâche par
commande (`darkmira-analyzer-fetch|install|index|plan|read`,
`infra/analyzer-tasks.tf`), lancée par l'application (`EcsAnalyzerRunner`)
sur le cluster `<project>-<env>-agent-runner`. Le dossier d'étape vit sous
`s3://<ANALYZER_BUCKET>/runs/<étape>/` ; les conteneurs `init`, `analyzer`,
`upload` (et `progress` pour `read`) le rapatrient, l'exécutent et le
renvoient.

- Réseau : sous-réseaux publics, IP publique, aucune entrée, sortie 443
  seulement ; pas de NAT. `index` sort aussi : Fargate tire l'image par
  l'interface de la tâche (dette nommée côté Darkmira Service).
- Secrets (clé du fournisseur d'IA) : jamais dans `RunTask` ; un objet
  `runs/<étape>/secrets/<exécution>.env` étiqueté `kind=secrets`, supprimé par
  l'application, effacé après un jour s'il reste.
- La Lambda `agent-runner-sweeper` arrête une tâche au-delà de
  `agent_runner_max_task_minutes`.
- Journaux : `/aws/ecs/<project>-<env>-agent-runner`.
