import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, it } from "node:test";

import { env } from "../../config/env";
import { AppError } from "../../shared/http/app-error";
import { AuthService } from "./auth.service";
import type { RegisterInitialInput } from "./auth.schemas";
import type { SessionTokenBundle } from "./auth-session.service";

const previousAllowInitialBootstrap = env.ALLOW_INITIAL_BOOTSTRAP;

beforeEach(() => {
  env.ALLOW_INITIAL_BOOTSTRAP = true;
});

afterEach(() => {
  env.ALLOW_INITIAL_BOOTSTRAP = previousAllowInitialBootstrap;
});

describe("AuthService.registerInitial", () => {
  it("rejects bootstrap when the environment flag is disabled", async () => {
    env.ALLOW_INITIAL_BOOTSTRAP = false;
    const fakeDb = new FakeBootstrapDb();
    const service = createService(fakeDb);

    await assert.rejects(
      () => service.registerInitial(makeInput({ password: "OwnerPass123!" })),
      (error: unknown) => hasAppErrorCode(error, "BOOTSTRAP_DISABLED"),
    );

    assert.equal(fakeDb.transactionCount, 0);
    assert.equal(fakeDb.users.length, 0);
  });

  it("rejects bootstrap after a user already exists and releases the lock", async () => {
    const fakeDb = new FakeBootstrapDb();
    fakeDb.users.push({ id: "existing-user" });
    const service = createService(fakeDb);
    const password = "OwnerPass123!";

    await assert.rejects(
      () => service.registerInitial(makeInput({ password })),
      (error: unknown) => {
        const serialized = JSON.stringify(error);
        assert.equal(serialized.includes(password), false);
        return hasAppErrorCode(error, "BOOTSTRAP_ALREADY_COMPLETED");
      },
    );

    assert.equal(fakeDb.committedOwners, 0);
    assert.equal(fakeDb.activeLocks, 0);
    assert.deepEqual(
      fakeDb.events.map((event) => event.op),
      [
        "lock-requested",
        "lock-acquired",
        "user-count",
        "rollback",
        "lock-released",
      ],
    );
  });

  it("creates the initial owner after acquiring the advisory lock inside the transaction", async () => {
    const fakeDb = new FakeBootstrapDb();
    const service = createService(fakeDb);

    const { result, logs } = await captureLogs(() =>
      service.registerInitial(makeInput({ password: "OwnerPass123!" })),
    );

    assert.equal(result.user.isPlatformAdmin, true);
    assert.equal(result.membership.role, "OWNER");
    assert.equal(fakeDb.committedOwners, 1);
    assert.equal(fakeDb.users.length, 1);
    assert.equal(fakeDb.activeLocks, 0);
    assert.equal(fakeDb.maxActiveLocks, 1);

    const txId = fakeDb.events.find((event) => event.op === "lock-requested")
      ?.txId;
    assert.ok(txId != null);
    for (const op of ["user-count", "company-create", "user-create", "membership-create"]) {
      assert.equal(fakeDb.events.find((event) => event.op === op)?.txId, txId);
    }
    assertEventOrder(fakeDb.events, [
      "lock-requested",
      "lock-acquired",
      "user-count",
      "company-create",
      "user-create",
      "license-create",
      "membership-create",
      "commit",
      "lock-released",
    ]);

    const serializedLogs = logs.join("\n");
    assert.equal(serializedLogs.includes("OwnerPass123!"), false);
    assert.equal(serializedLogs.includes("access-secret"), false);
    assert.equal(serializedLogs.includes("refresh-secret"), false);
    assert.equal(serializedLogs.includes("session-secret"), false);
  });

  it("serializes concurrent attempts so two owners cannot be created", async () => {
    const fakeDb = new FakeBootstrapDb();
    const service = createService(fakeDb);

    const [first, second] = await Promise.allSettled([
      service.registerInitial(makeInput({ companySlug: "first-company" })),
      service.registerInitial(makeInput({ companySlug: "second-company" })),
    ]);

    const results = [first, second];
    assert.equal(
      results.filter((result) => result.status === "fulfilled").length,
      1,
    );
    const rejected = results.find(
      (result): result is PromiseRejectedResult => result.status === "rejected",
    );
    assert.ok(rejected);
    assert.equal(rejected.reason.code, "BOOTSTRAP_ALREADY_COMPLETED");
    assert.equal(fakeDb.committedOwners, 1);
    assert.equal(fakeDb.users.length, 1);
    assert.equal(fakeDb.activeLocks, 0);
    assert.equal(fakeDb.maxActiveLocks, 1);
    assert.equal(
      fakeDb.events.filter((event) => event.op === "membership-create").length,
      1,
    );
  });

  it("rolls back staged records and releases the lock when creation fails", async () => {
    const fakeDb = new FakeBootstrapDb();
    fakeDb.failMembershipCreate = true;
    const service = createService(fakeDb);

    await assert.rejects(
      () => service.registerInitial(makeInput()),
      /membership-create-failed/,
    );

    assert.equal(fakeDb.committedOwners, 0);
    assert.equal(fakeDb.users.length, 0);
    assert.equal(fakeDb.rolledBackTransactions, 1);
    assert.equal(fakeDb.activeLocks, 0);
    assertEventOrder(fakeDb.events, [
      "lock-requested",
      "lock-acquired",
      "user-count",
      "company-create",
      "user-create",
      "license-create",
      "membership-create",
      "rollback",
      "lock-released",
    ]);
  });
});

