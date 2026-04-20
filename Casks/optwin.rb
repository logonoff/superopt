cask "optwin" do
  version "0.2.0"
  sha256 "271bf706020580b2b91f3f0e6b74141e46be01de861199e37c09eb584ea30458"

  url "https://github.com/logonoff/opt-win/releases/download/#{version}/OptWin.zip"
  name "OptWin"
  desc "macOS menu bar app that repurposes the Option key with GNOME-style features"
  homepage "https://github.com/logonoff/opt-win"

  depends_on macos: ">= :tahoe"

  app "OptWin.app"

  zap trash: [
    "~/Library/Preferences/co.logonoff.optwin.plist",
  ]
end
