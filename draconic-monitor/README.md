# Draconic Energy Monitor v2 (ATM10 / CC:Tweaked)

Ein **einziges Lua-Programm** (`draconic.lua`) für drei Rollen: `sender`, `display` und `local`. Es ersetzt die drei älteren Programme **nicht automatisch**. Die Backups bleiben unter [`copied-programs/Draconic`](../copied-programs/Draconic).

## Installation (auf jedem beteiligten CC:Tweaked-Computer)

Auf jedem Computer:

~~~lua
wget https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/draconic-monitor/draconic.lua draconic.lua
draconic.lua scan
draconic.lua setup
draconic.lua
~~~

Beim ersten Setup Betriebsart, Energy-Pylon/Storage, optional IN-/OUT-Detector, Monitor und bei Display die **Computer-ID des Senders** wählen. Die ID steht auf dem Sender per `id` (oder `os.getComputerID()`).

Das Programm legt `draconic.cfg` neben `draconic.lua` ab. Mit `draconic.lua setup` kann die Zuordnung jederzeit geändert werden. Das Programm fragt, ob es `startup` einrichten soll: Bei **ja** wird eine bestehende `startup` **vorher unter `startup.draconic-backup-N` gesichert**. Bei nein lässt es `startup` unangetastet. Nach Änderungen am Sender oder Display das jeweilige Programm neu starten.

**Automatisches Update:** Nicht enthalten; bei einer neuen Version den `wget`-Befehl auf jedem Computer erneut ausführen. Die Konfiguration bleibt dabei bestehen.

## Anschlussplan A: Sender + separater Monitor-Computer

~~~text
Draconic Energy Core
         |
  Energy Pylon  -- [Wired Modem (aktiviert)] -- Netzwerkkabel -- CC Sender
                                                        |
                                               Wireless Modem
                                                        ~
                                               Wireless Modem
                                                        |
                                                CC Display
                                                        |
                                               Monitor (optional)
~~~

* Der Pylon muss über seinen CC:Tweaked Peripheral-Zugang mit dem **Sender-Computer** verbunden sein. Die meisten Aufbauten nutzen ein **Wired Modem direkt am Pylon** (durch Rechtsklick den Peripheral-Zugang aktivieren) und ein Netzwerkkabel zum Computer; direkte Nachbarschaft ist alternativ möglich, **sofern `draconic.lua scan` die Methoden tatsächlich sieht**.
* Ein Wireless Modem am Sender und am Display ist die einfachste Verbindung. Alternativ beide Computer über dieselbe Wired-Modem-Verkabelung zusammenschalten. `rednet` muss zwischen den PCs funktionieren, Entfernung/Dimension und Funkreichweite sind zu beachten.
* Das Senderprogramm erkennt Draconic-typische `getEnergyStored()/getMaxEnergyStored()` und generische `getEnergy()/getEnergyCapacity()` Methoden, **wenn** ein angeschlossenes Peripheral diese tatsächlich anbietet.
* Der Displaycomputer benötigt keine direkte Energieverbindung: nur Rednet und seinen Monitor. Sensoren werden immer **am Sender** angeschlossen.
* Bei verkabelten Monitoren muss der Monitor ebenfalls als Peripheral erreichbar sein (direkt oder über Wired Modems).

## Anschlussplan B: Ein Computer

Pylon und Monitor mit einem Computer verbinden; beim Setup **3) Lokal** wählen. Kein Rednet und kein zweiter Computer nötig.

## Optionale Advanced-Peripherals-Energy-Detectors

**OPTIONAL – für den eigentlichen Draconic Core NICHT nötig:** Der Energy Pylon der Draconic-Evolution-Version 1.21 liefert bereits `getInputPerTick()`, `getOutputPerTick()` und `getTransferPerTick()`. Diese nativen Werte erfasst der Monitor automatisch, sobald der Pylon als Peripheral sichtbar ist. Ein `energy_detector` (ATM10 1.21.1) bietet `getTransferRate()` für den tatsächlichen **FE/t-Durchsatz durch diesen Block**. Sie können aber nicht automatisch zwischen Core-Ein- und -Ausgang unterscheiden: Das legt die **Platzierung** fest. Ein Detector am Eingang und ein zweiter am Ausgang liefern getrennte Werte.

~~~text
GENERATOR -- FE-Kabel -- [Energy Detector IN] -- FE-Kabel -- Pylon INPUT -- Core
CORE -- Pylon OUTPUT -- FE-Kabel -- [Energy Detector OUT] -- FE-Kabel -- VERBRAUCHER
~~~

Jeden Detector ebenfalls am **Sender** als Peripheral anschließen (Wired Modem oder direkt) und im Setup **IN** oder **OUT** auswählen. Die Energie muss **wirklich durch den Detector** laufen. Alternative Wege (z. B. drahtlose Kristallverbindungen oder Bypässe) werden nicht miterfasst. Der Detector kann wie ein Widerstand/Transferlimit wirken: `getTransferRateLimit()` gibt das konfigurierte Limit an. **Das Monitorprogramm verändert dieses Limit absichtlich nicht**, da das die Versorgung drosseln könnte. Bei Messung = 0 trotz Energiefluss: Kabelrichtung und Detector-Sitz prüfen. Ein Energy Detector *misst Durchsatz*, er liest **nicht** alleine den Speicherstand eines Tier-8-Core.

**Ohne Detectoren:** Bei einem korrekt angeschlossenen Draconic Energy Pylon zeigt das Dashboard den tatsächlichen **Core-IN / Core-OUT und Core-NET** per nativen Pylon-Methoden. Falls ein anderer Storage diese Methoden nicht unterstützt, bleiben IN/OUT ohne Detector unbekannt und NET wird ersatzweise aus zwei Speichermessungen geschätzt (bei enormen Tier-8-Werten kann das ungenau werden). Es werden keine erfundenen IN/OUT-Werte angezeigt.