function createService(fakeDb: FakeBootstrapDb) {
  return new AuthService(
    new FakeSessionService() as never,
    undefined,
    fakeDb as never,
  );
}

function makeInput(overrides: Partial<RegisterInitialInput> = {}): RegisterInitialInput {
  return {
    companyName: "Bootstrap Company",
    companySlug: "bootstrap-company",
    userName: "Bootstrap Owner",
    email: "owner@bootstrap.test",
    password: "OwnerPass123!",
    clientType: "admin_web",
    clientInstanceId: "bootstrap-client",
    deviceLabel: "Unit Test Browser",
    platform: "node-test",
    appVersion: "unit-test",
    ...overrides,
  };
}

function hasAppErrorCode(error: unknown, code: string) {
  assert.ok(error instanceof AppError);
  assert.equal(error.code, code);
  return true;
}

type FakeEvent = {
  txId: number;
  op: string;
};

type FakeUser = {
  id: string;
};

type FakeCompany = {
  id: string;
  name: string;
  legalName: string;
  slug: string;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
};

type FakeLicense = {
  id: string;
  companyId: string;
  plan: string;
  status: string;
  startsAt: Date;
  expiresAt: Date | null;
  maxDevices: number | null;
  syncEnabled: boolean;
  pendingPlan: string | null;
  pendingPlanRequestedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
};

type FakeCreatedUser = FakeUser & {
  email: string;
  name: string;
  passwordHash: string;
  isActive: boolean;
  isPlatformAdmin: boolean;
  mustChangePassword: boolean;
  temporaryPasswordExpiresAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
};

class FakeBootstrapDb {
  users: FakeUser[] = [];
  events: FakeEvent[] = [];
  activeLocks = 0;
  maxActiveLocks = 0;
  committedOwners = 0;
  rolledBackTransactions = 0;
  failMembershipCreate = false;
  transactionCount = 0;

  private lockTail: Promise<void> = Promise.resolve();
  private nextTxId = 0;

  async $transaction<T>(callback: (transaction: FakeTransaction) => Promise<T>) {
    this.transactionCount += 1;
    const transaction = new FakeTransaction(this, ++this.nextTxId);
    try {
      const result = await callback(transaction);
      transaction.commit();
      this.events.push({ txId: transaction.txId, op: "commit" });
      return result;
    } catch (error) {
      this.rolledBackTransactions += 1;
      this.events.push({ txId: transaction.txId, op: "rollback" });
      throw error;
    } finally {
      transaction.releaseLock();
    }
  }

  async acquireLock(txId: number) {
    this.events.push({ txId, op: "lock-requested" });
    let releaseNext: () => void = () => undefined;
    const previous = this.lockTail;
    this.lockTail = new Promise<void>((resolve) => {
      releaseNext = resolve;
    });

    await previous;
    this.activeLocks += 1;
    this.maxActiveLocks = Math.max(this.maxActiveLocks, this.activeLocks);
    this.events.push({ txId, op: "lock-acquired" });

    return () => {
      this.activeLocks -= 1;
      this.events.push({ txId, op: "lock-released" });
      releaseNext();
    };
  }
}

class FakeTransaction {
  readonly txId: number;
  private releaseCurrentLock: (() => void) | null = null;
  private stagedUsers: FakeCreatedUser[] = [];
  private stagedCompanies: FakeCompany[] = [];
  private stagedLicenses: FakeLicense[] = [];

  constructor(
    private readonly db: FakeBootstrapDb,
    txId: number,
  ) {
    this.txId = txId;
  }

  $executeRaw = async (_sql: unknown) => {
    this.releaseCurrentLock = await this.db.acquireLock(this.txId);
  };

