cask "superopt" do
  version "0.3.2"
  sha256 "e1e94e6ea69bd5c6d1d4229312bc6c278cf5c936a1af83eb98b54b08b5510c37"

  url "https://github.com/logonoff/superopt/releases/download/#{version}/SuperOpt.zip"
  name "SuperOpt"
  desc "macOS menu bar app that repurposes the Option key with GNOME-style features"
  homepage "https://github.com/logonoff/superopt"

  depends_on macos: ">= :tahoe"

  app "SuperOpt.app"

  zap trash: [
    "~/Library/Preferences/co.logonoff.superopt.plist",
  ]
end
