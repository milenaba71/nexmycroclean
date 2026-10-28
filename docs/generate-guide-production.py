from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, white
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'guida-produzione-pianificazione.pdf'
pdfmetrics.registerFont(TTFont('Guide', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
pdfmetrics.registerFont(TTFont('GuideBold', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'))
pdfmetrics.registerFontFamily('Guide', normal='Guide', bold='GuideBold')
NAVY=HexColor('#243C77'); PINK=HexColor('#CC217B'); INK=HexColor('#243047'); GREY=HexColor('#5A6477'); PALE=HexColor('#EFF3FA')
W,H=595.28,841.89
c=canvas.Canvas(str(OUT),pagesize=(W,H),pageCompression=1)
c.setTitle('Mycroclean - Produzione e pianificazione - Carrelli, macchinate e asciugatura')
c.setAuthor('Mycroclean')
y=0

def text(content, size=13, color=INK, x=44, width=507, gap=9):
 global y
 p=Paragraph(content,ParagraphStyle('p',fontName='Guide',fontSize=size,leading=size*1.32,textColor=color))
 _,height=p.wrap(width,900)
 if y-height<54: raise ValueError('Page overflow: '+content[:80])
 p.drawOn(c,x,y-height);y-=height+gap

def header(n,title,subtitle):
 global y
 c.setFillColor(NAVY);c.rect(0,H-10,W,10,fill=1,stroke=0)
 c.setFont('GuideBold',11);c.setFillColor(NAVY);c.drawString(44,H-41,'MYCROCLEAN  /  GUIDA OPERATIVA')
 c.setFont('Guide',9);c.setFillColor(GREY);c.drawRightString(W-44,H-41,'Versione 2.0 - 28/10/2026')
 y=H-76;text(title,24,NAVY,gap=8);text(subtitle,12,GREY,gap=18)
 c.setStrokeColor(HexColor('#D9E0ED'));c.line(44,39,W-44,39)
 c.setFont('Guide',9);c.drawString(44,25,'Produzione e pianificazione');c.drawRightString(W-44,25,f'{n} / 11')

def label(s):
 global y
 y-=4;text(s,15,NAVY,gap=10)

def step(n,title,body=''):
 global y
 c.setFillColor(PINK);c.circle(56,y-11,11,fill=1,stroke=0)
 c.setFont('GuideBold',11);c.setFillColor(white);c.drawCentredString(56,y-15,str(n))
 text('<b>'+title+'</b>'+('<br/>'+body if body else ''),13,x=78,width=473,gap=12)

def box(title,body):
 global y
 style=ParagraphStyle('box',fontName='Guide',fontSize=12,leading=17,textColor=INK)
 p=Paragraph('<b>'+title+'</b><br/>'+body,style);_,h=p.wrap(475,600)
 if y-h-28<54:raise ValueError('Box overflow '+title)
 c.setFillColor(PALE);c.roundRect(44,y-h-24,507,h+24,8,fill=1,stroke=0);p.drawOn(c,60,y-h-12);y-=h+39

def end():c.showPage()

header(1,'Produzione e pianificazione','Guida aggiornata: persone, carrelli, lavaggio, asciugatura e uscita.')
box('Prima configura le persone. Poi assegna il lavoro.','Il responsabile verifica <b>ruoli e permessi</b>, <b>postazioni abilitate</b>, <b>turni e pause</b>. Solo dopo prepara le attività e distribuisce il piano.')
label('Responsabile: leggi in questo ordine')
text('<b>Pagina 2</b> - Ruoli e permessi degli account.<br/><b>Pagina 3</b> - Abilità, turni, pause e assenze.<br/><b>Pagina 4</b> - Programmi, macchine ed essiccatoi.<br/><b>Pagina 5</b> - Arrivi, consegne e assegnazione del lavoro.',13)
label('Operatore: segui il lavoro reale')
text('<b>Pagina 6</b> - Leggere Il mio lavoro e usare il timer personale.<br/><b>Pagina 7</b> - Scansionare e riempire il carrello.<br/><b>Pagina 8</b> - Caricare la macchina e avviare la macchinata.<br/><b>Pagina 9</b> - Avviare l’asciugatura quando serve.<br/><b>Pagina 10</b> - Piegare e registrare l’uscita.<br/><b>Pagina 11</b> - Interruzioni, errori e cambi di operatore.',13)
box('Il percorso normale','<b>Lavaggio ad acqua:</b> entrata → carrello → lavaggio → asciugatura → piegatura → uscita.<br/><br/><b>Lavaggio e decontaminazione / lavaggio a secco:</b> entrata → carrello → ciclo unico → piegatura → uscita. È il comportamento attuale del gestionale.')
text('Ogni persona usa il proprio account. Sul telefono apri <b>Altro → Produzione</b>. Questa versione sostituisce la precedente guida 1.2.',12,GREY)
end()

header(2,'1. Assegna ruoli e permessi','SUPER AMMINISTRATORE - Da fare prima della pianificazione.')
step(1,'Apri Utenti e ruoli.','Controlla che ogni persona abbia il proprio account attivo. Se manca, usa <b>Nuovo utente</b>.')
step(2,'Apri Ruolo e permessi della persona.','Solo il <b>Super amministratore</b> può modificare queste impostazioni.')
step(3,'Scegli il Profilo.','Seleziona il profilo previsto: <b>Amministratore</b>, <b>Operatore</b>, <b>Operatore base</b> oppure <b>Sola lettura</b>.')
step(4,'Controlla le caselle una per una.','Per chi registra entrata, piegatura e uscita: <b>Lotti: scansioni, note, segnalazioni e riparazioni</b>.<br/>Per chi esegue produzione e avvia i cicli: <b>Eseguire attività assegnate e avviare macchinate</b>.')
step(5,'Abilita il responsabile alla pianificazione.','La casella è <b>Pianificare e gestire operatori, turni, macchine e programmi</b>. Assegna gli altri permessi solo se necessari al suo lavoro.')
step(6,'Premi Salva permessi.','Ripeti il controllo per tutte le persone che devono lavorare nel gestionale.')
box('Non basta scegliere “Operatore”','<b>Profilo</b> = ruolo dell’account.<br/><b>Permessi</b> = operazioni consentite nel programma.<br/><b>Postazioni abilitate</b> = lavori che la persona può svolgere. Si impostano nella pagina successiva.')
text('Cambiare profilo può conservare le selezioni compatibili: controlla sempre le caselle prima di salvare.',12,PINK)
end()

header(3,'2. Registra abilità e turni','RESPONSABILE - Una scheda completa per ogni operatore.')
step(1,'Apri Produzione → Operatori e turni.','Premi <b>Associa operatore</b>. Se la persona è già presente, premi <b>Modifica turno</b>.')
step(2,'Scegli Account operatore e Postazione abituale.','La postazione abituale indica dove lavora normalmente. Deve essere compresa anche tra le postazioni abilitate.')
step(3,'Spunta tutte le sue Postazioni abilitate.','Seleziona <b>tutte e soltanto</b> le postazioni per cui la persona è formata e autorizzata. Non spuntare tutto automaticamente.')
step(4,'Controlla chi deve avviare l’asciugatura.','Deve avere il permesso di esecuzione produzione e l’abilitazione alla <b>postazione indicata nel programma di asciugatura</b>. Assegnargli un’attività non sostituisce l’abilitazione.')
step(5,'Compila giorni, orari e pause.','Imposta <b>Inizio turno</b>, <b>Fine turno</b> e <b>Giorni lavorativi</b>. Inserisci inizio e minuti delle pause; usa <b>0 minuti</b> per una pausa non prevista. Controlla <b>Disponibilità: Attivo</b>, poi premi <b>Salva</b>.')
box('Esempio di abilitazione','Una persona formata per entrata e lavaggio ad acqua riceve queste abilitazioni. Se non è formata per le riparazioni, la relativa casella resta vuota. I nomi delle postazioni possono essere personalizzati.')
text('<b>Assenze o cambio postazione:</b> usa <b>Variazione / assenza</b>. La variazione sostituisce l’intero turno di quel giorno: inserisci tutte le fasce lavorate, escludendo le pause. Poi ricalcola il piano.',12)
end()

header(4,'3. Prepara programmi e macchine','RESPONSABILE - Verifica i dati reali prima di distribuire il lavoro.')
step(1,'Apri Produzione → Programmi e macchine.','Usa <b>Nuovo programma</b> o <b>Modifica programma</b>.')
step(2,'Controlla ogni programma di lavaggio.','Imposta nome, <b>Postazione</b>, tipo macchina, <b>Valore / durata standard</b> e <b>Minuti operatore per ciclo</b>. La durata del ciclo e il tempo di lavoro della persona sono due valori diversi.')
step(3,'Prepara il programma di asciugatura.','Scegli il tipo macchina <b>Asciugatura</b>, la durata e la postazione incaricata. Per il flusso ad acqua verifica il collegamento con la postazione lavaggio ad acqua e le abilitazioni degli operatori.')
step(4,'Configura ogni macchina e ogni essiccatoio.','Usa <b>Nuova macchina</b> o <b>Modifica macchina</b>. Inserisci tipo, <b>Capacità massima · indumenti</b>, orari di disponibilità e stato <b>Attiva</b>.')
step(5,'Controlla le lavorazioni manuali.','In <b>Tempi lavorazioni</b> verifica postazione e tempi di piegatura, riparazione e uscita. Non inventare tempi: completa quelli mancanti prima del piano.')
box('Tre controlli essenziali','<b>Capacità</b> = della singola macchina, in capi.<br/><b>Durata</b> = del programma, in minuti.<br/><b>Abilitazione</b> = alla postazione del programma.')
text('Una macchina occupata o con guasto bloccante non può avviare un nuovo ciclo. La capacità impostata non sostituisce le istruzioni fisiche di carico della macchina.',12,GREY)
end()

header(5,'4. Distribuisci il lavoro','RESPONSABILE - Solo dopo avere completato persone e macchine.')
step(1,'Controlla Arrivi e consegne.','Usa <b>Appuntamento singolo</b> oppure <b>Nuovo programma fisso</b>. Verifica cliente, reparto, arrivo dello sporco e riconsegna del pulito. Collega o apri il lotto all’arrivo effettivo.')
step(2,'Apri Pianificazione.','Imposta <b>Dal giorno</b>. Per il lotto premi <b>Prepara percorso di un lotto</b>. Scegli solo le fasi necessarie e la data di consegna.')
step(3,'Prevedi l’asciugatura solo dove serve.','Per il percorso ad acqua inserisci il programma di asciugatura. Con le impostazioni attuali, decontaminazione e lavaggio a secco passano direttamente alla piegatura.')
step(4,'Controlla attività, prodotti e operatore.','Per lavori aggiuntivi usa <b>Nuova attività</b>. Lascia l’assegnazione automatica oppure scegli una persona abilitata. Non creare due volte lo stesso lavoro.')
step(5,'Premi Distribuisci automaticamente · 7 giorni.','Controlla <b>Carichi operatori</b>, attività non pianificate e avvisi di ritardo. Se mancano abilità, turni o tempi, correggili e distribuisci di nuovo.')
step(6,'Verifica il lavoro di ogni persona.','Il responsabile usa <b>Attività operatori</b>. L’operatore vede le assegnazioni in <b>Il mio lavoro</b>.')
box('Il piano non avvia la macchina','Creare un’attività o assegnarla non fa partire il ciclo. L’operatore deve usare <b>Avvia macchinata</b> e, quando serve, <b>Avvia asciugatura</b>, al momento dell’avvio reale.')
text('Le caselle dei prodotti e delle fasi precedenti servono a pianificare: <b>non segnano il lavoro come completato</b>.',12,PINK)
end()

header(6,'Il mio lavoro: che cosa fare','OPERATORE - Leggi la scheda prima di iniziare.')
step(1,'Apri Produzione → Il mio lavoro.','Controlla <b>fase</b>, <b>lotto e cliente</b>, <b>Assegnata a</b>, orario e consegna. Leggi anche eventuali note.')
step(2,'Leggi Stato operativo.','Se compare <b>Attende</b>, la fase precedente non è finita. Se compare <b>Da pianificare</b> o <b>Piano da aggiornare</b>, avvisa il responsabile.')
step(3,'Per un’attività manuale, premi Inizia attività.','Fallo quando cominci davvero. Durante un’interruzione premi <b>Pausa</b>. Quando torni al lavoro premi <b>Riprendi attività</b>.')
step(4,'Registra anche i prodotti nel lotto.','Apri il lotto dalla scheda. La piegatura si registra scansionando in <b>02 Lavorazione</b>; la consegna in <b>03 Uscita</b>. Il timer personale non sostituisce queste scansioni.')
step(5,'Premi Completa attività solo a lavoro finito.','Non completare un lavoro che deve ancora essere eseguito. Se devi passarlo a un collega, avvisa il responsabile.')
box('Per lavaggio e asciugatura','Usa i pulsanti del <b>carrello</b> descritti nelle pagine 8 e 9. <b>Inizia attività</b> non sostituisce l’avvio del ciclo. Se utilizzi anche il timer personale, registra solo il lavoro effettivo e mettilo in pausa durante il funzionamento autonomo della macchina.')
text('Le attività di lavaggio e asciugatura non avviate nel timer personale si chiudono automaticamente quando tutti i capi collegati hanno concluso il ciclo previsto. Non registrare un secondo ciclo per chiuderle.',12)
end()

header(7,'Entrata: riempi il carrello','OPERATORE - Ogni scansione registra un capo nel lotto e nel carrello.')
step(1,'Apri il lotto giusto in Lotti.','Controlla cliente e numero del lotto. Entra in <b>01 Entrata</b>.')
step(2,'Scegli Lavaggio e macchina.','Seleziona il programma indicato dal responsabile e la macchina compatibile. Non scegliere solo in base al nome della persona o del cliente.')
step(3,'Controlla il capo e scansiona il tag.','Metti il capo nel carrello corretto. Verifica la registrazione sullo schermo. Se compare un errore, fermati e leggilo prima di continuare.')
step(4,'Guarda il numero di capi nel carrello.','Il carrello contiene capi dello <b>stesso lotto e dello stesso programma</b>. Al raggiungimento della capacità compare <b>Il tuo carrello è pronto</b>.')
step(5,'Scegli se avviare o continuare a scansionare.','Se devi preparare altri capi, premi <b>Continua le scansioni</b>: il carrello successivo riparte da zero. Se devi caricare la macchina, segui la pagina 8.')
step(6,'Se hai finito prima di riempirlo, termina l’entrata.','Premi <b>Termina controllo in entrata</b>. Anche passando a un altro lotto, il carrello parziale precedente diventa pronto.')
box('Carrello pronto non significa macchina avviata','Puoi avere carrelli pronti <b>In coda</b> mentre la macchina è occupata. Attendi che si liberi. Terminare il controllo in entrata <b>non chiude il lotto</b> e non registra una consegna.')
end()

header(8,'Lavaggio: avvia la macchinata','OPERATORE - Premi l’avvio nel gestionale quando parte la macchina reale.')
step(1,'Trova il carrello da lavare.','Nel lotto apri <b>Carrelli e macchinate</b>. I carrelli sono visibili anche in Produzione. Controlla lotto, programma e quantità.')
step(2,'Carica la macchina corretta.','Rispetta la procedura di carico della lavanderia. Verifica che la macchina sia libera e adatta al programma.')
step(3,'Premi Avvia macchinata.','Per un carrello non pieno il pulsante è <b>Avvia macchinata parziale</b>. Nel messaggio di carrello pronto può comparire <b>Carica e avvia macchinata</b>.')
step(4,'Controlla la Macchina nella finestra.','Seleziona quella che stai usando realmente. Deve avere capacità sufficiente. Alla partenza reale premi <b>Avvia macchinata</b> nella finestra.')
step(5,'Verifica che il ciclo sia in corso.','Il gestionale mostra il tempo e la fine prevista. Se la macchina si interrompe, premi subito <b>Segnala interruzione</b> (pagina 11).')
step(6,'Alla fine prevista controlla la macchina reale.','Per il lavaggio ad acqua i capi diventano <b>Da asciugare</b>: vai a pagina 9. Per decontaminazione e lavaggio a secco passa alla piegatura, dopo il controllo reale del ciclo.')
box('Il timer è una previsione','Il gestionale <b>non riceve un segnale dalla macchina</b>. La fine viene calcolata dalla durata del programma. Il conteggio del lavaggio avviene una sola volta; non avviare un altro ciclo solo per registrare la fine.')
end()

header(9,'Acqua: avvia l’asciugatura','OPERATORE ABILITATO - Prima dell’asciugatura la piegatura è bloccata.')
step(1,'Verifica lo stato Da asciugare.','Il carrello ad acqua ha finito il lavaggio previsto. Controlla che il ciclo fisico sia davvero terminato.')
step(2,'Apri il carrello da asciugare.','In Produzione cerca <b>Carrelli da asciugare · postazione lavaggio ad acqua</b> in Pianificazione, Il mio lavoro o Macchine. Nel lotto cerca <b>Asciugatura dopo il lavaggio ad acqua</b>.')
step(3,'Premi Avvia asciugatura.','Scegli il <b>Programma di asciugatura</b> previsto e un <b>Essiccatoio</b> libero con capacità sufficiente.')
step(4,'Carica e avvia l’essiccatoio reale.','Segui la procedura della lavanderia. Quando parte, premi <b>Avvia asciugatura</b> nella finestra del gestionale.')
step(5,'Controlla In asciugatura e la fine prevista.','Se il ciclo si ferma, premi <b>Segnala interruzione</b>. Non lasciare scorrere il conteggio come se il ciclo proseguisse.')
step(6,'Alla fine prevista passa alla piegatura.','Dopo il controllo reale dell’asciugatura, lo stato atteso è <b>Da lavorare · Piegatura</b>. Apri il lotto e segui la pagina 10.')
box('Non vedi il pulsante?','Se leggi <b>Avvio riservato agli operatori abilitati a…</b>, chiama il responsabile. Deve verificare permesso di esecuzione produzione e abilitazione alla postazione del programma. Se non ci sono essiccatoi liberi e capienti, attendi: non scegliere una macchina inadatta.')
end()

header(10,'Piegatura e uscita','OPERATORE - La fine del timer non piega e non consegna i capi.')
step(1,'Apri il lotto e controlla lo stato.','Procedi quando i capi sono <b>Da lavorare · Piegatura</b>. Se sono <b>Da asciugare</b>, <b>In asciugatura</b> o con ciclo interrotto, torna alla fase precedente.')
step(2,'Controlla le segnalazioni aperte.','Riparazione, etichettatura, verifica o rilavaggio devono essere risolti prima di registrare il capo pronto. Non togliere una segnalazione solo per superare il blocco.')
step(3,'Apri 02 Lavorazione.','Piega il capo e <b>scansiona il barcode</b>. La scansione registra la piegatura con data, ora e operatore. Non occorre premere un altro pulsante Registra.')
step(4,'Verifica Pronto per l’uscita.','Ripeti il lavoro per gli altri capi. Se il programma segnala un blocco, leggi il messaggio e risolvilo prima di continuare.')
step(5,'Quando registri la riconsegna, apri 03 Uscita.','Scansiona soltanto i capi già pronti. Controlla l’esito: il capo passa a <b>Uscito</b>. L’uscita non aggiunge un altro lavaggio.')
box('Controllo prima di chiudere il lavoro','Cliente e lotto sono corretti?<br/>I capi hanno finito tutti i cicli necessari?<br/>Le segnalazioni aperte sono state risolte?<br/>Piegatura e uscita sono registrate nelle rispettive fasi?')
text('Per scarto, sostituzione e riuso del tag usa l’altra guida in <b>Istruzioni → Capi, scarto, sostituzione e riuso tag</b>.',12,GREY)
end()

header(11,'Interruzioni e problemi','Usa il comando adatto al problema. Se hai dubbi, chiama il responsabile.')
box('Il ciclo si interrompe davvero','Premi <b>Segnala interruzione</b>. La conclusione automatica viene sospesa. Per ripartire usa <b>Riavvia ciclo completo</b> nel lavaggio oppure <b>Riavvia asciugatura</b>. Riparte l’intera durata del programma: verifica con il responsabile prima del riavvio.')
box('Hai registrato un avvio per errore','Prima ferma la macchina fisica dalla pulsantiera, secondo procedura.<br/><b>Lavaggio:</b> usa <b>Ferma e riprendi le scansioni</b>, poi <b>Conferma · macchina ferma</b>.<br/><b>Asciugatura:</b> usa <b>Annulla avvio</b>, poi <b>Conferma · essiccatoio fermo</b>. Il carrello torna <b>Da asciugare</b>.')
box('Macchina guasta o occupata','Non forzare l’avvio. Segnala al responsabile. Chi ha il permesso registra il problema in <b>Guasti e ticket</b>. Un guasto bloccante esclude la macchina; dopo la verifica e la risoluzione, il responsabile ricalcola il piano.')
box('Un collega deve continuare un’attività manuale','Metti l’attività in <b>Pausa</b>. Il responsabile usa <b>Passa a un collega</b>, sceglie una persona abilitata, indica i minuti residui e il motivo, poi ricalcola il piano. I tempi già registrati restano al primo operatore.')
box('Non hai attività oppure il pulsante non compare','Il responsabile controlla: account attivo, permessi, postazioni abilitate, turno completo, programma attivo, fasi precedenti e piano aggiornato. <b>Non cambiare account con quello di un collega.</b>')
text('<b>Ricorda:</b> i pulsanti del gestionale registrano gli eventi. Non comandano fisicamente lavatrici o essiccatoi. Non segnare come concluso un lavoro che non è stato eseguito.',12,PINK)
end()
c.save()
print(OUT)
