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
