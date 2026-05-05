export type AppContextUser = {
  id: string;
  name: string;
  email: string;
};

export type AppContextCompany = {
  id: string;
  name: string;
  setupCompleted: boolean;
};

export type AppContextMembership = {
  id: string;
  role: string;
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
  license: AppContextLicense;
  device: AppContextDevice;
  clientInstanceId: string;
  tenantReady: true;
};
