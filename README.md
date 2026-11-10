# Casa – Smart Home für Tekkit Lite (Minecraft 1.4.7)

Licht, Türen und Maschinen per Touch-Monitor schalten, mit Szenen und Regeln.
Läuft auf ComputerCraft 1.5, wie es in Tekkit Lite steckt (nicht Tekkit Classic).

Inspiriert von [tekkit-lite-smart-home](https://github.com/DJDarkMatter/tekkit-lite-smart-home)
und [Tekkit-Lite-Smart-Home-V2](https://github.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2), aber neu geschrieben.

## Was anders ist

| | Vorlage (V2) | Casa |
| --- | --- | --- |
| Installation | Installer mit 358 KB, 25 Dateien, Apps einzeln nachladen | **eine Datei** (`casa`, 67 KB) für alle Computer |
| Mindestaufbau | 3 Computer (OS, IO, Monitor) | **1 Computer** mit Monitor und Kabel reicht |
| Einrichten | Konsolenbefehle wie `map test io_11 left white` | Menüs; Sensoren werden **gelernt** (Hebel einmal umlegen) |
| Automatik | eigene App „Logic Sandbox“ | Regeln: *Wenn … dann …*, auch nach Uhrzeit, Abend, Morgen |
| Monitore | Zentrale zeichnet alles und funkt Bilder | Panel zeichnet selbst, nur geänderte Zeilen, kein Flackern |
| Funk | ohne Schutz | Pakete sind mit Passwort signiert, alte Pakete werden verworfen |
| Funkdaten lesen | `textutils.unserialize` (führt Code aus) | eigener Parser, führt nie fremden Code aus |
| Ausfall der Zentrale | Ausgänge gehen nach 15 s aus | Stationen halten den Zustand und stellen ihn nach einem Neustart selbst wieder her |

Was Casa **nicht** hat: Fenster-Desktop, Bildschirmschoner, ME-/Reaktor-Anzeigen über OpenCCSensors.
Casa steuert und liest Redstone – mehr nicht.

## Was du brauchst

- Computer (normal oder Advanced)
- Funkmodem an jedem Computer, sobald es mehr als einer ist
- Advanced Monitor für Touch
- RedPower-Bündelkabel (16 Leitungen pro Seite) oder normales Redstone (1 Leitung pro Seite)

## Die Datei in den Computer bringen

**Einzelspieler (am einfachsten):**
1. Im Spiel am Computer `id` eintippen und die Nummer merken.
2. Einmal `edit x` öffnen, mit Strg speichern und beenden – dadurch entsteht der Ordner des Computers.
3. `casa.lua` in den Ordner `saves/<Welt>/computer/<Nummer>/` kopieren und in `casa` umbenennen.

**Server oder mit Internet im Spiel:** Den Inhalt von `casa.lua` bei pastebin.com hochladen, dann am Computer
`pastebin get <CODE> casa`. Dafür muss in der ComputerCraft-Konfiguration `enableAPI_http=true` stehen.

## Aufbau in 5 Minuten

1. **Zentrale:** `casa` starten → „Zentrale“ wählen → überall Enter. Fertig.
   Steht ein Advanced Monitor direkt am Computer, ist er sofort ein Touch-Panel.
2. **Schalter anlegen:** Menü *Schalter → Neuer Schalter*. Name, Raum, Computer, Seite, Kabelfarbe.
   Mit *Jetzt umschalten (Test)* siehst du gleich, ob die richtige Lampe angeht.
3. **Sensor anlegen:** *Sensoren → Neuer Sensor → Lernen* und dann den Hebel, Knopf oder die Druckplatte einmal schalten.
4. **Regel anlegen:** *Regeln → Neue Regel*, z. B. „Druckplatte geht AN → Tür 5 Sekunden AN“ oder „Es wird Abend → Szene Nachtlicht“.

Weitere Computer:

- **Station** – steht woanders und hat dort Kabel. `casa` starten, „Station“ wählen, Namen geben (z. B. `keller`).
  Sie taucht danach an der Zentrale bei *Welcher Computer?* auf.
- **Panel** – Computer mit Monitor zum Schalten. Auf Wunsch zeigt es nur einen Raum.
- **Relay** – jede Station und jedes Panel kann Funk weiterreichen, wenn die Zentrale zu weit weg ist (bis zu 3 Sprünge).

Kanal und Passwort müssen auf allen Computern gleich sein (Standard: `4711` und `casa` – das Passwort bitte ändern).
Neu einrichten: `casa setup`.

## Die Panels

- Grün = an, grau = aus, gelb = wird gerade geschaltet, rot = Station nicht erreichbar.
- Orange/hellgrau sind Sensoren (nur Anzeige).
- Reiter oben = Räume, dazu *Szenen* mit „Alles aus“.
- Die Uhr ist gelb am Tag und grau in der Nacht.
- Funktioniert vom 1×1-Monitor bis zur großen Wand; die Textgröße wird automatisch gewählt.

## Gut zu wissen

- `vorne` ist die Seite mit dem Bildschirm des Computers.
- Computer laufen nur in geladenen Chunks. Für entfernte Stationen einen Chunkloader benutzen.
- Funkreichweite sind etwa 64 Blöcke, bei Gewitter weniger.
- Eine Leitung ist entweder Schalter oder Sensor, nicht beides.
- Die Signatur hält Mitspieler ab, die einfach mitfunken wollen. Echte Verschlüsselung ist das nicht.

## Getestet

`lua tests/sim.lua` simuliert fünf Computer (Zentrale, zwei Stationen, zwei Panels) samt Funk, Redstone und Monitoren
und prüft 38 Abläufe: Einrichtung, Touch, Lernen, Regeln, Zeitregeln, Relay, Neustarts, gefälschte Funkpakete.

**Im echten Spiel wurde Casa noch nicht ausprobiert.** Der Code hält sich an Lua 5.1 und die Schnittstellen von
ComputerCraft 1.5; falls trotzdem etwas hakt, steht die Fehlermeldung in `casa_data/fehler.txt`.
