builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor;
    options.KnownProxies.Add(IPAddress.Parse(builder.Configuration["TrustedProxy"]!));
});
builder.Services.AddRateLimiter(options =>
{
    options.AddPolicy("login", http =>
        RateLimitPartition.GetFixedWindowLimiter(
            http.Connection.RemoteIpAddress?.ToString() ?? "none",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(15) }));
});
var app = builder.Build();
app.UseForwardedHeaders();
app.UseRateLimiter();
app.MapPost("/login", LoginHandler.Handle).RequireRateLimiting("login");
