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

## Scansione e operatività dei lotti

- Il lettore può terminare la scansione con Invio o Tab. È disponibile anche il riconoscimento automatico dopo 500 ms di pausa sul barcode. I codici sono testo: zeri iniziali e maiuscole/minuscole vengono conservati.
- Le scansioni vengono salvate in coda, una per volta, con il lotto, la fase e la lavorazione scelti al momento della lettura. Gli errori restano visibili tra le scansioni da controllare. Durante gli avvisi temporizzati è possibile acquisire i prossimi codici nel campo della finestra.
- Le tre fasi sono Entrata, Lavorazione, Uscita. La lettura in Lavorazione registra il trattamento eseguito e il suo completamento; il lavaggio aumenta una sola volta quando previsto. Le scansioni duplicate non aggiungono lavaggi. L’uscita richiede assenza di interventi aperti; l’eventuale completamento ancora da registrare viene contabilizzato automaticamente.
- Aggiungi prodotti riporta all’Entrata e conserva tutte le righe e le uscite precedenti. È possibile aggiungere nuovi codici al lotto anche dopo una riconsegna completa. Un nuovo ingresso dello stesso codice già presente richiede un nuovo lotto, per conservare la tracciabilità.
- Note nel lotto, filtri per codice/utilizzatore/note, tipo, reparto, taglia, fase e segnalazione. Esportazione CSV dei risultati con note e flag.
- I flag Sostituzione e Rilavaggio alimentano il riepilogo per tipo. Sostituzione è una segnalazione del prodotto: il flag non assegna un nuovo barcode. Rilavaggio su un prodotto già completato richiede un nuovo ciclo; la lettura in Lavorazione, oppure direttamente in Uscita senza interventi aperti, contabilizza il lavaggio una sola volta e conserva il conteggio dei cicli. Togliere il flag prima del nuovo ciclo ripristina il completamento precedente.
- Le etichette totali nel riepilogo includono le richieste completate; le etichette ancora da fare sono indicate separatamente. I conteggi riguardano l’intero lotto anche quando la tabella è filtrata.
- Ogni apertura della scheda prodotto ricarica da Supabase le anagrafiche aggiornate prima di mostrare i menu. I file JavaScript hanno un identificativo di versione per evitare di usare menu precedenti rimasti in cache.

Il trigger documentato in `sql/lot_workflow.sql` controlla anche sul server le uscite, il cliente dei nuovi prodotti e la conservazione delle righe precedenti.

## Stato e storico dei lotti

Gli stati sono rappresentati da pallini: rosso (Aperto), giallo (In lavorazione, compresa l’uscita parziale), verde (tutti i prodotti usciti). La sezione Storico contiene i lotti archiviati, mostrando inizialmente quelli ancora da finire. Il filtro consente di includere i completati. L’archiviazione conserva prodotti mancanti, note, flag e movimenti; il lotto può essere completato dallo storico o ripristinato nell’elenco attivo.

## Acquisizione e tipo prodotto

In Entrata un barcode assente dall’anagrafica apre una finestra con la sola scelta del tipo prodotto. Selezionata la voce, il prodotto del cliente del lotto e l’ingresso vengono registrati automaticamente. Annulla non crea il prodotto. Il flusso usa le RPC esistenti lot_acquire e lot_set_type; se la seconda operazione viene interrotta, una richiesta di completamento resta nella sessione del browser e consente di riprendere dopo il ricaricamento, senza duplicare il prodotto o la riga lotto. Proprietà, taglia e colore non noti restano da definire. I duplicati nello stesso lotto sono bloccati dal database, anche con diverse maiuscole e dopo l’uscita. Un prodotto già presente in un altro lotto aperto non viene acquisito di nuovo.

Seleziona tutto il lotto comprende anche le righe nascoste dai filtri. Assegna tipo ai selezionati aggiorna le schede prodotto, il campo TIPO per le etichette e i riepiloghi. Gli operatori possono eseguire questa operazione circoscritta sui prodotti del lotto; la creazione dei valori anagrafici resta riservata agli amministratori.

In Uscita un prodotto senza riparazioni, etichettature o verifiche aperte può essere registrato direttamente, anche se manca una precedente conferma di completamento. Il trattamento e gli eventuali lavaggi ancora da conteggiare vengono contabilizzati una sola volta durante l’uscita.

## Barcode progressivi e modificabili

La migrazione sql/product_barcodes.sql è applicata e il modulo product-barcodes.js è attivo. Gli amministratori possono scegliere un progressivo numerico assegnato dal database oppure inserire/modificare il barcode manualmente. L’identificativo interno resta stabile e le etichette, la ricerca e l’esportazione mostrano il barcode corrente. I precedenti codici rimangono riservati e riconducono allo stesso prodotto durante la lettura. Lotti, riparazioni e storico conservano i collegamenti. La nuova API richiede una sessione confermata e un amministratore attivo; non è accessibile agli utenti anonimi.

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

## Ricerca nei menu e sicurezza amministrativa

