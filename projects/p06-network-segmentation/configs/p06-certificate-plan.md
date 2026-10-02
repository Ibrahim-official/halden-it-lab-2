# P6 certificate plan (PKI material and what may be committed)

**What this is:** the rules for certificate material used by P6 (802.1X Wi-Fi, NPS server
certificate, CA trust). It exists so nobody has to guess later which file is safe to commit.

**Where it applies:** CA01 (the enterprise CA), the NPS server (FS01), domain computers (via
autoenrollment) and LNX01 (the `eapol_test` client).

## 1. The PKI in words

```
Halden Root CA (CA01)  ---issues--->  Halden-WiFi-Computer   -> domain workstations
                       ---issues--->  Halden-RAS-IAS-Server  -> FS01 (NPS / RADIUS)
                       ---issues--->  device certificates    -> LNX01, servers, VPN clients
```

- **CA01** hosts an **Enterprise Root CA** for the lab. In production this would be an offline root
  plus an issuing CA, and the CA itself is Tier 0. That gap is documented, not hidden.
- A **root CA certificate is public.** It contains no private key; it is safe to commit and is what
  clients use to *trust* the CA.
- Everything with a `-----BEGIN PRIVATE KEY-----` (or `PRIVATE KEY`) header, a `.pfx`/`.p12`, or a
  `-----BEGIN OpenVPN Static key` header is **secret**. It is generated on the device, backed up to
  the owner's password manager, and never committed.

## 2. What may be committed, and where

| Material | Contains a private key? | Commit? | Location if committed |
|---|---|---|---|
| Halden Root CA certificate (public, `.crt`/`.pem`) | No | Yes | `configs/public-certs/halden-root-ca.pem` |
| Issued computer/server client certificate (public part) | No | Yes, if sanitised | `configs/public-certs/` |
| Certificate private key (`*.key`, `*.pem` with a key block) | Yes | **Never** | vault only; `.gitignore` blocks it |
| `.pfx` / `.p12` export bundle | Yes | **Never** | vault only; `.gitignore` blocks it |
| NPS / RADIUS shared secret | n/a | **Never** | vault only |
| WireGuard / OpenVPN private keys and `tls-crypt` static key | Yes | **Never** | vault only |
| OPNsense `config.xml` (raw) | Yes, many | **Never raw** | export locally, publish a sanitised summary only |

The repository's `.gitignore` already blocks `*.key`, `*.pem` (except under `public-certs/`), `*.pfx`
and `*.p12`. This document records *why*, so the rule survives a future contributor.

## 3. Certificate templates (designed)

| Template | Based on | Subject | Validity | EKU | Who may enrol |
|---|---|---|---|---|---|
| `Halden-WiFi-Computer` | Computer | built from AD (DNS name) | 2 years | Client Authentication | Domain Computers (autoenroll) |
| `Halden-RAS-IAS-Server` | RAS and IAS Server | built from AD | 2 years | Server Authentication, Client Authentication | FS01 only |
| `Halden-VPN-Client` (optional, per-user) | User | built from AD | 1 year | Client Authentication | `G_VPN_Users` |

Autoenrollment is delivered by the GPO `WKS - Cert Autoenrollment - v1` (see
[`../scripts/07-Install-EnterpriseCa.ps1`](../scripts/07-Install-EnterpriseCa.ps1)). Verify on a
client with `certutil -store My`; a computer with no certificate cannot join `Halden-Corp`.

## 4. Status

Designed, not built. Certificates do not exist until CA01 is deployed in the lab phase; nothing in
this folder is presented as an issued artefact.
