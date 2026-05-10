import type { AppContext } from './app-context.types';

const SERVER_VERSION = 'app-context-v1';

export class AppBootstrapService {
  buildPayload(context: AppContext) {
    return {
      user: context.user,
      company: context.company,
      membership: context.membership,
      employee: context.employee ?? null,
      license: context.license,
      plan: context.plan,
      features: context.features,
      limits: context.limits,
      device: {
        id: context.device.id,
        clientInstanceId: context.device.clientInstanceId,
        status: context.device.status,
        deviceLabel: context.device.deviceLabel,
        platform: context.device.platform,
        appVersion: context.device.appVersion,
      },
      sync: {
        enabled: context.license.syncEnabled,
        serverVersion: SERVER_VERSION,
        pullRequired: false,
      },
    };
  }
}

export function buildSyncContract(context: AppContext) {
  return {
    enabled: context.license.syncEnabled,
    serverVersion: SERVER_VERSION,
    pullRequired: false,
  };
}
