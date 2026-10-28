# Pianificazione e macchinate

Le caselle nella modifica attività selezionano prodotti e dipendenze: non indicano il completamento. Il riepilogo mostra lo stato registrato all’apertura; i collegamenti si modificano nella sezione espandibile.

Le macchine con macchinate in corso o interrotte sono escluse dalla scelta programma/macchina. Tornano disponibili dopo la fine stimata registrata dal server o dopo l’annullamento dell’avvio. L’elenco si aggiorna senza ricaricare la pagina. Il server protegge anche da avvii concorrenti.

Per un avvio errato: fermare fisicamente la macchina, quindi scegliere **Ferma e riprendi le scansioni** e confermare. Il carrello conserva i prodotti e torna in preparazione (o pronto se pieno), senza incrementare i lavaggi. Il prossimo avvio usa tutta la durata del programma. Il comando richiede il permesso di eseguire produzione.

Solo gli amministratori possono usare **Elimina macchinata**. La macchinata errata viene eliminata; i prodotti restano nel lotto e sono trasferiti in un nuovo carrello, senza doverli riscansionare. L’operazione conserva un audit. Cicli già terminati o prodotti già lavorati/usciti non possono essere cancellati con questo comando.

**Segnala interruzione** resta distinto: sospende il ciclo per un problema e mantiene la macchina occupata. Il gestionale non controlla fisicamente le macchine.
