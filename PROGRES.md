# POS Flutter — Contexte du projet & suivi de progression

> **Pour l'agent LLM qui reprend ce projet** : Ce document décrit l'état exact du projet, les décisions d'architecture, les fonctionnalités implémentées et celles qui restent à faire. Lire entièrement avant de commencer.

---

## 1. Vue d'ensemble du projet

Application **Point de Vente (POS)** desktop **Windows** développée en **Flutter**.  
Fonctionne **100 % hors-ligne** avec base de données SQLite locale.  
Modèle **SaaS** : le développeur vend des licences aux boutiques.

### Stack technique
- **Flutter** (Windows desktop, SDK ^3.12.0)
- **SQLite** via `sqflite_common_ffi` (pas sqflite mobile)
- **Provider** (`ChangeNotifier`) — PAS Riverpod, PAS Bloc
- **http** `^1.2.2` — pour le mode multi-postes
- **crypto** — SHA-256 pour les mots de passe
- **pdf + printing** — impressions/PDF
- **fl_chart** — graphiques dans les rapports
- **file_selector** — sélecteur de fichiers natif Windows

---

## 2. Architecture générale

```
lib/
├── main.dart                          # Point d'entrée + routing à 4 niveaux
├── core/
│   ├── database/
│   │   └── db.dart                    # Singleton DB — toutes les opérations SQLite + proxy HTTP
│   ├── server/
│   │   ├── pos_server.dart            # Serveur HTTP intégré (mode serveur)
│   │   └── pos_client.dart            # Client HTTP (mode terminal)
│   ├── settings/
│   │   └── local_settings.dart        # pos_config.json — config serveur/terminal
│   └── theme/
│       └── app_theme.dart             # Thème Material 3 dynamique
├── providers/
│   ├── auth_provider.dart             # Authentification (login/pin/logout)
│   ├── settings_provider.dart         # Paramètres boutique depuis SQLite
│   └── pos_provider.dart              # État du POS (panier, vente en cours)
└── screens/
    ├── startup/
    │   ├── welcome_screen.dart        # Choix installation (nouveau/restaurer/serveur)
    │   └── server_connect_screen.dart # Connexion au serveur (IP + port + code)
    ├── license/
    │   └── license_screen.dart        # Activation de licence au démarrage
    ├── admin/
    │   └── saas_generator_screen.dart # Générateur de codes licence (opérateurs)
    ├── setup/
    │   └── setup_screen.dart          # Wizard configuration initiale boutique
    ├── login_screen.dart              # Connexion utilisateur (mot de passe + PIN)
    ├── main_shell.dart                # Shell principal (navigation latérale)
    ├── pos/                           # Écran caisse (POS)
    ├── products/                      # Gestion produits
    ├── customers/                     # Gestion clients
    ├── suppliers/                     # Gestion fournisseurs
    ├── employees/                     # Gestion employés
    ├── reports/                       # Rapports & analyses
    ├── banking/                       # Gestion bancaire
    ├── expenses/                      # Dépenses
    └── settings/
        └── settings_screen.dart       # Paramètres (6 onglets)
```

---

## 3. Routing au démarrage (4 niveaux)

```dart
// Dans main.dart → PosApp.build()
if (!settings.isLoaded)           → _SplashScreen()        // chargement
else if (!settings.hasValidLicense) → LicenseScreen()      // pas de licence
else if (!settings.isSetupComplete) → WelcomeScreen()      // première install
else if (auth.isLoggedIn)           → MainShell()          // connecté
else                                → LoginScreen()         // déconnecté
```

**`settings.hasValidLicense`** : vérifie `license_status == 'active'` + date d'expiration  
**`settings.isSetupComplete`** : vérifie `setup_completed == '1'` dans la table settings

---

## 4. Système de licences (SaaS)

> ⚠️ **Réécrit intégralement le 2026-07-05** — l'ancien système (checksum
> alphabet%36 + générateur embarqué protégé par un mot de passe en dur
> `PSGEN2026`) était cassable en quelques minutes : n'importe qui pouvait
> extraire le mot de passe du binaire et générer des licences lifetime
> gratuites, et Settings → Licence contenait même un bouton "Générer un code
> de test" **sans aucune protection**. Voir `[[gestock-securite-licence-reseau]]`
> pour le détail de l'audit qui a mené à cette refonte.

