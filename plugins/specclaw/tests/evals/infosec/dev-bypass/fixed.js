function requireAuth(req, res, next) {
  const session = sessions.get(req.cookies.sid);
  if (!session) return res.status(401).end();
  req.user = session.user;
  next();
}
