router.post('/auth/verify-code', async (req, res) => {
  const saved = await codes.get(req.body.userId);
  if (!saved || saved.value !== req.body.code) return res.status(401).end();
  await codes.delete(req.body.userId);
  res.json({ token: sessions.create(req.body.userId) });
});
