import { BridgeComponent } from "@hotwired/hotwire-native-bridge"

// Hotwire Native bridge component "device".
// When the pairing page renders a freshly issued device token, this hands it to
// the native Android layer so the background SMS service can authenticate.
// In a plain web browser (no native bridge) `send` is a safe no-op.
export default class extends BridgeComponent {
  static component = "device"
  static values = { token: String, name: String }

  connect() {
    super.connect()
    if (this.tokenValue) {
      this.send("connect", { token: this.tokenValue, name: this.nameValue }, () => {
        // native acknowledged storing the token
      })
    }
  }
}
