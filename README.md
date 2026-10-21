# RefurbX 1.0.82 (86) — preparazione alla revisione

Progetto Swift per iPhone e iPad, iOS 17 o successivo. Bundle eu.refurbx.diagnostics. Il progetto Xcode viene generato da project.yml con XcodeGen.

Questa consegna contiene correzioni ai sorgenti. Non è stata compilata con Xcode né provata su un dispositivo: l'ambiente di lavoro è Windows. Non costituisce una garanzia di approvazione Apple. Non inviare in revisione prima di completare i controlli sotto.

## Correzioni

- Eliminati funzione readMemory, stato e riferimenti del vecchio test memoria, già assente dal catalogo 1.0.81. Nessuna diagnosi di RAM o integrità dell’archiviazione. La lettura del volume è disponibile soltanto nella nuova schermata informativa Spazio di archiviazione.
- Pre-schermate dei permessi: assenza di Salta anche per bussola, biometria, movimento e NFC. L'utente mantiene il controllo nella richiesta di sistema e può saltare le prove dopo un rifiuto.
- NFC: dopo la spiegazione, Continua avvia direttamente la sessione Core NFC e mostra il foglio di scansione di Apple. Rimosso il pulsante intermedio Apri lettore tag; Riprova NFC compare solo se la sessione si chiude prima di una lettura.
- Il ritorno in primo piano non avvia più richieste GPS dalla fase di spiegazione. Ripristino TrueDepth dopo Impostazioni incluso.
- Luce: resta una verifica automatica della risposta della luminosità dello schermo. Per 40 secondi campiona UIScreen.brightness mentre l'operatore copre e scopre la zona superiore con Luminosità automatica attiva. Se rileva una variazione sufficiente registra la risposta osservata; se non la rileva, l'esito è inconclusivo. Non misura lux, non legge direttamente il sensore ambientale e non certifica il componente.
- Eliminati URL non documentati delle impostazioni; uso di UIApplication.openSettingsURLString. Wi-Fi e Bluetooth si attivano nelle Impostazioni di sistema, come spiegato dal testo.
- Privacy manifest: dichiarazione UserDefaults, motivo CA92.1 per preferenze dell'app; dichiarato 85F4.1 per mostrare lo spazio del volume nella schermata informativa, separata dai test e dagli export.
- Aggiunto nella home il collegamento diretto all'informativa privacy. Prima della revisione verifica che https://refurbx.eu/privacy-policy sia raggiungibile, descriva correttamente i dati e le finalità effettivi e coincida con l'URL indicato nei metadati App Store Connect.
- Esclusi dai risultati ripristinati gli identificativi non più presenti nel catalogo.
- Versione coerente in Info.plist e project.yml: 1.0.82, build 86.
- Codemagic usa scripts/apply_profile.py leggibile, invece di due copie codificate Base64 identiche. Aggiunto preflight. Tolta la cancellazione automatica dei profili remoti Apple; restano verifica e selezione del profilo NFC TAG.

## Caricamento su Codemagic

1. Estrai lo ZIP e inserisci IL CONTENUTO nella radice del repository collegato a Codemagic. codemagic.yaml e project.yml devono essere alla radice, con RefurbX/ e scripts/ accanto.
2. Usa il workflow RefurbX iOS (identificativo ios-testflight). Parte manualmente.
3. Mantieni l'integrazione App Store Connect chiamata RefurbX e il gruppo di variabili signing con CERTIFICATE_PRIVATE_KEY. Usa i segreti già configurati nel tuo account, senza inserirli nei file.
4. L'App ID eu.refurbx.diagnostics deve avere NFC Tag Reading e un profilo App Store valido con TAG. Se manca, configura o rigenera il profilo corretto in Apple Developer e ripeti la build. Il workflow non cancella più profili sul tuo account.
5. Controlla che 86 sia superiore alle build già caricate per questa versione. Se è già stato usato, aggiorna CFBundleVersion in Info.plist e CURRENT_PROJECT_VERSION in project.yml allo stesso numero superiore.
6. Avvia la build. Il workflow compila, verifica la firma NFC e carica su App Store Connect; NON invia automaticamente in revisione e NON abilita la distribuzione TestFlight. Per provare su un dispositivo usa il canale di test interno già configurato oppure una build di sviluppo/ad hoc firmata per il dispositivo.
7. Se la compilazione fallisce, conserva il log completo, soprattutto le righe error:. Non inviare una build precedente per aggirare l'errore.

