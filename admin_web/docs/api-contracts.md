# Admin Web API Contracts

Documentacao preliminar dos contratos consumidos pelo `admin_web`.

Este documento inventaria o contrato observado no front-end Flutter. Ele nao e
fonte de verdade do backend, nao cria endpoint novo e nao autoriza mudanca de
payload real. Qualquer divergencia deve ser resolvida no backend ou no contrato
oficial antes de mudar telas operacionais.

## Status dos Contratos

- **Real**: endpoint chamado por `AdminApiService`.
- **Fixture**: payload exercitado por teste/fake service.
- **Placeholder**: UI mostra estado futuro ou acao ainda nao operacional.
- **Desconhecido**: contrato inferido parcialmente pelo front-end.

## Endpoints Consumidos

### Autenticacao

| Metodo | Path | Tela | Service/model | Finalidade | Status |
| --- | --- | --- | --- | --- | --- |
| POST | `/auth/login` | Login | `login`, `AdminSession` | Autenticar admin e salvar tokens. | Real |
| GET | `/auth/me` | Restore de sessao | `restoreSession`, `AdminSession` | Restaurar identidade admin. | Real |
| POST | `/auth/refresh` | Cliente HTTP | `AdminApiClient` | Renovar access token. | Real |
| POST | `/auth/logout` | Shell/login | `logout` | Encerrar sessao local/remota. | Real |
| POST | `/admin/sessions/:sessionId/revoke` | Nao exposto como comando novo nesta fase | `revokeSession` | Revogar sessao administrativa. | Real no service, fora do console operacional read-only |

### Empresas

| Metodo | Path | Tela | Service/model | Finalidade | Status |
| --- | --- | --- | --- | --- | --- |
| GET | `/admin/companies` | Empresas | `fetchCompanies`, `AdminCompanySummary` | Listar empresas/tenants. | Real |
| GET | `/admin/companies/:companyId` | Detalhe da empresa | `fetchCompanyDetail`, `AdminCompanyDetail` | Carregar dados 360 e sessoes recentes. | Real |
| GET | `/admin/companies/:companyId/access-summary` | Usuarios e funcionarios | `fetchCompanyAccessSummary`, `AdminCompanyAccessSummary` | Consolidar usuarios, funcionarios, permissoes, dispositivos e auditoria de acesso. | Real |

### Usuarios e Funcionarios

| Metodo | Path | Tela | Service/model | Finalidade | Status |
| --- | --- | --- | --- | --- | --- |
| POST | `/admin/companies/:companyId/access/:targetId/block/dry-run` | Usuarios/funcionarios | `dryRunAccessBlock`, `AdminAccessActionDryRun` | Simular bloqueio operacional. | Real no service |
| POST | `/admin/companies/:companyId/access/:targetId/block` | Usuarios/funcionarios | `applyAccessBlock`, `AdminAccessActionResult` | Aplicar bloqueio operacional. | Real no service |
| POST | `/admin/companies/:companyId/access/:targetId/reactivate/dry-run` | Usuarios/funcionarios | `dryRunAccessReactivate`, `AdminAccessActionDryRun` | Simular reativacao. | Real no service |
| POST | `/admin/companies/:companyId/access/:targetId/reactivate` | Usuarios/funcionarios | `applyAccessReactivate`, `AdminAccessActionResult` | Aplicar reativacao. | Real no service |

Observacao: as fases 4 a 7 documentam o console operacional como read-only. A
existencia desses endpoints no service nao autoriza criar novas acoes reais sem
dry-run, motivo obrigatorio, confirmacao e auditoria.

### Dispositivos e Sessoes

