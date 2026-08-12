// Point the dc-runtime's three CDN scripts at the copies vendored under vendor/.
//
// Load order is the whole design: this file must run BEFORE support.js, which is the page's
// first script. support.js reads window.__resources at the moment it needs a script
// (`grep -n '__resources' task-tracker/support.js`), so a map defined after it has already
// fetched is a map that does nothing — and it fails *open*, quietly going back to unpkg.com
// rather than erroring. It also has to be a served file rather than an inline <script>: the
// server's CSP carries no nonce and no 'unsafe-inline' in script-src, so an inline block is
// refused by the very policy that protects the token.
//
// support.js is vendored third-party code and is deliberately NOT patched. This map is the
// hook it already exposes; when a key hits, cdnScriptFor returns {src} with no integrity,
// which is correct — SRI covers a fetch this page no longer makes. The bytes under vendor/
// were verified against support.js's own sha384 constants at vendor time instead.
//
// Keys must match those CDN URLs byte for byte; re-check with:
//   grep -n 'REACT_URL\|REACT_DOM_URL\|BABEL_URL' task-tracker/support.js
//
// Values are document-relative on purpose. A root-relative "/vendor/..." would work when
// served but break criterion 8's file:// path, where it resolves against the filesystem root.
window.__resources = {
  "https://unpkg.com/react@18.3.1/umd/react.production.min.js": "vendor/react.production.min.js",
  "https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js": "vendor/react-dom.production.min.js",
  "https://unpkg.com/@babel/standalone@7.29.0/babel.min.js": "vendor/babel.min.js"
};
