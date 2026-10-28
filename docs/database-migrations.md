# Migrazioni SQL: procedura controllata

## Stato e ambito

Questo ramo prepara un aggiornamento; non certifica né modifica Supabase operativo.
Il repository non contiene lo schema originario completo (`laundry_members`,
`laundry_products`, `laundry_repairs`, gateway `laundry_app`, trigger storici, ecc.).
Non eseguire `db reset` su un database reale e non trattare questa sequenza come
inizializzazione di un progetto vuoto. Per un'installazione nuova occorre prima
recuperare e revisionare una baseline completa e anonimizzata.

Gli script storici in `sql/*.sql` sono ora arresti espliciti: non modificano nulla.
Le loro versioni originali restano nella cronologia Git e, esclusivamente per
riprodurre regressioni, in `tests/database/fixtures/legacy-sql.json`.
Non eseguire tali fixture fuori dal processo di test.

## Sequenza unica

Usare solo la cronologia Supabase, in ordine di timestamp:

| Versione | Contenuto |
| --- | --- |
| 20261026204528 | Ordini clienti Airtable |
| 20261026220115 | Collegamento ordini/lotti |
| 20261026222534 | Pianificazione produzione |
| 20261027060819 | Postazioni |
| 20261027061557 | Programmi macchina |
| 20261027065752 | Calendario ricorrente e pg_cron |
| 20261027072835 | Calendario per cliente/reparto |
| 20261027090941 | Consolidamento core, cataloghi, barcode, uscite e Super Admin esplicito |

La verifica read-only del 27 ottobre ha rilevato che le sette migrazioni hanno
identificativi diversi in Supabase. `supabase/legacy-version-map.json` registra
la corrispondenza verificata: il SQL registrato coincide con quello del repository,
ignorando soltanto gli spazi esterni. Il preflight accetta entrambi gli identificativi
solo con nome e contenuto SQL corrispondenti. Non modifica la cronologia e non
riesegue migrazioni. Non usare un `db push` indiscriminato: la CLI può interpretare
le versioni del repository come ancora pendenti. Prima del deploy occorre una
procedura di riconciliazione revisionata, senza inventare migrazioni applicate.

La creazione del branch Supabase di prova è stata rifiutata nella conferma dello
strumento: il collaudo reale non è stato eseguito e il rilascio operativo rimane
sospeso. Le verifiche di codice non sostituiscono quel collaudo.

Le sette migrazioni già versionate sono immutate. La nuova migrazione richiede
che queste versioni siano registrate e che esistano le tabelle necessarie.
Se la cronologia non è stata mantenuta, **fermarsi e confrontare lo schema reale**:
non segnare migrazioni come applicate senza verificarne tutti gli effetti.
Non ripetere quelle già applicate: alcune creano oggetti non idempotenti.

La nuova migrazione è transazionale, prende un lock consultivo e usa un timeout
per i lock. Accetta soltanto i corpi delle funzioni storiche conosciute, comprese
le varianti con/senza risoluzione degli alias barcode. Una versione sconosciuta
richiede revisione e integrazione delle differenze, non l'aggiunta indiscriminata
del suo hash alla lista consentita. Il core finale contiene direttamente tutte
le funzionalità: nessuna sostituzione testuale di `pg_get_functiondef` a runtime.
I contatori barcode già utilizzati non vengono riportati indietro.

`core_release` impedisce di rieseguire questo rilascio, anche se manca la relativa
riga di cronologia Supabase. Le impronte delle funzioni consentono di rilevare
successive alterazioni. Le modifiche future vanno in **nuove migrazioni** che
verificano la versione precedente e aggiornano impronte e versione del rilascio.
Non modificare i file applicati o i loro checksum per aggirare un controllo.
La protezione non può impedire a un proprietario PostgreSQL di eseguire vecchio
SQL copiato fuori dal repository: limitare le sessioni privilegiate e verificare
il rilascio dopo ogni manutenzione.

## Super Admin: scelta obbligatoria e separata

Nessun ordinamento per data, email o primo utente. La migrazione non promuove
nessuno: un'eventuale scelta automatica storica è conservata ma rimane **non
confermata**, senza potere di nominare amministratori. Gli amministratori ordinari
mantengono le normali funzioni. Pianificare la conferma nella stessa finestra di
manutenzione per evitare un periodo senza gestione degli amministratori.

Dopo revisione e autorizzazione, un manutentore privilegiato deve:

1. Identificare esplicitamente l'UUID dell'account in `auth.users`, verificarne
   email, conferma, stato e corrispondenza con un amministratore attivo in
   `laundry_members`. Non usare l'UUID di un account di gestione del progetto.
