# CC:Tweaked: gesamten Computer nach GitHub kopieren

`copy_computer_to_github.lua` ist ein **manueller** Uploader für Dateien auf der *lokalen Festplatte des ausführenden Computers*. Er umgeht keine Server-Claims und kann keine anderen Computer fernsteuern. Der Besitzer muss ihn **auf seinem Computer selbst** ausführen bzw. bewusst ausführen lassen.

## Start auf dem Computer, der gesichert werden soll

```lua
wget run https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/tools/copy_computer_to_github.lua
```

1. Das Programm listet **alle Dateien und Unterordner der HDD**, einschließlich `startup` und eigener Konfigurationen, auf. `/rom` und externe Disketten/Peripherals sind ausgeschlossen. Leere Verzeichnisse werden mit `.gitkeep` repräsentiert.
2. Backup-Namen eingeben (Vorgabe `computer-<ID>`), Dateiliste prüfen und **JA** eintippen. **Achtung: das Ziel-Repository ist öffentlich!** Keine privaten Zugangsdaten, Tokens oder Geheimnisse hochladen.
3. Ein **kurzlebiges fine-grained personal access token** von GitHub eingeben: Resource owner `Chazammm`, Repository access **Only select repositories** → `atm10-cc-doom`, Repository permissions → **Contents: Read and write**. Das Token wird im Programm nur zur Laufzeit im Arbeitsspeicher gehalten und nicht gespeichert. Es sollte niemandem weitergegeben und nach Gebrauch widerrufen werden. Niemals in einem fremden, nicht vertrauenswürdigen Computer eingeben.
4. Der Upload landet unter `copied-programs/<Backup-Name>/` in der `main`-Branch. Ein erneuter Lauf mit demselben Backup-Namen ersetzt gleichnamige Dateien, löscht aber nichts. Pro Datei erzeugt GitHub einen Commit.

**Grenzen:** Dateien über **768 KiB** werden mit Hinweis übersprungen; fehlgeschlagene Dateien erscheinen in der Ausgabe. Bei API-Fehlern erneut ausführen. Zum Hochladen sind aktivierte CC:Tweaked-HTTP-Anfragen einschließlich `api.github.com` nötig.

**Ohne GitHub-Token auf dem fremden Computer:** Besitzer kann seine Dateien alternativ per Diskettenlaufwerk/anderem von ihm freigegebenem Weg weitergeben; der Uploader benötigt für den direkten GitHub-Schreibzugriff ein Token. Dies ist **keine** Methode, Claims oder Serverrechte zu umgehen.

Dokumentation: [CC:Tweaked HTTP](https://tweaked.cc/module/http.html), [GitHub Contents API](https://docs.github.com/en/rest/repos/contents).
