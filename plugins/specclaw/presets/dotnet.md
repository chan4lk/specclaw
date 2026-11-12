# Preset: dotnet

Detected by a `*.csproj` or `*.sln` file.

## Stack
- .NET 8 or later, `<Nullable>enable</Nullable>`, `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`.
- Minimal APIs.
- EF Core in Infrastructure only.
- xUnit for tests.

## Clean Architecture
```
src/<App>.Domain/          entities, value objects, domain errors. References nothing.
src/<App>.Application/     use cases, interfaces (ports). References Domain.
src/<App>.Infrastructure/  EF Core, HTTP clients, adapters. References Application.
src/<App>.Api/             endpoints, DI wiring. References Application and Infrastructure.
tests/<App>.Tests/
```
- References point inward only. `specclaw-preset-check` fails on an inner project referencing an outer one, using the order Domain < Application < Infrastructure < Api.
- Interfaces live in Application; implementations in Infrastructure.

## Rules
- One type per file.
- Endpoints map requests to use cases and nothing else.
- Use `Result` types or domain exceptions mapped in one exception handler.
- Async with `CancellationToken` through every I/O call.

## Security
- **Authorization:** endpoints require authorization by default (a fallback policy or `RequireAuthorization()` on the group). Anonymous routes are listed.
- **Binding:** bind requests to DTOs, never to entities (over-posting).
- **Errors:** one exception handler returns `ProblemDetails`.
- **Http:** outbound calls use `IHttpClientFactory`, never a new `HttpClient` per call.
- **Cors:** list explicit origins; never `AllowAnyOrigin` together with credentials.

## Shared
- `src/<App>.Common/` (a class library) for code reused across layers: base entities, generic repositories and handlers, guards, result types.
- Keep `Common` free of Infrastructure dependencies.

## Commands
- Test: `dotnet test`
- Lint: `dotnet build -warnaserror`
