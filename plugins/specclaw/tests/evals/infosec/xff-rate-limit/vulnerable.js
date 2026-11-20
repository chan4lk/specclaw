app.set('trust proxy', true);
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  keyGenerator: (req) => req.headers['x-forwarded-for'] || req.ip,
});
app.post('/login', limiter, loginHandler);
