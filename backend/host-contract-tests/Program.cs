using System.Collections;
using System.Management.Automation;
using System.Reflection;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Cipp.Gdap.Hosting;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Hosting;

// Runs in the pinned image, with its unmodified Craft marshaler and PowerShell.
// The synthetic certificate exercises byte/signature plumbing, not PKI trust.
var payload = Encoding.UTF8.GetBytes("{\r\n  \"EventName\": \"test-created\", \"unicode\": \"☃\"\r\n}\n");
using var rsa = RSA.Create(2048);
var csr = new CertificateRequest("CN=synthetic-test", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
using var cert = csr.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-1), DateTimeOffset.UtcNow.AddDays(1));
var signature = Convert.ToBase64String(rsa.SignData(payload, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1));
var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseSetting("urls", "http://127.0.0.1:18080");
await using var app = builder.Build();
var craft = Assembly.Load("Craft");
var snapshot = craft.GetType("Craft.Services.PowerShellRunnerService", true)!.GetMethod("SnapshotRequest")!;
app.MapPost("/api/PublicWebhooks", async (HttpContext context) =>
{
    var request = await (Task<Hashtable>)snapshot.Invoke(null, new object[] { context })!;
    using var ps = PowerShell.Create();
    ps.AddScript("""
        param($Request, $Certificate, $Signature)
        $ErrorActionPreference = 'Stop'
        . /checks/Get-CippGdapOriginalWebhookBody.ps1
        . /checks/Test-CippPartnerWebhookSignature.ps1
        $raw = Get-CippGdapOriginalWebhookBody -Request $Request
        if ($raw -isnot [byte[]]) { throw 'Body lost its byte-array type in PowerShell.' }
        Test-CippPartnerWebhookSignature -Content $raw -Signature $Signature -Certificate $Certificate
        """).AddArgument(request).AddArgument(cert).AddArgument(context.Request.Headers["x-test-signature"].ToString());
    var results = ps.Invoke();
    if (ps.HadErrors) throw new Exception(string.Join("; ", ps.Streams.Error));
    return Results.Json(new { valid = results.Count == 1 && results[0].BaseObject is true });
});
await app.StartAsync();
try
{
    if (!WebhookBodyBridge.Installed) throw new Exception("Startup extension did not install.");
    using var client = new HttpClient();
    foreach (var tamper in new[] { false, true })
    {
        var bytes = (byte[])payload.Clone();
        if (tamper) bytes[3] = 9; // JSON still valid; only the signed whitespace changes.
        using var request = new HttpRequestMessage(HttpMethod.Post, "http://127.0.0.1:18080/api/PublicWebhooks?Type=PartnerCenter");
        request.Content = new ByteArrayContent(bytes);
        request.Content.Headers.ContentType = new("application/json");
        request.Headers.Add("x-test-signature", signature);
        request.Headers.Add(WebhookBodyBridge.HeaderName, new string('A', 64));
        using var response = await client.SendAsync(request);
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadAsStringAsync();
        if (body != (tamper ? "{\"valid\":false}" : "{\"valid\":true}")) throw new Exception("HTTP signature contract mismatch.");
    }
    Console.WriteLine("PASS: HTTP startup extension -> pinned Craft marshaller -> PowerShell byte retrieval -> signed/tampered payload verification");
}
finally { await app.StopAsync(); }
