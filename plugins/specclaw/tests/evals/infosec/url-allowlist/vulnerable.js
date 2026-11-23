const ALLOWED = 'images.example.com';
router.get('/preview', async (req, res) => {
  const target = req.query.url;
  if (!target.includes(ALLOWED)) return res.status(400).end();
  const upstream = await fetch(target, { redirect: 'error' });
  res.type(upstream.headers.get('content-type')).send(Buffer.from(await upstream.arrayBuffer()));
});
