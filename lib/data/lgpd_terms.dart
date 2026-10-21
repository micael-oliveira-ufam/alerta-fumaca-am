/// Termo de uso e tratamento de dados (LGPD, Lei nº 13.709/2018).
///
/// Ao alterar QUALQUER texto abaixo, incremente [kLgpdTermsVersion]: o app volta a
/// exibir o termo a quem aceitou a versão anterior.
///
/// ATENÇÃO (a confirmar pela instituição, não é aconselhamento jurídico): o texto foi
/// redigido pela equipe técnica a partir da LGPD e do comportamento real do app. Antes
/// de divulgar ao público, a UFAM/FCF deve revisar, designar formalmente o controlador
/// e o canal do encarregado (art. 41) e definir o prazo de retenção.
const kLgpdTermsVersion = '1.3';

class TermsSection {
  const TermsSection(this.title, this.paragraphs);
  final String title;
  final List<String> paragraphs;
}

const kLgpdSummary =
    'Este aplicativo trata informações de saúde (sintomas). Em resumo: tudo fica no seu '
    'aparelho, a menos que você aceite compartilhar ao final do questionário; o envio é anônimo, '
    'opcional e você pode recusar sem perder nenhuma função do app.';

const kLgpdSections = <TermsSection>[
  TermsSection('1. Quem somos e para que serve', [
    'O RespirAR Amazonas é um projeto acadêmico da Faculdade de Ciências Farmacêuticas (FCF) '
        'da Universidade Federal do Amazonas (UFAM). Oferece orientação educativa e triagem de '
        'sintomas em episódios de fumaça. Não faz diagnóstico e não substitui atendimento médico.',
    'Controlador dos dados enviados: equipe do projeto (FCF/UFAM), representada pelos '
        'desenvolvedores listados em "Sobre o aplicativo".',
  ]),
  TermsSection('2. Que dados tratamos', [
    'Dados de saúde (dado pessoal sensível, art. 5º, II): os sintomas e as gravidades que você '
        'marca, seu perfil de vulnerabilidade (idoso, gestante, criança, doença respiratória ou '
        'cardíaca), o tempo de exposição à fumaça e o nível de risco calculado.',
    'Localização aproximada (opcional): arredondada para cerca de 1 km, nunca a posição exata. '
        'Ela só é enviada se você aceitar compartilhar as respostas e permitir o acesso à '
        'localização do aparelho.',
    'Não coletamos nome, telefone, e-mail, CPF, conta, identificador do aparelho nem endereço IP '
        '(o servidor não grava o IP). Cada envio recebe um código aleatório que serve só para '
        'evitar duplicidade se o envio for repetido.',
  ]),
  TermsSection('3. Para que usamos (finalidades)', [
    'Neste aparelho: calcular seu nível de risco, mostrar o histórico e as estatísticas locais.',
    'Se você aceitar compartilhar as respostas: formar estatísticas coletivas (sintomas mais '
        'relatados, níveis de risco, perfil, exposição), um mapa de áreas afetadas e o ranking de '
        'bairros de Manaus, para estudos epidemiológicos e saúde pública em caráter educativo. '
        'Esses resultados agregados ficam abertos a qualquer pessoa na plataforma online.',
    'Para indicar o bairro, a área aproximada (~1 km) de cada resposta é consultada em um serviço '
        'público de mapas (Nominatim/OpenStreetMap). Só a área arredondada é enviada a esse serviço, '
        'nunca suas respostas.',
    'Não vendemos, não compartilhamos com fins comerciais e não usamos os dados para publicidade, '
        'seguros, crédito, decisões sobre emprego ou qualquer fim discriminatório.',
  ]),
  TermsSection('4. Base legal: seu consentimento, separado por finalidade', [
    'Para dados de saúde, usamos o seu consentimento específico e destacado (art. 11, I). '
        'Ao final de cada questionário, o app pergunta se você quer compartilhar aquelas respostas '
        'para estudos epidemiológicos. A decisão vale só para aquele questionário:',
    '• "Sim": as respostas anônimas são enviadas ao servidor e, se você permitir o acesso à '
        'localização, a área aproximada (~1 km) vai junto;\n'
        '• "Não": nada sai do aparelho.',
    'Aceitar este termo apenas confirma que você leu as regras. Ele NÃO autoriza nenhum envio. '
        'O aplicativo funciona normalmente sem enviar nada.',
  ]),
  TermsSection('5. Como protegemos', [
    'Minimização: só pedimos o que a finalidade exige.',
    'Anonimização: não há identificador pessoal; a localização é generalizada a ~1 km.',
    'Divulgação: as estatísticas agregadas (gráficos) são públicas mesmo com poucas respostas, '
        'porque não trazem nome nem contato; já uma área do mapa só aparece com ao menos 3 '
        'respostas, e contagens muito pequenas de perfil aparecem como "menos de 3", para que '
        'ninguém seja reconhecido por uma amostra pequena.',
    'Limitação honesta: nenhum sistema é totalmente seguro, e dados anonimizados podem, em '
        'situações raras (por exemplo, poucas pessoas numa área pequena), permitir inferências. '
        'Por isso a localização é opcional.',
  ]),
  TermsSection('6. Seus direitos e o que NÃO conseguimos fazer', [
    'Você pode, a qualquer momento: responder "Não" ao compartilhamento, negar a permissão de '
        'localização e apagar tudo o que o app guarda neste aparelho limpando os dados do app '
        'nas configurações do sistema (ou desinstalando-o).',
    'Por serem anônimos, os envios JÁ FEITOS não podem ser localizados nem apagados depois, '
        'pois não sabemos quais são seus. Se isso não for aceitável para você, não autorize o envio.',
    'Recusar o compartilhamento vale para os próximos questionários. Dúvidas e pedidos sobre a LGPD: fale com '
        'os desenvolvedores indicados em "Sobre o aplicativo".',
  ]),
  TermsSection('7. Retenção e mudanças', [
    'Os registros anônimos são mantidos enquanto durar o projeto de pesquisa; o prazo final será '
        'definido pela instituição e informado em nova versão deste termo.',
    'Se este termo mudar, pediremos sua leitura novamente. Versão atual: $kLgpdTermsVersion.',
  ]),
];

const kLgpdAcceptLabel = 'Li e entendi';
const kLgpdCheckboxLabel =
    'Li o termo e entendi que o envio de dados é opcional, anônimo e que envios já feitos não podem ser apagados.';