### Principe : signature Ed25519 + liaison machine
- Une licence est un texte signé, pas un simple code à checksum :
  `base64url(payload) + "." + base64url(signature)`.
- Le payload (pipe-délimité) : `1|TYPE|CLIENT|ISSUED_ISO|HWID1,HWID2,...`
- La clé **publique** Ed25519 est embarquée dans l'app
  (`lib/core/license/license_public_key.dart`) — elle permet de **vérifier**
  une licence mais jamais d'en **forger** une.
- La clé **privée** n'existe que dans l'outil séparé
  `../gestock_license_tool/` (hors du dépôt `gestock`, jamais livré au
  client). Voir son `README.md` pour l'usage et les précautions de sauvegarde.
- Chaque licence est liée à un ou plusieurs identifiants machine (voir
  `HardwareId`, dérivé du `MachineGuid` Windows) : elle ne s'active que sur
  les postes dont l'ID a été inclus à la génération. Le client copie son ID
  depuis l'écran de licence et le transmet au vendeur pour obtenir sa clé.
- La durée part de la date d'émission **signée** (`issued`), pas de
  l'horloge locale du poste — impossible à prolonger en changeant la date
  système.
- **Vérification cryptographique à chaque démarrage** (`SettingsProvider._checkLicense`)
  — l'app ne se fie jamais à un simple indicateur stocké en base
  (`license_blob` est le seul champ persisté ; toute la validité est
  recalculée à chaque lancement).

### Types de licences
| Préfixe | Type | Durée |
|---------|------|-------|
| PM | monthly | 30 jours |
| P3 | 3months | 90 jours |
| P6 | 6months | 180 jours |
| PY | yearly | 365 jours |

