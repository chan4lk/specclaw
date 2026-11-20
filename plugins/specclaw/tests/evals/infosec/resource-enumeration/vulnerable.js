router.get('/invoices/:id', requireAuth, async (req, res) => {
  const invoice = await db.invoices.findById(req.params.id);
  if (!invoice) return res.status(404).json({ error: 'not found' });
  if (invoice.accountId !== req.user.accountId) return res.status(403).json({ error: 'forbidden' });
  res.json(invoice);
});
