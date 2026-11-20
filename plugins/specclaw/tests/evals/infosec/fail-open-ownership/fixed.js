router.get('/orders/:id', async (req, res) => {
  if (!req.user) return res.status(401).end();
  const order = await db.orders.findById(req.params.id);
  if (!order || order.ownerId !== req.user.id) return res.status(404).end();
  res.json(order);
});
