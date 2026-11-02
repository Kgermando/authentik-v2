# Signature MSIX

Emplacement unique des clés (build) :

| Fichier | Rôle |
| --- | --- |
| `authentik_codesign.pfx` | Clé privée (gitignored) |
| `authentik_codesign.cer` | Certificat public (export, build) |

Création : `.\tool\signing\create_cert.ps1`  
Build MSIX : `Build-MSIX.bat` ou `.\tool\build_msix.ps1`

Le dossier **`tool\dist\`** reçoit à chaque build :

- `Authentik_v2.msix`
- `Authentik_v2_Publisher.cer` (copie du `.cer` de signature)
- `Install.bat` + `windows_install.ps1`

Installation sur un poste : `Install-Authentik.bat` (racine) ou `tool\dist\Install.bat`.

Mot de passe PFX : `AUTHENTIK_MSIX_CERT_PASSWORD` ou `tool/signing/.cert_password`.
