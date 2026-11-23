app.set('trust proxy', process.env.TRUSTED_PROXY_ADDRESSES.split(','));
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  keyGenerator: (req) => `${req.body.email}:${req.ip}`,
});
app.post('/login', limiter, loginHandler);
