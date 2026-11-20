router.post('/signup', async (req, res) => {
  const existing = await users.findByEmail(req.body.email);
  if (existing) return res.status(409).json({ error: 'Email already registered' });
  await users.create(req.body.email, await argon2.hash(req.body.password));
  res.status(201).json({ ok: true });
});
