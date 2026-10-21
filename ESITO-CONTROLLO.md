# Esito del secondo controllo — RefurbX 1.0.82 (85)

## Controlli passati in questo ambiente Windows

- Preflight del progetto: versioni coerenti, plist leggibili, motivi privacy CA92.1 e 85F4.1, entitlement NFC TAG, riferimenti del vecchio test memoria assenti, luce manuale, risorse immagini presenti, sintassi dei file Python.
- 8 test offline della preparazione firma: tutti passati. Non sono test della firma Apple reale.
- 83 nomi usati come model.nome nell'interfaccia trovano una dichiarazione nel sorgente del modello. È un controllo dei riferimenti, non un type-check Swift.
- Icona App Store: 1024×1024, RGB senza canale alfa.
- Sorgenti Swift leggibili come UTF-8, senza byte NUL.
- Valori di archiviazione confinati in StorageInfo.swift, assenti dai modelli e dai generatori delle schede.
- Pacchetto ZIP confrontato byte per byte con i sorgenti consegnati.

## Correzioni aggiuntive rispetto alla prima consegna

Schermata spazio totale/disponibile/occupato separata dai test; consenso prima dell'outbox; messaggio che distingue file pronto da trasferimento confermato; note complete nei report; rimozione di dati dispositivo non misurati; cancellazione registrazioni temporanee; ripresa sessioni precedenti; guardie per callback obsolete; richiesta biometrica senza pulsanti preliminari Salta; carica cavo/pad confermata dall'operatore; arresto della firma se manca l'App ID invece di un fallback account fisso.

## Controlli ancora necessari

| Controllo | Stato |
|---|---|
| Generazione progetto Xcode e compilazione Swift | Da eseguire su Codemagic |
| Archivio App Store, certificati e firma NFC effettiva | Da eseguire con l'account Apple |
| Installazione e permessi su iPhone/iPad | Da eseguire su dispositivo |
| Tutte le 35 prove definite nel catalogo | Non eseguite fisicamente |
| Layout reale e PDF generato da UIKit | Da controllare su dispositivo |
| Invio al software del banco, via rete e cavo | Da provare con il banco reale |
| Screenshot, descrizione e App Privacy pubblicati | Da controllare in App Store Connect |
| Privacy policy del sito, inclusa gestione TrueDepth | Da verificare sul sito pubblicato |
| Approvazione Apple | Decisione di App Review |

Usa prima il workflow **RefurbX - verifica compilazione senza firma**, poi **RefurbX iOS**. Non è corretto definire l'app perfetta o pronta alla revisione finché questi passaggi non sono completati. In caso di errore, il log Codemagic serve per la correzione successiva.
