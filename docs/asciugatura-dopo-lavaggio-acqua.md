# Asciugatura dopo il lavaggio ad acqua

1. **Entrata e controllo:** scegli il programma ad acqua e la lavatrice, scansiona i prodotti e premi **Avvia macchinata**.
2. Alla fine del tempo previsto i capi del carrello diventano **Da asciugare**. La piegatura resta bloccata.
3. **Postazione lavaggio ad acqua:** in Produzione (Pianificazione, Il mio lavoro, Macchine) e nel lotto compare **Carrelli da asciugare**. L'operatore abilitato preme **Avvia asciugatura**, sceglie il programma e un essiccatoio libero con capacità sufficiente.
4. I capi passano a **In asciugatura**. Alla fine prevista diventano **Da lavorare · Piegatura**: in **02 Lavorazione** si piega e si scansiona, come prima.
5. Se l'essiccatoio si ferma: **Segnala interruzione**, poi **Riavvia asciugatura** con l'intera durata. **Annulla avvio** riporta il carrello a Da asciugare.

**Lavaggio e decontaminazione** e **lavaggio a secco** sono cicli unici: il carrello passa direttamente alla piegatura, senza asciugatura.

## Chi può avviare l'asciugatura

- Permesso **Esecuzione produzione** (`production_execute`).
- Abilitazione alla postazione del programma di asciugatura, in Produzione → Operatori e turni → Postazioni abilitate. Gli amministratori possono sempre avviare.
- In Il mio lavoro, un'attività di asciugatura assegnata mostra il tasto per i carrelli dei suoi prodotti. Alla fine prevista l'attività non avviata viene chiusa automaticamente, come per i lavaggi.

## Configurazione amministratore

- **Programmi e macchine:** un programma con tipo macchina **Asciugatura**, la durata del ciclo e la postazione lavaggio ad acqua.
- **Macchine:** gli essiccatoi con tipo Asciugatura e capacità in capi.

## Installazione

Eseguire `sql/dryer_phase.sql` dopo `wash_batch_corrections.sql`. Riguarda solo i carrelli ad acqua avviati dopo l'installazione; quelli già avviati o terminati restano come sono. Test: `node tests/dryer-phase.cjs`.
