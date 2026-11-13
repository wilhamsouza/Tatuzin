# Correções do piloto Android — 1.0.2-pilot

## Comportamento entregue

- Comprovantes ficam fora das abas. Depois de vender, fechar pelo botão, seta ou
  Voltar do Android retorna a Vender; comprovante aberto pelo histórico volta ao detalhe.
- Atividade abre nas vendas de hoje do dispositivo, sem o limite de cinco movimentos
  do dashboard. Mostra cliente, horário, valor e situação e permite consultar o detalhe.
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
- O APK usa o mesmo pacote piloto e cache da chave de testes para atualização direta.
  A assinatura e o checksum devem ser conferidos na entrega.

## Repetição no Android

1. Instalar a atualização do Tatuzin Piloto sem apagar os dados; entrar na empresa de testes.
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
