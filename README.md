# Transmote

Client macOS natif pour [Transmission](https://transmissionbt.com) via l'API JSON-RPC.

---

## Prérequis

- macOS 14 Sonoma ou plus récent
- Xcode 15+
- Transmission installé sur votre serveur (local ou distant) avec l'API RPC activée

---

## Installation

### 1. Cloner et ouvrir dans Xcode

```bash
git clone https://github.com/vous/transmote
cd transmote
```

Créez un nouveau projet Xcode :
1. **File → New → Project → macOS → App**
2. Nom : `Transmote`, Interface : SwiftUI, Language : Swift
3. Supprimez `ContentView.swift` généré
4. Ajoutez tous les fichiers du projet dans les groupes correspondants

### 2. Configurer le projet Xcode

Dans les **Build Settings** :
- `MACOSX_DEPLOYMENT_TARGET` = `14.0`
- `SWIFT_STRICT_CONCURRENCY` = `complete`

Dans **Signing & Capabilities** :
- Ajoutez `com.apple.security.network.client` (Outgoing connections)
- Si vous voulez les notifications : `com.apple.security.network.server`

### 3. Info.plist

Ajoutez les clés suivantes :
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```
(Pour permettre HTTP non-sécurisé vers votre serveur local)

---

## Configuration de Transmission

Dans les préférences de Transmission (ou `settings.json`) :

```json
{
  "rpc-enabled": true,
  "rpc-port": 9091,
  "rpc-whitelist-enabled": false,
  "rpc-authentication-required": false
}
```

Pour activer l'authentification :
```json
{
  "rpc-authentication-required": true,
  "rpc-username": "admin",
  "rpc-password": "motdepasse"
}
```

---

## Architecture du projet

```
Transmote/
├── App/
│   ├── TransmoteApp.swift          # @main, scènes SwiftUI
│   └── AppDelegate.swift           # Status bar, notifications
│
├── Networking/
│   ├── RPCClient.swift             # Client JSON-RPC (actor)
│   └── RPCMethods.swift            # Toutes les méthodes Transmission
│
├── Models/
│   ├── Torrent.swift               # Modèle principal + enums
│   └── Server.swift                # ServerConfig, SessionArguments, Stats
│
├── Store/
│   └── TorrentStore.swift          # @Observable — état central
│
├── Views/
│   ├── ContentView.swift           # NavigationSplitView + toolbar
│   ├── Sidebar/
│   │   └── SidebarView.swift       # Filtres + gestion serveurs
│   ├── TorrentList/
│   │   └── TorrentListView.swift   # Table + context menu
│   ├── TorrentDetail/
│   │   └── TorrentDetailView.swift # Infos, fichiers, pairs, trackers
│   ├── Sheets/
│   │   ├── AddTorrentViews.swift   # Ajout magnet / fichier
│   │   └── ServerEditView.swift    # Édition serveur
│   └── Settings/
│       └── SettingsView.swift      # Préférences Transmission
│
└── Helpers/
    └── Formatters.swift            # ByteFormatter, ETAFormatter, etc.
```

---

## Fonctionnalités

| Fonctionnalité | Implémenté |
|---|---|
| Liste des torrents avec tri/filtre | ✅ |
| Démarrer / Mettre en pause / Supprimer | ✅ |
| Ajouter fichier .torrent (drag & drop, picker) | ✅ |
| Ajouter lien magnet | ✅ |
| Détail : infos, fichiers, pairs, trackers | ✅ |
| Priorité par fichier | ✅ |
| Gestion multi-serveurs | ✅ |
| Barre de menu avec vitesses | ✅ |
| Notifications à la fin d'un téléchargement | ✅ |
| Mode tortue (alt speed) | ✅ |
| Préférences bande passante / pairs / file | ✅ |
| Polling configurable | ✅ |

---

## API Transmission utilisée

| Méthode | Usage |
|---|---|
| `torrent-get` | Récupérer la liste et les détails |
| `torrent-start` / `torrent-stop` | Démarrer / Arrêter |
| `torrent-remove` | Supprimer |
| `torrent-add` | Ajouter magnet ou fichier |
| `torrent-set` | Priorité, limites de vitesse |
| `torrent-verify` | Vérification des données |
| `torrent-reannounce` | Réannoncer |
| `session-get` / `session-set` | Préférences du serveur |
| `session-stats` | Statistiques globales |
| `free-space` | Espace disque disponible |

---

## Dépendances

**Aucune dépendance externe.** Le projet utilise uniquement :
- SwiftUI
- AppKit
- URLSession (réseau)
- UserNotifications (notifications système)
- UniformTypeIdentifiers (gestion des types de fichiers)

---

## Contribuer

Les contributions sont les bienvenues ! En particulier :
- Localisation (français, anglais, etc.)
- Thème sombre / clair automatique
- Widget macOS pour les vitesses
- Support des séquences d'annonce des trackers
- Intégration Spotlight

---

## Licence

MIT — voir LICENSE
