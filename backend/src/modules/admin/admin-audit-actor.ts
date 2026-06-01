export type AdminAuditActorType = "USER" | "SYSTEM" | "BOOTSTRAP" | "SERVICE";

export type AdminAuditActorFields = {
  actorType: AdminAuditActorType;
  actorUserId: string | null;
  actorLabel: string | null;
};

export function userAdminAuditActor(actorUserId: string) {
  return {
    actorType: "USER",
    actorUserId,
    actorLabel: null,
  } as const;
}

export function bootstrapAdminAuditActor() {
  return {
    actorType: "BOOTSTRAP",
    actorUserId: null,
    actorLabel: "SYSTEM_BOOTSTRAP",
  } as const;
}

export function normalizeAdminAuditActor(input: {
  actorType?: AdminAuditActorType | null;
  actorUserId?: string | null;
  actorLabel?: string | null;
}): AdminAuditActorFields {
  return {
    actorType: input.actorType ?? "USER",
    actorUserId: input.actorUserId ?? null,
    actorLabel: input.actorLabel ?? null,
  };
}
