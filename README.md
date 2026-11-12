# Le Hub — guide de mise en place

Tant que la configuration n'est pas remplie, le site tourne en **mode démo** : données d'exemple, et tu es connecté en admin pour tester le panneau. Dès que tu remplis `SUPABASE_URL` et `SUPABASE_ANON_KEY`, il passe en vrai.

## Contenu du dossier

| Fichier | Rôle |
| --- | --- |
| `index.html` | Le site entier, à héberger sur Vercel |
| `assets/` | Logo (SVG, PNG 512 px pour l'icône Discord, favicon) |
| `supabase/schema.sql` | Tables, vérifications, badges et sécurité |
| `supabase/functions/claim-server/index.ts` | Fonction qui vérifie auprès de Discord qu'un membre gère bien un serveur |
| `bot-protect/hub_sync.py` | Module à ajouter à Protect (salons de vérification, rôles, forum, messages privés) |
| `bot-protect/.env.exemple` | Les variables à ajouter à la config de Protect |

## Protect et la connexion au site : oui, c'est relié

- **La connexion au site passe par l'application Discord de Protect.** Quand quelqu'un clique sur « Se connecter avec Discord », il voit « Protect » sur l'écran d'autorisation.
- **Le Hub utilise le même projet Supabase que ton dashboard Protect.** Toutes les tables du Hub commencent par `hub_` : elles ne touchent à aucune des tables du dashboard. Un même compte Discord sert pour le dashboard et pour le Hub.
- **Protect fait le lien côté Discord** grâce au module `hub_sync.py` : salons de vérification, rôles, forum et messages privés.

## Étape 1 — La base de données

1. Ouvre ton projet Supabase (celui du dashboard Protect).
2. Va dans *SQL Editor* puis *New query*, colle tout `supabase/schema.sql` et clique sur *Run*. Le script peut être relancé sans danger.

## Étape 2 — L'application Discord (Protect)

1. Sur discord.com/developers/applications, ouvre l'application **Protect**, puis *OAuth2*.
2. Dans *Redirects*, ajoute : `https://TON-PROJET.supabase.co/auth/v1/callback`. Si l'adresse y est déjà pour le dashboard, il n'y a rien à faire.
3. Note le *Client ID* et le *Client Secret*. Ne clique pas sur « Reset Secret » si ton dashboard l'utilise déjà : ça le couperait.

## Étape 3 — La connexion Discord dans Supabase

1. *Authentication* > *Sign In / Providers* > *Discord* : active-le et colle l'ID et le secret de Protect. Si c'est déjà fait pour le dashboard, ne change rien.
2. *Authentication* > *URL Configuration* > *Redirect URLs* : ajoute l'adresse du site, par exemple `https://le-hub.vercel.app/**`. Garde le *Site URL* actuel si le dashboard l'utilise.

## Étape 4 — La fonction de vérification des serveurs

1. Dans Supabase, va dans *Edge Functions* > *Deploy a new function* > *Via Editor*.
2. Nomme-la exactement `claim-server`.
3. Colle `supabase/functions/claim-server/index.ts`, puis clique sur *Deploy*. Supabase fournit lui-même les clés dont elle a besoin.

## Étape 5 — Le site

1. Dans `index.html`, en haut du script, remplis le bloc `CONFIG` :
   - `SUPABASE_URL` et `SUPABASE_ANON_KEY` : dans *Settings* > *API*, prends la clé **anon public**, jamais la clé service_role ;
   - `DISCORD_INVITE` : l'invitation de ton serveur du Hub ;
   - `PROTECT_INVITE` : le lien d'ajout de Protect, à générer dans *OAuth2* > *URL Generator*.
2. Crée un dépôt GitHub avec `index.html` et le dossier `assets`.
3. Sur Vercel, fais *Add New* > *Project*, importe le dépôt, choisis le framework *Other* et clique sur *Deploy*. Il n'y a aucune commande à lancer.

## Étape 6 — Te donner l'accès admin

1. Connecte-toi une fois sur le site avec ton compte Discord.
2. Dans *SQL Editor*, lance la commande suivante, avec ton identifiant Discord :

```sql
update public.hub_profiles set is_admin = true, status = 'valide' where discord_id = 'TON_ID_DISCORD';
```

3. Le bouton **Admin** apparaît alors en haut du site. Fais pareil pour chaque membre de ton staff qui doit avoir accès au panneau.

## Étape 7 — Le bot Protect

**Côté Discord, sur le serveur du Hub, crée :**
- **Salons privés staff** : `#vérif-serveurs`, `#vérif-profils`, `#logs-vérifications` (les demandes traitées y sont rangées avec le verdict) et `#commandes-studio`.
- **Trois catégories pour les contrats** : « Contrats en attente », « Contrats » et « Contrats archivés ». Elles doivent être invisibles pour @everyone et visibles pour le rôle staff. Le bot crée les tickets dedans et y ajoute les deux membres.
- **Un salon forum** `#je-recrute`, avec les tags Modération, Dev bot, Graphisme, FiveM et Community manager. Le bot les applique tout seul.
- **Les rôles** des badges. Place le rôle de Protect **au-dessus** de tous ces rôles, sinon il ne pourra pas les donner.

| Rôle | Donné par | Variable du .env |
| --- | --- | --- |
| Team Hub (ton rôle staff) | Toi, à la main sur Discord. Le site met le badge tout seul | `HUB_STAFF_ROLE_ID` |
| Fondateur certifié | Automatique : propriétaire d'une fiche validée | `ROLE_FONDATEUR_CERTIFIE` |
| Staff certifié | Automatique quand toutes les quêtes sont validées | `ROLE_STAFF_CERTIFIE` |
| Développeur bot, Développeur site, Graphiste | Le staff, dans le panneau admin | `ROLE_DEV_BOT`, `ROLE_DEV_SITE`, `ROLE_GRAPHISTE` |
| Fondateur+, Fondateur Pro, Talent+, Talent Vérifié | La formule du membre | `ROLE_FONDATEUR_PLUS`, `ROLE_FONDATEUR_PRO`, `ROLE_TALENT_PLUS`, `ROLE_TALENT_VERIFIE` |
| Expériences vérifiées | Le staff, dans le panneau admin | `ROLE_VERIFIE` |
| Client Studio | Automatique quand une commande passe en « Livrée » | `ROLE_CLIENT_STUDIO` |

**Côté fichiers de Protect :**

| Fichier | Action |
| --- | --- |
| `hub_sync.py` | **Nouveau** : place-le à côté de tes autres cogs |
| `.env` | **À compléter** : copie dedans les lignes de `.env.exemple` (voir juste en dessous). Les variables du Hub commencent par `HUB_` : ne touche pas à `SUPABASE_URL` / `SUPABASE_SERVICE_KEY` du dashboard |
| Fichier principal du bot | **À modifier** : ajoute une ligne de chargement, voir ci-dessous |
| Tous les autres fichiers | **À ne pas toucher** |

### Où mettre le .env

`.env.exemple` n'est **pas** un fichier à envoyer tel quel : c'est un modèle.

1. Sur Bot-Hosting.net, ouvre le gestionnaire de fichiers de Protect, à la racine, là où se trouve ton fichier principal (`main.py` ou `bot.py`).
2. **Si un fichier `.env` existe déjà** (celui qui contient ton token), ouvre-le et colle à la fin toutes les lignes de `.env.exemple`.
3. **S'il n'existe pas**, crée un fichier nommé exactement `.env` (avec le point, sans rien après), et colle les lignes dedans.
4. Remplis chaque valeur : clic droit sur un salon ou un rôle, puis *Copier l'identifiant* (avec le mode développeur de Discord activé).
5. Vérifie que ton fichier principal charge bien le `.env` tout en haut, **avant** de charger les cogs :

```python
from dotenv import load_dotenv
load_dotenv()
```

Si ces deux lignes n'y sont pas, ajoute-les, et ajoute `python-dotenv` dans ton `requirements.txt`.

Ne publie jamais ce fichier sur GitHub : il contient la clé service_role.

### La ligne à ajouter au chargement des cogs

```python
await bot.load_extension("hub_sync")   # ou "cogs.hub_sync" si tes cogs sont dans un dossier cogs/
```

Le bot a besoin des permissions **Gérer les salons** et **Gérer les rôles** sur le serveur du Hub (pour créer et déplacer les tickets de contrat).

L'intent **Members** doit être activé (Developer Portal > Bot > Privileged Gateway Intents, et `intents.members = True`) pour que le bot puisse donner les rôles.

## Comment ça tourne ensuite

1. **Un membre crée sa fiche serveur.** La fonction vérifie avec Discord qu'il est propriétaire ou gestionnaire du serveur, et la fiche part « en attente ».
2. **Protect poste la demande** dans `#vérif-serveurs`, avec un avertissement s'il y a un lien dans la description, et les boutons **Valider** / **Refuser**. Refuser demande un motif.
3. **Le staff décide**, sur Discord ou dans le panneau admin du site : les deux sont synchronisés.
4. **Protect prévient la personne** en message privé, avec le motif en cas de refus.
5. **Les modifications repassent en vérification.** Toute modification d'une fiche ou d'un profil la renvoie en vérification automatiquement.
6. **Les droits sont revérifiés à chaque connexion.** Si quelqu'un perd ses droits sur un serveur, sa fiche est suspendue.

Les mêmes étapes valent pour les profils, avec `#vérif-profils`.

## Les contrats

1. **Le fondateur propose un contrat.** Il le fait depuis une candidature reçue (*Annonces et candidatures*) ou depuis le profil d'un membre, et remplit la durée, la date de début, la période d'essai, l'engagement, les horaires, la rémunération, les missions et les conditions.
2. **Protect ouvre un ticket privé** `#contrat-n-pseudo` dans « Contrats en attente », avec les deux membres et la Team Hub. Le ticket contient l'embed du contrat, le lien des règles et les boutons **Accepter**, **Refuser**, **Annuler** et **Signaler**.
3. **Accepté :** le ticket passe dans « Contrats » et reste ouvert. Les boutons deviennent **Terminer** et **Signaler**.
4. **Refusé, annulé, terminé ou rompu :** le ticket passe dans « Contrats archivés », en lecture seule pour les deux membres. Chacun peut ensuite laisser un avis sur le site.
5. **À la date de fin prévue,** le contrat se termine tout seul.
6. **Partout en même temps :** le site (*Mes contrats*, *Panneau admin > Contrats*) et le ticket sont synchronisés, et les deux membres sont prévenus en message privé.

Sécurité : seul le membre recruté peut accepter, seul le fondateur peut annuler, et un fondateur ne peut pas avoir plus de 5 propositions en attente.

## Les statistiques des serveurs

Pour les serveurs qui ont Protect, le bot met à jour toutes les 10 minutes :
- les membres, les membres en ligne, les bots, les salons, les rôles et les boosts ;
- les messages des dernières 24 h ;
- une courbe des membres sur 30 jours.

Sans Protect, la fiche affiche les membres et les membres en ligne, mis à jour à chaque connexion du fondateur, et en direct si le lien d'invitation est renseigné.

## Le journal d'activité

La base de données note toute seule ce qui se passe sur le site : validations, refus, badges, annonces, contrats, commandes et nouveaux membres. Personne ne peut écrire dans le journal à la main.

- **Coin « Activité »**, en bas à gauche du site, très discret : tout le monde y voit les actualités publiques (nouveau serveur vérifié, nouvelle annonce, contrat signé, badge reçu…). La Team Hub peut basculer sur « Tout (staff) ».
- **Panneau admin > Journal** : tout le journal, avec qui a fait quoi, et des filtres par type.

## Les outils admin

- Sur **chaque profil et chaque fiche serveur**, un bloc « Outils admin », que seuls les admins voient, permet de valider, refuser ou suspendre, de changer la formule, de donner les certifications et les quêtes, et d'ajouter les badges personnalisés.
- **Panneau admin > Membres et serveurs** liste tout le monde, quel que soit le statut, avec une recherche et des filtres (en attente, à compléter, refusés, suspendus…).

## Les badges

- **Automatiques :**
  - **Fondateur certifié** : propriétaire d'un serveur dont la fiche est validée.
  - **Client Studio** : une commande passée en « Livrée ».
  - **Team Hub** : avoir le rôle staff sur le Discord.
  - **Staff certifié** : avoir validé toutes les quêtes.
- **Donnés dans le panneau admin**, onglet *Gestion et badges* :
  - Développeur bot, Développeur site et Graphiste ;
  - les quêtes une par une ;
  - Expériences vérifiées et la formule ;
  - tes badges personnalisés.
- **Les quêtes** se modifient en haut du script de `index.html`, dans le bloc `QUESTS`. Le barème actuel est un exemple à adapter.

## Les formules et les rôles

Le paiement n'est pas encore branché. En attendant, **tu changes la formule d'un membre dans le panneau admin** (onglet *Gestion et badges*), et Protect lui donne le rôle dans les 5 minutes. On branchera ensuite Ko-fi, Patreon ou Whop pour que ça se fasse tout seul.

## Avant l'ouverture au public

- Remplir la page *Mentions légales / CGV / Confidentialité*.
- Tester tout le parcours avec un deuxième compte Discord (profil, fiche, annonce, candidature).
