using System.Collections.Concurrent;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

[assembly: HostingStartup(typeof(Cipp.Gdap.Hosting.WebhookHostingStartup))]

namespace Cipp.Gdap.Hosting;

// Bodies exist only while their original HTTP requests are alive. A handle is
// not authentication: it connects an in-process capture to the signature check.
public static class WebhookBodyBridge
{
    public const string HeaderName = "x-cipp-gdap-body-handle";
    public const int MaximumBytes = 1024 * 1024;
    private static readonly ConcurrentDictionary<string, byte[]> Bodies = new();
    private static readonly SemaphoreSlim Slots = new(32, 32);
    public static bool Installed { get; private set; }

    // Called from PowerShell after Craft has parsed JSON. No client-supplied
    // header or reconstructed JSON can substitute for an original byte buffer.
    public static byte[]? Take(string? handle) => handle is not null &&
        Bodies.TryRemove(handle, out var bytes) ? bytes : null;

    internal static void MarkInstalled() => Installed = true;

    public static async Task Capture(HttpContext context, RequestDelegate next)
    {
        context.Request.Headers.Remove(HeaderName);
        var request = context.Request;
        var partnerCallback = string.Equals(request.Path.Value?.TrimEnd('/'),
            "/api/PublicWebhooks", StringComparison.OrdinalIgnoreCase) &&
            string.Equals(request.Query["Type"], "PartnerCenter", StringComparison.OrdinalIgnoreCase);
        if (!partnerCallback || !string.Equals(Environment.GetEnvironmentVariable("GDAP_ACCEPTOR_ENABLED"), "true", StringComparison.OrdinalIgnoreCase))
        {
            await next(context);
            return;
        }
        if (!HttpMethods.IsPost(request.Method)) { context.Response.StatusCode = 405; return; }
        if (request.Headers.ContentEncoding.Count > 0 && request.Headers.ContentEncoding != "identity")
        { context.Response.StatusCode = 415; return; }
        if (request.ContentLength > MaximumBytes) { context.Response.StatusCode = 413; return; }
        if (!await Slots.WaitAsync(0, context.RequestAborted)) { context.Response.StatusCode = 503; return; }
        var original = request.Body;
        string? handle = null;
        try
        {
            using var buffer = new MemoryStream();
            using var readTimeout = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
            readTimeout.CancelAfter(TimeSpan.FromSeconds(15));
            var chunk = new byte[8192];
            int read;
            while ((read = await original.ReadAsync(chunk.AsMemory(0, Math.Min(chunk.Length,
                MaximumBytes + 1 - (int)buffer.Length)), readTimeout.Token)) != 0)
            {
                buffer.Write(chunk, 0, read);
                if (buffer.Length > MaximumBytes) { context.Response.StatusCode = 413; return; }
            }
            if (buffer.Length == 0) { context.Response.StatusCode = 400; return; }
            handle = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
            if (!Bodies.TryAdd(handle, buffer.ToArray())) throw new InvalidOperationException("Duplicate internal request handle.");
            request.Headers[HeaderName] = handle;
            buffer.Position = 0;
            request.Body = buffer;
            await next(context);
        }
        catch (OperationCanceledException) when (!context.RequestAborted.IsCancellationRequested && handle is null)
        {
            context.Response.StatusCode = 408;
        }
        finally
        {
            request.Body = original;
            request.Headers.Remove(HeaderName);
            if (handle is not null) Bodies.TryRemove(handle, out _);
            Slots.Release();
        }
    }
}

public sealed class WebhookHostingStartup : IHostingStartup
{
    public void Configure(IWebHostBuilder builder) => builder.ConfigureServices(services =>
        services.AddTransient<IStartupFilter, WebhookStartupFilter>());
}

public sealed class WebhookStartupFilter : IStartupFilter
{
    public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next) => app =>
    {
        app.Use((context, continuation) => WebhookBodyBridge.Capture(context, continuation));
        WebhookBodyBridge.MarkInstalled();
        next(app);
    };
}
