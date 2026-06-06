import 'package:flutter/material.dart';

import 'public_legal_page.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PublicLegalPage(
      title: 'Política de Privacidade',
      description:
          'Esta política explica como o Tatuzin coleta, utiliza, armazena, '
          'compartilha e protege dados pessoais e comerciais durante o uso do '
          'aplicativo e do painel web.',
      sections: [
        LegalSection(
          title: '1. Responsável pelo tratamento',
          content: [
            LegalParagraph(
              'O tratamento dos dados relacionados ao Tatuzin é realizado por '
              '[NOME/RAZÃO SOCIAL], [CNPJ, se houver]. Para assuntos de '
              'privacidade e proteção de dados, entre em contato pelo e-mail '
              '[E-MAIL DE PRIVACIDADE].',
            ),
          ],
        ),
        LegalSection(
          title: '2. Dados coletados',
          content: [
            LegalParagraph(
              'Conforme os recursos utilizados e as informações fornecidas, '
              'o Tatuzin pode tratar:',
            ),
            LegalBulletList([
              'nome, e-mail, telefone, endereço e documento, quando informado;',
              'dados da empresa e de usuários ou funcionários vinculados;',
              'dados de clientes, fornecedores, produtos e estoque;',
              'vendas, gastos, compras, caixa, fiado, contas a receber e contas a pagar;',
              'relatórios, PDFs, recibos e exportações gerados pelo usuário;',
              'identificadores técnicos, como deviceId, clientInstanceId, appVersion e platform;',
              'logs operacionais e de erro e dados de sincronização offline;',
              'dados de assinatura, plano e licença;',
              'dados relacionados a pagamento, quando o Mercado Pago estiver ativo e for aplicável.',
            ]),
          ],
        ),
        LegalSection(
          title: '3. Como os dados são coletados',
          content: [
            LegalParagraph(
              'Os dados podem ser informados diretamente pelo titular, pelo '
              'responsável da empresa ou por usuários autorizados; gerados '
              'durante o uso dos recursos do Tatuzin; obtidos do dispositivo '
              'e do contexto técnico do aplicativo; ou recebidos de '
              'prestadores de serviço, como processamento de pagamentos, '
              'quando aplicável.',
            ),
          ],
        ),
        LegalSection(
          title: '4. Finalidades do tratamento',
          content: [
            LegalBulletList([
              'criar e administrar contas, empresas, usuários, planos e licenças;',
              'oferecer as funções de gestão comercial e financeira do Tatuzin;',
              'armazenar operações offline e sincronizá-las entre dispositivos autorizados;',
              'gerar relatórios, recibos, PDFs e exportações solicitados;',
              'autenticar usuários, aplicar permissões e proteger contas e empresas;',
              'diagnosticar falhas, manter o serviço, prevenir abuso e prestar suporte;',
              'processar e conciliar pagamentos e assinaturas, quando aplicável;',
              'cumprir obrigações legais, regulatórias e exercer direitos em processos.',
            ]),
          ],
        ),
        LegalSection(
          title: '5. Armazenamento local no dispositivo',
          content: [
            LegalParagraph(
              'O aplicativo pode manter dados comerciais, pessoais e de '
              'sincronização localmente para permitir o funcionamento offline. '
              'Access token e refresh token são armazenados em secure storage. '
              'Em builds de release, o backup bruto do arquivo .db é bloqueado, '
              'o backup do Android é desativado e os logs são reduzidos ou '
              'sanitizados. O banco local SQLite não possui criptografia total '
              'neste momento.',
            ),
          ],
        ),
        LegalSection(
          title: '6. Sincronização com servidores',
          content: [
            LegalParagraph(
              'Quando a sincronização estiver habilitada, dados do aplicativo '
              'podem ser enviados aos servidores usados pelo Tatuzin para '
              'backup operacional, continuidade do serviço e uso em '
              'dispositivos autorizados. A sincronização utiliza contexto de '
              'dispositivo e de instância do cliente. O backend valida '
              'autenticação, empresa e permissões antes de autorizar operações.',
            ),
          ],
        ),
        LegalSection(
          title: '7. Compartilhamento com terceiros',
          content: [
            LegalParagraph(
              'Os dados podem ser compartilhados, no limite necessário, com '
              'fornecedores de infraestrutura, hospedagem, armazenamento, '
              'monitoramento, suporte e outros operadores que viabilizam o '
              'serviço; com autoridades quando houver obrigação legal; ou para '
              'proteção de direitos e segurança. Esses terceiros devem tratar '
              'os dados de acordo com suas responsabilidades legais e '
              'contratuais.',
            ),
          ],
        ),
        LegalSection(
          title: '8. Pagamentos e Mercado Pago',
          content: [
            LegalParagraph(
              'Quando aplicável e após a ativação desse recurso, pagamentos e '
              'assinaturas podem ser processados pelo Mercado Pago. Nesse caso, '
              'dados necessários à transação poderão ser enviados ou recebidos '
              'do provedor. O Mercado Pago também poderá tratar dados conforme '
              'sua própria política de privacidade. O recurso encontra-se em '
              'validação ou teste e pode não estar disponível para todos os '
              'usuários.',
            ),
          ],
        ),
        LegalSection(
          title: '9. Segurança',
          content: [
            LegalParagraph(
              'O Tatuzin adota medidas técnicas e administrativas proporcionais '
              'ao risco, incluindo armazenamento seguro de tokens no app, '
              'redução e sanitização de logs de release, desativação de backup '
              'Android, bloqueio de backup bruto .db em release e validações de '
              'autenticação, empresa e permissões no backend. Nenhum sistema é '
              'totalmente imune a incidentes, e as medidas são continuamente '
              'avaliadas e aprimoradas.',
            ),
          ],
        ),
        LegalSection(
          title: '10. Retenção',
          content: [
            LegalParagraph(
              'Os dados são mantidos pelo período necessário para prestar o '
              'serviço, cumprir as finalidades desta política e atender '
              'obrigações legais, fiscais, regulatórias, de segurança, auditoria '
              'e exercício regular de direitos. Após esse período, poderão ser '
              'excluídos ou anonimizados, conforme aplicável.',
            ),
          ],
        ),
        LegalSection(
          title: '11. Exclusão de conta e dados',
          content: [
            LegalParagraph(
              'O titular ou responsável pela empresa pode solicitar a exclusão '
              'da conta e dos dados associados. Alguns registros poderão ser '
              'retidos quando necessários por obrigação legal, segurança, '
              'auditoria ou exercício regular de direitos.',
            ),
            LegalRouteLink(
              label: 'Ver instruções para exclusão de conta e dados',
              route: '/exclusao-de-dados',
            ),
          ],
        ),
        LegalSection(
          title: '12. Direitos do titular pela LGPD',
          content: [
            LegalParagraph(
              'Nos termos da Lei Geral de Proteção de Dados Pessoais (LGPD), o '
              'titular pode solicitar, quando aplicável, confirmação do '
              'tratamento, acesso, correção, anonimização, bloqueio, exclusão, '
              'portabilidade, informação sobre compartilhamentos, revisão de '
              'decisões automatizadas e revogação do consentimento. As '
              'solicitações podem exigir confirmação de identidade para '
              'proteger a conta e os dados.',
            ),
          ],
        ),
        LegalSection(
          title: '13. Crianças e adolescentes',
          content: [
            LegalParagraph(
              'O Tatuzin é destinado à gestão de empresas e não é direcionado '
              'a crianças. O uso por adolescentes deve ocorrer somente quando '
              'legalmente permitido e com a participação do responsável legal, '
              'observando o melhor interesse do menor.',
            ),
          ],
        ),
        LegalSection(
          title: '14. Alterações desta política',
          content: [
            LegalParagraph(
              'Esta política poderá ser atualizada para refletir mudanças no '
              'Tatuzin, em práticas de tratamento ou na legislação. A versão '
              'vigente e sua data de atualização serão publicadas nesta página.',
            ),
          ],
        ),
        LegalSection(
          title: '15. Contato',
          content: [
            LegalParagraph(
              'Dúvidas, solicitações e comunicações sobre privacidade podem ser '
              'enviadas para [E-MAIL DE PRIVACIDADE]. Informe dados suficientes '
              'para localizar a conta, evitando enviar senhas, tokens ou dados '
              'de pagamento completos.',
            ),
          ],
        ),
      ],
    );
  }
}
