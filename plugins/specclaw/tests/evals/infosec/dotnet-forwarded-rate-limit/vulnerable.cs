builder.Services.AddRateLimiter(options =>
{
    options.AddPolicy("login", http =>
        RateLimitPartition.GetFixedWindowLimiter(
            http.Request.Headers["X-Forwarded-For"].FirstOrDefault() ?? http.Connection.RemoteIpAddress?.ToString() ?? "none",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = 10, Window = TimeSpan.FromMinutes(15) }));
});
var app = builder.Build();
app.UseRateLimiter();
app.MapPost("/login", LoginHandler.Handle).RequireRateLimiting("login");
