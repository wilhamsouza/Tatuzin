import { AdminPermissionBootstrapService } from "../src/modules/admin-permissions";

type CliOptions = {
  targetAdminId?: string;
  targetEmail?: string;
  permissionKey?: string;
  reason?: string;
};

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const service = new AdminPermissionBootstrapService();
  const result = await service.bootstrapManagePermission({
    targetAdminId: options.targetAdminId,
    targetEmail: options.targetEmail,
    permissionKey: options.permissionKey,
    reason: options.reason,
  });

  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (!result.ok) {
    process.exitCode = 1;
  }
}

export function parseArgs(args: string[]): CliOptions {
  const options: CliOptions = {};
  for (const arg of args) {
    const [key, ...valueParts] = arg.split("=");
    const value = valueParts.join("=").trim();
    if (value.length === 0) {
      continue;
    }

    switch (key) {
      case "--adminUserId":
      case "--targetAdminId":
        options.targetAdminId = value;
        break;
      case "--email":
      case "--targetEmail":
        options.targetEmail = value;
        break;
      case "--permission":
      case "--permissionKey":
        options.permissionKey = value;
        break;
      case "--reason":
        options.reason = value;
        break;
    }
  }
  return options;
}

if (require.main === module) {
  main().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : "Erro inesperado";
    process.stderr.write(`${message}\n`);
    process.exitCode = 1;
  });
}
