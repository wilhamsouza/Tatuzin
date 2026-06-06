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
          'associados sem precisar entrar no aplicativo ou no painel.',
      sections: [
        LegalSection(
          title: 'Como solicitar',
          content: [
            LegalParagraph(
              'Envie um e-mail para [E-MAIL DE PRIVACIDADE] com o assunto '
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
          title: 'Confirmação e prazo de resposta',
          content: [
            LegalParagraph(
              'Para proteger os dados, poderemos solicitar informações '
              'adicionais para confirmar a identidade e a relação com a conta '
              'ou empresa. A solicitação receberá uma resposta inicial em até '
              '15 dias corridos. O prazo para concluir a exclusão poderá variar '
              'conforme a complexidade, os sistemas envolvidos e os prazos '
              'legais aplicáveis; eventuais extensões serão informadas.',
            ),
          ],
        ),
        LegalSection(
          title: 'O que será excluído',
          content: [
            LegalParagraph(
              'Após a validação do pedido, serão avaliadas a exclusão da conta '
              'e dos dados pessoais e comerciais associados nos sistemas sob '
              'responsabilidade do Tatuzin, incluindo dados sincronizados, '
              'quando aplicável. Dados mantidos somente no dispositivo podem '
              'exigir a remoção local do aplicativo ou dos dados do app pelo '
              'próprio usuário.',
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
              'diretamente pelo provedor também podem precisar ser encaminhadas '
              'a ele.',
            ),
          ],
        ),
        LegalSection(
          title: 'Responsável e contato',
          content: [
            LegalParagraph(
              'Responsável: [NOME/RAZÃO SOCIAL], [CNPJ, se houver]. E-mail para '
              'solicitações: [E-MAIL DE PRIVACIDADE].',
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
