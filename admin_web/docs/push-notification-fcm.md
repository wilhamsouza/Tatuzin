# Push Notification / FCM

Este documento prepara o `admin_web` para uma futura integracao de Push
Notification / FCM no ecossistema Tatuzin. Nesta fase, tudo e documentacao e
visao read-only. Nao ha Firebase real, credenciais, registro real de token,
envio real de push, endpoints novos, contratos novos, Android alterado ou
backend alterado.

## Objetivo futuro

FCM pode ser usado futuramente para comunicacao operacional com dispositivos
Android, sempre com seguranca, consentimento, preferencias e auditoria. O
objetivo e permitir avisos controlados, rastreaveis e seguros, sem transformar o
Admin Web em um canal livre de mensagens.

## Limites atuais do Admin Web

O `admin_web` nesta fase apenas:

- Documenta o modelo futuro.
- Exibe estado read-only como `Nao configurado` ou `Indisponivel`.
- Informa que envio real depende de backend, Android, Firebase, permissoes e
  auditoria.

O `admin_web` nesta fase nao:

- Registra token FCM.
- Envia notificacao.
- Configura Firebase.
- Usa credenciais Firebase.
- Cria endpoint.
- Altera contrato real de API.
- Altera permissoes reais.

## Modelo futuro de FCM

Campos e conceitos esperados para uma fase futura:

- Token FCM por dispositivo.
- Status do token.
- Data de registro do token.
- Data da ultima atualizacao do token.
- Preferencias do usuario ou da empresa.
- Opt-in e opt-out, se aplicavel.
- Historico de notificacoes.
- Status de entrega, se disponivel futuramente.
- Motivos de falha.
- Revogacao ou invalidacao de token.
- Segmentacao por empresa, usuario ou dispositivo.

Nenhum desses dados e obrigatorio para a fase atual.

## Tipos futuros de notificacao

Tipos possiveis, apenas como planejamento:

- Aviso de atualizacao obrigatoria.
- Aviso de sync pendente.
- Aviso operacional.
- Lembrete administrativo.
- Alerta de billing, se permitido futuramente.
- Aviso de manutencao.
- Mensagem manual do suporte, se permitido futuramente.

Nenhum envio real e criado nesta fase.

## Dados necessarios para envio futuro

- Endpoint para listar tokens por empresa/dispositivo.
- Endpoint para preferencias de push.
- Endpoint para historico de notificacoes.
- Endpoint de dry-run de envio.
- Endpoint de envio real.
- Payload padrao de notificacao.
- Politica de permissoes.
- Politica de auditoria.
- Integracao Firebase no backend.
- Integracao Firebase no Android.
- Tratamento de token expirado ou invalido.
- Configuracao segura de credenciais.

## Seguranca

Regras obrigatorias para qualquer fase futura:

- Nunca exibir token FCM completo.
- Nunca exibir credenciais Firebase.
- Nunca exibir payload sensivel.
- Nunca enviar notificacao sem permissao especifica.
- Exigir motivo obrigatorio.
- Exigir confirmacao explicita.
- Exigir dry-run antes do envio real.
- Gerar auditoria backend.
- Registrar ator/admin.
- Registrar resultado e falhas.
- Tratar erro de forma auditavel.

## Auditoria futura

Eventos futuros de push devem auditar:

- Quem enviou.
- Empresa afetada.
- Usuarios e dispositivos afetados.
- Tipo de notificacao.
- Payload seguro/resumido.
- Resultado.
- Falhas.
- Data e hora.
- Motivo informado.
- Dry-run executado antes do envio real.

## Observabilidade futura

Metricas futuras desejadas:

- Total de tokens ativos.
- Tokens invalidos.
- Taxa de sucesso de envio.
- Taxa de falha.
- Falhas por motivo.
- Envios por empresa.
- Envios por tipo.
- Opt-out e preferencias.
- Latencia de envio.
- Historico temporal.

## Riscos de envio indevido

- Impacto operacional em lojas durante atendimento.
- Comunicacao fora de contexto com usuarios finais.
- Vazamento de informacao por payload sensivel.
- Envio duplicado ou para publico errado.
- Ausencia de auditoria para acoes sensiveis.
- Uso de credenciais Firebase sem controle.

## Relacao com outras areas

- Android: deve registrar token, respeitar preferencias e receber mensagens.
- Backend: deve guardar tokens, validar permissao, executar dry-run e enviar.
- Auditoria: deve registrar motivo, ator, alvo, payload seguro e resultado.
- Seguranca: deve proteger tokens, credenciais e payloads.
- Observabilidade: deve acompanhar sucesso, falha, latencia e tokens invalidos.
- Central de Suporte: pode exibir status read-only e lacunas.
- Dispositivos: pode exibir fallback de token/preferencias quando houver dados.

## Fora do escopo desta fase

- Firebase real.
- Credenciais Firebase.
- FCM real.
- Envio real de push.
- Registro real de token.
- Push notification no Android.
- Endpoints novos.
- Contratos reais de API.
- Permissoes reais.
- Infraestrutura ou deploy.