I menu permettono di scrivere per trovare una voce esistente, mantenendo valori e permessi del controllo originale. I risultati compaiono in un elenco visibile nella pagina, anche su iPhone e nei moduli a comparsa: scrivendo una parte del nome (es. toppa) si può toccare la voce completa (es. Toppa · Minuti). La scelta aggiorna i valori collegati, inclusi minuti e prezzo degli interventi. Sono supportati anche frecce, Invio, Escape e ricerca senza distinzione di accenti o maiuscole. I valori non presenti non vengono aggiunti tramite digitazione. Un prodotto di un cliente diverso apre un avviso e l’acquisizione rimane bloccata.

Il Super Admin è unico e coincide con l’account amministratore iniziale. Può creare ulteriori amministratori; gli amministratori ordinari gestiscono gli utenti operatore/lettore e le anagrafiche. Il ruolo e l’accesso del Super Admin sono protetti sul database. Cancella rimuove solo voci anagrafiche non collegate a prodotti, lotti o interventi; una voce utilizzata può essere disattivata.

## Tipi di riparazione e consuntivi

La tabella Tipi di riparazione è gestita dagli amministratori. Ogni voce è a pezzi (prezzo unitario in euro a tre decimali) oppure a minuti. È disponibile un tempo predefinito, modificabile durante la registrazione del lavoro eseguito.

Dalle Riparazioni: apri il lotto, premi Apri prodotto e poi Registra riparazione eseguita. La scheda del prodotto mostra gli interventi riferiti esclusivamente a quel lotto, con tipo, quantità, minuti, note, data e operatore (nome ed email dell’utente collegato). Il modulo propone i tipi di riparazione configurati dall’amministratore. Salva e aggiungi altro consente più interventi sullo stesso prodotto. Completa senza consuntivo mantiene disponibile la semplice chiusura della segnalazione, senza inventare tempi o prezzi.

Il lotto mostra minuti registrati, pezzi per tipo e importi dei lavori completati. Gli importi sono memorizzati in millesimi interi di euro e i tempi in centesimi di minuto. Ogni intervento conserva tipo, unità, prezzo applicato, quantità, tempo, operatore e data: la modifica successiva del listino non cambia i consuntivi precedenti. Le voci usate nei consuntivi non possono essere cancellate.

## Lettura con telefono

Nei lotti, Fotocamera usa la fotocamera posteriore per leggere continuativamente i codici; Leggi da foto accetta una foto scattata o scelta dalla galleria. La lettura registra automaticamente nella fase aperta (Entrata, Lavorazione o Uscita), attraverso la stessa coda e gli stessi controlli delle letture manuali. In entrata va selezionata prima la lavorazione. La stessa lettura della fotocamera viene inviata una sola volta durante ogni apertura; i duplicati sono inoltre bloccati dal normale flusso del lotto.

La modalità iniziale è Barcode prodotto (codici lineari, tra cui Code 128). QR / Data Matrix prodotto è disponibile per etichette che codificano direttamente l’identificativo del prodotto. Link e recapiti non vengono acquisiti. La fotocamera viene fermata quando cambia lotto, fase, lavorazione o pagina e quando il sito passa in secondo piano. Le foto vengono decodificate localmente, senza caricamento sul server. Il lettore ZXing Browser 0.1.5 viene caricato su richiesta da jsDelivr. Se la fotocamera è negata, è disponibile la lettura da foto; la lettura manuale rimane sempre accessibile. Su telefono il sito deve essere aperto in un browser con accesso alla fotocamera e deve esserne consentito l’uso.

## Numero stampato e interfaccia smartphone

Leggi numero attiva la fotocamera posteriore e l’OCR del solo codice stampato nel riquadro, anche se le barre del barcode sono rovinate. Non serve premere Registra: tre letture consecutive concordanti inviano il codice al flusso Entrata / Lavorazione / Uscita. Gli zeri iniziali sono conservati. Le letture incerte, i testi generici e le letture con più codici noti sono scartati; per un codice nuovo è richiesta una confidenza maggiore. Non vengono effettuate sostituzioni automatiche tra lettere e cifre simili. Le immagini restano in memoria e non vengono salvate né inviate al server. Tesseract.js e core 5.1.1 e il modello inglese 1.0.0 sono caricati su richiesta da CDN. Camera e worker OCR vengono fermati alla chiusura o al cambio di contesto.

Su smartphone il gestionale presenta una testata compatta e navigazione in basso, con menu completo Altro. Lotti, prodotti e righe lotto sono schede leggibili; i filtri sono richiudibili e i moduli si dispongono in una colonna. I dettagli aggiuntivi del prodotto si espandono nell’elenco. La vista desktop conserva le tabelle.

La migrazione barcode predisposta è stata rivista per riservare anche i precedenti codici e risolverli durante l’acquisizione server. È stata verificata in PostgreSQL isolato con creazione progressiva, modifica manuale, scansione di vecchie etichette, protezione dai duplicati e controllo dei ruoli. Dopo l’autorizzazione esplicita è stata applicata e verificata anche sul database condiviso, usando una transazione di prova annullata senza lasciare prodotti o lotti fittizi.

