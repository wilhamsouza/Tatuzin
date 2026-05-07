export type PlanKey = 'FREE' | 'BASIC' | 'PRO';

export type FeatureKey =
  | 'sales'
  | 'cash'
  | 'products'
  | 'categories'
  | 'customersBasic'
  | 'fiadoCreateSale'
  | 'fiadoManagement'
  | 'supplies'
  | 'costs'
  | 'suppliers'
  | 'purchases'
  | 'inventoryBasic'
  | 'inventoryAdvanced'
  | 'reportsDaily'
  | 'reportsBasic'
  | 'reportsAdvanced'
  | 'employees'
  | 'permissions'
  | 'multiDevice'
  | 'ownerWebPanel'
  | 'commissions'
  | 'devicesManagement';

export type ReportPeriodKey =
  | 'daily'
  | 'weekly'
  | 'monthly'
  | 'yearly'
  | 'custom';

export type PlanLimits = {
  maxDevices: number;
  maxEmployees: number;
  reportPeriods: ReportPeriodKey[];
};

export type PlanEntitlements = {
  plan: PlanKey;
  features: Record<FeatureKey, boolean>;
  limits: PlanLimits;
};

export const FEATURE_KEYS: FeatureKey[] = [
  'sales',
  'cash',
  'products',
  'categories',
  'customersBasic',
  'fiadoCreateSale',
  'fiadoManagement',
  'supplies',
  'costs',
  'suppliers',
  'purchases',
  'inventoryBasic',
  'inventoryAdvanced',
  'reportsDaily',
  'reportsBasic',
  'reportsAdvanced',
  'employees',
  'permissions',
  'multiDevice',
  'ownerWebPanel',
  'commissions',
  'devicesManagement',
];

export const PLAN_KEYS: PlanKey[] = ['FREE', 'BASIC', 'PRO'];

const FREE_FEATURES: FeatureKey[] = [
  'sales',
  'cash',
  'products',
  'categories',
  'customersBasic',
  'fiadoCreateSale',
  'reportsDaily',
  'inventoryBasic',
];

const BASIC_FEATURES: FeatureKey[] = [
  ...FREE_FEATURES,
  'fiadoManagement',
  'supplies',
  'costs',
  'suppliers',
  'purchases',
  'inventoryAdvanced',
  'reportsBasic',
];

export const PLAN_CATALOG: Record<PlanKey, PlanEntitlements> = {
  FREE: {
    plan: 'FREE',
    features: featuresRecord(FREE_FEATURES),
    limits: {
      maxDevices: 1,
      maxEmployees: 0,
      reportPeriods: ['daily'],
    },
  },
  BASIC: {
    plan: 'BASIC',
    features: featuresRecord(BASIC_FEATURES),
    limits: {
      maxDevices: 1,
      maxEmployees: 0,
      reportPeriods: ['daily', 'weekly', 'monthly'],
    },
  },
  PRO: {
    plan: 'PRO',
    features: featuresRecord(FEATURE_KEYS),
    limits: {
      maxDevices: 100,
      maxEmployees: 100,
      reportPeriods: ['daily', 'weekly', 'monthly', 'yearly', 'custom'],
    },
  },
};

export function normalizePlan(rawPlan: string | null | undefined): PlanKey {
  const normalized = (rawPlan ?? '').trim().toLowerCase();
  switch (normalized) {
    case 'free':
      return 'FREE';
    case 'basic':
      return 'BASIC';
    case 'pro':
      return 'PRO';
    case 'trial':
      // TODO: introduce dedicated trial entitlements when trial policy is defined.
      return 'FREE';
    default:
      return 'FREE';
  }
}

export function getPlanEntitlements(
  rawPlan: string | null | undefined,
): PlanEntitlements {
  const plan = normalizePlan(rawPlan);
  const entitlements = PLAN_CATALOG[plan];
  return {
    plan,
    features: { ...entitlements.features },
    limits: {
      ...entitlements.limits,
      reportPeriods: [...entitlements.limits.reportPeriods],
    },
  };
}

export function hasFeature(
  rawPlan: string | null | undefined,
  feature: FeatureKey,
) {
  return getPlanEntitlements(rawPlan).features[feature] === true;
}

export function requiredPlanForFeature(feature: FeatureKey): PlanKey | null {
  for (const plan of PLAN_KEYS) {
    if (PLAN_CATALOG[plan].features[feature]) {
      return plan;
    }
  }
  return null;
}

function featuresRecord(enabledFeatures: FeatureKey[]) {
  const enabled = new Set(enabledFeatures);
  return FEATURE_KEYS.reduce(
    (record, feature) => ({
      ...record,
      [feature]: enabled.has(feature),
    }),
    {} as Record<FeatureKey, boolean>,
  );
}
