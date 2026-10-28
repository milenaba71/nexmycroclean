# Prodotti fermi

In **Mancanti e resi**, selezionare **Prodotti fermi · 60 giorni**. La tabella mostra ultima uscita e giorni senza rientro; sono disponibili ricerca, filtro cliente ed esportazioni della vista.

Solo un prodotto con gestione **Noleggio** è classificato come fermo dal sessantesimo giorno di calendario dall’ultima uscita registrata, secondo la data italiana, se non risulta un successivo ingresso o una presenza in un lotto non ancora uscito, anche archiviato. Le modifiche alle note e alle anagrafiche non azzerano il conteggio. Un nuovo ingresso rimuove automaticamente la segnalazione.

Il calcolo usa lo storico dei movimenti del prodotto; in assenza di movimenti nello storico usa gli eventi dei lotti. La data di creazione o di ingresso del lotto non viene utilizzata come data di uscita. Prodotti di proprietà del cliente, con proprietà da definire, mai usciti o senza una data di uscita verificabile non vengono classificati come fermi.

**Fermo** è una segnalazione automatica, distinta dai mancanti segnalati manualmente e dai resi definitivi. Non imposta SMARRITO, non blocca le scansioni e non sottrae automaticamente il prodotto dalla dotazione disponibile. Mancanti manuali e resi mantengono il proprio stato.

Non servono modifiche al database: il risultato è calcolato dai movimenti condivisi, all’apertura e aggiornamento della sezione.
