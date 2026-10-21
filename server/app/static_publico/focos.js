/* Seção "Focos de calor" do painel público. Lê só /focos (cópia em cache do WFS do INPE). */
(function () {
  'use strict';
  var SAT = {
    'AQUA_M-T': 'MODIS Aqua', 'TERRA_M-T': 'MODIS Terra', 'NOAA-20': 'NOAA-20 (VIIRS)',
    'NOAA-21': 'NOAA-21 (VIIRS)', 'NPP-375': 'Suomi NPP (VIIRS)', 'NPP-375D': 'Suomi NPP (VIIRS, dia)'
  };
  var MANAUS_MS = -4 * 3600 * 1000; // UTC-4, sem horário de verão
  var janela = 'hoje', modo = 'calor', todos = null, mapa = null, camadaPontos = null, camadaCalor = null;
  var meta = { consultado: null, cache: '', pagina: null }; // quando o servidor consultou o INPE, e quando esta página atualizou

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
  function nf(n, d) { return Number(n).toLocaleString('pt-BR', { maximumFractionDigits: d == null ? 0 : d }); }
  function num(v) { var x = Number(v); return v === null || v === undefined || v === '' || !isFinite(x) ? null : x; }
  function media(a) { return a.length ? a.reduce(function (s, x) { return s + x; }, 0) / a.length : null; }

  // O INPE entrega "data_hora_gmt" em UTC. Interpreta como UTC mesmo sem o "Z".
  function quando(p) {
    var s = String(p.data_hora_gmt || '').trim(); if (!s) return null;
    s = s.replace(' ', 'T'); if (!/[zZ]|[+-]\d\d:?\d\d$/.test(s)) s += 'Z';
    var t = Date.parse(s); return isFinite(t) ? t : null;
  }
  function diaManaus(t) { return new Date(t + MANAUS_MS).toISOString().slice(0, 10); }
  function p2(n) { return (n < 10 ? '0' : '') + n; }
  /* "20/10/2026 10:30" no horário de Manaus (UTC-4) e "14:30 UTC". */
  function manaus(t) {
    var d = new Date(t + MANAUS_MS);
    return p2(d.getUTCDate()) + '/' + p2(d.getUTCMonth() + 1) + '/' + d.getUTCFullYear() + ' ' + p2(d.getUTCHours()) + ':' + p2(d.getUTCMinutes());
  }
  function utcHora(t) { var d = new Date(t); return p2(d.getUTCHours()) + ':' + p2(d.getUTCMinutes()) + ' UTC'; }
  function ha(ms) {
    var m = Math.max(0, Math.round(ms / 60000));
    if (m < 1) return 'agora há pouco';
    if (m < 60) return 'há ' + m + ' min';
    var hh = Math.floor(m / 60), mm = m % 60;
    if (hh < 48) return 'há ' + hh + ' h' + (mm ? ' ' + mm + ' min' : '');
    return 'há ' + Math.floor(hh / 24) + ' dias';
  }

  function carregar() {
    fetch('/focos?window=last48h&scope=amazonas', { headers: { Accept: 'application/json' } })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        var c = r.headers.get('X-Consultado-Em'), t = c ? Date.parse(c) : NaN;
        meta.consultado = isFinite(t) ? t : null; meta.cache = r.headers.get('X-Cache') || ''; meta.pagina = Date.now();
        return r.json();
      })
      .then(function (g) {
        todos = (g.features || []).map(function (f) {
          var p = f.properties || {}, t = quando(p), lat = num(p.latitude), lon = num(p.longitude);
          if ((lat === null || lon === null) && f.geometry && f.geometry.coordinates) {
            lon = f.geometry.coordinates[0]; lat = f.geometry.coordinates[1];
          }
          if (t === null || lat === null || lon === null) return null;
          var dsc = num(p.numero_dias_sem_chuva), rf = num(p.risco_fogo), frp = num(p.frp);
          return { t: t, lat: lat, lon: lon, sat: String(p.satelite || ''), mun: String(p.municipio || '—'),
            frp: frp === null || frp < 0 ? null : frp,
            dsc: dsc === null || dsc < 0 ? null : dsc,   // valores negativos = ausência de dado (suposição)
            rf: rf === null || rf < 0 ? null : rf };
        }).filter(Boolean);
        $('focos-erro').hidden = true;
        desenhar();
      })
      .catch(function () {
        var e = $('focos-erro'); e.hidden = false;
        e.textContent = 'Não foi possível obter os focos de calor agora (o servidor do INPE pode estar indisponível). Tente novamente em instantes.';
      });
  }

  function recorte() {
    if (janela === '48h') return todos;
    var ini = Date.parse(diaManaus(Date.now()) + 'T00:00:00Z') - MANAUS_MS;
    return todos.filter(function (x) { return x.t >= ini; });
  }

  function desenhar() {
    var d = recorte();
    kpis(d); porSatelite(d); porDia(todos); tabela(d); mapaFocos(d);
    atualizacao();
    $('focos-nota').textContent = 'Fonte: INPE, Programa Queimadas (TerraBrasilis), via cópia em cache do servidor. ' +
      'Um foco indica fogo detectado por satélite, com atraso de passagem e processamento; vários focos podem ser o mesmo incêndio.';
  }

  /* Faixa "quando foi atualizado": três instantes diferentes, que não se confundem. */
  function atualizacao() {
    var el = limpar($('focos-quando'));
    var agora = Date.now();
    var ult = todos.reduce(function (m, x) { return Math.max(m, x.t); }, 0);
    function chip(rotulo, valor, detalhe) {
      return h('div', { class: 'chip' }, h('span', { class: 'cl', text: rotulo }), h('b', { text: valor }),
        detalhe ? h('span', { class: 'cd', text: detalhe }) : null);
    }
    el.appendChild(chip('Detecção mais recente do satélite',
      ult ? manaus(ult) + ' (Manaus)' : 'nenhuma em 48 h',
      ult ? utcHora(ult) + ' · ' + ha(agora - ult) : 'sem focos no Amazonas nas últimas 48 h'));
    el.appendChild(chip('Servidor consultou o INPE',
      meta.consultado ? manaus(meta.consultado) + ' (Manaus)' : 'horário não informado',
      meta.consultado ? ha(agora - meta.consultado) + ' · a consulta é reaproveitada por até 5 min' : ''));
    el.appendChild(chip('Esta página atualizou', manaus(meta.pagina || agora) + ' (Manaus)', 'recarrega sozinha a cada 5 min'));
    var aviso = $('focos-defasagem');
    if (meta.cache === 'STALE') {
      aviso.hidden = false;
      aviso.textContent = 'O servidor do INPE não respondeu agora; os focos abaixo são da última consulta bem-sucedida' +
        (meta.consultado ? ' (' + manaus(meta.consultado) + ', horário de Manaus)' : '') + '.';
    } else { aviso.hidden = true; }
  }

  function kpi(l, v, dt, cor) {
    return h('div', { class: 'kpi', style: '--k:' + cor }, h('div', { class: 'l', text: l }),
      h('div', { class: 'v', text: v }), h('div', { class: 'd', text: dt }));
  }
  function kpis(d) {
    var el = limpar($('focos-kpis'));
    var frp = d.map(function (x) { return x.frp; }).filter(function (x) { return x !== null; });
    var dsc = media(d.map(function (x) { return x.dsc; }).filter(function (x) { return x !== null; }));
    var rf = media(d.map(function (x) { return x.rf; }).filter(function (x) { return x !== null; }));
    var muns = {}; d.forEach(function (x) { muns[x.mun] = 1; });
    el.appendChild(kpi('Focos', nf(d.length), janela === 'hoje' ? 'hoje, no horário de Manaus' : 'últimas 48 h', '#E65100'));
    el.appendChild(kpi('Municípios', nf(Object.keys(muns).length), 'com ao menos um foco', '#1565C0'));
    el.appendChild(kpi('FRP máximo', frp.length ? nf(Math.max.apply(null, frp), 1) + ' MW' : '—', 'potência radiativa do fogo', '#B71C1C'));
    el.appendChild(kpi('Dias sem chuva', dsc === null ? '—' : nf(dsc, 1), 'média nos focos', '#9CCC65'));
    el.appendChild(kpi('Risco de fogo', rf === null ? '—' : nf(rf, 2), 'média (índice 0 a 1)', '#C98A12'));
  }

  function barras(box, itens, cor) {
    limpar(box);
    if (!itens.length) { box.appendChild(h('p', { class: 'vazio', text: 'Sem focos neste recorte.' })); return; }
    var max = Math.max.apply(null, itens.map(function (i) { return i[1]; })) || 1;
    itens.forEach(function (i) {
      box.appendChild(h('div', { class: 'r' },
        h('div', { class: 't' }, h('span', { text: i[0] }), h('span', { text: nf(i[1]) })),
        h('div', { class: 'bar' }, h('i', { style: 'width:' + (100 * i[1] / max) + '%;background:' + cor }))));
    });
  }
  function porSatelite(d) {
    var c = {}, ultimo = {};
    d.forEach(function (x) { c[x.sat] = (c[x.sat] || 0) + 1; ultimo[x.sat] = Math.max(ultimo[x.sat] || 0, x.t); });
    barras($('focos-sat'), Object.keys(c).map(function (k) { return [SAT[k] || k, c[k]]; })
      .sort(function (a, b) { return b[1] - a[1]; }), '#E65100');
    var corpo = limpar($('focos-sat-tab').querySelector('tbody'));
    var ks = Object.keys(c).sort(function (a, b) { return ultimo[b] - ultimo[a]; });
    if (!ks.length) { corpo.appendChild(h('tr', {}, h('td', { colspan: 3, text: 'Sem focos neste recorte.' }))); return; }
    ks.forEach(function (k) {
      corpo.appendChild(h('tr', {}, h('td', { text: SAT[k] || k }), h('td', { text: nf(c[k]) }),
        h('td', { text: manaus(ultimo[k]) + ' · ' + ha(Date.now() - ultimo[k]) })));
    });
  }
  function porDia(d) {
    var c = {}; d.forEach(function (x) { var k = diaManaus(x.t); c[k] = (c[k] || 0) + 1; });
    barras($('focos-dia'), Object.keys(c).sort().reverse().map(function (k) {
      return [k.slice(8) + '/' + k.slice(5, 7), c[k]]; }), '#C98A12');
  }

  function tabela(d) {
    var por = {};
    d.forEach(function (x) {
      var m = por[x.mun] || (por[x.mun] = { n: 0, frp: 0, max: null, dsc: [], rf: [] });
      m.n++; if (x.frp !== null) { m.frp += x.frp; m.max = m.max === null ? x.frp : Math.max(m.max, x.frp); }
      if (x.dsc !== null) m.dsc.push(x.dsc); if (x.rf !== null) m.rf.push(x.rf);
    });
    var corpo = limpar($('focos-tab').querySelector('tbody'));
    var linhas = Object.keys(por).sort(function (a, b) { return por[b].n - por[a].n; }).slice(0, 15);
    if (!linhas.length) { corpo.appendChild(h('tr', {}, h('td', { colspan: 6, text: 'Sem focos neste recorte.' }))); return; }
    linhas.forEach(function (k) {
      var m = por[k], dsc = media(m.dsc), rf = media(m.rf);
      corpo.appendChild(h('tr', {}, h('td', { text: k }), h('td', { text: nf(m.n) }), h('td', { text: nf(m.frp, 1) }),
        h('td', { text: m.max === null ? '—' : nf(m.max, 1) }), h('td', { text: dsc === null ? '—' : nf(dsc, 1) }),
        h('td', { text: rf === null ? '—' : nf(rf, 2) })));
    });
  }

  function corFrp(f) { return f === null ? '#8D6E63' : f >= 50 ? '#B71C1C' : f >= 15 ? '#E65100' : '#F2A93B'; }

  function mapaFocos(d) {
    if (!mapa) {
      mapa = L.map('mapa-focos', { scrollWheelZoom: false }).setView([-4.0, -64.5], 5);
      camadaPontos = L.layerGroup();
      RespirarMapas.configurar(mapa, { aviso: $('focos-mapa-aviso') });
      mapa.on('focus', function () { mapa.scrollWheelZoom.enable(); });
      mapa.on('blur', function () { mapa.scrollWheelZoom.disable(); });
    }
    if (camadaCalor) { mapa.removeLayer(camadaCalor); camadaCalor = null; }
    camadaPontos.clearLayers(); mapa.removeLayer(camadaPontos);
    if (modo === 'calor') {
      camadaCalor = L.heatLayer(d.map(function (x) { return [x.lat, x.lon, x.frp === null ? 0.5 : Math.min(1, 0.3 + x.frp / 60)]; }),
        { radius: 18, blur: 20, maxZoom: 9, minOpacity: 0.35 }).addTo(mapa);
    } else {
      d.forEach(function (x) {
        var m = L.circleMarker([x.lat, x.lon], { radius: 4, color: corFrp(x.frp), fillColor: corFrp(x.frp), fillOpacity: .7, weight: 1 });
        m.bindTooltip(x.mun + ' · ' + (SAT[x.sat] || x.sat) + ' · FRP ' + (x.frp === null ? '—' : nf(x.frp, 1) + ' MW'));
        m.addTo(camadaPontos);
      });
      camadaPontos.addTo(mapa);
    }
    if (d.length) mapa.fitBounds(d.map(function (x) { return [x.lat, x.lon]; }), { maxZoom: 8, padding: [20, 20] });
    setTimeout(function () { mapa.invalidateSize(); }, 50);
  }

  function alternar(id, attr, cb) {
    $(id).addEventListener('click', function (e) {
      var b = e.target.closest('button[data-' + attr + ']'); if (!b || !todos) return;
      Array.prototype.forEach.call($(id).children, function (x) {
        var on = x === b; x.classList.toggle('on', on); x.setAttribute('aria-pressed', String(on));
      });
      cb(b.getAttribute('data-' + attr)); desenhar();
    });
  }
  alternar('focos-janela', 'j', function (v) { janela = v; });
  alternar('focos-modo', 'm', function (v) { modo = v; });

  carregar();
  setInterval(function () { if (!document.hidden) carregar(); }, 5 * 60 * 1000);
  // Atualiza só os textos "há X min", sem mexer no mapa (o usuário pode estar com ele aberto).
  setInterval(function () { if (todos && !document.hidden) { atualizacao(); porSatelite(recorte()); } }, 60 * 1000);
})();
