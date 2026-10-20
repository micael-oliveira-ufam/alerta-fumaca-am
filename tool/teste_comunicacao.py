#!/usr/bin/env python3
"""Teste de comunicação app -> servidor: reproduz o JSON que o app envia (ver
`buildAnswerPayload` em lib/services/api_client.dart) e confere as respostas HTTP.

    python3 tool/teste_comunicacao.py [URL_BASE]     # padrão: http://127.0.0.1:8000

ATENÇÃO: grava ~11 respostas FICTÍCIAS (app_version "teste-comunicacao"). Use banco de
desenvolvimento. Requer `pip install requests`. O limite de envios (RATE_LIMIT_PER_MIN) pode
devolver 429 se rodar várias vezes seguidas.
"""
import sys, uuid, datetime as dt, random
import requests
B=(sys.argv[1] if len(sys.argv)>1 else 'http://127.0.0.1:8000').rstrip('/'); s=requests.Session()
SINT='cough throat nose wheeze dyspnea eyes chest palpitation headache dizzy fatigue'.split()
def payload(lat=-3.1234, lon=-60.0212, ctx=True):
    now=dt.datetime.now(dt.timezone.utc)
    p={'submission_id':str(uuid.uuid4()),
       'registrado_em':now.strftime('%Y-%m-%dT%H:%M:%S.%f')+'Z',   # formato do toIso8601String do Dart
       'nivel':random.choice(['low','moderate','high','emergency']),'pontos':random.randint(0,30),
       'exposicao':random.choice(['under1h','between1and4h','over4h']),
       'perfil':{'idoso':False,'gestante':False,'crianca':random.random()<.3,'doenca_respiratoria':False,'doenca_cardiaca':False},
       'sintomas':{k:random.randint(0,3) for k in SINT},'app_version':'teste-comunicacao'}
    if lat is not None: p['lat']=round(lat,2); p['lon']=round(lon,2)
    if ctx: p['contexto']={'local':'casa_janelas_fechadas','fumaca_visivel':True,'mascara':'nao_saiu','piorando':False}
    return p
r=lambda *a,**k: s.post(B+'/respostas',timeout=10,*a,**k)
print('health',s.get(B+'/health').status_code, s.get(B+'/health').text[:80])
p=payload(); a=r(json=p); print('novo',a.status_code,a.text[:80])
b=r(json=p); print('reenvio',b.status_code,b.text[:80])
print('sem localização',r(json=payload(lat=None,ctx=False)).status_code)
bad=payload(); bad['nivel']='xyz'; print('inválido (espera 4xx não-429)',r(json=bad).status_code)
bad=payload(); del bad['sintomas']; print('sem sintomas',r(json=bad).status_code)
for i in range(8): assert r(json=payload()).status_code==201
d=s.get(B+'/publico/painel?dias=30').json()
print('painel: total',d['total_respostas'],'suficiente',d['suficiente'],'sintomas',len(d['sintomas']),'mapa',len(d['mapa']['celulas']),'bairros',d['bairros']['areas_em_consulta'])
print('top sintoma',d['sintomas'][0]['rotulo'],d['sintomas'][0]['relatos'])
print('estatisticas',s.get(B+'/estatisticas?dias=30').status_code,'mapa',s.get(B+'/mapa').status_code,'bairros',s.get(B+'/bairros').status_code)
print('raiz',s.get(B+'/').status_code,'respostas.csv sem token',s.get(B+'/respostas/export.csv').status_code)
