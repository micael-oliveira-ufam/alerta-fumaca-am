/* Painel público do RespirAR Amazonas. Só lê /publico/painel (dados agregados). Sem senha. */
(function () {
  'use strict';

  var NIVEIS = [
    ['low', 'Baixo', '#2E7D32'],
    ['moderate', 'Moderado', '#C98A12'],
    ['high', 'Alto', '#E65100'],
    ['emergency', 'Procure atendimento', '#B71C1C']
  ];
  var EXPOSICAO = { under1h: 'Menos de 1 h', between1and4h: '1 a 4 horas', over4h: 'Mais de 4 horas' };
  var PERFIL = {
    idoso: 'Idosos', gestante: 'Gestantes', crianca: 'Crianças',
    doenca_respiratoria: 'Doença respiratória', doenca_cardiaca: 'Doença cardíaca'
  };
  var CTX_BOOL = {
    fumaca_visivel: 'Havia fumaça visível',
    atividade_fisica_ar_livre: 'Atividade física ao ar livre',
    ar_filtrado: 'Ambiente com ar filtrado',
    trabalho_ar_livre: 'Trabalha ao ar livre',
    imunologica: 'Imunidade reduzida',
    medicacao_a_mao: 'Tem medicação à mão',
    medicacao_nao_alivia: 'Medicação não alivia',
    piorando: 'Sintomas piorando'
  };
  var CTX_CAT = {
    local: ['Onde estava', {
      ar_livre: 'Ao ar livre', casa_janelas_abertas: 'Em casa, janelas abertas',
      casa_janelas_fechadas: 'Em casa, janelas fechadas'
    }],
    mascara: ['Máscara usada', {
      nao_saiu: 'Não saiu', nao: 'Sem máscara', cirurgica_pano: 'Cirúrgica ou de pano', pff2_n95: 'PFF2/N95'
    }]
  };

  var dias = 30, ordem = 'relatos', dados = null, mapa = null, camada = null, ultimoOk = 0, timer = null;

  function $(id) { return document.getElementById(id); }
  function h(tag, attrs) {
    var el = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) {
      if (k === 'text') el.textContent = attrs[k];
      else if (k === 'style') el.setAttribute('style', attrs[k]);
      else el.setAttribute(k, attrs[k]);
    });
    for (var i = 2; i < arguments.length; i++) {
      var c = arguments[i];
      if (c == null) continue;
      el.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
    return el;
  }
  function limpar(el) { while (el.firstChild) el.removeChild(el.firstChild); return el; }
  function nf(n) { return Number(n).toLocaleString('pt-BR'); }
  function pct(n, total) { return total ? (100 * n / total).toLocaleString('pt-BR', { maximumFractionDigits: 1 }) + '%' : '—'; }
  function svgNS(tag, attrs) {
    var el = document.createElementNS('http://www.w3.org/2000/svg', tag);
    Object.keys(attrs || {}).forEach(function (k) { el.setAttribute(k, attrs[k]); });
    return el;
  }
  function periodoTxt() { return dias === 1 ? 'nas últimas 24 horas' : 'nos últimos ' + dias + ' dias'; }

  /* ------------------------------------------------------------------ dados */
  function carregar() {
    fetch('/publico/painel?dias=' + dias, { headers: { Accept: 'application/json' } })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (d) { dados = d; ultimoOk = Date.now(); desenhar(); })
      .catch(function () { estado('erro', 'Sem conexão com o servidor. Tentando de novo…'); });
  }
  function estado(tipo, txt) {
    var el = $('live'); el.className = 'live ' + tipo; $('live-txt').textContent = txt;
  }
  function atualizarRelogio() {
    if (!ultimoOk) return;
    var s = Math.round((Date.now() - ultimoOk) / 1000);
    estado('ok', 'Ao vivo · atualizado há ' + (s < 60 ? s + ' s' : Math.floor(s / 60) + ' min'));
  }

  /* ----------------------------------------------------------------- desenho */
  function desenhar() {
    $('conteudo').setAttribute('aria-busy', 'false');
    $('min-pub').textContent = dados.minimo_para_divulgar;
    $('min-area').textContent = dados.minimo_por_area;
    $('baixar').setAttribute('href', '/publico/painel?dias=' + dias);
    atualizarRelogio();
    avisoSeInsuficiente();
    kpis();
    sintomas();
    niveis();
    serie();
    desenharMapa();
    bairros();
    perfil();
    exposicao();
    contexto();
  }

  function avisoSeInsuficiente() {
    var a = $('aviso');
    if (dados.suficiente) { a.hidden = true; return; }
    limpar(a);
    a.appendChild(h('b', { text: 'Ainda coletando dados' }));
    a.appendChild(document.createTextNode(
      'Há ' + nf(dados.total_respostas) + ' resposta(s) ' + periodoTxt() + '. Os gráficos aparecem a partir de ' +
      dados.minimo_para_divulgar + ' respostas, para que ninguém possa ser identificado em amostras muito pequenas.'));
    var prog = h('div', { class: 'prog', role: 'progressbar', 'aria-valuemin': 0,
      'aria-valuemax': dados.minimo_para_divulgar, 'aria-valuenow': dados.total_respostas },
      h('i', { style: 'width:' + Math.min(100, 100 * dados.total_respostas / dados.minimo_para_divulgar) + '%' }));
    a.appendChild(prog);
    a.hidden = false;
  }

  function kpi(rotulo, valor, detalhe, cor, texto) {
    return h('div', { class: 'kpi', style: '--k:' + cor },
      h('div', { class: 'l', text: rotulo }),
      h('div', { class: 'v' + (texto ? ' txt' : ''), text: valor }),
      h('div', { class: 'd', text: detalhe }));
  }
  function kpis() {
    var el = limpar($('kpis')), d = dados, t = d.total_respostas;
    el.appendChild(kpi('Respostas', nf(t), periodoTxt(), '#2E7D32'));
    if (!d.suficiente) return;
    var alto = (d.niveis.high || 0) + (d.niveis.emergency || 0);
    el.appendChild(kpi('Risco alto ou atendimento', nf(alto), pct(alto, t) + ' das respostas', '#E65100'));
    var top = d.sintomas[0];
    el.appendChild(kpi('Sintoma mais relatado', top ? top.rotulo : '—',
      top ? pct(top.relatos, t) + ' das respostas (' + nf(top.relatos) + ')' : 'sem relatos', '#9CCC65', true));
    el.appendChild(kpi('Áreas no mapa', nf(d.mapa.celulas.length),
      'com ' + d.minimo_por_area + '+ respostas', '#1565C0'));
  }

  function sintomas() {
    var lista = limpar($('rank')), d = dados;
    $('sintomas-sub').textContent = d.suficiente
      ? 'Percentual das respostas ' + periodoTxt() + ' em que o sintoma foi marcado (leve, moderado ou intenso).'
      : 'Disponível quando houver respostas suficientes.';
    if (!d.suficiente) { lista.appendChild(h('li', { class: 'vazio', text: 'Aguardando mais respostas.' })); return; }
    var itens = d.sintomas.filter(function (s) { return s.relatos > 0; });
    if (!itens.length) { lista.appendChild(h('li', { class: 'vazio', text: 'Nenhum sintoma relatado no período.' })); return; }
    itens = itens.slice().sort(function (a, b) {
      if (ordem === 'gravidade') return (b.gravidade_media || 0) - (a.gravidade_media || 0) || b.relatos - a.relatos;
      return b.relatos - a.relatos || a.rotulo.localeCompare(b.rotulo);
    });
    var max = dados.total_respostas || 1; // a barra inteira = 100% das respostas
    var barras = [];
    itens.forEach(function (s, i) {
      var l = h('b', { class: 'l' }), m = h('b', { class: 'm' }), n = h('b', { class: 'i' });
      var larg = function (v) { return (100 * v / max) + '%'; };
      barras.push([l, larg(s.leve)], [m, larg(s.moderado)], [n, larg(s.intenso)]);
      var det = nf(s.leve) + ' leve · ' + nf(s.moderado) + ' moderado · ' + nf(s.intenso) + ' intenso' +
        (s.gravidade_media ? ' · gravidade média ' + s.gravidade_media.toLocaleString('pt-BR') + ' de 3' : '');
      lista.appendChild(h('li', { class: 'rk' + (i < 3 ? ' top' : '') },
        h('span', { class: 'pos', text: String(i + 1) }),
        h('span', { class: 'nome', text: s.rotulo }),
        h('span', { class: 'pct' }, document.createTextNode(s.percentual.toLocaleString('pt-BR') + '%'),
          h('small', { text: nf(s.relatos) + ' relatos' })),
        h('div', { class: 'barra', role: 'img', 'aria-label': s.rotulo + ': ' + det }, l, m, n),
        h('span', { class: 'det', text: det })));
    });
    requestAnimationFrame(function () { requestAnimationFrame(function () {
      barras.forEach(function (p) { p[0].style.width = p[1]; });
    }); });
  }

  function niveis() {
    var box = limpar($('donut')), d = dados;
    if (!d.suficiente) { box.appendChild(h('p', { class: 'vazio', text: 'Aguardando mais respostas.' })); return; }
    var total = NIVEIS.reduce(function (s, n) { return s + (d.niveis[n[0]] || 0); }, 0);
    var svg = svgNS('svg', { viewBox: '0 0 120 120', role: 'img', 'aria-label': 'Distribuição dos níveis de risco' });
    var R = 46, C = 2 * Math.PI * R, off = 0;
    svg.appendChild(svgNS('circle', { cx: 60, cy: 60, r: R, fill: 'none', stroke: 'currentColor', 'stroke-opacity': .1, 'stroke-width': 16 }));
    NIVEIS.forEach(function (n) {
      var v = d.niveis[n[0]] || 0; if (!v || !total) return;
      var len = C * v / total;
      svg.appendChild(svgNS('circle', { cx: 60, cy: 60, r: R, fill: 'none', stroke: n[2], 'stroke-width': 16,
        'stroke-dasharray': len + ' ' + (C - len), 'stroke-dashoffset': -off, transform: 'rotate(-90 60 60)' }));
      off += len;
    });
    var tn = svgNS('text', { x: 60, y: 62, 'text-anchor': 'middle', class: 'centro-n' }); tn.textContent = nf(total);
    var tt = svgNS('text', { x: 60, y: 76, 'text-anchor': 'middle', class: 'centro-t' }); tt.textContent = 'respostas';
    svg.appendChild(tn); svg.appendChild(tt);
    var leg = h('ul', { class: 'dleg' });
    NIVEIS.forEach(function (n) {
      var v = d.niveis[n[0]] || 0;
      leg.appendChild(h('li', {}, h('i', { style: 'background:' + n[2] }), n[1], h('b', { text: nf(v) }), h('em', { text: pct(v, total) })));
    });
    box.appendChild(svg); box.appendChild(leg);
  }

  function serie() {
    var box = limpar($('serie')), d = dados;
    if (!d.suficiente) { box.appendChild(h('p', { class: 'vazio', text: 'Aguardando mais respostas.' })); return; }
    if (!d.serie_diaria.length) { box.appendChild(h('p', { class: 'vazio', text: 'Nenhuma resposta neste período ainda.' })); return; }
    // Preenche os dias sem resposta com zero, do primeiro dia com dado até hoje.
    var mapaDias = {}; d.serie_diaria.forEach(function (x) { mapaDias[x.dia] = x.respostas; });
    var fim = new Date(d.gerado_em.slice(0, 10) + 'T00:00:00Z');
    var ini = new Date(Math.max(new Date(d.serie_diaria[0].dia + 'T00:00:00Z').getTime(), fim.getTime() - (dias - 1) * 864e5));
    var pts = [];
    for (var t = ini.getTime(); t <= fim.getTime(); t += 864e5) {
      var k = new Date(t).toISOString().slice(0, 10); pts.push([k, mapaDias[k] || 0]);
    }
    var W = 520, H = 190, L = 30, B = 22, T = 8, max = Math.max(4, Math.max.apply(null, pts.map(function (p) { return p[1]; })));
    var svg = svgNS('svg', { viewBox: '0 0 ' + W + ' ' + H, role: 'img', 'aria-label': 'Respostas por dia' });
    [0, .5, 1].forEach(function (f) {
      var y = T + (H - B - T) * (1 - f);
      svg.appendChild(svgNS('line', { x1: L, x2: W, y1: y, y2: y, class: 'grade' }));
      var tx = svgNS('text', { x: L - 6, y: y + 3, 'text-anchor': 'end', class: 'eixo' }); tx.textContent = Math.round(max * f); svg.appendChild(tx);
    });
    var bw = (W - L) / pts.length, gap = Math.min(4, bw * .25);
    pts.forEach(function (p, i) {
      var hgt = (H - B - T) * p[1] / max, x = L + i * bw + gap / 2;
      var r = svgNS('rect', { x: x, y: H - B - hgt, width: Math.max(1, bw - gap), height: Math.max(p[1] ? 1 : 0, hgt), rx: Math.min(4, bw / 3), class: 'b' });
      var tl = svgNS('title'); tl.textContent = p[0].split('-').reverse().join('/') + ': ' + p[1] + ' resposta(s)'; r.appendChild(tl);
      svg.appendChild(r);
    });
    var passo = Math.max(1, Math.ceil(pts.length / 6));
    pts.forEach(function (p, i) {
      if (i % passo && i !== pts.length - 1) return;
      var ult = i === pts.length - 1;
      var tx = svgNS('text', { x: ult ? W - 2 : L + i * bw + bw / 2, y: H - 6, 'text-anchor': ult ? 'end' : 'middle', class: 'eixo' });
      tx.textContent = p[0].slice(8) + '/' + p[0].slice(5, 7); svg.appendChild(tx);
    });
    box.appendChild(svg);
  }

  function desenharMapa() {
    var d = dados;
    if (!mapa) {
      mapa = L.map('mapa', { zoomControl: true, scrollWheelZoom: false }).setView([-3.12, -60.02], 5);
      camada = L.layerGroup().addTo(mapa);
      RespirarMapas.configurar(mapa, { aviso: $('mapa-aviso'), extras: { 'Áreas com relatos (app)': camada } });
      mapa.on('focus', function () { mapa.scrollWheelZoom.enable(); });
      mapa.on('blur', function () { mapa.scrollWheelZoom.disable(); });
    }
    camada.clearLayers();
    var cel = d.suficiente ? d.mapa.celulas : [];
    var cores = {}; NIVEIS.forEach(function (n) { cores[n[0]] = n[2]; });
    var rot = {}; NIVEIS.forEach(function (n) { rot[n[0]] = n[1]; });
    var pontos = [];
    cel.forEach(function (c) {
      var m = L.circleMarker([c.lat, c.lon], {
        radius: 7 + Math.min(16, 3.2 * Math.log2(c.respostas + 1)),
        color: cores[c.pior_nivel] || '#555', fillColor: cores[c.pior_nivel] || '#555', fillOpacity: .45, weight: 2
      });
      m.bindTooltip(c.respostas + ' resposta(s) · pior nível: ' + (rot[c.pior_nivel] || c.pior_nivel));
      m.addTo(camada); pontos.push([c.lat, c.lon]);
    });
    if (pontos.length) mapa.fitBounds(pontos, { maxZoom: 9, padding: [30, 30] });
    $('mapa-nota').textContent = !d.suficiente ? 'O mapa aparece quando houver respostas suficientes.'
      : cel.length ? cel.length + ' área(s) com ' + d.minimo_por_area + ' ou mais respostas nas últimas ' + d.mapa.horas + ' h. Os pontos mostram o centro da área de ~1 km, nunca o local exato de alguém.'
      : 'Nenhuma área tem respostas suficientes nas últimas ' + d.mapa.horas + ' h para ser mostrada.';
    setTimeout(function () { mapa.invalidateSize(); }, 50);
  }

  function bairros() {
    var box = limpar($('bairros')), b = dados.bairros, nota = $('bairros-nota');
    if (!b || !b.bairros.length) {
      var vazio = h('div', { class: 'mini' });
      vazio.appendChild(h('p', { class: 'vazio', text: 'Ainda não há bairros com respostas suficientes (mínimo ' +
        (b ? b.minimo_por_bairro : 3) + ' por bairro).' }));
      box.appendChild(vazio);
      nota.textContent = b && b.areas_em_consulta ? 'Identificando bairros de ' + b.areas_em_consulta + ' área(s)…' : (b ? b.fonte : '');
      return;
    }
    var max = Math.max.apply(null, b.bairros.map(function (x) { return x.respostas; }));
    var lista = h('ol', { class: 'rank' });
    b.bairros.forEach(function (x, i) {
      lista.appendChild(h('li', { class: 'rk' + (i < 3 ? ' top' : '') },
        h('span', { class: 'pos', text: String(i + 1) }),
        h('span', { class: 'nome', text: x.bairro }),
        h('span', { class: 'pct' }, document.createTextNode(nf(x.respostas)), h('small', { text: 'respostas' })),
        h('div', { class: 'barra', role: 'img', 'aria-label': x.bairro + ': ' + x.respostas + ' respostas' },
          h('b', { class: 'm', style: 'width:' + (100 * x.respostas / max) + '%' })),
        h('span', { class: 'det', text: x.alto_ou_emergencia === null ? 'Risco alto: poucos casos para detalhar' :
          nf(x.alto_ou_emergencia) + ' com risco alto ou atendimento' })));
    });
    box.appendChild(lista);
    nota.textContent = (b.areas_em_consulta ? b.areas_em_consulta + ' área(s) ainda sendo identificadas. ' : '') + b.fonte;
  }

  function barra(rotulo, n, total) {
    var oculto = n === null;
    return h('div', { class: 'r' },
      h('div', { class: 't' }, h('span', { text: rotulo }),
        h('span', { text: oculto ? 'menos de ' + dados.minimo_por_area : nf(n) + ' · ' + pct(n, total) })),
      h('div', { class: 'bar' }, h('i', { style: 'width:' + (oculto || !total ? 0 : 100 * n / total) + '%' })));
  }
  function perfil() {
    var box = limpar($('perfil')), d = dados;
    if (!d.suficiente) { box.appendChild(h('p', { class: 'vazio', text: 'Aguardando mais respostas.' })); return; }
    var mini = h('div', { class: 'mini' });
    Object.keys(PERFIL).forEach(function (k) { mini.appendChild(barra(PERFIL[k], d.perfil[k], d.total_respostas)); });
    box.appendChild(mini);
  }
  function exposicao() {
    var box = limpar($('exposicao')), d = dados;
    if (!d.suficiente) { box.appendChild(h('p', { class: 'vazio', text: 'Aguardando mais respostas.' })); return; }
    var mini = h('div', { class: 'mini' });
    Object.keys(EXPOSICAO).forEach(function (k) { mini.appendChild(barra(EXPOSICAO[k], d.exposicao[k], d.total_respostas)); });
    box.appendChild(mini);
  }
  function contexto() {
    var box = limpar($('contexto')), d = dados;
    if (!d.suficiente) { box.appendChild(h('p', { class: 'vazio', text: 'Aguardando mais respostas.' })); return; }
    var mini = h('div', { class: 'mini' }), algum = false;
    Object.keys(CTX_CAT).forEach(function (campo) {
      var c = d.contexto[campo]; if (!c) return; algum = true;
      mini.appendChild(h('h3', { text: CTX_CAT[campo][0] }));
      Object.keys(CTX_CAT[campo][1]).forEach(function (v) {
        if (c.valores[v] === undefined) return;
        mini.appendChild(barra(CTX_CAT[campo][1][v], c.valores[v], c.respondeu));
      });
    });
    var temBool = Object.keys(CTX_BOOL).some(function (k) { return d.contexto[k]; });
    if (temBool) {
      mini.appendChild(h('h3', { text: 'Respondeu "sim"' }));
      Object.keys(CTX_BOOL).forEach(function (campo) {
        var c = d.contexto[campo]; if (!c) return; algum = true;
        var sim = c.valores.sim === undefined ? 0 : c.valores.sim;
        var oculto = sim === null || (sim === 0 && false);
        mini.appendChild(barra(CTX_BOOL[campo], oculto ? null : sim, c.respondeu));
      });
    }
    if (!algum) { box.appendChild(h('p', { class: 'vazio', text: 'Poucas respostas a estas perguntas opcionais.' })); return; }
    box.appendChild(mini);
  }

  /* ------------------------------------------------------------------- eventos */
  $('periodo').addEventListener('click', function (e) {
    var b = e.target.closest('button[data-dias]'); if (!b) return;
    dias = Number(b.getAttribute('data-dias'));
    Array.prototype.forEach.call($('periodo').children, function (x) {
      var on = x === b; x.classList.toggle('on', on); x.setAttribute('aria-pressed', String(on));
    });
    estado('', 'Atualizando…'); carregar();
  });
  $('ordem').addEventListener('click', function (e) {
    var b = e.target.closest('button[data-ordem]'); if (!b || !dados) return;
    ordem = b.getAttribute('data-ordem');
    Array.prototype.forEach.call($('ordem').children, function (x) {
      var on = x === b; x.classList.toggle('on', on); x.setAttribute('aria-pressed', String(on));
    });
    sintomas();
  });

  carregar();
  timer = setInterval(function () { if (!document.hidden) carregar(); }, 15000);
  setInterval(atualizarRelogio, 1000);
  document.addEventListener('visibilitychange', function () { if (!document.hidden) carregar(); });
})();