| Metodo | Path | Tela | Service/model | Finalidade | Status |
| --- | --- | --- | --- | --- | --- |
| GET | `/admin/devices` | Dispositivos global | `fetchDevices`, `AdminDeviceInventoryItem` | Inventario de dispositivos, sessoes e diagnostico local. | Real |
| GET | `/admin/companies/:companyId/sessions` | Dispositivos da empresa | `fetchCompanySessions`, `AdminDeviceSession` | Listar sessoes recentes por empresa. | Real |
| GET | `/admin/companies/:companyId/devices` | Sync Center por empresa | `fetchCompanySyncDevices`, `AdminCompanySyncDevice` | Listar dispositivos observados no sync. | Real |

### Licencas e Planos

| Metodo | Path | Tela | Service/model | Finalidade | Status |
| --- | --- | --- | --- | --- | --- |
| GET | `/admin/licenses` | Licencas | `fetchLicenses`, `AdminLicenseSnapshot` | Listar licencas administrativas. | Real |
| PATCH | `/admin/licenses/:companyId` | Licenca legada | `updateLicense`, `AdminLicenseSnapshot` | Edicao legada de licenca. | Real no service |
| GET | `/admin/plans` | Planos | `fetchPlansOverview`, `AdminPlansOverview` | Matriz de planos, recursos e limites. | Real |
| POST | `/admin/companies/:companyId/license/extension/dry-run` | Licenca/billing | `dryRunLicenseEmergencyExtension` | Simular extensao emergencial. | Real |
| POST | `/admin/companies/:companyId/license/extension` | Licenca/billing | `applyLicenseEmergencyExtension` | Aplicar extensao emergencial. | Real |
| POST | `/admin/companies/:companyId/license/suspend/dry-run` | Licenca/billing | `dryRunLicenseSuspend` | Simular suspensao. | Real |
| POST | `/admin/companies/:companyId/license/suspend` | Licenca/billing | `applyLicenseSuspend` | Aplicar suspensao. | Real |
| POST | `/admin/companies/:companyId/license/reactivate/dry-run` | Licenca/billing | `dryRunLicenseReactivate` | Simular reativacao. | Real |
| POST | `/admin/companies/:companyId/license/reactivate` | Licenca/billing | `applyLicenseReactivate` | Aplicar reativacao. | Real |

### Billing

| Metodo | Path | Tela | Service/model | Finalidade | Status |
| --- | --- | --- | --- | --- | --- |
| GET | `/admin/billing/companies` | Billing | `fetchBillingCompanies`, `AdminBillingCompanySummary` | Listar empresas com billing. | Real |
| GET | `/admin/companies/:companyId/billing/status` | Billing da empresa | `fetchBillingCompanyStatus`, `AdminBillingCompanyStatus` | Snapshot de cobranca/licenca. | Real |
| GET | `/admin/companies/:companyId/billing/events` | Billing da empresa | `fetchBillingEvents`, `AdminBillingEvent` | Eventos do provider. | Real |
| GET | `/admin/companies/:companyId/billing/checkout-sessions` | Billing da empresa | `fetchBillingCheckoutSessions`, `AdminBillingCheckoutSession` | Sessoes de checkout. | Real |
| GET | `/admin/companies/:companyId/billing/audit-logs` | Billing da empresa | `fetchBillingAuditLogs`, `AdminBillingAuditLog` | Auditoria especifica de billing. | Real |
| POST | `/admin/companies/:companyId/billing/refresh` | Billing da empresa | `refreshBillingCompany` | Recarregar estado de billing. | Real |
| POST | `/admin/companies/:companyId/billing/force-plan` | Billing da empresa | `forceBillingPlan` | Ajuste administrativo de plano. | Real |
| POST | `/admin/companies/:companyId/billing/cancel-local` | Billing da empresa | `cancelBillingLocal` | Cancelamento local, nao provider. | Real |
| POST | `/admin/companies/:companyId/billing/reconcile/dry-run` | Billing da empresa | `dryRunBillingReconcile` | Simular reconciliacao. | Real |
| POST | `/admin/companies/:companyId/billing/reconcile` | Billing da empresa | `applyBillingReconcile` | Aplicar reconciliacao. | Real |

