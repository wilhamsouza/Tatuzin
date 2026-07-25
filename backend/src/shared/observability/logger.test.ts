import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { logger } from "./logger";

describe("logger redaction", () => {
  it("redacts sensitive keys in nested objects, arrays and different casing", () => {
    const { payload, line } = captureInfo(() => {
      logger.info("redaction.test", {
        password: "plain-password",
        passwordHash: "hash-secret",
        ACCESS_TOKEN: "access-secret",
        nested: {
          refreshToken: "refresh-secret",
          Authorization: "Bearer header-secret",
          cookie: "sid=cookie-secret",
          "set-cookie": "sid=set-cookie-secret",
        },
        rows: [{ apiKey: "api-secret", label: "kept-row" }],
        operation: "sync-completed",
        count: 2,
      });
    });

    assert.equal(payload.context.operation, "sync-completed");
    assert.equal(payload.context.count, 2);
    assert.equal(payload.context.rows[0].label, "kept-row");
    assertNoSecrets(line, [
      "plain-password",
      "hash-secret",
      "access-secret",
      "refresh-secret",
      "header-secret",
      "cookie-secret",
      "set-cookie-secret",
      "api-secret",
    ]);
    assert.match(line, /\[redacted\]/);
  });

  it("redacts URL credentials and sensitive query parameters", () => {
    const { payload, line } = captureInfo(() => {
      logger.info("url.test", {
        callbackUrl:
          "https://url-user:url-pass@example.test/callback?access_token=url-token&refreshToken=refresh-url-token&ok=visible",
        relativeUrl: "/reset?token=relative-token&safe=visible",
      });
    });

    assert.match(payload.context.callbackUrl, /ok=visible/);
    assert.match(payload.context.relativeUrl, /safe=visible/);
    assertNoSecrets(line, [
      "url-user",
      "url-pass",
      "url-token",
      "refresh-url-token",
      "relative-token",
    ]);
  });

  it("serializes Error, cause and stack while redacting sensitive enumerable fields", () => {
    const cause = new Error("inner cause");
    const error = new Error("outer failure", { cause });
    error.stack = "Error: outer failure\n    at test";
    Object.assign(error, {
      password: "error-password",
      accessToken: "error-token",
      publicCode: "E_PUBLIC",
    });

    const { payload, line } = captureError(() => {
      logger.error("error.test", { error });
    });

    assert.equal(payload.context.error.name, "Error");
    assert.equal(payload.context.error.message, "outer failure");
    assert.match(payload.context.error.stack, /Error: outer failure/);
    assert.equal(payload.context.error.cause.message, "inner cause");
    assert.equal(payload.context.error.publicCode, "E_PUBLIC");
    assertNoSecrets(line, ["error-password", "error-token"]);
  });

  it("handles circular references without throwing and does not mutate the input object", () => {
    const context: Record<string, unknown> = {
      name: "original",
      nested: { password: "nested-secret", visible: "still-visible" },
    };
    context.self = context;

    const { payload, line } = captureInfo(() => {
      logger.info("circular.test", context);
    });

    assert.equal(payload.context.name, "original");
    assert.equal(payload.context.nested.visible, "still-visible");
    assert.equal(payload.context.self.self, "[circular]");
    assert.equal((context.nested as { password: string }).password, "nested-secret");
    assertNoSecrets(line, ["nested-secret"]);
  });
});

type ParsedLog = {
  message: string;
  context: any;
};

function captureInfo(action: () => void) {
  return captureConsole("log", action);
}

function captureError(action: () => void) {
  return captureConsole("error", action);
}

function captureConsole(method: "log" | "error", action: () => void) {
  const original = console[method];
  const lines: string[] = [];
  console[method] = (line?: unknown) => {
    lines.push(String(line));
  };

  try {
    action();
  } finally {
    console[method] = original;
  }

  assert.equal(lines.length, 1);
  const line = lines[0]!;
  return {
    line,
    payload: JSON.parse(line) as ParsedLog,
  };
}

function assertNoSecrets(serialized: string, secrets: string[]) {
  for (const secret of secrets) {
    assert.equal(serialized.includes(secret), false, secret);
  }
}