*(Les anciens types `2years`/`lifetime` ont été retirés — licences à
renouveler uniquement, pas d'option illimitée.)*

### Générer une licence pour un client
Depuis `../gestock_license_tool/` :
```bash
dart pub get
dart run bin/generate_license.dart
```
Demande le nom du client, le type, et le(s) identifiant(s) machine — affiche
le bloc de licence à transmettre tel quel.

---

## 5. Mode multi-postes (Client-Serveur HTTP)

### Architecture
```
[Serveur POS] ←── réseau local ──→ [Terminal 1, 2, 3…]
    ↓                                      ↓
pos_server.dart                    pos_client.dart
HttpServer (port 4321)             http.post() vers IP:port
SQLite local                       Proxy SQL via HTTP
```

### Sur le serveur (poste principal)
1. Aller dans **Paramètres → Réseau**
2. Optionnel : changer le port (défaut 4321)
3. Cliquer **"Démarrer le serveur"**
4. L'écran affiche : adresses IP LAN + port + **code d'accès** (10 caractères)

### Sur le terminal (autre poste)
1. Écran de licence → **"Se connecter à un serveur existant"**  
   OU WelcomeScreen → **"Se connecter à un serveur"**
2. Entrer : **IP du serveur** + **port** + **code d'accès**
3. Tester → Se connecter
4. `SettingsProvider.load()` lit depuis le serveur → routing avance automatiquement

### Fichiers config
- **`pos_config.json`** (à côté de l'exe) : stocke `server_mode`, `server_ip`, `server_port`, `server_token`
- Chargé dans `main()` AVANT `runApp` via `LocalSettings.initialize()`
- Au démarrage en mode terminal : `PosClient.instance.configure(ip, port, token)` est appelé

### Routes HTTP du serveur
```
GET  /ping                        → health check (auth requis)
POST /sql                         → proxy SQL générique {type, sql, params}
POST /api/create-sale             → vente atomique {sale, items}
POST /api/void-sale               → annulation {id}
POST /api/add-bank-transaction    → transaction bancaire atomique
POST /api/bulk-import             → import CSV produits {rows}
```
### Sécurité réseau (refonte 2026-07-05)
> ⚠️ Avant cette date : token de 6 caractères sans limite de tentatives,
> corps des requêtes en clair, route `/sql` acceptant du SQL totalement
> libre (un terminal compromis pouvait vider/altérer toute la base). Voir
> `[[gestock-securite-licence-reseau]]`.

- **Jeton jamais transmis en clair** : `NetworkCrypto.authTag(token)` dérive
  (SHA-256) la valeur envoyée dans l'en-tête `x-pos-token` — le code d'accès
  brut ne circule jamais sur le réseau.
- **Corps chiffré** : AES-256-GCM, clé dérivée du token
  (`NetworkCrypto.encrypt`/`decrypt`), format `nonce.ciphertext+mac` en
  base64url. Réponses d'erreur (401/404/500/429) restent en JSON clair (pas
  de donnée sensible).
- **Anti brute-force** : verrouillage progressif par IP après 5 échecs
  (30s, 60s, 120s… jusqu'à ~8 min), voir `PosServer._attempts`.
- **Token** : 10 caractères (alphabet 32 symboles, générés avec
  `Random.secure()`), au lieu de 6.
- **Liste blanche SQL** (`PosServer._isSqlAllowed`) : la route `/sql` rejette
  toute requête contenant `;`, `PRAGMA`, `ATTACH`, `DROP`, `ALTER`,
  `CREATE`, `VACUUM`, ou référençant une table hors du schéma connu de
  l'app. Le type `execute` (DDL libre) a été retiré — seuls
  `query/insert/update/delete` restent supportés.

### db.dart — Helpers de routing local/distant
```dart
_q(sql, params)     → rawQuery
_ri(sql, params)    → rawInsert
_ru(sql, params)    → rawUpdate
_ex(sql, params)    → execute
_ci(table, map, ca) → convenience insert
_cu(table, map, ...)→ convenience update
_cd(table, ...)     → convenience delete
_cq(table, ...)     → convenience query
```
Chaque helper vérifie `PosClient.instance.isConnected` et route vers HTTP ou SQLite.

---

## 6. Base de données SQLite

### Schéma (version 7)
| Table | Description |
|-------|-------------|
| settings | Clés/valeurs de configuration (business_name, currency, setup_completed, license_blob, etc.) |
| employees | Utilisateurs + rôles + permissions JSON + PIN + **salt** (mot de passe salé, v7) |
| categories | Catégories produits |
| products | Produits (stock, prix, coût, code-barre) |
| customers | Clients (solde crédit) |
| suppliers | Fournisseurs |
| sales | Ventes |
| sale_items | Lignes de vente |
| held_orders | Commandes en attente (mise en attente) |
| banks | Comptes bancaires |
| bank_transactions | Transactions bancaires |
| expense_heads | Catégories de dépenses |
| expenses | Dépenses |

### Clés importantes dans `settings`
- `setup_completed` : '0' ou '1'
- `license_blob` : bloc de licence signé Ed25519 complet (voir section 4) — seul champ
  persisté, toute la validité (type/expiration/machine) est recalculée à chaque
  démarrage, jamais lue depuis un champ de statut séparé
- `business_name`, `business_address`, `business_phone`, `currency_code`, `currency_symbol`
- `logo_path`, `theme_mode`, `theme_color`, `tax_rate`, `receipt_footer`

### Mots de passe employés (PBKDF2 salé, refonte 2026-07-05)
> ⚠️ Avant cette date : SHA-256 simple sans sel (vulnérable aux tables
> arc-en-ciel et au rejeu réseau). Voir `[[gestock-securite-licence-reseau]]`.

- `lib/core/utils/password_hasher.dart` : PBKDF2-HMAC-SHA256, 50 000
  itérations, sel aléatoire 16 octets par utilisateur (colonne `salt`).
- Migration silencieuse : un compte créé avant l'ajout du sel (colonne
  `salt` vide) est vérifié avec l'ancien format puis re-haché
  automatiquement à la prochaine connexion réussie (`DB.login`).

---

## 7. Fonctionnalités IMPLÉMENTÉES ✅

### Démarrage & Licence
- [x] **SplashScreen** pendant le chargement des settings
- [x] **LicenseScreen** : collage licence signée, affichage identifiant machine, restauration backup, connexion serveur
- [x] **WelcomeScreen** : choix installation (nouveau/restaurer/serveur)
- [x] **SetupScreen** : wizard configuration boutique (nom, devise, admin)
- [x] **Outil générateur de licences** (`../gestock_license_tool/`, hors app) : script CLI séparé, clé privée jamais livrée au client
- [x] **Validation de licence** : signature Ed25519 + liaison machine + expiration, revérifiée à chaque démarrage

### Authentification
- [x] Login par identifiant/mot de passe (PBKDF2-HMAC-SHA256 salé)
- [x] Login par PIN (4-6 chiffres)
- [x] Rôles & permissions (admin, cashier, custom)
- [x] Restauration backup depuis LoginScreen

### POS (Caisse)
- [x] Écran de vente (panier, recherche produits, code-barre)
- [x] Modes de paiement : espèces, carte, crédit
- [x] Mise en attente / reprise commande
- [x] Impression de reçu PDF
- [x] Annulation de vente (void)

### Gestion
- [x] Produits (CRUD, import CSV bulk, ajustement stock)
- [x] Catégories
- [x] Clients (solde crédit)
- [x] Fournisseurs
- [x] Employés (CRUD, changement mot de passe)

### Rapports
- [x] Dashboard (ventes du jour, semaine, top produits)
- [x] Dashboard mensuel (chiffre d'affaires, profit, dépenses)
- [x] Rapport de ventes (plage dates)
- [x] Rapport de dépenses
- [x] Analyse des ventes (par employé, par heure)
- [x] Mouvements de stock
- [x] Activité récente

### Banque & Dépenses
- [x] Gestion des comptes bancaires
- [x] Transactions bancaires (dépôt/retrait)
- [x] Dépenses par catégorie

### Paramètres (6 onglets)
- [x] **Boutique** : nom, adresse, téléphone, logo
- [x] **Sécurité postes** : gestion utilisateurs/rôles
- [x] **Apparence** : thème (clair/sombre), couleur principale
- [x] **Imprimante** : config impression
- [x] **Licence** : affichage licence, identifiant machine, collage/désactivation
- [x] **Réseau** : démarrage/arrêt serveur HTTP, affichage IP + code d'accès

### Mode Multi-postes
- [x] `PosServer` : serveur HTTP intégré avec proxy SQL
- [x] `PosClient` : client HTTP avec tous les endpoints
- [x] `db.dart` routage automatique local ↔ distant
- [x] `LocalSettings` : persistance config serveur dans pos_config.json
- [x] `ServerConnectScreen` : formulaire IP + port + code
- [x] Bannière "Mode serveur" dans LoginScreen avec déconnexion
- [x] Connexion serveur disponible depuis LicenseScreen et WelcomeScreen

### Télémétrie / rapport d'erreurs
- [x] **`CrashReportService`** (ajouté 2026-07-05) : capture les erreurs non
  gérées via `FlutterError.onError` (framework) et `runZonedGuarded` (async/
  autres), et envoie un rapport texte (version, OS, message, stack trace) par
  email au support — **réutilise la configuration SMTP de la sauvegarde
  cloud** (pas de nouveau compte à créer). Ne fonctionne donc que si le
  commerçant a configuré cette section.
- Limité à 1 envoi / 15 minutes pour éviter le spam en cas d'erreur en boucle.
- Toggle indépendant `crash_reporting_enabled` (Settings → Sécurité postes,
  activé par défaut si SMTP configuré).
- Destinataire fixe (`_supportEmail` dans `crash_report_service.dart`), pas
  configurable par le commerçant — c'est l'adresse du développeur.

### Mise à jour automatique
- [x] **`UpdateService`** (ajouté 2026-07-05) : vérifie la dernière version via
  l'API publique des GitHub Releases du dépôt `sonyjo64/gestock` (public,
  aucun jeton embarqué requis). Vérification silencieuse 3s après l'entrée
  dans `MainShell`, + bouton manuel "Vérifier" dans Settings → Licence.
- [x] Téléchargement de l'installateur avec barre de progression
  (`update_dialog.dart`), puis lancement détaché + fermeture de l'app
  (`exit(0)`) pour permettre à Inno Setup de remplacer les fichiers —
  Windows ne permet pas d'écraser un `.exe` en cours d'exécution.
- [x] `pos_data` étant exclu du contenu de l'installateur, une mise à jour
  ne touche jamais la base de données existante du client.
- ⚠️ **À chaque nouvelle version** : incrémenter `kAppVersion`
  (`lib/core/app_version.dart`), `pubspec.yaml`, et `MyAppVersion`
  (`installer.iss`) ensemble, puis publier une nouvelle GitHub Release
  (tag `vX.Y.Z`) avec l'installateur en pièce jointe :
  `gh release create vX.Y.Z installer/Gestock_Setup_vX.Y.Z.exe --repo sonyjo64/gestock --title "Gestock vX.Y.Z" --notes "..."`

### Sauvegarde / Restauration
- [x] Backup manuel depuis Settings
- [x] Restauration depuis LicenseScreen, WelcomeScreen, LoginScreen
- [x] **Sauvegarde locale automatique** (`AutoBackupScheduler`, ajouté 2026-07-05) :
  toutes les heures pendant que l'app est ouverte (pas de tâche planifiée
  système), dossier configurable (`auto_backup_dir`), conserve les 48
  dernières copies. Démarré dans `main()`, désactivé si le poste est un
  terminal connecté à un serveur distant (pas de base locale à sauvegarder).
