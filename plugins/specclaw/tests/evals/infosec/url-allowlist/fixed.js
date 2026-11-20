const ALLOWED = new Set(['images.example.com']);
router.get('/preview', async (req, res) => {
  let target;
  try { target = new URL(req.query.url); } catch { return res.status(400).end(); }
  if (target.protocol !== 'https:' || !ALLOWED.has(target.hostname)) return res.status(400).end();
  const upstream = await fetch(target, { redirect: 'error' });
  res.type(upstream.headers.get('content-type')).send(Buffer.from(await upstream.arrayBuffer()));
});
