'use strict';
// Painel do servidor. Todo texto vindo da API entra via textContent (nunca innerHTML).
(function () {
  const NIVEIS = [
    ['low', 'Baixo', 'var(--low)'], ['moderate', 'Moderado', 'var(--moderate)'],
    ['high', 'Alto', 'var(--high)'], ['emergency', 'Emergência', 'var(--emergency)'],
  ];
  const EXPOSICAO = { under1h: '< 1 h', between1and4h: '1 a 4 h', over4h: '> 4 h' };
  const PERFIL = { idoso: 'Idoso', gestante: 'Gestante', crianca: 'Criança',
    doenca_respiratoria: 'Doença respiratória', doenca_cardiaca: 'Doença cardíaca' };
  const GRAV = ['', 'leve', 'moderada', 'intensa'];
  const $ = (id) => document.getElementById(id);
  let token = '';
  try { token = sessionStorage.getItem('painel_token') || ''; } catch (_) {}
  let janelaNivel = '24h', ultimo = null, timer = null, qrUrl = null, mapa = null, camada = null;

  function el(tag, props, ...kids) {
    const e = document.createElement(tag);
    if (props) for (const [k, v] of Object.entries(props)) { if (k === 'text') e.textContent = v; else if (k === 'style') e.style.cssText = v; else e.setAttribute(k, v); }
    for (const k of kids) if (k != null) e.append(k);
    return e;
  }
  const fmtN = (n) => new Intl.NumberFormat('pt-BR').format(n);
  const fmtHora = (iso) => new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' });
  function atras(iso) {
    const s = Math.max(0, Math.round((Date.now() - new Date(iso)) / 1000));
    if (s < 60) return `há ${s} s`; if (s < 3600) return `há ${Math.floor(s / 60)} min`;
    if (s < 86400) return `há ${Math.floor(s / 3600)} h`; return `há ${Math.floor(s / 86400)} d`;
  }
  function dur(s) { const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
    return d ? `${d} d ${h} h` : h ? `${h} h ${m} min` : `${m} min`; }

  async function api(path) {
    const r = await fetch(path, { headers: token ? { 'X-Admin-Token': token } : {}, cache: 'no-store' });
    if (r.status === 401) { const e = new Error('auth'); e.auth = true; throw e; }
    if (r.status === 429) throw new Error('Muitas tentativas de token. Aguarde um minuto.');
    if (!r.ok) throw new Error(`Erro ${r.status}`);
    return r;
  }

  function barras(alvo, itens, total) {
    alvo.replaceChildren();
    if (!itens.length) { alvo.append(el('p', { class: 'nota', text: 'Sem dados no período.' })); return; }
    for (const it of itens) {
      const trilha = el('div', { class: 'trilha', title: it.dica || '' });
      for (const seg of it.segmentos) trilha.append(el('i', { style: `width:${total ? (100 * seg.valor / total) : 0}%;background:${seg.cor}` }));
      alvo.append(el('div', { class: 'linha' }, el('span', { class: 'rot', text: it.rotulo, title: it.rotulo }), trilha, el('span', { class: 'num', text: it.texto })));
    }
  }

  function desenhaNiveis(r) {
    const mapaN = janelaNivel === '24h' ? r.niveis_24h : r.niveis_30d;
    const total = Object.values(mapaN).reduce((a, b) => a + b, 0);
    barras($('niveis'), NIVEIS.map(([id, nome, cor]) => ({
      rotulo: nome, segmentos: [{ valor: mapaN[id] || 0, cor }],
      texto: `${fmtN(mapaN[id] || 0)}${total ? ` · ${(100 * (mapaN[id] || 0) / total).toFixed(0)}%` : ''}`,
    })), total);
  }

  function desenhaSintomas(r) {
    const itens = r.sintomas_30d.filter((s) => s.relatos > 0).slice(0, 11);
    barras($('sintomas'), itens.map((s) => ({
      rotulo: s.rotulo,
      segmentos: [{ valor: s.leve, cor: '#9CCC65' }, { valor: s.moderado, cor: '#FFB300' }, { valor: s.intenso, cor: '#D84315' }],
      texto: `${s.percentual.toFixed(1)}% · ${fmtN(s.relatos)}`,
      dica: `leve ${s.leve} · moderado ${s.moderado} · intenso ${s.intenso}` + (s.gravidade_media != null ? ` · média ${s.gravidade_media}` : ''),
    })), r.total_30d);
    if (itens.length) $('sintomas').append(el('p', { class: 'legenda', text: 'Barra = % das respostas do período · cores: leve, moderado, intenso · passe o mouse para a gravidade média.' }));
  }

  function desenhaPerfil(r) {
    barras($('perfil'), Object.entries(PERFIL).map(([id, nome]) => ({
      rotulo: nome, segmentos: [{ valor: r.perfil_30d[id] || 0, cor: 'var(--bar)' }],
      texto: fmtN(r.perfil_30d[id] || 0),
    })), r.total_30d);
  }

  function desenhaSerie(serie) {
    const W = 960, H = 150, pad = { l: 28, r: 6, t: 8, b: 20 };
    const max = Math.max(1, ...serie.map((s) => s.respostas));
    const bw = (W - pad.l - pad.r) / serie.length;
    const ns = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', `0 0 ${W} ${H}`); svg.setAttribute('preserveAspectRatio', 'none');
    svg.setAttribute('role', 'img'); svg.setAttribute('aria-label', 'Respostas por hora nas últimas 48 horas');
    const t = (x, y, s, anchor) => { const e = document.createElementNS(ns, 'text'); e.setAttribute('x', x); e.setAttribute('y', y); e.setAttribute('text-anchor', anchor || 'start'); e.textContent = s; return e; };
    svg.append(t(pad.l - 4, pad.t + 8, String(max), 'end'), t(pad.l - 4, H - pad.b, '0', 'end'));
    serie.forEach((s, i) => {
      const h = (H - pad.t - pad.b) * s.respostas / max;
      const r = document.createElementNS(ns, 'rect');
      r.setAttribute('class', 'b'); r.setAttribute('x', pad.l + i * bw + 1); r.setAttribute('width', Math.max(1, bw - 2));
      r.setAttribute('y', H - pad.b - h); r.setAttribute('height', h);
      const tt = document.createElementNS(ns, 'title'); tt.textContent = `${new Date(s.hora).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit' })} h: ${s.respostas}`;
      r.append(tt); svg.append(r);
      if (i % 6 === 0) svg.append(t(pad.l + i * bw, H - 6, new Date(s.hora).toLocaleTimeString('pt-BR', { hour: '2-digit' }) + 'h'));
    });
    $('serie').replaceChildren(svg);
  }

  function desenhaMapa(celulas) {
    if (typeof L === 'undefined') { $('mapa').replaceChildren(el('p', { class: 'nota', text: 'Mapa indisponível.' })); return; }
    if (!mapa) {
      mapa = L.map('mapa', { zoomControl: true }).setView([-3.12, -60.02], 6);
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 18, attribution: '© OpenStreetMap' }).addTo(mapa);
      camada = L.layerGroup().addTo(mapa);
      L.circleMarker([-3.12, -60.02], { radius: 4, color: '#1B5E20', weight: 2, fill: false }).bindTooltip('Manaus (referência)').addTo(mapa);
    }
    camada.clearLayers();
    const cor = Object.fromEntries(NIVEIS.map(([id, , c]) => [id, c]));
    const cores = { low: '#2E7D32', moderate: '#B7791F', high: '#E65100', emergency: '#B71C1C' };
    for (const c of celulas) {
      L.circleMarker([c.lat, c.lon], { radius: 6 + Math.min(14, 3 * Math.log2(c.respostas + 1)), color: cores[c.pior_nivel] || '#555', fillOpacity: .45, weight: 2 })
        .bindTooltip(`${c.respostas} resposta(s) · pior nível: ${c.pior_nivel}`).addTo(camada);
    }
  }

  function desenhaRecentes(lista) {
    const tb = $('recentes'); tb.replaceChildren();
    if (!lista.length) { tb.append(el('tr', null, el('td', { colspan: 8, class: 'nota', text: 'Nenhuma resposta ainda.' }))); return; }
    const cor = Object.fromEntries(NIVEIS.map(([id, nome, c]) => [id, [nome, c]]));
    for (const r of lista) {
      const [nome, c] = cor[r.nivel] || [r.nivel, '#555'];
      const sint = r.sintomas.map((s) => `${s.rotulo} (${GRAV[s.gravidade] || s.gravidade})`).join(', ') || '—';
      tb.append(el('tr', null,
        el('td', { class: 'n', text: String(r.id) }),
        el('td', { class: 'n', title: fmtHora(r.criado_em), text: atras(r.criado_em) }),
        el('td', null, el('span', { class: 'tag', style: `background:${c}`, text: nome })),
        el('td', { class: 'n', text: String(r.pontos) }),
        el('td', { text: EXPOSICAO[r.exposicao] || r.exposicao }),
        el('td', { text: sint }),
        el('td', { text: r.perfil.map((p) => PERFIL[p] || p).join(', ') || '—' }),
        el('td', { class: 'n', text: r.lat == null ? '—' : `${r.lat.toFixed(2)}, ${r.lon.toFixed(2)}` })));
    }
  }

  function desenhaServidor(s) {
    const dl = $('servidor'); dl.replaceChildren();
    const par = (k, v) => dl.append(el('dt', { text: k }), el('dd', { text: v }));
    par('Banco de dados', s.banco); par('Ativo há', dur(s.segundos_ativo));
    par('Painel protegido por token', s.token_exigido ? 'sim' : 'não (use só localmente)');
    par('Mínimo p/ estatísticas públicas', String(s.minimo_publico)); par('Mínimo por área no mapa público', String(s.minimo_celula));
    par('Limite de envios por min/origem', s.limite_envios_por_min ? String(s.limite_envios_por_min) : 'sem limite');
  }

  async function desenhaTunel(t) {
    $('tunel-url').textContent = t.url || '—';
    $('copiar').disabled = !t.url;
    $('tunel-estado').textContent = `Estado: ${t.estado}${t.aleatorio ? ' · link aleatório (muda se o túnel reiniciar)' : ''}`;
    if (!t.url) { $('qr').hidden = true; qrUrl = null; return; }
    if (qrUrl === t.url) return;
    try {
      const blob = await (await api('/api/qr.svg')).blob();
      const img = $('qr'); if (img.dataset.obj) URL.revokeObjectURL(img.dataset.obj);
      const obj = URL.createObjectURL(blob); img.dataset.obj = obj; img.src = obj; img.hidden = false; qrUrl = t.url;
    } catch (_) { $('qr').hidden = true; }
  }

  function desenha(d) {
    const s = d.servidor, r = d.resumo;
    $('pill-banco').textContent = `banco: ${s.banco}`; $('pill-banco').className = 'pill ' + (s.banco === 'ok' ? 'ok' : 'ruim');
    if (!r) return;
    $('k-total').textContent = fmtN(r.total); $('k-24h').textContent = fmtN(r.ultimas_24h); $('k-1h').textContent = fmtN(r.ultima_hora);
    $('k-ultima').textContent = r.ultima_resposta ? atras(r.ultima_resposta) : '—';
    desenhaNiveis(r); desenhaSintomas(r); desenhaPerfil(r); desenhaSerie(d.serie_horaria);
    desenhaMapa(d.mapa); desenhaRecentes(d.recentes); desenhaServidor(s); desenhaTunel(s.tunel);
  }

  function mostraLogin(msg) {
    $('login').hidden = false; $('conteudo').hidden = true;
    $('login-erro').hidden = !msg; $('login-erro').textContent = msg || '';
    if (timer) { clearTimeout(timer); timer = null; }
  }

  async function atualizar() {
    try {
      const d = await (await api('/api/painel?limite=20')).json();
      $('login').hidden = true; $('conteudo').hidden = false;
      ultimo = d; desenha(d);
      $('pill-atualizado').textContent = `atualizado ${new Date().toLocaleTimeString('pt-BR')}`; $('pill-atualizado').className = 'pill ok';
      if (mapa) mapa.invalidateSize();
    } catch (e) {
      if (e.auth) { mostraLogin(token ? 'Token inválido.' : ''); return; }
      $('pill-atualizado').textContent = `sem conexão com o painel (${e.message})`; $('pill-atualizado').className = 'pill ruim';
    }
    timer = setTimeout(atualizar, 5000);
  }

  $('login').addEventListener('submit', (ev) => {
    ev.preventDefault(); token = $('token').value.trim();
    try { sessionStorage.setItem('painel_token', token); } catch (_) {}
    atualizar();
  });
  $('copiar').addEventListener('click', async () => {
    const u = $('tunel-url').textContent;
    try { await navigator.clipboard.writeText(u); $('copiar').textContent = 'Copiado'; } catch (_) { $('copiar').textContent = 'Selecione e copie'; }
    setTimeout(() => { $('copiar').textContent = 'Copiar'; }, 1800);
  });
  document.querySelectorAll('.alternar button').forEach((b) => b.addEventListener('click', () => {
    janelaNivel = b.dataset.nivel; document.querySelectorAll('.alternar button').forEach((x) => x.classList.toggle('on', x === b));
    if (ultimo) desenhaNiveis(ultimo.resumo);
  }));
  document.addEventListener('visibilitychange', () => { if (!document.hidden && !timer) atualizar(); });
  atualizar();
})();
