Je vais analyser l’infra localement, en commençant par la structure Terraform et le script `user_data_app.sh.tftpl`, puis je te donnerai uniquement des pistes de réduction de coûts sans modifier les fichiers.

Le dépôt contient une stack Terraform classique `ALB + EC2 + RDS + CloudWatch`, avec un bootstrap EC2 qui installe Docker, CloudWatch Agent et lance Docker Compose. Je vais lire les modules principaux pour identifier les ressources qui expliquent le budget mensuel.

Les coûts probables ne viennent pas du script user-data lui-même, mais des choix structurels autour de l’ALB, du RDS et éventuellement du NAT Gateway. Je vais compléter avec les variables, valeurs `tfvars`, CloudWatch et security groups pour chiffrer qualitativement les leviers.

Pour éviter des estimations obsolètes, je vais vérifier les tarifs AWS actuels sur les pages officielles, surtout pour `eu-north-1`. Ensuite je relierai ces tarifs aux ressources déclarées dans Terraform.Je vais interroger les fichiers publics AWS Price List plutôt que deviner les montants. Cela permet d’obtenir des ordres de grandeur actuels par région sans toucher à l’infra.

La stack utilise bien `eu-north-1`. J’extrais maintenant les postes unitaires clés: EC2 `t3.micro`, RDS MySQL `db.t3.micro`, ALB, NAT Gateway et logs CloudWatch.

J’ai les versions de tarifs AWS en vigueur au 29 mai-2 juin 2026 selon les services. Je vais filtrer uniquement les SKU correspondant à cette architecture pour ne pas mélanger avec d’autres familles.

Le parsing des prix est en cours. En parallèle, je vérifie si le state local indique des ressources effectivement créées qui divergeraient des variables par défaut, notamment NAT activé ou types d’instances différents.

Le state Terraform existe localement, donc je peux confirmer l’architecture déployée sans appliquer quoi que ce soit. Je n’utiliserai ces infos que pour l’analyse des coûts.

Les prix extraits confirment un socle mensuel approximatif avant trafic: ALB environ 17,5 $/mo + LCU, EC2 t3.micro environ 7,9 $/mo hors EBS, RDS db.t3.micro environ 12,4 $/mo + stockage, CloudWatch selon volume. Je vérifie maintenant le NAT dans le state, car un NAT Gateway seul peut ajouter autour de 30 $/mo.

Le state local ne contient pas de `aws_nat_gateway`, donc le poste NAT n’explique pas les 80 $ actuels avec cette configuration. Le coût est probablement composé de l’ALB, RDS, EC2/EBS, logs CloudWatch, transferts et éventuellement CPU credits/ressources hors Terraform.

Je récupère les attributs effectifs depuis le state pour vérifier les tailles réelles. Si elles correspondent aux defaults, le budget de 80 $ implique probablement du trafic, des logs, des crédits CPU, ou des coûts AWS hors de ce dépôt.

Les tailles effectives sont les petites tailles prévues: EC2 `t3.micro`, RDS `db.t3.micro`, stockage RDS 20 Go, pas de backups RDS, pas de NAT. Je vérifie le disque EBS racine EC2 pour compléter l’estimation.

À ce stade, l’écart entre le socle estimé et les 80 $ suggère un point à vérifier côté AWS Billing/Cost Explorer: crédits CPU T3, trafic sortant/LCU ALB, ingestion CloudWatch, ou services non gérés par ce repo. Je vais consolider les pistes avec impact/priorité.

Le volume EBS racine ne semble pas être un gros poste; le state ne montre pas de volume volontairement surdimensionné. Je vais maintenant formuler les recommandations sans changement de code.

Je n’ai fait aucune modification. Les conclusions ci-dessous seront basées sur les fichiers Terraform, le state local et les tarifs AWS publics actuels en `eu-north-1`.

**Constat**
Aucune implémentation faite. D’après Terraform + state local, l’architecture déployée est :

- 1 EC2 `t3.micro` public
- 1 ALB public sur 2 subnets
- 1 RDS MySQL `db.t3.micro`, Single-AZ, 20 Go gp2
- CloudWatch Logs pour EC2 + Docker
- Pas de NAT Gateway dans le state local
- Région `eu-north-1`

Le socle théorique ne devrait pas atteindre 80 $ seul :

- EC2 `t3.micro`: environ 7,9 $/mo hors EBS
- RDS `db.t3.micro`: environ 12,4 $/mo + 2,4 $/mo stockage
- ALB: environ 17,5 $/mo + LCU selon trafic
- CloudWatch Logs: 0,54 $/Go ingéré, 0,028 $/Go-mo stocké
- NAT Gateway: absent ici, donc pas le coupable dans cette stack

Sources AWS: [EC2 Pricing](https://aws.amazon.com/ec2/pricing/), [RDS MySQL Pricing](https://aws.amazon.com/rds/mysql/pricing/), [NAT Gateway Pricing](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html).

**Pistes Prioritaires**
1. Supprimer l’ALB en dev
   Le plus gros levier évident. Pour une seule EC2, l’ALB coûte cher par rapport au service rendu. Alternative: exposer directement Nginx sur l’EC2 avec Elastic IP + Route53, éventuellement Caddy/Certbot pour TLS. Gain probable: ~18 à 25 $/mo.

2. Planifier l’arrêt hors horaires utiles
   Si c’est un environnement dev/demo, arrêter EC2 + RDS la nuit/week-end réduit fortement le coût. RDS arrêté continue à facturer le stockage, mais plus l’instance. Gain possible: 40 à 70 % selon usage.

3. Remplacer RDS par MySQL en conteneur pour dev
   Pour une démo non critique, MySQL dans Docker avec volume EBS peut supprimer le coût RDS. Gain probable: ~15 $/mo. Tradeoff: moins managé, backups/restore à gérer soi-même.

4. Réduire CloudWatch Logs
   Le compose envoie `app`, `nginx`, `messenger-worker`, `scheduler` vers CloudWatch. Les workers tournent avec `-vv`, donc potentiellement très verbeux. Passer les consumers en logs moins bavards et ne collecter que les logs utiles peut éviter une dérive. Gain dépend du volume.

5. Vérifier CPU credits T3
   RDS T3 peut facturer des CPU credits si la charge dépasse le baseline. AWS indique que RDS T3/T4g en Unlimited facture les crédits excédentaires. À vérifier dans Cost Explorer et CloudWatch: `CPUCreditBalance`, `CPUSurplusCreditsCharged`.

6. Éviter RDS si la base est peu utilisée
   Si l’application a une charge intermittente, RDS facture à l’heure même sans trafic. Alternatives possibles: SQLite/EBS pour démo, MySQL Docker, ou base externe moins chère selon contraintes.

7. Passer EC2 en Spot si tolérance à l’interruption
   Pour une démo, une instance Spot peut réduire le compute EC2. Gain modéré ici car `t3.micro` est déjà peu cher, mais utile si tu dois monter en taille.

**À Vérifier Dans AWS Billing**
Les 80 $ semblent supérieurs au coût attendu de cette stack seule. Je regarderais dans Cost Explorer par service :

- `EC2-Other`: EBS, data transfer, snapshots
- `Elastic Load Balancing`: ALB + LCU
- `RDS`: instance, stockage, CPU credits
- `CloudWatch`: logs ingestion
- Services hors Terraform: snapshots, anciens volumes, IP publiques inutilisées, autres régions

**Meilleure piste immédiate**
Pour un environnement dev/demo: supprimer l’ALB et exposer directement l’EC2, puis programmer l’arrêt EC2/RDS. C’est probablement le meilleur ratio économie/complexité.
