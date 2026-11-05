# Mascherine · Confezionamento

La sezione è disponibile nel menu ufficio, dopo DDT fornitori, e nella schermata iniziale della vista operatori. Le righe sono quelle dei DDT sincronizzati la cui descrizione contiene mascherina o mascherine. Non è richiesto il barcode.

1. Cercare fornitore, numero DDT o articolo.
2. Controllare **Rientrati** e **Da imbustare**. I rientri devono essere prima registrati nel modulo DDT e sincronizzati.
3. Dopo aver contato i pezzi effettivamente imbustati, premere **Carica imbustati** e inserire solo i nuovi pezzi confezionati. Unità di misura: singola mascherina, non confezione multipla.
4. Il totale **Imbustati** aumenta e la **Giacenza confezionata** viene aggiornata subito nel gestionale.
5. Quando il materiale confezionato lascia il magazzino, premere **Scarica confezionati**, inserire i pezzi e indicare nelle note la destinazione. Lo scarico riduce la giacenza.
6. **Storico** mostra operatore, data, quantità e note. Gli utenti con permesso di eliminazione possono annullare un movimento indicando il motivo. Se un confezionamento è già stato scaricato, occorre correggere prima lo scarico.

Giacenza = pezzi imbustati − pezzi scaricati, inclusi gli storni. Queste registrazioni sono conservate nel gestionale e non modificano QTY RIENTRATA in Airtable. Il magazzino parte da zero: eventuali pezzi già imbustati devono essere contati e caricati.

# Correggere un rientro DDT errato

In **DDT fornitori → Storico rientri → Annulla carico**, indicare il motivo e confermare. È richiesto il permesso di eliminazione. I carichi non ancora presi in invio vengono annullati subito. Se l'invio è già iniziato, attendere la sincronizzazione e ripetere l'annullamento. Per i carichi sincronizzati viene creato uno storno, inviato ad Airtable al ciclo successivo (circa cinque minuti).

Lo storico resta consultabile. I rientri già usati per confezionare mascherine richiedono prima la correzione del confezionamento. È possibile annullare solo i carichi registrati da questo modulo: i conteggi pregressi inseriti direttamente in Airtable non hanno una singola registrazione annullabile nel gestionale.
