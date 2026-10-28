/// Catálogo padrão de áreas e cargos usado como sugestão nos formulários
/// de candidatura.
///
/// Por que existe: `rh_area`/`rh_cargo` (RH-9) começam VAZIAS em toda
/// organização nova — o seed só aproveita o que já foi digitado antes. Sem
/// nada para sugerir, a página de carreiras vira dois campos de texto livre
/// e o banco de talentos enche de grafias diferentes para a mesma coisa
/// ("TI", "T.I.", "Tecnologia", "Informatica"), o que quebra filtro,
/// dashboard e o direcionamento de vagas.
///
/// Estas listas são só o ponto de partida da UI: o catálogo da própria
/// empresa sempre vem primeiro, e o candidato continua livre para digitar
/// algo fora da lista (mercado tem cargo demais para caber em preset).
library;

/// Áreas na ordem em que aparecem, cada uma com seus cargos mais comuns.
const Map<String, List<String>> kJobCatalog = {
  'Administrativo': [
    'Assistente Administrativo',
    'Auxiliar Administrativo',
    'Analista Administrativo',
    'Recepcionista',
    'Secretário(a)',
    'Auxiliar de Escritório',
    'Coordenador Administrativo',
  ],
  'Alimentação e Gastronomia': [
    'Auxiliar de Cozinha',
    'Cozinheiro(a)',
    'Chef de Cozinha',
    'Confeiteiro(a)',
    'Padeiro(a)',
    'Garçom / Garçonete',
    'Barista',
    'Nutricionista',
  ],
  'Atendimento ao Cliente': [
    'Atendente',
    'Operador de Telemarketing',
    'Analista de Suporte ao Cliente',
    'Assistente de SAC',
    'Supervisor de Atendimento',
    'Analista de Customer Success',
  ],
  'Comercial e Vendas': [
    'Vendedor(a)',
    'Consultor de Vendas',
    'Representante Comercial',
    'Executivo de Contas',
    'Assistente Comercial',
    'Analista Comercial',
    'Supervisor de Vendas',
    'Gerente Comercial',
  ],
  'Compras e Suprimentos': [
    'Assistente de Compras',
    'Analista de Compras',
    'Comprador(a)',
    'Analista de Suprimentos',
    'Coordenador de Compras',
  ],
  'Construção Civil': [
    'Ajudante Geral',
    'Pedreiro(a)',
    'Eletricista',
    'Encanador(a)',
    'Mestre de Obras',
    'Técnico em Edificações',
    'Engenheiro Civil',
    'Arquiteto(a)',
  ],
  'Contabilidade': [
    'Auxiliar Contábil',
    'Assistente Contábil',
    'Analista Contábil',
    'Contador(a)',
    'Analista Fiscal',
    'Coordenador Contábil',
  ],
  'Educação': [
    'Auxiliar de Sala',
    'Professor(a)',
    'Instrutor(a)',
    'Coordenador Pedagógico',
    'Pedagogo(a)',
    'Monitor(a)',
  ],
  'Engenharia': [
    'Estagiário de Engenharia',
    'Técnico(a) em Engenharia',
    'Engenheiro de Produção',
    'Engenheiro Mecânico',
    'Engenheiro Elétrico',
    'Engenheiro de Segurança do Trabalho',
    'Projetista',
  ],
  'Estética e Beleza': [
    'Cabeleireiro(a)',
    'Manicure / Pedicure',
    'Esteticista',
    'Maquiador(a)',
    'Barbeiro(a)',
    'Depilador(a)',
    'Recepcionista de Salão',
    'Designer de Sobrancelhas',
  ],
  'Financeiro': [
    'Auxiliar Financeiro',
    'Assistente Financeiro',
    'Analista Financeiro',
    'Analista de Contas a Pagar',
    'Analista de Contas a Receber',
    'Tesoureiro(a)',
    'Controller',
    'Gerente Financeiro',
  ],
  'Jurídico': [
    'Estagiário de Direito',
    'Assistente Jurídico',
    'Analista Jurídico',
    'Advogado(a)',
    'Paralegal',
    'Coordenador Jurídico',
  ],
  'Logística e Transporte': [
    'Auxiliar de Logística',
    'Estoquista',
    'Conferente',
    'Motorista',
    'Motoboy',
    'Operador de Empilhadeira',
    'Analista de Logística',
    'Supervisor de Logística',
  ],
  'Manutenção e Facilities': [
    'Auxiliar de Manutenção',
    'Técnico de Manutenção',
    'Eletricista de Manutenção',
    'Mecânico(a)',
    'Zelador(a)',
    'Auxiliar de Limpeza',
    'Porteiro(a)',
  ],
  'Marketing e Comunicação': [
    'Assistente de Marketing',
    'Analista de Marketing',
    'Social Media',
    'Designer Gráfico',
    'Redator(a)',
    'Analista de Mídias Digitais',
    'Videomaker',
    'Coordenador de Marketing',
  ],
  'Operações e Produção': [
    'Auxiliar de Produção',
    'Operador de Máquinas',
    'Montador(a)',
    'Inspetor de Qualidade',
    'Líder de Produção',
    'Supervisor de Produção',
    'Analista de Processos',
  ],
  'Recursos Humanos': [
    'Auxiliar de RH',
    'Assistente de RH',
    'Analista de Recrutamento e Seleção',
    'Analista de Departamento Pessoal',
    'Analista de Treinamento',
    'Business Partner de RH',
    'Coordenador de RH',
  ],
  'Saúde': [
    'Recepcionista de Clínica',
    'Auxiliar de Enfermagem',
    'Técnico de Enfermagem',
    'Enfermeiro(a)',
    'Fisioterapeuta',
    'Psicólogo(a)',
    'Farmacêutico(a)',
    'Biomédico(a)',
  ],
  'Segurança do Trabalho': [
    'Técnico de Segurança do Trabalho',
    'Engenheiro de Segurança do Trabalho',
    'Analista de SESMT',
    'Bombeiro Civil',
  ],
  'Tecnologia da Informação': [
    'Estagiário de TI',
    'Suporte Técnico / Help Desk',
    'Desenvolvedor Front-end',
    'Desenvolvedor Back-end',
    'Desenvolvedor Full-stack',
    'Desenvolvedor Mobile',
    'Analista de Sistemas',
    'Analista de Dados',
    'Analista de Infraestrutura',
    'Analista de Segurança da Informação',
    'QA / Analista de Testes',
    'DevOps',
    'UX/UI Designer',
    'Product Owner',
    'Tech Lead',
  ],
  'Turismo e Hotelaria': [
    'Recepcionista de Hotel',
    'Camareiro(a)',
    'Agente de Viagens',
    'Guia de Turismo',
    'Governanta',
  ],
  'Varejo e Loja': [
    'Operador de Caixa',
    'Repositor(a)',
    'Vendedor de Loja',
    'Fiscal de Loja',
    'Visual Merchandiser',
    'Encarregado de Loja',
    'Gerente de Loja',
  ],
};

