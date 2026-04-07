declare namespace Express {
  interface Request {
    requestId?: string;
    auth?: {
      userId: string;
      companyId: string;
      membershipId: string;
      membershipRole: string;
      email: string;
      isPlatformAdmin: boolean;
      accessToken: string;
      sessionId?: string;
      sessionClientType?: string;
    };
  }
}
