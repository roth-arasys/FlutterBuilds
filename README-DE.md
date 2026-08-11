# FlutterBuilds

> ⚠️ **Wartungsstatus**: *Dieses Projekt wird als unentgeltliches Community-Werkzeug "wie besehen" bereitgestellt und wird nicht aktiv weiterentwickelt. Die Issue-Funktion auf diesem Repository ist deaktiviert.*

`FlutterBuilds` ist ein kompaktes macOS-Werkzeug und Build-Pipeline, das Build-Fehler von Flutter-Projekten für iOS/macOS in cloud-synchronisierten Ordnern (wie Microsoft OneDrive über das macOS FileProvider-Framework) behebt.

---

## Das Problem

### Ursache: FileProvider-Metadaten & `codesign`-Ablehnung
Liegt ein Flutter-Projekt in einem von macOS FileProvider verwalteten Ordner (z. B. OneDrive), fügt der Sync-Client neuen Build-Dateien im `build/`-Verzeichnis automatisch erweiterte Dateiatattribute und Metadaten (wie `com.apple.FinderInfo` oder Resource Forks) hinzu.

Beim Signieren des iOS-Codes lehnt `codesign` das `Flutter.framework` sowie App-Binaries mit folgender Fehlermeldung ab:
```
resource fork, Finder information, or similar detritus not allowed
```

### Irreführende Fehlermeldung
Flutter CLI und Xcode melden diesen echten Fehler nur versteckt als unkodierten Fehlercode:
```
Uncategorized (Xcode): Exited with status code 255
```
Das liegt daran, dass der Fehler in einer Xcode-Scheme-Pre-Action passiert und nicht im `.xcresult`-Protokoll landet.

### Fehlerdiagnose
Um die tatsächliche `codesign`-Fehlermeldung anzuzeigen, führe den Build-Befehl mit erweiterter Ausgabe aus:
```bash
flutter build ios --simulator -v
```

