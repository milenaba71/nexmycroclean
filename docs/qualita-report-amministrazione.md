# Controllo qualità e report amministrazione

## Operatore: controllare il lotto
1. Apri il lotto, anche dalla vista reparto. Premi **Controllo qualità**.
2. Nei nuovi lotti il controllo è obbligatorio prima dell'uscita. Nei lotti preesistenti premi **Attiva controllo qualità** se vuoi applicarlo.
3. Completa lavorazione, eventuale asciugatura, piegatura e interventi dei capi da consegnare.
4. Controlla pulizia, asciugatura, integrità, identificazione e confezionamento. Non applicabile è disponibile solo per asciugatura e confezionamento.
5. Inserisci il numero di capi effettivamente controllati. La scheda dichiara la numerosità del controllo, non impone un piano di campionamento.
6. Scegli **Conforme** per autorizzare i capi pronti presenti al momento del controllo. Un nuovo capo o una modifica al capo richiede un nuovo controllo. La consegna parziale resta possibile per i capi autorizzati.
7. Scegli **Non conforme** e scrivi il problema per bloccare le nuove uscite del lotto. Segnala nel lotto i capi che richiedono riparazione, rilavaggio o verifica: il controllo qualità non inventa né chiude questi interventi.
8. Dopo la risoluzione registra un nuovo controllo. I precedenti restano conservati con data e operatore.

La registrazione richiede il permesso **Lotti: scansioni, note, segnalazioni e riparazioni**. La consultazione resta disponibile agli utenti abilitati al gestionale. Nessuna scheda costituisce una certificazione microbiologica o particellare: indicare eventualmente il riferimento al rapporto di prova esterno.

## Ufficio: stampare il report
1. Apri un lotto attivo o in Archivio.
2. Premi **Report amministrazione / PDF**.
3. Controlla il riepilogo: quantità per tipo/taglia/reparto, lavorazioni, interventi con minuti e importi registrati, controlli qualità, elenco capi, mancanti e registro operazioni.
4. Premi **Stampa / Salva come PDF**. Nella finestra del browser scegli **Salva come PDF**, oppure la stampante.

Il report rilegge i dati salvati su Supabase. Un lotto non completamente riconsegnato è indicato come parziale. I capi dismessi sono separati dai mancanti. Gli importi comprendono soltanto i consuntivi a pezzi registrati; gli interventi a minuti e gli altri servizi devono essere valorizzati dall'amministrazione. Fatture e DDT restano nel gestionale esterno. Conservare i PDF consegnati per fissare il consuntivo del momento.

## Responsabile: abilitare Reparto Acqua
In **Produzione → Operatori e turni**, abilita la persona alla postazione **Reparto Acqua**. In **Utenti → Ruolo e permessi**, il Super amministratore verifica anche **Eseguire attività assegnate e avviare macchinate**.
I programmi di lavaggio ad acqua e asciugatura sono associati alla medesima postazione. L'operatore abilitato può avviare entrambi, rispettando disponibilità, capienza e durata configurata. Il comando registra l'avvio nel gestionale: la macchina fisica va avviata dall'operatore.

## Report reparto cucito per lotto
Apri il lotto e premi **Report reparto cucito / PDF** (ufficio o vista reparto). Premi **Stampa / Salva come PDF**. Il report riporta cliente e lotto, tag, indumento, taglia, utilizzatore, reparto, interventi registrati, quantità, minuti, importi a pezzi, operatore, data e note. Le segnalazioni ancora aperte sono separate. Gli interventi a minuti restano da valorizzare; il documento non è una fattura.

Il reparto cucito comprende riparazioni, etichettature, verifiche, sostituzioni e scarti da verificare. Il report separa gli interventi registrati con tempi/importi, le sostituzioni e dismissioni del lotto, le richieste ancora aperte e il registro delle attività (incluse quelle senza consuntivo).

## Avvio diretto dal lotto
Dopo le scansioni, premi **Avvia macchinata** (oppure **Avvia macchinata parziale**) sul carrello: il timer parte sulla macchina indicata, senza premere Termina controllo e senza una seconda conferma. Premi quando avvii realmente la macchina. Per cambiare macchina usa **Scegli un’altra macchina**. Permessi, abilità Reparto Acqua, capienza, durata, guasti e macchina occupata restano controllati. Un errore lascia il carrello disponibile per riprovare.
