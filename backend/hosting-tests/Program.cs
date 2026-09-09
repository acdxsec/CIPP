using System.Security.Cryptography;
using System.Text;
using Cipp.Gdap.Hosting;
using Microsoft.AspNetCore.Http;

static void Check(bool valid, string message) { if (!valid) throw new Exception(message); }
static DefaultHttpContext Request(byte[] bytes, string path = "/api/PublicWebhooks")
{
    var context = new DefaultHttpContext();
    context.Request.Method = "POST";
    context.Request.Path = path;
    context.Request.QueryString = new("?Type=PartnerCenter");
    context.Request.Body = new MemoryStream(bytes);
    context.Request.Headers[WebhookBodyBridge.HeaderName] = "forged";
    return context;
}

Environment.SetEnvironmentVariable("GDAP_ACCEPTOR_ENABLED", "true");
var payload = Encoding.UTF8.GetBytes("{\r\n  \"EventName\": \"test-created\", \"unicode\": \"☃\"\r\n}\n");
using var rsa = RSA.Create(2048);
var signature = rsa.SignData(payload, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
var context = Request(payload);
var original = context.Request.Body;
string? used = null;
await WebhookBodyBridge.Capture(context, async request =>
{
    used = request.Request.Headers[WebhookBodyBridge.HeaderName];
    Check(used != "forged", "Client handle was trusted");
    var raw = WebhookBodyBridge.Take(used)!;
    Check(raw.SequenceEqual(payload), "Signed bytes changed");
    Check(rsa.VerifyData(raw, signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1), "Signature no longer matches");
    Check(WebhookBodyBridge.Take(used) is null, "Handle replay succeeded");
    using var body = new MemoryStream();
    await request.Request.Body.CopyToAsync(body);
    Check(body.ToArray().SequenceEqual(payload), "Downstream body changed");
});
Check(context.Request.Body == original, "Request stream was not restored");
Check(!context.Request.Headers.ContainsKey(WebhookBodyBridge.HeaderName), "Handle survived request");
Check(WebhookBodyBridge.Take("forged") is null, "Unknown handle resolved");
try
{
    await WebhookBodyBridge.Capture(Request(payload), request =>
    {
        used = request.Request.Headers[WebhookBodyBridge.HeaderName];
        throw new InvalidOperationException("Synthetic downstream failure");
    });
}
catch (InvalidOperationException) { }
Check(WebhookBodyBridge.Take(used) is null, "Failed request retained raw body");
foreach (var size in new[] { 0, WebhookBodyBridge.MaximumBytes + 1 })
{
    var rejected = Request(new byte[size]);
    await WebhookBodyBridge.Capture(rejected, _ => throw new Exception("Invalid body reached downstream"));
    Check(rejected.Response.StatusCode == (size == 0 ? 400 : 413), "Invalid size not rejected");
}
var other = Request(payload, "/api/Unrelated");
await WebhookBodyBridge.Capture(other, request =>
{
    Check(!request.Request.Headers.ContainsKey(WebhookBodyBridge.HeaderName), "Unrelated request kept forged handle");
    return Task.CompletedTask;
});
Environment.SetEnvironmentVariable("GDAP_ACCEPTOR_ENABLED", "false");
await WebhookBodyBridge.Capture(Request(payload), request =>
{
    Check(!request.Request.Headers.ContainsKey(WebhookBodyBridge.HeaderName), "Disabled capture retained forged handle");
    return Task.CompletedTask;
});
Environment.SetEnvironmentVariable("GDAP_ACCEPTOR_ENABLED", "true");
foreach (var mode in new[] { "method", "encoding", "length" })
{
    var rejected = Request(payload);
    if (mode == "method") rejected.Request.Method = "GET";
    if (mode == "encoding") rejected.Request.Headers.ContentEncoding = "gzip";
    if (mode == "length") rejected.Request.ContentLength = WebhookBodyBridge.MaximumBytes + 1;
    await WebhookBodyBridge.Capture(rejected, _ => throw new Exception("Invalid request reached downstream"));
    Check(rejected.Response.StatusCode == (mode == "method" ? 405 : mode == "encoding" ? 415 : 413), "Invalid request was accepted");
}
var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
var active = new List<Task>();
for (var index = 0; index < 32; index++)
    active.Add(WebhookBodyBridge.Capture(Request(payload), _ => release.Task));
var overflow = Request(payload);
await WebhookBodyBridge.Capture(overflow, _ => throw new Exception("Capture concurrency was unbounded"));
Check(overflow.Response.StatusCode == 503, "Busy capture was not rejected");
release.SetResult();
await Task.WhenAll(active);
var recovered = false;
await WebhookBodyBridge.Capture(Request(payload), _ => { recovered = true; return Task.CompletedTask; });
Check(recovered, "Capture slots leaked after completion");
Console.WriteLine("PASS: exact signed bytes, one-use handles, spoof rejection, bounded buffering, cleanup and disabled/unrelated passthrough");
