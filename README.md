# RefurbX Diagnostica per iPhone e iPad

App nativa dei test, versione 1.0.77 (build 78). Sul dispositivo il nome è **RefurbX Diagnostica**. Gira su iPhone e iPad. Team ID `L9F47LJC86`, bundle `eu.refurbx.diagnostics`.

Le prove che questo modello non ha restano in fondo, scure, e non partono. Su un altro dispositivo si accendono da sole: la penna sugli iPad che la ricevono, il 3D Touch sugli iPhone che lo hanno ancora.

A fine diagnosi, nella scheda, scrivi solo il codice di sei lettere del banco, per esempio `Q2DRA7`, e premi **Invia al banco**. L'iPhone sente il computer sulla stessa Wi-Fi. Col cavo il programma Windows scrive `Documents/bench.url` e legge `Documents/outbox.json`: la scheda arriva anche senza Wi-Fi. Il banco può arrivare anche come argomento di avvio. Codemagic carica l'app su TestFlight senza inviarla ogni volta alla revisione beta: quel limite di Apple si era già esaurito. I tester interni la installano subito. La revisione per i tester esterni si fa a mano, una volta, da App Store Connect. L'IPA di TestFlight non si installa dal cavo su un iPhone qualsiasi: per quel pulsante serve l'IPA firmata per il telefono, salvata come `RefurbX.ipa` accanto a `project.yml`.

Il permesso NFC è solo `TAG`. Prima della firma Codemagic attiva NFC Tag Reading sull'App ID, cancella i profili App Store di `eu.refurbx.diagnostics` che non contengono TAG (compreso quello del 5 ottobre) e ne crea uno nuovo. La firma sceglie soltanto un profilo App Store il cui entitlement decodificato contiene `com.apple.developer.nfc.readersession.formats` con TAG. Ogni altro profilo ios_app_store viene messo da parte, anche se il bundle coincide. Archivio ed export usano quel profilo e `RefurbX.entitlements`. Se nessun profilo installato contiene TAG, la build si ferma e non pubblica l'IPA. Dopo l'IPA, `codesign -d --entitlements` sull'app dentro Payload deve mostrare TAG, e il log stampa il nome del profilo. Non si aggiunge `NDEF`: App Store Connect lo rifiuta con l'errore 90778.

Codemagic legge `codemagic.yaml` in questa cartella e compila sul Mac mini M2. La build parte solo a mano, così non consuma i minuti gratuiti prima che la firma sia pronta.

Prima di **Start build**:

1. Su App Store Connect crea la chiave API (Utenti e accessi, Integrazioni) con accesso Admin.
2. In Codemagic, account personale, Integrazioni, carica quella chiave con il nome esatto `RefurbX`.
3. In App Store Connect crea l'app iOS RefurbX Diagnostics con il bundle `eu.refurbx.diagnostics`.
4. In Codemagic premi **Check for configuration file**, poi **Start build**.

L'iPhone riceve l'app da TestFlight. L'immagine a infrarossi di Face ID resta nel sistema. L'app non legge l'IMEI. Cicli e salute delle celle non escono da un'app di terzi.
