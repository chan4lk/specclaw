router.post('/auth/send-code', async (req, res) => {
  const user = await users.findByEmail(req.body.email);
  if (!user) return res.status(204).end();
  const code = String(crypto.randomInt(100000, 999999));
  await codes.save(user.id, code, { ttlSeconds: 300 });
  await mailer.send(user.email, `Your code is ${code}`);
  res.json({ sent: true, code });
});
