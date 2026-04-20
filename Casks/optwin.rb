cask "optwin" do
  version "0.1.2"
  sha256 "95b4fa1b67ec75d39f9ef46047afecae6c9f8d1088eb79d65de3d1abcb6fe27f"

  url "https://github.com/logonoff/opt-win/releases/download/#{version}/OptWin.zip"
  name "OptWin"
  desc "macOS menu bar app that repurposes the Option key with GNOME-style features"
  homepage "https://github.com/logonoff/opt-win"

  depends_on macos: ">= :tahoe"

  app "OptWin.app"

  zap trash: [
    "~/Library/Preferences/com.local.optwin.plist",
  ]
end
