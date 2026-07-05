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

### Format de la clé
```
XXXX-XXXX-XXXX-XXXX  (affichée avec tirets, 16 caractères sans tirets)
Positions 0-1  : préfixe type (PM/P3/P6/PY/P2/PL)
Positions 2-14 : caractères aléatoires de l'alphabet '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Position 15    : checksum = alphabet[sum_of_indices(0..14) % 36]
```

### Types de licences
| Préfixe | Type | Durée |
|---------|------|-------|
| PM | monthly | 30 jours |
| P3 | 3months | 90 jours |
| P6 | 6months | 180 jours |
| PY | yearly | 365 jours |
| P2 | 2years | 730 jours |
| PL | lifetime | Illimitée |

### Clés importantes (NE PAS SUPPRIMER)
- **Code maître opérateur** : `PSGEN2026` (accès au générateur SaaS)
- **Clé lifetime opérateur** : `PLPS-OFFA-DMIN-001O` (clé administrateur vérifiée mathématiquement)
- **Accès générateur** : depuis LicenseScreen (bouton discret "⚙ Opérateur") ou Settings → Licence

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
4. L'écran affiche : adresses IP LAN + port + **code d'accès** (6 caractères)

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
Auth : header `x-pos-token: <code>` sur toutes les requêtes.

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

### Schéma (version 3)
| Table | Description |
|-------|-------------|
| settings | Clés/valeurs de configuration (business_name, currency, setup_completed, license_*, etc.) |
| employees | Utilisateurs + rôles + permissions JSON + PIN |
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
- `license_code`, `license_type`, `license_status`, `license_activated_at`, `license_expiry`
- `business_name`, `business_address`, `business_phone`, `currency_code`, `currency_symbol`
- `logo_path`, `theme_mode`, `theme_color`, `tax_rate`, `receipt_footer`

---

## 7. Fonctionnalités IMPLÉMENTÉES ✅

### Démarrage & Licence
- [x] **SplashScreen** pendant le chargement des settings
- [x] **LicenseScreen** : activation licence, restauration backup, connexion serveur
- [x] **WelcomeScreen** : choix installation (nouveau/restaurer/serveur)
- [x] **SetupScreen** : wizard configuration boutique (nom, devise, admin)
- [x] **Générateur SaaS** (`SaasGeneratorScreen`) : génère des clés pour les clients
  - Protégé par code maître `PSGEN2026`
  - Accessible depuis LicenseScreen (bouton ⚙ Opérateur) et Settings → Licence
- [x] **Validation de licence** : checksum, type, expiration

### Authentification
- [x] Login par identifiant/mot de passe (SHA-256)
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
- [x] **Licence** : affichage licence, renouvellement, accès opérateur SaaS
- [x] **Réseau** : démarrage/arrêt serveur HTTP, affichage IP + code d'accès

### Mode Multi-postes
- [x] `PosServer` : serveur HTTP intégré avec proxy SQL
- [x] `PosClient` : client HTTP avec tous les endpoints
- [x] `db.dart` routage automatique local ↔ distant
- [x] `LocalSettings` : persistance config serveur dans pos_config.json
- [x] `ServerConnectScreen` : formulaire IP + port + code
- [x] Bannière "Mode serveur" dans LoginScreen avec déconnexion
- [x] Connexion serveur disponible depuis LicenseScreen et WelcomeScreen

### Sauvegarde / Restauration
- [x] Backup manuel depuis Settings
- [x] Restauration depuis LicenseScreen, WelcomeScreen, LoginScreen

---

## 8. Fonctionnalités RESTANTES / TODO 🔲

### Priorité HAUTE
- [ ] **Auto-démarrage du serveur** : option dans Settings → Réseau pour démarrer le serveur automatiquement au lancement de l'app (persister `server_auto_start` dans `local_settings.dart` + appeler `PosServer.instance.start()` dans `main()` si activé)
- [ ] **Gestion des erreurs réseau** : dialog/snackbar si le terminal perd la connexion au serveur pendant une vente
- [ ] **Reconnexion automatique** : si `PosClient.isConnected` mais serveur inaccessible → retry ou fallback en mode local
- [ ] **Sauvegarde automatique** : backup planifié (quotidien/hebdomadaire) avec chemin configurable
- [ ] **Backup depuis Settings** : le bouton de backup dans Settings → Boutique doit permettre de choisir le dossier de destination

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
SHA-256 via package `crypto`. Le terminal hache le mot de passe localement avant de l'envoyer au serveur. Le serveur compare avec le hash stocké. Les mots de passe en clair ne transitent jamais.

### Transactions atomiques
Les transactions SQLite (createSale, voidSale, addBankTransaction, bulkImport) ont des endpoints HTTP dédiés sur le serveur qui les exécutent localement de manière atomique.

### pos_config.json
Fichier JSON à côté de l'exécutable (pas dans %APPDATA%). Contient uniquement la config réseau (mode terminal, IP, port, token). Chargé **avant** `runApp` pour pouvoir configurer `PosClient` avant l'ouverture de la base.

---

## 10. Comment continuer avec un autre modèle LLM

### Fichiers à lire en priorité
1. `lib/main.dart` — routing global
2. `lib/core/database/db.dart` — opérations BDD (local + remote)
3. `lib/core/server/pos_server.dart` — serveur HTTP
4. `lib/core/server/pos_client.dart` — client HTTP
5. `lib/core/settings/local_settings.dart` — config locale
6. `lib/providers/settings_provider.dart` — state management settings

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
crypto: ^3.0.6                # SHA-256
file_selector: ^1.0.3         # Sélecteur fichiers natif
pdf: ^3.11.3                  # Génération PDF
printing: ^5.14.2             # Impression
fl_chart: ^0.71.0             # Graphiques
intl: ^0.20.2                 # Formatage dates/nombres
```

---

*Dernière mise à jour : 2026-05-29*  
*Développeur : josony1994@gmail.com*
