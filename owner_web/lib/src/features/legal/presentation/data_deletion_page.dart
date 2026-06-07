import 'package:flutter/material.dart';

import 'public_legal_page.dart';

class DataDeletionPage extends StatelessWidget {
  const DataDeletionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PublicLegalPage(
      title: 'Exclusão de Conta e Dados',
      description:
          'Você pode solicitar a exclusão da sua conta Tatuzin e dos dados '
          'associados por este canal público, sem precisar entrar no aplicativo '
          'ou no painel.',
      sections: [
        LegalSection(
          title: 'Como solicitar',
          content: [
            LegalParagraph(
              'Envie um e-mail para privacidade@tatuzin.com.br com o assunto '
              '"Exclusão de conta e dados - Tatuzin". A página e o canal de '
              'solicitação são públicos e não exigem login.',
            ),
          ],
        ),
        LegalSection(
          title: 'Informações necessárias',
          content: [
            LegalParagraph(
              'No pedido, informe o e-mail usado na conta Tatuzin e o nome da '
              'empresa vinculada. Se desejar excluir apenas determinados dados, '
              'descreva claramente quais informações ou registros devem ser '
              'avaliados. Não envie senha, access token, refresh token ou dados '
              'de pagamento completos.',
            ),
          ],
        ),
        LegalSection(
          title: 'Validação de identidade e prazo de resposta',
          content: [
            LegalParagraph(
              'Para proteger os dados, a equipe responsável poderá solicitar '
              'informações adicionais para confirmar a identidade e a relação '
              'com a conta ou empresa. A solicitação receberá uma resposta '
              'inicial em até 15 dias corridos. Essa resposta inicial não '
              'significa a conclusão do pedido, cujo prazo dependerá da '
              'complexidade, dos sistemas envolvidos e das obrigações legais '
              'aplicáveis.',
            ),
          ],
        ),
        LegalSection(
          title: 'Como a solicitação será tratada',
          content: [
            LegalParagraph(
              'Após a validação de identidade, a solicitação será analisada e '
              'tratada por processo operacional e manual. A exclusão não é '
              'automática nem imediata. Conforme a natureza dos dados e as '
              'obrigações aplicáveis, a tratativa poderá resultar em exclusão, '
              'anonimização, desativação da conta ou retenção justificada.',
            ),
          ],
        ),
        LegalSection(
          title: 'Dados armazenados no dispositivo',
          content: [
            LegalParagraph(
              'Dados mantidos localmente no aparelho podem não ser alcançados '
              'pela tratativa operacional. Nesses casos, o usuário poderá '
              'precisar desinstalar o aplicativo ou remover os dados do app nas '
              'configurações do dispositivo.',
            ),
          ],
        ),
        LegalSection(
          title: 'Retenções permitidas',
          content: [
            LegalParagraph(
              'Alguns dados podem ser retidos pelo período necessário para '
              'cumprimento de obrigação legal ou regulatória, segurança e '
              'prevenção a fraudes, auditoria, comprovação de transações ou '
              'exercício regular de direitos. Quando possível, o acesso ficará '
              'restrito e os dados serão eliminados ou anonimizados após o fim '
              'do prazo aplicável.',
            ),
          ],
        ),
        LegalSection(
          title: 'Dados de pagamento',
          content: [
            LegalParagraph(
              'Quando pagamentos pelo Mercado Pago forem aplicáveis, o provedor '
              'poderá manter dados sob sua própria responsabilidade e conforme '
              'obrigações legais. Solicitações relativas ao tratamento feito '
              'diretamente pelo provedor podem depender dos procedimentos e '
              'prazos dele, ou precisar ser encaminhadas diretamente a ele.',
            ),
          ],
        ),
        LegalSection(
          title: 'Responsável e contato',
          content: [
            LegalParagraph(
              'Responsável: Tatuzin, Não informado. E-mail para '
              'solicitações: privacidade@tatuzin.com.br.',
            ),
            LegalRouteLink(
              label: 'Consultar a Política de Privacidade',
              route: '/privacidade',
            ),
          ],
        ),
      ],
    );
  }
}
