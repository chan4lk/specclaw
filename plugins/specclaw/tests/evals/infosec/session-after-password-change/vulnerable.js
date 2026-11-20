router.post('/account/password', requireAuth, async (req, res) => {
  if (!(await argon2.verify(req.user.passwordHash, req.body.currentPassword))) return res.status(403).end();
  const hash = await argon2.hash(req.body.newPassword);
  await users.update(req.user.id, { passwordHash: hash });
  res.status(204).end();
});