### Sync Center

| Metodo | Path | Tela | Service/model | Finalidade | Status |
| --- | --- | --- | --- | --- | --- |
| GET | `/admin/companies/:companyId/sync/health` | Empresa/Sync Center | `fetchCompanySyncHealth`, `AdminCompanySyncHealth` | Saude de sync por empresa. | Real |
| GET | `/admin/companies/:companyId/sync/events` | Sync Center por empresa | `fetchCompanySyncEvents`, `AdminSyncEventDiagnostic` | Eventos de sync por empresa. | Real |
| GET | `/admin/companies/:companyId/sync/conflicts` | Sync Center por empresa | `fetchCompanySyncConflicts`, `AdminSyncConflictDiagnostic` | Conflitos de sync por empresa. | Real |
| GET | `/admin/companies/:companyId/sync/incidents` | Sync Center por empresa | `fetchCompanySyncIncidents`, `AdminSyncIncidentDiagnostic` | Incidentes por empresa. | Real |
| GET | `/admin/sync/summary` | Sync legado/saude | `fetchSyncSummary`, `AdminSyncSummary` | Resumo global de sync. | Real |
| GET | `/admin/sync/operational-summary` | Sync health | `fetchSyncOperationalSummary`, `AdminSyncOperationalSummary` | Visao operacional de tenants. | Real |
| GET | `/admin/sync/companies` | Sync Center global | `fetchSyncCenterCompanies`, `AdminSyncCenterCompany` | Empresas para triagem operacional. | Real |
| GET | `/admin/sync/companies/:companyId/summary` | Central de Suporte | `fetchSyncCenterCompanySummary`, `AdminSyncCenterCompanySummary` | Resumo de sync da empresa. | Real |
| GET | `/admin/sync/companies/:companyId/events` | Detalhes Sync Center | `fetchSyncCenterEvents`, `AdminSyncCenterEvent` | Eventos por empresa no contrato novo. | Real |
| GET | `/admin/sync/companies/:companyId/conflicts` | Detalhes Sync Center | `fetchSyncCenterConflicts`, `AdminSyncCenterConflict` | Conflitos por empresa no contrato novo. | Real |
| GET | `/admin/sync/companies/:companyId/devices` | Dispositivos Sync Center | `fetchSyncSupportDevices`, `AdminSyncSupportDevice` | Dispositivos de suporte sync. | Real |
| GET | `/admin/sync/companies/:companyId/devices/:deviceId/diagnostics` | Dispositivo Sync Center | `fetchSyncSupportDeviceDetail`, `AdminSyncSupportDeviceDetail` | Diagnostico seguro do dispositivo. | Real |
| POST | `/admin/sync/companies/:companyId/devices/:deviceId/support-actions/dry-run` | Dispositivo Sync Center | `dryRunSyncSupportAction` | Simular comando de suporte. | Real no service |
| POST | `/admin/sync/companies/:companyId/devices/:deviceId/support-actions` | Dispositivo Sync Center | `createSyncSupportAction` | Criar comando de suporte. | Real no service |
| GET | `/admin/sync/events/:eventId` | Detalhe evento | `fetchSyncCenterEventDetail`, `AdminSyncCenterEventDetail` | Detalhe read-only de evento. | Real |
| GET | `/admin/sync/conflicts/:conflictId` | Detalhe conflito | `fetchSyncCenterConflictDetail`, `AdminSyncCenterConflictDetail` | Detalhe read-only de conflito. | Real |
| POST | `/admin/sync/events/:eventId/reprocess-dry-run` | Acao futura sync | `dryRunSyncEventReprocess` | Simular reprocessamento. | Real no service |
| POST | `/admin/sync/events/:eventId/reprocess` | Acao futura sync | `reprocessSyncEvent` | Reprocessar evento. | Real no service |
| POST | `/admin/sync/conflicts/:conflictId/archive-dry-run` | Acao futura sync | `dryRunSyncConflictArchive` | Simular arquivamento. | Real no service |
| POST | `/admin/sync/conflicts/:conflictId/archive` | Acao futura sync | `archiveSyncConflict` | Arquivar conflito. | Real no service |
| POST | `/admin/sync/conflicts/:conflictId/manual-stock-adjustment-dry-run` | Acao futura sync | `dryRunManualStockAdjustment` | Simular ajuste manual. | Real no service |

