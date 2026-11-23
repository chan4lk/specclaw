const maxAttempts = Number(process.env.LOGIN_MAX_ATTEMPTS);
if (!Number.isInteger(maxAttempts) || maxAttempts < 1) throw new Error('LOGIN_MAX_ATTEMPTS must be a positive integer');
const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: maxAttempts });
app.post('/login', limiter, loginHandler);
