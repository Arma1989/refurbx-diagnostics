# RefurbX Diagnostica per iPhone e iPad

App nativa dei test, versione 1.0.78 (build 80). Sul dispositivo il nome è **RefurbX Diagnostica**. Gira su iPhone e iPad. Team ID `L9F47LJC86`, bundle `eu.refurbx.diagnostics`.

Le prove che questo modello non ha restano in fondo, scure, e non partono. Su un altro dispositivo si accendono da sole: la penna sugli iPad che la ricevono, il 3D Touch sugli iPhone che lo hanno ancora.

A fine diagnosi, nella scheda, scrivi solo il codice di sei lettere del banco, per esempio `Q2DRA7`, e premi **Invia al banco**. L'iPhone sente il computer sulla stessa Wi-Fi. Col cavo il programma Windows scrive `Documents/bench.url` e legge `Documents/outbox.json`: la scheda arriva anche senza Wi-Fi. Il banco può arrivare anche come argomento di avvio. Codemagic compila la 1.0.78 (build 80), carica l'IPA e la manda in revisione App Store. Il rilascio resta manuale: dopo l'ok di Apple l'app non va online da sola. TestFlight non parte da questa build, perché il limite della revisione beta esterna è già esaurito. L'IPA di TestFlight non si installa dal cavo su un iPhone qualsiasi: per quel pulsante serve l'IPA firmata per il telefono, salvata come `RefurbX.ipa` accanto a `project.yml`.

Il permesso NFC è solo `TAG`. Prima della firma Codemagic attiva NFC Tag Reading sull'App ID, cancella i profili App Store di `eu.refurbx.diagnostics` che non contengono TAG (compreso quello del 5 ottobre) e ne crea uno nuovo. La firma sceglie soltanto un profilo App Store il cui entitlement decodificato contiene `com.apple.developer.nfc.readersession.formats` con TAG. Ogni altro profilo ios_app_store viene messo da parte, anche se il bundle coincide. Archivio ed export usano quel profilo e `RefurbX.entitlements`. Se nessun profilo installato contiene TAG, la build si ferma e non pubblica l'IPA. Dopo l'IPA, `codesign -d --entitlements` sull'app dentro Payload deve mostrare TAG, e il log stampa il nome del profilo. Non si aggiunge `NDEF`: App Store Connect lo rifiuta con l'errore 90778.

Codemagic legge `codemagic.yaml` in questa cartella e compila sul Mac mini M2. La build parte solo a mano, così non consuma i minuti gratuiti prima che la firma sia pronta.

Prima di **Start build** la scheda dell'app deve già esistere su [App Store Connect](https://appstoreconnect.apple.com). Se manca uno screenshot, l'URL privacy o la categoria, l'IPA si carica lo stesso e il passo «invia in revisione» fallisce: si completa la scheda e si preme **Aggiungi per la verifica** su quella build.

1. Chiave API già usata da Codemagic: Utenti e accessi, Integrazioni, accesso Admin o App Manager, nome integrazione `RefurbX`.
2. App iOS con bundle `eu.refurbx.diagnostics`. Se non c'è, creala: nome **RefurbX Diagnostica**, lingua principale Italiano, SKU `refurbx-diagnostics`.
3. Versione **1.0.78**. Compila questi campi e salva:
   - Sottotitolo: `Test hardware iPhone e iPad`
   - Categoria: Utilità
   - URL assistenza: `https://refurbx.eu`
   - URL privacy: `https://refurbx.eu/privacy-policy` (`/privacy` risponde 404)
   - Copyright: `2026 REFURBX S.R.L.`
   - Descrizione: app di diagnosi per iPhone e iPad. Controlla schermo, fotocamere, Face ID o Touch ID, altoparlanti, rete, NFC e gli altri pezzi che quel modello ha. I test assenti restano spenti. A fine prova la scheda si invia al computer del negozio. L'app non legge l'IMEI.
   - Novità: `Prima versione.`
4. Screenshot, almeno tre per formato, presi dall'app vera (home, un test, scheda). iPhone 6,9" (l'iPhone 17 Pro Max va bene, 1320×2868) e iPad 13" (2064×2752). Senza gli screenshot iPad Apple non accetta l'invio: l'app è universale.
5. Classificazione età: 4+. Nessun account, nessun contenuto generato dagli utenti.
6. Privacy dell'app: **No** al tracciamento e **No** alla raccolta dati. È lo stesso di `PrivacyInfo.xcprivacy`: foto, audio, GPS, Bluetooth e NFC restano sul telefono per il test. La scheda esce solo se premi Invia, verso il computer del negozio, non verso un server RefurbX.
7. Crittografia: l'app non usa cifratura propria. In Info.plist c'è già `ITSAppUsesNonExemptEncryption` = false. Se Apple lo chiede, rispondi no.
8. Note per il team di revisione, da incollare:

```
App di diagnosi per iPhone e iPad. Non serve un account.
Face ID non esporta l'immagine a infrarossi: resta nel sistema.
L'NFC legge solo un tag (entitlement TAG, non NDEF).
L'IMEI lo legge il computer del negozio dal cavo, non l'app.
Se il Wi-Fi è spento, il test apre la pagina Wi-Fi di Impostazioni.
I test che il modello non ha restano spenti, in fondo alla lista.
```

9. In Codemagic: **Check for configuration file**, poi **Start build** sul workflow RefurbX iOS. A fine build Codemagic invia la 1.0.78 in revisione e lascia il rilascio su **Manuale**. Quando Apple approva, su App Store Connect premi tu **Rilascia**. La revisione dura alcuni giorni: stasera parte la coda, non la pagina dello store.

La pagina `https://refurbx.eu/privacy-policy` è la privacy del negozio. Se Apple chiede che citi anche l'app di diagnosi, aggiungi lì questo paragrafo: RefurbX Diagnostica usa fotocamera, microfono, posizione, Bluetooth, NFC e Face ID o Touch ID solo per il test sul telefono. Foto e audio non vengono caricati. L'immagine a infrarossi di Face ID resta nel sistema. L'app non legge l'IMEI, non ha pubblicità e non traccia. La scheda esce dal telefono solo se la invii al computer del negozio.

L'immagine a infrarossi di Face ID resta nel sistema. L'app non legge l'IMEI. Cicli e salute delle celle non escono da un'app di terzi.
