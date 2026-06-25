# AWS Symfony POC IaC

Ce dépôt contient l'infrastructure as code du Projet de maintenance Darkmira.

## Objectif

Recréer progressivement une infrastructure AWS capable d'héberger une application Symfony dockerisée.

Architecture cible progressive :

```text
Internet
  -> Application Load Balancer public
  -> EC2 applicative
  -> Docker / Symfony
  -> RDS MySQL privé
```

## Runtime applicatif EC2

L'EC2 installe Docker au boot puis lance le compose prod depuis `infra/docker-compose.prod.yml.tftpl`.
Ce compose est derive de `/home/john/www/darkmira-maintenance/docker-compose.prod.yml`, avec RDS a la place du conteneur MySQL local.

Le fichier d'environnement runtime doit exister dans SSM SecureString :

```text
/darkmira-maintenance/dev/app/env
```

Il doit contenir au minimum les variables requises par l'application :

```text
APP_SECRET=...
DATABASE_URL=...
OPENAI_API_KEY=...
GITHUB_TOKEN=...
GMAIL_OAUTH_CLIENT_ID=...
GMAIL_OAUTH_CLIENT_SECRET=...
GMAIL_OAUTH_REFRESH_TOKEN=...
```

Le token GHCR est lu depuis :

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

Le parametre `/darkmira-maintenance/dev/app/env` doit etre un `SecureString` contenant un fichier `.env` complet, par exemple :

```env
APP_SECRET=...
DATABASE_URL=...
OPENAI_API_KEY=...
GITHUB_TOKEN=...
GMAIL_OAUTH_CLIENT_ID=...
GMAIL_OAUTH_CLIENT_SECRET=...
GMAIL_OAUTH_REFRESH_TOKEN=...
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