La sezione Accessori e riparazioni della scheda prodotto è un menu richiudibile con ricerca e selezione multipla. Il riepilogo indica il numero di voci selezionate. Le selezioni restano attive durante la ricerca e i valori storici già presenti vengono conservati al salvataggio.

I quattro riquadri della pagina Lotti sono scorciatoie: Lotti aperti mostra tutti i lotti attivi non chiusi; gli altri mostrano i lotti con prodotti in entrata, in lavorazione o usciti. I conteggi dei prodotti restano coerenti con i rispettivi stati e i lotti archiviati restano nello Storico. Il filtro scelto è evidenziato, può essere combinato con la ricerca ed è rimosso con Mostra tutti i lotti. L’esportazione segue l’elenco filtrato. Il numero del lotto è cliccabile e apre il dettaglio anche nello Storico; il pulsante Apri lotto nella colonna azioni è stato rimosso.

## Noleggi e dotazioni

La sezione è accessibile dalla navigazione desktop, dal menu Altro su smartphone e dall’elenco Clienti. I contratti sono salvati nel campo rentalContracts dell’anagrafica cliente tramite le API Supabase esistenti, con controllo della revisione condivisa; non richiedono nuove tabelle o permessi. Gli amministratori creano e modificano contratti/dotazioni e assegnano prodotti. Operatori e lettori possono consultarli ed esportarli.

Ogni contratto conserva riferimento, stato, decorrenza/fine, tipo di canone mensile (per prodotto, utilizzatore o fisso), importi in millesimi di euro, inclusione/prezzo dei lavaggi e condizioni. Importi non indicati restano da definire; non vengono generate fatture o addebiti. Sono effettivi solo i contratti attivi nelle date correnti. Contratti scaduti, futuri, sospesi, in bozza o chiusi restano consultabili.

Le righe di dotazione prevedono tipo prodotto, quantità, reparto legato al cliente, utilizzatore e taglia/colore facoltativi. Il confronto usa i prodotti Mycroclean a noleggio associati al cliente e all’ambito della riga. Scarti, smarriti e prodotti con limite lavaggi raggiunto sono esclusi dagli assegnati validi e indicati separatamente; prodotti in lavanderia ancora validi restano assegnati all’utilizzatore. Mancanti ed eccedenze sono calcolati per riga. Ambiti sovrapposti non sono ammessi nel contratto e tra contratti attivi con periodi sovrapposti, per evitare doppi conteggi. Gli identificativi delle anagrafiche mantengono il collegamento dopo la rinomina di un tipo, reparto, taglia o colore.

Assegna prodotti propone articoli utilizzabili dello stesso cliente e della stessa tipologia, rispettando taglia/colore e senza trasferire quelli di altri utilizzatori/reparti. La conferma aggiorna utilizzatore/reparto anche nei dati etichetta e registra l’assegnazione nello storico del prodotto e nel registro del cliente. Le variazioni del contratto e delle previsioni sono registrate in rentalEvents. La rimozione di una previsione conserva i prodotti assegnati. Non si possono cancellare dall’interfaccia clienti o voci anagrafiche riferiti ai contratti; è disponibile la disattivazione. L’unione di un cliente con contratti non chiusi è bloccata nell’interfaccia.

Il salvataggio rilegge l’anagrafica prima di applicare la variazione e conserva gli altri dati cliente; una modifica concorrente dello stesso contratto richiede di riaprire la scheda. Sono disponibili ricerca, filtri per mancanze/contratti e CSV di riepilogo o delle dotazioni del singolo cliente. Nessun contratto, canone o quantitativo previsto viene inventato dai prodotti importati: va configurato dall’amministratore.

### Mancanti e resi
`missing-returns.js` aggiunge il registro per barcode di segnalazione mancante, ritrovamento, reso definitivo dal cliente e rimessa in servizio. Il reso non è una normale uscita lavanderia. Le operazioni amministratore salvano stato `custody`, flag raw.SMARRITO/RESO, eventi `custodyEvents` con data operazione, registrazione, utente, cliente/utilizzatore/reparto e note/riferimento, più storico prodotto, in un unico salvataggio esistente su Supabase con controllo revisione. Nessuna nuova tabella o migrazione. Proprietà, cliente e barcode restano invariati. Resi e mancanti sono esclusi dalle dotazioni utilizzabili senza cambiare le quantità previste; gli scarti restano esclusi anche dopo un ritrovamento. Il reso è impedito finché esistono righe non uscite in qualunque lotto (anche archiviato). La UI scansioni richiede prima ritrovamento/rimessa in servizio per i prodotti segnalati. Ricerca, cliente, filtri cliccabili, CSV e layout mobile; accesso da Altro, scheda prodotto e cliente noleggi. Operatori/lettori consultano; l’API esistente impedisce loro modifiche di questi campi anagrafici.
