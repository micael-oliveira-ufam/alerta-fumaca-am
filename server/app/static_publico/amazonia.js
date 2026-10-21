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

  if (!$('mapa-amazonia') || typeof L === 'undefined') return;
  var mapa = L.map('mapa-amazonia', { scrollWheelZoom: false, zoomControl: true, worldCopyJump: false }).setView([-4, -63], 5);
  mapa.on('focus', function () { mapa.scrollWheelZoom.enable(); });
  mapa.on('blur', function () { mapa.scrollWheelZoom.disable(); });
  L.control.scale({ imperial: false }).addTo(mapa);

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
  var baseAtual = 'osm'; bases.osm.addTo(mapa);

  var camadas = {}, ligadas = {}, falhas = {}, info = {};
  GRUPOS.forEach(function (g) {
    g[1].forEach(function (c) {
      camadas[c[0]] = L.tileLayer.wms(WMS, { layers: c[2], format: 'image/png', transparent: true, version: '1.3.0', attribution: ATRIB, opacity: 0.85 });
      info[c[0]] = c;
    });
  });
  GIBS.forEach(function (c) {
    camadas[c[0]] = gibs(c[2], c[3], c[4], c[5]);
    info[c[0]] = [c[0], c[1], c[2], c[6]];
  });
  Object.keys(camadas).forEach(function (id) {
    camadas[id].on('tileerror', function () {
      falhas[id] = (falhas[id] || 0) + 1;
      if (falhas[id] === 4 && ligadas[id]) avisar('A camada "' + info[id][1] + '" não carregou (serviço indisponível ou camada sem imagem nesta área). Tente outra camada ou mais tarde.');
    });
  });

  function avisar(t) { var e = $('amz-aviso'); e.textContent = t; e.hidden = !t; }
  function legenda() {
    var box = $('amz-legenda'); while (box.firstChild) box.removeChild(box.firstChild);
    var ids = Object.keys(ligadas).filter(function (i) { return ligadas[i]; });
    if (!ids.length) { box.textContent = 'Nenhuma camada ligada. Use os botões acima.'; return; }
    ids.forEach(function (i) {
      var p = document.createElement('p'); p.className = 'sub';
      var b = document.createElement('b'); b.textContent = info[i][1] + ': ';
      p.appendChild(b); p.appendChild(document.createTextNode(info[i][3])); box.appendChild(p);
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
    avisar(''); legenda();
  }

  var box = $('amz-botoes');
  function grupo(titulo, itens) {
    var d = document.createElement('div'); d.className = 'grupo';
    var t = document.createElement('b'); t.textContent = titulo; d.appendChild(t);
    itens.forEach(function (x) { d.appendChild(x); });
    box.appendChild(d);
  }
  grupo('Mapa de fundo', BASES.map(function (bs) {
    return botao(bs[1], bs[0] === baseAtual, function () {
      mapa.removeLayer(bases[baseAtual]); baseAtual = bs[0]; bases[baseAtual].addTo(mapa); bases[baseAtual].bringToBack();
      Array.prototype.forEach.call(box.querySelectorAll('.grupo')[0].querySelectorAll('button'), function (x, i) { x.setAttribute('aria-pressed', String(BASES[i][0] === baseAtual)); });
    });
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