/// Todas as áreas do catálogo padrão, na ordem de exibição.
List<String> get kDefaultAreas => kJobCatalog.keys.toList();

/// Todos os cargos do catálogo padrão, sem repetição.
List<String> get kDefaultCargos {
  final vistos = <String>{};
  final out = <String>[];
  for (final cargos in kJobCatalog.values) {
    for (final c in cargos) {
      if (vistos.add(_chave(c))) out.add(c);
    }
  }
  out.sort();
  return out;
}

/// Cargos sugeridos para [area].
///
/// A área digitada raramente bate letra a letra com a do catálogo (o
/// candidato escreve "TI", o preset diz "Tecnologia da Informação"), então
/// a busca é tolerante: ignora acento/caixa e aceita que um contenha o
/// outro. Sem correspondência, devolve lista vazia — quem chama decide o
/// fallback.
List<String> cargosDaArea(String? area) {
  final alvo = _chave(area ?? '');
  if (alvo.isEmpty) return const [];
  for (final entry in kJobCatalog.entries) {
    final chave = _chave(entry.key);
    if (chave == alvo) return entry.value;
  }
  for (final entry in kJobCatalog.entries) {
    final chave = _chave(entry.key);
    if (chave.contains(alvo) || alvo.contains(chave)) return entry.value;
  }
  return const [];
}

/// Junta listas de sugestões preservando a ordem e removendo repetições
/// que só diferem em acento, caixa ou pontuação. A primeira lista tem
/// prioridade — é sempre o catálogo da própria empresa.
List<String> mesclarSugestoes(List<List<String>> listas) {
  final vistos = <String>{};
  final out = <String>[];
  for (final lista in listas) {
    for (final item in lista) {
      final v = item.trim();
      if (v.isEmpty) continue;
      if (vistos.add(_chave(v))) out.add(v);
    }
  }
  return out;
}

/// Chave de comparação: minúsculas, sem acento e sem pontuação.
String _chave(String s) {
  final semAcento = _traduzirAcentos(s.toLowerCase());
  return semAcento.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

const _acentos = {
  'á': 'a',
  'à': 'a',
  'ã': 'a',
  'â': 'a',
  'ä': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'õ': 'o',
  'ô': 'o',
  'ö': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ç': 'c',
  'ñ': 'n',
};

String _traduzirAcentos(String s) {
  final b = StringBuffer();
  for (final ch in s.split('')) {
    b.write(_acentos[ch] ?? ch);
  }
  return b.toString();
}
