/// Above this width, screens with a wide-layout precedent show a 3-pane
/// desktop-style workspace instead of the narrow/mobile push flow.
///
/// This is a width check, not a platform check — it triggers on desktop
/// OSes and equally on large/tablet Android or iOS screens in landscape or
/// split-screen. Narrower windows on any platform keep the mobile flow.
const double kWideLayoutBreakpoint = 900;
