cask "superopt" do
  version "0.3.3"
  sha256 "1bc6f3b40e2e064a69c0f5d34a722f003be062d74d77f64740afc2da64a0f796"

  url "https://github.com/logonoff/superopt/releases/download/#{version}/SuperOpt.zip"
  name "SuperOpt"
  desc "macOS menu bar app that repurposes the Option key with GNOME-style features"
  homepage "https://logonoff.co/superopt"

  depends_on macos: ">= :tahoe"

  app "SuperOpt.app"

  zap trash: [
    "~/Library/Preferences/co.logonoff.superopt.plist",
  ]
end
