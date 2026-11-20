router.get('/notes', requireAuth, async (req, res) => {
  const token = await tokens.forUser(req.user.id);
  const upstream = await fetch(`${NOTES_API}/notes`, { headers: { authorization: `Bearer ${token}` } });
  res.json(await upstream.json());
});
