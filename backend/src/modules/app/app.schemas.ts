import { z } from 'zod';

const requiredClientInstanceId = z.string().trim().min(1).max(120);
const optionalClientString = (maxLength: number) =>
  z.string().trim().min(1).max(maxLength).optional();

export const deviceRegisterSchema = z.object({
  clientInstanceId: requiredClientInstanceId,
  deviceLabel: optionalClientString(120),
  platform: optionalClientString(60),
  appVersion: optionalClientString(40),
});

export type DeviceRegisterInput = z.infer<typeof deviceRegisterSchema>;
