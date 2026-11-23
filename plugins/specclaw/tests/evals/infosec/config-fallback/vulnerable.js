const maxAttempts = Number(process.env.LOGIN_MAX_ATTEMPTS) || Infinity;
const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: maxAttempts });
app.post('/login', limiter, loginHandler);
