router.post('/signup', async (req, res) => {
  const passwordHash = await argon2.hash(req.body.password);
  await queue.add('signup', { email: req.body.email, passwordHash });
  res.status(202).json({ ok: true });
});
