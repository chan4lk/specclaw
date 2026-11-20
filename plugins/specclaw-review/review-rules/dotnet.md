## .NET rules

- **DN1** `async void` outside event handlers, or `.Result`/`.Wait()` on tasks (deadlock risk) → **major**.
- **DN2** `catch (Exception)` that logs and continues where the caller needs to know (B3) → **major**.
- **DN3** EF Core: a query inside a loop (N+1) on a request path, or tracking queries used for read-only
  lists → **minor**. A missing `SaveChanges` in a transaction scope, or a partial save → **major**.
- **DN4** An inner Clean Architecture layer referencing an outer one (Domain → Infrastructure) → **major**.
- **DN5** String-concatenated SQL or `FromSqlRaw` with interpolated input → **blocker** (B8).
- **DN6** `IDisposable`/`HttpClient` created per call without `using` or a factory → **major**.
- **DN7** A request model that binds an entity directly instead of a DTO (over-posting) → **major**.
- **DN8** An endpoint with no authorization policy where the app has no fallback policy, or an anonymous route
  not intended to be public → **blocker** (B13).
- **DN9** CORS with `AllowAnyOrigin` combined with credentials → **major**.
- **DN10** A sign-in, code or token endpoint with no rate limiter, or one that becomes a no-limit partition when its
  setting is missing → **major** (B22).
- **DN11** Forwarded headers trusted from any source (no `KnownProxies`/`KnownNetworks`, or `X-Forwarded-For` read
  directly), so a client-set header picks its own rate-limit bucket → **major**.
