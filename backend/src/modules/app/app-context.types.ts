import type {
  FeatureKey,
  PlanKey,
  PlanLimits,
} from '../plans/plan-catalog.service';

export type AppContextUser = {
  id: string;
  name: string;
  email: string;
};

export type AppContextCompany = {
  id: string;
  name: string;
  legalName: string;
  documentNumber: string | null;
  receiptDisplayName: string | null;
  receiptDocument: string | null;
  receiptPhone: string | null;
  receiptAddress: string | null;
  receiptFooterMessage: string | null;
  showDocumentOnReceipt: boolean;
  showPhoneOnReceipt: boolean;
  showAddressOnReceipt: boolean;
  showFooterMessageOnReceipt: boolean;
  setupCompleted: boolean;
};

export type AppContextMembership = {
  id: string;
  role: string;
  permissions: string[];
};

export type AppContextEmployee = {
  id: string;
  role: string;
  status: string;
  permissions: string[];
};

export type AppContextLicense = {
  id: string;
  plan: string;
  status: string;
  syncEnabled: boolean;
  maxDevices: number | null;
  expiresAt: string | null;
};

export type AppContextDevice = {
  id: string;
  clientInstanceId: string;
  status: string;
  deviceLabel: string | null;
  platform: string | null;
  appVersion: string | null;
  lastSeenAt: string | null;
};

export type AppContext = {
  user: AppContextUser;
  company: AppContextCompany;
  membership: AppContextMembership;
  employee?: AppContextEmployee | null;
  license: AppContextLicense;
  device: AppContextDevice;
  plan: PlanKey;
  features: Record<FeatureKey, boolean>;
  limits: PlanLimits;
  clientInstanceId: string;
  tenantReady: true;
};
