#!/bin/bash
set -eux

# umbrelOS is headless: allow the umbrel console user to manage WiFi
# without a graphical PolicyKit agent.
install -d /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/50-umbrel-networkmanager.rules <<'EOF'
// Allow umbrel user to manage NetworkManager (WiFi) without a seat/session agent.
polkit.addRule(function(action, subject) {
    if (subject.user == "umbrel" && (
        action.id.indexOf("org.freedesktop.NetworkManager.") == 0 ||
        action.id.indexOf("org.freedesktop.network1.") == 0)) {
        return polkit.Result.YES;
    }
});
EOF

# Also useful for nmcli as rootless wheel members on the tablet.
usermod -aG netdev umbrel 2>/dev/null || true
