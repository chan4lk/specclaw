router.get('/invoices/:id', requireAuth, async (req, res) => {
  const invoice = await db.invoices.findOne({ id: req.params.id, accountId: req.user.accountId });
  if (!invoice) return res.status(404).json({ error: 'not found' });
  res.json(invoice);
});