  user = {
    count: async () => {
      this.db.events.push({ txId: this.txId, op: "user-count" });
      return this.db.users.length;
    },
    create: async (input: {
      data: {
        email: string;
        name: string;
        passwordHash: string;
        isPlatformAdmin: boolean;
      };
    }) => {
      this.db.events.push({ txId: this.txId, op: "user-create" });
      const now = new Date("2026-01-01T00:00:00.000Z");
      const user: FakeCreatedUser = {
        id: `user-${this.txId}`,
        email: input.data.email,
        name: input.data.name,
        passwordHash: input.data.passwordHash,
        isActive: true,
        isPlatformAdmin: input.data.isPlatformAdmin,
        mustChangePassword: false,
        temporaryPasswordExpiresAt: null,
        createdAt: now,
        updatedAt: now,
      };
      this.stagedUsers.push(user);
      return user;
    },
  };

  company = {
    create: async (input: {
      data: { name: string; legalName: string; slug: string };
    }) => {
      this.db.events.push({ txId: this.txId, op: "company-create" });
      const now = new Date("2026-01-01T00:00:00.000Z");
      const company: FakeCompany = {
        id: `company-${this.txId}`,
        name: input.data.name,
        legalName: input.data.legalName,
        slug: input.data.slug,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      };
      this.stagedCompanies.push(company);
      return company;
    },
  };

  license = {
    create: async (input: {
      data: {
        companyId: string;
        plan: string;
        status: string;
        startsAt: Date;
        expiresAt: Date | null;
        syncEnabled: boolean;
      };
    }) => {
      this.db.events.push({ txId: this.txId, op: "license-create" });
      const license: FakeLicense = {
        id: `license-${this.txId}`,
        companyId: input.data.companyId,
        plan: input.data.plan,
        status: input.data.status,
        startsAt: input.data.startsAt,
        expiresAt: input.data.expiresAt,
        maxDevices: null,
        syncEnabled: input.data.syncEnabled,
        pendingPlan: null,
        pendingPlanRequestedAt: null,
        createdAt: input.data.startsAt,
        updatedAt: input.data.startsAt,
      };
      this.stagedLicenses.push(license);
      return license;
    },
  };

  membership = {
    create: async () => {
      this.db.events.push({ txId: this.txId, op: "membership-create" });
      if (this.db.failMembershipCreate) {
        throw new Error("membership-create-failed");
      }

      const user = this.stagedUsers[0]!;
      const company = this.stagedCompanies[0]!;
      const license = this.stagedLicenses[0]!;
      return {
        id: `membership-${this.txId}`,
        userId: user.id,
        companyId: company.id,
        role: "OWNER",
        isDefault: true,
        user,
        employeeProfiles: [],
        company: {
          ...company,
          license,
        },
      };
    },
  };

  commit() {
    this.db.users.push(...this.stagedUsers);
    if (this.stagedUsers.length > 0) {
      this.db.committedOwners += 1;
    }
  }

  releaseLock() {
    this.releaseCurrentLock?.();
    this.releaseCurrentLock = null;
  }
}

class FakeSessionService {
  async createSession(input: {
    userId: string;
    userEmail: string;
    companyId: string;
    membershipId: string;
    membershipRole: string;
    clientInput: {
      clientType: "mobile_app" | "admin_web" | "unknown";
      clientInstanceId: string;
      deviceLabel?: string;
      platform?: string;
      appVersion?: string;
    };
  }): Promise<SessionTokenBundle> {
    const now = "2026-01-01T00:00:00.000Z";
    return {
      accessToken: "access-secret",
      refreshToken: "refresh-secret",
      tokenType: "Bearer",
      expiresIn: "12h",
      refreshTokenExpiresAt: now,
      device: {} as SessionTokenBundle["device"],
      session: {
        id: "session-secret",
        userId: input.userId,
        userName: "Bootstrap Owner",
        userEmail: input.userEmail,
        companyId: input.companyId,
        companyName: "Bootstrap Company",
        membershipId: input.membershipId,
        membershipRole: input.membershipRole,
        clientType: input.clientInput.clientType,
        clientInstanceId: input.clientInput.clientInstanceId,
        deviceLabel: input.clientInput.deviceLabel ?? null,
        platform: input.clientInput.platform ?? null,
        appVersion: input.clientInput.appVersion ?? null,
        status: "active",
        createdAt: now,
        lastSeenAt: now,
        lastRefreshedAt: null,
        refreshTokenExpiresAt: now,
        revokedAt: null,
        revokedReason: null,
      },
    };
  }
}

async function captureLogs<T>(action: () => Promise<T>) {
  const originalLog = console.log;
  const lines: string[] = [];
  console.log = (line?: unknown) => {
    lines.push(String(line));
  };

  try {
    return {
      result: await action(),
      logs: lines,
    };
  } finally {
    console.log = originalLog;
  }
}

function assertEventOrder(events: FakeEvent[], expected: string[]) {
  assert.deepEqual(
    events.map((event) => event.op),
    expected,
  );
}