### Auditoria

| Metodo | Path | Tela | Service/model | Finalidade | Status |
| --- | --- | --- | --- | --- | --- |
| GET | `/admin/audit/summary` | Dashboard | `fetchAuditSummary`, `AdminAuditSummary` | Resumo de auditoria. | Real |
| GET | `/admin/audit` | Auditoria | `fetchAuditLogs`, `AdminAuditLogPage` | Eventos normalizados e filtraveis. | Real |

### Areas Gerenciais Legadas

Essas telas existem no admin web, mas ficam fora do foco das fases 1-7 de
suporte operacional.

| Metodo | Path | Tela | Status |
| --- | --- | --- | --- |
| GET | `/admin/analytics/dashboard` | Management dashboard | Real |
| GET | `/admin/analytics/reports/sales-by-day` | Reports | Real |
| GET | `/admin/analytics/reports/sales-by-product` | Reports | Real |
| GET | `/admin/analytics/reports/sales-by-customer` | Reports | Real |
| GET | `/admin/analytics/reports/cash-consolidated` | Reports | Real |
| GET | `/admin/analytics/reports/financial-summary` | Reports | Real |
| GET | `/admin/crm/customers` | CRM | Real |
| GET | `/admin/crm/customers/:customerId` | CRM detail | Real |
| GET | `/admin/crm/customers/:customerId/timeline` | CRM detail | Real |
| POST | `/admin/crm/customers/:customerId/notes` | CRM detail | Real |
| POST | `/admin/crm/customers/:customerId/tasks` | CRM detail | Real |
| POST | `/admin/crm/customers/:customerId/tags` | CRM detail | Real |
| GET | `/admin/hybrid-governance/overview` | Governanca hibrida | Real |
| PATCH | `/admin/hybrid-governance/profile` | Governanca hibrida | Real |

## Models e Payloads Principais

### Company

Models: `AdminCompanySummary`, `AdminCompanyDetail`, `AdminAccessCompany`.

Campos conhecidos: `id`, `name`, `legalName`, `documentNumber`, `slug`,
`isActive`, `createdAt`, `updatedAt`, `license`, `counts`, `memberships`,
`sessions`.

Opcionais/fallbacks: `legalName` usa `name`; `documentNumber` aparece como
`Nao informado`; licenca pode estar ausente e vira `Sem dados` em cards.

Telas: Empresas, Detalhe da empresa, Central de Suporte, Billing, Licencas,
Sync Center, Auditoria.

### Admin User e Company User

Models: `AdminUser`, `AdminCompanyAccessUser`, `AdminMembershipSummary`.

Campos conhecidos: `id`, `name`, `email`, `isPlatformAdmin`, `userId`,
`membershipId`, `employeeProfileId`, `membershipRole`, `employeeRole`,
`status`, `accountStatus`, `effectivePermissions`, `isOwner`,
`isProtectedOwner`, `hasUserAccount`, `hasEmployeeProfile`, `lastSeenAt`,
`devices`.

Opcionais/fallbacks: nome de admin usa `Administrador`; usuario usa `Usuario`;
email ausente vira `Nao informado`; `lastSeenAt` ausente vira `Sem atividade
registrada`; vinculo usuario/funcionario pode virar `Vinculo indisponivel`.

Telas: Login/restauracao, Usuarios e funcionarios, Central de Suporte,
Auditoria de acesso.

### Employee

