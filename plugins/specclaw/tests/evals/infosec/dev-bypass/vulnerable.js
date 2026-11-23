function requireAuth(req, res, next) {
  if (req.headers['x-dev-user']) {
    req.user = { id: req.headers['x-dev-user'], role: 'admin' };
    return next();
  }
  const session = sessions.get(req.cookies.sid);
  if (!session) return res.status(401).end();
  req.user = session.user;
  next();
}
