# Mycroclean — lavanderia industriale

Gestionale statico per GitHub Pages con database e autenticazione Supabase. Il sito pubblico contiene solo codice; i dati operativi vengono caricati dopo l'accesso con email e password e la verifica dei permessi sul database.

## Funzioni

Prodotti, clienti in elenco, lavorazioni, lotti con numerazione server, scansione barcode da tastiera, riparazioni automatiche, riepilogo quantità per tipologia, ruoli amministratore/operatore/sola lettura, CSV/Excel, avvisi temporizzati ed editor etichette integrato con selezione multipla.

## Aggiornamento del 26 ottobre 2026

- Filtri combinabili per cliente, reparto, tipo, taglia, colore, proprietà e stato; filtri avanzati su tutte le colonne della scheda, anche quelle importate.
- Selezione di tutti i risultati, della pagina o di un intervallo di pagine da 50 prodotti. La selezione resta disponibile cambiando pagina e filtri; il contatore distingue il totale dai selezionati nei risultati correnti. Esportazione CSV/Excel anche dei soli selezionati.
- Cliente, utilizzatore e reparto in colonne e campi distinti. Reparti associati all’ID del cliente, anche dopo una rinomina.
- Anagrafiche amministratore: tipi, taglie, colori e reparti, con rinomina e disattivazione. I valori storici restano leggibili. I valori nuovi presenti negli import amministratore alimentano le anagrafiche.
- Clienti disattivabili e comando per riunire anagrafiche nel cliente principale, con reparto facoltativo. Nessuna fusione automatica dei nomi esistenti.
- Conteggi per riparazione, etichettatura e verifica nella lista lotti; accesso diretto agli interventi del lotto.

Le nuove tabelle Supabase hanno RLS e accesso diretto negato. Le operazioni passano dal gateway con controllo del ruolo, revisione e registro audit. Il file `sql/catalogs.sql` documenta l’estensione al database esistente; non è uno script per inizializzare un progetto vuoto.

Integrazione CO/Airtable e ordini di produzione: fase successiva, non implementata in questo aggiornamento.

## Pubblicazione

In GitHub: Settings → Pages → Build and deployment → Source: Deploy from a branch → Branch: main → Folder: / (root) → Save.

In Supabase: Authentication → URL Configuration. Impostare Site URL e Redirect URLs sull'indirizzo HTTPS esatto restituito da GitHub Pages. Questo indirizzo serve per conferma email e recupero password.

Al primo accesso usare l'email abilitata dall'amministratore, scegliere una password e confermare la mail. L'account Supabase usato per gestire il progetto non crea automaticamente un account utente nell'applicazione.

Gli amministratori abilitano le email nella sezione Utenti; i colleghi usano Primo accesso. Un account non abilitato non può leggere o modificare dati anche se completa la registrazione.

## Sicurezza

`config.js` contiene solo l'URL del progetto e una chiave publishable, progettata per l'uso nel browser. Non contiene una chiave service_role, un token server o password. Il gateway SQL verifica utente confermato, sessione attiva, anagrafica utenti, stato e ruolo a ogni richiesta. L'accesso diretto alle tabelle è negato. I dati importati e le credenziali non sono nel repository.

## Etichette

Da Prodotti: selezionare uno o più capi e scegliere Etichette selezionate. Dalla scheda: Salva e prepara etichetta. La sezione Etichette integra l'editor con anteprima, campi, logo, barcode/QR, dimensioni, layout e stampa A4/rotolo.

## Librerie

Supabase JS 2.57.4 e SheetJS CE 0.20.3 sono caricate da CDN con versioni fissate. Il modello etichette usa inoltre JsBarcode, qrcode-generator, PDF.js e Tesseract tramite CDN con versioni dichiarate nel file.
