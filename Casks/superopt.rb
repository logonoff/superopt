cask "superopt" do
  version "0.4.7"
  sha256 "cebb058cd1a118b1aa37caa2f6983b152d8921eaf4cfda19bea9eb84d528f0f3"

  url "https://github.com/logonoff/superopt/releases/download/#{version}/SuperOpt.zip",
      verified: "github.com/logonoff/superopt/"
  name "SuperOpt"
  desc "Muscle memory polyfill for GNOME users"
  homepage "https://logonoff.co/superopt"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "SuperOpt.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-rd", "com.apple.quarantine", "#{appdir}/SuperOpt.app"]
  end

  zap trash: "~/Library/Preferences/co.logonoff.superopt.plist"

  caveats <<~EOS
    #{token} requires Accessibility and Input Monitoring permissions.
    Grant both in System Settings > Privacy & Security after first launch.

    #{token} is not signed with an Apple Developer ID.
    The quarantine flag is removed automatically during install.
    If macOS still says the app is damaged, run:
      xattr -rd com.apple.quarantine #{appdir}/SuperOpt.app
  EOS
end