Model: `AdminCompanyAccessEmployee`.

Campos conhecidos: `employeeProfileId`, `userId`, `membershipId`, `name`,
`email`, `phone`, `employeeRole`, `membershipRole`, `status`,
`savedPermissions`, `effectivePermissions`, `isOwner`, `isProtectedOwner`,
`hasUserAccount`, `invitationStatus`, `createdAt`, `updatedAt`.

Opcionais/fallbacks: nome usa `Funcionario`; role usa `READ_ONLY`; status usa
`DISABLED`; email/telefone ausentes aparecem como `Nao informado`; vinculo sem
usuario aparece como `Sem usuario vinculado`.

Telas: Usuarios e funcionarios, Central de Suporte.

### Device

Models: `AdminDeviceInventoryItem`, `AdminCompanyAccessDevice`,
`AdminCompanySyncDevice`, `AdminSyncSupportDevice`.

Campos conhecidos: `id`, `maskedDeviceId`, `companyId`, `companyName`,
`userId`, `userName`, `userEmail`, `deviceLabel`, `clientType`,
`clientInstanceId`, `platform`, `appVersion`, `status`, `lastSeenAt`,
`session`, `diagnostic`.

Opcionais/fallbacks: `deviceLabel` pode virar id mascarado; usuario vazio vira
`Nao informado`; plataforma/app version ausentes viram `Nao informado` ou `Sem
dados`; diagnostico ausente vira `Sem dados`/`Indisponivel`; sync ausente vira
`Nenhum sync recente`; erro ausente vira `Nenhum erro`.

Telas: Dispositivos, Usuarios e funcionarios, Sync Center, Central de Suporte.

### Session

Models: `AdminDeviceSession`, `AdminDeviceInventorySession`.

Campos conhecidos: `id`, `userId`, `userName`, `userEmail`, `companyId`,
`companyName`, `membershipId`, `membershipRole`, `clientType`,
`clientInstanceId`, `deviceLabel`, `platform`, `appVersion`, `status`,
`createdAt`, `lastSeenAt`, `lastRefreshedAt`, `refreshTokenExpiresAt`,
`expiresAt`, `revokedAt`, `revokedReason`.

Opcionais/fallbacks: `deviceLabel` vira identificador mascarado; app/platform
ausentes viram `Nao informado`; lista vazia mostra que nenhuma sessao foi
registrada.

Telas: Dispositivos e sessoes, Detalhe da empresa.

### License

Models: `AdminLicenseSnapshot`, `AdminBillingLicenseSnapshot`,
`AdminLicenseExtensionDryRun`, `AdminLicenseExtensionResult`,
`AdminLicenseStatusActionDryRun`, `AdminLicenseStatusActionResult`.

Campos conhecidos: `id`, `companyId`, `companyName`, `plan`, `status`,
`startsAt`, `expiresAt`, `maxDevices`, `syncEnabled`, `pendingPlan`,
`reason`, `expectedConfirmationText`, `risks`, `blockers`.

Opcionais/fallbacks: `plan` pode usar `FREE`; `status` pode usar `ACTIVE`;
datas ausentes aparecem como `Nao informado`/`Sem dados`; `pendingPlan`
ausente aparece como `Nenhum`.

Telas: Licencas, Billing da empresa, Central de Suporte.

### Billing

Models: `AdminBillingCompanySummary`, `AdminBillingCompanyStatus`,
`AdminBillingStatusSnapshot`, `AdminBillingCheckoutSession`,
`AdminBillingEvent`, `AdminBillingAuditLog`, `AdminBillingInvoiceSummary`,
`AdminBillingActionResult`, `AdminBillingReconcileDryRun`,
`AdminBillingReconcileResult`.

Campos conhecidos: `provider`, `providerSubscriptionId` mascarado, `plan`,
`status`, `billingSubscriptionStatus`, `checkoutUrl`, `eventType`, `metadata`,
`reason`, `actor`, `createdAt`, `updatedAt`, `dryRun`.

