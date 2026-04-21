cask "superopt" do
  version "0.3.0"
  sha256 "28548a88d51828ccafb3e37f585b9bec85d436105633a4671f9894e953053293"

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
