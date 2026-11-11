# Tempi produttivi e fermi macchina

Aprire Dashboard → Tempi produttivi e fermi macchina, oppure Produzione → Tempi e fermi macchina. Il logo e i permessi sono quelli del gestionale.

## Uso
- Definire gli standard in Produzione → Lavorazioni; i prezzi delle riparazioni non partecipano ai calcoli.
- Usare Inizia, Pausa e Completa sulle attività. Lo standard viene salvato al primo avvio e resta immutabile anche se il listino delle lavorazioni cambia.
- Aprire o aggiornare il ticket indicando Macchina ferma quando il guasto blocca la macchina; indicare Macchina utilizzabile quando riparte. La chiusura termina il fermo.
- Selezionare mese, cliente, lotto e lavorazione per i tempi; macchina per i guasti. Esportazione CSV disponibile.

## Definizioni
Il confronto comprende le attività completate nel mese e confronta il loro standard con tutti i minuti dei timer personali chiusi. Le pause esplicitamente registrate sono escluse. Più operatori sommano minuti-persona; i tempi autonomi di macchina non sono minuti-persona. Un fermo non mette automaticamente in pausa i timer: usare Pausa.

I ticket nuovi sono contati per mese di apertura. I fermi sono intervalli documentati di indisponibilità, uniti per macchina per evitare duplicati; le ore comprendono solo la porzione del mese selezionato, anche fuori turno. I fermi iniziati prima del mese sono distinti dai nuovi. I timer ancora attivi non entrano nel consuntivo. Gli indicatori aperti/fermi oggi descrivono lo stato corrente.

Le attività senza standard storico o timer sono escluse dal confronto e segnalate. Lo storico dei ticket precedenti all’aggiornamento non consente di ricostruire tutte le ore perse: nessuna durata viene inventata. I filtri lotto/cliente includono l’intera attività se coinvolge più lotti, senza ripartizioni arbitrarie.

## Verifica tecnica
Eseguire `node tests/production-analytics.cjs`. Per la migrazione usare `node tests/production-analytics-db.cjs` con @electric-sql/pglite installato o PGLITE_PATH impostato. I fixture contengono esclusivamente definizioni SQL precedenti alla migrazione; i test creano dati sintetici in memoria.
La migrazione `sql/production-analytics.sql` aggiorna solo funzioni private esistenti, preservando autorizzazioni, revisioni e RLS, senza nuovi grant o API pubbliche.
