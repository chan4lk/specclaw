router.get('/invoices/search', async (req, res) => {
  const url = new URL('/invoices', BILLING_API);
  url.searchParams.set('customer', req.user.customerId);
  url.searchParams.set('q', String(req.query.q ?? ''));
  const upstream = await fetch(url, { headers: { authorization: `Bearer ${BILLING_TOKEN}` } });
  res.json(await upstream.json());
});