Opcionais/fallbacks: provider ausente usa `provider`; plano usa `FREE`; status
usa `unknown`; moeda usa `BRL`; dados sensiveis sao sanitizados antes de
renderizar.

Telas: Billing, Licencas, Central de Suporte, Auditoria.

### Sync

Models: `AdminCompanySyncHealth`, `AdminSyncCenterCompany`,
`AdminSyncCenterCompanySummary`, `AdminSyncEventDiagnostic`,
`AdminSyncConflictDiagnostic`, `AdminSyncIncidentDiagnostic`,
`AdminSyncSupportDevice`, `AdminSyncSupportDiagnostic`.

Campos conhecidos: `status`, `syncEnabled`, `currentServerVersion`,
`serverFirstSnapshotVersion`, `lastSyncAt`, `lastMaterializedAt`, `events`,
`openConflictsCount`, `lastIncident`, `pendingCount`, `failedCount`,
`openConflictCount`, `lastLocalError`, `reportedAt`, `classification`,
`recommendedAction`, `safePayloadPreview`.

Opcionais/fallbacks: versoes usam `0`; status de empresa usa `healthy`;
classificacao usa `UNKNOWN`; recommended action usa `CONTACT_SUPPORT`; sem
sync recente vira `Sem dados recentes de sync` ou `Nenhum sync recente`;
diagnostico ausente vira `Sem dados`.

Telas: Sync Center global, Sync Center por empresa, Dispositivos, Central de
Suporte.

### Audit Event

Models: `AdminAuditSummary`, `AdminAuditLogPage`, `AdminAuditEntry`,
`AdminBillingAuditLog`, `AdminCompanyAccessAuditEvent`.

Campos conhecidos: `id`, `source`, `category`, `action`, `status`, `companyId`,
`companyName`, `actorUserId`, `actorName`, `actorEmail`, `targetType`,
`targetId`, `targetLabel`, `reason`, `summary`, `createdAt`, `ipAddress`,
`userAgent`, `metadata`, `before`, `after`.

Opcionais/fallbacks: empresa ausente vira `Nao informado`; ator ausente vira
`Sistema`/`Nao informado`; recurso ausente vira `Sem recurso relacionado`;
motivo/contexto ausente vira `Sem contexto registrado`; IP ausente vira
`Indisponivel`; JSON sensivel e sanitizado.

Telas: Auditoria, Dashboard, Central de Suporte, Billing, Usuarios e
funcionarios.

### Operational Status

Widget/modelo visual: `AdminOperationalStatus`, `AdminOperationalTone`.

Estados: `ok`, `attention`, `critical`, `noData`. Rotulos visiveis: `OK`,
`Atencao`, `Critico`, `Sem dados`.

Uso: console operacional de usuarios/dispositivos/sessoes, Sync Center,
Auditoria e Central de Suporte.

## Erros e Estados Vazios

