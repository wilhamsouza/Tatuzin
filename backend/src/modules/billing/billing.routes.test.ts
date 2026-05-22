import assert from "node:assert/strict";
import { createHmac } from "crypto";
import { after, before, beforeEach, describe, it } from "node:test";
import type { AddressInfo } from "node:net";

import type { Server } from "http";
import jwt from "jsonwebtoken";

import { createApp } from "../../app";
import { env } from "../../config/env";
import { prisma } from "../../database/prisma";

const runId = `billing-${Date.now()}`;
const webhookSecret = "billing-webhook-secret";

let server: Server;
let apiBaseUrl = "";
let originalFetch: typeof globalThis.fetch;
const originalEnv = {
  accessToken: env.MERCADO_PAGO_ACCESS_TOKEN,
  webhookSecret: env.MERCADO_PAGO_WEBHOOK_SECRET,
  apiPublicUrl: env.API_PUBLIC_URL,
  isProduction: env.isProduction,
};

describe("billing routes", () => {
  before(async () => {
    await prisma.$connect();
    originalFetch = globalThis.fetch;
    env.MERCADO_PAGO_ACCESS_TOKEN = "test-mercado-token";
    env.MERCADO_PAGO_WEBHOOK_SECRET = webhookSecret;
    server = createApp().listen(0);
    const address = server.address() as AddressInfo;
    apiBaseUrl = `http://127.0.0.1:${address.port}/api`;
  });

  beforeEach(async () => {
    await cleanupFixtures();
    globalThis.fetch = originalFetch;
    env.MERCADO_PAGO_ACCESS_TOKEN = "test-mercado-token";
    env.MERCADO_PAGO_WEBHOOK_SECRET = webhookSecret;
    env.API_PUBLIC_URL = originalEnv.apiPublicUrl;
    env.isProduction = false;
  });

  after(async () => {
    await cleanupFixtures();
    env.MERCADO_PAGO_ACCESS_TOKEN = originalEnv.accessToken;
    env.MERCADO_PAGO_WEBHOOK_SECRET = originalEnv.webhookSecret;
    env.API_PUBLIC_URL = originalEnv.apiPublicUrl;
    env.isProduction = originalEnv.isProduction;
    globalThis.fetch = originalFetch;
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error == null ? resolve() : reject(error)));
    });
    await prisma.$disconnect();
  });

  it("lists public FREE/BASIC/PRO billing plans with default prices", async () => {
    const response = await requestJson("GET", "/billing/plans");

    assert.equal(response.status, 200);
    const items = (
      response.data as { items: Array<{ key: string; priceCents: number }> }
    ).items;
    assert.deepEqual(
      items.map((item) => [item.key, item.priceCents]),
      [
        ["FREE", 0],
        ["BASIC", 3500],
        ["PRO", 8500],
      ],
    );
  });

  it("returns billing status from local database without exposing full provider id", async () => {
    const fixture = await createFixture({
      plan: "basic",
      providerSubscriptionId: "preapproval-1234567890",
    });
    globalThis.fetch = failFetch("status must not call Mercado Pago");

    const response = await requestJson("GET", "/billing/status", {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      plan: string;
      hasProviderSubscription: boolean;
      maskedProviderSubscriptionId?: string;
      providerSubscriptionId?: string;
    };
    assert.equal(payload.plan, "BASIC");
    assert.equal(payload.hasProviderSubscription, true);
    assert.equal(payload.maskedProviderSubscriptionId, "prea...7890");
    assert.equal(payload.providerSubscriptionId, undefined);
  });

  it("includes pending and cancel fields in billing status without exposing provider id", async () => {
    const future = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    const fixture = await createFixture({
      plan: "pro",
      providerSubscriptionId: "preapproval-status-1234567890",
    });
    await prisma.license.update({
      where: { companyId: fixture.companyId },
      data: {
        currentPeriodEnd: future,
        pendingPlan: "BASIC",
        pendingPlanRequestedAt: new Date(),
        cancelAtPeriodEnd: true,
        cancelRequestedAt: new Date(),
        billingSubscriptionStatus: "CUSTOMER_CANCEL_PERIOD_END",
      },
    });

    const response = await requestJson("GET", "/billing/status", {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      plan: string;
      pendingPlan?: string | null;
      cancelAtPeriodEnd?: boolean;
      billingSubscriptionStatus?: string | null;
      providerSubscriptionId?: string;
    };
    assert.equal(payload.plan, "PRO");
    assert.equal(payload.pendingPlan, "BASIC");
    assert.equal(payload.cancelAtPeriodEnd, true);
    assert.equal(
      payload.billingSubscriptionStatus,
      "CUSTOMER_CANCEL_PERIOD_END",
    );
    assert.equal(payload.providerSubscriptionId, undefined);
  });

  it("creates BASIC checkout session without changing license.plan", async () => {
    const fixture = await createFixture({ plan: "free" });
    env.API_PUBLIC_URL = "https://api.tatuzin.com.br";
    let capturedBody = {} as Record<string, any>;
    globalThis.fetch = jsonFetch(async (_url, init) => {
      capturedBody = JSON.parse(init.body ?? "{}") as Record<string, unknown>;
      return {
        id: "mp-basic-1",
        init_point: "https://mercadopago.test/basic",
        sandbox_init_point: "https://sandbox.mercadopago.test/basic",
        status: "pending",
      };
    });

    const response = await requestJson("POST", "/billing/subscribe", {
      token: fixture.token,
      body: { plan: "BASIC" },
    });

    assert.equal(response.status, 201);
    const subscribeBody = capturedBody;
    const payload = response.data as {
      checkoutUrl: string;
      checkoutSessionId: string;
    };
    assert.equal(payload.checkoutUrl, "https://mercadopago.test/basic");
    assert.ok(payload.checkoutSessionId);
    assert.equal(
      (subscribeBody.auto_recurring as { frequency?: number }).frequency,
      1,
    );
    assert.equal(
      (subscribeBody.auto_recurring as { frequency_type?: string })
        .frequency_type,
      "months",
    );
    assert.equal(
      (subscribeBody.auto_recurring as { transaction_amount?: number })
        .transaction_amount,
      35,
    );
    assert.equal(
      (subscribeBody.auto_recurring as { currency_id?: string }).currency_id,
      "BRL",
    );
    assert.equal(subscribeBody.status, "pending");
    assert.equal(subscribeBody.external_reference, payload.checkoutSessionId);
    assert.equal(
      subscribeBody.notification_url,
      "https://api.tatuzin.com.br/api/webhooks/mercadopago",
    );

    const session = await prisma.billingCheckoutSession.findUniqueOrThrow({
      where: { id: payload.checkoutSessionId },
    });
    assert.equal(session.providerReference, "mp-basic-1");
    assert.equal(session.checkoutUrl, "https://mercadopago.test/basic");
    assert.equal(
      session.sandboxCheckoutUrl,
      "https://sandbox.mercadopago.test/basic",
    );
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "free");
  });

  it("keeps BASIC while PRO upgrade checkout is pending", async () => {
    const fixture = await createFixture({ plan: "basic" });
    let capturedBody = {} as Record<string, any>;
    globalThis.fetch = jsonFetch(async (_url, init) => {
      capturedBody = JSON.parse(init.body ?? "{}") as Record<string, unknown>;
      return {
        id: "mp-pro-pending",
        init_point: "https://mercadopago.test/pro",
        status: "pending",
      };
    });

    const response = await requestJson("POST", "/billing/subscribe", {
      token: fixture.token,
      body: { plan: "PRO" },
    });

    assert.equal(response.status, 201);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "basic");
    assert.equal(license.pendingPlan, "PRO");
    assert.equal(
      (capturedBody.auto_recurring as { free_trial?: unknown }).free_trial,
      undefined,
    );
  });

  it("creates PRO checkout with 15 day trial for FREE owner without unlocking PRO", async () => {
    const fixture = await createFixture({ plan: "free" });
    let capturedBody = {} as Record<string, any>;
    globalThis.fetch = jsonFetch(async (_url, init) => {
      capturedBody = JSON.parse(init.body ?? "{}") as Record<string, unknown>;
      return {
        id: "mp-pro-trial",
        init_point: "https://mercadopago.test/pro-trial",
        status: "pending",
      };
    });

    const response = await requestJson("POST", "/billing/subscribe", {
      token: fixture.token,
      body: { plan: "PRO" },
    });

    assert.equal(response.status, 201);
    assert.deepEqual(
      (capturedBody.auto_recurring as { free_trial?: unknown }).free_trial,
      { frequency: 15, frequency_type: "days" },
    );
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "free");
    assert.equal(license.pendingPlan, "PRO");
  });

  it("returns friendly subscribe errors and keeps license plan unchanged", async () => {
    const fixture = await createFixture({ plan: "free" });
    globalThis.fetch = failFetch("provider unavailable token=secret 502");

    const response = await requestJson("POST", "/billing/subscribe", {
      token: fixture.token,
      body: { plan: "PRO" },
    });

    assert.equal(response.status, 503);
    const serialized = JSON.stringify(response.data);
    assert.equal(serialized.includes("/api/billing/subscribe"), false);
    assert.equal(serialized.includes("502"), false);
    assert.equal(serialized.includes("provider unavailable"), false);
    assert.equal(
      (response.data as { message?: string }).message,
      "Nao foi possivel iniciar a assinatura agora. Tente novamente em alguns minutos.",
    );
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "free");
    assert.equal(license.pendingPlan, null);
  });

  it("blocks non-owner subscription attempts", async () => {
    const fixture = await createFixture({ role: "OPERATOR" });

    const response = await requestJson("POST", "/billing/subscribe", {
      token: fixture.token,
      body: { plan: "BASIC" },
    });

    assert.equal(response.status, 403);
    assert.equal(
      (response.data as { code?: string }).code,
      "BILLING_OWNER_REQUIRED",
    );
  });

  it("blocks non-owner access to customer billing management endpoints", async () => {
    const fixture = await createFixture({ role: "OPERATOR" });

    for (const request of [
      () => requestJson("GET", "/billing/invoices", { token: fixture.token }),
      () =>
        requestJson("GET", "/billing/payment-method", { token: fixture.token }),
      () =>
        requestJson("POST", "/billing/cancel", {
          token: fixture.token,
          body: {},
        }),
      () => requestJson("POST", "/billing/resume", { token: fixture.token }),
      () =>
        requestJson("POST", "/billing/change-plan", {
          token: fixture.token,
          body: { plan: "PRO" },
        }),
    ]) {
      const response = await request();
      assert.equal(response.status, 403);
      assert.equal(
        (response.data as { code?: string }).code,
        "BILLING_OWNER_REQUIRED",
      );
    }
  });

  it("activates BASIC through signed approved webhook and is idempotent", async () => {
    const fixture = await createFixture({ plan: "free" });
    const checkout = await createCheckoutSession(
      fixture,
      "BASIC",
      "mp-basic-ok",
    );
    let fetchCount = 0;
    globalThis.fetch = jsonFetch(async (url) => {
      if (url.includes("/authorized_payments/search")) {
        return { results: [] };
      }
      fetchCount += 1;
      return {
        id: "mp-basic-ok",
        status: "authorized",
        external_reference: checkout.id,
        next_payment_date: "2026-06-07T00:00:00.000Z",
      };
    });

    const first = await sendWebhook("mp-basic-ok", "subscription_preapproval");
    const second = await sendWebhook("mp-basic-ok", "subscription_preapproval");

    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.equal(fetchCount, 1);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "BASIC");
    assert.equal(license.status, "ACTIVE");
    assert.equal(license.providerSubscriptionId, "mp-basic-ok");

    const bootstrap = await requestJson("GET", "/app/bootstrap", {
      token: fixture.token,
    });
    assert.equal((bootstrap.data as { plan?: string }).plan, "BASIC");
  });

  it("activates PRO through approved webhook and unlocks second device limit", async () => {
    const fixture = await createFixture({ plan: "free" });
    const checkout = await createCheckoutSession(fixture, "PRO", "mp-pro-ok");
    globalThis.fetch = jsonFetch(async () => ({
      id: "mp-pro-ok",
      status: "active",
      external_reference: checkout.id,
    }));

    const webhook = await sendWebhook("mp-pro-ok", "subscription_preapproval");
    assert.equal(webhook.status, 200);

    const secondDevice = await requestJson("POST", "/app/device", {
      token: fixture.ownerTokenWithoutDevice,
      body: {
        clientInstanceId: `${runId}-second-device`,
        deviceLabel: "Second Device",
        platform: "android",
        appVersion: "1.0.0",
      },
    });
    assert.equal(secondDevice.status, 200);
  });

  it("does not change plan for pending rejected or unknown provider statuses", async () => {
    for (const [status, providerRef] of [
      ["pending", "mp-pending"],
      ["in_process", "mp-in-process"],
      ["rejected", "mp-rejected"],
    ]) {
      const fixture = await createFixture({ plan: "basic" });
      const checkout = await createCheckoutSession(fixture, "PRO", providerRef);
      globalThis.fetch = jsonFetch(async () => ({
        id: providerRef,
        status,
        external_reference: checkout.id,
      }));

      const webhook = await sendWebhook(
        providerRef,
        "subscription_preapproval",
      );
      assert.equal(webhook.status, 200);

      const license = await prisma.license.findUniqueOrThrow({
        where: { companyId: fixture.companyId },
      });
      assert.equal(license.plan, "basic", status);
    }
  });

  it("reconciles subscription authorized payment as invoice without activating plan alone", async () => {
    const fixture = await createFixture({ plan: "free" });
    const checkout = await createCheckoutSession(
      fixture,
      "BASIC",
      "mp-auth-payment-preapproval",
    );
    let authorizedPaymentCalled = false;
    let subscriptionCalledWithPreapproval = false;
    let subscriptionCalledWithAuthorizedPaymentId = false;
    globalThis.fetch = jsonFetch(async (url) => {
      if (url.includes("/authorized_payments/auth-pay-1")) {
        authorizedPaymentCalled = true;
        return {
          id: "auth-pay-1",
          status: "processed",
          preapproval_id: "mp-auth-payment-preapproval",
          transaction_amount: 35,
          currency_id: "BRL",
          debit_date: "2026-06-07T00:00:00.000Z",
          date_created: "2026-05-07T00:00:00.000Z",
        };
      }
      if (url.includes("/preapproval/auth-pay-1")) {
        subscriptionCalledWithAuthorizedPaymentId = true;
      }
      if (url.includes("/preapproval/mp-auth-payment-preapproval")) {
        subscriptionCalledWithPreapproval = true;
        return {
          id: "mp-auth-payment-preapproval",
          status: "pending",
          external_reference: checkout.id,
        };
      }
      throw new Error(`unexpected Mercado Pago URL: ${url}`);
    });

    const webhook = await sendWebhook(
      "auth-pay-1",
      "subscription_authorized_payment",
    );

    assert.equal(webhook.status, 200);
    assert.equal(authorizedPaymentCalled, true);
    assert.equal(subscriptionCalledWithPreapproval, true);
    assert.equal(subscriptionCalledWithAuthorizedPaymentId, false);
    const invoice = await prisma.billingInvoice.findFirstOrThrow({
      where: {
        companyId: fixture.companyId,
        provider: "mercadopago",
        providerInvoiceId: "auth-pay-1",
      },
    });
    assert.equal(invoice.providerSubscriptionId, "mp-auth-payment-preapproval");
    assert.equal(invoice.amountCents, 3500);
    assert.equal(invoice.currency, "BRL");
    assert.equal(invoice.status, "processed");
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "free");
  });

  it("locates authorized payment company by license provider subscription id", async () => {
    const fixture = await createFixture({
      plan: "basic",
      providerSubscriptionId: "mp-license-preapproval",
    });
    let subscriptionCalled = false;
    globalThis.fetch = jsonFetch(async (url) => {
      if (url.includes("/authorized_payments/auth-pay-license")) {
        return {
          id: "auth-pay-license",
          status: "processed",
          preapproval_id: "mp-license-preapproval",
          transaction_amount: 35,
          currency_id: "BRL",
        };
      }
      if (url.includes("/preapproval/mp-license-preapproval")) {
        subscriptionCalled = true;
        return {
          id: "mp-license-preapproval",
          status: "pending",
        };
      }
      throw new Error(`unexpected Mercado Pago URL: ${url}`);
    });

    const webhook = await sendWebhook(
      "auth-pay-license",
      "subscription_authorized_payment",
    );

    assert.equal(webhook.status, 200);
    assert.equal(subscriptionCalled, true);
    const invoice = await prisma.billingInvoice.findFirstOrThrow({
      where: {
        companyId: fixture.companyId,
        provider: "mercadopago",
        providerInvoiceId: "auth-pay-license",
      },
    });
    assert.equal(invoice.providerSubscriptionId, "mp-license-preapproval");
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "basic");
  });

  it("keeps plan unchanged and retries when related preapproval lookup fails", async () => {
    const fixture = await createFixture({ plan: "free" });
    await createCheckoutSession(fixture, "BASIC", "mp-related-fails");
    globalThis.fetch = jsonFetch(async (url) => {
      if (url.includes("/authorized_payments/auth-pay-related-fails")) {
        return {
          id: "auth-pay-related-fails",
          status: "processed",
          preapproval_id: "mp-related-fails",
          transaction_amount: 35,
          currency_id: "BRL",
        };
      }
      if (url.includes("/preapproval/mp-related-fails")) {
        throw new Error("related preapproval unavailable");
      }
      throw new Error(`unexpected Mercado Pago URL: ${url}`);
    });

    const webhook = await sendWebhook(
      "auth-pay-related-fails",
      "subscription_authorized_payment",
    );

    assert.equal(webhook.status, 200);
    const event = await prisma.billingProviderEvent.findFirstOrThrow({
      where: { provider: "mercadopago" },
      orderBy: { createdAt: "desc" },
    });
    assert.equal(event.status, "FAILED_RETRYABLE");
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "free");
  });

  it("does not create orphan invoice when authorized payment has no preapproval id", async () => {
    const fixture = await createFixture({ plan: "free" });
    let subscriptionCalled = false;
    globalThis.fetch = jsonFetch(async (url) => {
      if (url.includes("/authorized_payments/auth-pay-without-preapproval")) {
        return {
          id: "auth-pay-without-preapproval",
          status: "processed",
          transaction_amount: 35,
          currency_id: "BRL",
        };
      }
      if (url.includes("/preapproval/")) {
        subscriptionCalled = true;
      }
      throw new Error(`unexpected Mercado Pago URL: ${url}`);
    });

    const webhook = await sendWebhook(
      "auth-pay-without-preapproval",
      "subscription_authorized_payment",
    );

    assert.equal(webhook.status, 200);
    assert.equal(subscriptionCalled, false);
    const invoiceCount = await prisma.billingInvoice.count({
      where: {
        companyId: fixture.companyId,
        providerInvoiceId: "auth-pay-without-preapproval",
      },
    });
    assert.equal(invoiceCount, 0);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "free");
  });

  it("marks authorized payment webhook as retryable when lookup fails", async () => {
    const fixture = await createFixture({ plan: "free" });
    globalThis.fetch = jsonFetch(async () => {
      throw new Error("authorized payment unavailable");
    });

    const webhook = await sendWebhook(
      "auth-pay-fail",
      "subscription_authorized_payment",
    );

    assert.equal(webhook.status, 200);
    const event = await prisma.billingProviderEvent.findFirstOrThrow({
      where: { provider: "mercadopago" },
      orderBy: { createdAt: "desc" },
    });
    assert.equal(event.status, "FAILED_RETRYABLE");
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "free");
  });

  it("treats paused preapproval as neutral and preserves active period", async () => {
    const futurePeriodEnd = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    const fixture = await createFixture({
      plan: "pro",
      providerSubscriptionId: "mp-paused",
      currentPeriodEnd: futurePeriodEnd,
    });
    const checkout = await createCheckoutSession(fixture, "PRO", "mp-paused");
    globalThis.fetch = jsonFetch(async () => ({
      id: "mp-paused",
      status: "paused",
      external_reference: checkout.id,
      next_payment_date: futurePeriodEnd.toISOString(),
    }));

    const webhook = await sendWebhook("mp-paused", "subscription_preapproval");

    assert.equal(webhook.status, 200);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "pro");
    assert.equal(license.billingSubscriptionStatus, "paused");
    assert.equal(
      license.currentPeriodEnd?.toISOString(),
      futurePeriodEnd.toISOString(),
    );
  });

  it("downgrades to FREE on cancelled or expired without deleting data", async () => {
    for (const [status, providerRef] of [
      ["cancelled", "mp-cancelled"],
      ["expired", "mp-expired"],
    ]) {
      const fixture = await createFixture({
        plan: "pro",
        providerSubscriptionId: providerRef,
      });
      const checkout = await createCheckoutSession(fixture, "PRO", providerRef);
      await prisma.product.create({
        data: {
          companyId: fixture.companyId,
          localUuid: `${providerRef}-product`,
          name: "Produto mantido",
          salePriceCents: 1000,
        },
      });
      globalThis.fetch = jsonFetch(async () => ({
        id: providerRef,
        status,
        external_reference: checkout.id,
      }));

      const webhook = await sendWebhook(
        providerRef,
        "subscription_preapproval",
      );
      assert.equal(webhook.status, 200);

      const license = await prisma.license.findUniqueOrThrow({
        where: { companyId: fixture.companyId },
      });
      const productCount = await prisma.product.count({
        where: { companyId: fixture.companyId },
      });
      assert.equal(license.plan, "FREE");
      assert.equal(productCount, 1);
    }
  });

  it("marks webhook as retryable when Mercado Pago lookup fails", async () => {
    const fixture = await createFixture({ plan: "free" });
    await createCheckoutSession(fixture, "BASIC", "mp-fail");
    globalThis.fetch = jsonFetch(async () => {
      throw new Error("provider unavailable");
    });

    const webhook = await sendWebhook("mp-fail", "subscription_preapproval");

    assert.equal(webhook.status, 200);
    const event = await prisma.billingProviderEvent.findFirstOrThrow({
      where: { provider: "mercadopago" },
      orderBy: { createdAt: "desc" },
    });
    assert.equal(event.status, "FAILED_RETRYABLE");
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "free");
  });

  it("rejects unsigned Mercado Pago webhook in production", async () => {
    env.isProduction = true;
    env.MERCADO_PAGO_WEBHOOK_SECRET = webhookSecret;

    const response = await requestJson(
      "POST",
      "/webhooks/mercadopago?data.id=mp-no-signature",
      {
        body: {
          type: "subscription_preapproval",
          data: { id: "mp-no-signature" },
        },
      },
    );

    assert.equal(response.status, 401);
    assert.equal(
      (response.data as { code?: string }).code,
      "MERCADO_PAGO_WEBHOOK_SIGNATURE_INVALID",
    );
  });

  it("refresh reconciles explicitly and is rate limited", async () => {
    const fixture = await createFixture({ plan: "free" });
    const checkout = await createCheckoutSession(
      fixture,
      "BASIC",
      "mp-refresh",
    );
    globalThis.fetch = jsonFetch(async () => ({
      id: "mp-refresh",
      status: "approved",
      external_reference: checkout.id,
    }));

    const refreshed = await requestJson("POST", "/billing/refresh", {
      token: fixture.token,
    });
    assert.equal(refreshed.status, 200);
    assert.equal((refreshed.data as { plan?: string }).plan, "BASIC");

    for (let index = 0; index < 3; index += 1) {
      await requestJson("POST", "/billing/refresh", { token: fixture.token });
    }
    const limited = await requestJson("POST", "/billing/refresh", {
      token: fixture.token,
    });
    assert.equal(limited.status, 429);
  });

  it("lists and reads safe invoices only for the current company", async () => {
    const fixture = await createFixture({
      plan: "basic",
      providerSubscriptionId: "mp-invoice-sub-1234567890",
    });
    const other = await createFixture({ plan: "basic" });
    const paidInvoice = await prisma.billingInvoice.create({
      data: {
        companyId: fixture.companyId,
        provider: "mercadopago",
        providerInvoiceId: "inv-paid",
        providerSubscriptionId: "mp-invoice-sub-1234567890",
        plan: "BASIC",
        status: "paid",
        amountCents: 3500,
        currency: "BRL",
        invoiceUrl: "https://mercadopago.test/invoices/inv-paid?token=secret",
        payload: {
          authorization: "Bearer secret",
          card: { card_number: "4111111111111111" },
        },
      },
    });
    await prisma.billingInvoice.create({
      data: {
        companyId: fixture.companyId,
        provider: "mercadopago",
        providerInvoiceId: "inv-pending",
        providerSubscriptionId: "mp-invoice-sub-1234567890",
        status: "pending",
      },
    });
    const otherInvoice = await prisma.billingInvoice.create({
      data: {
        companyId: other.companyId,
        provider: "mercadopago",
        providerInvoiceId: "inv-other",
        status: "paid",
      },
    });

    const list = await requestJson(
      "GET",
      "/billing/invoices?status=paid&page=1&pageSize=1",
      { token: fixture.token },
    );
    assert.equal(list.status, 200);
    const listPayload = list.data as {
      total: number;
      items: Array<Record<string, unknown>>;
    };
    assert.equal(listPayload.total, 1);
    assert.equal(listPayload.items.length, 1);
    assert.equal(listPayload.items[0].providerSubscriptionId, undefined);
    assert.equal(listPayload.items[0].payload, undefined);
    assert.equal(
      listPayload.items[0].maskedProviderSubscriptionId,
      "mp-i...7890",
    );
    assert.notEqual(
      listPayload.items[0].invoiceUrl,
      "https://mercadopago.test/invoices/inv-paid?token=secret",
    );

    const detail = await requestJson(
      "GET",
      `/billing/invoices/${paidInvoice.id}`,
      { token: fixture.token },
    );
    assert.equal(detail.status, 200);
    assert.equal((detail.data as Record<string, unknown>).payload, undefined);
    assert.equal(
      (detail.data as Record<string, unknown>).providerSubscriptionId,
      undefined,
    );

    const crossCompany = await requestJson(
      "GET",
      `/billing/invoices/${otherInvoice.id}`,
      { token: fixture.token },
    );
    assert.equal(crossCompany.status, 404);
  });

  it("reconciles authorized payments into invoices without duplicate or plan changes", async () => {
    const fixture = await createFixture({
      plan: "basic",
      providerSubscriptionId: "mp-invoices-reconcile",
    });
    globalThis.fetch = jsonFetch(async (url) => {
      if (url.includes("/authorized_payments/search")) {
        return {
          results: [
            {
              id: "auth-paid",
              preapproval_id: "mp-invoices-reconcile",
              status: "approved",
              transaction_amount: 35,
              currency_id: "BRL",
              external_resource_url:
                "https://mercadopago.test/invoices/auth-paid?token=secret",
              payment_date: "2026-05-07T10:00:00.000Z",
              card: { card_number: "4111111111111111", cvv: "123" },
              access_token: "secret",
            },
            {
              id: "auth-pending",
              preapproval_id: "mp-invoices-reconcile",
              status: "pending",
              transaction_amount: 35,
              currency_id: "BRL",
            },
            {
              id: "auth-rejected",
              preapproval_id: "mp-invoices-reconcile",
              status: "rejected",
              transaction_amount: 35,
              currency_id: "BRL",
            },
            {
              preapproval_id: "mp-invoices-reconcile",
              status: "approved",
              transaction_amount: 35,
            },
          ],
        };
      }
      return {
        id: "mp-invoices-reconcile",
        status: "authorized",
        auto_recurring: { transaction_amount: 35 },
      };
    });

    const response = await requestJson("POST", "/billing/refresh", {
      token: fixture.token,
    });
    assert.equal(response.status, 200);
    assert.deepEqual((response.data as { warnings?: string[] }).warnings, [
      "BILLING_INVOICE_SKIPPED_MISSING_STABLE_ID",
    ]);

    const invoices = await prisma.billingInvoice.findMany({
      where: { companyId: fixture.companyId },
      orderBy: { providerInvoiceId: "asc" },
    });
    assert.equal(invoices.length, 3);
    assert.deepEqual(
      invoices.map((invoice) => [invoice.providerInvoiceId, invoice.status]),
      [
        ["auth-paid", "paid"],
        ["auth-pending", "pending"],
        ["auth-rejected", "failed"],
      ],
    );
    assert.equal(
      JSON.stringify(invoices[0].payload).includes("4111111111111111"),
      false,
    );
    assert.equal(invoices[0].invoiceUrl, null);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "BASIC");

    await requestJson("POST", "/billing/refresh", { token: fixture.token });
    const count = await prisma.billingInvoice.count({
      where: { companyId: fixture.companyId },
    });
    assert.equal(count, 3);
  });

  it("does not move an existing invoice across companies on provider id conflict", async () => {
    const fixture = await createFixture({
      plan: "basic",
      providerSubscriptionId: "mp-invoice-conflict",
    });
    const other = await createFixture({ plan: "basic" });
    const existing = await prisma.billingInvoice.create({
      data: {
        companyId: other.companyId,
        provider: "mercadopago",
        providerInvoiceId: "auth-conflict",
        providerSubscriptionId: "mp-other",
        status: "paid",
      },
    });
    globalThis.fetch = jsonFetch(async (url) => {
      if (url.includes("/authorized_payments/search")) {
        return {
          results: [
            {
              id: "auth-conflict",
              preapproval_id: "mp-invoice-conflict",
              status: "approved",
              transaction_amount: 35,
            },
          ],
        };
      }
      return {
        id: "mp-invoice-conflict",
        status: "authorized",
        auto_recurring: { transaction_amount: 35 },
      };
    });

    const response = await requestJson("POST", "/billing/refresh", {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    assert.deepEqual((response.data as { warnings?: string[] }).warnings, [
      "BILLING_INVOICE_PROVIDER_ID_CONFLICT",
    ]);
    const reloaded = await prisma.billingInvoice.findUniqueOrThrow({
      where: { id: existing.id },
    });
    assert.equal(reloaded.companyId, other.companyId);
    assert.equal(
      await prisma.billingInvoice.count({
        where: { companyId: fixture.companyId },
      }),
      0,
    );
  });

  it("keeps refresh successful when invoice reconciliation fails", async () => {
    const fixture = await createFixture({
      plan: "free",
      providerSubscriptionId: "mp-refresh-warning",
    });
    await createCheckoutSession(fixture, "BASIC", "mp-refresh-warning");
    globalThis.fetch = (async (url: string | URL | Request) => {
      const rawUrl = String(url);
      if (rawUrl.includes("/authorized_payments/search")) {
        throw new Error("authorized payments unavailable");
      }
      return new Response(
        JSON.stringify({
          id: "mp-refresh-warning",
          status: "authorized",
          auto_recurring: { transaction_amount: 35 },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
    }) as typeof globalThis.fetch;

    const response = await requestJson("POST", "/billing/refresh", {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    assert.equal((response.data as { plan?: string }).plan, "BASIC");
    assert.deepEqual((response.data as { warnings?: string[] }).warnings, [
      "INVOICE_RECONCILIATION_FAILED",
    ]);
  });

  it("returns a safe payment method summary and tolerates provider failure", async () => {
    const fixture = await createFixture({
      plan: "basic",
      providerSubscriptionId: "mp-payment-method-1234567890",
    });
    globalThis.fetch = jsonFetch(async () => ({
      id: "mp-payment-method-1234567890",
      status: "authorized",
      next_payment_date: "2026-06-07T00:00:00.000Z",
      payment_method_id: "visa-secret-id-123456",
      payment_method: { type: "credit_card" },
      card: { card_number: "4111111111111111", last_four_digits: "1111" },
    }));

    const response = await requestJson("GET", "/billing/payment-method", {
      token: fixture.token,
    });
    assert.equal(response.status, 200);
    const payload = response.data as Record<string, unknown>;
    assert.equal(payload.hasPaymentMethod, true);
    assert.equal(payload.paymentMethodType, "credit_card");
    assert.equal(payload.lastFour, "1111");
    assert.equal(payload.maskedProviderSubscriptionId, "mp-p...7890");
    assert.equal(JSON.stringify(payload).includes("4111111111111111"), false);
    assert.equal(
      JSON.stringify(payload).includes("mp-payment-method-1234567890"),
      false,
    );

    globalThis.fetch = failFetch("provider unavailable");
    const unavailable = await requestJson("GET", "/billing/payment-method", {
      token: fixture.token,
    });
    assert.equal(unavailable.status, 200);
    assert.equal(
      (unavailable.data as { unavailable?: boolean }).unavailable,
      true,
    );
  });

  it("cancels customer subscription at period end without downgrading immediately", async () => {
    const future = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    const fixture = await createFixture({
      plan: "pro",
      providerSubscriptionId: "mp-cancel-period",
    });
    await prisma.license.update({
      where: { companyId: fixture.companyId },
      data: { currentPeriodEnd: future },
    });
    let providerMethod = "";
    globalThis.fetch = jsonFetch(async (_url, init) => {
      providerMethod = init.method ?? "";
      return {
        id: "mp-cancel-period",
        status: "cancelled",
        end_date: future.toISOString(),
      };
    });

    const response = await requestJson("POST", "/billing/cancel", {
      token: fixture.token,
      body: { effective: "period_end", reason: "cliente pediu" },
    });

    assert.equal(response.status, 200);
    assert.equal(providerMethod, "PUT");
    assert.equal(
      (response.data as { providerCancelled?: boolean }).providerCancelled,
      true,
    );
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "pro");
    assert.equal(license.cancelAtPeriodEnd, true);
    assert.equal(license.providerSubscriptionId, "mp-cancel-period");
  });

  it("keeps paid access on cancel now while current period is still valid", async () => {
    const future = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    const fixture = await createFixture({
      plan: "basic",
      providerSubscriptionId: "mp-cancel-now-future",
    });
    await prisma.license.update({
      where: { companyId: fixture.companyId },
      data: { currentPeriodEnd: future },
    });
    globalThis.fetch = jsonFetch(async () => ({
      id: "mp-cancel-now-future",
      status: "cancelled",
      end_date: future.toISOString(),
    }));

    const response = await requestJson("POST", "/billing/cancel", {
      token: fixture.token,
      body: { effective: "now" },
    });

    assert.equal(response.status, 200);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "basic");
    assert.equal(license.cancelAtPeriodEnd, true);
  });

  it("downgrades to FREE on cancel now when there is no active paid period", async () => {
    const fixture = await createFixture({
      plan: "basic",
      providerSubscriptionId: "mp-cancel-now",
    });
    globalThis.fetch = jsonFetch(async () => ({
      id: "mp-cancel-now",
      status: "cancelled",
    }));

    const response = await requestJson("POST", "/billing/cancel", {
      token: fixture.token,
      body: { effective: "now" },
    });

    assert.equal(response.status, 200);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "FREE");
    assert.equal(license.providerSubscriptionId, null);
  });

  it("returns safe errors on provider cancel failure without downgrading", async () => {
    const fixture = await createFixture({
      plan: "basic",
      providerSubscriptionId: "mp-cancel-fail",
    });
    globalThis.fetch = failFetch("provider unavailable");

    const response = await requestJson("POST", "/billing/cancel", {
      token: fixture.token,
      body: { effective: "now" },
    });

    assert.equal(response.status, 502);
    assert.equal(
      JSON.stringify(response.data).includes("provider unavailable"),
      false,
    );
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "basic");
  });

  it("resume does not promote locally and falls back to new checkout when needed", async () => {
    const fixture = await createFixture({ plan: "free" });

    const response = await requestJson("POST", "/billing/resume", {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    assert.equal(
      (response.data as { requiresNewCheckout?: boolean }).requiresNewCheckout,
      true,
    );
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "free");
  });

  it("changes plans with pendingPlan without unlocking features early", async () => {
    const basic = await createFixture({
      plan: "basic",
      providerSubscriptionId: "mp-change-basic-pro",
    });
    globalThis.fetch = jsonFetch(async () => ({
      id: "mp-change-basic-pro",
      status: "authorized",
      auto_recurring: { transaction_amount: 85 },
    }));

    const upgrade = await requestJson("POST", "/billing/change-plan", {
      token: basic.token,
      body: { plan: "PRO" },
    });
    assert.equal(upgrade.status, 200);
    const upgradePayload = upgrade.data as {
      status: {
        plan: string;
        pendingPlan?: string;
        features: Record<string, boolean>;
      };
    };
    assert.equal(upgradePayload.status.plan, "BASIC");
    assert.equal(upgradePayload.status.pendingPlan, "PRO");
    assert.equal(upgradePayload.status.features.employees, false);
    let license = await prisma.license.findUniqueOrThrow({
      where: { companyId: basic.companyId },
    });
    assert.equal(license.plan, "basic");
    assert.equal(license.pendingPlan, "PRO");

    const pro = await createFixture({
      plan: "pro",
      providerSubscriptionId: "mp-change-pro-basic",
    });
    await prisma.license.update({
      where: { companyId: pro.companyId },
      data: {
        currentPeriodEnd: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      },
    });
    globalThis.fetch = jsonFetch(async () => ({
      id: "mp-change-pro-basic",
      status: "authorized",
      auto_recurring: { transaction_amount: 35 },
    }));

    const downgrade = await requestJson("POST", "/billing/change-plan", {
      token: pro.token,
      body: { plan: "BASIC" },
    });
    assert.equal(downgrade.status, 200);
    const downgradePayload = downgrade.data as {
      status: {
        plan: string;
        pendingPlan?: string;
        features: Record<string, boolean>;
      };
    };
    assert.equal(downgradePayload.status.plan, "PRO");
    assert.equal(downgradePayload.status.pendingPlan, "BASIC");
    assert.equal(downgradePayload.status.features.employees, true);
    license = await prisma.license.findUniqueOrThrow({
      where: { companyId: pro.companyId },
    });
    assert.equal(license.plan, "pro");
    assert.equal(license.pendingPlan, "BASIC");
  });

  it("preserves pendingPlan on refresh until provider confirmation is safe", async () => {
    const fixture = await createFixture({
      plan: "basic",
      providerSubscriptionId: "mp-pending-upgrade",
    });
    await prisma.license.update({
      where: { companyId: fixture.companyId },
      data: {
        pendingPlan: "PRO",
        pendingPlanRequestedAt: new Date(),
      },
    });
    globalThis.fetch = jsonFetch(async (url) => {
      if (url.includes("/authorized_payments/search")) {
        return { results: [] };
      }
      return {
        id: "mp-pending-upgrade",
        status: "authorized",
      };
    });

    const response = await requestJson("POST", "/billing/refresh", {
      token: fixture.token,
    });

    assert.equal(response.status, 200);
    const payload = response.data as {
      plan: string;
      pendingPlan?: string | null;
      features: Record<string, boolean>;
    };
    assert.equal(payload.plan, "BASIC");
    assert.equal(payload.pendingPlan, "PRO");
    assert.equal(payload.features.employees, false);
    const license = await prisma.license.findUniqueOrThrow({
      where: { companyId: fixture.companyId },
    });
    assert.equal(license.plan, "BASIC");
    assert.equal(license.pendingPlan, "PRO");
  });
});

async function createFixture(options?: {
  role?: "OWNER" | "ADMIN" | "OPERATOR";
  plan?: string;
  providerSubscriptionId?: string;
  currentPeriodEnd?: Date;
}) {
  const unique = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  const company = await prisma.company.create({
    data: {
      name: "Billing Company",
      legalName: "Billing Company LTDA",
      slug: `${runId}-company-${unique}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email: `${runId}-${unique}@tatuzin.test`,
      name: "Billing Owner",
      passwordHash: "not-used",
    },
  });
  const membership = await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: options?.role ?? "OWNER",
      isDefault: true,
    },
  });
  await prisma.license.create({
    data: {
      companyId: company.id,
      plan: options?.plan ?? "free",
      status: "ACTIVE",
      startsAt: new Date(),
      syncEnabled: true,
      billingProvider:
        options?.providerSubscriptionId == null ? null : "mercadopago",
      providerSubscriptionId: options?.providerSubscriptionId ?? null,
      currentPeriodEnd: options?.currentPeriodEnd ?? null,
    },
  });
  const clientInstanceId = `${runId}-device-${unique}`;
  await prisma.companyDevice.create({
    data: {
      companyId: company.id,
      userId: user.id,
      clientInstanceId,
      deviceLabel: "Billing Test Device",
      platform: "node-test",
      appVersion: "billing-test",
      status: "ACTIVE",
      approvedAt: new Date(),
      approvedByUserId: user.id,
      lastSeenAt: new Date(),
    },
  });

  return {
    companyId: company.id,
    userId: user.id,
    membershipId: membership.id,
    email: user.email,
    token: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
      membershipRole: options?.role ?? "OWNER",
      clientInstanceId,
    }),
    ownerTokenWithoutDevice: signToken({
      userId: user.id,
      companyId: company.id,
      membershipId: membership.id,
      email: user.email,
      membershipRole: "OWNER",
    }),
  };
}

async function createCheckoutSession(
  fixture: { companyId: string; userId: string },
  plan: "BASIC" | "PRO",
  providerReference: string,
) {
  return prisma.billingCheckoutSession.create({
    data: {
      companyId: fixture.companyId,
      userId: fixture.userId,
      plan,
      billingCycle: "monthly",
      status: "PENDING",
      provider: "mercadopago",
      providerReference,
      checkoutUrl: `https://mercadopago.test/${providerReference}`,
      sandboxCheckoutUrl: `https://sandbox.mercadopago.test/${providerReference}`,
      expiresAt: new Date(Date.now() + 30 * 60 * 1000),
    },
  });
}

function signToken(input: {
  userId: string;
  companyId: string;
  membershipId: string;
  email: string;
  membershipRole: string;
  clientInstanceId?: string;
}) {
  return jwt.sign(
    {
      sub: input.userId,
      companyId: input.companyId,
      membershipId: input.membershipId,
      membershipRole: input.membershipRole,
      email: input.email,
      isPlatformAdmin: false,
      ...(input.clientInstanceId == null
        ? {}
        : { clientInstanceId: input.clientInstanceId }),
    },
    env.JWT_SECRET,
    { expiresIn: "15m" },
  );
}

async function sendWebhook(providerReference: string, eventType: string) {
  const requestId = `${runId}-${providerReference}`;
  const ts = "1715000000";
  const signature = signWebhook(providerReference, requestId, ts);
  return requestJson(
    "POST",
    `/webhooks/mercadopago?data.id=${encodeURIComponent(providerReference)}&type=${eventType}`,
    {
      headers: {
        "x-request-id": requestId,
        "x-signature": signature,
      },
      body: {
        type: eventType,
        data: { id: providerReference },
      },
    },
  );
}

function signWebhook(dataId: string, requestId: string, ts: string) {
  const manifest = `id:${dataId};request-id:${requestId};ts:${ts};`;
  const v1 = createHmac("sha256", webhookSecret).update(manifest).digest("hex");
  return `ts=${ts},v1=${v1}`;
}

async function requestJson(
  method: string,
  path: string,
  options?: {
    token?: string;
    body?: Record<string, unknown>;
    headers?: Record<string, string>;
  },
) {
  const response = await originalFetch(`${apiBaseUrl}${path}`, {
    method,
    headers: {
      ...(options?.token == null
        ? {}
        : { Authorization: `Bearer ${options.token}` }),
      ...(options?.body == null ? {} : { "Content-Type": "application/json" }),
      ...(options?.headers ?? {}),
    },
    body: options?.body == null ? undefined : JSON.stringify(options.body),
  });
  const rawBody = await response.text();
  return {
    status: response.status,
    data: rawBody.trim().length === 0 ? null : JSON.parse(rawBody),
  };
}

function jsonFetch(
  handler: (
    url: string,
    init: { method?: string; body?: string },
  ) => Promise<Record<string, unknown>> | Record<string, unknown>,
) {
  return (async (url: string | URL | Request, init?: RequestInit) => {
    const payload = await handler(String(url), {
      method: init?.method,
      body: typeof init?.body === "string" ? init.body : undefined,
    });
    return new Response(JSON.stringify(payload), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }) as typeof globalThis.fetch;
}

function failFetch(message: string) {
  return (async () => {
    throw new Error(message);
  }) as typeof globalThis.fetch;
}

async function cleanupFixtures() {
  await prisma.billingProviderEvent.deleteMany({
    where: {
      provider: "mercadopago",
      providerEventId: { contains: runId },
    },
  });
  await prisma.rateLimitBucket.deleteMany({
    where: { scope: "billing_refresh" },
  });
  await prisma.billingInvoice.deleteMany({
    where: { company: { slug: { startsWith: `${runId}-` } } },
  });
  await prisma.billingCheckoutSession.deleteMany({
    where: { company: { slug: { startsWith: `${runId}-` } } },
  });
  await prisma.company.deleteMany({
    where: { slug: { startsWith: `${runId}-` } },
  });
  await prisma.user.deleteMany({
    where: { email: { startsWith: `${runId}-` } },
  });
}