- [x] **Sauvegarde cloud par email** (`BackupService.sendBackupEmail`, SMTP
  générique via le package `mailer`) : une fois par jour si activé, avec
  configuration propre à chaque commerçant (serveur/port/utilisateur/mot de
  passe/destinataire dans Settings → Sécurité postes). Remplace l'ancien
  bouton "Envoyer en ligne" qui uploadait la base **en clair vers 0x0.st**
  (hébergeur de fichiers public anonyme — fuite de données potentielle,
  corrigé le 2026-07-05).

---

## 8. Fonctionnalités RESTANTES / TODO 🔲

### Priorité HAUTE
- [ ] **Auto-démarrage du serveur** : option dans Settings → Réseau pour démarrer le serveur automatiquement au lancement de l'app (persister `server_auto_start` dans `local_settings.dart` + appeler `PosServer.instance.start()` dans `main()` si activé)
- [ ] **Gestion des erreurs réseau** : dialog/snackbar si le terminal perd la connexion au serveur pendant une vente
- [ ] **Reconnexion automatique** : si `PosClient.isConnected` mais serveur inaccessible → retry ou fallback en mode local
- [x] ~~**Sauvegarde automatique**~~ — fait le 2026-07-05, voir section 7 (Sauvegarde/Restauration)
- [x] ~~**Backup depuis Settings** : choisir le dossier de destination~~ — fait le 2026-07-05 (`auto_backup_dir`)

