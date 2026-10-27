# Macchinate dal controllo in entrata

1. In Lotti aprire il lotto e scegliere **Lavaggio e macchina**. La voce unisce un programma della produzione e una macchina compatibile.
2. Scansionare i prodotti. Ogni prodotto viene registrato una volta nel lotto e nel carrello, nella stessa transazione.
3. Alla capacità impostata compare **Il tuo carrello è pronto**. Si può continuare a scansionare: il carrello successivo riparte da zero.
4. Quando si carica realmente la macchina, premere **Avvia macchinata**. Si può scegliere un'altra macchina compatibile con capacità sufficiente. Una macchina occupata o con un ticket bloccante non può partire.
5. Passando a un altro lotto, il carrello parziale precedente diventa pronto. È disponibile anche **Termina controllo in entrata**. Il lotto resta aperto fino alla riconsegna: termina solo il controllo in entrata.
6. Il timer usa la durata del programma al momento dell'avvio, conservandola nello storico. Alla scadenza compare **Ciclo previsto terminato · pronto per scarico**. Il lavaggio viene contabilizzato una volta; non servono conferme separate di completamento.
7. Se il ciclo si interrompe, premere **Segnala interruzione** o aprire un ticket bloccante sulla macchina. La conclusione automatica si sospende. Riavviando si applica l'intera durata del programma, indicata nella finestra.

## Configurazione amministratore

- **Produzione → Macchine**: capacità in capi, tipo e nome. La capacità non viene presunta uguale per tutte le lavatrici.
- **Produzione → Tempi lavorazioni**: programma macchina, durata del ciclo in minuti e tipo macchina.
- **Lotto → Configura collegamenti**: associare il programma alla lavorazione di entrata. I programmi con lo stesso nome univoco della lavorazione sono collegati inizialmente; gli altri richiedono una scelta esplicita.
- Le opzioni prive di capacità o durata riportano l'informazione da completare. Il ciclo non può partire senza durata valida.

## Significato della fine prevista

Non è un segnale proveniente dal PLC della macchina. È una stima basata su un avvio confermato dall'operatore e sulla durata configurata. La procedura deve includere la segnalazione tempestiva delle interruzioni. La registrazione conserva `program_estimate` come origine e non inventa minuti effettivi di lavoro dell'operatore.

Il controllo sul server passa ogni minuto e viene richiamato anche all'apertura del gestionale. La riconciliazione delle attività riguarda solo lavaggi non avviati nel vecchio timer e interamente coperti dalle nuove macchinate. Riparazioni, asciugatura, piegatura e uscita mantengono le proprie registrazioni. Nessun lotto storico viene automaticamente migrato a carrelli.
