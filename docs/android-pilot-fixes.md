# Correções do piloto Android — 1.0.2-pilot

## Comportamento entregue

- Comprovantes ficam fora das abas. Depois de vender, fechar pelo botão, seta ou
  Voltar do Android retorna a Vender; comprovante aberto pelo histórico volta ao detalhe.
- Atividade abre nas vendas de hoje do dispositivo, sem o limite de cinco movimentos
  do dashboard. Mostra cliente, horário, valor e situação e permite consultar o detalhe.
  Registros UTC recebidos da sincronização são classificados e exibidos no horário local.
- Cliente está disponível no checkout sem abrir Mais opções. O evento envia a
  identidade remota/UUID do cadastro e o recebimento entre dispositivos preserva o vínculo.
- Detalhe da venda permite vincular ou alterar cliente de venda ativa sem fiado,
  haver, troca ou devolução. Dono/administrador podem corrigir vendas da empresa;
  operadores com permissão de vender, somente as próprias. Vendas antigas sem autoria
  confiável exigem dono/administrador.
- A associação grava auditoria e outbox na mesma transação, sem alterar dinheiro,
  caixa ou estoque. Permanece identificada como pendente offline; rejeição e conflito
  ficam explícitos e impedem uma segunda alteração antes de resolver a anterior.
- O backend valida empresa, permissões e revisão. Reenvios são deduplicados;
  edições concorrentes não sobrescrevem silenciosamente. A edição genérica da venda
  continua bloqueada. Troca/devolução gera bloqueio monotônico do vínculo.
- O drawer recebe a localização pelo router, fecha sem remover a rota e rola inteiro.
  Badges ficam abaixo do título, sem consumir a largura do item. Estados vazios e
  cards do Início também acomodam fonte ampliada.

## Compatibilidade e validação

- SQLite v38 é aditivo e preserva as migrations publicadas v1–37.
- Backend requer a migration `20261113160000_sale_customer_assignments` antes do APK.
  Clientes anteriores continuam funcionando; não desfazer a migration em uma reversão normal.
- Validação local: 616 testes Flutter, análise estática limpa e nove integrações
  PostgreSQL. Casos novos cobrem persistência, rollback, permissões, concorrência,
  dependências, projeção remota, vendas do dia, comprovantes e menu em claro/escuro
  com fonte ampliada. O smoke HTTP usa exclusivamente ambiente `isolated-test`.
- A primeira chave do piloto não foi preservada pelo cache do CI. A conferência
  detectou a divergência e bloqueou a entrega como atualização direta.
- O responsável escolheu instalar em paralelo: o novo pacote é
  `br.com.tatuzin.gestao.pilot2`, com nome Tatuzin Piloto 2. A versão anterior e seus
  dados permanecem no aparelho. Dados ainda offline não migram automaticamente;
  dados sincronizados pertencem à mesma empresa ao entrar novamente.
- O CI agora produz somente um candidato sem assinatura. O host de distribuição
  assina com chave persistente em `.release-backups/android-pilot-signing/`, com
  permissões restritas. Chave e senha nunca são publicadas nem enviadas ao CI.
- O script `backend/scripts/sign-pilot-apk.sh` recusa o pacote oficial, confere a
  assinatura e a impressão digital fixada. Guardar backup privado dessa pasta
  antes de mover ou substituir o servidor; não apagar nem regenerar a chave.

## Repetição no Android

1. Instalar Tatuzin Piloto 2 em paralelo, sem desinstalar a versão anterior;
   entrar na empresa de testes. A nova instalação tem cache local próprio.
2. Fazer duas vendas e fechar cada comprovante. Abrir Atividade: devem aparecer as
   vendas do dia, sem reaparecer o comprovante anterior.
3. Abrir uma venda pelo histórico, consultar o comprovante e voltar ao detalhe.
4. Selecionar cliente no checkout; depois, em outra venda simples, usar Vincular/Alterar
   cliente no detalhe. Reabrir o comprovante e conferir o nome.
5. Repetir uma associação offline após preparar os cadastros, observar o aviso pendente
   e sincronizar. Conferir a confirmação e o vínculo em outro dispositivo.
6. Confirmar o bloqueio em fiado/haver/devoluções. Abrir e fechar o menu pelo ícone e
   pelo gesto nas cinco abas, nos dois temas e com fonte ampliada.

Os testes automatizados não substituem esta repetição em aparelho físico.

## Publicação no ambiente de testes

Em 13/11/2026, backend atualizado para `tatuzin-backend:customer-fixes-20261113`,
imagem `sha256:f858ee0045e2d5c02ebe512cbb589094bc70c40182d1da808994899546542759`.
Backup privado anterior às alterações em `.release-backups/customer-fixes-20261113/`,
com dump conferido, fora do Git. Imagem anterior preservada como
`tatuzin-backend:rollback-customer-fixes-20261113`.

Migration aplicada, readiness HTTPS saudável e coleta do piloto ativa.
Quinze verificações HTTP passaram no candidato isolado, incluindo o contrato real
de push/pull da associação. Nenhuma venda ou associação sintética foi criada no
ambiente compartilhado. Monitoramento passa a acompanhar `1.0.2-pilot`.