| Caso | Mensagem/estado | Tela | Comportamento |
| --- | --- | --- | --- |
| Rota invalida | `Rota invalida` e local solicitado | `AdminRouteErrorPage` | Mostra CTA para dashboard. |
| Empresa nao encontrada | Erro de carregamento ou dados indisponiveis | Detalhe/Support/Sync | Mostra erro seguro com retry quando provider falha. |
| Dados indisponiveis | `Indisponivel`, `Sem dados`, `Nao informado` | Todas as areas operacionais | Renderiza fallback sem quebrar layout. |
| Lista vazia de empresas | `Nenhuma empresa encontrada para os filtros.` | Empresas/Sync/Billing | Mantem filtros e permite limpar/ajustar. |
| Lista vazia de usuarios | `Nenhum usuario encontrado...` | Usuarios | Estado vazio explicativo. |
| Lista vazia de funcionarios | `Nenhum funcionario encontrado...` | Funcionarios | Estado vazio explicativo. |
| Lista vazia de dispositivos | `Nenhum dispositivo encontrado para os filtros...` | Dispositivos | Estado vazio explicativo. |
| Lista vazia de sessoes | `Nenhuma sessao registrada...` | Dispositivos | Estado vazio explicativo. |
| Sync sem eventos | `Nenhum evento de sync encontrado...` | Sync Center | Estado vazio read-only. |
| Sync sem conflitos | `Nenhum conflito OPEN...` | Sync Center | Estado vazio read-only. |
| Auditoria sem eventos | `Nenhum evento de auditoria encontrado...` | Auditoria | Estado vazio ajustado por filtro/empresa. |
| Billing sem historico | `Nenhum evento de billing encontrado.` | Billing/licenca | Estado vazio read-only. |
| Falha de autenticacao | Login/restore falha e sessao nao e restaurada | Login/shell | Usuario volta ao fluxo de login. |
| Erro generico de API | `Nao foi possivel carregar...` + erro sanitizado | Varias telas | Exibe CTA `Tentar novamente` ou `Atualizar`. |

## Mapa de Dependencias por Tela

| Tela | Dados principais | Providers/service |
| --- | --- | --- |
| Empresas | lista de empresas, licenca, contadores | `fetchCompanies` |
| Detalhe da empresa | empresa, memberships, sessoes, licenca, sync health | `fetchCompanyDetail`, `fetchCompanySyncHealth`, billing/license providers |
| Central de Suporte | empresa, billing, dispositivos, sessoes, acesso, sync, auditoria | `fetchCompanyDetail`, `fetchBillingCompanyStatus`, `fetchDevices`, `fetchCompanySessions`, `fetchCompanyAccessSummary`, `fetchSyncCenterCompanySummary`, `fetchAuditLogs` |
| Usuarios | usuarios, funcionarios, permissoes, dispositivos, auditoria de acesso | `fetchCompanyAccessSummary` |
| Funcionarios | perfis, convites, permissoes, auditoria | `fetchCompanyAccessSummary` |
| Dispositivos | inventario global/empresa, sessoes por empresa | `fetchDevices`, `fetchCompanySessions` |
| Billing | empresas com billing, status, eventos, checkout, auditoria | billing endpoints em `AdminApiService` |
| Licencas | licencas, planos, billing relacionado | `fetchLicenses`, `fetchPlansOverview`, billing endpoints |
| Sync Center | empresas, resumo, health, eventos, conflitos, incidentes, devices | sync endpoints em `AdminApiService` |
| Auditoria | eventos normalizados, resumo, filtros | `fetchAuditLogs`, `fetchAuditSummary` |

## Lacunas Identificadas

- Vinculo mais rico e padronizado entre usuario, sessao e dispositivo.
- Severidade/contexto de auditoria vindo do backend, em vez de inferencia visual
  no front-end.
- Janela configuravel para classificar `sem sync recente`.
- Estrutura padronizada para ultimo erro local/remoto.
- Permissoes operacionais futuras por tipo de acao.
- Payload auditavel minimo para acoes reais de suporte.
- Dry-run consistente para todas as acoes operacionais.
- Motivo obrigatorio em todas as acoes operacionais reais.
- Resultado auditavel de operacoes com sucesso, falha, bloqueio e rollback.
- Documentacao oficial compartilhada entre backend e admin_web.

## Regras Futuras para Acoes Operacionais

Qualquer acao real futura no Admin Web deve exigir:

- dry-run quando aplicavel;
- confirmacao explicita com texto esperado;
- motivo obrigatorio;
- ator/admin identificado;
- registro de auditoria;
- resultado da operacao;
- payload/contexto minimo seguro;
- tratamento de erro auditavel;
- permissoes especificas por tipo de acao;
- ausencia de dados sensiveis em UI, logs, payload preview e auditoria.

