## Login and password security

The superadmin can configure login and password protection from **Settings**:

- Failed attempts allowed, the measurement window, and temporary lockout duration
- Minimum password length from 8 to 128 characters
- Basic, standard, or strong password composition requirements
- Privacy-preserving compromised-password screening through the free Pwned Passwords range service

Regular users and Web Admins must satisfy the configured password policy when their accounts are created or their passwords are changed. The strength indicator provides immediate guidance, while the server remains authoritative. Strong mode requires uppercase and lowercase letters, a number, and a symbol. The superadmin is exempt from password policy and breach screening, but login rate limiting protects every account.

Signed-in users can change their own password from **Change password** in the navigation menu. Web Admins and the superadmin can mark any non-superadmin account as requiring a password change from **Users**. A marked user is sent to the password-change screen and cannot use other application features until they provide their current password and choose a compliant replacement. Existing passwords remain grandfathered unless an administrator marks the account.

Only the first five characters of a password's SHA-1 hash are sent for compromised-password screening; the complete password and hash remain on the server. If the screening service is temporarily unavailable, the password is accepted and the administrator receives an informational notice.

By default, rate limiting uses the direct client address and ignores forwarded headers. When a trusted reverse proxy sits in front of the application, set `TRUSTED_PROXY_CIDRS` in the deployed `.env` to a comma-separated list containing only that proxy's IP addresses or CIDR ranges. For example:

```env
TRUSTED_PROXY_CIDRS=127.0.0.1/32,::1/128
```

Forwarded client addresses are honored only when the immediate connection comes from one of those trusted networks.