router.post('/login', async (req, res) => {
  const user = await auth.verify(req.body.email, req.body.password);
  if (!user) return res.status(401).render('login');
  req.session.userId = user.id;
  const next = String(req.body.returnTo || '/');
  res.redirect(next.startsWith('/') && !next.startsWith('//') && !next.includes('\') ? next : '/');
});
