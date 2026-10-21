/* Seção "Qualidade do ar" do painel público. Lê só /publico/qualidade-ar (cópia em cache do servidor).
 *
 * São ESTIMATIVAS DE MODELO (CAMS, via Open-Meteo), com células de ~45 km: não são medições de
 * estações e não distinguem bairros. O índice é o US AQI (EPA), o mesmo do app, e não o IQAr oficial.
 */
(function () {
  'use strict';

  var COR = { boa: '#2E7D32', moderada: '#F9A825', sensivel: '#EF6C00', ruim: '#C62828', muito_ruim: '#6A1B9A', perigosa: '#4E0B1D' };
  var MANAUS_MS = -4 * 3600 * 1000;
  var dados = null, ordem = 'aqi', todos = false, mapa = null, camada = null, assinatura = null;

  function $(id) { return document.getElementById(id); }
  function h(tag, attrs) {
    var el = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) {
      if (k === 'text') el.textContent = attrs[k]; else el.setAttribute(k, attrs[k]);
    });
    for (var i = 2; i < arguments.length; i++) {
      var c = arguments[i]; if (c == null) continue;
      el.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return el;
  }
  function limpar(el) { while (el.firstChild) el.removeChild(el.firstChild); return el; }
  function nf(n, d) { return n === null || n === undefined ? '—' : Number(n).toLocaleString('pt-BR', { maximumFractionDigits: d == null ? 0 : d }); }
  function p2(n) { return (n < 10 ? '0' : '') + n; }
  function manaus(iso) {
    var t = Date.parse(iso); if (!isFinite(t)) return null;
    var d = new Date(t + MANAUS_MS);
    return p2(d.getUTCDate()) + '/' + p2(d.getUTCMonth() + 1) + ' ' + p2(d.getUTCHours()) + ':' + p2(d.getUTCMinutes());
  }
  // Data completa (com ano) no horário de Manaus, ex.: 21/10/2026 14:00.
  function manausCompleta(iso) {
    var t = Date.parse(iso); if (!isFinite(t)) return null;
    var d = new Date(t + MANAUS_MS);
    return p2(d.getUTCDate()) + '/' + p2(d.getUTCMonth() + 1) + '/' + d.getUTCFullYear() + ' ' + p2(d.getUTCHours()) + ':' + p2(d.getUTCMinutes());
  }
  function badge(m) {
    if (m.us_aqi === null) return h('span', { class: 'aqi nd', text: 'sem dado' });
    return h('span', { class: 'aqi', style: 'background:' + COR[m.categoria] + (m.categoria === 'moderada' ? ';color:#2b2100' : '') }, String(m.us_aqi));
  }

  function carregar() {
    fetch('/publico/qualidade-ar', { headers: { Accept: 'application/json' } })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (d) { dados = d; $('ar-erro').hidden = true; desenhar(); })
      .catch(function () {
        $('ar-erro').hidden = false;
        $('ar-erro').textContent = 'Não foi possível obter a qualidade do ar agora (o serviço do modelo pode estar indisponível). Tente novamente em instantes.';
      });
  }

  function kpi(l, v, dt, cor) {
    return h('div', { class: 'kpi', style: '--k:' + cor }, h('div', { class: 'l', text: l }),
      h('div', { class: 'v txt', text: v }), h('div', { class: 'd', text: dt }));
  }

  function desenhar() {
    var r = dados.resumo, m = dados.manaus;
    var el = limpar($('ar-kpis'));
    if (m) {
      el.appendChild(kpi('Manaus', m.us_aqi === null ? 'sem dado' : 'Índice ' + m.us_aqi + ' · ' + m.categoria_rotulo,
        'PM2,5 ' + nf(m.pm2_5, 1) + ' · PM10 ' + nf(m.pm10, 1) + ' µg/m³', m.categoria ? COR[m.categoria] : '#999'));
    }
    el.appendChild(kpi('Pior índice no estado', r.pior ? r.pior.municipio + ' · ' + r.pior.us_aqi : '—',
      r.pior ? r.pior.categoria_rotulo : 'sem dados', r.pior ? COR[(dados.municipios.filter(function (x) { return x.municipio === r.pior.municipio; })[0] || {}).categoria] || '#999' : '#999'));
    el.appendChild(kpi('PM2,5 mais alto', r.pm2_5_max ? r.pm2_5_max.municipio + ' · ' + nf(r.pm2_5_max.pm2_5, 1) + ' µg/m³' : '—',
      'partículas finas (até 2,5 µm)', '#6A1B9A'));
    var ref = dados.referencia_modelo ? manausCompleta(dados.referencia_modelo) : null;
    var refTxt = ref ? 'Última atualização dos dados do modelo: ' + ref + ' (horário de Manaus).' : 'A data de atualização do modelo não foi informada pelo serviço.';
    var cons = manausCompleta(dados.consultado_em);
    $('ar-atualizacao').textContent = refTxt + (cons ? ' Consultados pelo servidor em ' + cons + '.' : '');
    el.appendChild(kpi('Referência do modelo', ref ? ref + ' (Manaus)' : 'não informada',
      'consultado em ' + (manausCompleta(dados.consultado_em) || '—') + ' · ' + r.com_dado + ' de ' + r.total + ' municípios com dado', '#1565C0'));

    var av = $('ar-defasagem');
    if (dados.desatualizado) {
      av.hidden = false;
      av.textContent = 'O serviço do modelo não respondeu agora; os valores são da última consulta bem-sucedida (' + (manausCompleta(dados.consultado_em) || '—') + ', horário de Manaus).';
    } else { av.hidden = true; }

    // Manaus: um único valor para a cidade, com a ressalva sobre bairros.
    $('ar-manaus-nota').textContent = dados.nota_bairros + ' Por isso o painel não mostra índice por bairro: seria o mesmo número repetido, e isso sugeriria uma precisão que o dado não tem. Os bairros mais afetados segundo os relatos do app estão na seção "Bairros de Manaus mais afetados".';

    legenda(); mapaAr(); tabela();
    $('ar-fonte').textContent = dados.atribuicao + ' Escala: ' + dados.escala + '. Resolução do modelo: ~' + dados.resolucao_km + ' km. ' +
      'Estimativa de modelo, não medição de estação; não substitui os boletins oficiais.';
  }

  function legenda() {
    var el = limpar($('ar-legenda'));
    var ant = 0;
    dados.faixas.forEach(function (f) {
      var faixa = f.ate === null ? 'acima de ' + (ant - 1) : ant + '–' + f.ate;
      ant = f.ate === null ? ant : f.ate + 1;
      el.appendChild(h('span', {}, h('i', { style: 'background:' + COR[f.id] }), f.rotulo + ' (' + faixa + ')'));
    });
  }

  function popup(m) {
    return m.municipio + ': índice ' + (m.us_aqi === null ? '—' : m.us_aqi + ' (' + m.categoria_rotulo + ')') +
      ' · PM2,5 ' + nf(m.pm2_5, 1) + ' · PM10 ' + nf(m.pm10, 1) + ' µg/m³';
  }

  function mapaAr() {
    if (!mapa) {
      mapa = L.map('mapa-ar', { scrollWheelZoom: false }).setView([-4.0, -64.5], 5);
      camada = L.layerGroup().addTo(mapa);
      RespirarMapas.configurar(mapa, { aviso: $('ar-mapa-aviso'), extras: { 'Municípios (índice do modelo)': camada } });
      mapa.on('focus', function () { mapa.scrollWheelZoom.enable(); });
      mapa.on('blur', function () { mapa.scrollWheelZoom.disable(); });
      setTimeout(function () { mapa.invalidateSize(); }, 50);
    }
    // Só redesenha se os dados mudaram: não fecha dicas abertas nem mexe no zoom de quem está explorando.
    var nova = JSON.stringify(dados.municipios.map(function (m) { return [m.latitude, m.longitude, m.us_aqi, m.pm2_5, m.pm10, m.categoria]; }));
    if (nova === assinatura) return;
    assinatura = nova;
    camada.clearLayers();
    dados.municipios.forEach(function (m) {
      var cor = m.categoria ? COR[m.categoria] : '#9E9E9E';
      var raio = m.pm2_5 === null ? 6 : Math.min(18, 6 + Math.sqrt(m.pm2_5) * 1.6); // área ~ PM2,5
      L.circleMarker([m.latitude, m.longitude], { radius: raio, color: cor, fillColor: cor, fillOpacity: .55, weight: 2 })
        .bindTooltip(popup(m)).addTo(camada);
    });
  }

  function ordenar(lista) {
    var l = lista.slice();
    if (ordem === 'nome') l.sort(function (a, b) { return a.municipio.localeCompare(b.municipio, 'pt-BR'); });
    else if (ordem === 'pm25') l.sort(function (a, b) { return (b.pm2_5 === null ? -1 : b.pm2_5) - (a.pm2_5 === null ? -1 : a.pm2_5); });
    else l.sort(function (a, b) { return (b.us_aqi === null ? -1 : b.us_aqi) - (a.us_aqi === null ? -1 : a.us_aqi); });
    return l;
  }

  function tabela() {
    var corpo = limpar($('ar-tab').querySelector('tbody'));
    var l = ordenar(dados.municipios), tot = l.length;
    if (!todos) l = l.slice(0, 15);
    l.forEach(function (m) {
      corpo.appendChild(h('tr', {}, h('td', { text: m.municipio }), h('td', {}, badge(m)),
        h('td', { text: m.categoria_rotulo || '—' }), h('td', { text: nf(m.pm2_5, 1) }), h('td', { text: nf(m.pm10, 1) }),
        h('td', { text: m.fracao_fina_pct === null ? '—' : m.fracao_fina_pct + '%' })));
    });
    var bt = $('ar-todos');
    bt.hidden = tot <= 15; bt.textContent = todos ? 'Mostrar só os 15 primeiros' : 'Mostrar os ' + tot + ' municípios';
  }

  $('ar-ordem').addEventListener('click', function (e) {
    var b = e.target.closest('button[data-o]'); if (!b || !dados) return;
    ordem = b.getAttribute('data-o');
    Array.prototype.forEach.call($('ar-ordem').children, function (x) {
      var on = x === b; x.classList.toggle('on', on); x.setAttribute('aria-pressed', String(on));
    });
    tabela();
  });
  $('ar-todos').addEventListener('click', function () { todos = !todos; if (dados) tabela(); });

  carregar();
  setInterval(function () { if (!document.hidden) carregar(); }, 15 * 60 * 1000);
})();
