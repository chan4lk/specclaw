router.get('/notes', requireAuth, async (req, res) => {
  const token = req.headers['x-notes-token'] || req.body.accessToken;
  const upstream = await fetch(`${NOTES_API}/notes`, { headers: { authorization: `Bearer ${token}` } });
  res.json(await upstream.json());
});
