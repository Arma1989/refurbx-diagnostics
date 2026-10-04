# RefurbX Diagnostics per iPhone

App nativa dei test. Team ID `L9F47LJC86`, bundle `eu.refurbx.diagnostics`.

Codemagic legge `codemagic.yaml` in questa cartella e compila sul Mac mini M2. La build parte solo a mano, così non consuma i minuti gratuiti prima che la firma sia pronta.

Prima di **Start build**:

1. Su App Store Connect crea la chiave API (Utenti e accessi, Integrazioni) con accesso Admin.
2. In Codemagic, account personale, Integrazioni, carica quella chiave con il nome esatto `RefurbX`.
3. In App Store Connect crea l'app iOS RefurbX Diagnostics con il bundle `eu.refurbx.diagnostics`.
4. In Codemagic premi **Check for configuration file**, poi **Start build**.

L'iPhone riceve l'app da TestFlight. L'immagine a infrarossi di Face ID resta nel sistema. L'app non legge l'IMEI. Cicli e salute delle celle non escono da un'app di terzi.
