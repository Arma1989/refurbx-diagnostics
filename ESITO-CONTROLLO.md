# RefurbX 1.0.82 (92) — stato della verifica

## Controlli statici eseguiti

- Versioni, plist, motivi privacy CA92.1 e 85F4.1, entitlement NFC TAG e asset.
- Rimozione del test di memoria/RAM e dei relativi valori da schede, export e risultati diagnostici.
- Prova luce impostata sul flusso iOS documentato da M360: lettura pubblica della luminosità dello schermo, riferimento al 35%, osservazione manuale dell'adattamento automatico. Nessun accesso fotocamera o lettura diretta del sensore per questo test.
- Spazio informativo basato su capacità del volume Foundation, senza salvataggio, grading o export.
- NFC si avvia direttamente dal pulsante Continua; le spiegazioni dei permessi non offrono Salta prima della richiesta di sistema.
- Bussola separata dal permesso GPS: avvio diretto del servizio heading magnetico, nessun filtro angolare, calibrazione di sistema e retry se non arrivano dati. La verifica fisica resta da eseguire su iPhone.
- Sintassi Python e risorse immagini.

Preflight `validate_release.py` superato sulla versione 1.0.82 (92). Gli 8 test offline di `test_signing.py` sono superati. Questi controlli verificano file e regole statiche, non compilano Swift.

## Confronto funzionale con i test iOS documentati da M360

| Area | RefurbX | Stato rispetto al flusso M360 iOS |
|---|---|---|
| Schermo e touch | Display a colori, touch e multi-touch | Copertura funzionale analoga; la verifica del display resta visiva |
| Sensori | Luminosità automatica, prossimità, accelerometro, giroscopio, bussola, GPS | Flussi specifici iOS. La luce osserva l'adattamento del display e non legge il sensore direttamente |
| Fotocamere | Frontale, posteriore, autofocus e flash | Prove visive guidate |
| Audio | Speaker, capsula, microfoni, cuffie e vibrazione | Test guidati; ascolto e conferma restano manuali quando iOS non offre una misura affidabile |
| Connettività | Wi-Fi, Bluetooth, NFC; rete cellulare aggiuntiva | Verifica dello stato disponibile tramite API pubbliche; NFC richiede un tag compatibile |
| Tasti e ricarica | Volume, accensione, silenzioso, cavo e wireless | Osservazione/azione dell'operatore dove iOS non espone il segnale hardware completo |
| Face ID/Touch ID e sensori avanzati | Biometria, TrueDepth, LiDAR, penna e pressione dove supportati | Prove RefurbX aggiuntive, filtrate per modello |
| Batteria e memoria | Nessun test di salute batteria, RAM o integrità archiviazione | Differenza intenzionale: M360 documenta che su iOS 17+ la sua prova batteria richiede il software desktop collegato. RefurbX non ha quel collegamento per acquisire misure iniziali/finali; non inventa un risultato. Lo spazio resta solo informativo dopo il rifiuto Apple del test memoria. |

Quindi il catalogo non è una copia uno-a-uno dell'app M360. Riprende le aree di verifica compatibili con RefurbX e distingue le letture automatiche dalle conferme manuali. La documentazione M360 descrive metodi diversi per iOS e Android; il valore numerico reale del sensore luce è documentato per Android, mentre su iOS si osserva il cambio automatico dello schermo.

## Limiti di verifica

Questo ambiente Windows non esegue Xcode, firma Apple o test fisici su iPhone. Prima dell'invio servono compilazione Codemagic, installazione della build 92 e verifica su dispositivo di: Luminosità automatica attiva e disattiva, risposta dello schermo coprendo/illuminando il sensore, ripristino della luminosità originale dopo Passa/Fallito/Salta, valore spazio confrontato con Impostazioni, bussola, permessi, NFC, layout e report.

La guida M360 descrive per Android una barra con il valore del sensore; per iOS descrive invece l'osservazione della luminosità automatica dello schermo. RefurbX usa la seconda modalità e presenta la percentuale come luminosità dello schermo, non come misura del sensore. Questo segue una procedura documentata, ma non garantisce l'approvazione Apple.

Riferimento M360: https://m360soft.com/pl/help/application-help/in-depth-diagnostics/mobile-tests/sensor-tests/light-sensor
Riferimento Apple per UIScreen.brightness: https://developer.apple.com/documentation/uikit/uiscreen/brightness
