// <<< tracker-command-handler: node-loadable slice begins >>>
// Task 10 / criterion 15. test_ui_commands.py cuts this region out of this file verbatim
// and loads it in node, so it must stay dependency-free: no React, no DCLogic, no
// document, no window. It cannot live in its own .js file (the servable set is a closed
// manifest pinned in both server.py and the spec half, so a new row is a spec change and
// reopens criterion 13) and it cannot be an inline <script> (the CSP carries no
// 'unsafe-inline' for scripts). `fetch` arrives as an argument for the same reason: one
// row is driven by genuinely stopping the server, the rest by a stub.
var TRACKER_COMMAND_IDS=['clear','handoff','reanalyze'];
// The page's mirror of server.py's LOCAL_COMMANDS / SEND_COMMANDS. A duplication, so
// test_ui_commands.py reads both sides and asserts they are the same partition.
var TRACKER_LOCAL_IDS=['reanalyze'];
var TRACKER_SEND_IDS=['clear','handoff'];
var TRACKER_COPY_TEXT={
  clear:'/clear',
  handoff:'/handoff',
  // No keystroke equivalent exists — reanalyze is server-side. This is the manual command
  // that reproduces the analysis half; the store write is the server's own.
  reanalyze:'python3 treko/analyze.py .'};
var TRACKER_MESSAGES={
  success:'Sent.',
  stale_token:"This page's token is stale — reload to reconnect.",
  session_ended:'The session this page controls has ended.',
  // Never "sent", never "failed": a 502 may mean the keystroke landed, and resolving it
  // either way asserts something the server explicitly does not know.
  send_unknown:'The command may or may not have reached the session — check it before retrying.',
  analysis_failed:'Analysis failed; the data below is from the previous run.',
  page_bug:'Unexpected error.',
  unexpected:'Unexpected error.',
  server_gone:'The control server is no longer running.',
  no_channel:'No control channel — /clear and /handoff cannot be sent from here. Copy them instead.'};
// Every row of §Design 3's failure table, by `error` code. There is deliberately no
// default branch: a code with no entry here resolves to `unexpected` below, which is a
// decision, where a fall-through would be a button that does nothing.
var TRACKER_ERROR_OUTCOMES={
  forbidden:'stale_token',
  unresolved_surface:'session_ended',
  send_failed:'send_unknown',
  reanalyze_failed:'analysis_failed',
  malformed:'page_bug',
  too_large:'page_bug',
  unsupported_media_type:'page_bug',
  no_channel:'no_channel'};
// `409` and a dead socket are the two states where a retry cannot work, so the button
// stops being offered and the copyable text takes its place. `no_channel` is deliberately
// absent: terminality withdraws every button, Re-analyze included, and Re-analyze is the
// one command a channel-less server still runs.
var TRACKER_TERMINAL_OUTCOMES={session_ended:true,server_gone:true};

// The ids offered as buttons. `channelOk` arrives as a strict `=== 'ok'` comparison, so
// every other value the channel meta could carry resolves to the local-only set.
function trackerLiveIds(hasToken,channelOk){
  return !hasToken?[]:(channelOk?TRACKER_COMMAND_IDS:TRACKER_LOCAL_IDS);
}
// Keyed by the closed channel enum (channel.py's Reason). The meta's text is never shown:
// an unrecognised token falls to the fixed string, the same rule error codes follow.
var TRACKER_CHANNEL_REASONS={
  surface_unset:'Launched outside cmux, so there is no session to type into.',
  probe_timeout:'cmux did not answer within 5s — the control channel may be wedged.',
  probe_failed:'This surface is not a terminal; an agent-session surface has no control channel.',
  cmux_unrunnable:'cmux could not be run on this host.'};
var TRACKER_CHANNEL_REASON_FALLBACK='No control channel.';
function trackerChannelReason(token){
  return Object.prototype.hasOwnProperty.call(TRACKER_CHANNEL_REASONS,token)
    ?TRACKER_CHANNEL_REASONS[token]:TRACKER_CHANNEL_REASON_FALLBACK;
}

function trackerIdleView(analyzedAt){
  return {analyzedAt:analyzedAt,outcome:'idle',message:'',
          offersButton:true,offersCopyText:false,shouldReload:false};
}
function trackerViewFor(view,outcome,id){
  var terminal=TRACKER_TERMINAL_OUTCOMES[outcome]===true;
  return {
    // Carried forward untouched. The stale timestamp is the only on-screen signal that
    // the data is old; only a reload after a successful reanalyze may move it.
    analyzedAt:view.analyzedAt,
    outcome:outcome,
    message:TRACKER_MESSAGES[outcome],
    offersButton:!terminal,
    offersCopyText:terminal,
    shouldReload:outcome==='success'&&id==='reanalyze'};
}
function trackerOutcomeForBody(body){
  var code=body&&typeof body.error==='string'?body.error:null;
  // hasOwnProperty, not a bare lookup: an `error` of "constructor" or "toString" would
  // otherwise inherit a truthy value off the prototype and pick someone else's row.
  if(code!==null&&Object.prototype.hasOwnProperty.call(TRACKER_ERROR_OUTCOMES,code))
    return TRACKER_ERROR_OUTCOMES[code];
  // A code this page has never heard of maps to its own fixed string — never to the
  // server's bytes. The server refuses to echo request content; rendering its text here
  // would reintroduce that gadget from the other side.
  return 'unexpected';
}
function trackerApplyCommand(view,opts){
  return opts.fetchImpl(opts.url,{
    method:'POST',
    headers:{'Content-Type':'application/json','X-Tracker-Token':opts.token},
    body:JSON.stringify({id:opts.id})
  }).then(function(response){
    return response.json().then(function(body){
      if(response.status===200)
        return trackerViewFor(view,body&&body.ok===true?'success':'unexpected',opts.id);
      return trackerViewFor(view,trackerOutcomeForBody(body),opts.id);
    },function(){
      // A body that is not JSON is still an outcome. Silence is never one.
      return trackerViewFor(view,'unexpected',opts.id);
    });
  },function(){
    // fetch rejected: there was no response at all, so there is no code to map. The
    // server exiting under an open page is the normal end of a session, not an edge case.
    return trackerViewFor(view,'server_gone',opts.id);
  });
}
if(typeof module!=='undefined'&&module.exports){
  module.exports={IDS:TRACKER_COMMAND_IDS,COPY_TEXT:TRACKER_COPY_TEXT,
                  MESSAGES:TRACKER_MESSAGES,idleView:trackerIdleView,
                  applyCommand:trackerApplyCommand,
                  LOCAL_IDS:TRACKER_LOCAL_IDS,SEND_IDS:TRACKER_SEND_IDS,
                  liveIds:trackerLiveIds,
                  channelReason:trackerChannelReason,
                  CHANNEL_REASONS:TRACKER_CHANNEL_REASONS};
}
// <<< tracker-command-handler: node-loadable slice ends >>>
