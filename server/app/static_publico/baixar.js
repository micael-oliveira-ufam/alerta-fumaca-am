/* Cabeçalho "Baixe o aplicativo" (link + QR code) e seção "Baixar os dados (CSV)". */
(function () {
  'use strict';

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
  function mb(b) { return (b / 1048576).toLocaleString('pt-BR', { maximumFractionDigits: 1 }) + ' MB'; }

  // ------------------------------------------------------------- download do app
  function app() {
    fetch('/publico/app', { headers: { Accept: 'application/json' } })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (i) {
        var box = limpar($('app-conteudo'));
        if (!i.disponivel) {
          box.appendChild(h('p', { class: 'app-nd', text: 'O download do aplicativo ainda não está disponível neste endereço.' }));
          box.appendChild(h('p', { class: 'app-nota', text: 'Versão para iPhone: ainda não disponível.' }));
          return;
        }
        var data = new Date(i.atualizado_em);
        var meta = [i.plataforma + ' (APK)', i.versao ? 'versão ' + i.versao : null, mb(i.tamanho_bytes),
          isFinite(data) ? 'atualizado em ' + data.toLocaleDateString('pt-BR') : null].filter(Boolean).join(' · ');
        var qr = h('img', { src: '/publico/qr.svg?alvo=app', alt: 'QR code para baixar o aplicativo no celular', width: '132', height: '132' });
        var texto = h('div', { class: 'app-txt' },
          h('a', { class: 'btn', href: i.url, download: i.arquivo }, 'Baixar para Android'),
          h('p', { class: 'app-meta' }, h('code', { text: i.arquivo })),
          h('p', { class: 'app-meta', text: meta }),
          h('p', { class: 'app-nota', text: 'Aponte a câmera do celular para o QR code. Ao abrir o arquivo, o Android pode pedir permissão para instalar apps desta origem. Versão para iPhone: ainda não disponível.' }),
          (i.manual_url ? h('p', { class: 'app-nota' }, h('a', { href: i.manual_url, download: 'Manual-Instalacao-RespirAR-Amazonas.pdf' }, 'Baixar o manual de instalação (PDF, com imagens)')) : null),
          h('details', {}, h('summary', { text: 'Conferir a integridade (SHA-256)' }), h('code', { class: 'hash', text: i.sha256 })));
        var linha = h('div', { class: 'app-linha' }, h('div', { class: 'qr' }, qr), texto);
        limpar($('app-conteudo')).appendChild(linha);
      })
      .catch(function () {
        limpar($('app-conteudo')).appendChild(h('p', { class: 'app-nd', text: 'Não foi possível verificar o download agora. Tente recarregar a página.' }));
      });
  }

  // ----------------------------------------------------------------- CSV
  var CONJUNTOS = [
    ['sintomas', 'Sintomas relatados', 'leve, moderado e intenso, por sintoma', true],
    ['niveis', 'Nível de risco', 'respostas por nível calculado pelo app', true],
    ['serie_diaria', 'Respostas por dia', 'série diária (UTC)', true],
    ['bairros', 'Bairros de Manaus', 'só bairros com respostas suficientes', true],
    ['areas', 'Áreas do mapa (~1 km)', 'centro da área, respostas e pior nível', true],
    ['perfil_contexto', 'Perfil e situação', 'grupos de atenção, exposição e contexto', true],
    ['qualidade_ar', 'Qualidade do ar', 'índice, PM2,5 e PM10 por município (modelo)', false]
  ];

  function periodo() {
    var on = document.querySelector('#periodo button.on');
    return on ? on.getAttribute('data-dias') : '30';
  }
  function links() {
    var d = periodo(), rot = d === '1' ? 'últimas 24 h' : 'últimos ' + d + ' dias';
    $('csv-periodo').textContent = rot;
    var el = limpar($('csv-lista'));
    CONJUNTOS.forEach(function (c) {
      var href = '/publico/export.csv?conjunto=' + c[0] + (c[3] ? '&dias=' + d : '');
      el.appendChild(h('a', { class: 'csv-item', href: href, download: '' },
        h('b', { text: c[1] }), h('span', { text: c[2] + (c[3] ? ' · ' + rot : '') }), h('em', { text: 'Baixar CSV' })));
    });
  }
  $('periodo').addEventListener('click', function () { setTimeout(links, 0); }); // depois de publico.js marcar o botão
  links();
  app();
})();
