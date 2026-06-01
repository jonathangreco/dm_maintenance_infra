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
