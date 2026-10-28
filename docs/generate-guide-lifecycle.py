from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, white
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'guida-capi-tag-sostituzioni.pdf'
pdfmetrics.registerFont(TTFont('Guide', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
pdfmetrics.registerFont(TTFont('GuideBold', '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'))
pdfmetrics.registerFontFamily('Guide', normal='Guide', bold='GuideBold')
NAVY=HexColor('#243C77'); PINK=HexColor('#CC217B'); INK=HexColor('#243047'); GREY=HexColor('#5A6477'); PALE=HexColor('#EFF3FA')
W,H=595.28,841.89
c=canvas.Canvas(str(OUT),pagesize=(W,H),pageCompression=1)
c.setTitle('Mycroclean - Capi, scarto, sostituzione e riuso tag - Guida operativa')
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
 c.setFont('Guide',9);c.setFillColor(GREY);c.drawRightString(W-44,H-41,'Versione 1.0 - 28/10/2026')
 y=H-76;text(title,24,NAVY,gap=8);text(subtitle,12,GREY,gap=18)
 c.setStrokeColor(HexColor('#D9E0ED'));c.line(44,39,W-44,39)
 c.setFont('Guide',9);c.drawString(44,25,'Capi, scarto, sostituzione e riuso tag');c.drawRightString(W-44,25,f'{n} / 6')

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

header(1,'Da dove cominciare','Prima pagina da leggere. Poi vai alla pagina che ti serve.')
box('Due cose diverse','<b>Capo</b> = il camice, pantalone o altro indumento.<br/><b>Tag</b> = l’etichetta con il codice. Il tag può passare a un altro capo; lo storico del vecchio capo resta.')
step(1,'Apri Capi e tag.','Sul telefono: premi <b>Altro</b>, poi <b>Capi e tag</b>.')
step(2,'Cerca il capo.','Nella ricerca inserisci il codice del tag oppure il nome dell’utilizzatore.')
step(3,'Controlla che sia quello giusto.','Confronta <b>codice, cliente, utilizzatore, tipo e taglia</b> con il capo che hai davanti.')
step(4,'Premi Scarta / Sostituisci.','Il comando si trova anche nel lotto. Nella scheda prodotto si chiama <b>Scarta / Sostituisci capo</b>.')
label('Che cosa devi fare?')
text('<b>Sostituire e tenere lo stesso tag</b>  →  pagina 2<br/><b>Usare un tag diverso oppure fare solo scarto</b>  →  pagina 3<br/><b>Controllare o recuperare tag</b>  →  pagina 4<br/><b>Risolvere un blocco</b>  →  pagina 5<br/><b>Impostare prezzi e addebiti (responsabile)</b>  →  pagina 6',12)
box('Se hai un dubbio, fermati','Non confermare sul capo sbagliato. Se non vedi il pulsante, chiedi al responsabile di controllare il permesso <b>Gestione prodotti</b>.')
end()

header(2,'Sostituire con lo stesso tag','Usa questa pagina solo se hai recuperato il tag del vecchio capo.')
step(1,'Scegli Scarta e sostituisci capo.','È la voce del campo <b>Operazione</b>.')
step(2,'Scegli il Motivo obbligatorio.','Indica il motivo reale. Se non sai quale scegliere, chiedi al responsabile.')
step(3,'Scegli il Capo sostitutivo.','Seleziona un capo proposto dalla <b>Scorta</b>. Oppure scegli <b>Registra un capo nuovo</b> solo se stai usando un capo nuovo.')
step(4,'Inserisci i dati forniti dal responsabile.','Compila <b>Listino del capo sostitutivo €</b> e <b>Fasce del sostituto</b>. Non inventare prezzi o percentuali.')
step(5,'Scegli Riusa lo stesso tag.','Nel campo <b>Tag del sostituto</b>, controlla il codice indicato. Il tag deve essere <b>termosaldato e cucito</b>, recuperato e idoneo al riuso.')
step(6,'Spunta la conferma del controllo.','Spunta la casella solo dopo avere recuperato e controllato davvero il tag.')
step(7,'Ricontrolla, poi premi Conferma una volta.','Aspetta il messaggio <b>Operazione registrata.</b> Prima di usare il nuovo capo, applica il tag secondo la procedura della lavanderia e verifica il codice.')
box('Risultato da controllare','Il vecchio capo risulta <b>Dismesso</b>. Il nuovo prende il suo posto e il tag ora identifica il nuovo capo. Utilizzatore, reparto e contratto vengono mantenuti.')
text('<b>Non usare questo percorso per Smarrimento o Mancato reso:</b> il tag del capo non recuperato non può essere riusato.',11,GREY)
end()

header(3,'Tag diverso o solo scarto','Scegli uno dei due percorsi. Non fare entrambi sullo stesso capo.')
label('A. Sostituisci, ma usa un altro tag')
step(1,'Compila i passaggi 1-4 della pagina 2.','Scegli operazione, motivo, capo sostitutivo e dati forniti dal responsabile.')
step(2,'Scegli il Tag del sostituto.','<b>Nuovo tag</b>: etichetta nuova.<br/><b>Tag libero verificato</b>: tag già controllato e segnato come <b>Libero</b> nel registro.')
step(3,'Inserisci il codice e conferma.','Scrivi o leggi il codice nel campo <b>Codice nuovo tag / tag libero</b>. Ricontrolla, premi <b>Conferma</b> e aspetta <b>Operazione registrata.</b>')
box('Prima della prossima scansione','Assicurati che sul capo sostitutivo ci sia proprio il tag registrato. Se recuperi il vecchio tag per usarlo in futuro, segui la pagina 4.')
label('B. Scarta senza mettere un altro capo')
step(1,'Scegli Solo scarto e dismissione.','Nel campo <b>Operazione</b>.')
step(2,'Scegli il Motivo obbligatorio.','Controlla un’ultima volta codice, cliente e utilizzatore.')
step(3,'Premi Conferma e aspetta il messaggio.','Il capo diventa <b>Dismesso</b>. Non viene creato un sostituto. Il vecchio capo resta nello storico.')
text('<b>Per sostituirlo in seguito:</b> apri <b>Storico</b> del capo e premi <b>Sostituisci capo dismesso</b>.',12)
text('<b>Non cancellare il vecchio prodotto</b> e non modificare a mano il barcode per trasferire il tag.',12,PINK)
end()

header(4,'Recuperare e riusare i tag','Un tag “Da verificare” non è ancora pronto per il riuso.')
label('Se devi staccare un tag ancora assegnato')
step(1,'Apri Capi e tag → Capi → Tag.','Controlla il codice del capo e quello del tag indicato.')
step(2,'Recupera il tag, poi conferma.','Spunta <b>Confermo il recupero fisico del tag</b> solo quando lo hai davvero recuperato. Premi <b>Conferma</b>. Il tag passa a <b>Da verificare</b>.')
label('Per renderlo disponibile')
step(3,'Apri Tag liberi / da verificare.','Trova il codice e premi <b>Controlla tag</b>. Controlla che il codice sia leggibile e il tag riutilizzabile.')
step(4,'Scegli l’Esito.','Se il tag termosaldato e cucito è recuperato e idoneo: <b>Idoneo: rendi libero</b>, spunta il controllo e premi <b>Conferma</b>.<br/>Se non è riutilizzabile: segui la procedura del responsabile e registra <b>Non idoneo: distrutto</b>.')
step(5,'Assegna il tag libero al capo giusto.','Durante una sostituzione scegli <b>Tag libero verificato</b> (pagina 3).<br/>Su un capo senza tag: premi <b>Tag</b>, scegli <b>Tag libero già verificato</b>, inserisci il <b>Codice tag</b> e conferma.')
box('Leggi sempre lo stato','<b>In uso</b>: appartiene già a un capo.<br/><b>Da verificare</b>: controllalo prima di usarlo.<br/><b>Libero</b>: è disponibile per l’assegnazione.<br/><b>Distrutto</b>: non si usa più.')
text('Un tag non trovato fisicamente non va segnato come recuperato o libero. Non scansionare in produzione un tag ancora senza capo associato.',11,GREY)
end()

header(5,'Se il programma ti ferma','Leggi il messaggio. Fai l’azione indicata, poi riprova.')
box('“Carrello non ancora completato”','Completa realmente lavaggio e asciugatura. Se il capo è <b>Da asciugare</b>, l’operatore abilitato usa <b>Carrelli da asciugare → Avvia asciugatura</b>, sceglie programma ed essiccatoio e attende la fine del ciclo. Poi riapri lo scarto.')
box('“Il capo ha un’attività avviata”','Completa l’attività reale prima di procedere. Se è bloccata, avvisa il responsabile. Non segnare come eseguito un lavoro non fatto.')
box('“Tag non disponibile” oppure “Codice già assegnato”','Non cambiare numeri a caso. Controlla il tag in <b>Tag liberi / da verificare</b>. Se appartiene a un altro capo, fermati e avvisa il responsabile.')
box('“Dati cambiati da un’altra postazione”','Chiudi la finestra con <b>Annulla</b>. Premi <b>Aggiorna</b> in Capi e tag e riapri il capo. Controlla lo stato prima di confermare di nuovo.')
box('Il caricamento non finisce','Nella schermata di errore premi <b>Riprova</b>. Se non basta, premi <b>Accedi di nuovo</b> e inserisci le tue credenziali. Se continua, avvisa il responsabile.')
label('Prima di passare al capo successivo')
text('1. Hai letto <b>Operazione registrata.</b>?<br/>2. Lo stato del vecchio capo è quello previsto?<br/>3. Il tag sul sostituto è quello registrato?<br/>4. Se c’è una proposta di addebito, l’hai segnalata al responsabile?',13)
text('Se non sai se un’operazione è riuscita, controlla <b>Storico</b> prima di ripeterla.',12,PINK)
end()

header(6,'Solo per il responsabile','L’operatore usa i valori che gli vengono forniti.')
label('1. Prepara fasce e dati del capo')
text('<b>Capi e tag → Fasce di ammortamento → Nuova tabella di ammortamento.</b> Inserisci nome, base (mesi o lavaggi) e percentuali. Parti da zero, senza buchi o sovrapposizioni. Lascia vuoto il limite finale dell’ultima fascia.',12)
text('Poi apri <b>Capi → Dati del capo</b>. Imposta stato, prezzo di listino, data effettiva di messa in servizio, lavaggi già presenti a quella data e tabella da congelare. Premi <b>Conferma</b>. Usa soltanto dati documentati.',12)
box('Nessun prezzo o ammortamento preimpostato','I dati della messa in servizio restano fissati nello storico. Una nuova versione delle fasce non modifica i capi già messi in servizio. Anche il sostituto richiede i propri dati; entra in servizio alla data della sostituzione.')
label('2. Controlla le proposte di addebito')
text('Apri <b>Addebiti da approvare</b>.<br/><b>Da completare</b>: premi <b>Completa dati</b> e inserisci i dati documentati.<br/><b>Da approvare</b>: controlla il calcolo, scegli <b>Approva</b> o <b>Respingi</b>, scrivi la nota e conferma.<br/><b>Esporta approvati CSV</b>: esporta soltanto le proposte approvate.',12)
text('Con le regole attuali: usura, fine vita per lavaggi, rottura e macchia permanente non generano addebiti. Danno improprio, smarrimento e mancato reso possono generare una proposta. <b>Il programma non emette una fattura.</b>',11)
label('3. Gestisci la fine del contratto')
text('Chiudi prima il contratto in <b>Noleggi e dotazioni</b>.<br/><b>Reso fine contratto</b>: il capo passa a <b>Da ricondizionare</b>. Solo dopo il lavoro e il controllo, premi <b>Ricondiziona</b>: torna in scorta usato.<br/><b>Riscatto</b>: usalo solo per il riscatto concordato. Produce una proposta da approvare; il tag resta con il capo riscattato.',12)
text('Lo storico viene conservato. I lavaggi già effettuati non vengono azzerati.',11,GREY)
end()
c.save()
print(OUT)