## Prove obbligatorie prima dell'invio

- Installazione pulita: test fotocamera, microfono, GPS, bussola, Bluetooth e Face ID/Touch ID. Sulle pre-schermate non deve comparire Salta. Continua apre il flusso della funzione; iOS mostra la richiesta solo se il relativo consenso non è già stato deciso.
- Per ogni permesso: prova consenso, rifiuto, ritorno da Impostazioni e interruzione/ripresa dell'app. Il rifiuto non deve produrre una diagnosi di guasto.
- Prova Risposta alla luce su un iPhone reale con Luminosità automatica attiva: copri la zona superiore per 15 secondi, poi scopri e porta il telefono in un ambiente luminoso. Controlla che la misura automatica si aggiorni e che il risultato senza variazione resti inconclusivo. Non è una misura in lux né una diagnosi del sensore.
- Verifica assenza di Memoria/RAM/diagnosi archiviazione in home, percorso completo, scheda PDF ed esportazioni. Ripeti dopo aggiornamento da una build precedente e ripristino di una sessione.
- Percorso completo su iPhone, poi iPad se mantieni l'app universale: schermo, audio, fotocamere, tasti, sensori, ricarica, biometria, NFC, scheda PDF e invio al banco. Controlla che prove non supportate risultino assenti e non guaste.
- Le prove manuali e quelle indirette (es. screenshot per il tasto, stato di carica per la ricarica) verificano comportamenti osservati, non certificano l'integrità dei componenti.

## App Store Connect e sito: interventi esterni ancora necessari

- Rimuovi da nome promozionale, sottotitolo, descrizione, parole chiave e screenshot qualsiasi promessa di diagnosi della memoria/RAM/archiviazione e di misura automatica del sensore ambientale.
- Descrivi l'app come raccolta di verifiche funzionali guidate, con prove automatiche dove supportate dalle API e conferme manuali dove indicate. Non promettere certificazione completa dell'hardware o componenti originali.
- Usa screenshot REALI della nuova build per iPhone e iPad. Nessun risultato inventato.
- Verifica la privacy policy effettivamente pubblicata a https://refurbx.eu/privacy-policy. Questo progetto non modifica il sito. Deve descrivere anche TrueDepth/ARKit, elaborazione temporanea locale, audio di prova e trasferimento volontario della scheda al banco. Controlla che non contraddica funzioni e destinazioni reali.
- Ricontrolla le risposte App Privacy in base ai dati effettivamente trasmessi e a chi li riceve. NSPrivacyCollectedDataTypes nel manifest non sostituisce la dichiarazione App Store Connect e non dimostra da solo che non avvenga raccolta.
- Per Apple allega eventualmente un video reale del test NFC con un tag compatibile e istruzioni per usare l'app senza il computer del banco. Non dichiarare verifiche che non hai eseguito.
- Seleziona la nuova build dopo i controlli e usa APPLE_REVIEW_REPLY.txt come bozza di risposta, correggendola se modifichi ulteriormente il progetto.

## Verifiche eseguite in questa consegna

scripts/validate_release.py controlla versioni, plist, motivi privacy, entitlement TAG, riferimenti rimossi, classificazione prudente della prova luce e risorse immagini. I sorgenti Python sono stati analizzati sintatticamente. Questi controlli non sostituiscono il compilatore Swift, la firma Apple o i test su dispositivo.

## Adattamento al dispositivo

Le prove sono filtrate da HardwareFit.supports. LiDAR, TrueDepth, NFC, 3D Touch, accelerometro, giroscopio e bussola usano controlli di disponibilità delle API. Altre caratteristiche, come Pencil, tasti fisici e ricarica wireless, includono regole basate sul modello e vanno provate sui dispositivi supportati; non è garantita una classificazione corretta di ogni modello futuro. Modelli non presenti nella tabella mostrano il codice tecnico come fallback.