### Priorité MOYENNE
- [ ] **Reçu personnalisé** : logo boutique sur le reçu PDF, pied de page configurable
- [ ] **Gestion des retours** (return/refund) : créer une vente avec quantité négative ou table dédiée
- [ ] **Rapport de stock** : alerte stock bas configurable (seuil min_stock par produit)
- [ ] **Export Excel/CSV** : rapports exportables (ventes, stock, clients)
- [ ] **Gestion des devis** : créer un devis avant de le transformer en vente
- [ ] **Remises clients** : remise par défaut par client (%)
- [ ] **Taxes multiples** : TVA par produit ou par catégorie (actuellement taux global)
- [ ] **Code-barre scan** : intégration scanner USB (déjà basique, à améliorer)

### Priorité BASSE
- [ ] **Thème par boutique** : couleur et logo dans l'écran de connexion
- [ ] **Notification stock bas** : badge/alerte dans la navigation
- [ ] **Journal d'activité** : log des actions critiques (connexions, ventes annulées, modifs)
- [ ] **Mode hors-ligne terminal** : si serveur inaccessible, travailler localement et synchroniser à la reconnexion (complexe)
- [ ] **QR code de connexion** : afficher un QR code sur le serveur contenant IP+port+code → le terminal scanne pour remplir automatiquement

---

## 9. Décisions d'architecture importantes

### Provider pattern
Utilise `ChangeNotifier` via le package `provider`. NE PAS migrer vers Riverpod sans refactoring complet.

### SQLite en mode serveur
En mode terminal, **toutes** les opérations SQLite sont proxifiées via HTTP vers le serveur. Le terminal n'a PAS de base SQLite locale (sauf pour les backups de restauration). C'est le design intentionnel.

