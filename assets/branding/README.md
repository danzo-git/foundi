# Foundi branding

`foundi-logo-source.png` is the unmodified logo supplied by the user.
`foundi-mark.png` preserves that artwork, with its outer white presentation
margin trimmed and a square canvas, for in-app display and native icons.

Regenerate the platform icon sizes from the repository root:

```powershell
node tool/prepare_branding.cjs
```

The script uses the project's existing Sharp dependency in `functions`.
It does not generate or redraw the artwork.

`google-g.png` is the official Google sign-in logo downloaded from
[Google Identity](https://developers.google.com/static/identity/images/g-logo.png).
The sign-in control uses its original colours on a white, bounded button,
with a tooltip and accessible action label. See
[Google's branding guidance](https://developers.google.com/identity/branding-guidelines).
