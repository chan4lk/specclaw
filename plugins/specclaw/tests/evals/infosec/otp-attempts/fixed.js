const MAX_ATTEMPTS = 5;
router.post('/auth/verify-code', async (req, res) => {
  // claimAttempt counts this try atomically and returns null once the cap is reached
  const saved = await codes.claimAttempt(req.body.userId, MAX_ATTEMPTS);
  if (!saved || saved.value !== req.body.code) return res.status(401).end();
  await codes.delete(req.body.userId);
  res.json({ token: sessions.create(req.body.userId) });
});
