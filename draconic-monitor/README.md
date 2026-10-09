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

**Ja, sie helfen:** `energy_detector` (ATM10 1.21.1) bietet `getTransferRate()` für den tatsächlichen **FE/t-Durchsatz durch diesen Block**. Sie können aber nicht automatisch zwischen Core-Ein- und -Ausgang unterscheiden: Das legt die **Platzierung** fest. Ein Detector am Eingang und ein zweiter am Ausgang liefern getrennte Werte.

~~~text
GENERATOR -- FE-Kabel -- [Energy Detector IN] -- FE-Kabel -- Pylon INPUT -- Core
CORE -- Pylon OUTPUT -- FE-Kabel -- [Energy Detector OUT] -- FE-Kabel -- VERBRAUCHER
~~~

Jeden Detector ebenfalls am **Sender** als Peripheral anschließen (Wired Modem oder direkt) und im Setup **IN** oder **OUT** auswählen. Die Energie muss **wirklich durch den Detector** laufen. Alternative Wege (z. B. drahtlose Kristallverbindungen oder Bypässe) werden nicht miterfasst. Der Detector kann wie ein Widerstand/Transferlimit wirken: `getTransferRateLimit()` gibt das konfigurierte Limit an. **Das Monitorprogramm verändert dieses Limit absichtlich nicht**, da das die Versorgung drosseln könnte. Bei Messung = 0 trotz Energiefluss: Kabelrichtung und Detector-Sitz prüfen. Ein Energy Detector *misst Durchsatz*, er liest **nicht** alleine den Speicherstand eines Tier-8-Core.

**Ohne Detectoren** zeigt das Dashboard IN/OUT als nicht verfügbar, aber NET als aus zwei Core-Abfragen geschätzte Speicheränderung pro Tick (nicht als gemessenen Gesamtdurchsatz). Bei enormen Tier-8-Werten können kleinere Änderungen wegen numerischer Genauigkeit untergehen. Keine falsche Aufteilung in IN/OUT wird erfunden.

## Anzeige

- Absoluter Speicherstand + Kapazität, Prozentbalken
- Eingang und Ausgang **nur soweit mit Detector gemessen**
- NET aus tatsächlicher gespeicherter Differenz zwischen Messzeitpunkten (FE/t)
- Füllstandsverlauf mit **sichtbarer, variabler Y-Skala**
- Status ONLINE/OFFLINE nach 5 Sekunden ohne gültige Daten
- Monitor passt sich an die Größe an; bei genügend Platz Grafik (empfohlen 3x3 oder größer, Textscale 0.5)
- Bei Monitorverlust Fallback auf das Computer-Terminal

## Fehlersuche

`draconic.lua scan` zeigt sämtliche erreichbaren Peripheral-Typen und verfügbaren Methoden. Wenn der Pylon **nicht** gelistet wird: Wired Modem prüfen, mit Netzwerk verbinden, richtigen Block anklicken und Draconic-Core-Verbindung prüfen. Wenn `getEnergyStored` oder `getEnergy` fehlen, kann dieses Gerät den Speicherstand nicht liefern; den richtigen Pylon oder eine zugängliche Energy-Storage-Schnittstelle verwenden.

Wenn Display OFFLINE zeigt: Beide Computer angeschaltet? Funkmodems verbunden und in Reichweite? Gleiche Programversion? Im Display-Setup die richtige **Sender-ID** eingegeben? Diese ID filtert versehentliche Fremd-Sender, ist aber **keine kryptographische Authentifizierung** (Rednet lässt Sender-Spoofing zu). Wenn Display ohne gebundene ID betrieben wird, nimmt es gültige Daten jedes erreichbaren Senders desselben Protokolls an.

Die alten Dateien bleiben in `copied-programs/Draconic` unverändert. **Core und Detectors werden nie per Steuerbefehl verändert.**

## Technische Referenz

- CC:Tweaked `energy_storage`: https://tweaked.cc/generic_peripheral/energy_storage.html
- CC:Tweaked `rednet`: https://tweaked.cc/module/rednet.html
- Advanced Peripherals v0.8 `energy_detector`: https://docs.advanced-peripherals.de/0.8/peripherals/base_detector/

## Selbsttest / CI

Im Computer mit `draconic.lua selftest` laufen lokale Prüfungen für Paketvalidierung, Größenformatierung und Wertebegrenzung. Im GitHub-Repository prüft der Workflow `.github/workflows/draconic-lua.yml` zusätzlich Lua-Syntax und den Peripheral-Scan mit simulierten Geräten. Das ersetzt keinen realen In-Game-Test der Mod-Peripherals.
