/* Seção "Focos de calor" do painel público. Lê só /focos (cópia em cache do WFS do INPE). */
(function () {
  'use strict';
  var SAT = {
    'AQUA_M-T': 'MODIS Aqua', 'TERRA_M-T': 'MODIS Terra', 'NOAA-20': 'NOAA-20 (VIIRS)',
    'NOAA-21': 'NOAA-21 (VIIRS)', 'NPP-375': 'Suomi NPP (VIIRS)', 'NPP-375D': 'Suomi NPP (VIIRS, dia)'
  };
  var MANAUS_MS = -4 * 3600 * 1000; // UTC-4, sem horário de verão
  var janela = 'hoje', modo = 'calor', todos = null, mapa = null, camadaPontos = null, camadaCalor = null;

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

  function carregar() {
    fetch('/focos?window=last48h&scope=amazonas', { headers: { Accept: 'application/json' } })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
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
    var ult = todos.reduce(function (m, x) { return Math.max(m, x.t); }, 0);
    $('focos-nota').textContent = 'Fonte: INPE, Programa Queimadas (TerraBrasilis), via cópia em cache do servidor' +
      (ult ? '. Detecção mais recente: ' + new Date(ult + MANAUS_MS).toISOString().replace('T', ' ').slice(8, 10) + '/' +
        new Date(ult + MANAUS_MS).toISOString().slice(5, 7) + ' às ' + new Date(ult + MANAUS_MS).toISOString().slice(11, 16) + ' (Manaus)' : '') +
      '. Um foco indica fogo detectado por satélite, com atraso de passagem e processamento; vários focos podem ser o mesmo incêndio.';
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
    var c = {}; d.forEach(function (x) { c[x.sat] = (c[x.sat] || 0) + 1; });
    barras($('focos-sat'), Object.keys(c).map(function (k) { return [SAT[k] || k, c[k]]; })
      .sort(function (a, b) { return b[1] - a[1]; }), '#E65100');
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
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 18, attribution: '© OpenStreetMap' }).addTo(mapa);
      camadaPontos = L.layerGroup();
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
})();
