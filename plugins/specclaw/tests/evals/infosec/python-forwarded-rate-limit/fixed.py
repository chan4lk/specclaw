def client_key(request: Request) -> str:
    return request.client.host

limiter = Limiter(key_func=client_key)

@app.post("/login")
@limiter.limit("10/15minutes")
async def login(request: Request, body: LoginBody):
    return await auth.sign_in(body.email, body.password)