### Hachage des mots de passe
PBKDF2-HMAC-SHA256 salé (`lib/core/utils/password_hasher.dart`, voir section 6).
Le terminal hache le mot de passe localement avant de l'envoyer au serveur. Le
serveur compare avec le hash stocké. Les mots de passe en clair ne transitent
jamais, et le corps de la requête est lui-même chiffré (voir section 5).

### Licence : pourquoi Ed25519 et pas un simple secret partagé
Un HMAC/secret symétrique embarqué dans l'app aurait le même défaut que
l'ancien système : la clé nécessaire pour *vérifier* une licence hors-ligne
serait aussi celle qui permet d'en *forger*. Ed25519 (asymétrique) permet
d'embarquer uniquement la clé publique dans l'app livrée au client — la clé
privée ne quitte jamais l'outil générateur séparé. Voir section 4 et
`[[gestock-securite-licence-reseau]]`.

### Transactions atomiques
Les transactions SQLite (createSale, voidSale, addBankTransaction, bulkImport) ont des endpoints HTTP dédiés sur le serveur qui les exécutent localement de manière atomique.

### pos_config.json
Fichier JSON à côté de l'exécutable (pas dans %APPDATA%). Contient uniquement la config réseau (mode terminal, IP, port, token). Chargé **avant** `runApp` pour pouvoir configurer `PosClient` avant l'ouverture de la base.

---

## 10. Comment continuer avec un autre modèle LLM

### Fichiers à lire en priorité
1. `lib/main.dart` — routing global
2. `lib/core/database/db.dart` — opérations BDD (local + remote)
3. `lib/core/server/pos_server.dart` — serveur HTTP (chiffré, anti brute-force)
4. `lib/core/server/pos_client.dart` — client HTTP
5. `lib/core/server/network_crypto.dart` — chiffrement AES-GCM des échanges réseau
6. `lib/core/license/license_service.dart` — vérification de licence Ed25519
7. `lib/core/license/hardware_id.dart` — identifiant machine
8. `lib/core/settings/local_settings.dart` — config locale
9. `lib/providers/settings_provider.dart` — state management settings + validité licence
10. `../gestock_license_tool/` (hors dépôt) — génération de licences, clé privée
11. `lib/core/services/update_service.dart` — vérification/téléchargement des mises à jour (GitHub Releases)
12. `lib/core/services/auto_backup_scheduler.dart` / `backup_service.dart` — sauvegarde automatique locale + email

### Pour tester le projet
```bash
# Depuis le dossier pos_flutter :
flutter run -d windows           # Mode debug
flutter build windows --release  # Build release
```

### Structure des providers
```dart
// Dans main() via MultiProvider :
ChangeNotifierProvider(create: (_) => AuthProvider())
ChangeNotifierProvider(create: (_) => SettingsProvider()..load())
ChangeNotifierProvider(create: (_) => PosProvider())
```

### Convention de nommage
- Screens : `XxxScreen` (StatefulWidget)
- Providers : `XxxProvider`
- Private widgets dans le même fichier : `_XxxWidget`
- DB helpers privés : `_q`, `_ri`, `_ru`, `_ex`, `_ci`, `_cu`, `_cd`, `_cq`

---

## 11. Dépendances clés (pubspec.yaml)

```yaml
sqflite_common_ffi: ^2.3.4   # SQLite pour Windows/Linux/macOS
provider: ^6.1.5              # State management
http: ^1.2.2                  # Requêtes HTTP (mode terminal)
crypto: ^3.0.6                # SHA-256 (legacy hash migration, HardwareId)
cryptography: ^2.7.0          # Ed25519 (licence) + AES-GCM (réseau)
mailer: ^6.1.0                 # Envoi SMTP (sauvegarde cloud par email)
file_selector: ^1.0.3         # Sélecteur fichiers natif
pdf: ^3.11.3                  # Génération PDF
printing: ^5.14.2             # Impression
fl_chart: ^0.71.0             # Graphiques
intl: ^0.20.2                 # Formatage dates/nombres
```

---

*Dernière mise à jour : 2026-07-05 — refonte sécurité (licence Ed25519 + liaison machine, chiffrement réseau AES-GCM, mots de passe PBKDF2 salés) + sauvegarde automatique locale/cloud email + mise à jour automatique via GitHub Releases (dépôt public `sonyjo64/gestock`) + rapport d'erreurs par email*  
*Développeur : josony1994@gmail.com*
