router.post('/login', async (req, res) => {
  const user = await auth.verify(req.body.email, req.body.password);
  if (!user) return res.status(401).render('login');
  req.session.userId = user.id;
  res.redirect(req.body.returnTo || '/');
});