Weitere Details siehe Issue [flutter/flutter#123583](https://github.com/flutter/flutter/issues/123583).

---

## Die Lösung: APFS-Volume-Mounts

`FlutterBuilds` mountet pro erkanntem Flutter-Projekt ein eigenes APFS-Volume auf dessen `build/`-Verzeichnis. Alle Volumes liegen in einem gemeinsamen APFS-Container innerhalb eines Sparse-Bundle-Images unter `~/Library/Application Support/FlutterBuilds/FlutterBuilds.sparsebundle` und teilen sich dynamisch den Speicherplatz.

### Warum Mounts Symlinks überlegen sind

1. **Schutz vor `flutter clean`**: Ein `flutter clean` versucht, das `build/`-Verzeichnis zu löschen. Ist `build/` ein aktiver Mount-Point, schlägt `rm -rf` wegen `EBUSY` fehl und der Mount bleibt erhalten. Ein Symlink würde durch `flutter clean` unwiderruflich gelöscht.
2. **Isolierung vom Sync-Client**: Der OneDrive-/FileProvider-Sync-Client greift nicht auf gemountete externe APFS-Volumes zu. Dadurch entstehen keine Dateisperren oder Metadaten-Detritus im Build-Output.
3. **Keine Projektänderungen nötig**: Im Flutter-Projekt selbst müssen keine Dateien oder Symlinks angelegt werden.

---

## Sicherheits- und Architekturingaranten

- **Nutzdaten außerhalb des App-Bundles**: Anwendungsdaten, Logs und das Sparse-Bundle-Image liegen ausschließlich in `~/Library/Application Support/FlutterBuilds/`. Schreibzugriffe im `.app`-Bundle würden die Signatur beschädigen und TCC-Berechtigungen (Vollzugriff auf die Festplatte) ungültig machen.
- **Pfad-abgeleitete Volume-Namen**: Volume-Namen werden aus dem Projektpfad relativ zu `~/Library/CloudStorage` generiert (Schrägstriche werden zu `_`, Suffix `-build`). Dies garantiert eindeutige Namen über verschiedene Konten hinweg ohne externe Konfigurationsdatei.
- **Purge nur im ungemounteten Zustand**: Das Bereinigen von shadowed Cloud-Resten (`purge_shadowed`) erfolgt nur bei getrennten Mounts. Ein Löschen bei aktivem Mount würde die frischen Volume-Inhalte statt der alten Cloud-Reste treffen.
- **Kompaktierung beim Systemstart**: Sparse-Bundles geben freien Speicherplatz nur frei, wenn das Image komplett getrennt ist. `FlutterBuilds` kompaktiert das Image automatisch direkt nach dem Systemstart (`boot`-Modus).
- **Schutz vor versehentlichem Löschen**: Das Löschen verwaister Volumes (`drop_obsolete`) bricht ab, wenn keine Projekte entdeckt wurden. Dies verhindert Datenverlust bei TCC-Fehlern oder OneDrive-Aussetzern.

---

## Automatische OneDrive-Erkennung & Konfiguration

Standardmäßig erkennt `FlutterBuilds` automatisch alle OneDrive-Ordner unter `~/Library/CloudStorage/` (z. B. `OneDrive-Personal`, `OneDrive-Shared` oder geschäftliche OneDrive-Konten).

Sollen spezielle Pfade manuell vorgegeben werden, können diese über die Umgebungsvariable `FLUTTERBUILDS_CLOUD_DIR` gesetzt werden. Mehrere Pfade lassen sich durch Doppelpunkt (`:`) getrennt angeben:
```bash
export FLUTTERBUILDS_CLOUD_DIR="$HOME/MeinCloudOrdner/FlutterProjekte:$HOME/ZweiterCloudOrdner/Projekte"
```

---

## Erforderliche macOS-Berechtigungen (Vollzugriff auf die Festplatte)

Da `FlutterBuilds` Cloud-Ordner durchsucht und APFS-Volumes mountet, benötigt die App Vollzugriff auf die Festplatte:

1. Öffne **Systemeinstellungen** > **Datenschutz & Sicherheit** > **Vollzugriff auf die Festplatte**.
2. Füge **`FlutterBuilds.app`** (unter `~/Applications/`) hinzu und aktiviere die Freigabe.

---

## Repository-Struktur

```
flutterbuilds/
├── README.md                # Hauptdokumentation (Englisch)
├── README-DE.md             # Dokumentation (Deutsch)
├── Makefile                 # Build, Install, Uninstall, Sign, Verify, Clean
├── src/
│   ├── mount.sh             # Mount-Skript (zsh)
│   └── main.applescript     # UI-Quelltext (AppleScript)
├── assets/
│   └── app_icon_1024.png    # Master-Icon (1024x1024 PNG)
├── scripts/
│   ├── build.sh             # Baut FlutterBuilds.app nach ./build/
│   ├── install.sh           # Installiert nach ~/Applications und registriert Anmeldeobjekt
│   └── make-icns.sh         # Erzeugt applet.icns (10 Icon-Größen)
└── .gitignore               # Schließt build/, *.icns, .DS_Store aus
```

---

## Befehle & Entwicklung

### Bauen und Prüfen

```bash
# Baut die App nach ./build/FlutterBuilds.app
make build

# Führt automatische Integritäts- und Signaturprüfungen aus
make verify
```

### Installation & Deinstallation

```bash
# Installiert nach ~/Applications/ und registriert Anmeldeobjekt (berührt bestehende Nutzdaten NICHT)
make install

# Entfernt App und Anmeldeobjekt
make uninstall
```

### Skript-Modi (`src/mount.sh`)

- **`mount.sh boot`**: Wird beim Login ausgeführt. Kompaktiert das Sparse-Bundle (falls getrennt) und mountet alle Projekt-Volumes.
- **`mount.sh mount`**: Durchsucht den Cloud-Ordner und mountet APFS-Volumes (idempotent).
- **`mount.sh unmount`**: Trennt alle aktiven Projekt-Volumes sauber.
- **`mount.sh clean`**: Trennt Volumes, löscht verwaiste Volumes, bereinigt Schattenreste, kompaktiert das Image und mountet neu.

---

## Rechtlicher Hinweis & Markenrechte (Disclaimer)

*Flutter und das Flutter-Logo sind Marken von Google LLC. FlutterBuilds ist ein unabhängiges Open-Source-Community-Projekt und steht in keiner Verbindung zu Google LLC, wird von Google LLC weder gesponsert noch unterstützt.*
