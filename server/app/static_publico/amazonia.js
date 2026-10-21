/* Seção "Amazônia · camadas oficiais": mapa com botões para ligar/desligar camadas.
 *
 * Camadas do TerraBrasilis (INPE), via WMS no mesmo GeoServer. Os NOMES das camadas foram lidos do catálogo WFS
 * (GetCapabilities) em 20/10/2026, na máquina do usuário. NÃO foi verificado: que cada camada responde por WMS,
 * o estilo padrão de cada uma, o tempo de resposta e a licença/atribuição. Se uma camada não carregar, a página avisa.
 * Camadas NASA GIBS: mesmos identificadores de mapas.js (também não conferidos ao vivo).
 */
(function () {
  'use strict';
  var WMS = 'https://terrabrasilis.dpi.inpe.br/geoserver/ows';
  var ATRIB = 'Dados: INPE / TerraBrasilis';
  function $(id) { return document.getElementById(id); }

  // [id, rótulo, camada WMS, explicação, opções]
  var GRUPOS = [
    ['Desmatamento', [
      ['deter', 'Alertas DETER (Amazônia)', 'deter-amz:deter_amz', 'Alertas de desmatamento e degradação quase diários; indicam onde agir, não a taxa oficial.'],
      ['prodes', 'Desmatamento anual (PRODES)', 'prodes-amazon-nb:yearly_deforestation_biome', 'Taxa oficial anual de desmatamento no bioma Amazônia.'],
      ['acum', 'Desmatamento acumulado até 2007', 'prodes-amazon-nb:accumulated_deforestation_2007_biome', 'Áreas já desmatadas até 2007, base do PRODES.'],
      ['semfloresta', 'Sem floresta (natural)', 'prodes-amazon-nb:no_forest_biome', 'Áreas sem floresta por natureza (campos, água etc.), fora do cálculo do PRODES.']
    ]],
    ['Limites e território', [
      ['bioma', 'Bioma Amazônia', 'prodes-amazon-nb:amazon_biome_border', 'Contorno do bioma Amazônia.'],
      ['legal', 'Amazônia Legal', 'prodes-legal-amz:brazilian_legal_amazon', 'Área de atuação da Amazônia Legal.'],
      ['estados', 'Estados', 'prodes-amazon-nb:states_amazon_biome', 'Estados no bioma.'],
      ['munic', 'Municípios', 'prodes-amazon-nb:municipalities_amazon_biome', 'Municípios no bioma (camada pesada; amplie o mapa).'],
      ['hidro', 'Hidrografia', 'prodes-amazon-nb:hydrography_biome', 'Rios e corpos d\'água.']
    ]],
    ['Áreas protegidas', [
      ['uc', 'Unidades de conservação', 'prodes-amazon-nb:conservation_units_amazon_biome', 'Unidades de conservação no bioma.'],
      ['ti', 'Terras indígenas', 'prodes-amazon-nb:indigenous_area_amazon_biome', 'Terras indígenas no bioma.']
    ]]
  ];
  var GIBS = [
    ['aerossol', 'Aerossóis: fumaça e poeira (NASA)', 'MODIS_Terra_Aerosol', 'png', 6, 0.65, 'Aerossóis detectados pelo MODIS Terra.'],
    ['termica', 'Anomalias térmicas (NASA VIIRS)', 'VIIRS_SNPP_Thermal_Anomalies_375m_All', 'png', 9, 1, 'Detecções térmicas do VIIRS (375 m), fonte da NASA.']
  ];
  var BASES = [['osm', 'Mapa'], ['sat', 'Satélite'], ['relevo', 'Relevo']];
  var DESMAT = ['deter', 'prodes', 'acum', 'semfloresta']; // com elas ligadas, o fundo fica restrito ao Satélite
  var TEXTO_GIBS = {
    aerossol: 'Mancha colorida = quantidade de partículas (fumaça, poeira) no ar sobre o local, estimada pelo satélite MODIS. Cor mais intensa indica mais partículas; áreas sem cor não têm dado naquele dia (nuvens, por exemplo). Não mede a qualidade do ar no chão.',
    termica: 'Cada ponto é uma detecção de calor anômalo pelo satélite VIIRS (pixel de 375 m). Pode ser fogo, mas não é incêndio confirmado; vários pontos próximos podem ser o mesmo incêndio.'
  };

  if (!$('mapa-amazonia') || typeof L === 'undefined') return;
  var mapa = L.map('mapa-amazonia', { scrollWheelZoom: false, zoomControl: true, worldCopyJump: false }).setView([-4, -63], 5);
  mapa.on('focus', function () { mapa.scrollWheelZoom.enable(); });
  mapa.on('blur', function () { mapa.scrollWheelZoom.disable(); });
  L.control.scale({ imperial: false }).addTo(mapa);

  /* Barra de progresso: conta as imagens (tiles) que começaram e terminaram de baixar, em todas as camadas. */
  var prog = { ini: 0, fim: 0, falhas: 0, carregando: {}, timer: null };
  var barra = $('amz-progresso'), barraPreench = $('amz-prog-barra'), barraTexto = $('amz-prog-texto');
  function atualizarBarra() {
    if (!barra) return;
    var nomes = Object.keys(prog.carregando).filter(function (k) { return prog.carregando[k]; });
    var pend = prog.ini - prog.fim;
    clearTimeout(prog.timer);
    if (pend > 0 || nomes.length) {
      var pct = prog.ini ? Math.round(100 * prog.fim / prog.ini) : 0;
      barra.hidden = false; barra.className = 'progresso ativo';
      barra.setAttribute('aria-valuenow', String(pct));
      barraPreench.style.width = pct + '%';
      barraTexto.textContent = 'Baixando imagens do mapa: ' + prog.fim + ' de ' + prog.ini + ' (' + pct + '%)' +
        (nomes.length ? ' · ' + nomes.join(', ') : '');
    } else if (prog.ini) {
      barraPreench.style.width = '100%'; barra.setAttribute('aria-valuenow', '100'); barra.className = 'progresso pronto';
      barraTexto.textContent = prog.falhas ? 'Concluído, com ' + prog.falhas + ' imagem(ns) que não carregaram.' : 'Mapa carregado.';
      prog.timer = setTimeout(function () { barra.hidden = true; prog.ini = prog.fim = prog.falhas = 0; }, 2500);
    }
  }
  function acompanhar(camada, rotulo) {
    camada.on('loading', function () { prog.carregando[rotulo] = true; atualizarBarra(); });
    camada.on('load', function () { prog.carregando[rotulo] = false; atualizarBarra(); });
    camada.on('tileloadstart', function () { prog.ini++; atualizarBarra(); });
    camada.on('tileload', function () { prog.fim++; atualizarBarra(); });
    camada.on('tileerror', function () { prog.fim++; prog.falhas++; atualizarBarra(); });
  }

  var bases = {
    osm: L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 18, attribution: '© OpenStreetMap' }),
    relevo: L.tileLayer('https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png', { subdomains: 'abc', maxZoom: 17, attribution: 'Dados: © OpenStreetMap, SRTM | Estilo: © OpenTopoMap (CC-BY-SA)' }),
    sat: null
  };
  var dia = window.RespirarMapas ? window.RespirarMapas.dataGibs() : new Date(Date.now() - 864e5).toISOString().slice(0, 10);
  function gibs(id, ext, nivel, op) {
    return L.tileLayer('https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/' + id + '/default/' + dia + '/GoogleMapsCompatible_Level' + nivel + '/{z}/{y}/{x}.' + ext,
      { maxNativeZoom: nivel, maxZoom: 12, opacity: op, attribution: 'Imagens: NASA GIBS / EOSDIS (' + dia + ')' });
  }
  bases.sat = gibs('VIIRS_SNPP_CorrectedReflectance_TrueColor', 'jpg', 9, 1);
  var baseAtual = 'osm', baseAnterior = 'osm'; bases.osm.addTo(mapa);
  acompanhar(bases.osm, 'mapa de fundo'); acompanhar(bases.sat, 'satélite'); acompanhar(bases.relevo, 'relevo');

  var camadas = {}, ligadas = {}, falhas = {}, info = {};
  GRUPOS.forEach(function (g) {
    g[1].forEach(function (c) {
      camadas[c[0]] = L.tileLayer.wms(WMS, { layers: c[2], format: 'image/png', transparent: true, version: '1.3.0', attribution: ATRIB, opacity: 0.85 });
      info[c[0]] = c; acompanhar(camadas[c[0]], c[1]);
    });
  });
  GIBS.forEach(function (c) {
    camadas[c[0]] = gibs(c[2], c[3], c[4], c[5]);
    info[c[0]] = [c[0], c[1], c[2], c[6]]; acompanhar(camadas[c[0]], c[1]);
  });
  Object.keys(camadas).forEach(function (id) {
    camadas[id].on('tileerror', function () {
      falhas[id] = (falhas[id] || 0) + 1;
      if (falhas[id] === 4 && ligadas[id]) avisar('A camada "' + info[id][1] + '" não carregou (serviço indisponível ou camada sem imagem nesta área). Tente outra camada ou mais tarde.');
    });
  });

  function avisar(t) { var e = $('amz-aviso'); e.textContent = t; e.hidden = !t; }
  function urlLegenda(camada) {
    return WMS + '?service=WMS&version=1.3.0&request=GetLegendGraphic&format=image%2Fpng&layer=' + encodeURIComponent(camada);
  }
  function legenda() {
    var box = $('amz-legenda'); while (box.firstChild) box.removeChild(box.firstChild);
    var ids = Object.keys(ligadas).filter(function (i) { return ligadas[i]; });
    if (!ids.length) { box.textContent = 'Nenhuma camada ligada. Use os botões acima.'; return; }
    var t = document.createElement('h3'); t.textContent = 'Legenda: o que você está vendo'; box.appendChild(t);
    ids.forEach(function (i) {
      var d = document.createElement('div'); d.className = 'leg-item';
      var b = document.createElement('b'); b.textContent = info[i][1]; d.appendChild(b);
      var p = document.createElement('p'); p.className = 'sub'; p.textContent = info[i][3]; d.appendChild(p);
      if (TEXTO_GIBS[i]) {
        var g = document.createElement('p'); g.className = 'sub'; g.textContent = TEXTO_GIBS[i]; d.appendChild(g);
      } else {
        var q = document.createElement('p'); q.className = 'sub';
        q.textContent = 'Os elementos desta camada são linhas ou áreas (não pontos); as cores seguem a legenda oficial abaixo.';
        d.appendChild(q);
        var img = document.createElement('img'); img.className = 'leg-img'; img.alt = 'Legenda oficial da camada ' + info[i][1];
        img.loading = 'lazy'; img.src = urlLegenda(info[i][2]);
        img.addEventListener('error', function () {
          img.remove();
          var f = document.createElement('p'); f.className = 'sub'; f.textContent = 'A legenda gráfica oficial não pôde ser carregada agora.'; d.appendChild(f);
        });
        d.appendChild(img);
      }
      box.appendChild(d);
    });
  }
  function botao(texto, ativo, aoClicar) {
    var b = document.createElement('button'); b.type = 'button'; b.textContent = texto;
    b.setAttribute('aria-pressed', String(!!ativo)); b.addEventListener('click', function () { aoClicar(b); });
    return b;
  }
  function alternar(id, b) {
    ligadas[id] = !ligadas[id];
    if (ligadas[id]) { camadas[id].addTo(mapa); falhas[id] = 0; } else { mapa.removeLayer(camadas[id]); }
    b.setAttribute('aria-pressed', String(!!ligadas[id]));
    avisar(''); legenda(); aplicarRestricao();
  }
  /* Com qualquer camada de desmatamento ligada, só o fundo "Satélite" fica disponível (e é escolhido sozinho). */
  var botoesBase = [];
  function trocarBase(id) {
    if (id === baseAtual) return;
    mapa.removeLayer(bases[baseAtual]); baseAtual = id; bases[id].addTo(mapa); bases[id].bringToBack();
    botoesBase.forEach(function (x, i) { x.setAttribute('aria-pressed', String(BASES[i][0] === baseAtual)); });
  }
  function aplicarRestricao() {
    var restrito = DESMAT.some(function (i) { return ligadas[i]; });
    var nota = $('amz-nota-base');
    if (restrito) {
      if (baseAtual !== 'sat') { baseAnterior = baseAtual; trocarBase('sat'); }
    } else if (baseAtual === 'sat' && baseAnterior !== 'sat' && nota && !nota.hidden) {
      trocarBase(baseAnterior);
    }
    botoesBase.forEach(function (x, i) {
      var bloqueia = restrito && BASES[i][0] !== 'sat';
      x.disabled = bloqueia; x.title = bloqueia ? 'Com camadas de desmatamento, só o fundo Satélite está disponível.' : '';
    });
    if (nota) nota.hidden = !restrito;
  }

  var box = $('amz-botoes');
  function grupo(titulo, itens) {
    var d = document.createElement('div'); d.className = 'grupo';
    var t = document.createElement('b'); t.textContent = titulo; d.appendChild(t);
    itens.forEach(function (x) { d.appendChild(x); });
    box.appendChild(d);
  }
  grupo('Mapa de fundo', BASES.map(function (bs) {
    var bt = botao(bs[1], bs[0] === baseAtual, function () { baseAnterior = bs[0]; trocarBase(bs[0]); });
    botoesBase.push(bt); return bt;
  }));
  GRUPOS.forEach(function (g) {
    grupo(g[0], g[1].map(function (c) { return botao(c[1], false, function (b) { alternar(c[0], b); }); }));
  });
  grupo('Imagens de satélite (NASA)', GIBS.map(function (c) { return botao(c[1], false, function (b) { alternar(c[0], b); }); }));

  // Começa com o contorno do bioma, para a pessoa já ver a Amazônia.
  var nBotoes = BASES.length + GRUPOS[0][1].length; // o primeiro botão do grupo 'Limites' é o bioma
  alternar('bioma', box.querySelectorAll('button')[nBotoes]);
  setTimeout(function () { mapa.invalidateSize(); }, 80);
})();
