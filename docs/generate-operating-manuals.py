"""Generate all shipped manuals from the same content used in the application."""
from pathlib import Path
import json
from xml.sax.saxutils import escape
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.colors import HexColor
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.utils import ImageReader
ROOT=Path(__file__).resolve().parent
DATA=json.loads((ROOT/'manual-content.json').read_text())
pdfmetrics.registerFont(TTFont('Guide','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'))
pdfmetrics.registerFont(TTFont('GuideBold','/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'))
navy=HexColor('#203b78')
styles={
 'title':ParagraphStyle('title',fontName='GuideBold',fontSize=22,leading=28,textColor=navy,spaceAfter=18),
 'body':ParagraphStyle('body',fontName='Guide',fontSize=11,leading=16,spaceAfter=12),
 'meta':ParagraphStyle('meta',fontName='Guide',fontSize=10,leading=14,textColor=HexColor('#53637b'),spaceAfter=18)
}
def footer(c,doc):
 c.saveState();c.setStrokeColor(navy);c.line(42,52,553,52);c.setFont('Guide',9)
 c.drawString(42,36,'Ultimo aggiornamento: '+DATA['updated']);c.drawRightString(553,36,str(doc.page))
 c.drawImage(ImageReader(str(ROOT.parent/'mycroclean-logo.png')),42,787,width=130,height=31,preserveAspectRatio=True,mask='auto')
 c.restoreState()
sets={
 'guida-completa-gestionale.pdf':None,
 'guida-produzione-pianificazione.pdf':['accesso','entrata','telefono','lavaggio','asciugatura','cucito','qualita','piano'],
 'guida-capi-tag-sostituzioni.pdf':['scarto','tag'],
 'guida-report-amministrazione.pdf':['qualita','report','cucito']
}
for name,ids in sets.items():
 parts=[s for s in DATA['sections'] if ids is None or s['id'] in ids]
 story=[]
 for section in parts:
  if story:story.append(PageBreak())
  story.append(Paragraph(escape(section['title']),styles['title']))
  story.append(Paragraph('MYCROCLEAN NEXT · Versione '+DATA['version']+'<br/>Questa edizione sostituisce le precedenti istruzioni sullo stesso argomento.',styles['meta']))
  for i,step in enumerate(section['steps'],1):story.append(Paragraph(str(i)+'. '+escape(step),styles['body']))
 doc=SimpleDocTemplate(str(ROOT/name),pagesize=(595.28,841.89),leftMargin=42,rightMargin=42,topMargin=78,bottomMargin=68,title='Mycroclean Next - '+name,author='Mycroclean Italia')
 doc.build(story,onFirstPage=footer,onLaterPages=footer)
 print(name)
# Keep the checked-in browser copy in sync with the canonical content.
(ROOT.parent/'operating-guide.js').write_text('/* Generated from docs/manual-content.json. */\nwindow.operatingGuide='+json.dumps(DATA,ensure_ascii=False)+';\n')
