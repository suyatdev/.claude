// Loader shim — NOT part of the Nocturne export. Added when the UI was vendored.
//
// The page hard-codes <script src="tracker-data.js">, which treko/store.py
// generates. Before the first analysis that file does not exist, and a missing
// file:// script fails silently, so the page would sit on its "No analysis data
// found" empty state with a complete sample sitting right beside it.
//
// This runs immediately after the generated file and pulls in the vendored sample
// only when nothing set window.TRACKER_DATA. Generated data therefore always wins
// when it is present; the sample never shadows a real run.
//
// document.write is deliberate: the shim is parser-inserted, so the write lands
// during parsing and the sample is guaranteed to be in place before the design-system
// runtime boots the app on DOMContentLoaded. An async/injected load would race that boot.
(function () {
  if (window.TRACKER_DATA) return;

  window.TRACKER_DATA_SOURCE = 'sample';
  document.write('<script src="tracker-data.sample.js"><\/script>');
})();
