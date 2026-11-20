def client_key(request: Request) -> str:
    return request.headers.get("x-forwarded-for", request.client.host)

limiter = Limiter(key_func=client_key)

@app.post("/login")
@limiter.limit("10/15minutes")
async def login(request: Request, body: LoginBody):
    return await auth.sign_in(body.email, body.password)
