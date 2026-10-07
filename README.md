# RefurbX Diagnostica per iPhone e iPad

App nativa dei test, versione 1.0.50 (build 51). Sul dispositivo il nome è **RefurbX Diagnostica**. Gira su iPhone e iPad. Team ID `L9F47LJC86`, bundle `eu.refurbx.diagnostics`.

Le prove che questo modello non ha restano in fondo, scure, e non partono. Su un altro dispositivo si accendono da sole: la penna sugli iPad che la ricevono, il 3D Touch sugli iPhone che lo hanno ancora.

A fine diagnosi, nella scheda, incolla il link del banco e premi **Invia al banco**. Codemagic carica l'app su TestFlight senza inviarla ogni volta alla revisione beta: quel limite di Apple si era già esaurito. I tester interni la installano subito. La revisione per i tester esterni si fa a mano, una volta, da App Store Connect.

Il permesso NFC è solo `TAG`. Prima dell'archivio il log scrive il nome del profilo e se contiene TAG. L'export usa lo stesso certificato Apple Distribution e quel profilo, e passa `RefurbX.entitlements`. La pubblicazione si ferma se `codesign -d --entitlements :-` sull'app dentro l'IPA non mostra TAG: non basta controllare l'archivio. Non si aggiunge `NDEF`: App Store Connect lo rifiuta con l'errore 90778.

Codemagic legge `codemagic.yaml` in questa cartella e compila sul Mac mini M2. La build parte solo a mano, così non consuma i minuti gratuiti prima che la firma sia pronta.

Prima di **Start build**:

1. Su App Store Connect crea la chiave API (Utenti e accessi, Integrazioni) con accesso Admin.
2. In Codemagic, account personale, Integrazioni, carica quella chiave con il nome esatto `RefurbX`.
3. In App Store Connect crea l'app iOS RefurbX Diagnostics con il bundle `eu.refurbx.diagnostics`.
4. In Codemagic premi **Check for configuration file**, poi **Start build**.

L'iPhone riceve l'app da TestFlight. L'immagine a infrarossi di Face ID resta nel sistema. L'app non legge l'IMEI. Cicli e salute delle celle non escono da un'app di terzi.
