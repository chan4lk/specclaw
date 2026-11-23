router.post('/auth/send-code', async (req, res) => {
  const user = await users.findByEmail(req.body.email);
  if (user) await queue.add('send-code', { userId: user.id, email: user.email });
  res.status(204).end();
});
