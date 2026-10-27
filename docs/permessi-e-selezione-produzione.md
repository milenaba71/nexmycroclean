# Permessi utenti e selezione in Produzione

## Super amministratore

Aprire **Utenti e ruoli → Ruolo e permessi** accanto all'utente. Scegliere Amministratore, Operatore, Operatore base oppure Sola lettura; quindi selezionare le operazioni ammesse e salvare.

Le dieci caselle distinguono lavoro nei lotti (scansioni, note, segnalazioni e riparazioni), creazione lotti, schede prodotto, anagrafiche/clienti/contratti, esecuzione attività e macchinate, pianificazione/configurazione produzione, cancellazioni, ticket, abbinamenti Airtable e PDF.

L'Operatore base parte con il lavoro nei lotti e l'esecuzione delle attività assegnate. L'Operatore parte anche con creazione lotti e ticket. I poteri amministrativi richiedono il profilo Amministratore. La consultazione dei dati rimane disponibile: queste caselle limitano le operazioni, non la visibilità dei dati per cliente o reparto.

Solo l'unico Super amministratore può gestire ruoli e permessi. Non è possibile rimuovere o ridurre il suo accesso da questa schermata. I permessi sono verificati nelle operazioni sul server; nascondere o disabilitare un pulsante non costituisce l'unico controllo.

## Selezione multipla

In **Produzione → Pianificazione** e **Attività operatori**, l'amministratore seleziona le caselle delle attività. Può selezionare tutti i risultati visibili e deselezionarli. La selezione resta attiva cambiando filtro; la conferma elenca esattamente le attività interessate.

- **Elimina pianificazioni selezionate**: rimuove gli orari e le assegnazioni, mantenendo le attività da ripianificare.
- **Elimina attività selezionate**: rimuove attività non avviate e relative assegnazioni. Non elimina lotti, prodotti, ingressi o uscite.

Le attività avviate, concluse o con tempi registrati restano nello storico. Se un'attività successiva dipende da una selezionata per eliminazione, includere anche la successiva o correggere il collegamento: non vengono cancellate implicitamente attività non selezionate. Il piano viene marcato da ricalcolare.

Per la cancellazione occorrono ruolo Amministratore e potere **Eliminare pianificazioni, attività e lotti non lavorati**. Si registrano operatore, motivo e dati precedenti nel registro di audit.

## Ordine installazione

Applicare `production_bulk_delete.sql` prima di `user_permissions.sql`. Quest'ultima migrazione aggiunge i controlli alle definizioni correnti delle funzioni, senza ripristinare vecchie copie di `laundry_core`. Non reinstallare vecchie migrazioni di autorizzazione sopra una versione più recente senza revisione.
