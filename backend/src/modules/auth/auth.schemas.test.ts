import assert from "node:assert/strict";
import { describe, it } from "node:test";

import type { Request, Response } from "express";
import { ZodError } from "zod";

import { validateBody } from "../../shared/http/validate";
import { authRouter } from "./auth.routes";
import { registerInitialSchema } from "./auth.schemas";

const validPayload = {
  companyName: "Initial Company",
  companySlug: "initial-company",
  userName: "Initial Owner",
  email: "owner@example.test",
  password: "12345678",
  clientType: "admin_web" as const,
  clientInstanceId: "initial-client",
};

describe("registerInitialSchema", () => {
  it("rejects bootstrap passwords shorter than eight characters", () => {
    const result = registerInitialSchema.safeParse({
      ...validPayload,
      password: "1234567",
    });

    assert.equal(result.success, false);
    assert.match(JSON.stringify(result.error.format()), /8 caracteres/);
  });

  it("accepts bootstrap passwords with eight or more characters", () => {
    const result = registerInitialSchema.safeParse(validPayload);

    assert.equal(result.success, true);
    assert.equal(result.data.password, "12345678");
  });

  it("rejects invalid required bootstrap payloads", () => {
    const result = registerInitialSchema.safeParse({});

    assert.equal(result.success, false);
    assert.ok(result.error.issues.length > 0);
  });

  it("uses the same password policy through the register-initial route validator", () => {
    const middleware = findRegisterInitialValidateMiddleware();
    const request = {
      body: {
        ...validPayload,
        password: "1234567",
      },
    } as Request;

    assert.throws(
      () => middleware(request, {} as Response, () => undefined),
      ZodError,
    );

    request.body = validPayload;
    let nextCalled = false;
    middleware(request, {} as Response, () => {
      nextCalled = true;
    });

    assert.equal(nextCalled, true);
    assert.equal(request.body.password, "12345678");
  });
});

type RouterLayer = {
  route?: {
    path: string;
    methods: Record<string, boolean>;
    stack: Array<{ handle: ReturnType<typeof validateBody> }>;
  };
};

function findRegisterInitialValidateMiddleware() {
  const stack = (authRouter as unknown as { stack: RouterLayer[] }).stack;
  const route = stack.find(
    (layer) =>
      layer.route?.path === "/register-initial" && layer.route.methods.post,
  )?.route;

  assert.ok(route, "register-initial route must exist");
  assert.equal(route.stack.length >= 3, true);
  return route.stack[1]!.handle;
}