Corretta l'esclusione errata della ricarica Qi su iPhone SE 2020, SE 2022 e 16e: questi modelli supportano Qi. Unificata la regola tra catalogo e avvio del test. Gli iPad restano esclusi dalla prova wireless.

Riferimenti: https://support.apple.com/en-gb/111882 , https://support.apple.com/en-us/111866 , https://support.apple.com/en-us/122208 .

## Audit della build 85 (sostituito dalla correzione build 86)

- Aggiunta la schermata separata Spazio di archiviazione, nella home: totale del volume, disponibile e occupato calcolato. La build 86 usa volumeAvailableCapacityForImportantUsageKey per mostrare la capacità stimata da iOS per risorse importanti. Non legge RAM o salute del disco; i valori possono differire da Impostazioni. Nessuna persistenza, nessun esito diagnostico, nessun inserimento in PDF, condivisioni o payload del banco. Motivo privacy 85F4.1.
- Il file outbox.json per il banco viene scritto solo dopo Invia al banco. A ogni avvio o nuova sessione viene eliminata la vecchia outbox per evitare trasferimenti involontari o schede obsolete. L'invio volontario via Internet della scheda continua a essere possibile se il banco lo prevede; lo spazio di archiviazione ne è escluso.
- PDF: note complete, altezza delle righe calcolata sul testo, titoli separati dallo stato. Condivisione testuale senza troncamento arbitrario e con avvertenza.
- Eliminati dal payload il numero di tocchi fittizio e il campo secureContext dedotto erroneamente dal codice del banco; lingua ricavata dal sistema.
- Registrazioni microfono eliminate alla chiusura della prova, dopo arresto della riproduzione.
- Ripresa sessione: conserva il test corrente quando cambia il catalogo; la build 86 invalida gli esiti manuali precedenti della prova luce, che deve essere ripetuta con la nuova misura automatica. Protezioni contro callback di prove precedenti.
- Richiesta biometrica avviata senza mostrare Salta durante un ritardo preliminare. Biometria non disponibile/non autorizzata non è classificata automaticamente come hardware assente.
- Cavo e pad: lo stato di carica iOS non distingue la sorgente; l'esito positivo richiede la conferma dell'operatore. Aggiornate le istruzioni.
- Firma: se l'App ID manca dalla risposta Apple, la build si ferma invece di usare un identificativo account fisso. Confronto esatto del bundle nei profili.

### Workflow di compilazione aggiuntivo

In Codemagic puoi prima eseguire **RefurbX - verifica compilazione senza firma** (ios-compile-check). Compila l'app per simulatore con Xcode senza accedere ad Apple Developer o pubblicare. È utile per separare errori Swift da problemi di certificati. Questo workflow è preparato ma NON è stato eseguito da questa sessione Windows. Dopo il successo esegui RefurbX iOS per archivio, firma e upload, quindi prova la build su dispositivo.

### Test offline eseguiti

8 test del codice di preparazione firma: estrazione App ID da JSON annidato, arresto se manca l'App ID, rifiuto di NDEF insieme a TAG, lettura entitlements con messaggi codesign, rifiuto profili scaduti/development/enterprise, arresto senza TAG, modifica delle impostazioni del solo target previsto. Nessun test contatta Apple o verifica certificati reali. Eseguiti inoltre i controlli di validate_release.py, inclusa separazione della schermata spazio dagli export.

### Prima di dichiarare il pacchetto pronto

Restano NON verificati: compilazione Xcode dei sorgenti modificati, generazione effettiva del progetto, firma con i tuoi certificati, installazione, permessi e interruzioni su dispositivo, risposta della luminosità automatica in condizioni reali, confronto dello spazio disponibile con Impostazioni, qualità audio/video, layout iPhone/iPad/PDF e comunicazione con il tuo banco. Il preflight non certifica questi aspetti. Non inviare ad Apple finché non sono stati controllati. Se build 86 è già stata usata, scegli un numero superiore nei due file versione.

Riferimento Apple per la visualizzazione dello spazio e i vincoli di trasferimento: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype .
