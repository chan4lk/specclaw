router.get('/orders/:id', async (req, res) => {
  const order = await db.orders.findById(req.params.id);
  if (!order) return res.status(404).end();
  if (req.user && order.ownerId !== req.user.id) return res.status(404).end();
  res.json(order);
});
