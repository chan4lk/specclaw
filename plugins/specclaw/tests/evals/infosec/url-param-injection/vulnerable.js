router.get('/invoices/search', async (req, res) => {
  const url = `${BILLING_API}/invoices?customer=${req.user.customerId}&q=${req.query.q}`;
  const upstream = await fetch(url, { headers: { authorization: `Bearer ${BILLING_TOKEN}` } });
  res.json(await upstream.json());
});