## Premium-Dashboard für einen 8x5-Monitor

Das neue Sci-Fi-Dashboard ist besonders für deinen **8 Blöcke breiten und 5 Blöcke hohen Monitor** ausgelegt. Es setzt die Monitor-Textskalierung bei der ersten Verbindung auf **0.5** und verwendet eine breite Zwei-Spalten-Ansicht mit vollständigem Verlauf.

- Großer digitaler **Stored OP**-Wert, Kapazität, präziser Ladeprozentsatz, Füllstandsbalken
- Separate **INPUT** (grün), **OUTPUT** (rot) und **NET** (grün/rot) in **OP/t**
- Direktwerte vom Draconic Pylon, optional andere Energie-Detectoren als Fallback
- Echte **gespeicherte OP** im Live-Graphen statt gerundeter Prozentwerte; automatische Min/Max-Skala
- Orange/rote Warnung bei wenig Energie; bei extrem kleinen Prozenten wird kein künstlich großer Füllbalken gezeichnet
- Aufgeräumter Status, Sender-ID, Datenquelle, ONLINE/OFFLINE und flackerärmere Fensterdarstellung
- Kompaktes Layout auf kleinen Terminals; beim Entfernen des Monitors Fallback auf das Computer-Terminal
- Bestehendes Rednet-Protokoll **v2 bleibt erhalten**: Du musst den Sender nicht aktualisieren, um das neue Display zu verwenden.

### Nur das Display aktualisieren (bereits installiertes System)

Am **Display-Computer** erst das laufende Programm mit `Ctrl+T` beenden. Danach diese Befehle **einzeln** eingeben:

~~~text
copy draconic.lua draconic-backup.lua
delete draconic.lua
wget https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/draconic-monitor/draconic.lua draconic.lua
draconic.lua
~~~

Die bestehende `draconic.cfg` bleibt erhalten, daher ist normalerweise **kein erneutes Setup** notwendig. Ein Computer mit Autostart lädt beim nächsten Neustart diese neue Version. Nur wenn die Datei unter einem anderen Namen/Pfad installiert wurde, diesen Pfad entsprechend anpassen.

Der Monitor muss aus mindestens 72 Textspalten und 32 Zeilen bestehen, damit die volle Premium-Ansicht erscheint. Kleinere Displays erhalten automatisch ein kompaktes Layout.


## Fehlersuche

`draconic.lua scan` zeigt sämtliche erreichbaren Peripheral-Typen und verfügbaren Methoden. Wenn `Storage: 0 | Detector: 0` erscheint, aber Monitore und Modems gefunden werden, ist das **kein Beweis, dass der Block fehlerhaft ist**: Wired Modem direkt an die **feste Pylon-Basis** (nicht an die Glaskugel), Networking Cable bis zum Computer, und **Rechtsklick auf das am Pylon befestigte Modem** (peripheres Gerät aktivieren). Das gleiche gilt separat für einen Detector. Ein Energy Detector, der einfach nur neben dem Pylon steht, ist nicht automatisch für den Computer sichtbar. Kontrolliere mit dem CC-Shell-Befehl `peripherals` und erneut mit `draconic.lua scan`. Erst wenn der Pylon als `draconic_rf_storage` oder mit seinen `getEnergyStored`-Methoden sichtbar ist, kann der Monitor lesen.

 Wenn der Pylon **nicht** gelistet wird: Wired Modem prüfen, mit Netzwerk verbinden, richtigen Block anklicken und Draconic-Core-Verbindung prüfen. Wenn `getEnergyStored` oder `getEnergy` fehlen, kann dieses Gerät den Speicherstand nicht liefern; den richtigen Pylon oder eine zugängliche Energy-Storage-Schnittstelle verwenden.

Wenn Display OFFLINE zeigt: Beide Computer angeschaltet? Funkmodems verbunden und in Reichweite? Gleiche Programversion? Im Display-Setup die richtige **Sender-ID** eingegeben? Diese ID filtert versehentliche Fremd-Sender, ist aber **keine kryptographische Authentifizierung** (Rednet lässt Sender-Spoofing zu). Wenn Display ohne gebundene ID betrieben wird, nimmt es gültige Daten jedes erreichbaren Senders desselben Protokolls an.

Die alten Dateien bleiben in `copied-programs/Draconic` unverändert. **Core und Detectors werden nie per Steuerbefehl verändert.**

## Technische Referenz

- CC:Tweaked `energy_storage`: https://tweaked.cc/generic_peripheral/energy_storage.html
- CC:Tweaked `rednet`: https://tweaked.cc/module/rednet.html
- Advanced Peripherals v0.8 `energy_detector`: https://docs.advanced-peripherals.de/0.8/peripherals/base_detector/

## Selbsttest / CI

Im Computer mit `draconic.lua selftest` laufen lokale Prüfungen für Paketvalidierung, Größenformatierung und Wertebegrenzung. Im GitHub-Repository prüft der Workflow `.github/workflows/draconic-lua.yml` zusätzlich Lua-Syntax und den Peripheral-Scan mit simulierten Geräten. Das ersetzt keinen realen In-Game-Test der Mod-Peripherals.

- Draconic-Evolution-Quellcode für Energy-Pylon-Peripheral: https://github.com/Draconic-Inc/Draconic-Evolution/blob/1.21/src/main/java/com/brandon3055/draconicevolution/integration/computers/PeripheralEnergyPylon.java
