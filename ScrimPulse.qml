import QtQuick
import Qt5Compat.GraphicalEffects

// The Scrim pulse: a glow behind a lyric plate or a card, driven by the
// mid/high envelope. Always on whenever the organ is live, whatever Scene is
// running — it is the one place the audio reaches the lyrics themselves.
//
// It never touches the Scrim's black/white choice, which is a contrast
// guarantee and must not move with the beat. Only this glow and the plate's
// scale animate, and `amount` arrives already slew-limited by the analyzer.
RectangularGlow {
  id: pulse

  property real amount: 0
  property real plateRadius: 0

  glowRadius: 5 + 20 * amount
  spread: 0.08
  cornerRadius: plateRadius + glowRadius
  opacity: 0.34 * amount
  visible: amount > 0.01
}