2. Leggere la scelta precedente, se presente, nella tabella privata
   `laundry_super_admin`. Farla verificare dalla persona autorizzante.
3. Eseguire `sql/operations/designate_super_admin.sql` con le variabili psql
   `super_admin_user_id` e `expected_previous_email` (stringa vuota se non c'è
   alcuna riga precedente). Il confronto impedisce una sostituzione inconsapevole.

La funzione di designazione non è eseguibile da `anon`, `authenticated` o
`service_role`. Verifica l'account e acquisisce i lock prima di scrivere, registra
l'operazione nell'audit, consente di ripetere la conferma dello stesso account e
rifiuta di trasferire una designazione già confermata. Un trasferimento futuro
richiede una procedura amministrativa distinta e revisionata. Il privilegio è
legato sia all'email sia all'UUID confermato, non solo a una stringa riutilizzabile.

## Verifica prima del rilascio

1. `npm ci --ignore-scripts && npm test` esegue checksum, regressioni SQL e test
   del pianificatore. Non richiede rete verso Supabase o credenziali di produzione.
2. Su un **ripristino anonimizzato in staging**, raccogliere un backup e
   l'inventario con `sql/operations/preflight.sql`. Confrontare schema, trigger,
   gateway e cronologia con le dipendenze dichiarate. Questo passaggio è ancora
   necessario: le fixture non sono un dump del database reale.
3. Risolvere eventuali migrazioni mancanti in ordine. Prima di applicare,
   controllare l'elenco delle migrazioni pendenti con la CLI Supabase e la sua
   modalità dry run. Un dry run non sostituisce i test sul database di prova.
4. Applicare in staging il rilascio con la procedura di migrazione Supabase,
   confermare un account di prova esplicito ed eseguire
   `psql -X -v ON_ERROR_STOP=1 -f sql/operations/verify_release.sql`.
5. Sul ripristino verificare anche gli oggetti non presenti nel repository:
   proiezione `laundry_repairs`, trigger originali, ACL del gateway, API PostgREST,
   sessioni Supabase reali e job `pg_cron`. Provare i flussi dell'interfaccia con
   account admin/operatore/lettore. Conservare log, versione Git e risultati.
6. Solo dopo autorizzazione esplicita sul piano concreto: backup verificato,
   finestra di manutenzione, migrazione delle sole versioni pendenti,
   designazione dell'account approvato e verifica read-only sul database operativo.
   Non è incluso alcun workflow di deploy o credenziale Supabase in questa PR.

In caso di errore nella nuova migrazione, la transazione annulla il rilascio.
Non fare rollback eseguendo vecchie definizioni del core. Se un problema emerge
dopo il commit, fermare le scritture e preparare una correzione successiva oppure
un ripristino concordato; non promettere rollback automatico dei dati.

## Test e limiti dichiarati

La suite esegue PostgreSQL tramite PGlite in memoria, con ruoli e permessi reali
nel motore SQL. `auth.users`, `auth.sessions`, `auth.uid()` e `auth.jwt()` sono
fixture minime per simulare le sessioni; non collaudano GoTrue o PostgREST.
Il motore non offre background worker: solo le due istruzioni di installazione
e pianificazione `pg_cron` sono escluse durante il test, mentre tutte le funzioni
applicative delle migrazioni vengono eseguite. Nessuna connessione esterna al DB.

Scenari: installazione storica completa; core sovrascritto dall'acquisizione;
Super Admin non assegnato; acquisizione senza amministrazione/barcode;
amministrazione eseguita dopo barcode; cronologia con gli identificativi effettivi
di Supabase e rifiuto di SQL alterato a parità di versione. Si verificano ordine, rifiuto delle
funzioni sconosciute, rollback, rifiuto del replay, script legacy bloccati e
rilevamento del drift. I test passano attraverso le RPC con ruolo `authenticated`
e verificano anche l'accesso negato alle funzioni interne e alle tabelle.

Flussi: scansione con zeri iniziali, duplicati e alias; tipo prodotto; clienti e
lotti aperti; completamento, interventi e rilavaggi prima dell'uscita; persistenza
dei millesimi dei consuntivi; listino storico e cancellazione di voci utilizzate;
revisioni obsolete; ruoli, account inattivi/non confermati/bannati/anonimi e
sessioni revocate; designazione esplicita e protezione del Super Admin.

I conteggi dei lavaggi e i costi sono calcolati dal client attuale: i test SQL
verificano persistenza, protezioni e assenza di incrementi causati dal salvataggio,
non certificano la coda scanner nel browser né introducono un calcolo server dei
consuntivi. Questi aspetti e la concorrenza tra connessioni reali richiedono il
collaudo staging indicato sopra. La CI su GitHub esegue la stessa suite isolata;
non applica migrazioni operative.
