# Signature Android & secrets GitHub

Ce document explique comment générer le keystore de release et quels secrets
configurer sur GitHub pour que le workflow `.github/workflows/build-apk.yml`
produise un APK release signé.

> ⚠️ **Sécurité** : le keystore de release et ses mots de passe sont des secrets.
> Ne les commite jamais, ne les colle jamais dans un chat, un ticket ou les logs.
> Le fichier `.keystore` doit rester sur ta machine (et dans une sauvegarde sûre).

## 1. Générer le keystore de release (une seule fois, sur ta machine)

Nécessite un JDK (l'outil `keytool`) :

```bash
keytool -genkeypair \
  -keystore zimut-release.keystore \
  -alias zimut \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "<MOT_DE_PASSE_FORT>" \
  -keypass "<MOT_DE_PASSE_FORT>" \
  -dname "CN=ZimutAdventure, OU=CharlieG42, O=CharlieG42, L=, ST=, C=FR"
```

- `-alias zimut` : l'alias demandé pour ce projet (utilisé dans le preset d'export).
- `-validity 10000` : ~27 ans, recommandé par Google pour les apps longue durée.
- Le mot de passe du keystore et de la clé doivent être **identiques** (limitation
  actuelle de l'export Godot).
- **Sauvegarde** le fichier `zimut-release.keystore` et note le mot de passe dans
  un gestionnaire de mots de passe. Sans eux, impossible de publier des mises à
  jour de l'app sous la même identité.

Vérification :

```bash
keytool -list -v -keystore zimut-release.keystore -storepass "<MOT_DE_PASSE>"
```

Tu dois voir une entrée `zimut, PrivateKeyEntry`.

## 2. Export local (éditeur Godot)

Dans l'éditeur : **Projet → Exporter → Android → Options du preset** :

| Champ | Valeur |
|---|---|
| Keystore / Release | chemin absolu vers `zimut-release.keystore` |
| Keystore / Release User | `zimut` |
| Keystore / Release Password | ton mot de passe |

Puis **Exporter le projet** en décochant « Exporter avec debug ».

> Les identifiants sont écrits en clair dans `export_presets.cfg` quand tu fais ça
> depuis l'éditeur. Le dépôt ignore ce fichier (`.gitignore`) et le preset commité
> laisse le mot de passe vide : en CI, il est injecté par variable d'environnement.

## 3. Secrets GitHub à créer

Va dans **Settings → Secrets and variables → Actions → New repository secret**
(sur le dépôt `CharlieG42/ZimutAdventure`) et crée **3 secrets** :

| Secret | Valeur | Comment l'obtenir |
|---|---|---|
| `RELEASE_KEYSTORE_BASE64` | contenu du keystore encodé en base64 | `base64 -w0 zimut-release.keystore` (Linux/macOS) ou `certutil -encodehex zimut-release.keystore tmp.txt 1 && ...` (Windows, voir ci-dessous) |
| `RELEASE_KEYSTORE_PASSWORD` | mot de passe du keystore / de la clé | celui choisi à l'étape 1 |
| *(optionnel)* `RELEASE_KEY_ALIAS` | `zimut` | fixe, peut aussi être mis en variable du workflow si tu préfères |

### Encoder le keystore en base64

**Linux / macOS :**
```bash
base64 -w0 zimut-release.keystore
# ou pour le copier directement dans le presse-papiers (macOS) :
base64 -w0 zimut-release.keystore | pbcopy
```

**Windows (PowerShell) :**
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("zimut-release.keystore"))
```

Colle le résultat **tel quel** (une seule longue ligne) comme valeur du secret
`RELEASE_KEYSTORE_BASE64`.

## 4. Ce que fait le workflow

`.github/workflows/build-apk.yml` :

1. **Job `test`** : importe le projet et lance les tests headless
   (`tests/run_all.sh`).
2. **Job `build-apk`** (matrice `debug` / `release`) :
   - installe JDK 17 (Temurin) ;
   - installe l'Android SDK (build-tools 36.1.0, platform android-36, CMake 3.10.2.4988404,
     NDK 29.0.14206865 — versions requises par le template Gradle de Godot 4.7) ;
   - installe Godot 4.7 + les templates d'export ;
   - configure les chemins Java SDK / Android SDK pour Godot ;
   - **release uniquement** : si les secrets de signature sont présents, décode
     `RELEASE_KEYSTORE_BASE64` vers `/home/runner/work/release.keystore` et signe
     l'APK ; sinon (ex: sur une PR), le preset de signature est retiré et l'APK
     release est construit **non signé** (la vérification de signature est alors
     sautée) ;
   - exporte l'APK (`--export-debug` ou `--export-release`) ;
   - vérifie la signature avec `apksigner verify --print-certs` (sauf build release
     non signé) ;
   - publie l'APK en **artifact** téléchargeable (`ZimutAdventure-android-debug`
     / `ZimutAdventure-android-release`) ;
   - **sur un tag `v*`** : attache l'APK release à la release GitHub.

Les identifiants de signature sont passés via les variables d'environnement
officielles de Godot (`GODOT_ANDROID_KEYSTORE_RELEASE_*`), qui priment sur le
preset — le mot de passe n'apparaît donc ni dans `export_presets.cfg` ni dans
les logs.

## 5. Déclenchement

- À chaque **push sur `main`** et chaque **tag `v*`** (ex: `git tag v0.1.0 && git push origin v0.1.0`).
- Sur **pull request** : les jobs debug et release passent tous les deux. L'APK
  release est **non signé** sur une PR (les secrets ne sont exposés qu'aux
  branches protégées / à `main`), ce qui permet de valider le build. La signature
  n'a lieu que sur `main` et les tags `v*`, où les secrets sont disponibles.
- Manuellement via **Actions → Build APK → Run workflow**.

## 6. Tester l'APK

```bash
adb install build/android/ZimutAdventure-debug.apk      # debug (sideload)
adb install build/android/ZimutAdventure-release.apk    # release signé
```

Note : si une ancienne version signée avec une autre clé est installée, désinstalle-la
d'abord (`adb uninstall com.charlieg42.zimutadventure`).

## 7. Si le keystore est perdu

Impossible de publier une mise à jour signée avec la même identité : il faudrait
changer le `package/unique_name` (nouvelle app sur le Play Store) et recréer un
keystore. D'où l'importance de la sauvegarde.
