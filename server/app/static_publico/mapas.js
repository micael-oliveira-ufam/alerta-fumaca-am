/* Camadas de mapa compartilhadas pelas seções do painel público (Leaflet).
 *
 * Bases:      OpenStreetMap, relevo (OpenTopoMap) e imagem de satélite em cor real (NASA GIBS).
 * Sobreposições (NASA GIBS): aerossóis (MODIS Terra) e anomalias térmicas (VIIRS 375 m).
 *
 * As camadas GIBS usam os mesmos identificadores do app (lib/logic/map_layers.dart). Eles NÃO
 * puderam ser conferidos contra o catálogo da NASA a partir do ambiente de desenvolvimento
 * (acesso bloqueado). Se uma imagem não existir para a data, o mapa avisa em vez de ficar em branco.
 * Data usada: ontem (UTC), porque o dia corrente costuma estar incompleto.
 */
(function () {
  'use strict';

  function dataGibs() { return new Date(Date.now() - 24 * 3600 * 1000).toISOString().slice(0, 10); }

  function gibs(id, ext, nivel, opcoes) {
    var url = 'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/' + id + '/default/' + dataGibs() +
      '/GoogleMapsCompatible_Level' + nivel + '/{z}/{y}/{x}.' + ext;
    var o = { maxNativeZoom: nivel, maxZoom: 12, attribution: 'Imagens: NASA GIBS / EOSDIS (' + dataGibs() + ')' };
    for (var k in (opcoes || {})) o[k] = opcoes[k];
    return L.tileLayer(url, o);
  }

  /* Cria as camadas e o seletor. `aviso` é o elemento onde se escreve se imagens da NASA falharem. */
  function configurar(mapa, opcoes) {
    opcoes = opcoes || {};
    var osm = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 18, attribution: '© OpenStreetMap' });
    var relevo = L.tileLayer('https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png', {
      subdomains: 'abc', maxZoom: 17,
      attribution: 'Dados: © OpenStreetMap, SRTM | Estilo: © OpenTopoMap (CC-BY-SA)'
    });
    var satelite = gibs('VIIRS_SNPP_CorrectedReflectance_TrueColor', 'jpg', 9);
    var aerossol = gibs('MODIS_Terra_Aerosol', 'png', 6, { opacity: 0.65 });
    var termica = gibs('VIIRS_SNPP_Thermal_Anomalies_375m_All', 'png', 9);

    osm.addTo(mapa);
    var bases = { 'Mapa (OpenStreetMap)': osm, 'Relevo (OpenTopoMap)': relevo, 'Satélite, cor real (NASA)': satelite };
    var sobre = { 'Aerossóis: fumaça e poeira (NASA MODIS)': aerossol, 'Focos de calor (NASA VIIRS 375 m)': termica };
    var extras = opcoes.extras || {};
    for (var k in extras) sobre[k] = extras[k];
    L.control.layers(bases, sobre, { collapsed: true }).addTo(mapa);
    L.control.scale({ imperial: false }).addTo(mapa);

    var erros = 0, avisou = false;
    [satelite, aerossol, termica].forEach(function (c) {
      c.on('tileerror', function () {
        erros++;
        if (erros >= 6 && !avisou && opcoes.aviso) {
          avisou = true;
          opcoes.aviso.textContent = 'Algumas imagens da NASA não carregaram (pode não haver imagem para ' + dataGibs() +
            ' ou o serviço está indisponível). Escolha outra camada de base ou tente mais tarde.';
          opcoes.aviso.hidden = false;
        }
      });
    });
    return { osm: osm, relevo: relevo, satelite: satelite, aerossol: aerossol, termica: termica };
  }

  window.RespirarMapas = { configurar: configurar, dataGibs: dataGibs };
})();
