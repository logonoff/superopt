cask "optwin" do
  version "0.0.5"
  sha256 "828cdd559d1f08273b0deeab424c4c21ed9bbe14757b89820c5f6401b0bf8c96"

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
